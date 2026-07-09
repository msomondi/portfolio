/*
Cloud Capacity & Cost Analytics Pipeline
data_quality_checks.sql

Purpose:
This file is the SQL data quality proof behind the portfolio project.
It shows the checks I would run before trusting the dashboard numbers.

Dataset note:
The data used in this project is simulated for portfolio purposes.
No real company, customer, or confidential cloud billing data is used.

Why these checks matter:
A dashboard can look clean but still be wrong if the data behind it has
missing values, duplicates, negative costs, invalid utilization, or broken joins.
These checks help make sure the final reporting is reliable.

Expected model:
fact_cloud_usage
dim_service
dim_region
dim_cost_center
dim_month
*/


/* ============================================================
   1. Check for missing key values in the fact table
   These fields are needed for reliable reporting.
   ============================================================ */

SELECT
    COUNT(*) AS records_with_missing_keys
FROM fact_cloud_usage
WHERE
    month_id IS NULL
    OR service_id IS NULL
    OR region_id IS NULL
    OR cost_center_id IS NULL;


/* ============================================================
   2. Check for missing measure values
   These are the numeric fields used for KPIs and dashboards.
   ============================================================ */

SELECT
    COUNT(*) AS records_with_missing_measures
FROM fact_cloud_usage
WHERE
    monthly_cost_eur IS NULL
    OR compute_hours IS NULL
    OR storage_gb IS NULL
    OR utilization_pct IS NULL;


/* ============================================================
   3. Check for duplicate service-month-region-cost center records
   A duplicate can make monthly cost look higher than it really is.
   ============================================================ */

SELECT
    month_id,
    service_id,
    region_id,
    cost_center_id,
    COUNT(*) AS duplicate_count
FROM fact_cloud_usage
GROUP BY
    month_id,
    service_id,
    region_id,
    cost_center_id
HAVING
    COUNT(*) > 1
ORDER BY
    duplicate_count DESC;


/* ============================================================
   4. Check for negative cost values
   Cloud cost should not be negative in this project context.
   ============================================================ */

SELECT
    *
FROM fact_cloud_usage
WHERE
    monthly_cost_eur < 0;


/* ============================================================
   5. Check for negative usage values
   Compute hours and storage usage should not be negative.
   ============================================================ */

SELECT
    *
FROM fact_cloud_usage
WHERE
    compute_hours < 0
    OR storage_gb < 0;


/* ============================================================
   6. Check utilization percentage range
   Utilization should normally be between 0 and 100.
   ============================================================ */

SELECT
    *
FROM fact_cloud_usage
WHERE
    utilization_pct < 0
    OR utilization_pct > 100;


/* ============================================================
   7. Check for missing service names
   A service without a name cannot be explained clearly in reporting.
   ============================================================ */

SELECT
    *
FROM dim_service
WHERE
    service_name IS NULL
    OR TRIM(service_name) = '';


/* ============================================================
   8. Check for blank region names
   A blank region makes regional cost analysis incomplete.
   ============================================================ */

SELECT
    *
FROM dim_region
WHERE
    region_name IS NULL
    OR TRIM(region_name) = '';


/* ============================================================
   9. Check for inconsistent region names
   This helps spot region names that may need standardization.
   ============================================================ */

SELECT
    region_name,
    COUNT(*) AS region_name_count
FROM dim_region
GROUP BY
    region_name
ORDER BY
    region_name_count DESC;


/* ============================================================
   10. Check for orphan service IDs
   Every service_id in the fact table should exist in dim_service.
   ============================================================ */

SELECT
    f.service_id,
    COUNT(*) AS affected_records
FROM fact_cloud_usage f
LEFT JOIN dim_service s
    ON f.service_id = s.service_id
WHERE
    s.service_id IS NULL
GROUP BY
    f.service_id;


/* ============================================================
   11. Check for orphan region IDs
   Every region_id in the fact table should exist in dim_region.
   ============================================================ */

