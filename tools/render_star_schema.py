"""
Render docs/star_schema.png - the Divvy warehouse star schema.

Laid out by hand rather than by an auto-layout tool, because the point of a star
schema is the shape: two fact tables in the middle, the two conformed dimensions
(dim_date, dim_rider) sitting between them where both can reach them, and the
trip-only dimensions out on the left.

    python tools/render_star_schema.py

Needs matplotlib. Writes a 200 dpi PNG next to the design doc.
"""

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "docs", "star_schema.png"))

# ----------------------------------------------------------------- palette --
INK = "#1f2430"
MUTED = "#6b7280"
LINE = "#94a3b8"
STYLES = {
    "fact": dict(head="#1d4e89", body="#eef4fb", edge="#1d4e89"),
    "dim": dict(head="#2f6f4e", body="#edf6f0", edge="#2f6f4e"),
    "extra": dict(head="#8a5216", body="#fdf3e5", edge="#8a5216"),
}
KEYC = {"PK": "#b45309", "FK": "#1d4e89", "": MUTED}

ROW_H = 0.26
HEAD_H = 0.56
PAD = 0.16

# ------------------------------------------------------------------ tables --
# (name, kind, centre-x, top-y, width, [(key, column, type), ...])
TABLES = [
    ("dim_time", "dim", 3.0, 14.0, 4.2, [
        ("PK", "time_key", "tinyint"),
        ("", "hour_24", "tinyint"),
        ("", "hour_label", "varchar(5)"),
        ("", "time_of_day", "varchar(9)"),
        ("", "is_peak_commute", "bit"),
    ]),
    ("dim_station", "dim", 3.0, 8.0, 4.2, [
        ("PK", "station_id", "varchar(50)"),
        ("", "station_name", "varchar(75)"),
        ("", "latitude", "float"),
        ("", "longitude", "float"),
    ]),
    ("dim_date", "dim", 12.2, 14.8, 4.2, [
        ("PK", "date_key", "int"),
        ("", "full_date", "date"),
        ("", "year", "smallint"),
        ("", "quarter", "tinyint"),
        ("", "month", "tinyint"),
        ("", "month_name", "varchar(10)"),
        ("", "day_of_month", "tinyint"),
        ("", "day_of_week", "tinyint"),
        ("", "day_name", "varchar(9)"),
        ("", "week_of_year", "tinyint"),
        ("", "is_weekend", "bit"),
        ("", "year_month", "varchar(7)"),
        ("", "year_quarter", "varchar(7)"),
        ("", "month_start_date", "date"),
    ]),
    ("dim_rider", "dim", 12.2, 4.4, 4.2, [
        ("PK", "rider_id", "int"),
        ("", "first_name", "varchar(50)"),
        ("", "last_name", "varchar(50)"),
        ("", "address", "varchar(100)"),
        ("", "birthday", "date"),
        ("", "account_start_date", "date"),
        ("", "account_end_date", "date"),
        ("", "is_member", "bit"),
        ("", "rider_type", "varchar(6)"),
        ("", "age_at_account_start", "int"),
        ("", "age_band_at_account_start", "varchar(8)"),
        ("", "account_tenure_months", "int"),
        ("", "is_account_open", "bit"),
    ]),
    ("fact_trip", "fact", 9.0, 9.6, 4.9, [
        ("PK", "trip_id", "varchar(50)"),
        ("FK", "rider_id", "int"),
        ("FK", "start_station_id", "varchar(50)"),
        ("FK", "end_station_id", "varchar(50)"),
        ("FK", "start_date_key", "int"),
        ("FK", "end_date_key", "int"),
        ("FK", "start_time_key", "tinyint"),
        ("", "rideable_type", "varchar(75)"),
        ("", "started_at", "datetime2"),
        ("", "ended_at", "datetime2"),
        ("", "duration_seconds", "int"),
        ("", "duration_minutes", "decimal(10,2)"),
        ("", "rider_age_at_trip", "int"),
        ("", "rider_age_band_at_trip", "varchar(8)"),
        ("", "is_member", "bit"),
        ("", "rider_type", "varchar(7)"),
    ]),
    ("fact_payment", "fact", 16.8, 9.6, 4.9, [
        ("PK", "payment_id", "int"),
        ("FK", "rider_id", "int"),
        ("FK", "date_key", "int"),
        ("", "payment_date", "date"),
        ("", "amount", "decimal(10,2)"),
        ("", "rider_age_at_payment", "int"),
    ]),
    ("fact_rider_monthly", "extra", 18.4, 6.5, 4.9, [
        ("FK", "rider_id", "int"),
        ("FK", "month_date_key", "int"),
        ("", "month_start_date", "date"),
        ("", "year_month", "varchar(7)"),
        ("", "year", "smallint"),
        ("", "quarter", "tinyint"),
        ("", "month", "tinyint"),
        ("", "rides_in_month", "int"),
        ("", "ride_minutes_in_month", "decimal(12,2)"),
        ("", "payments_in_month", "int"),
        ("", "amount_paid_in_month", "decimal(12,2)"),
    ]),
    ("agg_rider_spend_vs_rides", "extra", 24.9, 6.5, 5.1, [
        ("PK", "rider_id", "int"),
        ("", "rider_type", "varchar(6)"),
        ("", "is_member", "bit"),
        ("", "age_at_account_start", "int"),
        ("", "age_band_at_account_start", "varchar(8)"),
        ("", "first_active_month", "date"),
        ("", "last_active_month", "date"),
        ("", "months_observed", "int"),
        ("", "months_active", "int"),
        ("", "total_rides", "int"),
        ("", "total_ride_minutes", "decimal(12,2)"),
        ("", "total_paid", "decimal(12,2)"),
        ("", "avg_rides_per_month", "decimal(10,2)"),
        ("", "avg_spend_per_month", "decimal(12,2)"),
        ("", "spend_per_ride", "decimal(12,2)"),
        ("", "rides_per_month_band", "varchar(12)"),
    ]),
]

