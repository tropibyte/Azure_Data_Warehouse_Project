# Divvy warehouse — findings

Every number below was produced by `local/validate_with_duckdb.py` against the
full dataset **and independently reproduced by the Synapse serverless warehouse**
on 6 Sep 2026. The two agree to the cent: day-of-week averages, the age-band
spend ladder, and the whole extra-credit table match exactly.

**Dataset:** 75,000 riders · 838 stations · 4,584,921 trips · 1,946,607 payments
· $19,457,105.25 of payments, reconciling to the cent between staging,
`fact_payment`, `fact_rider_monthly` and `agg_rider_spend_vs_rides`.

---

## 1. Time spent per ride

### By day of week — weekends are leisure, weekdays are commuting

| Day | Rides | Avg minutes |
|---|---:|---:|
| Sunday | 713,177 | **24.87** |
| Saturday | 822,169 | 23.66 |
| Monday | 575,943 | 19.06 |
| Friday | 653,236 | 18.70 |
| Tuesday | 604,661 | 17.13 |
| Thursday | 598,160 | 16.70 |
| Wednesday | 616,182 | **16.63** |

A Sunday ride runs 50% longer than a Wednesday ride. The weekday floor sits at
16–19 minutes with very little spread, which is what a fixed commute looks like.

### By time of day

| Time of day | Rides | Avg minutes |
|---|---:|---:|
| Afternoon (12–16) | 1,553,085 | 21.70 |
| Night (22–04) | 405,531 | 21.54 |
| Evening (17–21) | 1,535,248 | 19.17 |
| Morning (05–11) | 1,089,664 | **17.53** |

Morning is both the second-busiest window and the shortest ride — the same
commuting signal from the other direction. Night rides are few but long.

### By start station — the long rides start at the edges

| Start station | Rides | Avg minutes |
|---|---:|---:|
| Cicero Ave & Quincy St | 76 | 84.74 |
| Yates Blvd & 75th St | 181 | 77.54 |
| Kenton Ave & Madison St | 84 | 68.52 |
| Western Ave & 111th St | 164 | 60.97 |
| Central Park Blvd & 5th Ave | 239 | 60.51 |

Every one of these is an outlying, low-volume station — 76 to 239 rides against
a system in the millions. Stations with under 50 rides are excluded, because
below that a single unreturned bike moves the average by twenty minutes.

### By rider age and rider type

Ride length is essentially **flat across age and membership**: every age band
sits between 19.2 and 20.5 minutes, members and casual riders alike. The
Under-18 band is marginally the longest at 20.4, the 45–54 members the shortest
at 19.2.

This is a genuine negative result and worth stating plainly in the write-up:
*when* someone rides predicts ride length far better than *who* they are. Age
and membership are not useful levers here; day of week and hour are.

---

## 2. Money spent

### Per year — near-linear growth, then a partial year

| Year | Payments | Total |
|---|---:|---:|
| 2013 | 5,351 | $53,693.34 |
| 2014 | 22,608 | $227,402.95 |
| 2015 | 47,448 | $477,233.22 |
| 2016 | 82,480 | $825,120.81 |
| 2017 | 130,936 | $1,308,372.54 |
| 2018 | 200,312 | $2,000,105.50 |
| 2019 | 298,165 | $2,978,658.79 |
| 2020 | 431,630 | $4,315,449.40 |
| 2021 | 608,550 | $6,081,098.25 |
| 2022 | 119,127 | $1,189,970.45 |

2022 is a partial year, not a collapse — do not read it as a trend.

### Per member, by age at account start

| Age band at account start | Members | Total | Per member |
|---|---:|---:|---:|
| Under 18 | 7,522 | $2,559,105 | **$340.22** |
| 18–24 | 13,425 | $3,278,754 | $244.23 |
| 25–34 | 18,814 | $4,317,093 | $229.46 |
| 35–44 | 11,955 | $2,529,567 | $211.59 |
| 45–54 | 5,236 | $1,046,601 | $199.89 |
| 55–64 | 1,420 | $268,182 | $188.86 |
| 65+ | 273 | $39,375 | **$144.23** |

