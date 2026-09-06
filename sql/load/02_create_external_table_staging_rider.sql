/* =====================================================================
   LOAD 1 of 4 - staging_rider
   Source: <<EXTRACT_FOLDER>>/public.rider.txt  (from the EXTRACT step)

   All DATE columns are staged as VARCHAR, per the project hint. The extract
   writes dates as text, and a datetime2 external column fails the whole file on
   a single unparseable row; converting in TRANSFORM keeps failures inspectable.
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

IF OBJECT_ID('dbo.staging_rider') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[staging_rider];
GO

CREATE EXTERNAL TABLE [dbo].[staging_rider]
(
    [rider_id]            INT,
    [first_name]          VARCHAR(50),
    [last_name]           VARCHAR(50),
    [address]             VARCHAR(100),
    [birthday]            VARCHAR(50),
    [account_start_date]  VARCHAR(50),
    [account_end_date]    VARCHAR(50),
    [is_member]           VARCHAR(10)
)
WITH (
    LOCATION    = '<<EXTRACT_FOLDER>>/public.rider.txt',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseDelimitedTextFormat]
);
GO

SELECT TOP 100 * FROM [dbo].[staging_rider];
SELECT COUNT(*) AS rider_rows FROM [dbo].[staging_rider];
GO
