/* =====================================================================
   TRANSFORM - fact_trip  (CETAS)
   Grain: one row per completed bike trip.

   Built by joining staging_trip to the already-materialised dim_rider, which is
   the pattern the project tip describes: materialise the reference data to a
   file with CETAS first, then join to that single external table here rather
   than re-deriving rider attributes from staging every time.

   Foreign keys emitted: rider_id, start_station_id, end_station_id,
   start_date_key, end_date_key, start_time_key.

   Measures: duration_seconds, duration_minutes, rider_age_at_trip.

   rider_age_at_trip is a fact, not a dimension attribute - the same rider is a
   different age on two different trips, so it can only be correct if it is
   stamped at fact-build time.

   Rows with an unparseable start or end timestamp are excluded: they cannot
   contribute a duration, a date key or an hour, so a NULL-keyed row would only
   corrupt the aggregates. 40_validate_star_schema.sql reports how many were
   dropped so the loss is visible rather than silent.

   RE-RUN NOTE: delete <<FILESYSTEM>>/warehouse/fact_trip before re-running.
   ===================================================================== */

IF OBJECT_ID('dbo.fact_trip') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[fact_trip];
GO

CREATE EXTERNAL TABLE [dbo].[fact_trip]
WITH (
    LOCATION    = 'warehouse/fact_trip',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
WITH typed AS (
    SELECT
        t.[trip_id],
        t.[rideable_type],
        TRY_CONVERT(DATETIME2(0), NULLIF(t.[started_at], '')) AS started_at,
        TRY_CONVERT(DATETIME2(0), NULLIF(t.[ended_at],   '')) AS ended_at,
        LTRIM(RTRIM(t.[start_station_id]))                    AS start_station_id,
        LTRIM(RTRIM(t.[end_station_id]))                      AS end_station_id,
        t.[rider_id],
        r.[birthday],
        r.[is_member],
        r.[rider_type]
    FROM [dbo].[staging_trip] AS t
    LEFT JOIN [dbo].[dim_rider] AS r
           ON r.[rider_id] = t.[rider_id]
    WHERE t.[trip_id] IS NOT NULL
),
aged AS (
    SELECT
        typed.*,
        DATEDIFF(SECOND, started_at, ended_at) AS duration_seconds,
        DATEDIFF(YEAR, birthday, started_at)
            - CASE WHEN MONTH(started_at) < MONTH(birthday)
                     OR (MONTH(started_at) = MONTH(birthday)
                         AND DAY(started_at) < DAY(birthday))
                   THEN 1 ELSE 0 END AS rider_age_at_trip
    FROM typed
    WHERE started_at IS NOT NULL
      AND ended_at   IS NOT NULL
)
SELECT
    CAST([trip_id] AS VARCHAR(50))                  AS [trip_id],
    CAST([rider_id] AS INT)                         AS [rider_id],
    CAST([start_station_id] AS VARCHAR(50))         AS [start_station_id],
    CAST([end_station_id] AS VARCHAR(50))           AS [end_station_id],
    CAST(YEAR(started_at) * 10000 + MONTH(started_at) * 100 + DAY(started_at) AS INT)
                                                    AS [start_date_key],
    CAST(YEAR(ended_at)   * 10000 + MONTH(ended_at)   * 100 + DAY(ended_at)   AS INT)
                                                    AS [end_date_key],
    CAST(DATEPART(HOUR, started_at) AS TINYINT)     AS [start_time_key],
    CAST([rideable_type] AS VARCHAR(75))            AS [rideable_type],
    CAST(started_at AS DATETIME2(0))                AS [started_at],
    CAST(ended_at   AS DATETIME2(0))                AS [ended_at],
    CAST(duration_seconds AS INT)                   AS [duration_seconds],
    CAST(duration_seconds / 60.0 AS DECIMAL(10, 2)) AS [duration_minutes],
    CAST(rider_age_at_trip AS INT)                  AS [rider_age_at_trip],
    CAST(CASE
            WHEN rider_age_at_trip IS NULL  THEN 'Unknown'
            WHEN rider_age_at_trip < 18 THEN 'Under 18'
            WHEN rider_age_at_trip < 25 THEN '18-24'
            WHEN rider_age_at_trip < 35 THEN '25-34'
            WHEN rider_age_at_trip < 45 THEN '35-44'
            WHEN rider_age_at_trip < 55 THEN '45-54'
            WHEN rider_age_at_trip < 65 THEN '55-64'
            ELSE '65+'
         END AS VARCHAR(8))                         AS [rider_age_band_at_trip],
    CAST(COALESCE([is_member], 0) AS BIT)           AS [is_member],
    CAST(COALESCE([rider_type], 'Unknown') AS VARCHAR(7)) AS [rider_type]
FROM aged;
GO

SELECT TOP 100 * FROM [dbo].[fact_trip];
SELECT COUNT(*)                    AS trip_rows,
       AVG([duration_minutes])     AS avg_minutes,
       MIN([duration_minutes])     AS min_minutes,
       MAX([duration_minutes])     AS max_minutes,
       SUM(CASE WHEN [rider_age_at_trip] IS NULL THEN 1 ELSE 0 END) AS trips_missing_age
FROM [dbo].[fact_trip];
GO
