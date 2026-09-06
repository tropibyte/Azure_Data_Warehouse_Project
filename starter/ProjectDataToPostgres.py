"""
Load the Divvy project CSVs into PostgreSQL to simulate the OLTP source system.

This is the Udacity starter script with three changes:
  1. Connection settings come from environment variables (or local.env) instead of
     being hard-coded, so credentials never land in the repo.
  2. sslmode is configurable, so the same script drives the Azure Database for
     PostgreSQL *and* a local Docker Postgres for offline rehearsal.
  3. Row counts are printed after each load, which is the check the project asks
     for ("verify that all four data files are copied/uploaded into PostgreSQL").

Usage
  set PGHOST=<server>.postgres.database.azure.com
  set PGUSER=<admin-user>
  set PGPASSWORD=<password>
  python starter/ProjectDataToPostgres.py

  # or, for the local rehearsal:
  python starter/ProjectDataToPostgres.py --local
"""

import argparse
import os
import sys

try:
    import psycopg2
    from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
except ImportError:  # pragma: no cover
    sys.exit(
        "psycopg2 is not installed.\n"
        "  pip install psycopg2-binary\n"
        "If the wheel will not build on Python 3.13+, create a 3.12 venv:\n"
        "  py -3.12 -m venv .venv && .venv\Scripts\activate && pip install psycopg2-binary"
    )

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.environ.get("DIVVY_DATA_DIR", os.path.join(HERE, "..", "data"))

parser = argparse.ArgumentParser()
parser.add_argument("--local", action="store_true",
                    help="target localhost Docker Postgres (no SSL)")
args = parser.parse_args()

########################################
# Connection string information        #
########################################
if args.local:
    host = os.environ.get("PGHOST", "localhost")
    user = os.environ.get("PGUSER", "postgres")
    password = os.environ.get("PGPASSWORD", "divvy")
    sslmode = "disable"
else:
    host = os.environ.get("PGHOST") or "<<host>>"
    user = os.environ.get("PGUSER") or "<<user>>"
    password = os.environ.get("PGPASSWORD") or "<<password>>"
    sslmode = "require"

if "<<" in host or "<<" in user or "<<" in password:
    sys.exit("Set PGHOST / PGUSER / PGPASSWORD before running (see docstring).")

# Create a new DB
dbname = "postgres"
conn_string = "host={0} user={1} dbname={2} password={3} sslmode={4}".format(
    host, user, dbname, password, sslmode)
conn = psycopg2.connect(conn_string)
conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
print("Connection established")

cursor = conn.cursor()
cursor.execute("DROP DATABASE IF EXISTS udacityproject")
cursor.execute("CREATE DATABASE udacityproject")
conn.commit()
cursor.close()
conn.close()

# Reconnect to the new DB
dbname = "udacityproject"
conn_string = "host={0} user={1} dbname={2} password={3} sslmode={4}".format(
    host, user, dbname, password, sslmode)
conn = psycopg2.connect(conn_string)
print("Connection established")
cursor = conn.cursor()


# Helper functions
def drop_recreate(c, tablename, create):
    c.execute("DROP TABLE IF EXISTS {0};".format(tablename))
    c.execute(create)
    print("Finished creating table {0}".format(tablename))


def populate_table(c, filename, tablename):
    path = os.path.normpath(os.path.join(DATA_DIR, filename))
    if not os.path.exists(path):
        sys.exit("Missing data file: {0}\n"
                 "Unzip azure-data-warehouse-projectdatafiles.zip into {1}"
                 .format(path, os.path.normpath(DATA_DIR)))
    with open(path, "r", encoding="utf-8") as f:
        try:
            c.copy_from(f, tablename, sep=",", null="")
            conn.commit()
        except Exception as error:
            print("Error: %s" % error)
            conn.rollback()
            raise
    c.execute("SELECT count(*) FROM {0};".format(tablename))
    print("Finished populating {0} -- {1:,} rows".format(tablename, c.fetchone()[0]))


# Create Rider table
drop_recreate(cursor, "rider",
              "CREATE TABLE rider (rider_id INTEGER PRIMARY KEY, first VARCHAR(50), "
              "last VARCHAR(50), address VARCHAR(100), birthday DATE, "
              "account_start_date DATE, account_end_date DATE, is_member BOOLEAN);")
populate_table(cursor, "riders.csv", "rider")

# Create Payment table
drop_recreate(cursor, "payment",
              "CREATE TABLE payment (payment_id INTEGER PRIMARY KEY, date DATE, "
              "amount MONEY, rider_id INTEGER);")
populate_table(cursor, "payments.csv", "payment")

# Create Station table
drop_recreate(cursor, "station",
              "CREATE TABLE station (station_id VARCHAR(50) PRIMARY KEY, name VARCHAR(75), "
              "latitude FLOAT, longitude FLOAT);")
populate_table(cursor, "stations.csv", "station")

# Create Trip table
drop_recreate(cursor, "trip",
              "CREATE TABLE trip (trip_id VARCHAR(50) PRIMARY KEY, rideable_type VARCHAR(75), "
              "start_at TIMESTAMP, ended_at TIMESTAMP, start_station_id VARCHAR(50), "
              "end_station_id VARCHAR(50), rider_id INTEGER);")
populate_table(cursor, "trips.csv", "trip")

# Clean up
conn.commit()
cursor.close()
conn.close()

print("All done!")
