/* =====================================================================
   00 - SETUP: external data source + file formats
   Run once, in the serverless (Built-in) SQL pool, against your database.

   Placeholders stamped by tools/configure.py:
     divvyfs303533       ADLS Gen2 container   e.g. mydlsfs20250906
     divvydls303533  storage account name  e.g. mydls20250906
   ===================================================================== */

-- Input format for the four extracted text files.
-- Identical to the Synapse wizard-generated format except for STRING_DELIMITER:
-- the ADF copy activity quotes any value containing a comma (rider.address and
-- station.name both do), so without the quote character those rows shift columns.
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'SynapseDelimitedTextFormat')
    CREATE EXTERNAL FILE FORMAT [SynapseDelimitedTextFormat]
    WITH ( FORMAT_TYPE = DELIMITEDTEXT,
           FORMAT_OPTIONS (
             FIELD_TERMINATOR = ',',
             STRING_DELIMITER = '"',
             USE_TYPE_DEFAULT = FALSE
           ));
GO

-- Output format for every CETAS in sql/transform.
-- Parquet rather than CSV: it round-trips real datetime2/decimal/bit types, so the
-- fact tables can be queried straight back without re-casting, and no station name
-- or address can corrupt the output by containing a delimiter.
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'SynapseParquetFormat')
    CREATE EXTERNAL FILE FORMAT [SynapseParquetFormat]
    WITH ( FORMAT_TYPE = PARQUET );
GO

-- Storage location for both the staged extract files and the CETAS output.
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'divvy_datalake')
    CREATE EXTERNAL DATA SOURCE [divvy_datalake]
    WITH ( LOCATION = 'abfss://divvyfs303533@divvydls303533.dfs.core.windows.net' );
GO

SELECT name, location FROM sys.external_data_sources;
SELECT name, format_type, field_terminator, string_delimiter FROM sys.external_file_formats;
GO