fig, ax = plt.subplots(figsize=(28.1, 17.2))
ax.set_xlim(0, 28.1)
ax.set_ylim(-1.8, 15.4)
ax.axis("off")
fig.patch.set_facecolor("white")

box = {}


def draw_table(name, kind, cx, top, width, rows):
    s = STYLES[kind]
    height = HEAD_H + len(rows) * ROW_H + PAD
    left, right = cx - width / 2.0, cx + width / 2.0
    bottom = top - height

    ax.add_patch(FancyBboxPatch(
        (left, bottom), width, height,
        boxstyle="round,pad=0,rounding_size=0.12",
        facecolor=s["body"], edgecolor=s["edge"], linewidth=1.4, zorder=3))
    ax.add_patch(FancyBboxPatch(
        (left, top - HEAD_H), width, HEAD_H,
        boxstyle="round,pad=0,rounding_size=0.12",
        facecolor=s["head"], edgecolor=s["head"], linewidth=1.4, zorder=4))
    # square off the underside of the rounded header
    ax.add_patch(FancyBboxPatch(
        (left, top - HEAD_H), width, HEAD_H / 2.0,
        boxstyle="square,pad=0",
        facecolor=s["head"], edgecolor=s["head"], linewidth=0, zorder=4))

    ax.text(cx, top - HEAD_H / 2.0, name, ha="center", va="center",
            color="white", fontsize=12.5, fontweight="bold",
            family="DejaVu Sans", zorder=5)

    y = top - HEAD_H - ROW_H / 2.0 - 0.03
    for key, col, typ in rows:
        if key:
            ax.text(left + 0.14, y, key, ha="left", va="center",
                    fontsize=6.4, color=KEYC[key], fontweight="bold",
                    family="DejaVu Sans", zorder=5)
        ax.text(left + 0.52, y, col, ha="left", va="center", fontsize=8.1,
                color=INK, family="DejaVu Sans Mono",
                fontweight="bold" if key else "normal", zorder=5)
        ax.text(right - 0.14, y, typ, ha="right", va="center", fontsize=6.9,
                color=MUTED, family="DejaVu Sans Mono", zorder=5)
        y -= ROW_H

    box[name] = dict(cx=cx, left=left, right=right, top=top, bottom=bottom)


for spec in TABLES:
    draw_table(*spec)


