# Stamped scripts — the exact SQL that ran

Generated from `sql/` by `tools/configure.py`, with the placeholders replaced by
the real names from the lab session these results came from:

| placeholder | value |
|---|---|
| `<<STORAGE_ACCOUNT>>` | `divvydls303533` |
| `<<FILESYSTEM>>` | `divvyfs303533` |
| `<<EXTRACT_FOLDER>>` | `divvy` |

`sql/` holds the templates, which are the version to reuse — regenerate this
folder with:

    python tools/configure.py \
        --storage-account <account> --filesystem <container> --extract-folder <folder>

This folder is committed rather than ignored so the LOAD scripts can be read
against `screenshots/01_blob_storage_four_files.png`: the `LOCATION` in
`02`–`05` names the same four files the screenshot shows, in the same container.
A reviewer should not have to run a generator to check that.

The Azure resources these names refer to were deleted after the run, as the
project instructions require.
