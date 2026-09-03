-- ============================================================================
-- D3 CHART EXPORTS
-- PROMOTION EFFECTIVENESS AND DISCOUNT ROI
--
-- Files:
--   C:\Users\tpq11\task3_csv\d3_campaign_financial.csv
--   C:\Users\tpq11\task3_csv\d3_promo_vs_baseline.csv
-- ============================================================================

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TRIMSPOOL ON
SET TERMOUT ON

ACCEPT p_year CHAR DEFAULT '2025' PROMPT 'Enter promotion analysis year [2025]: '

PROMPT
PROMPT Exporting D3 chart data for &p_year ...
PROMPT

-- ============================================================================
-- CHART 1
-- D3.1 - NET SALES + DISCOUNT-TO-GROSS %
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d3_campaign_financial.csv

PROMPT Promotion,Net Sales,Discount to Gross %

WITH promo_sales AS (
    SELECT
        sf.promo_key,
        SUM(sf.gross_sales_amt) AS gross_sales,
        SUM(sf.discount_amt) AS discount_given,
        SUM(sf.net_sales_amt) AS net_sales
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key
)
SELECT
    '"' || REPLACE(p.promo_name, '"', '""') || '",' ||
    TO_CHAR(ps.net_sales, 'FM999999990.00') || ',' ||
    TO_CHAR(
        100 * ps.discount_given / NULLIF(ps.gross_sales, 0),
        'FM990.00'
    )
FROM promo_sales ps
JOIN promotion_dim p
  ON p.promo_key = ps.promo_key
ORDER BY p.promo_name;

SPOOL OFF

-- ============================================================================
-- CHART 2
-- D3.2 - PROMO DAILY SALES VS MATCHED NON-PROMO BASELINE
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d3_promo_vs_baseline.csv

PROMPT Promotion,Promo Sales per Day,Baseline Sales per Day,Uplift %

WITH
year_bounds AS (
    SELECT
        TO_DATE('&p_year' || '0101', 'YYYYMMDD') AS year_start,
        TO_DATE('&p_year' || '1231', 'YYYYMMDD') AS year_end
    FROM dual
),
promo_window AS (
    SELECT
        p.promo_key,
        p.promo_name,
        GREATEST(p.promo_start_date, y.year_start) AS active_start,
        LEAST(p.promo_end_date, y.year_end) AS active_end,
        CASE
            WHEN LEAST(p.promo_end_date, y.year_end)
                 >= GREATEST(p.promo_start_date, y.year_start)
            THEN LEAST(p.promo_end_date, y.year_end)
                 - GREATEST(p.promo_start_date, y.year_start) + 1
            ELSE 0
        END AS active_days,
        y.year_end - y.year_start + 1 AS year_days
    FROM promotion_dim p
    CROSS JOIN year_bounds y
    WHERE p.promo_key > 0
),
promo_sales AS (
    SELECT
        sf.promo_key,
        SUM(sf.net_sales_amt) AS promo_net_sales
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key
),
promo_items AS (
    SELECT
        sf.promo_key,
        sf.item_key
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key, sf.item_key
),
baseline_sales AS (
    SELECT
        pi.promo_key,
        SUM(sf.net_sales_amt) AS baseline_net_sales
    FROM promo_items pi
    JOIN promo_window pw
      ON pw.promo_key = pi.promo_key
    JOIN sales_fact sf
      ON sf.item_key = pi.item_key
     AND sf.promo_key = 0
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND (
            d.cal_date < pw.active_start
            OR d.cal_date > pw.active_end
          )
    GROUP BY pi.promo_key
),
comparison AS (
    SELECT
        pw.promo_name,
        ps.promo_net_sales / NULLIF(pw.active_days, 0)
            AS promo_sales_per_day,
        NVL(bs.baseline_net_sales, 0)
            / NULLIF(pw.year_days - pw.active_days, 0)
            AS baseline_sales_per_day
    FROM promo_window pw
    JOIN promo_sales ps
      ON ps.promo_key = pw.promo_key
    LEFT JOIN baseline_sales bs
      ON bs.promo_key = pw.promo_key
)
SELECT
    '"' || REPLACE(promo_name, '"', '""') || '",' ||
    TO_CHAR(promo_sales_per_day, 'FM999999990.00') || ',' ||
    TO_CHAR(baseline_sales_per_day, 'FM999999990.00') || ',' ||
    TO_CHAR(
        100 * (
            promo_sales_per_day - baseline_sales_per_day
        ) / NULLIF(baseline_sales_per_day, 0),
        'FM9990.00'
    )
FROM comparison
ORDER BY promo_name;

SPOOL OFF

PROMPT
PROMPT Export complete.
PROMPT Files created:
PROMPT C:\Users\tpq11\task3_csv\d3_campaign_financial.csv
PROMPT C:\Users\tpq11\task3_csv\d3_promo_vs_baseline.csv
PROMPT

UNDEFINE p_year
SET FEEDBACK ON
