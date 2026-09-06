/* =====================================================================
   LOAD 4 of 4 - staging_trip
   Source: <<EXTRACT_FOLDER>>/public.trip.txt

   started_at / ended_at are staged as VARCHAR. The source is TIMESTAMP and the
   extract writes it as 2021-02-12 16:14:56, which TRANSFORM converts with
   TRY_CONVERT so a bad row lands as NULL instead of failing the whole query.
   ===================================================================== */

IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'SynapseDelimitedTextFormat')
    CREATE EXTERNAL FILE FORMAT [SynapseDelimitedTextFormat]
    WITH ( FORMAT_TYPE = DELIMITEDTEXT,
           FORMAT_OPTIONS ( FIELD_TERMINATOR = ',', STRING_DELIMITER = '"', USE_TYPE_DEFAULT = FALSE ));
GO

IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'divvy_datalake')
    CREATE EXTERNAL DATA SOURCE [divvy_datalake]
    WITH ( LOCATION = 'abfss://<<FILESYSTEM>>@<<STORAGE_ACCOUNT>>.dfs.core.windows.net' );
GO

IF OBJECT_ID('dbo.staging_trip') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[staging_trip];
GO

CREATE EXTERNAL TABLE [dbo].[staging_trip]
(
    [trip_id]           VARCHAR(50),
    [rideable_type]     VARCHAR(75),
    [started_at]        VARCHAR(50),
    [ended_at]          VARCHAR(50),
    [start_station_id]  VARCHAR(50),
    [end_station_id]    VARCHAR(50),
    [rider_id]          INT
)
WITH (
    LOCATION    = '<<EXTRACT_FOLDER>>/public.trip.txt',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseDelimitedTextFormat]
);
GO

SELECT TOP 100 * FROM [dbo].[staging_trip];
SELECT COUNT(*) AS trip_rows FROM [dbo].[staging_trip];
GO
