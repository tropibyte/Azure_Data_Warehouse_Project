/* =====================================================================
   LOAD 3 of 4 - staging_station
   Source: <<EXTRACT_FOLDER>>/public.station.txt

   station_id is VARCHAR in the source, not INT as the classroom ERD shows -
   Divvy station ids are alphanumeric. Keeping it VARCHAR avoids silently
   dropping every station whose id will not cast.
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

IF OBJECT_ID('dbo.staging_station') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[staging_station];
GO

CREATE EXTERNAL TABLE [dbo].[staging_station]
(
    [station_id]    VARCHAR(50),
    [station_name]  VARCHAR(75),
    [latitude]      FLOAT,
    [longitude]     FLOAT
)
WITH (
    LOCATION    = '<<EXTRACT_FOLDER>>/public.station.txt',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseDelimitedTextFormat]
);
GO

SELECT TOP 100 * FROM [dbo].[staging_station];
SELECT COUNT(*) AS station_rows FROM [dbo].[staging_station];
GO
