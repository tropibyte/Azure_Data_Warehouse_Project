"""
Offline rehearsal of the whole warehouse, on your laptop, with no Azure at all.

The Udacity lab allows 10 attempts total. This script builds the same star
schema from the same four CSVs using DuckDB, so every logic error - a bad age
calculation, a MONEY value that will not cast, an orphaned station id - is found
here, for free, before you spend a lab session on it.

DuckDB is not T-SQL, so this proves the LOGIC, not the syntax. What it proves:
  * the CSVs parse with the column order the starter script implies
  * row counts survive the transform
  * the age, duration and MONEY-cleaning expressions produce sane values
  * every fact row has a matching dimension row
  * all three business outcomes plus extra credit return real numbers

    pip install duckdb
    python local/validate_with_duckdb.py
"""

import argparse
import os
import sys

try:
    import duckdb
except ImportError:
    sys.exit("pip install duckdb")

HERE = os.path.dirname(os.path.abspath(__file__))

_parser = argparse.ArgumentParser()
_parser.add_argument("--data", default=os.path.join(HERE, "..", "data"),
                     help="folder holding the four project CSVs")
_args = _parser.parse_args()
DATA = os.path.normpath(_args.data)

FILES = {
    "riders.csv": ["rider_id", "first_name", "last_name", "address", "birthday",
                   "account_start_date", "account_end_date", "is_member"],
    "payments.csv": ["payment_id", "payment_date", "amount", "rider_id"],
    "stations.csv": ["station_id", "station_name", "latitude", "longitude"],
    "trips.csv": ["trip_id", "rideable_type", "started_at", "ended_at",
                  "start_station_id", "end_station_id", "rider_id"],
}

missing = [f for f in FILES if not os.path.exists(os.path.join(DATA, f))]
if missing:
    sys.exit("Missing {0} in {1}\n"
             "Unzip azure-data-warehouse-projectdatafiles.zip there first."
             .format(", ".join(missing), DATA))

con = duckdb.connect()


def banner(text):
    print("\n" + "=" * 72)
    print(text)
    print("=" * 72)


# ---------------------------------------------------------------- STAGING ----
# Everything read as VARCHAR, exactly like the Synapse external tables, so the
# casting logic gets exercised rather than bypassed by DuckDB's sniffer.
for filename, columns in FILES.items():
    table = "staging_" + filename.split(".")[0].rstrip("s")
    name_list = ", ".join("'{0}'".format(c) for c in columns)
    path = os.path.join(DATA, filename).replace("\\", "/")
    con.execute(
        "CREATE TABLE {0} AS SELECT * FROM read_csv('{1}', header=false, "
        "all_varchar=true, names=[{2}])".format(table, path, name_list)
    )

banner("STAGING ROW COUNTS")
for table in ("staging_rider", "staging_payment", "staging_station", "staging_trip"):
    n = con.execute("SELECT count(*) FROM " + table).fetchone()[0]
    print("  {0:20s} {1:>10,}".format(table, n))

banner("SAMPLE ROWS (check the column order matches the starter script)")
for table in ("staging_rider", "staging_payment", "staging_station", "staging_trip"):
    print("\n-- " + table)
    print(con.execute("SELECT * FROM " + table + " LIMIT 3").df().to_string(index=False))

# ------------------------------------------------------------- DIMENSIONS ----
con.execute("""
CREATE TABLE dim_rider AS
WITH typed AS (
    SELECT
        CAST(rider_id AS INTEGER)                        AS rider_id,
        first_name, last_name, address,
        TRY_CAST(nullif(birthday, '') AS DATE)           AS birthday,
        TRY_CAST(nullif(account_start_date, '') AS DATE) AS account_start_date,
        TRY_CAST(nullif(account_end_date, '') AS DATE)   AS account_end_date,
        CASE WHEN lower(trim(is_member)) IN ('true','t','1','yes','y') THEN 1 ELSE 0 END AS is_member
    FROM staging_rider
), aged AS (
    SELECT *, date_diff('year', birthday, account_start_date)
        - CASE WHEN month(account_start_date) < month(birthday)
                 OR (month(account_start_date) = month(birthday)
                     AND day(account_start_date) < day(birthday))
               THEN 1 ELSE 0 END AS age_at_account_start
    FROM typed
)
SELECT *,
    CASE WHEN is_member = 1 THEN 'Member' ELSE 'Casual' END AS rider_type,
    CASE WHEN age_at_account_start IS NULL THEN 'Unknown'
         WHEN age_at_account_start < 18 THEN 'Under 18'
         WHEN age_at_account_start < 25 THEN '18-24'
         WHEN age_at_account_start < 35 THEN '25-34'
         WHEN age_at_account_start < 45 THEN '35-44'
         WHEN age_at_account_start < 55 THEN '45-54'
         WHEN age_at_account_start < 65 THEN '55-64'
         ELSE '65+' END AS age_band_at_account_start
FROM aged
""")

