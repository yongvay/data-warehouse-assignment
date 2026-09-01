-- ============================================================================
-- TASK 3 - STUDENT D (TEO PEI QI)
-- D2. DELIVERY PARTNER PERFORMANCE BY REGION
--
-- Business Question:
--   Which delivery partners perform best in each region, and are lower-cost
--   couriers actually cost-efficient after delays and cancellations?
--
-- 5W Analytical Structure:
--   D2.1 WHERE + WHAT
--        What is happening, and where is delivery performance strongest/weakest?
--
--   D2.2 WHO
--        Which delivery company performs best within each region?
--
--   D2.3 WHY
--        Does a lower delivery charge actually produce better value, or is a
--        cheaper courier a false economy when service performance is weaker?
--
--   D2.4 WHEN
--        How does on-time performance change month by month?
--
-- Facts / Dimensions:
--   DELIVERY_FACT
--   DELIVERY_COMPANY_DIM
--   ADDRESS_DIM
--   DATE_DIM
--
-- Cohort Rule:
--   The report is filtered by DELIVERY_FACT.ORDER_DATE_KEY so all analysed
--   deliveries belong to the same original-order year.
--
-- Service Definitions:
--   Delivered order  = DELIVERY_STATUS = 'Delivered'
--   On-time delivery = Delivered with DELIVERY_LEAD_DAYS <= 3
--   Cancelled %      = Cancelled deliveries / all deliveries
--   On-Time %        = On-time delivered orders / delivered orders
--
-- Cost Definitions:
--   Avg Delivery Charge = average charge across delivery records
--
--   Cost per Delivered Order =
--       total delivery charges / number of successfully delivered orders
--
--   The second measure intentionally retains charges from all delivery records
--   in the numerator, so cancellation / unsuccessful-delivery burden remains
--   visible in the effective cost.
--
-- Final Chart Count:
--   2 charts only
--   1. D2.2 - Grouped Bar Chart
--   2. D2.4 - Line Chart
-- ============================================================================

SET DEFINE ON
SET SQLBLANKLINES ON
SET VERIFY OFF
SET FEEDBACK OFF
SET TRIMSPOOL ON
SET TAB OFF
SET LINESIZE 190
SET PAGESIZE 100
SET NULL '-'

ACCEPT p_year CHAR DEFAULT '2025' PROMPT 'Enter original order year [2025]: '
ACCEPT p_region CHAR DEFAULT 'ALL' PROMPT 'Enter destination region [ALL]: '

PROMPT
PROMPT ====================================================================================================
PROMPT D2 - DELIVERY PARTNER PERFORMANCE BY REGION
PROMPT Business Question : Which delivery partners perform best by region?
PROMPT Order Year        : &p_year
PROMPT Destination Region: &p_region
PROMPT Final Charts      : 2
PROMPT ====================================================================================================
PROMPT

-- ============================================================================
-- EXHIBIT D2.1
-- WHERE + WHAT
-- WHAT IS HAPPENING, AND WHERE IS DELIVERY PERFORMANCE STRONGEST / WEAKEST?
-- ============================================================================

PROMPT ====================================================================================================
PROMPT EXHIBIT D2.1 - WHERE + WHAT: REGIONAL DELIVERY PERFORMANCE OVERVIEW
PROMPT Chart type : Supporting Table (No Separate Chart)
PROMPT Purpose    : Shows what delivery performance looks like and where service risk is concentrated.
PROMPT ====================================================================================================
PROMPT

COLUMN address_region             HEADING 'Region'                    FORMAT A20
COLUMN deliveries                 HEADING 'Deliveries'                FORMAT 999,990
COLUMN delivered_orders           HEADING 'Delivered'                 FORMAT 999,990
COLUMN delivered_pct              HEADING 'Delivered|%'               FORMAT 990.99
COLUMN cancelled_orders           HEADING 'Cancelled'                 FORMAT 999,990
COLUMN cancelled_pct              HEADING 'Cancelled|%'               FORMAT 990.99
COLUMN avg_lead_days              HEADING 'Avg Lead|Days'             FORMAT 990.99
COLUMN on_time_pct                HEADING 'On-Time|%'                 FORMAT 990.99
COLUMN avg_delivery_charge        HEADING 'Avg Charge|(RM)'           FORMAT 999,990.00
COLUMN cost_per_delivered_order   HEADING 'Cost / Delivered|(RM)'     FORMAT 999,990.00

