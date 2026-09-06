/* =====================================================================
   LOAD 2 of 4 - staging_payment
   Source: divvy/public.payment.txt

   [amount] is staged as VARCHAR because the source column is PostgreSQL MONEY,
   which the extract can render with a currency symbol and thousands separators
   (for example $9.00). A numeric external column rejects that; TRANSFORM strips
   the symbols before casting to DECIMAL.
   ===================================================================== */

IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'SynapseDelimitedTextFormat')
    CREATE EXTERNAL FILE FORMAT [SynapseDelimitedTextFormat]
    WITH ( FORMAT_TYPE = DELIMITEDTEXT,
           FORMAT_OPTIONS ( FIELD_TERMINATOR = ',', STRING_DELIMITER = '"', USE_TYPE_DEFAULT = FALSE ));
GO

IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'divvy_datalake')
    CREATE EXTERNAL DATA SOURCE [divvy_datalake]
    WITH ( LOCATION = 'abfss://divvyfs303533@divvydls303533.dfs.core.windows.net' );
GO

IF OBJECT_ID('dbo.staging_payment') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[staging_payment];
GO

CREATE EXTERNAL TABLE [dbo].[staging_payment]
(
    [payment_id]    INT,
    [payment_date]  VARCHAR(50),
    [amount]        VARCHAR(50),
    [rider_id]      INT
)
WITH (
    LOCATION    = 'divvy/public.payment.txt',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseDelimitedTextFormat]
);
GO

SELECT TOP 100 * FROM [dbo].[staging_payment];
SELECT COUNT(*) AS payment_rows FROM [dbo].[staging_payment];
GO
