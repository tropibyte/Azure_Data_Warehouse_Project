# Divvy Bikeshare — Azure Synapse Data Warehouse

Udacity *Data Warehouses with Azure* project, including the extra credit.

Star schema design, four LOAD scripts, seven CETAS TRANSFORM scripts, a
reconciliation suite, and the analysis queries that answer every business
outcome in the brief.

**Start here: [SUBMISSION.md](SUBMISSION.md)** — the project writeup.
This README is the operating manual.

---

## The one thing that breaks most submissions

**The classroom ERD does not match the data.** The ERD image shows an `Account`
entity with an `account_number` foreign key. `starter/ProjectDataToPostgres.py`
never creates one. The actual source is four tables, and `rider` carries
`is_member`, `account_start_date` and `account_end_date` as its own columns.

Design to the ERD image and you will build a `dim_account` with nothing to put
in it, and a `fact_payment` that cannot join to anything. Design to the starter
script — as this repo does — and everything lines up.

See [docs/star_schema.md](docs/star_schema.md) for the full design and the
reasoning behind each key, and [docs/findings.md](docs/findings.md) for the
answers to every business outcome, computed from the real dataset.

The real data confirms the mismatch: `station_id` values look like
`KA1503000012`, not the integer the ERD shows; `account_end_date` is an empty
string for open accounts; `is_member` arrives as `True`/`False`.

**Status:** the full pipeline has been run end to end locally against all
4,584,921 trips and 1,946,607 payments. Every reconciliation check returns 0
defects and payments total $19,457,105.25 identically across staging, the fact
table and both extra-credit rollups.

---

## Repository layout

```
starter/ProjectDataToPostgres.py     Task 3 - load the OLTP source (env-var config)
sql/load/00_create_database.sql      create the serverless database (run first)
sql/load/01_setup_*.sql              external data source + file formats
sql/load/02..05_create_external_*    Task 5 - four CREATE EXTERNAL TABLE scripts
sql/transform/10..13_cetas_dim_*     Task 6 - dimensions via CETAS
sql/transform/20..21_cetas_fact_*    Task 6 - fact tables via CETAS
sql/transform/30..31_*               EXTRA CREDIT - rider-month fact + rider rollup
sql/transform/40_validate_*          reconciliation: staging vs star
sql/analysis/business_questions.sql  every business outcome, answered
sql_configured/                      the same scripts with real storage names,
                                     as actually run - read the LOAD scripts
                                     against screenshots/01_*.png
local/docker-compose.yml             local Postgres for offline rehearsal
local/validate_with_duckdb.py        run the whole warehouse on your laptop
tools/provision_azure.sh             create all Azure resources in one command
tools/configure.py                   stamp storage names into all SQL at once
docs/star_schema.md                  schema design + rubric traceability
docs/star_schema.png                 rendered star schema diagram
docs/lab_runbook.md                  step-by-step guide for the lab session
docs/findings.md                     answers to every business outcome
tools/render_star_schema.py          regenerates the diagram PNG
screenshots/README.md                what to capture in the lab, and how
SUBMISSION.md                        the project writeup
data/                                unzip the four project CSVs here (gitignored)
```

---

## Can this be built locally? Mostly, yes — and you should

You get **10 lab attempts, total**. Three of the four steps can be developed and
proven on your laptop, so the lab session is only ever a paste-and-run.

| Step | Locally? | How |
|---|---|---|
| Star schema design | Yes | It is a design document. No cloud needed. |
| Task 3 — load PostgreSQL | Yes | `local/docker-compose.yml` + `--local` flag |
| Task 4 — EXTRACT to Blob | **No** | Needs the Synapse copy wizard. This is also where one of the two required screenshots comes from. |
| Task 5 — LOAD external tables | Written locally, run in Synapse | `CREATE EXTERNAL TABLE` needs the serverless pool |
| Task 6 — TRANSFORM CETAS | Logic locally, run in Synapse | `local/validate_with_duckdb.py` proves every calculation first |

### Local rehearsal, start to finish

```bash
pip install duckdb pandas psycopg2-binary
```

The four CSVs are already unzipped into `data/` (gitignored, ~500 MB — `trips.csv`
alone is 440 MB). Then:

```bash
python local/validate_with_duckdb.py
```

Takes a couple of minutes; most of it is parsing `trips.csv`.

That builds `dim_rider`, `dim_station`, `fact_trip`, `fact_payment`,
`fact_rider_monthly` and `agg_rider_spend_vs_rides` from the CSVs, runs the
reconciliation checks, and prints the answer to every business question. Every
"defects" number should be `0`. If the age calculation is wrong, or a payment
amount will not cast, or a trip points at a station that does not exist, you
find out here rather than 40 minutes into a lab session.

Optionally rehearse the Postgres load too:

```bash
docker compose -f local/docker-compose.yml up -d
python starter/ProjectDataToPostgres.py --local
```

---

## Running it in Azure

### 1. Load PostgreSQL (Task 3)

```bash
set PGHOST=<your-server>.postgres.database.azure.com
set PGUSER=<admin-user>
set PGPASSWORD=<password>
python starter/ProjectDataToPostgres.py
```

The script prints a row count per table. Expected:

```
rider       75,000
payment  1,946,607
station        838
trip     4,584,921
```

`trips.csv` is 440 MB, so the `COPY` takes several minutes over the wire — start
this before you need it, not while the lab clock is running.

### 2. Extract to Blob Storage (Task 4)

Synapse Studio → **Integrate** → **Copy Data tool** → one-time run, source =
your Azure Database for PostgreSQL, select all four tables, sink = your ADLS
Gen2 container, format = DelimitedText.

