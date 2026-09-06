/* =====================================================================
   ANALYSIS - every business outcome in the project brief, answered.
   Run against the serverless pool after the CETAS scripts have completed.

   Trips longer than 24 hours are excluded from duration averages. They are
   real (an unreturned bike), but a handful of 300-hour rides drags every
   average far enough to make the answers useless. The filter is stated in each
   query rather than baked into fact_trip, so the outlier rows stay available.
   ===================================================================== */

-------------------------------------------------------------------------
-- OUTCOME 1a - time spent per ride, by DAY OF WEEK
-------------------------------------------------------------------------
SELECT
    d.[day_of_week],
    d.[day_name],
    COUNT(*)                              AS rides,
    AVG(f.[duration_minutes])             AS avg_minutes,
    MIN(f.[duration_minutes])             AS min_minutes,
    MAX(f.[duration_minutes])             AS max_minutes
FROM [dbo].[fact_trip] AS f
JOIN [dbo].[dim_date]  AS d ON d.[date_key] = f.[start_date_key]
WHERE f.[duration_seconds] BETWEEN 0 AND 86400
GROUP BY d.[day_of_week], d.[day_name]
ORDER BY d.[day_of_week];
GO

-------------------------------------------------------------------------
-- OUTCOME 1a - time spent per ride, by TIME OF DAY
-------------------------------------------------------------------------
SELECT
    t.[time_of_day],
    t.[is_peak_commute],
    COUNT(*)                  AS rides,
    AVG(f.[duration_minutes]) AS avg_minutes
FROM [dbo].[fact_trip] AS f
JOIN [dbo].[dim_time]  AS t ON t.[time_key] = f.[start_time_key]
WHERE f.[duration_seconds] BETWEEN 0 AND 86400
GROUP BY t.[time_of_day], t.[is_peak_commute]
ORDER BY avg_minutes DESC;
GO

-- Hour-by-hour, weekday against weekend - the shape most of the interesting
-- commuting behaviour shows up in.
SELECT
    t.[hour_label],
    AVG(CASE WHEN d.[is_weekend] = 0 THEN f.[duration_minutes] END) AS avg_minutes_weekday,
    AVG(CASE WHEN d.[is_weekend] = 1 THEN f.[duration_minutes] END) AS avg_minutes_weekend,
    COUNT(*) AS rides
FROM [dbo].[fact_trip] AS f
JOIN [dbo].[dim_time]  AS t ON t.[time_key] = f.[start_time_key]
JOIN [dbo].[dim_date]  AS d ON d.[date_key] = f.[start_date_key]
WHERE f.[duration_seconds] BETWEEN 0 AND 86400
GROUP BY t.[hour_label], t.[hour_24]
ORDER BY t.[hour_24];
GO

-------------------------------------------------------------------------
-- OUTCOME 1b - longest rides by START station
-------------------------------------------------------------------------
SELECT TOP 25
    s.[station_id],
    s.[station_name],
    COUNT(*)                  AS rides,
    AVG(f.[duration_minutes]) AS avg_minutes
FROM [dbo].[fact_trip]   AS f
JOIN [dbo].[dim_station] AS s ON s.[station_id] = f.[start_station_id]
WHERE f.[duration_seconds] BETWEEN 0 AND 86400
GROUP BY s.[station_id], s.[station_name]
HAVING COUNT(*) >= 50           -- ignore stations too small to mean anything
ORDER BY avg_minutes DESC;
GO

-------------------------------------------------------------------------
-- OUTCOME 1b - longest rides by START/END station PAIR
--   dim_station role-playing twice in one query
-------------------------------------------------------------------------
SELECT TOP 25
    ss.[station_name] AS start_station,
    es.[station_name] AS end_station,
    COUNT(*)                  AS rides,
    AVG(f.[duration_minutes]) AS avg_minutes
