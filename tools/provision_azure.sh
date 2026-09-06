#!/usr/bin/env bash
# Provision everything the project needs in the Udacity lab subscription:
# a PostgreSQL flexible server, an ADLS Gen2 storage account, and a Synapse
# workspace - then print the exact configure.py command with the names filled in.
#
# Replaces step 1 of docs/lab_runbook.md. Idempotent: safe to re-run if a step
# fails partway, it skips whatever already exists.
#
# Prerequisites
#   az login                        <- you must do this yourself, in a browser
#   export PGPASSWORD='...'         <- Postgres admin password you choose
#   export SYNAPSE_SQL_PASSWORD='...'
#
# Usage
#   bash tools/provision_azure.sh
#
# Passwords must be 8-128 chars with three of: uppercase, lowercase, digit,
# non-alphanumeric. Do not use '@', '/' or ';' - Azure rejects them here.

set -uo pipefail

SUFFIX="${SUFFIX:-$(date +%y%m%d)}"
PG_SERVER="${PG_SERVER:-divvypg${SUFFIX}}"
STORAGE="${STORAGE:-divvydls${SUFFIX}}"
FILESYSTEM="${FILESYSTEM:-divvyfs${SUFFIX}}"
SYNAPSE="${SYNAPSE:-divvysyn${SUFFIX}}"
PG_ADMIN="${PG_ADMIN:-divvyadmin}"
SYNAPSE_ADMIN="${SYNAPSE_ADMIN:-synadmin}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    WARNING: %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------ preflight -----
command -v az >/dev/null 2>&1 || die "Azure CLI not found on PATH."

say "Checking Azure login"
if ! az account show >/dev/null 2>&1; then
    die "Not logged in. Run:  az login"
fi
az account show --query "{subscription:name, user:user.name}" -o tsv

# az account show reads a cached record and succeeds even when the token behind
# it is dead - which is exactly what a lapsed Udacity lab session leaves behind.
# Probe ARM for real so the failure lands here with a useful message rather than
# three resources into the run.
if ! az group list -o none 2>/dev/null; then
    die "Logged in as a stale session - the lab access pass has expired.
This happens when the Udacity lab session that created the login has ended.

  1. Open the Udacity classroom and start a lab session
  2. az logout
  3. az login
  4. re-run this script

If the browser signs you straight back into the dead session, use:
  az login --tenant f958e84a-92b8-439f-a62d-4f45996b6d07 --use-device-code"
fi

[ -n "${PGPASSWORD:-}" ] || die "Set PGPASSWORD first:  export PGPASSWORD='YourPass1!'"
[ -n "${SYNAPSE_SQL_PASSWORD:-}" ] || die "Set SYNAPSE_SQL_PASSWORD first."

# ------------------------------------------------------- resource group -----
say "Finding the resource group"
RG="${RG:-$(az group list --query "[0].name" -o tsv 2>/dev/null)}"
if [ -z "$RG" ]; then
    die "No resource group found and none given. The Udacity lab normally
pre-creates one. Set it explicitly:  RG=<name> bash tools/provision_azure.sh"
fi
LOCATION="${LOCATION:-$(az group show -n "$RG" --query location -o tsv)}"
echo "    resource group: $RG"
echo "    location:       $LOCATION"

MYIP="$(curl -s -m 10 https://api.ipify.org || echo '')"
[ -n "$MYIP" ] && echo "    your client IP: $MYIP" || warn "Could not detect your public IP; firewall rules for your laptop will be skipped."

# ------------------------------------------------------------- postgres -----
say "Creating PostgreSQL flexible server: $PG_SERVER"
if az postgres flexible-server show -g "$RG" -n "$PG_SERVER" >/dev/null 2>&1; then
    echo "    already exists, skipping"
else
    az postgres flexible-server create \
        --resource-group "$RG" --name "$PG_SERVER" --location "$LOCATION" \
        --admin-user "$PG_ADMIN" --admin-password "$PGPASSWORD" \
        --tier Burstable --sku-name Standard_B1ms --storage-size 32 \
        --version 16 --public-access Enabled --yes -o none \
        || die "PostgreSQL creation failed. If the lab blocks this SKU or region,
re-run with e.g.  LOCATION=eastus bash tools/provision_azure.sh"
fi

# Verify rather than assume. The meaning of --public-access has shifted between
# CLI versions: on 2.82.0, `None` produces publicNetworkAccess=Disabled, which
# silently makes the server unreachable AND rejects every firewall-rule call
# with a message that does not mention why. Check the resulting state and fix it.
say "Verifying public network access"
PNA="$(az postgres flexible-server show -g "$RG" -n "$PG_SERVER" --query network.publicNetworkAccess -o tsv 2>/dev/null)"
echo "    publicNetworkAccess: ${PNA:-unknown}"
if [ "$PNA" = "Disabled" ]; then
    SUBNET="$(az postgres flexible-server show -g "$RG" -n "$PG_SERVER" --query network.delegatedSubnetResourceId -o tsv 2>/dev/null)"
    if [ -n "$SUBNET" ] && [ "$SUBNET" != "None" ]; then
        die "Server is VNet-injected; public access cannot be enabled after creation.
Delete it and re-run:  az postgres flexible-server delete -g $RG -n $PG_SERVER --yes"
    fi
    warn "public access was disabled at creation - enabling it now"
    az postgres flexible-server update -g "$RG" -n "$PG_SERVER" \
        --public-access Enabled -o none 2>/dev/null \
        && echo "    enabled" || die "Could not enable public access on $PG_SERVER"
