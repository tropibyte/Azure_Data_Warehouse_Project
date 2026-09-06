# Divvy Bikeshare Data Warehouse — Project Submission

**Course:** Data Warehouses with Azure
**Author:** Tarie Nosworthy
**Platform:** Azure Synapse Analytics, serverless (Built-in) SQL pool
**Status:** built and reconciled end to end in Azure, 6 Sep 2026
**Includes:** Extra credit

---

## 1. What was built

A dimensional warehouse over the Divvy bikeshare dataset, built entirely in the
Azure Synapse serverless SQL pool. Two fact tables and four dimensions, all
materialised with `CREATE EXTERNAL TABLE AS SELECT`, plus two additional derived
tables for the extra credit.

The pipeline is:

```
PostgreSQL (OLTP)  ->  Blob / ADLS Gen2  ->  external staging tables  ->  CETAS star schema
   4 tables            4 delimited files       4 external tables          6 + 2 tables
```

Volumes processed: **75,000 riders · 838 stations · 4,584,921 trips ·
1,946,607 payments · $19,457,105.25 in payments.**

---

## 2. The source system is not the ERD

The classroom provides a relational ERD showing an `Account` entity with an
`account_number` foreign key linking `Rider` and `Payment`. **That entity does
not exist.** `ProjectDataToPostgres.py` creates four tables, and none of them is
an account:

| Table | Columns as created by the starter script |
|---|---|
| `rider` | `rider_id INTEGER PK, first, last, address, birthday DATE, account_start_date DATE, account_end_date DATE, is_member BOOLEAN` |
| `payment` | `payment_id INTEGER PK, date DATE, amount MONEY, rider_id INTEGER` |
| `station` | `station_id VARCHAR(50) PK, name, latitude FLOAT, longitude FLOAT` |
| `trip` | `trip_id VARCHAR(50) PK, rideable_type, start_at TIMESTAMP, ended_at TIMESTAMP, start_station_id VARCHAR(50), end_station_id VARCHAR(50), rider_id INTEGER` |

Inspecting the actual data files confirms the DDL over the diagram:

* `station_id` values are `KA1503000012`, `TA1305000029`, `525` — alphanumeric,
  not the `int` the ERD shows. A dimension keyed on `int` would silently drop
  most of the station table.
* `account_end_date` is an **empty string**, not `NULL`, for open accounts.
* `is_member` arrives as the text `True` / `False`.
* Membership and account lifespan are columns on `rider`. There is no account
  number anywhere in the data.

Three design consequences followed:

1. **No `dim_account`.** Account attributes are rider attributes and live on
   `dim_rider`.
2. **`fact_payment` joins to the rider directly** on `rider_id`, not through an
   account.
3. **`station_id` stays `VARCHAR(50)`** end to end.

This is the decision the rest of the design rests on, so it is stated first.

---

## 3. Star schema

![Divvy star schema](docs/star_schema.png)

### Fact tables

| Fact | Grain | Measures | Dimension keys |
|---|---|---|---|
| `fact_trip` | one completed bike trip | `duration_seconds`, `duration_minutes`, `rider_age_at_trip` | `rider_id`, `start_station_id`, `end_station_id`, `start_date_key`, `end_date_key`, `start_time_key` |
| `fact_payment` | one payment | `amount`, `rider_age_at_payment` | `rider_id`, `date_key` |

`trip_id` and `payment_id` are carried as degenerate dimensions — they identify
a row and support drill-through, but have no attributes of their own worth a
table.

### Dimensions

| Dimension | Grain | Rows | Serves |
|---|---|---|---|
| `dim_date` | one calendar day, 2013-01-01 → 2030-12-31 | 6,574 | both facts |
| `dim_rider` | one rider | 75,000 | both facts |
| `dim_station` | one station | 838 | `fact_trip`, role-played twice |
| `dim_time` | one hour of day | 24 | `fact_trip` |

**`dim_date` and `dim_rider` are conformed.** Both fact tables key to them, which
is what makes the extra credit possible at all: rides and payments can be placed
on the same calendar and attributed to the same rider without a bridge table.

**`dim_station` role-plays.** `fact_trip` joins to it twice — once as
`start_station_id`, once as `end_station_id` — which is what business outcome 1b
("longest rides by start and/or end station") requires. One physical table, two
logical roles.

**`dim_time` is at hour grain, not minute.** Twenty-four rows answer "time of
day" completely; 1,440 rows would answer nothing further, since no one asks how
ride length differs between 08:17 and 08:18.

### Key strategy