SELECT
    f.region_id,
    COUNT(*) AS affected_records
FROM fact_cloud_usage f
LEFT JOIN dim_region r
    ON f.region_id = r.region_id
WHERE
    r.region_id IS NULL
GROUP BY
    f.region_id;


/* ============================================================
   12. Check for orphan cost center IDs
   Every cost_center_id in the fact table should exist in dim_cost_center.
   ============================================================ */

SELECT
    f.cost_center_id,
    COUNT(*) AS affected_records
FROM fact_cloud_usage f
LEFT JOIN dim_cost_center c
    ON f.cost_center_id = c.cost_center_id
WHERE
    c.cost_center_id IS NULL
GROUP BY
    f.cost_center_id;


/* ============================================================
   13. Check for orphan month IDs
   Every month_id in the fact table should exist in dim_month.
   ============================================================ */

SELECT
    f.month_id,
    COUNT(*) AS affected_records
FROM fact_cloud_usage f
LEFT JOIN dim_month m
    ON f.month_id = m.month_id
WHERE
    m.month_id IS NULL
GROUP BY
    f.month_id;


/* ============================================================
   14. Check for unrealistic high monthly cost values
   This does not mean the data is wrong automatically.
   It highlights records that should be reviewed.
   ============================================================ */

SELECT
    *
FROM fact_cloud_usage
WHERE
    monthly_cost_eur > 50000
ORDER BY
    monthly_cost_eur DESC;


/* ============================================================
   15. Check for high cost with very low utilization
   This is a business quality check because it may show possible waste.
   ============================================================ */

SELECT
    f.month_id,
    f.service_id,
    s.service_name,
    f.region_id,
    r.region_name,
    f.monthly_cost_eur,
    f.utilization_pct
FROM fact_cloud_usage f
JOIN dim_service s
    ON f.service_id = s.service_id
JOIN dim_region r
    ON f.region_id = r.region_id
WHERE
    f.monthly_cost_eur > 5000
    AND f.utilization_pct < 40
ORDER BY
    f.monthly_cost_eur DESC;


/* ============================================================
   16. Check for services with cost but zero usage
   This can happen in cloud reporting, but it should be reviewed.
   ============================================================ */

SELECT
    f.month_id,
    s.service_name,
    r.region_name,
    f.monthly_cost_eur,
    f.compute_hours,
    f.storage_gb
FROM fact_cloud_usage f
JOIN dim_service s
    ON f.service_id = s.service_id
JOIN dim_region r
    ON f.region_id = r.region_id
WHERE
    f.monthly_cost_eur > 0
    AND f.compute_hours = 0
    AND f.storage_gb = 0
ORDER BY
    f.monthly_cost_eur DESC;


/* ============================================================
   17. Check monthly record count
   Sudden drops in record count may mean a data load problem.
   ============================================================ */

SELECT
    m.year,
    m.month_number,
    m.month_name,
    COUNT(*) AS record_count
FROM fact_cloud_usage f
JOIN dim_month m
    ON f.month_id = m.month_id
GROUP BY
    m.year,
    m.month_number,
    m.month_name
ORDER BY
    m.year,
    m.month_number;


/* ============================================================
   18. Check monthly cost totals for sudden jumps
   This helps identify unusual cost movement before reporting.
   ============================================================ */

WITH monthly_cost AS (
    SELECT
        m.year,
        m.month_number,
        m.month_name,
        SUM(f.monthly_cost_eur) AS total_cost_eur
    FROM fact_cloud_usage f
    JOIN dim_month m
        ON f.month_id = m.month_id
    GROUP BY
        m.year,
        m.month_number,
        m.month_name
),
monthly_cost_change AS (
    SELECT
        year,
        month_number,
        month_name,
        total_cost_eur,
        LAG(total_cost_eur) OVER (
            ORDER BY year, month_number
        ) AS previous_month_cost_eur
    FROM monthly_cost
)
SELECT
    year,
    month_name,
    total_cost_eur,
    previous_month_cost_eur,
    ROUND(
        ((total_cost_eur - previous_month_cost_eur) / NULLIF(previous_month_cost_eur, 0)) * 100,
        2
    ) AS monthly_cost_change_pct