def link(p0, p1, label=None, dashed=False, lx=None, ly=None):
    ax.add_patch(FancyArrowPatch(
        p0, p1, arrowstyle="-", linewidth=1.6 if not dashed else 1.3,
        color=LINE if not dashed else "#c39a63",
        linestyle="--" if dashed else "-",
        shrinkA=0, shrinkB=0, zorder=2))
    if label:
        mx = lx if lx is not None else (p0[0] + p1[0]) / 2.0
        my = ly if ly is not None else (p0[1] + p1[1]) / 2.0
        ax.text(mx, my, label, ha="center", va="center", fontsize=7.4,
                color="#4b5563", family="DejaVu Sans Mono", zorder=6,
                bbox=dict(boxstyle="round,pad=0.22", facecolor="white",
                          edgecolor="none", alpha=0.94))


t, p = box["fact_trip"], box["fact_payment"]
d, r = box["dim_date"], box["dim_rider"]
tm, st = box["dim_time"], box["dim_station"]
frm, agg = box["fact_rider_monthly"], box["agg_rider_spend_vs_rides"]

# trip-only dimensions
link((tm["cx"] + 1.1, tm["bottom"]), (t["left"], t["top"] - 0.7), "start_time_key")
link((st["right"], st["top"] - 0.35), (t["left"], t["top"] - 2.35), "start_station_id",
     lx=5.83, ly=7.46)
link((st["right"], st["top"] - 0.95), (t["left"], t["top"] - 2.95), "end_station_id",
     lx=5.83, ly=6.86)

# conformed dimensions - reach both facts
link((d["cx"] - 1.5, d["bottom"]), (t["right"] - 0.6, t["top"]),
     "start_date_key\nend_date_key", lx=10.0, ly=10.15)
link((d["cx"] + 1.5, d["bottom"]), (p["left"] + 0.9, p["top"]), "date_key",
     lx=15.2, ly=10.15)
link((r["cx"] - 1.4, r["top"]), (t["cx"] + 0.6, t["bottom"]), "rider_id",
     lx=10.9, ly=4.30)
link((r["cx"] + 1.6, r["top"]), (p["left"] + 0.4, p["bottom"]), "rider_id",
     lx=14.6, ly=6.1)

# extra credit derivations
link((t["right"], t["bottom"] + 0.9), (frm["left"], frm["top"] - 0.9),
     "rides", dashed=True, lx=13.0, ly=5.35)
link((p["cx"] + 0.9, p["bottom"]), (frm["cx"] + 0.9, frm["top"]),
     "payments", dashed=True, lx=18.5, ly=7.02)
link((frm["right"], 4.6), (agg["left"], 4.6),
     "rolled up", dashed=True, lx=21.6, ly=4.6)

# ------------------------------------------------------------------ labels --
ax.text(0.55, 15.25, "Divvy Bikeshare - Star Schema", fontsize=25,
        fontweight="bold", color=INK, family="DejaVu Sans", va="top")
ax.text(0.55, 14.55,
        "Azure Synapse serverless SQL pool - every table materialised with CETAS",
        fontsize=12.5, color=MUTED, family="DejaVu Sans", va="top")

legend = [("fact", "Fact table"), ("dim", "Dimension"),
          ("extra", "Extra credit (derived)")]
lx0 = 22.1
for i, (kind, text) in enumerate(legend):
    ly0 = 15.05 - i * 0.52
    ax.add_patch(FancyBboxPatch(
        (lx0, ly0 - 0.17), 0.42, 0.28,
        boxstyle="round,pad=0,rounding_size=0.05",
        facecolor=STYLES[kind]["head"], edgecolor=STYLES[kind]["edge"], zorder=5))
    ax.text(lx0 + 0.62, ly0 - 0.03, text, fontsize=11, color=INK,
            family="DejaVu Sans", va="center", zorder=5)

ax.text(0.55, -0.55,
        "dim_date and dim_rider are conformed: both fact tables key to them, so "
        "trip behaviour and payment behaviour can be compared on the same "
        "calendar and the same rider.",
        fontsize=11, color=MUTED, family="DejaVu Sans", va="top")
ax.text(0.55, -1.05,
        "dim_station role-plays twice on fact_trip (start and end). Age at time "
        "of trip is a fact, not a rider attribute - it differs on every ride.",
        fontsize=11, color=MUTED, family="DejaVu Sans", va="top")

fig.tight_layout(pad=0.6)
fig.savefig(OUT, dpi=200, facecolor="white", bbox_inches="tight")
print("wrote {0}".format(OUT))
