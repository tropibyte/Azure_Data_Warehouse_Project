/* =====================================================================
   TRANSFORM - dim_rider  (CETAS)

   Membership and account dates live here, not in a dim_account: the source
   PostgreSQL rider table carries is_member / account_start_date /
   account_end_date as rider columns. The classroom ERD shows a separate
   account entity, but the starter script never creates one.

   age_at_account_start IS a dimension attribute - it is fixed for the life of
   the rider, and business outcome 2b asks for spend by exactly that value.
   Age at the time of a ride is a different, point-in-time number and belongs
   on fact_trip.

   No facts here: no ride counts, no payment totals, no durations.

   RE-RUN NOTE: delete divvyfs303533/warehouse/dim_rider before re-running.
   ===================================================================== */

IF OBJECT_ID('dbo.dim_rider') IS NOT NULL
    DROP EXTERNAL TABLE [dbo].[dim_rider];
GO

CREATE EXTERNAL TABLE [dbo].[dim_rider]
WITH (
    LOCATION    = 'warehouse/dim_rider',
    DATA_SOURCE = [divvy_datalake],
    FILE_FORMAT = [SynapseParquetFormat]
)
AS
WITH typed AS (
    SELECT
        [rider_id],
        [first_name],
        [last_name],
        [address],
        TRY_CONVERT(DATE, NULLIF([birthday], ''))           AS birthday,
        TRY_CONVERT(DATE, NULLIF([account_start_date], '')) AS account_start_date,
        TRY_CONVERT(DATE, NULLIF([account_end_date], ''))   AS account_end_date,
        CASE WHEN LOWER(LTRIM(RTRIM([is_member]))) IN ('true', 't', '1', 'yes', 'y')
             THEN 1 ELSE 0 END                              AS is_member
    FROM [dbo].[staging_rider]
    WHERE [rider_id] IS NOT NULL
),
aged AS (
    SELECT
        typed.*,
        -- Whole years completed at account start: subtract one if the birthday
        -- had not yet come round in that calendar year.
        DATEDIFF(YEAR, birthday, account_start_date)
            - CASE WHEN MONTH(account_start_date) < MONTH(birthday)
                     OR (MONTH(account_start_date) = MONTH(birthday)
                         AND DAY(account_start_date) < DAY(birthday))
                   THEN 1 ELSE 0 END AS age_at_account_start
    FROM typed
)
SELECT
    CAST([rider_id] AS INT)                     AS [rider_id],
    CAST([first_name] AS VARCHAR(50))           AS [first_name],
    CAST([last_name] AS VARCHAR(50))            AS [last_name],
    CAST([address] AS VARCHAR(100))             AS [address],
    CAST(birthday AS DATE)                      AS [birthday],
    CAST(account_start_date AS DATE)            AS [account_start_date],
    CAST(account_end_date AS DATE)              AS [account_end_date],
    CAST(is_member AS BIT)                      AS [is_member],
    CAST(CASE WHEN is_member = 1 THEN 'Member' ELSE 'Casual' END AS VARCHAR(6)) AS [rider_type],
    CAST(age_at_account_start AS INT)           AS [age_at_account_start],
    CAST(CASE
            WHEN age_at_account_start IS NULL THEN 'Unknown'
            WHEN age_at_account_start < 18 THEN 'Under 18'
            WHEN age_at_account_start < 25 THEN '18-24'
            WHEN age_at_account_start < 35 THEN '25-34'
            WHEN age_at_account_start < 45 THEN '35-44'
            WHEN age_at_account_start < 55 THEN '45-54'
            WHEN age_at_account_start < 65 THEN '55-64'
            ELSE '65+'
         END AS VARCHAR(8))                     AS [age_band_at_account_start],
    CAST(DATEDIFF(MONTH, account_start_date,
                  COALESCE(account_end_date, CAST(GETDATE() AS DATE))) AS INT)
                                                AS [account_tenure_months],
    CAST(CASE WHEN account_end_date IS NULL THEN 1 ELSE 0 END AS BIT) AS [is_account_open]
FROM aged;
GO

SELECT TOP 100 * FROM [dbo].[dim_rider];
SELECT COUNT(*) AS rider_rows,
       SUM(CAST([is_member] AS INT)) AS members,
       MIN([age_at_account_start]) AS min_age,
       MAX([age_at_account_start]) AS max_age
FROM [dbo].[dim_rider];
GO
