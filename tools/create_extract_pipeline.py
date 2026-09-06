"""
Build and run the EXTRACT pipeline: PostgreSQL -> ADLS Gen2 delimited text.

The classroom does this with the Synapse Copy Data wizard. This is the same
copy activity defined as code, so the extract is reproducible without twenty
minutes of clicking - and so the four files land at exactly the paths the LOAD
scripts expect.

Creates one linked service per side, a source and sink dataset per table, and a
pipeline with four copy activities that run in parallel. Then optionally
triggers it and waits.

    az login
    export PGPASSWORD='...'                 # the Postgres admin password
    python tools/create_extract_pipeline.py \
        --workspace   divvysyn260906 \
        --resource-group ODL-DataEng-260906 \
        --pg-server   divvypg260906 \
        --pg-user     divvyadmin \
        --storage     divvydls260906 \
        --filesystem  divvyfs260906 \
        --run

Two things this encodes that cost real time to discover:

1. `quoteAllText: false` is rejected outright - "QuoteAllText cannot set to
   false for Copy activity currently". Omitting the setting gives the wanted
   behaviour anyway: quote only values that need it.

2. The sink authenticates with the storage ACCOUNT KEY, not the workspace
   managed identity. A copy activity runs as the workspace MI, and the MI has
   no access to the lake unless someone grants it Storage Blob Data
   Contributor. In the Udacity lab nobody can - Microsoft.Authorization is
   blocked for the lab user, so the role assignment fails for you, for the
   portal, and for a workspace created through the Copy Data wizard alike. The
   failure surfaces as AuthorizationPermissionMismatch on the first write.
   Account-key auth is a documented alternative and sidesteps it. The key is
   read from Azure at deploy time and never written to this repo.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

TABLES = ["rider", "payment", "station", "trip"]

parser = argparse.ArgumentParser()
parser.add_argument("--workspace", required=True)
parser.add_argument("--resource-group", required=True)
parser.add_argument("--pg-server", required=True, help="server name, not FQDN")
parser.add_argument("--pg-user", required=True)
parser.add_argument("--pg-database", default="udacityproject")
parser.add_argument("--storage", required=True)
parser.add_argument("--filesystem", required=True)
parser.add_argument("--extract-folder", default="divvy")
parser.add_argument("--pipeline-name", default="ExtractDivvyToLake")
parser.add_argument("--run", action="store_true", help="trigger it and wait")
args = parser.parse_args()

PGPASSWORD = os.environ.get("PGPASSWORD")
if not PGPASSWORD:
    sys.exit("Set PGPASSWORD to the Postgres admin password first.")

SHELL = os.name == "nt"


def az(cmd, capture=True):
    out = subprocess.run(["az"] + cmd, shell=SHELL,
                         capture_output=capture, text=True)
    if out.returncode != 0:
        sys.exit("az {0} failed:\n{1}".format(" ".join(cmd[:3]),
                                              (out.stderr or "").strip()))
    return (out.stdout or "").strip()


def deploy(kind, name, body, workdir):
    path = os.path.join(workdir, "{0}_{1}.json".format(kind, name))
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(body, fh, indent=2)
    az(["synapse", kind, "create", "--workspace-name", args.workspace,
        "--name", name, "--file", "@" + path, "-o", "none"])
    print("  {0:14s} {1}".format(kind, name))


workdir = tempfile.mkdtemp(prefix="divvy_adf_")
fqdn = "{0}.postgres.database.azure.com".format(args.pg_server)

print("Reading the storage account key (not stored in this repo)")
key = az(["storage", "account", "keys", "list", "-g", args.resource_group,
          "-n", args.storage, "--query", "[0].value", "-o", "tsv"])

print("Deploying linked services")
deploy("linked-service", "DivvyPostgres", {
    "name": "DivvyPostgres",
    "properties": {
        "type": "AzurePostgreSql",
        "typeProperties": {"connectionString": {
            "type": "SecureString",
            "value": ("Server={0};Database={1};Port=5432;UID={2};Password={3};"
                      "SSLMode=Require;Timeout=600;CommandTimeout=3600").format(
                          fqdn, args.pg_database, args.pg_user, PGPASSWORD)}}}},
    workdir)

deploy("linked-service", "DivvyLakeKey", {
    "name": "DivvyLakeKey",
    "properties": {
        "type": "AzureBlobFS",
        "typeProperties": {
            "url": "https://{0}.dfs.core.windows.net".format(args.storage),
            "accountKey": {"type": "SecureString", "value": key}}}},
    workdir)

print("Deploying datasets")
for t in TABLES:
    deploy("dataset", "src_" + t, {
        "name": "src_" + t,
        "properties": {
            "type": "AzurePostgreSqlTable",
            "linkedServiceName": {"referenceName": "DivvyPostgres",
                                  "type": "LinkedServiceReference"},
            "typeProperties": {"schema": "public", "table": t}}}, workdir)

    deploy("dataset", "sink_" + t, {
        "name": "sink_" + t,
        "properties": {
            "type": "DelimitedText",
            "linkedServiceName": {"referenceName": "DivvyLakeKey",
                                  "type": "LinkedServiceReference"},
            "typeProperties": {
                "location": {"type": "AzureBlobFSLocation",
                             "fileSystem": args.filesystem,
                             "folderPath": args.extract_folder,
                             "fileName": "public.{0}.txt".format(t)},
                "columnDelimiter": ",", "escapeChar": "\\", "quoteChar": "\"",
                "firstRowAsHeader": False}}}, workdir)

print("Deploying pipeline")
deploy("pipeline", args.pipeline_name, {
    "name": args.pipeline_name,
    "properties": {
        "description": "One-time EXTRACT: PostgreSQL OLTP -> ADLS Gen2",
        "activities": [{
            "name": "Copy_" + t, "type": "Copy",
            "policy": {"timeout": "0.12:00:00", "retry": 1,
                       "retryIntervalInSeconds": 30},
            "inputs": [{"referenceName": "src_" + t, "type": "DatasetReference"}],
            "outputs": [{"referenceName": "sink_" + t, "type": "DatasetReference"}],
            "typeProperties": {
                "source": {"type": "AzurePostgreSqlSource",
                           "query": "SELECT * FROM public.{0}".format(t)},
                "sink": {"type": "DelimitedTextSink",
                         "storeSettings": {"type": "AzureBlobFSWriteSettings"},
                         # No quoteAllText here - see the module docstring.
                         "formatSettings": {"type": "DelimitedTextWriteSettings",
                                            "fileExtension": ".txt"}},
                "enableStaging": False}} for t in TABLES]}}, workdir)

if not args.run:
    print("\nDeployed. Trigger it in Synapse Studio, or re-run with --run.")
    sys.exit(0)

print("\nTriggering {0}".format(args.pipeline_name))
run_id = az(["synapse", "pipeline", "create-run", "--workspace-name",
             args.workspace, "--name", args.pipeline_name,
             "--query", "runId", "-o", "tsv"])
print("  run id {0}".format(run_id))

last = None
while True:
    status = az(["synapse", "pipeline-run", "show", "--workspace-name",
                 args.workspace, "--run-id", run_id, "--query", "status",
                 "-o", "tsv"])
    if status != last:
        print("  {0}".format(status))
        last = status
    if status in ("Succeeded", "Failed", "Cancelled"):
        break
    time.sleep(20)

if status != "Succeeded":
    message = az(["synapse", "pipeline-run", "show", "--workspace-name",
                  args.workspace, "--run-id", run_id, "--query", "message",
                  "-o", "tsv"])
    sys.exit("Pipeline {0}:\n{1}".format(status, message))

print("\nFiles written to {0}/{1}:".format(args.filesystem, args.extract_folder))
listing = az(["storage", "fs", "file", "list", "-f", args.filesystem,
              "--account-name", args.storage, "--path", args.extract_folder,
              "--auth-mode", "login",
              "--query", "[].{name:name,bytes:contentLength}", "-o", "tsv"])
print(listing)
print("\nThis is the Extract-step screenshot: Synapse Studio > Data > Linked > "
      "{0} > {1} > {2}".format(args.storage, args.filesystem, args.extract_folder))
