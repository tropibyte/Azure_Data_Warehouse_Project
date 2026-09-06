/* =====================================================================
   TRANSFORM - fact_rider_monthly  (CETAS)   *** EXTRA CREDIT, part 1 of 2 ***
   Grain: one row per rider per calendar month in which that rider had any
   activity (a ride, a payment, or both).

   Why this table exists
   ---------------------
   Extra credit asks for money spent per member BASED ON how many rides the
   rider averages per month. Rides and payments are two separate facts at two
   different grains, so joining them directly fans out: a rider with 12 payments
   and 40 trips would produce 480 rows and a payment total inflated 40x.

   Conforming both onto a shared rider-month grain first makes the comparison a
   plain arithmetic one, and it is the same "materialise the join to a file,
   then query the single external table" pattern the project tip recommends.

   The month spine is the UNION of months in which the rider rode and months in
   which the rider paid, so a rider who paid in a month they never rode still
   gets a row - with rides_in_month = 0, which is itself a finding.

   RE-RUN NOTE: delete <<FILESYSTEM>>/warehouse/fact_rider_monthly first.
   ===================================================================== */

IF OBJECT_ID('dbo.fact_rider_monthly') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[fact_rider_monthly];
GO

CREATE EXTERNAL TABLE [dbo].[fact_rider_monthly]
WITH (
    LOCATION    = 'warehouse/fact_rider_monthly',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
WITH trips_by_month AS (
    SELECT
        [rider_id],
        DATEFROMPARTS(YEAR([started_at]), MONTH([started_at]), 1) AS month_start_date,
        COUNT(*)                  AS rides_in_month,
        SUM([duration_minutes])   AS ride_minutes_in_month
    FROM [dbo].[fact_trip]
    WHERE [rider_id] IS NOT NULL
    GROUP BY [rider_id], DATEFROMPARTS(YEAR([started_at]), MONTH([started_at]), 1)
),
payments_by_month AS (
    SELECT
        [rider_id],
        DATEFROMPARTS(YEAR([payment_date]), MONTH([payment_date]), 1) AS month_start_date,
        COUNT(*)      AS payments_in_month,
        SUM([amount]) AS amount_paid_in_month
    FROM [dbo].[fact_payment]
    WHERE [rider_id] IS NOT NULL
    GROUP BY [rider_id], DATEFROMPARTS(YEAR([payment_date]), MONTH([payment_date]), 1)
),
rider_months AS (
    SELECT [rider_id], month_start_date FROM trips_by_month
    UNION
    SELECT [rider_id], month_start_date FROM payments_by_month
)
SELECT
    CAST(rm.[rider_id] AS INT)                          AS [rider_id],
    CAST(YEAR(rm.month_start_date) * 10000 + MONTH(rm.month_start_date) * 100 + 1 AS INT)
                                                        AS [month_date_key],
    CAST(rm.month_start_date AS DATE)                   AS [month_start_date],
    CAST(LEFT(CONVERT(VARCHAR(10), rm.month_start_date, 23), 7) AS VARCHAR(7)) AS [year_month],
    CAST(YEAR(rm.month_start_date) AS SMALLINT)         AS [year],
    CAST(DATEPART(QUARTER, rm.month_start_date) AS TINYINT) AS [quarter],
    CAST(MONTH(rm.month_start_date) AS TINYINT)         AS [month],
    CAST(COALESCE(t.rides_in_month, 0) AS INT)          AS [rides_in_month],
    CAST(COALESCE(t.ride_minutes_in_month, 0) AS DECIMAL(12, 2)) AS [ride_minutes_in_month],
    CAST(COALESCE(p.payments_in_month, 0) AS INT)       AS [payments_in_month],
    CAST(COALESCE(p.amount_paid_in_month, 0) AS DECIMAL(12, 2))  AS [amount_paid_in_month]
FROM rider_months AS rm
LEFT JOIN trips_by_month AS t
       ON t.[rider_id] = rm.[rider_id]
      AND t.month_start_date = rm.month_start_date
LEFT JOIN payments_by_month AS p
       ON p.[rider_id] = rm.[rider_id]
      AND p.month_start_date = rm.month_start_date;
GO

SELECT TOP 100 * FROM [dbo].[fact_rider_monthly] ORDER BY [rider_id], [month_start_date];
SELECT COUNT(*) AS rider_month_rows,
       COUNT(DISTINCT [rider_id]) AS riders,
       SUM([rides_in_month])       AS total_rides,
       SUM([amount_paid_in_month]) AS total_paid
FROM [dbo].[fact_rider_monthly];
GO
