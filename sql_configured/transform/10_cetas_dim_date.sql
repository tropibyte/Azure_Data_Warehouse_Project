/* =====================================================================
   TRANSFORM - dim_date  (CETAS)

   Covers 2013-01-01 .. 2030-12-31, which spans every trip date, payment date
   and account start/end date in the dataset. Rider birthdays are deliberately
   NOT keyed to this dimension - age is computed as a point-in-time measure on
   the facts, so the calendar does not need to reach back to the 1940s.

   The spine is built from a cross-joined digit list rather than a recursive CTE
   or a system table, so it runs identically in the serverless pool with no
   dependency on sys.* row counts.

   RE-RUN NOTE: CETAS fails if the output folder already contains files, even
   after DROP EXTERNAL TABLE. Before re-running, delete the folder
   divvyfs303533/warehouse/dim_date in Data > Linked > your storage account.
   ===================================================================== */

IF OBJECT_ID('dbo.dim_date') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[dim_date];
GO

CREATE EXTERNAL TABLE [dbo].[dim_date]
WITH (
    LOCATION    = 'warehouse/dim_date',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
WITH digits (d) AS (
    SELECT * FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS v(d)
),
day_offsets (day_offset) AS (
    SELECT a.d + b.d * 10 + c.d * 100 + e.d * 1000
    FROM digits a CROSS JOIN digits b CROSS JOIN digits c CROSS JOIN digits e
),
calendar AS (
    SELECT DATEADD(DAY, day_offset, CAST('2013-01-01' AS DATE)) AS full_date
    FROM day_offsets
    WHERE day_offset <= DATEDIFF(DAY, CAST('2013-01-01' AS DATE), CAST('2030-12-31' AS DATE))
),
enriched AS (
    SELECT
        full_date,
        -- 1900-01-01 was a Monday, so this gives Monday=1 .. Sunday=7 without
        -- depending on the session DATEFIRST or language settings.
        (DATEDIFF(DAY, CAST('1900-01-01' AS DATE), full_date) % 7) + 1 AS day_of_week
    FROM calendar
)
SELECT
    CAST(YEAR(full_date) * 10000 + MONTH(full_date) * 100 + DAY(full_date) AS INT) AS [date_key],
    CAST(full_date AS DATE)                              AS [full_date],
    CAST(YEAR(full_date) AS SMALLINT)                    AS [year],
    CAST(DATEPART(QUARTER, full_date) AS TINYINT)        AS [quarter],
    CAST(MONTH(full_date) AS TINYINT)                    AS [month],
    CAST(CASE MONTH(full_date)
            WHEN  1 THEN 'January'   WHEN  2 THEN 'February' WHEN  3 THEN 'March'
            WHEN  4 THEN 'April'     WHEN  5 THEN 'May'      WHEN  6 THEN 'June'
            WHEN  7 THEN 'July'      WHEN  8 THEN 'August'   WHEN  9 THEN 'September'
            WHEN 10 THEN 'October'   WHEN 11 THEN 'November' ELSE 'December'
         END AS VARCHAR(10))                             AS [month_name],
    CAST(DAY(full_date) AS TINYINT)                      AS [day_of_month],
    CAST(day_of_week AS TINYINT)                         AS [day_of_week],
    CAST(CASE day_of_week
            WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'  WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'  WHEN 5 THEN 'Friday'   WHEN 6 THEN 'Saturday'
            ELSE 'Sunday'
         END AS VARCHAR(9))                              AS [day_name],
    CAST(DATEPART(ISO_WEEK, full_date) AS TINYINT)       AS [week_of_year],
    CAST(CASE WHEN day_of_week IN (6, 7) THEN 1 ELSE 0 END AS BIT) AS [is_weekend],
    CAST(LEFT(CONVERT(VARCHAR(10), full_date, 23), 7) AS VARCHAR(7)) AS [year_month],
    CAST(CONCAT(YEAR(full_date), '-Q', DATEPART(QUARTER, full_date)) AS VARCHAR(7)) AS [year_quarter],
    CAST(DATEFROMPARTS(YEAR(full_date), MONTH(full_date), 1) AS DATE) AS [month_start_date]
FROM enriched;
GO

SELECT TOP 10 * FROM [dbo].[dim_date] ORDER BY [date_key];
SELECT COUNT(*) AS date_rows, MIN([full_date]) AS first_day, MAX([full_date]) AS last_day
FROM [dbo].[dim_date];
GO
