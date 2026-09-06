/* =====================================================================
   VALIDATE - reconcile the star schema against staging.
   Run this after every CETAS. Nothing here creates objects.

   Each query returns a check_name and a value. Anything that should be zero is
   named so it reads as a defect count.
   ===================================================================== */

-- 1. Row counts: staging vs star. fact_trip may be lower than staging_trip if
--    any timestamps failed to parse; the next query says how many and why.
SELECT 'staging_rider'   AS table_name, COUNT(*) AS row_count FROM [dbo].[staging_rider]
UNION ALL SELECT 'dim_rider',           COUNT(*) FROM [dbo].[dim_rider]
UNION ALL SELECT 'staging_station',     COUNT(*) FROM [dbo].[staging_station]
UNION ALL SELECT 'dim_station',         COUNT(*) FROM [dbo].[dim_station]
UNION ALL SELECT 'staging_trip',        COUNT(*) FROM [dbo].[staging_trip]
UNION ALL SELECT 'fact_trip',           COUNT(*) FROM [dbo].[fact_trip]
UNION ALL SELECT 'staging_payment',     COUNT(*) FROM [dbo].[staging_payment]
UNION ALL SELECT 'fact_payment',        COUNT(*) FROM [dbo].[fact_payment]
UNION ALL SELECT 'dim_date',            COUNT(*) FROM [dbo].[dim_date]
UNION ALL SELECT 'dim_time',            COUNT(*) FROM [dbo].[dim_time]
UNION ALL SELECT 'fact_rider_monthly',  COUNT(*) FROM [dbo].[fact_rider_monthly]
UNION ALL SELECT 'agg_rider_spend_vs_rides', COUNT(*) FROM [dbo].[agg_rider_spend_vs_rides];
GO

-- 2. Trips dropped during TRANSFORM, and why. Should be 0 rows dropped, but if
--    it is not, this says whether the cause was the start or the end timestamp.
SELECT
    'staging_trip rows'                     AS check_name,
    COUNT(*)                                AS value
FROM [dbo].[staging_trip]
UNION ALL
SELECT 'unparseable started_at',
       SUM(CASE WHEN TRY_CONVERT(DATETIME2(0), NULLIF([started_at], '')) IS NULL THEN 1 ELSE 0 END)
FROM [dbo].[staging_trip]
UNION ALL
SELECT 'unparseable ended_at',
       SUM(CASE WHEN TRY_CONVERT(DATETIME2(0), NULLIF([ended_at], '')) IS NULL THEN 1 ELSE 0 END)
FROM [dbo].[staging_trip];
GO

-- 3. Referential integrity. Every one of these must be 0.
SELECT 'fact_trip rider_id not in dim_rider' AS check_name, COUNT(*) AS defects
FROM [dbo].[fact_trip] f
LEFT JOIN [dbo].[dim_rider] d ON d.[rider_id] = f.[rider_id]
WHERE d.[rider_id] IS NULL
UNION ALL
SELECT 'fact_trip start_station_id not in dim_station', COUNT(*)
FROM [dbo].[fact_trip] f
LEFT JOIN [dbo].[dim_station] s ON s.[station_id] = f.[start_station_id]
WHERE s.[station_id] IS NULL
UNION ALL
SELECT 'fact_trip end_station_id not in dim_station', COUNT(*)
FROM [dbo].[fact_trip] f
LEFT JOIN [dbo].[dim_station] s ON s.[station_id] = f.[end_station_id]
WHERE s.[station_id] IS NULL
UNION ALL
SELECT 'fact_trip start_date_key not in dim_date', COUNT(*)
FROM [dbo].[fact_trip] f
LEFT JOIN [dbo].[dim_date] d ON d.[date_key] = f.[start_date_key]
WHERE d.[date_key] IS NULL
UNION ALL
SELECT 'fact_trip start_time_key not in dim_time', COUNT(*)
FROM [dbo].[fact_trip] f
LEFT JOIN [dbo].[dim_time] t ON t.[time_key] = f.[start_time_key]
WHERE t.[time_key] IS NULL
UNION ALL
SELECT 'fact_payment rider_id not in dim_rider', COUNT(*)
FROM [dbo].[fact_payment] f
LEFT JOIN [dbo].[dim_rider] d ON d.[rider_id] = f.[rider_id]
WHERE d.[rider_id] IS NULL
UNION ALL
SELECT 'fact_payment date_key not in dim_date', COUNT(*)
FROM [dbo].[fact_payment] f
LEFT JOIN [dbo].[dim_date] d ON d.[date_key] = f.[date_key]
WHERE d.[date_key] IS NULL;
GO

-- 4. Grain / uniqueness. Both differences must be 0.
SELECT 'fact_trip duplicate trip_id' AS check_name,
       COUNT(*) - COUNT(DISTINCT [trip_id]) AS defects
FROM [dbo].[fact_trip]
UNION ALL
SELECT 'fact_payment duplicate payment_id',
       COUNT(*) - COUNT(DISTINCT [payment_id])
FROM [dbo].[fact_payment]
UNION ALL
SELECT 'dim_rider duplicate rider_id',
       COUNT(*) - COUNT(DISTINCT [rider_id])
FROM [dbo].[dim_rider]
UNION ALL
SELECT 'dim_station duplicate station_id',
       COUNT(*) - COUNT(DISTINCT [station_id])
FROM [dbo].[dim_station];
GO

-- 5. Measure sanity. Negative durations mean ended_at precedes started_at in
--    the source; very long ones are real Divvy behaviour (unreturned bikes) and
--    should be excluded per-query, not deleted here.
SELECT 'trips with negative duration' AS check_name, COUNT(*) AS value
FROM [dbo].[fact_trip] WHERE [duration_seconds] < 0
UNION ALL
SELECT 'trips over 24 hours', COUNT(*)
FROM [dbo].[fact_trip] WHERE [duration_seconds] > 86400
UNION ALL
SELECT 'trips with null rider age', COUNT(*)
FROM [dbo].[fact_trip] WHERE [rider_age_at_trip] IS NULL
UNION ALL
SELECT 'payments with null amount', COUNT(*)
FROM [dbo].[fact_payment] WHERE [amount] IS NULL;
GO

-- 6. Money reconciles between staging and the fact. The two totals must match
--    to the cent; if they do not, the MONEY-to-DECIMAL cleaning dropped rows.
SELECT
    (SELECT SUM(TRY_CONVERT(DECIMAL(12, 2),
        REPLACE(REPLACE(REPLACE([amount], '$', ''), ',', ''), ' ', '')))
     FROM [dbo].[staging_payment])            AS staging_total,
    (SELECT SUM([amount]) FROM [dbo].[fact_payment]) AS fact_total,
    (SELECT SUM([amount_paid_in_month]) FROM [dbo].[fact_rider_monthly]) AS monthly_total,
    (SELECT SUM([total_paid]) FROM [dbo].[agg_rider_spend_vs_rides])     AS agg_total;
GO

-- 7. Rides reconcile across the extra-credit rollups. All three must match.
SELECT
    (SELECT COUNT(*) FROM [dbo].[fact_trip] WHERE [rider_id] IS NOT NULL) AS fact_trip_rides,
    (SELECT SUM([rides_in_month]) FROM [dbo].[fact_rider_monthly])        AS monthly_rides,
    (SELECT SUM([total_rides]) FROM [dbo].[agg_rider_spend_vs_rides])     AS agg_rides;
GO