WITH base AS (
    SELECT
        a.address_region,
        df.delivery_status,
        df.delivery_charge,
        df.delivery_lead_days
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
),
regional AS (
    SELECT
        address_region,
        COUNT(*) AS deliveries,

        SUM(CASE
                WHEN delivery_status = 'Delivered'
                THEN 1 ELSE 0
            END) AS delivered_orders,

        SUM(CASE
                WHEN delivery_status = 'Cancelled'
                THEN 1 ELSE 0
            END) AS cancelled_orders,

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
    GROUP BY address_region
)
SELECT
    address_region,
    deliveries,
    delivered_orders,
    ROUND(
        100 * delivered_orders / NULLIF(deliveries, 0),
        2
    ) AS delivered_pct,
    cancelled_orders,
    ROUND(
        100 * cancelled_orders / NULLIF(deliveries, 0),
        2
    ) AS cancelled_pct,
    ROUND(avg_lead_days, 2) AS avg_lead_days,
    ROUND(on_time_pct, 2) AS on_time_pct,
    ROUND(avg_delivery_charge, 2) AS avg_delivery_charge,
    ROUND(cost_per_delivered_order, 2) AS cost_per_delivered_order
FROM regional
ORDER BY
    cancelled_pct DESC,
    on_time_pct ASC,
    avg_lead_days DESC,
    address_region;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D2.2
-- WHO
-- WHICH DELIVERY COMPANY PERFORMS BEST WITHIN EACH REGION?
-- REQUIRED CHART: GROUPED BAR
-- ============================================================================

PROMPT
PROMPT ====================================================================================================
PROMPT EXHIBIT D2.2 - WHO: DELIVERY PARTNER PERFORMANCE BY REGION
PROMPT Chart type : Grouped Bar Chart
PROMPT Chart      : Average Lead Days by Delivery Company x Region
PROMPT Purpose    : Compares and ranks courier performance within each destination region.
PROMPT ====================================================================================================
PROMPT

COLUMN performance_rank           HEADING 'Rank'                    FORMAT 9999
COLUMN address_region             HEADING 'Region'                  FORMAT A18
COLUMN company_name               HEADING 'Company'                 FORMAT A26
COLUMN deliveries                 HEADING 'Deliveries'              FORMAT 999,990
COLUMN volume_share_pct           HEADING 'Volume|Share %'          FORMAT 990.99
COLUMN avg_lead_days              HEADING 'Avg Lead|Days'           FORMAT 990.99
COLUMN on_time_pct                HEADING 'On-Time|%'               FORMAT 990.99
COLUMN cancelled_pct              HEADING 'Cancelled|%'             FORMAT 990.99
COLUMN avg_delivery_charge        HEADING 'Avg Charge|(RM)'         FORMAT 999,990.00
COLUMN cost_per_delivered_order   HEADING 'Cost / Delivered|(RM)'   FORMAT 999,990.00

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
),
with_share AS (
    SELECT
        m.*,
        100 * m.deliveries
            / NULLIF(
                SUM(m.deliveries) OVER (
                    PARTITION BY m.address_region
                ),
                0
              ) AS volume_share_pct
    FROM metrics m
),
ranked AS (
    SELECT
        ws.*,
        DENSE_RANK() OVER (
            PARTITION BY ws.address_region
            ORDER BY
                ws.on_time_pct DESC NULLS LAST,
                ws.cancelled_pct ASC NULLS LAST,
                ws.avg_lead_days ASC NULLS LAST,
                ws.cost_per_delivered_order ASC NULLS LAST
        ) AS performance_rank
    FROM with_share ws
)
SELECT
    performance_rank,
    address_region,
    company_name,
    deliveries,
    ROUND(volume_share_pct, 2) AS volume_share_pct,
    ROUND(avg_lead_days, 2) AS avg_lead_days,
    ROUND(on_time_pct, 2) AS on_time_pct,
    ROUND(cancelled_pct, 2) AS cancelled_pct,
    ROUND(avg_delivery_charge, 2) AS avg_delivery_charge,
    ROUND(cost_per_delivered_order, 2) AS cost_per_delivered_order
FROM ranked
ORDER BY
    address_region,
    performance_rank,
    company_name;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D2.3
-- WHY
-- DOES A LOWER CHARGE ACTUALLY MEAN BETTER VALUE?
-- ============================================================================

PROMPT
PROMPT ====================================================================================================
PROMPT EXHIBIT D2.3 - WHY: COST VS SERVICE TRADE-OFF
PROMPT Chart type : Supporting Table (No Separate Chart)
PROMPT Purpose    : Tests whether cheaper couriers also deliver acceptable service within each region.
PROMPT Note       : Negative Charge vs Avg = cheaper than regional courier average.
PROMPT Note       : Positive On-Time vs Avg = better than regional courier average.
PROMPT ====================================================================================================
PROMPT