FROM [dbo].[fact_trip]   AS f
JOIN [dbo].[dim_station] AS ss ON ss.[station_id] = f.[start_station_id]
JOIN [dbo].[dim_station] AS es ON es.[station_id] = f.[end_station_id]
WHERE f.[duration_seconds] BETWEEN 0 AND 86400
GROUP BY ss.[station_name], es.[station_name]
HAVING COUNT(*) >= 25
ORDER BY avg_minutes DESC;
GO

-------------------------------------------------------------------------
-- OUTCOME 1c - time spent per ride, by RIDER AGE AT TIME OF THE RIDE
-------------------------------------------------------------------------
SELECT
    f.[rider_age_band_at_trip],
    COUNT(*)                     AS rides,
    AVG(f.[duration_minutes])    AS avg_minutes,
    AVG(CAST(f.[rider_age_at_trip] AS FLOAT)) AS avg_age
FROM [dbo].[fact_trip] AS f
WHERE f.[duration_seconds] BETWEEN 0 AND 86400
GROUP BY f.[rider_age_band_at_trip]
ORDER BY MIN(f.[rider_age_at_trip]);
GO

-------------------------------------------------------------------------
-- OUTCOME 1d - time spent per ride, MEMBER vs CASUAL
--   crossed with age band, which is where the real story usually is
-------------------------------------------------------------------------
SELECT
    f.[rider_type],
    f.[rider_age_band_at_trip],
    COUNT(*)                  AS rides,
    AVG(f.[duration_minutes]) AS avg_minutes
FROM [dbo].[fact_trip] AS f
WHERE f.[duration_seconds] BETWEEN 0 AND 86400
GROUP BY f.[rider_type], f.[rider_age_band_at_trip]
ORDER BY f.[rider_type], MIN(f.[rider_age_at_trip]);
GO

-------------------------------------------------------------------------
-- OUTCOME 2a - money spent per MONTH, QUARTER, YEAR
-------------------------------------------------------------------------
SELECT d.[year],
       COUNT(*)      AS payments,
       SUM(p.[amount]) AS total_amount
FROM [dbo].[fact_payment] AS p
JOIN [dbo].[dim_date]     AS d ON d.[date_key] = p.[date_key]
GROUP BY d.[year]
ORDER BY d.[year];
GO

SELECT d.[year_quarter],
       COUNT(*)        AS payments,
       SUM(p.[amount]) AS total_amount
FROM [dbo].[fact_payment] AS p
JOIN [dbo].[dim_date]     AS d ON d.[date_key] = p.[date_key]
GROUP BY d.[year_quarter]
ORDER BY d.[year_quarter];
GO

SELECT d.[year_month],
       COUNT(*)        AS payments,
       SUM(p.[amount]) AS total_amount,
       AVG(p.[amount]) AS avg_payment
FROM [dbo].[fact_payment] AS p
JOIN [dbo].[dim_date]     AS d ON d.[date_key] = p.[date_key]
GROUP BY d.[year_month]
ORDER BY d.[year_month];
GO

-------------------------------------------------------------------------
-- OUTCOME 2b - money spent per member, by AGE AT ACCOUNT START
-------------------------------------------------------------------------
SELECT
    r.[age_band_at_account_start],
    COUNT(DISTINCT r.[rider_id]) AS riders,
    SUM(p.[amount])              AS total_amount,
    SUM(p.[amount]) / COUNT(DISTINCT r.[rider_id]) AS amount_per_rider
FROM [dbo].[fact_payment] AS p
JOIN [dbo].[dim_rider]    AS r ON r.[rider_id] = p.[rider_id]
WHERE r.[is_member] = 1
GROUP BY r.[age_band_at_account_start]
ORDER BY MIN(r.[age_at_account_start]);
GO