**Screenshot the container now** — four files named `public.rider.txt`,
`public.payment.txt`, `public.station.txt`, `public.trip.txt`. That is the
Extract-step rubric evidence. Save it to `screenshots/`.

### 3. Stamp your storage names into the SQL

```bash
python tools/configure.py --storage-account mydls20250906 --filesystem mydlsfs20250906 --extract-folder divvy
```

Reads `sql/`, writes `sql_configured/` with every placeholder replaced. It exits
non-zero if any `<< >>` placeholder is left, so you cannot paste a half-configured
script into the lab by accident.

### 4. Run the scripts, in this order



First connect to **Built-in** with **Use database: master**, run
`00_create_database.sql`, then refresh and switch the dropdown to `divvy`. The
serverless endpoint has only `master` until you do — and the error you get for
skipping it does not mention the database.

```
sql_configured/load/00_create_database.sql             -- in master, then switch to divvy
sql_configured/load/01_setup_data_source_and_formats.sql
sql_configured/load/02_create_external_table_staging_rider.sql
sql_configured/load/03_create_external_table_staging_payment.sql
sql_configured/load/04_create_external_table_staging_station.sql
sql_configured/load/05_create_external_table_staging_trip.sql

sql_configured/transform/10_cetas_dim_date.sql
sql_configured/transform/11_cetas_dim_time.sql
sql_configured/transform/12_cetas_dim_rider.sql
sql_configured/transform/13_cetas_dim_station.sql
sql_configured/transform/20_cetas_fact_trip.sql        -- needs dim_rider
sql_configured/transform/21_cetas_fact_payment.sql     -- needs dim_rider
sql_configured/transform/30_cetas_fact_rider_monthly.sql   -- needs both facts
sql_configured/transform/31_cetas_agg_rider_spend_vs_rides.sql

sql_configured/transform/40_validate_star_schema.sql
sql_configured/analysis/business_questions.sql
```

The order matters: `fact_trip` and `fact_payment` join to the materialised
`dim_rider`, and both extra-credit tables read the two facts.

---

## Gotchas that cost lab time

**CETAS will not overwrite.** `DROP EXTERNAL TABLE` removes the metadata but
leaves the files. Re-running a CETAS against a folder that still has files fails
with *"the specified path already exists"*. Before re-running any transform,
delete its folder under `<filesystem>/warehouse/` in **Data → Linked → your
storage account**. Every transform script says which folder in its header.

**`CREATE TABLE` is not supported in the serverless pool.** It has no local
storage. Everything is `CREATE EXTERNAL TABLE` or CETAS. This is expected, not a
misconfiguration.

**`MONEY` arrives as text.** `payment.amount` is PostgreSQL `MONEY`, so the
extract can write `$9.00`. That is why `staging_payment.amount` is `VARCHAR(50)`
and the transform strips `$`, `,`, spaces and non-breaking spaces before casting.

**Quoted fields.** `rider.address` and `station.name` can contain commas, which
the copy activity quotes. The file format therefore sets `STRING_DELIMITER = '"'`
— the wizard-generated format omits it, and without it those rows shift columns
and silently corrupt the load. If your extract wrote a header row, add
`FIRST_ROW = 2` to the format options.

**Dates stage as `VARCHAR`.** A `datetime2` external column fails the entire file
on one unparseable row. `TRY_CONVERT` in the transform turns that into a NULL you
can count instead — which `40_validate_star_schema.sql` does.

**Collation.** `00_create_database.sql` creates the database with
`COLLATE Latin1_General_100_CI_AS_SC_UTF8`. Without a UTF-8 collation, reading
UTF-8 delimited files into `VARCHAR` columns under PARSER_VERSION 2.0 throws a
collation error and you end up adding a `COLLATE` clause to every column.

**CETAS output is Parquet here, not CSV.** Parquet round-trips real
`datetime2` / `decimal` / `bit` types, so `fact_trip` can be queried straight
back without re-casting, and no address or station name containing a delimiter
can corrupt the output. The classroom example uses delimited text; swap
`SynapseParquetFormat` for `SynapseDelimitedTextFormat` in the transform scripts
if you want to match it exactly.

---

## Rubric traceability

| Rubric criterion | Where |
|---|---|
| Two fact tables sharing common dimensions | `fact_trip` + `fact_payment`, both on `dim_date` and `dim_rider` |
| Trip fact has duration and rider age at time of trip | `fact_trip.duration_seconds`, `duration_minutes`, `rider_age_at_trip` |
| Payment fact has payment amount | `fact_payment.amount` |
| Trip dimensions: riders, stations, dates | `dim_rider`, `dim_station` (role-played twice), `dim_date` (+ `dim_time`) |
| Payment dimensions: dates, riders | `dim_date`, `dim_rider` |
| Extract screenshot: 4 text files in Blob Storage | `screenshots/` — capture during Task 4 |
| 4 script files using `CREATE EXTERNAL TABLE` | `sql/load/02..05` |
| Fact CETAS with appropriate dimension keys | `sql/transform/20`, `21` |
| Dimension CETAS matching the diagram, no facts | `sql/transform/10..13` |
| **Extra credit** — spend per member by avg rides/month | `sql/transform/30`, `31`; query at the end of `sql/analysis/business_questions.sql` |

---

## Cleanup

When you are done, delete the PostgreSQL server, the Synapse workspace (only if
you created it for this project) and the associated storage. The lab bills by
the minute and does not preserve resources between sessions anyway.