con.execute("""
CREATE TABLE dim_station AS
SELECT trim(station_id) AS station_id, station_name,
       TRY_CAST(latitude AS DOUBLE) AS latitude,
       TRY_CAST(longitude AS DOUBLE) AS longitude
FROM staging_station
""")

# ------------------------------------------------------------------ FACTS ----
con.execute("""
CREATE TABLE fact_trip AS
WITH typed AS (
    SELECT t.trip_id, t.rideable_type,
           TRY_CAST(nullif(t.started_at, '') AS TIMESTAMP) AS started_at,
           TRY_CAST(nullif(t.ended_at,   '') AS TIMESTAMP) AS ended_at,
           trim(t.start_station_id) AS start_station_id,
           trim(t.end_station_id)   AS end_station_id,
           CAST(t.rider_id AS INTEGER) AS rider_id,
           r.birthday, r.is_member, r.rider_type
    FROM staging_trip t
    LEFT JOIN dim_rider r ON r.rider_id = CAST(t.rider_id AS INTEGER)
), aged AS (
    SELECT *,
        date_diff('second', started_at, ended_at) AS duration_seconds,
        date_diff('year', birthday, started_at)
            - CASE WHEN month(started_at) < month(birthday)
                     OR (month(started_at) = month(birthday)
                         AND day(started_at) < day(birthday))
                   THEN 1 ELSE 0 END AS rider_age_at_trip
    FROM typed WHERE started_at IS NOT NULL AND ended_at IS NOT NULL
)
SELECT trip_id, rider_id, start_station_id, end_station_id,
       CAST(strftime(started_at, '%Y%m%d') AS INTEGER) AS start_date_key,
       CAST(strftime(ended_at,   '%Y%m%d') AS INTEGER) AS end_date_key,
       hour(started_at) AS start_time_key,
       rideable_type, started_at, ended_at,
       duration_seconds,
       ROUND(duration_seconds / 60.0, 2) AS duration_minutes,
       rider_age_at_trip,
       CASE WHEN rider_age_at_trip IS NULL THEN 'Unknown'
            WHEN rider_age_at_trip < 18 THEN 'Under 18'
            WHEN rider_age_at_trip < 25 THEN '18-24'
            WHEN rider_age_at_trip < 35 THEN '25-34'
            WHEN rider_age_at_trip < 45 THEN '35-44'
            WHEN rider_age_at_trip < 55 THEN '45-54'
            WHEN rider_age_at_trip < 65 THEN '55-64'
            ELSE '65+' END AS rider_age_band_at_trip,
       coalesce(is_member, 0) AS is_member,
       coalesce(rider_type, 'Unknown') AS rider_type,
       dayname(started_at) AS day_name,
       CASE WHEN hour(started_at) BETWEEN 5 AND 11 THEN 'Morning'
            WHEN hour(started_at) BETWEEN 12 AND 16 THEN 'Afternoon'
            WHEN hour(started_at) BETWEEN 17 AND 21 THEN 'Evening'
            ELSE 'Night' END AS time_of_day
FROM aged
""")

con.execute("""
CREATE TABLE fact_payment AS
WITH typed AS (
    SELECT CAST(p.payment_id AS INTEGER) AS payment_id,
           CAST(p.rider_id AS INTEGER)   AS rider_id,
           TRY_CAST(nullif(p.payment_date, '') AS DATE) AS payment_date,
           TRY_CAST(replace(replace(replace(p.amount, '$', ''), ',', ''), ' ', '')
                    AS DECIMAL(10,2)) AS amount
    FROM staging_payment p
)
SELECT payment_id, rider_id,
       CAST(strftime(payment_date, '%Y%m%d') AS INTEGER) AS date_key,
       payment_date, amount
FROM typed WHERE payment_date IS NOT NULL
""")

