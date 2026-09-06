# Screenshots — what to capture and how

Two screenshots can only be taken while the lab session is live. Take them at
the moment the runbook says to, not at the end — if the session expires you
cannot get them back without spending another of your ten attempts.

## How to capture on Windows 11

`Win` + `Shift` + `S` → drag a rectangle → click the notification toast →
`Ctrl` + `S` → save here as PNG.

Or `Win` + `PrtScn` saves the whole screen straight to `Pictures\Screenshots\`.

Before capturing:

* Maximise the browser window.
* Collapse the Synapse Studio left nav (the `«` chevron) so the content pane is
  wider and the filenames are not truncated.
* Set browser zoom to 100–110%. A reviewer has to read the filenames; a 67%-zoom
  capture of a 4K monitor is unreadable when scaled into a PDF.
* Keep the Azure/Synapse chrome in frame — the workspace name in the top bar is
  what makes it evidence rather than a picture of a file list.
* **Do not capture the Udacity workspace credentials pane.** The lab page shows
  a live username and password; it does not belong in a submission.

---

## Required

### `01_blob_storage_four_files.png`

**The Extract-step rubric evidence.** Must show four text files.

Synapse Studio → **Data** (left rail) → **Linked** tab → **Azure Data Lake
Storage Gen2** → your workspace storage account → your filesystem → the `divvy`
folder.

Capture must include:

- the four files: `public.rider.txt`, `public.payment.txt`,
  `public.station.txt`, `public.trip.txt`
- the breadcrumb / folder path
- the Name, Last Modified and Size columns

The Azure Portal route works equally well: **Storage account → Containers →
your container → divvy**.

If the copy tool named the files differently, capture whatever it actually
produced — and update the `LOCATION` lines in `sql/load/02` – `05` to match
before running them.

### `02_cetas_results.png`

**Transform-step evidence.** A CETAS script with its output.

Synapse Studio → **Develop** → the `20_cetas_fact_trip` script tab, after it has
run. Capture must include:

- the `CREATE EXTERNAL TABLE ... AS SELECT` statement
- the **Results** grid with rows in it
- the green *Query executed successfully* line at the bottom
- the **Connect to: Built-in** and **Use database: divvy** dropdowns in the
  toolbar — this is what proves it ran on the serverless pool

---

## Worth adding — cheap, and they strengthen the submission

### `03_warehouse_folders.png`

Same data lake browser as screenshot 1, but the `warehouse/` folder. Shows the
eight CETAS output folders: `dim_date`, `dim_time`, `dim_rider`, `dim_station`,
`fact_trip`, `fact_payment`, `fact_rider_monthly`, `agg_rider_spend_vs_rides`.
Evidence that the transform actually wrote files, not just metadata.

### `04_validation_zero_defects.png`

The results grid from `40_validate_star_schema.sql` showing every `defects`
count at 0 and the money reconciliation matching. This is the single most
persuasive screenshot in the set — it is the difference between "the scripts
ran" and "the warehouse is correct".

### `05_extra_credit_result.png`

The results grid from the extra-credit query — spend per member by rides-per-month
band. It is the payoff for the whole extra-credit build, and worth showing rather
than only describing.

### `06_staging_row_counts.png`

The row counts from the four load scripts: 75,000 / 1,946,607 / 838 / 4,584,921.
Proves the extract carried everything across.

---

## Checklist

- [ ] `01_blob_storage_four_files.png` — **required**
- [ ] `02_cetas_results.png` — **required**
- [ ] `03_warehouse_folders.png`
- [ ] `04_validation_zero_defects.png`
- [ ] `05_extra_credit_result.png`
- [ ] `06_staging_row_counts.png`

`SUBMISSION.md` references `01` and `02` by name. If you rename anything, update
the reference there too.