FROM monthly_cost_change
WHERE
    previous_month_cost_eur IS NOT NULL
    AND ABS(
        ((total_cost_eur - previous_month_cost_eur) / NULLIF(previous_month_cost_eur, 0)) * 100
    ) > 30
ORDER BY
    monthly_cost_change_pct DESC;


/* ============================================================
   19. Final data quality summary
   This gives one simple overview that can be used before dashboard refresh.
   ============================================================ */

SELECT
    'missing_keys' AS check_name,
    COUNT(*) AS issue_count
FROM fact_cloud_usage
WHERE
    month_id IS NULL
    OR service_id IS NULL
    OR region_id IS NULL
    OR cost_center_id IS NULL

UNION ALL

SELECT
    'missing_measures' AS check_name,
    COUNT(*) AS issue_count
FROM fact_cloud_usage
WHERE
    monthly_cost_eur IS NULL
    OR compute_hours IS NULL
    OR storage_gb IS NULL
    OR utilization_pct IS NULL

UNION ALL

SELECT
    'negative_costs' AS check_name,
    COUNT(*) AS issue_count
FROM fact_cloud_usage
WHERE
    monthly_cost_eur < 0

UNION ALL

SELECT
    'negative_usage' AS check_name,
    COUNT(*) AS issue_count
FROM fact_cloud_usage
WHERE
    compute_hours < 0
    OR storage_gb < 0

UNION ALL

SELECT
    'invalid_utilization' AS check_name,
    COUNT(*) AS issue_count
FROM fact_cloud_usage
WHERE
    utilization_pct < 0
    OR utilization_pct > 100

UNION ALL

SELECT
    'duplicate_service_month_records' AS check_name,
    COUNT(*) AS issue_count
FROM (
    SELECT
        month_id,
        service_id,
        region_id,
        cost_center_id
    FROM fact_cloud_usage
    GROUP BY
        month_id,
        service_id,
        region_id,
        cost_center_id
    HAVING
        COUNT(*) > 1
) duplicates;


/* ============================================================
   20. Data quality status message
   This is a simple readable check for the end of the process.
   ============================================================ */

WITH quality_summary AS (
    SELECT
        SUM(issue_count) AS total_issue_count
    FROM (
        SELECT COUNT(*) AS issue_count
        FROM fact_cloud_usage
        WHERE
            month_id IS NULL
            OR service_id IS NULL
            OR region_id IS NULL
            OR cost_center_id IS NULL

        UNION ALL

        SELECT COUNT(*) AS issue_count
        FROM fact_cloud_usage
        WHERE
            monthly_cost_eur IS NULL
            OR compute_hours IS NULL
            OR storage_gb IS NULL
            OR utilization_pct IS NULL

        UNION ALL

        SELECT COUNT(*) AS issue_count
        FROM fact_cloud_usage
        WHERE
            monthly_cost_eur < 0

        UNION ALL

        SELECT COUNT(*) AS issue_count
        FROM fact_cloud_usage
        WHERE
            compute_hours < 0
            OR storage_gb < 0

        UNION ALL

        SELECT COUNT(*) AS issue_count
        FROM fact_cloud_usage
        WHERE
            utilization_pct < 0
            OR utilization_pct > 100
    ) checks
)
SELECT
    total_issue_count,
    CASE
        WHEN total_issue_count = 0
            THEN 'Data quality check passed. Dataset is ready for reporting.'
        ELSE 'Data quality issues found. Review before dashboard refresh.'
    END AS data_quality_status
FROM quality_summary;
