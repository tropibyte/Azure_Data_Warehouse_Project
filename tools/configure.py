"""
Stamp your Azure storage names into every SQL script, so you paste finished SQL
into Synapse instead of hand-editing eight files while the lab clock runs.

    python tools/configure.py \
        --storage-account mydls20250906 \
        --filesystem      mydlsfs20250906 \
        --extract-folder  divvy

Writes to sql_configured/ and leaves sql/ untouched, so you can re-run it when
the next lab session hands you a different storage account.
"""

import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "sql")
DST = os.path.join(ROOT, "sql_configured")

parser = argparse.ArgumentParser()
parser.add_argument("--storage-account", required=True,
                    help="ADLS Gen2 storage account name, e.g. mydls20250906")
parser.add_argument("--filesystem", required=True,
                    help="container / filesystem name, e.g. mydlsfs20250906")
parser.add_argument("--extract-folder", default="divvy",
                    help="folder the EXTRACT step wrote the four .txt files into")
args = parser.parse_args()

REPLACEMENTS = {
    "<<STORAGE_ACCOUNT>>": args.storage_account,
    "<<FILESYSTEM>>": args.filesystem,
    "<<EXTRACT_FOLDER>>": args.extract_folder.strip("/"),
}

if not os.path.isdir(SRC):
    sys.exit("Cannot find {0}".format(SRC))

if os.path.isdir(DST):
    shutil.rmtree(DST)

stamped = 0
remaining = []

for dirpath, _dirnames, filenames in os.walk(SRC):
    rel = os.path.relpath(dirpath, SRC)
    out_dir = os.path.join(DST, rel) if rel != "." else DST
    os.makedirs(out_dir, exist_ok=True)
    for name in filenames:
        if not name.lower().endswith(".sql"):
            continue
        with open(os.path.join(dirpath, name), "r", encoding="utf-8") as fh:
            text = fh.read()
        for token, value in REPLACEMENTS.items():
            text = text.replace(token, value)
        if "<<" in text:
            remaining.append(os.path.join(rel, name))
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as fh:
            fh.write(text)
        stamped += 1

print("Stamped {0} script(s) into {1}".format(stamped, DST))
for token, value in REPLACEMENTS.items():
    print("  {0:22s} -> {1}".format(token, value))

if remaining:
    print("\nWARNING: unreplaced << >> placeholders still present in:")
    for name in remaining:
        print("  " + name)
    sys.exit(1)
