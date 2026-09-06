# Lab runbook

Follow this with the lab clock running. Everything that could be done off the
clock has already been done — the SQL is written, the logic is proven against
the full dataset, the data is on disk.

**Budget:** the session is ~8 hours; this needs about 2. You have 10 lab
attempts total, so the goal is to finish in one.

---

## Before you click "Access Lab"

Do these while nothing is billing:

- [ ] `pip install psycopg2-binary` (already have duckdb/pandas)
- [ ] Confirm `data/` still holds `riders.csv`, `payments.csv`, `stations.csv`,
      `trips.csv` — 4 files, ~500 MB
- [ ] Have this repo open in VS Code
- [ ] Decide your three names now and write them down:
      - storage account, e.g. `mydls20260906`
      - filesystem/container, e.g. `mydlsfs20260906`
      - extract folder, e.g. `divvy`
- [ ] Know that your upload is ~500 MB — if you are on slow upstream, expect
      step 3 to take 20–40 minutes and plan the session around it

---

## 1. Create the Azure resources — ~8 min scripted, ~20 min by hand

### Scripted (preferred)

```bash
az logout && az login
export PGPASSWORD='ChooseAStrongOne1!'
export SYNAPSE_SQL_PASSWORD='AndAnotherOne1!'
bash tools/provision_azure.sh
```

Creates the resource group's Postgres flexible server, ADLS Gen2 storage
account, filesystem and Synapse workspace, opens both firewalls to your client
IP, grants Storage Blob Data Contributor, and prints the exact
`tools/configure.py` command with your names already filled in. It is
idempotent — re-run it if a step fails.

`az login` must be done by you, in a browser, against a **live** lab session. A
login cached from an expired session looks valid to `az account show` but fails
every real call; the script detects that and says so.

If it succeeds, skip to step 2.

### By hand (fallback if the lab blocks a SKU or region)

Sign in to the Azure portal with the `odl_user_...@udacityhol.onmicrosoft.com`
credentials the lab page shows.

**Azure Database for PostgreSQL — Flexible Server**
- Use the resource group the lab pre-created
- Workload: Development / Burstable, smallest tier
- Authentication: PostgreSQL authentication only; note the admin user + password
- Networking: **Public access**, and tick *Allow public access from any Azure
  service*, then **Add current client IP address** — without that firewall rule
  the Python script cannot connect from your laptop

**Azure Synapse Analytics workspace**
- Same resource group
- It creates an ADLS Gen2 storage account and filesystem as part of setup —
  **these are the two names you stamp into the SQL later**, so write them down
- Serverless pool only; do not create a dedicated SQL pool (the lab blocks it,
  and you do not need it)

---

## 2. Load PostgreSQL — ~20–40 min

```bash
set PGHOST=<your-server>.postgres.database.azure.com
set PGUSER=<admin-user>
set PGPASSWORD=<password>
python starter/ProjectDataToPostgres.py
```

Expected output — if any count is off, stop and fix it before moving on:

```
rider       75,000
payment  1,946,607
station        838
trip     4,584,921
```

Most of the wall time is `trips.csv` at 440 MB. Start it and go do something
else.

---

## 3. EXTRACT to Blob Storage — ~15 min

Synapse Studio → **Integrate** → **+** → **Copy Data tool**.

- Task type: **Built-in copy task**, run **once now**
- Source: new connection → **Azure Database for PostgreSQL**
  - server, database `udacityproject`, your admin user + password, SSL required
  - Existing tables → select **all four**: `public.rider`, `public.payment`,
    `public.station`, `public.trip`
- Target: new connection → **Azure Data Lake Storage Gen2** (the one the
  workspace created)
  - Folder path: `divvy` (or whatever you chose as the extract folder)
  - Format: **DelimitedText**, comma, **no header row**
- Run it, and wait for all four activities to go green

> **Screenshot #1 — required by the rubric.** Go to **Data → Linked → your
> storage account → your filesystem → divvy** and screenshot the four files:
> `public.rider.txt`, `public.payment.txt`, `public.station.txt`,
> `public.trip.txt`. Save it into `screenshots/`. Do it now — if the session
> expires you cannot get it back without burning an attempt.

Check the actual filenames the copy tool produced. If they differ from
`public.<table>.txt`, note the real names — you need them in the next step.

---

## 4. Stamp your names into the SQL — 1 min

Back on your laptop, with the names you wrote down:

```bash
python tools/configure.py --storage-account mydls20260906 --filesystem mydlsfs20260906 --extract-folder divvy
```