| Key | Type | Rationale |
|---|---|---|
| `date_key` | generated surrogate, `yyyymmdd` int | Sorts correctly, human-readable in a results grid, and independent of the source. |
| `time_key` | generated surrogate, hour `0..23` | Same. |
| `rider_id`, `station_id` | natural keys from the source | The serverless pool has no `IDENTITY` and CETAS cannot enforce a primary key, so a `ROW_NUMBER()` surrogate would add a lookup and buy nothing. Both natural keys are stable, unique and not reused. |

### Where age lives, and why it is in two places

This is the one modelling decision worth defending explicitly, because the
business outcomes ask for age twice and mean two different things:

* **Age at time of ride** (outcome 1c) is a **fact**. The same rider is a
  different age on two different trips, so the only correct place for it is
  stamped onto `fact_trip` at build time. Putting it on `dim_rider` would make
  it a slowly-changing-dimension problem, and would be wrong for every historical
  trip.
* **Age at account start** (outcome 2b) is a **dimension attribute**. It is
  fixed for the life of the rider, so it lives on `dim_rider` as
  `age_at_account_start` and its banding.

Both are computed with a full birthday comparison, not `DATEDIFF(YEAR, ...)`
alone, which overstates age by up to a year for anyone whose birthday has not
yet fallen in the calendar year.

The dimensions carry **no facts** — no ride counts, no payment totals, no
durations.

---

## 4. The pipeline

### EXTRACT — PostgreSQL to Blob Storage

The Synapse Copy Data tool, run once, moves all four tables to ADLS Gen2 as
DelimitedText. Evidence: `screenshots/01_blob_storage_four_files.png`.

### LOAD — external staging tables

Four `CREATE EXTERNAL TABLE` scripts (`sql/load/02` – `05`). Three deliberate
choices:

**Dates and timestamps stage as `VARCHAR`.** A `datetime2` external column fails
the *entire file* on a single unparseable row, with no indication of which row.
Staging as text and converting with `TRY_CONVERT` in the transform turns that
failure into a countable `NULL` — and `40_validate_star_schema.sql` counts them.
On this dataset the count is zero, but that is a result, not an assumption.

**`amount` stages as `VARCHAR(50)`.** The source column is PostgreSQL `MONEY`,
which the extract can render as `$9.00` or `1,250.00`. A numeric external column
rejects that outright. The transform strips currency symbols, thousands
separators and spaces before casting to `DECIMAL(10,2)` — and deliberately does
*not* try to strip non-breaking spaces with `CHAR(160)`, for the reason given in
section 7.

**The file format sets `STRING_DELIMITER = '"'`.** The wizard-generated format
omits it. `rider.address` contains commas, and the copy activity quotes such
values — without the quote character those rows shift columns and corrupt the
load *silently*, with no error and no dropped rows. This is the failure mode
most likely to go unnoticed, so the format is defined explicitly rather than
inherited.

### TRANSFORM — CETAS

Serverless has no local storage, so `CREATE TABLE` is unavailable; every warehouse
table is `CREATE EXTERNAL TABLE AS SELECT`, writing to `warehouse/<table>/` in
the data lake.

Order is a dependency, not a preference: `fact_trip` and `fact_payment` join to
the already-materialised `dim_rider` — the "materialise the reference join to a
file, then join to that single external table" pattern — and both extra-credit
tables read the two facts.

**Output is Parquet.** The classroom example writes delimited text. Parquet
round-trips real `datetime2`, `decimal` and `bit` types, so `fact_trip` can be
queried back without re-casting every column, and no address or station name
containing a delimiter can corrupt the output. The cost is nothing; the
`FILE_FORMAT` name is the only line that differs.

`dim_date` is generated from a cross-joined digit list rather than a recursive
CTE or `sys.all_objects`, so it runs identically anywhere and does not depend on
a system table having enough rows.

---

## 5. Extra credit

**The question:** how much money is spent per member, based on how many rides
the rider averages per month.

**The problem:** rides and payments are two facts at two different grains.
Joining them directly fans out — a rider with 12 payments and 40 trips produces
480 rows and a payment total inflated forty-fold. Any answer computed that way
is wrong by a factor that varies per rider.

**The solution:** two derived tables.

`fact_rider_monthly` — grain: one row per rider per calendar month with any
activity. The month spine is the `UNION` of months the rider rode and months the
rider paid, so a rider who paid in a month they never rode still gets a row with
`rides_in_month = 0`. That row turns out to matter enormously.

`agg_rider_spend_vs_rides` — grain: one row per rider. Rolls the monthly fact up
to lifetime totals, and computes `avg_rides_per_month` over **months observed**
(first activity to last, inclusive) rather than months active. Dividing by
active months only would score a rider who rode twice in one month and vanished
identically to one who rode twice a month for two years. The inactive months are
the signal; they stay in the denominator.

