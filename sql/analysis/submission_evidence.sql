/* =====================================================================
   ONE-SCREEN SUBMISSION EVIDENCE

   Every reconciliation check the project needs, as a single result set, so
   the whole proof fits in one screenshot instead of seven.

   Read it top to bottom: row counts first, then referential integrity, then
   the money and ride totals that must agree across the star. Every row in the
   DEFECT section must read 0. Every row in the RECONCILE section must match
   its pair.
   ===================================================================== */

WITH counts AS (
    SELECT
        (SELECT COUNT(*) FROM dbo.staging_rider)            AS staging_rider,
        (SELECT COUNT(*) FROM dbo.staging_payment)          AS staging_payment,
        (SELECT COUNT(*) FROM dbo.staging_station)          AS staging_station,
        (SELECT COUNT(*) FROM dbo.staging_trip)             AS staging_trip,
        (SELECT COUNT(*) FROM dbo.dim_rider)                AS dim_rider,
        (SELECT COUNT(*) FROM dbo.dim_station)              AS dim_station,
        (SELECT COUNT(*) FROM dbo.dim_date)                 AS dim_date,
        (SELECT COUNT(*) FROM dbo.dim_time)                 AS dim_time,
        (SELECT COUNT(*) FROM dbo.fact_trip)                AS fact_trip,
        (SELECT COUNT(*) FROM dbo.fact_payment)             AS fact_payment,
        (SELECT COUNT(*) FROM dbo.fact_rider_monthly)       AS fact_rider_monthly,
        (SELECT COUNT(*) FROM dbo.agg_rider_spend_vs_rides) AS agg_rider
)
SELECT  1 AS seq, 'ROW COUNTS' AS section, 'staging_rider  -> dim_rider'   AS check_name,
        CONCAT(staging_rider, '  ->  ', dim_rider)   AS result FROM counts
UNION ALL SELECT 2, 'ROW COUNTS', 'staging_station -> dim_station',
        CONCAT(staging_station, '  ->  ', dim_station) FROM counts
UNION ALL SELECT 3, 'ROW COUNTS', 'staging_trip   -> fact_trip',
        CONCAT(staging_trip, '  ->  ', fact_trip) FROM counts
UNION ALL SELECT 4, 'ROW COUNTS', 'staging_payment-> fact_payment',
        CONCAT(staging_payment, '  ->  ', fact_payment) FROM counts
UNION ALL SELECT 5, 'ROW COUNTS', 'dim_date / dim_time',
        CONCAT(dim_date, ' days, ', dim_time, ' hours') FROM counts
UNION ALL SELECT 6, 'ROW COUNTS', 'EXTRA CREDIT rider-months / riders',
        CONCAT(fact_rider_monthly, ' / ', agg_rider) FROM counts

UNION ALL SELECT 10, 'DEFECTS', 'trip rider_id not in dim_rider', CAST((
    SELECT COUNT(*) FROM dbo.fact_trip f
    LEFT JOIN dbo.dim_rider d ON d.rider_id = f.rider_id
    WHERE d.rider_id IS NULL) AS VARCHAR(20))
UNION ALL SELECT 11, 'DEFECTS', 'trip start_station not in dim_station', CAST((
    SELECT COUNT(*) FROM dbo.fact_trip f
    LEFT JOIN dbo.dim_station s ON s.station_id = f.start_station_id
    WHERE s.station_id IS NULL) AS VARCHAR(20))
UNION ALL SELECT 12, 'DEFECTS', 'trip end_station not in dim_station', CAST((
    SELECT COUNT(*) FROM dbo.fact_trip f
    LEFT JOIN dbo.dim_station s ON s.station_id = f.end_station_id
    WHERE s.station_id IS NULL) AS VARCHAR(20))
UNION ALL SELECT 13, 'DEFECTS', 'payment rider_id not in dim_rider', CAST((
    SELECT COUNT(*) FROM dbo.fact_payment p
    LEFT JOIN dbo.dim_rider d ON d.rider_id = p.rider_id
    WHERE d.rider_id IS NULL) AS VARCHAR(20))
UNION ALL SELECT 14, 'DEFECTS', 'payment date_key not in dim_date', CAST((
    SELECT COUNT(*) FROM dbo.fact_payment p
    LEFT JOIN dbo.dim_date d ON d.date_key = p.date_key
    WHERE d.date_key IS NULL) AS VARCHAR(20))
UNION ALL SELECT 15, 'DEFECTS', 'duplicate trip_id', CAST((
    SELECT COUNT(*) - COUNT(DISTINCT trip_id) FROM dbo.fact_trip) AS VARCHAR(20))
UNION ALL SELECT 16, 'DEFECTS', 'duplicate payment_id', CAST((
    SELECT COUNT(*) - COUNT(DISTINCT payment_id) FROM dbo.fact_payment) AS VARCHAR(20))
UNION ALL SELECT 17, 'DEFECTS', 'trips with NULL rider age', CAST((
    SELECT COUNT(*) FROM dbo.fact_trip WHERE rider_age_at_trip IS NULL) AS VARCHAR(20))
UNION ALL SELECT 18, 'DEFECTS', 'payments with NULL amount', CAST((
    SELECT COUNT(*) FROM dbo.fact_payment WHERE amount IS NULL) AS VARCHAR(20))

UNION ALL SELECT 20, 'RECONCILE', 'money: staging vs fact_payment', CONCAT(
    (SELECT FORMAT(SUM(TRY_CONVERT(DECIMAL(14,2),
        REPLACE(REPLACE(amount,'$',''),',',''))), 'N2') FROM dbo.staging_payment),
    '  =  ',
    (SELECT FORMAT(SUM(amount), 'N2') FROM dbo.fact_payment))
UNION ALL SELECT 21, 'RECONCILE', 'money: fact vs monthly vs agg', CONCAT(
    (SELECT FORMAT(SUM(amount), 'N2') FROM dbo.fact_payment), '  =  ',
    (SELECT FORMAT(SUM(amount_paid_in_month), 'N2') FROM dbo.fact_rider_monthly), '  =  ',
    (SELECT FORMAT(SUM(total_paid), 'N2') FROM dbo.agg_rider_spend_vs_rides))
UNION ALL SELECT 22, 'RECONCILE', 'rides: fact vs monthly vs agg', CONCAT(
    (SELECT FORMAT(COUNT(*), 'N0') FROM dbo.fact_trip), '  =  ',
    (SELECT FORMAT(SUM(rides_in_month), 'N0') FROM dbo.fact_rider_monthly), '  =  ',
    (SELECT FORMAT(SUM(total_rides), 'N0') FROM dbo.agg_rider_spend_vs_rides))

UNION ALL SELECT 30, 'KNOWN DATA ISSUES (kept, not deleted)',
    'trips ending before they start', CAST((
    SELECT COUNT(*) FROM dbo.fact_trip WHERE duration_seconds < 0) AS VARCHAR(20))
UNION ALL SELECT 31, 'KNOWN DATA ISSUES (kept, not deleted)',
    'trips over 24 hours (unreturned bikes)', CAST((
    SELECT COUNT(*) FROM dbo.fact_trip WHERE duration_seconds > 86400) AS VARCHAR(20))

ORDER BY seq;
