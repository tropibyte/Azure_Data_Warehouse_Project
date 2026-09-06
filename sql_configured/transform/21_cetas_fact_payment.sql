/* =====================================================================
   TRANSFORM - fact_payment  (CETAS)
   Grain: one row per payment.

   Foreign keys emitted: rider_id, date_key.
   Measure: amount.

   The source column is PostgreSQL MONEY, so the staged text can arrive as
   $9.00 or 1,250.00. Everything that is not a digit, a minus sign or a decimal
   point is stripped before the cast; TRY_CONVERT then leaves anything still
   unparseable as NULL instead of failing the whole CETAS.

   rider_age_at_payment is stamped here for the same reason age is stamped on
   fact_trip. Business outcome 2b asks for spend by age at ACCOUNT START, which
   is dim_rider.age_at_account_start - a different question, and both are
   answerable because each lives where it belongs.

   RE-RUN NOTE: delete divvyfs303533/warehouse/fact_payment before re-running.
   ===================================================================== */

IF OBJECT_ID('dbo.fact_payment') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[fact_payment];
GO

CREATE EXTERNAL TABLE [dbo].[fact_payment]
WITH (
    LOCATION    = 'warehouse/fact_payment',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
WITH typed AS (
    SELECT
        p.[payment_id],
        p.[rider_id],
        TRY_CONVERT(DATE, NULLIF(p.[payment_date], '')) AS payment_date,
        -- Do NOT add a REPLACE for CHAR(160) here. Under a UTF-8 database
        -- collation CHAR(160) evaluates to NULL, and REPLACE(x, NULL, '')
        -- returns NULL for every row - which silently nulls every amount in
        -- the fact table while staging still totals correctly.
        TRY_CONVERT(DECIMAL(10, 2),
            REPLACE(REPLACE(REPLACE(p.[amount], '$', ''), ',', ''), ' ', '')
        ) AS amount,
        r.[birthday]
    FROM [dbo].[staging_payment] AS p
    LEFT JOIN [dbo].[dim_rider] AS r
           ON r.[rider_id] = p.[rider_id]
    WHERE p.[payment_id] IS NOT NULL
),
aged AS (
    SELECT
        typed.*,
        DATEDIFF(YEAR, birthday, payment_date)
            - CASE WHEN MONTH(payment_date) < MONTH(birthday)
                     OR (MONTH(payment_date) = MONTH(birthday)
                         AND DAY(payment_date) < DAY(birthday))
                   THEN 1 ELSE 0 END AS rider_age_at_payment
    FROM typed
    WHERE payment_date IS NOT NULL
)
SELECT
    CAST([payment_id] AS INT)                       AS [payment_id],
    CAST([rider_id] AS INT)                         AS [rider_id],
    CAST(YEAR(payment_date) * 10000 + MONTH(payment_date) * 100 + DAY(payment_date) AS INT)
                                                    AS [date_key],
    CAST(payment_date AS DATE)                      AS [payment_date],
    CAST([amount] AS DECIMAL(10, 2))                AS [amount],
    CAST(rider_age_at_payment AS INT)               AS [rider_age_at_payment]
FROM aged;
GO

SELECT TOP 100 * FROM [dbo].[fact_payment];
SELECT COUNT(*)      AS payment_rows,
       SUM([amount]) AS total_amount,
       MIN([amount]) AS min_amount,
       MAX([amount]) AS max_amount,
       SUM(CASE WHEN [amount] IS NULL THEN 1 ELSE 0 END) AS unparseable_amounts
FROM [dbo].[fact_payment];
GO
