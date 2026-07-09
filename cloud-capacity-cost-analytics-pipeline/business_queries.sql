/*
Cloud Capacity & Cost Analytics Pipeline
business_queries.sql

Purpose:
This file is the SQL proof behind the portfolio project.
It shows how I would turn cleaned cloud usage data into business questions,
KPIs, dashboard views, and cost optimization recommendations.

Dataset note:
The data used in this project is simulated for portfolio purposes.
No real company, customer, or confidential cloud billing data is used.

Expected model:
fact_cloud_usage
dim_service
dim_region
dim_cost_center
dim_month

Main business questions:
1. Which services drive the highest cloud cost?
2. Which regions are showing growing capacity demand?
3. Which services are expensive but not fully used?
4. Which cost centers need earlier planning visibility?
5. Where should the business review possible cloud waste?
*/


/* ============================================================
   1. Total monthly cloud cost
   This gives the main cost KPI for the dashboard.
   ============================================================ */

SELECT
    m.year,
    m.month_name,
    SUM(f.monthly_cost_eur) AS total_monthly_cloud_cost_eur
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
   2. Monthly cost change
   This helps show whether cost is growing or falling.
   It is useful for the dashboard KPI: cost increase vs previous month.
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
cost_with_previous_month AS (
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
        ((total_cost_eur - previous_month_cost_eur) / previous_month_cost_eur) * 100,
        2
    ) AS cost_change_pct
FROM cost_with_previous_month
ORDER BY
    year,
    month_number;


/* ============================================================
   3. Top cloud services by total cost
   This answers: Which services drive the highest monthly cost?
   ============================================================ */

SELECT
    s.service_name,
    SUM(f.monthly_cost_eur) AS total_cost_eur,
    SUM(f.compute_hours) AS total_compute_hours,
    SUM(f.storage_gb) AS total_storage_gb,
    ROUND(AVG(f.utilization_pct), 2) AS avg_utilization_pct
FROM fact_cloud_usage f
JOIN dim_service s
    ON f.service_id = s.service_id
GROUP BY
    s.service_name
ORDER BY
    total_cost_eur DESC;


/* ============================================================
   4. Cost by service and region
   This helps the business see where cloud cost is coming from.
   ============================================================ */

SELECT
    s.service_name,
    r.region_name,
    SUM(f.monthly_cost_eur) AS total_cost_eur,
    ROUND(AVG(f.utilization_pct), 2) AS avg_utilization_pct,
    SUM(f.compute_hours) AS total_compute_hours,
    SUM(f.storage_gb) AS total_storage_gb
FROM fact_cloud_usage f
JOIN dim_service s
    ON f.service_id = s.service_id
JOIN dim_region r
    ON f.region_id = r.region_id
GROUP BY
    s.service_name,
    r.region_name
ORDER BY
    total_cost_eur DESC;


/* ============================================================
   5. High-cost services with low utilization
   This is the main cost optimization watch list.

   Business meaning:
   These services are expensive, but they are not being used strongly.
   This does not automatically mean they are waste.
   It means they should be reviewed before costs grow further.
   ============================================================ */

SELECT
    s.service_name,
    r.region_name,
    SUM(f.monthly_cost_eur) AS total_cost_eur,
    ROUND(AVG(f.utilization_pct), 2) AS avg_utilization_pct,
    SUM(f.compute_hours) AS total_compute_hours
FROM fact_cloud_usage f
JOIN dim_service s
    ON f.service_id = s.service_id
JOIN dim_region r
    ON f.region_id = r.region_id
GROUP BY
    s.service_name,
    r.region_name
HAVING
    SUM(f.monthly_cost_eur) > 5000
    AND AVG(f.utilization_pct) < 40
ORDER BY
    total_cost_eur DESC;


/* ============================================================
   6. Compute demand trend by month
   This supports capacity planning.
   It helps answer: Is compute demand growing?
   ============================================================ */

SELECT
    m.year,
    m.month_number,
    m.month_name,
    SUM(f.compute_hours) AS total_compute_hours,
    ROUND(AVG(f.utilization_pct), 2) AS avg_utilization_pct
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
   7. Storage usage by service
   This helps show which services are using the most storage.
   ============================================================ */

SELECT
    s.service_name,
    SUM(f.storage_gb) AS total_storage_gb,
    SUM(f.monthly_cost_eur) AS total_cost_eur,
    ROUND(
        SUM(f.monthly_cost_eur) / NULLIF(SUM(f.storage_gb), 0),
        4
    ) AS cost_per_storage_gb
FROM fact_cloud_usage f
JOIN dim_service s
    ON f.service_id = s.service_id
GROUP BY
    s.service_name
ORDER BY
    total_storage_gb DESC;


/* ============================================================
   8. Region growth view
   This helps identify regions where demand is rising.
   It supports earlier planning visibility.
   ============================================================ */