Spend per member falls monotonically with age at signup — the youngest cohort
pays 2.4x what the oldest does. Since ride length barely varies by age, this is
about account longevity, not usage intensity.

---

## 3. Extra credit — spend per member vs rides per month

| Rides/month band | Members | Avg rides/mo | Avg lifetime paid | Avg monthly spend | Avg spend per ride |
|---|---:|---:|---:|---:|---:|
| 0 (no rides) | 29,179 | 0.00 | $239.78 | $9.00 | — |
| Under 1 | 10,347 | 0.31 | $296.87 | $7.62 | $90.17 |
| 1 to 2 | 3,543 | 1.43 | $289.96 | $7.10 | $5.14 |
| 2 to 4 | 4,290 | 2.90 | $270.45 | $7.14 | $2.56 |
| 4 to 8 | 4,700 | 5.71 | $198.35 | $6.64 | $1.21 |
| 8 to 16 | 4,197 | 11.30 | $136.42 | $6.05 | $0.56 |
| 16+ | 3,162 | 27.56 | $87.93 | $5.14 | $0.22 |

### Two findings, one trap

**Finding 1 — the membership pays for itself somewhere around one ride a week.**
Cost per ride collapses from $90.17 for the barely-active to $0.22 for the
heaviest users, a 400x spread. Monthly spend also declines with frequency
($7.62 → $5.14), so the heaviest riders are not merely getting more value per
dollar, they are paying fewer dollars.

**Finding 2 — 29,179 members, roughly half of all members, never took a single
ride, and paid about $7.0M doing it.** They sit at a flat $9.00/month for an
average of 26.6 months. That is the largest single fact the extra-credit table
surfaces, and it is invisible in either fact table alone: `fact_payment` has no
concept of a ride, and `fact_trip` has no row for a rider who never rode. Only
the conformed rider-month grain shows an account paying into months with zero
trips.

**The trap — lifetime spend falls as ride frequency rises, and that is an
artifact.** It looks like heavy riders are worth less. They are not:

| Rides/month band | Avg months observed | Avg lifetime paid | Avg monthly spend |
|---|---:|---:|---:|
| Under 1 | 36.6 | $296.87 | $7.62 |
| 1 to 2 | 36.6 | $289.96 | $7.10 |
| 2 to 4 | 34.6 | $270.45 | $7.14 |
| 4 to 8 | 26.6 | $198.35 | $6.64 |
| 8 to 16 | 20.0 | $136.42 | $6.05 |
| 16+ | 15.4 | $87.93 | $5.14 |

Observation window drops from 36.6 months to 15.4 as frequency rises. The
heaviest riders joined most recently, so lifetime spend is measuring account
age, not behaviour. Use the rate measures — `avg_spend_per_month` and
`spend_per_ride` — or band on `months_observed`, which the last extra-credit
query in `business_questions.sql` does.

---

## Data quality

| Check | Result |
|---|---|
| Trips dropped for unparseable timestamps | 0 of 4,584,921 |
| Payments with unparseable amount | 0 of 1,946,607 |
| Orphan rider / start station / end station keys | 0 |
| Duplicate `trip_id` / `payment_id` | 0 |
| Trips missing rider age | 0 |
| Money: staging vs fact | $19,457,105.25 = $19,457,105.25 |
| Rides: fact vs monthly vs agg | 4,584,921 = 4,584,921 = 4,584,921 |
| **Trips with negative duration** | **116** — `ended_at` precedes `started_at` |
| **Trips over 24 hours** | **1,277** — unreturned bikes, real Divvy behaviour |

The 1,393 anomalous rows are kept in `fact_trip` rather than deleted; every
duration query filters `duration_seconds BETWEEN 0 AND 86400` so the rows stay
inspectable. Deleting them at load time would hide a real operational signal —
the over-24-hour trips are exactly the bikes that went missing.