COLUMN address_region              HEADING 'Region'                 FORMAT A18
COLUMN company_name                HEADING 'Company'                FORMAT A26
COLUMN deliveries                  HEADING 'Deliveries'             FORMAT 999,990
COLUMN avg_delivery_charge         HEADING 'Avg Charge|(RM)'        FORMAT 999,990.00
COLUMN charge_vs_region_avg        HEADING 'Charge vs Avg|(RM)'     FORMAT 999,990.00
COLUMN on_time_pct                 HEADING 'On-Time|%'              FORMAT 990.99
COLUMN on_time_vs_region_avg       HEADING 'On-Time vs Avg|(pp)'    FORMAT 9990.99
COLUMN cancelled_pct               HEADING 'Cancelled|%'            FORMAT 990.99
COLUMN cost_per_delivered_order    HEADING 'Cost / Delivered|(RM)'  FORMAT 999,990.00

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
        AVG(delivery_charge) AS avg_delivery_charge,

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
),
benchmarked AS (
    SELECT
        m.*,
        AVG(m.avg_delivery_charge)
            OVER (PARTITION BY m.address_region)
            AS region_avg_charge,
        AVG(m.on_time_pct)
            OVER (PARTITION BY m.address_region)
            AS region_avg_on_time
    FROM metrics m
)
SELECT
    address_region,
    company_name,
    deliveries,
    ROUND(avg_delivery_charge, 2) AS avg_delivery_charge,
    ROUND(
        avg_delivery_charge - region_avg_charge,
        2
    ) AS charge_vs_region_avg,
    ROUND(on_time_pct, 2) AS on_time_pct,
    ROUND(
        on_time_pct - region_avg_on_time,
        2
    ) AS on_time_vs_region_avg,
    ROUND(cancelled_pct, 2) AS cancelled_pct,
    ROUND(
        cost_per_delivered_order,
        2
    ) AS cost_per_delivered_order
FROM benchmarked
ORDER BY
    address_region,
    on_time_vs_region_avg ASC,
    cancelled_pct DESC,
    company_name;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D2.4
-- WHEN
-- HOW DOES ON-TIME PERFORMANCE CHANGE MONTH BY MONTH?
-- REQUIRED CHART: LINE
-- ============================================================================

PROMPT
PROMPT ====================================================================================================
PROMPT EXHIBIT D2.4 - WHEN: MONTHLY ON-TIME PERFORMANCE TREND
PROMPT Chart type : Line Chart
PROMPT Chart      : Monthly On-Time % by Delivery Company
PROMPT Purpose    : Shows whether courier service is stable or changes during the year.
PROMPT Note       : Interpret On-Time % together with Delivered volume because small monthly samples
PROMPT              can create extreme percentages such as 0% or 100%.
PROMPT ====================================================================================================
PROMPT

COLUMN month_name      HEADING 'Month'          FORMAT A12
COLUMN company_name    HEADING 'Company'        FORMAT A26
COLUMN delivered       HEADING 'Delivered'      FORMAT 999,990
COLUMN on_time         HEADING 'On-Time'        FORMAT 999,990
COLUMN on_time_pct     HEADING 'On-Time|%'      FORMAT 990.99

WITH monthly AS (
    SELECT
        d.cal_month_year AS month_no,
        d.cal_month_name AS month_name,
        dc.company_name,

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
    GROUP BY
        d.cal_month_year,
        d.cal_month_name,
        dc.company_name
)
SELECT
    month_name,
    company_name,
    delivered,
    on_time,
    ROUND(
        100 * on_time / NULLIF(delivered, 0),
        2
    ) AS on_time_pct
FROM monthly
WHERE delivered > 0
ORDER BY
    month_no,
    company_name;

CLEAR COLUMNS

-- ============================================================================
-- DATA QUALITY CHECKS
-- ============================================================================

PROMPT
PROMPT ====================================================================================================
PROMPT D2 DATA QUALITY CHECKS
PROMPT ====================================================================================================
PROMPT

COLUMN dq_check   HEADING 'Check'  FORMAT A38
COLUMN dq_status  HEADING 'Status' FORMAT A70

WITH selected_rows AS (
    SELECT
        df.delivery_status,
        df.delivery_lead_days,
        df.delivery_charge
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
),
checks AS (
    SELECT
        'Delivered rows missing lead days' AS dq_check,
        SUM(CASE
                WHEN delivery_status = 'Delivered'
                 AND delivery_lead_days IS NULL
                THEN 1 ELSE 0
            END) AS bad_count
    FROM selected_rows

    UNION ALL

    SELECT
        'Negative delivery lead days',
        SUM(CASE
                WHEN delivery_lead_days < 0
                THEN 1 ELSE 0
            END)
    FROM selected_rows

    UNION ALL

    SELECT
        'Negative delivery charges',
        SUM(CASE
                WHEN delivery_charge < 0
                THEN 1 ELSE 0
            END)
    FROM selected_rows
)
SELECT
    dq_check,
    CASE
        WHEN bad_count = 0
        THEN 'PASS'
        ELSE 'CHECK - ' || bad_count || ' row(s)'
    END AS dq_status
FROM checks
ORDER BY dq_check;

CLEAR COLUMNS

PROMPT
PROMPT ====================================================================================================
PROMPT END OF D2 - DELIVERY PARTNER PERFORMANCE BY REGION
PROMPT ====================================================================================================
PROMPT

UNDEFINE p_year
UNDEFINE p_region

SET FEEDBACK ON