con.execute("""
CREATE TABLE fact_rider_monthly AS
WITH t AS (
    SELECT rider_id, date_trunc('month', started_at)::DATE AS month_start_date,
           count(*) AS rides_in_month, sum(duration_minutes) AS ride_minutes_in_month
    FROM fact_trip WHERE rider_id IS NOT NULL GROUP BY 1, 2
), p AS (
    SELECT rider_id, date_trunc('month', payment_date)::DATE AS month_start_date,
           count(*) AS payments_in_month, sum(amount) AS amount_paid_in_month
    FROM fact_payment WHERE rider_id IS NOT NULL GROUP BY 1, 2
), k AS (
    SELECT rider_id, month_start_date FROM t
    UNION
    SELECT rider_id, month_start_date FROM p
)
SELECT k.rider_id, k.month_start_date,
       strftime(k.month_start_date, '%Y-%m') AS year_month,
       coalesce(t.rides_in_month, 0)         AS rides_in_month,
       coalesce(t.ride_minutes_in_month, 0)  AS ride_minutes_in_month,
       coalesce(p.payments_in_month, 0)      AS payments_in_month,
       coalesce(p.amount_paid_in_month, 0)   AS amount_paid_in_month
FROM k
LEFT JOIN t ON t.rider_id = k.rider_id AND t.month_start_date = k.month_start_date
LEFT JOIN p ON p.rider_id = k.rider_id AND p.month_start_date = k.month_start_date
""")

con.execute("""
CREATE TABLE agg_rider_spend_vs_rides AS
WITH rolled AS (
    SELECT rider_id,
           min(month_start_date) AS first_active_month,
           max(month_start_date) AS last_active_month,
           sum(rides_in_month)   AS total_rides,
           sum(amount_paid_in_month) AS total_paid,
           sum(CASE WHEN rides_in_month > 0 THEN 1 ELSE 0 END) AS months_active
    FROM fact_rider_monthly GROUP BY 1
), rated AS (
    SELECT *, date_diff('month', first_active_month, last_active_month) + 1 AS months_observed
    FROM rolled
)
SELECT r.rider_id, d.rider_type, d.is_member, d.age_at_account_start,
       d.age_band_at_account_start,
       r.months_observed, r.months_active, r.total_rides, r.total_paid,
       ROUND(r.total_rides * 1.0 / nullif(r.months_observed, 0), 2) AS avg_rides_per_month,
       ROUND(r.total_paid / nullif(r.months_observed, 0), 2)        AS avg_spend_per_month,
       ROUND(r.total_paid / nullif(r.total_rides, 0), 2)            AS spend_per_ride,
       CASE WHEN r.total_rides * 1.0 / nullif(r.months_observed, 0) IS NULL THEN 'Unknown'
            WHEN r.total_rides * 1.0 / nullif(r.months_observed, 0) = 0  THEN '0 (no rides)'
            WHEN r.total_rides * 1.0 / nullif(r.months_observed, 0) < 1  THEN 'Under 1'
            WHEN r.total_rides * 1.0 / nullif(r.months_observed, 0) < 2  THEN '1 to 2'
            WHEN r.total_rides * 1.0 / nullif(r.months_observed, 0) < 4  THEN '2 to 4'
            WHEN r.total_rides * 1.0 / nullif(r.months_observed, 0) < 8  THEN '4 to 8'
            WHEN r.total_rides * 1.0 / nullif(r.months_observed, 0) < 16 THEN '8 to 16'
            ELSE '16+' END AS rides_per_month_band
FROM rated r LEFT JOIN dim_rider d ON d.rider_id = r.rider_id
""")

# ------------------------------------------------------------- VALIDATION ----
banner("RECONCILIATION - every 'defects' number must be 0")
checks = [
    ("staging_trip rows",            "SELECT count(*) FROM staging_trip"),
    ("fact_trip rows",               "SELECT count(*) FROM fact_trip"),
    ("trips dropped (bad timestamp)",
     "SELECT (SELECT count(*) FROM staging_trip) - (SELECT count(*) FROM fact_trip)"),
    ("staging_payment rows",         "SELECT count(*) FROM staging_payment"),
    ("fact_payment rows",            "SELECT count(*) FROM fact_payment"),
    ("defects: unparseable amount",
     "SELECT count(*) FROM fact_payment WHERE amount IS NULL"),
    ("defects: trip rider not in dim_rider",
     "SELECT count(*) FROM fact_trip f LEFT JOIN dim_rider d ON d.rider_id = f.rider_id "
     "WHERE d.rider_id IS NULL"),
    ("defects: start station not in dim_station",
     "SELECT count(*) FROM fact_trip f LEFT JOIN dim_station s "
     "ON s.station_id = f.start_station_id WHERE s.station_id IS NULL"),
    ("defects: end station not in dim_station",
     "SELECT count(*) FROM fact_trip f LEFT JOIN dim_station s "
     "ON s.station_id = f.end_station_id WHERE s.station_id IS NULL"),
    ("defects: duplicate trip_id",
     "SELECT count(*) - count(DISTINCT trip_id) FROM fact_trip"),
    ("defects: duplicate payment_id",
     "SELECT count(*) - count(DISTINCT payment_id) FROM fact_payment"),
    ("defects: null rider age on trip",
     "SELECT count(*) FROM fact_trip WHERE rider_age_at_trip IS NULL"),
    ("info: negative duration trips",
     "SELECT count(*) FROM fact_trip WHERE duration_seconds < 0"),
    ("info: trips over 24h",
     "SELECT count(*) FROM fact_trip WHERE duration_seconds > 86400"),
    ("info: age range on trips",
     "SELECT min(rider_age_at_trip) || ' to ' || max(rider_age_at_trip) FROM fact_trip"),
    ("money: staging total vs fact total",
     "SELECT (SELECT round(sum(TRY_CAST(replace(replace(amount,'$',''),',','') AS DECIMAL(12,2))),2) "
     "        FROM staging_payment) || ' vs ' || "
     "       (SELECT round(sum(amount),2) FROM fact_payment)"),
    ("rides: fact vs monthly vs agg",
     "SELECT (SELECT count(*) FROM fact_trip) || ' / ' || "
     "       (SELECT sum(rides_in_month) FROM fact_rider_monthly) || ' / ' || "
     "       (SELECT sum(total_rides) FROM agg_rider_spend_vs_rides)"),
]
for label, sql in checks:
    print("  {0:42s} {1}".format(label, con.execute(sql).fetchone()[0]))