-------------------------------------------------------------------------
-- OUTCOME 3 - EXTRA CREDIT
--   money spent per member, by how many rides they average per month
-------------------------------------------------------------------------
SELECT
    a.[rides_per_month_band],
    COUNT(*)                       AS riders,
    AVG(a.[avg_rides_per_month])   AS avg_rides_per_month,
    SUM(a.[total_paid])            AS total_paid,
    AVG(a.[total_paid])            AS avg_lifetime_paid_per_rider,
    AVG(a.[avg_spend_per_month])   AS avg_monthly_spend,
    AVG(a.[spend_per_ride])        AS avg_spend_per_ride
FROM [dbo].[agg_rider_spend_vs_rides] AS a
WHERE a.[is_member] = 1
GROUP BY a.[rides_per_month_band]
ORDER BY MIN(a.[avg_rides_per_month]);
GO

-- Same question, members against casual riders, to show whether the
-- relationship between ride frequency and spend differs by rider type.
SELECT
    a.[rider_type],
    a.[rides_per_month_band],
    COUNT(*)                     AS riders,
    AVG(a.[avg_spend_per_month]) AS avg_monthly_spend,
    AVG(a.[spend_per_ride])      AS avg_spend_per_ride
FROM [dbo].[agg_rider_spend_vs_rides] AS a
GROUP BY a.[rider_type], a.[rides_per_month_band]
ORDER BY a.[rider_type], MIN(a.[avg_rides_per_month]);
GO

-- OUTCOME 3, controlled for tenure.
--
-- The query above shows lifetime spend FALLING as ride frequency rises, which
-- reads backwards until you look at months_observed: the heaviest riders joined
-- most recently, so they have had fewer months in which to pay. Lifetime spend
-- is measuring account age, not ride behaviour.
--
-- Two corrections, both of which belong in the write-up:
--   1. compare avg_spend_per_month and spend_per_ride, which are rate measures
--      and therefore tenure-neutral;
--   2. hold tenure constant by banding on months_observed.
SELECT
    CASE WHEN a.[months_observed] < 12 THEN 'under 1 year'
         WHEN a.[months_observed] < 24 THEN '1-2 years'
         WHEN a.[months_observed] < 36 THEN '2-3 years'
         ELSE '3+ years' END              AS tenure_band,
    a.[rides_per_month_band],
    COUNT(*)                              AS riders,
    AVG(a.[total_paid])                   AS avg_lifetime_paid,
    AVG(a.[avg_spend_per_month])          AS avg_monthly_spend,
    AVG(a.[spend_per_ride])               AS avg_spend_per_ride
FROM [dbo].[agg_rider_spend_vs_rides] AS a
WHERE a.[is_member] = 1
GROUP BY
    CASE WHEN a.[months_observed] < 12 THEN 'under 1 year'
         WHEN a.[months_observed] < 24 THEN '1-2 years'
         WHEN a.[months_observed] < 36 THEN '2-3 years'
         ELSE '3+ years' END,
    a.[rides_per_month_band]
ORDER BY MIN(a.[months_observed]), MIN(a.[avg_rides_per_month]);
GO

-- Members who pay every month and never ride. In this dataset that is roughly
-- 29,000 accounts and about 7.0M dollars of revenue - the single largest
-- finding the extra-credit table surfaces, and invisible without it.
SELECT
    COUNT(*)               AS riders,
    SUM(a.[total_paid])    AS revenue,
    AVG(a.[months_observed]) AS avg_months_observed
FROM [dbo].[agg_rider_spend_vs_rides] AS a
WHERE a.[is_member] = 1 AND a.[total_rides] = 0;
GO

-- The heavy users: members whose spend per ride is lowest, i.e. who extract the
-- most value from the membership. The inverse list is the churn-risk list.
SELECT TOP 25
    a.[rider_id], a.[age_at_account_start], a.[months_observed],
    a.[total_rides], a.[avg_rides_per_month], a.[total_paid], a.[spend_per_ride]
FROM [dbo].[agg_rider_spend_vs_rides] AS a
WHERE a.[is_member] = 1 AND a.[total_rides] >= 10
ORDER BY a.[spend_per_ride] ASC;
GO
