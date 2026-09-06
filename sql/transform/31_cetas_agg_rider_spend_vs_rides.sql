/* =====================================================================
   TRANSFORM - agg_rider_spend_vs_rides  (CETAS)  *** EXTRA CREDIT, 2 of 2 ***
   Grain: one row per rider.

   Rolls fact_rider_monthly up to the rider and answers the extra-credit
   question directly: how much money does a member spend, given how many rides
   they average per month.

   Choice of denominator
   ---------------------
   avg_rides_per_month divides total rides by months_observed - the number of
   calendar months from the rider's first activity to their last, inclusive -
   NOT by the number of months in which they happened to ride. Dividing by
   active months only would score a rider who rode twice in one month and then
   vanished the same as a rider who rode twice every month for two years. The
   inactive months are the signal, so they stay in the denominator.

   months_active is kept alongside it so the ratio between the two is visible.

   RE-RUN NOTE: delete <<FILESYSTEM>>/warehouse/agg_rider_spend_vs_rides first.
   ===================================================================== */

IF OBJECT_ID('dbo.agg_rider_spend_vs_rides') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[agg_rider_spend_vs_rides];
GO

CREATE EXTERNAL TABLE [dbo].[agg_rider_spend_vs_rides]
WITH (
    LOCATION    = 'warehouse/agg_rider_spend_vs_rides',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
WITH rolled AS (
    SELECT
        [rider_id],
        MIN([month_start_date])       AS first_active_month,
        MAX([month_start_date])       AS last_active_month,
        SUM([rides_in_month])         AS total_rides,
        SUM([ride_minutes_in_month])  AS total_ride_minutes,
        SUM([amount_paid_in_month])   AS total_paid,
        SUM(CASE WHEN [rides_in_month] > 0 THEN 1 ELSE 0 END) AS months_active
    FROM [dbo].[fact_rider_monthly]
    GROUP BY [rider_id]
),
measured AS (
    SELECT
        rolled.*,
        DATEDIFF(MONTH, first_active_month, last_active_month) + 1 AS months_observed
    FROM rolled
),
rated AS (
    SELECT
        measured.*,
        CAST(total_rides * 1.0 / NULLIF(months_observed, 0) AS DECIMAL(10, 2)) AS avg_rides_per_month
    FROM measured
)
SELECT
    CAST(r.[rider_id] AS INT)                       AS [rider_id],
    CAST(d.[rider_type] AS VARCHAR(6))              AS [rider_type],
    CAST(d.[is_member] AS BIT)                      AS [is_member],
    CAST(d.[age_at_account_start] AS INT)           AS [age_at_account_start],
    CAST(d.[age_band_at_account_start] AS VARCHAR(8)) AS [age_band_at_account_start],
    CAST(r.first_active_month AS DATE)              AS [first_active_month],
    CAST(r.last_active_month AS DATE)               AS [last_active_month],
    CAST(r.months_observed AS INT)                  AS [months_observed],
    CAST(r.months_active AS INT)                    AS [months_active],
    CAST(r.total_rides AS INT)                      AS [total_rides],
    CAST(r.total_ride_minutes AS DECIMAL(12, 2))    AS [total_ride_minutes],
    CAST(r.total_paid AS DECIMAL(12, 2))            AS [total_paid],
    CAST(r.avg_rides_per_month AS DECIMAL(10, 2))   AS [avg_rides_per_month],
    CAST(r.total_paid / NULLIF(r.months_observed, 0) AS DECIMAL(12, 2)) AS [avg_spend_per_month],
    CAST(r.total_paid / NULLIF(r.total_rides, 0) AS DECIMAL(12, 2))     AS [spend_per_ride],
    CAST(CASE
            WHEN r.avg_rides_per_month IS NULL      THEN 'Unknown'
            WHEN r.avg_rides_per_month  =  0        THEN '0 (no rides)'
            WHEN r.avg_rides_per_month  <  1        THEN 'Under 1'
            WHEN r.avg_rides_per_month  <  2        THEN '1 to 2'
            WHEN r.avg_rides_per_month  <  4        THEN '2 to 4'
            WHEN r.avg_rides_per_month  <  8        THEN '4 to 8'
            WHEN r.avg_rides_per_month  < 16        THEN '8 to 16'
            ELSE '16+'
         END AS VARCHAR(12))                        AS [rides_per_month_band]
FROM rated AS r
LEFT JOIN [dbo].[dim_rider] AS d
       ON d.[rider_id] = r.[rider_id];
GO

SELECT TOP 100 * FROM [dbo].[agg_rider_spend_vs_rides] ORDER BY [avg_rides_per_month] DESC;
GO