# ---------------------------------------------------------- THE QUESTIONS ----
banner("OUTCOME 1a - avg ride minutes by DAY OF WEEK")
print(con.execute("""
SELECT day_name, count(*) AS rides, round(avg(duration_minutes), 2) AS avg_minutes
FROM fact_trip WHERE duration_seconds BETWEEN 0 AND 86400
GROUP BY day_name ORDER BY avg_minutes DESC
""").df().to_string(index=False))

banner("OUTCOME 1a - avg ride minutes by TIME OF DAY")
print(con.execute("""
SELECT time_of_day, count(*) AS rides, round(avg(duration_minutes), 2) AS avg_minutes
FROM fact_trip WHERE duration_seconds BETWEEN 0 AND 86400
GROUP BY time_of_day ORDER BY avg_minutes DESC
""").df().to_string(index=False))

banner("OUTCOME 1b - longest average rides by START station (min 50 rides)")
print(con.execute("""
SELECT s.station_name, count(*) AS rides, round(avg(f.duration_minutes), 2) AS avg_minutes
FROM fact_trip f JOIN dim_station s ON s.station_id = f.start_station_id
WHERE f.duration_seconds BETWEEN 0 AND 86400
GROUP BY s.station_name HAVING count(*) >= 50
ORDER BY avg_minutes DESC LIMIT 10
""").df().to_string(index=False))

banner("OUTCOME 1c/1d - avg ride minutes by AGE BAND and RIDER TYPE")
print(con.execute("""
SELECT rider_age_band_at_trip, rider_type, count(*) AS rides,
       round(avg(duration_minutes), 2) AS avg_minutes
FROM fact_trip WHERE duration_seconds BETWEEN 0 AND 86400
GROUP BY 1, 2 ORDER BY min(rider_age_at_trip), rider_type
""").df().to_string(index=False))

banner("OUTCOME 2a - money spent per YEAR and per QUARTER")
print(con.execute("""
SELECT year(payment_date) AS year, count(*) AS payments, round(sum(amount), 2) AS total
FROM fact_payment GROUP BY 1 ORDER BY 1
""").df().to_string(index=False))

banner("OUTCOME 2b - member spend by AGE AT ACCOUNT START")
print(con.execute("""
SELECT d.age_band_at_account_start, count(DISTINCT d.rider_id) AS riders,
       round(sum(p.amount), 2) AS total,
       round(sum(p.amount) / count(DISTINCT d.rider_id), 2) AS per_rider
FROM fact_payment p JOIN dim_rider d ON d.rider_id = p.rider_id
WHERE d.is_member = 1
GROUP BY 1 ORDER BY min(d.age_at_account_start)
""").df().to_string(index=False))

banner("OUTCOME 3 (EXTRA CREDIT) - member spend by AVG RIDES PER MONTH")
print(con.execute("""
SELECT rides_per_month_band, count(*) AS riders,
       round(avg(avg_rides_per_month), 2) AS avg_rides_pm,
       round(avg(total_paid), 2)          AS avg_lifetime_paid,
       round(avg(avg_spend_per_month), 2) AS avg_monthly_spend,
       round(avg(spend_per_ride), 2)      AS avg_spend_per_ride
FROM agg_rider_spend_vs_rides WHERE is_member = 1
GROUP BY 1 ORDER BY min(avg_rides_per_month)
""").df().to_string(index=False))

print("\nAll checks complete. Numbers above are what the Synapse star schema "
      "should reproduce.")