This writes `sql_configured/`. It exits non-zero if any placeholder is left
unreplaced, so a half-configured script cannot reach the lab.

If step 3 produced different filenames, edit the `LOCATION` line in the four
`sql/load/0[2-5]_*` scripts first, then re-run this.

---

## 5. Create the database — 1 min

Synapse Studio → **Develop** → **+** → **SQL script**.

Set **Connect to: Built-in** and **Use database: master**, then run:

```
sql_configured/load/00_create_database.sql
```

Now click the refresh arrow beside the database dropdown and switch
**Use database** to `divvy`. **Everything after this point runs against
`divvy`, not `master`.** This is the single easiest step to skip and the
error it produces later ("CREATE EXTERNAL TABLE is not supported in master")
is not obviously about this.

---

## 6. LOAD — ~10 min

Still on Built-in / `divvy`. Run in order, checking the row counts each script
prints at the end:

| Script | Expect |
|---|---|
| `01_setup_data_source_and_formats.sql` | one data source, two file formats |
| `02_create_external_table_staging_rider.sql` | 75,000 |
| `03_create_external_table_staging_payment.sql` | 1,946,607 |
| `04_create_external_table_staging_station.sql` | 838 |
| `05_create_external_table_staging_trip.sql` | 4,584,921 |

Also eyeball the `SELECT TOP 100` output in each. If columns look shifted —
an address spilling into the birthday column — the file format's
`STRING_DELIMITER` is not matching how the copy tool quoted the file.

---

## 7. TRANSFORM — ~30 min

Order matters. `fact_trip` and `fact_payment` join to the materialised
`dim_rider`; both extra-credit tables read the two facts.

```
transform/10_cetas_dim_date.sql
transform/11_cetas_dim_time.sql
transform/12_cetas_dim_rider.sql
transform/13_cetas_dim_station.sql
transform/20_cetas_fact_trip.sql
transform/21_cetas_fact_payment.sql
transform/30_cetas_fact_rider_monthly.sql
transform/31_cetas_agg_rider_spend_vs_rides.sql
```

`20_cetas_fact_trip.sql` is the long one — 4.6M rows through a join. Several
minutes is normal.

> **If a CETAS fails with "path already exists":** `DROP EXTERNAL TABLE` leaves
> the files behind. Go to **Data → Linked → your filesystem → warehouse/** and
> delete the folder named in that script's header, then re-run. This is the
> single most common re-run failure.

> **Screenshot #2 — required by the rubric.** Capture a CETAS script with its
> results grid showing rows, and the `warehouse/` folder in the data lake
> showing the output folders. Save into `screenshots/`.

---

## 8. Validate — ~5 min

```
transform/40_validate_star_schema.sql
```

Everything named `defects` must be `0`. The numbers to match against the local
run:

| Check | Expected |
|---|---|
| `dim_rider` | 75,000 |
| `dim_station` | 838 |
| `fact_trip` | 4,584,921 |
| `fact_payment` | 1,946,607 |
| staging money total = fact money total | $19,457,105.25 |
| fact rides = monthly rides = agg rides | 4,584,921 |
| trips with negative duration | 116 |
| trips over 24 hours | 1,277 |

If these match, the warehouse in Azure is the same warehouse you already
validated on your laptop, and you are done building.

---

## 9. Answer the questions — ~10 min

```
analysis/business_questions.sql
```

Compare against [findings.md](findings.md). Screenshot anything you want in the
write-up — particularly the extra-credit result and the ~29,000 members who pay
and never ride.

---

## 10. Publish and clean up

- **Publish all** in Synapse Studio so the scripts are saved to the workspace
- Copy your final scripts out of `sql_configured/` into the submission
- Delete the PostgreSQL server, the Synapse workspace and the storage account

Udacity deletes lab resources when the session ends anyway, but deleting them
yourself is what the project asks for and it stops the meter early.

---

## Submission checklist

- [ ] Star schema diagram — `docs/star_schema.png`
- [ ] Screenshot: Blob Storage with the four `public.*.txt` files
- [ ] Four `CREATE EXTERNAL TABLE` scripts — `sql/load/02..05`
- [ ] Dimension CETAS scripts — `sql/transform/10..13`
- [ ] Fact CETAS scripts — `sql/transform/20..21`
- [ ] Extra credit — `sql/transform/30..31` plus the query in
      `sql/analysis/business_questions.sql`
- [ ] Write-up drawing on `docs/findings.md`