### Result

| Rides/month band | Members | Avg rides/mo | Avg lifetime paid | Avg monthly spend | Avg spend per ride |
|---|---:|---:|---:|---:|---:|
| 0 (no rides) | 29,179 | 0.00 | $239.78 | $9.00 | — |
| Under 1 | 10,347 | 0.31 | $296.87 | $7.62 | $90.17 |
| 1 to 2 | 3,543 | 1.43 | $289.96 | $7.10 | $5.14 |
| 2 to 4 | 4,290 | 2.90 | $270.45 | $7.14 | $2.56 |
| 4 to 8 | 4,700 | 5.71 | $198.35 | $6.64 | $1.21 |
| 8 to 16 | 4,197 | 11.30 | $136.42 | $6.05 | $0.56 |
| 16+ | 3,162 | 27.56 | $87.93 | $5.14 | $0.22 |

**Finding 1 — the membership pays for itself at roughly one ride a week.** Cost
per ride collapses from $90.17 to $0.22 across the range, a 400x spread.

**Finding 2 — 29,179 members, about half of all members, never took a single
ride, and paid roughly $7.0M doing it.** They sit at a flat $9.00/month for an
average of 26.6 months. This is invisible in either fact table alone:
`fact_payment` has no concept of a ride, and `fact_trip` has no row for a rider
who never rode. Only the conformed rider-month grain shows an account paying
into months containing zero trips. It is the strongest argument for why the
extra-credit table exists rather than a single clever query.

**The trap, and the correction.** Lifetime spend *falls* as ride frequency
rises, which reads as though heavy riders are worth less. They are not — it is a
tenure artifact:

| Rides/month band | Avg months observed | Avg lifetime paid | Avg monthly spend |
|---|---:|---:|---:|
| Under 1 | 36.6 | $296.87 | $7.62 |
| 1 to 2 | 36.6 | $289.96 | $7.10 |
| 2 to 4 | 34.6 | $270.45 | $7.14 |
| 4 to 8 | 26.6 | $198.35 | $6.64 |
| 8 to 16 | 20.0 | $136.42 | $6.05 |
| 16+ | 15.4 | $87.93 | $5.14 |

The observation window shrinks from 36.6 months to 15.4 as frequency rises: the
heaviest riders joined most recently, so lifetime spend is measuring account age,
not behaviour. The defensible measures are the rate measures —
`avg_spend_per_month` and `spend_per_ride` — or a tenure-banded cut, which the
final extra-credit query in `business_questions.sql` provides.

---

## 6. Business outcomes

All results in [docs/findings.md](docs/findings.md); queries in
[sql/analysis/business_questions.sql](sql/analysis/business_questions.sql).

| Outcome | Answered by | Headline result |
|---|---|---|
| 1a — ride time by day of week | `dim_date.day_name` | Sunday 24.87 min vs Wednesday 16.63 min — weekend rides run 50% longer |
| 1a — ride time by time of day | `dim_time.time_of_day` | Morning is the shortest at 17.53 min despite being the second-busiest window |
| 1b — ride time by station | `dim_station` joined twice | Longest averages all come from low-volume outlying stations (Cicero & Quincy, 84.74 min over 76 rides) |
| 1c — ride time by age at ride | `fact_trip.rider_age_at_trip` | Flat: every band between 19.2 and 20.5 min |
| 1d — member vs casual | `fact_trip.is_member` | Also flat — membership does not predict ride length |
| 2a — spend by month/quarter/year | `dim_date` | Near-linear growth $53.7K (2013) to $6.08M (2021); 2022 is a partial year |
| 2b — member spend by age at account start | `dim_rider.age_band_at_account_start` | Falls monotonically: $340.22 per under-18 member vs $144.23 per 65+ member |
| 3 — **extra credit** | `agg_rider_spend_vs_rides` | See section 5 |

Worth stating plainly: **1c and 1d are negative results.** Ride length is
essentially independent of both rider age and membership status. *When* someone
rides predicts ride length far better than *who* they are. Age and membership
are not useful levers here; day of week and hour are. A schema that only
supported the hypotheses that panned out would be a worse schema.

---

## 7. Data quality

`sql/transform/40_validate_star_schema.sql` reconciles the star against staging
after every build. Results on the full dataset:

| Check | Result |
|---|---|
| Trips dropped for unparseable timestamps | 0 of 4,584,921 |
| Payments with unparseable amount | 0 of 1,946,607 |
| Orphan `rider_id` / `start_station_id` / `end_station_id` | 0 |
| Orphan `date_key` / `time_key` | 0 |
| Duplicate `trip_id` / `payment_id` | 0 |
| Trips missing rider age | 0 |
| Money: staging vs `fact_payment` | $19,457,105.25 = $19,457,105.25 |
| Rides: `fact_trip` = `fact_rider_monthly` = `agg_rider_spend_vs_rides` | 4,584,921 |
| **Trips with negative duration** | **116** — `ended_at` precedes `started_at` |
| **Trips over 24 hours** | **1,277** — unreturned bikes |

### What the reconciliation caught

This is not a formality. Building the warehouse in Azure surfaced three defects
that the offline rehearsal could not have found, because DuckDB is not T-SQL:

**`CHAR(160)` returns NULL under a UTF-8 database collation.** The payment
transform stripped non-breaking spaces with
`REPLACE(..., CHAR(160), '')`. Since `REPLACE(x, NULL, '')` evaluates to NULL,
**every amount in `fact_payment` became NULL** - 1,946,607 rows of it. The CETAS
succeeded. The row count was correct. The table looked fine. Only the
staging-versus-fact money check exposed it, because staging still totalled
$19,457,105.25 while the fact totalled nothing at all.

A green CETAS means the statement parsed and ran. It does not mean the data is
right. That gap is the entire justification for
`40_validate_star_schema.sql`, and without it this project would have shipped a
warehouse with no money in it and two extra-credit tables reading 0.00.

**`OFFSETS` is a reserved keyword in T-SQL** and cannot name a CTE, which broke
`dim_date` outright - a loud failure, and the easy kind.

**The lab blocks `Microsoft.Authorization`,** so the Synapse managed identity
cannot be granted Storage Blob Data Contributor by anyone, and the copy activity
failed with `AuthorizationPermissionMismatch`. Resolved with account-key
authentication on the sink linked service, which is a documented ADF method. A
workspace created through the portal hits the same wall for the same reason.

### Anomalous rows

The 1,393 anomalous trips are **kept** in `fact_trip`. Every duration query
filters `duration_seconds BETWEEN 0 AND 86400` instead. Deleting them at load
would hide a real operational signal — the over-24-hour trips are precisely the
bikes that went missing — and would make the warehouse unable to answer a
question it currently can.

---

## 8. Repository

```
docs/star_schema.md           design and rationale
docs/star_schema.png          the diagram above
docs/findings.md              full results for every business outcome
docs/lab_runbook.md           step-by-step Azure session guide
sql/load/00                   CREATE DATABASE (serverless has only master)
sql/load/01                   external data source + file formats
sql/load/02..05               four CREATE EXTERNAL TABLE scripts
sql/transform/10..13          dimension CETAS
sql/transform/20..21          fact CETAS
sql/transform/30..31          extra credit CETAS
sql/transform/40              reconciliation
sql/analysis/                 business outcome queries
local/validate_with_duckdb.py rebuilds the whole warehouse offline
tools/configure.py            stamps storage names into every script
tools/render_star_schema.py   regenerates the diagram
```

### Reproducibility

The entire warehouse can be rebuilt on a laptop with no Azure subscription:

```bash
pip install duckdb pandas
python local/validate_with_duckdb.py
```

This runs the same logic against the same CSVs, prints the same reconciliation
checks and the same business answers. It exists because the Udacity lab allows
ten attempts total, and every calculation error found offline is an attempt not
spent. Every number in this document was produced by it and is reproduced by the
Synapse build.

---

## 9. Rubric mapping

| Criterion | Where |
|---|---|
| Two fact tables sharing common dimensions | `fact_trip`, `fact_payment`; both key to `dim_date` and `dim_rider` |
| Trip fact has trip duration and rider age at time of trip | `fact_trip.duration_seconds`, `duration_minutes`, `rider_age_at_trip` |
| Payment fact has amount of payment | `fact_payment.amount` |
| Trip dimensions: riders, stations, dates | `dim_rider`, `dim_station` (role-played twice), `dim_date`, plus `dim_time` |
| Payment dimensions: dates, riders | `dim_date`, `dim_rider` |
| Extract screenshot — 4 text files in Blob Storage | `screenshots/01_blob_storage_four_files.png` |
| 4 scripts using `CREATE EXTERNAL TABLE` | `sql/load/02` – `05` |
| Fact CETAS with appropriate dimension keys | `sql/transform/20`, `21` |
| Dimension CETAS matching the diagram, no facts | `sql/transform/10` – `13` |
| Extra credit | `sql/transform/30`, `31`; final queries in `sql/analysis/business_questions.sql` |