SELECT
    r.region_name,
    m.year,
    m.month_number,
    m.month_name,
    SUM(f.monthly_cost_eur) AS total_cost_eur,
    SUM(f.compute_hours) AS total_compute_hours,
    SUM(f.storage_gb) AS total_storage_gb
FROM fact_cloud_usage f
JOIN dim_region r
    ON f.region_id = r.region_id
JOIN dim_month m
    ON f.month_id = m.month_id
GROUP BY
    r.region_name,
    m.year,
    m.month_number,
    m.month_name
ORDER BY
    r.region_name,
    m.year,
    m.month_number;


/* ============================================================
   9. Cost by cost center
   This shows which teams or departments are responsible for cost.
   It is useful for monthly cost review meetings.
   ============================================================ */

SELECT
    c.cost_center_name,
    c.business_unit,
    SUM(f.monthly_cost_eur) AS total_cost_eur,
    SUM(f.compute_hours) AS total_compute_hours,
    SUM(f.storage_gb) AS total_storage_gb,
    ROUND(AVG(f.utilization_pct), 2) AS avg_utilization_pct
FROM fact_cloud_usage f
JOIN dim_cost_center c
    ON f.cost_center_id = c.cost_center_id
GROUP BY
    c.cost_center_name,
    c.business_unit
ORDER BY
    total_cost_eur DESC;


/* ============================================================
   10. Dashboard KPI summary
   This query brings the most important KPIs into one view.
   ============================================================ */

SELECT
    SUM(monthly_cost_eur) AS total_cloud_cost_eur,
    ROUND(AVG(utilization_pct), 2) AS avg_capacity_utilization_pct,
    SUM(compute_hours) AS total_compute_hours,
    SUM(storage_gb) AS total_storage_gb,
    COUNT(*) AS usage_records
FROM fact_cloud_usage;


/* ============================================================
   11. Services where cost increased faster than compute usage
   This is useful because not every cost increase is bad.
   But if cost grows faster than usage, the team should ask why.
   ============================================================ */

WITH service_month AS (
    SELECT
        s.service_name,
        m.year,
        m.month_number,
        SUM(f.monthly_cost_eur) AS monthly_cost_eur,
        SUM(f.compute_hours) AS monthly_compute_hours
    FROM fact_cloud_usage f
    JOIN dim_service s
        ON f.service_id = s.service_id
    JOIN dim_month m
        ON f.month_id = m.month_id
    GROUP BY
        s.service_name,
        m.year,
        m.month_number
),
comparison AS (
    SELECT
        service_name,
        year,
        month_number,
        monthly_cost_eur,
        monthly_compute_hours,
        LAG(monthly_cost_eur) OVER (
            PARTITION BY service_name
            ORDER BY year, month_number
        ) AS previous_cost_eur,
        LAG(monthly_compute_hours) OVER (
            PARTITION BY service_name
            ORDER BY year, month_number
        ) AS previous_compute_hours
    FROM service_month
)
SELECT
    service_name,
    year,
    month_number,
    monthly_cost_eur,
    previous_cost_eur,
    monthly_compute_hours,
    previous_compute_hours,
    ROUND(
        ((monthly_cost_eur - previous_cost_eur) / NULLIF(previous_cost_eur, 0)) * 100,
        2
    ) AS cost_growth_pct,
    ROUND(
        ((monthly_compute_hours - previous_compute_hours) / NULLIF(previous_compute_hours, 0)) * 100,
        2
    ) AS compute_growth_pct
FROM comparison
WHERE
    previous_cost_eur IS NOT NULL
    AND previous_compute_hours IS NOT NULL
    AND (
        ((monthly_cost_eur - previous_cost_eur) / NULLIF(previous_cost_eur, 0)) >
        ((monthly_compute_hours - previous_compute_hours) / NULLIF(previous_compute_hours, 0))
    )
ORDER BY
    cost_growth_pct DESC;


/* ============================================================
   12. Business recommendation view
   This turns the analysis into simple business actions.
   ============================================================ */

SELECT
    s.service_name,
    r.region_name,
    SUM(f.monthly_cost_eur) AS total_cost_eur,
    ROUND(AVG(f.utilization_pct), 2) AS avg_utilization_pct,
    CASE
        WHEN SUM(f.monthly_cost_eur) > 5000
             AND AVG(f.utilization_pct) < 40
            THEN 'Review for possible cloud waste'
        WHEN SUM(f.compute_hours) > 5000
             AND AVG(f.utilization_pct) >= 70
            THEN 'Plan capacity early'
        WHEN SUM(f.storage_gb) > 15000
            THEN 'Review storage growth and archiving'
        ELSE 'Monitor normally'
    END AS recommended_action
FROM fact_cloud_usage f
JOIN dim_service s
    ON f.service_id = s.service_id
JOIN dim_region r
    ON f.region_id = r.region_id
GROUP BY
    s.service_name,
    r.region_name
ORDER BY
    total_cost_eur DESC;
