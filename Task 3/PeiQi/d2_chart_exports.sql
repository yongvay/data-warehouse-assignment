-- ============================================================================
-- TASK 3 - STUDENT D (TEO PEI QI)
-- D2 CHART CSV EXPORT
-- Oracle SQL*Plus 11g compatible
--
-- Creates:
--   C:\Users\tpq11\task3_csv\d2_avg_lead_by_region_company.csv
--   C:\Users\tpq11\task3_csv\d2_monthly_ontime.csv
--
-- Chart mapping:
--   Exhibit D2.2 -> Grouped Bar Chart
--   Exhibit D2.4 -> Line Chart (Overall Monthly On-Time %)
-- ============================================================================

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TERMOUT ON
SET PAGESIZE 0
SET LINESIZE 32767
SET TRIMSPOOL ON
SET TAB OFF

ACCEPT p_year CHAR DEFAULT '2025' PROMPT 'Enter original order year [2025]: '
ACCEPT p_region CHAR DEFAULT 'ALL' PROMPT 'Enter destination region [ALL]: '

PROMPT
PROMPT Exporting D2 chart data for &p_year ...
PROMPT

SET TERMOUT OFF

-- ============================================================================
-- EXHIBIT D2.2
-- GROUPED BAR CHART: AVG LEAD DAYS BY DELIVERY COMPANY x REGION
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d2_avg_lead_by_region_company.csv

PROMPT Region,Company,Deliveries,Avg Lead Days,On-Time %,Cancelled %,Avg Charge,Cost per Delivered Order

WITH base AS (
    SELECT
        a.address_region,
        dc.company_name,
        df.delivery_status,
        df.delivery_charge,
        df.delivery_lead_days
    FROM delivery_fact df
    JOIN delivery_company_dim dc
      ON dc.delivery_company_key = df.delivery_company_key
    JOIN address_dim a
      ON a.address_key = df.address_key
    JOIN date_dim d
      ON d.date_key = df.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND df.delivery_company_key <> -1
      AND df.address_key <> -1
      AND UPPER(dc.company_name) <> 'UNKNOWN'
      AND UPPER(a.address_region) <> 'UNKNOWN'
      AND (
            UPPER(TRIM('&p_region')) = 'ALL'
            OR UPPER(a.address_region) = UPPER(TRIM('&p_region'))
          )
),
metrics AS (
    SELECT
        address_region,
        company_name,
        COUNT(*) AS deliveries,

        AVG(CASE
                WHEN delivery_status = 'Delivered'
                THEN delivery_lead_days
            END) AS avg_lead_days,

        100 * SUM(CASE
                      WHEN delivery_status = 'Delivered'
                       AND delivery_lead_days <= 3
                      THEN 1 ELSE 0
                  END)
            / NULLIF(
                SUM(CASE
                        WHEN delivery_status = 'Delivered'
                        THEN 1 ELSE 0
                    END),
                0
              ) AS on_time_pct,

        100 * SUM(CASE
                      WHEN delivery_status = 'Cancelled'
                      THEN 1 ELSE 0
                  END)
            / NULLIF(COUNT(*), 0) AS cancelled_pct,

        AVG(delivery_charge) AS avg_delivery_charge,

        SUM(delivery_charge)
            / NULLIF(
                SUM(CASE
                        WHEN delivery_status = 'Delivered'
                        THEN 1 ELSE 0
                    END),
                0
              ) AS cost_per_delivered_order

    FROM base
    GROUP BY
        address_region,
        company_name
)
SELECT
    '"' || REPLACE(address_region, '"', '""') || '",' ||
    '"' || REPLACE(company_name, '"', '""') || '",' ||
    TO_CHAR(deliveries) || ',' ||
    TO_CHAR(ROUND(avg_lead_days, 2), 'FM990.00') || ',' ||
    TO_CHAR(ROUND(on_time_pct, 2), 'FM990.00') || ',' ||
    TO_CHAR(ROUND(cancelled_pct, 2), 'FM990.00') || ',' ||
    TO_CHAR(ROUND(avg_delivery_charge, 2), 'FM999990.00') || ',' ||
    TO_CHAR(ROUND(cost_per_delivered_order, 2), 'FM999990.00')
FROM metrics
ORDER BY
    address_region,
    company_name;

SPOOL OFF

-- ============================================================================
-- EXHIBIT D2.4
-- LINE CHART: OVERALL MONTHLY ON-TIME DELIVERY %
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d2_monthly_ontime.csv

PROMPT Month,Month Order,Delivered,On-Time,On-Time %

WITH monthly AS (
    SELECT
        d.cal_month_year AS month_order,
        d.cal_month_name AS month_name,
        SUM(CASE
                WHEN df.delivery_status = 'Delivered'
                THEN 1 ELSE 0
            END) AS delivered,
        SUM(CASE
                WHEN df.delivery_status = 'Delivered'
                 AND df.delivery_lead_days <= 3
                THEN 1 ELSE 0
            END) AS on_time
    FROM delivery_fact df
    JOIN address_dim a
      ON a.address_key = df.address_key
    JOIN date_dim d
      ON d.date_key = df.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND df.address_key <> -1
      AND UPPER(a.address_region) <> 'UNKNOWN'
      AND (
            UPPER(TRIM('&p_region')) = 'ALL'
            OR UPPER(a.address_region) = UPPER(TRIM('&p_region'))
          )
    GROUP BY
        d.cal_month_year,
        d.cal_month_name
)
SELECT
    '"' || month_name || '",' ||
    TO_CHAR(month_order) || ',' ||
    TO_CHAR(delivered) || ',' ||
    TO_CHAR(on_time) || ',' ||
    TO_CHAR(
        ROUND(100 * on_time / NULLIF(delivered, 0), 2),
        'FM990.00'
    )
FROM monthly
WHERE delivered > 0
ORDER BY
    month_order;

SPOOL OFF

SET TERMOUT ON
SET HEADING ON
SET FEEDBACK ON

PROMPT
PROMPT Export complete.
PROMPT Files created:
PROMPT   C:\Users\tpq11\task3_csv\d2_avg_lead_by_region_company.csv
PROMPT   C:\Users\tpq11\task3_csv\d2_monthly_ontime.csv
PROMPT

UNDEFINE p_year
UNDEFINE p_region
