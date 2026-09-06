/* =====================================================================
   TRANSFORM - dim_time  (CETAS)

   Hour-of-day grain, 24 rows. This is what answers the "time of day" half of
   business outcome 1a. Minute grain would be 1,440 rows of no analytical value
   here - nobody asks how ride length differs at 08:17 versus 08:18.

   RE-RUN NOTE: delete divvyfs303533/warehouse/dim_time before re-running.
   ===================================================================== */

IF OBJECT_ID('dbo.dim_time') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[dim_time];
GO

CREATE EXTERNAL TABLE [dbo].[dim_time]
WITH (
    LOCATION    = 'warehouse/dim_time',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
WITH hours (hour_24) AS (
    SELECT * FROM (VALUES
        (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),
        (12),(13),(14),(15),(16),(17),(18),(19),(20),(21),(22),(23)
    ) AS v(hour_24)
)
SELECT
    CAST(hour_24 AS TINYINT)                                     AS [time_key],
    CAST(hour_24 AS TINYINT)                                     AS [hour_24],
    CAST(RIGHT('0' + CAST(hour_24 AS VARCHAR(2)), 2) + ':00' AS VARCHAR(5)) AS [hour_label],
    CAST(CASE
            WHEN hour_24 BETWEEN  5 AND 11 THEN 'Morning'
            WHEN hour_24 BETWEEN 12 AND 16 THEN 'Afternoon'
            WHEN hour_24 BETWEEN 17 AND 21 THEN 'Evening'
            ELSE 'Night'
         END AS VARCHAR(9))                                      AS [time_of_day],
    CAST(CASE
            WHEN hour_24 BETWEEN 7 AND 9 OR hour_24 BETWEEN 16 AND 18 THEN 1
            ELSE 0
         END AS BIT)                                             AS [is_peak_commute]
FROM hours;
GO

SELECT * FROM [dbo].[dim_time] ORDER BY [time_key];
GO
