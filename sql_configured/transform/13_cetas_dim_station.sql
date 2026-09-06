/* =====================================================================
   TRANSFORM - dim_station  (CETAS)

   Role-playing dimension: fact_trip joins to it twice, once as the start
   station and once as the end station, which is what business outcome 1b
   ("longest rides by start and/or end station") needs.

   RE-RUN NOTE: delete divvyfs303533/warehouse/dim_station before re-running.
   ===================================================================== */

IF OBJECT_ID('dbo.dim_station') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[dim_station];
GO

CREATE EXTERNAL TABLE [dbo].[dim_station]
WITH (
    LOCATION    = 'warehouse/dim_station',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
SELECT
    CAST(LTRIM(RTRIM([station_id])) AS VARCHAR(50)) AS [station_id],
    CAST([station_name] AS VARCHAR(75))             AS [station_name],
    CAST([latitude] AS FLOAT)                       AS [latitude],
    CAST([longitude] AS FLOAT)                      AS [longitude]
FROM [dbo].[staging_station]
WHERE [station_id] IS NOT NULL;
GO

SELECT TOP 100 * FROM [dbo].[dim_station];
SELECT COUNT(*) AS station_rows, COUNT(DISTINCT [station_id]) AS distinct_ids
FROM [dbo].[dim_station];
GO