fi

say "Opening the PostgreSQL firewall"
az postgres flexible-server firewall-rule create -g "$RG" -n "$PG_SERVER" \
    --rule-name AllowAzureServices \
    --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none 2>/dev/null \
    && echo "    Azure services allowed" || warn "could not add the Azure services rule"
if [ -n "$MYIP" ]; then
    az postgres flexible-server firewall-rule create -g "$RG" -n "$PG_SERVER" \
        --rule-name AllowMyLaptop \
        --start-ip-address "$MYIP" --end-ip-address "$MYIP" -o none 2>/dev/null \
        && echo "    your laptop allowed" || warn "could not add your client IP"
fi

# -------------------------------------------------------------- storage -----
say "Creating ADLS Gen2 storage account: $STORAGE"
if az storage account show -g "$RG" -n "$STORAGE" >/dev/null 2>&1; then
    echo "    already exists, skipping"
else
    az storage account create \
        --resource-group "$RG" --name "$STORAGE" --location "$LOCATION" \
        --sku Standard_LRS --kind StorageV2 \
        --enable-hierarchical-namespace true -o none \
        || die "Storage creation failed. The name must be globally unique and
3-24 lowercase alphanumeric characters. Retry with SUFFIX=<something-else>."
fi

say "Creating filesystem: $FILESYSTEM"
az storage fs create -n "$FILESYSTEM" --account-name "$STORAGE" \
    --auth-mode login -o none 2>/dev/null \
    && echo "    created" || echo "    already exists or will be created by Synapse"

# -------------------------------------------------------------- synapse -----
say "Creating Synapse workspace: $SYNAPSE   (this is the slow one, ~5 min)"
if az synapse workspace show -g "$RG" -n "$SYNAPSE" >/dev/null 2>&1; then
    echo "    already exists, skipping"
else
    az synapse workspace create \
        --resource-group "$RG" --name "$SYNAPSE" --location "$LOCATION" \
        --storage-account "$STORAGE" --file-system "$FILESYSTEM" \
        --sql-admin-login-user "$SYNAPSE_ADMIN" \
        --sql-admin-login-password "$SYNAPSE_SQL_PASSWORD" -o none \
        || die "Synapse workspace creation failed."
fi

say "Opening the Synapse firewall"
if [ -n "$MYIP" ]; then
    az synapse workspace firewall-rule create --workspace-name "$SYNAPSE" \
        --resource-group "$RG" --name AllowMyLaptop \
        --start-ip-address "$MYIP" --end-ip-address "$MYIP" -o none 2>/dev/null \
        && echo "    your laptop allowed" || warn "could not add your client IP"
fi
az synapse workspace firewall-rule create --workspace-name "$SYNAPSE" \
    --resource-group "$RG" --name AllowAllWindowsAzureIps \
    --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none 2>/dev/null \
    && echo "    Azure services allowed" || warn "could not add the Azure services rule"

# ------------------------------------------------------------- rbac --------
# CETAS writes to the data lake as the Synapse managed identity, and Synapse
# Studio browses it as you. Both need Storage Blob Data Contributor. Role
# assignment needs elevated rights the lab may not grant, so failures here are
# a warning, not fatal - the portal can do it in two clicks.
say "Granting Storage Blob Data Contributor"
SCOPE="$(az storage account show -g "$RG" -n "$STORAGE" --query id -o tsv)"
MI="$(az synapse workspace show -g "$RG" -n "$SYNAPSE" --query identity.principalId -o tsv 2>/dev/null)"
ME="$(az ad signed-in-user show --query id -o tsv 2>/dev/null)"

for P in "$MI" "$ME"; do
    [ -n "$P" ] || continue
    az role assignment create --assignee-object-id "$P" \
        --assignee-principal-type ServicePrincipal \
        --role "Storage Blob Data Contributor" --scope "$SCOPE" -o none 2>/dev/null \
    || az role assignment create --assignee-object-id "$P" \
        --assignee-principal-type User \
        --role "Storage Blob Data Contributor" --scope "$SCOPE" -o none 2>/dev/null \
    || warn "could not assign the role to $P - do it in the portal:
      Storage account > Access Control (IAM) > Add role assignment >
      Storage Blob Data Contributor > add the Synapse workspace and yourself"
done

# -------------------------------------------------------------- summary ----
PG_FQDN="$(az postgres flexible-server show -g "$RG" -n "$PG_SERVER" --query fullyQualifiedDomainName -o tsv 2>/dev/null)"

cat <<SUMMARY

============================================================================
 PROVISIONED
============================================================================
  resource group     $RG
  location           $LOCATION
  postgres server    $PG_FQDN
  postgres admin     $PG_ADMIN
  storage account    $STORAGE
  filesystem         $FILESYSTEM
  synapse workspace  $SYNAPSE
  synapse studio     https://web.azuresynapse.net?workspace=$SYNAPSE

 NEXT
 ----
 1. Load PostgreSQL (runbook step 2):

      export PGHOST=$PG_FQDN
      export PGUSER=$PG_ADMIN
      python starter/ProjectDataToPostgres.py

 2. EXTRACT in Synapse Studio (runbook step 3) - Copy Data tool, all four
    tables, sink to $FILESYSTEM/divvy, DelimitedText, no header.
    *** Take screenshot 01 here. ***

 3. Stamp the SQL with these names:

      python tools/configure.py \\
          --storage-account $STORAGE \\
          --filesystem $FILESYSTEM \\
          --extract-folder divvy

 4. Continue from runbook step 5.
============================================================================
SUMMARY
