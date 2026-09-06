"""
Run a .sql script against the Synapse serverless SQL pool from the command line.

Authenticates with the Azure AD access token from `az account get-access-token`,
so no SQL password is stored, typed, or passed on a command line. You must
already be logged in with `az login`.

    python tools/run_sql.py --workspace <your-workspace> --database master \
        sql_configured/load/00_create_database.sql

    python tools/run_sql.py --workspace <your-workspace> --database divvy \
        sql_configured/load/02_create_external_table_staging_rider.sql

Splits the script on GO batch separators, which the ODBC driver does not
understand, and prints every result set the script produces - so the row counts
and validation queries at the end of each script are visible without opening
Synapse Studio.
"""

import argparse
import os
import re
import struct
import subprocess
import sys
import time

try:
    import pyodbc
except ImportError:
    sys.exit("pip install pyodbc")

SQL_COPT_SS_ACCESS_TOKEN = 1256
GO = re.compile(r"^\s*GO\s*(?:--.*)?$", re.IGNORECASE)

parser = argparse.ArgumentParser()
parser.add_argument("script", nargs="+", help="one or more .sql files, run in order")
parser.add_argument("--workspace", required=True, help="Synapse workspace name")
parser.add_argument("--database", default="master")
parser.add_argument("--driver", default="ODBC Driver 17 for SQL Server")
parser.add_argument("--timeout", type=int, default=3600, help="query timeout, seconds")
parser.add_argument("--max-rows", type=int, default=25, help="rows printed per result set")
args = parser.parse_args()


def access_token():
    """Bearer token for the SQL data plane, in the packed form ODBC expects."""
    raw = subprocess.check_output(
        ["az", "account", "get-access-token",
         "--resource", "https://database.windows.net/",
         "--query", "accessToken", "-o", "tsv"],
        shell=(os.name == "nt"),
    ).decode().strip()
    b = raw.encode("utf-16-le")
    return struct.pack("<I{0}s".format(len(b)), len(b), b)


server = "{0}-ondemand.sql.azuresynapse.net".format(args.workspace)
conn_str = (
    "Driver={{{0}}};Server={1},1433;Database={2};"
    "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;"
).format(args.driver, server, args.database)

print("server   {0}".format(server))
print("database {0}".format(args.database))

conn = pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: access_token()},
                      autocommit=True)
conn.timeout = args.timeout
cur = conn.cursor()

failures = 0

for path in args.script:
    if not os.path.exists(path):
        print("\n!! missing: {0}".format(path))
        failures += 1
        continue

    with open(path, "r", encoding="utf-8-sig") as fh:
        lines = fh.read().splitlines()

    batches, buf = [], []
    for line in lines:
        if GO.match(line):
            batches.append("\n".join(buf))
            buf = []
        else:
            buf.append(line)
    batches.append("\n".join(buf))
    batches = [b for b in batches if b.strip()]

    print("\n" + "=" * 74)
    print("{0}   ({1} batch(es))".format(os.path.basename(path), len(batches)))
    print("=" * 74)

    for i, batch in enumerate(batches, 1):
        started = time.time()
        try:
            cur.execute(batch)
        except Exception as exc:
            failures += 1
            head = " ".join(batch.split())[:110]
            print("\n  batch {0} FAILED  ({1})".format(i, head))
            print("    {0}".format(str(exc).replace("\n", "\n    ")))
            continue

        # Walk every result set the batch produced.
        while True:
            if cur.description:
                cols = [d[0] for d in cur.description]
                rows = cur.fetchmany(args.max_rows)
                if rows:
                    widths = [max(len(str(c)),
                                  max((len(str(r[j])) for r in rows), default=0))
                              for j, c in enumerate(cols)]
                    widths = [min(w, 34) for w in widths]
                    print("\n  " + "  ".join(str(c)[:34].ljust(w)
                                             for c, w in zip(cols, widths)))
                    print("  " + "  ".join("-" * w for w in widths))
                    for r in rows:
                        print("  " + "  ".join(str(v)[:34].ljust(w)
                                               for v, w in zip(r, widths)))
                    if len(rows) == args.max_rows:
                        print("  ... (truncated at --max-rows {0})".format(args.max_rows))
            if not cur.nextset():
                break
        print("  batch {0} ok  ({1:.1f}s)".format(i, time.time() - started))

conn.close()
print("\n" + ("ALL SCRIPTS OK" if not failures
              else "{0} batch failure(s)".format(failures)))
sys.exit(1 if failures else 0)
