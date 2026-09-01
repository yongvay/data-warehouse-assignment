-- ============================================================================
-- TASK 3 - STUDENT D (TEO PEI QI)
-- D1 CHART CSV EXPORT - 5W VERSION
-- Oracle SQL*Plus 11g compatible
--
-- Creates:
--   C:\Users\tpq11\task3_csv\d1_return_rate_by_category.csv
--   C:\Users\tpq11\task3_csv\d1_reason_mix.csv
--   C:\Users\tpq11\task3_csv\d1_refund_by_reason_category.csv
--   C:\Users\tpq11\task3_csv\d1_return_timing.csv
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

ACCEPT p_year CHAR DEFAULT '2025' PROMPT 'Enter original order cohort year [2025]: '

PROMPT
PROMPT Exporting D1 chart data for &p_year ...
PROMPT

SET TERMOUT OFF

-- ============================================================================
-- EXHIBIT D1.1 - WHERE: RETURN RATE BY ITEM CATEGORY
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d1_return_rate_by_category.csv

PROMPT Category,Qty Sold,Qty Returned,Return Rate %,Refund Amount

WITH
sales_by_category AS (
    SELECT
        i.category_id,
        i.category_name,
        SUM(sf.quantity) AS qty_sold
    FROM sales_fact sf
    JOIN item_dim i
      ON i.item_key = sf.item_key
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
    GROUP BY i.category_id, i.category_name
),
returns_by_category AS (
    SELECT
        i.category_id,
        i.category_name,
        SUM(rf.quantity_returned) AS qty_returned,
        SUM(rf.refund_amount) AS refund_amount
    FROM return_fact rf
    JOIN item_dim i
      ON i.item_key = rf.item_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
    GROUP BY i.category_id, i.category_name
)
SELECT
    '"' || REPLACE(r.category_name, '"', '""') || '",' ||
    TO_CHAR(s.qty_sold) || ',' ||
    TO_CHAR(r.qty_returned) || ',' ||
    TO_CHAR(
        ROUND(100 * r.qty_returned / NULLIF(s.qty_sold, 0), 2),
        'FM990.00'
    ) || ',' ||
    TO_CHAR(r.refund_amount, 'FM999999990.00')
FROM returns_by_category r
JOIN sales_by_category s
  ON s.category_id = r.category_id
ORDER BY
    100 * r.qty_returned / NULLIF(s.qty_sold, 0) DESC,
    r.qty_returned DESC;

SPOOL OFF

-- ============================================================================
-- EXHIBIT D1.2 - WHAT: RETURN REASON MIX PER ITEM CATEGORY
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d1_reason_mix.csv

PROMPT Category,Missing,Broken,Expired,Wrong Item

SELECT
    '"' || REPLACE(i.category_name, '"', '""') || '",' ||
    TO_CHAR(SUM(CASE WHEN rr.reason_name = 'Missing'
                     THEN rf.quantity_returned ELSE 0 END)) || ',' ||
    TO_CHAR(SUM(CASE WHEN rr.reason_name = 'Broken'
                     THEN rf.quantity_returned ELSE 0 END)) || ',' ||
    TO_CHAR(SUM(CASE WHEN rr.reason_name = 'Expired'
                     THEN rf.quantity_returned ELSE 0 END)) || ',' ||
    TO_CHAR(SUM(CASE WHEN rr.reason_name = 'Wrong Item'
                     THEN rf.quantity_returned ELSE 0 END))
FROM return_fact rf
JOIN return_reason_dim rr
  ON rr.reason_key = rf.reason_key
JOIN item_dim i
  ON i.item_key = rf.item_key
JOIN date_dim d
  ON d.date_key = rf.order_date_key
WHERE d.cal_year = TO_NUMBER('&p_year')
  AND i.category_id <> 'UNKN'
  AND rr.reason_name <> 'Unknown'
GROUP BY i.category_id, i.category_name
ORDER BY i.category_name;

SPOOL OFF

-- ============================================================================
-- EXHIBIT D1.3 - WHO: REFUND RESPONSIBILITY
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d1_refund_by_reason_category.csv

PROMPT Reason Category,Refund Amount,Refund Share %

WITH refund_reason AS (
    SELECT
        rr.reason_category,
        SUM(rf.refund_amount) AS refund_amount
    FROM return_fact rf
    JOIN return_reason_dim rr
      ON rr.reason_key = rf.reason_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND rr.reason_category <> 'Unknown'
    GROUP BY rr.reason_category
)
SELECT
    '"' || REPLACE(reason_category, '"', '""') || '",' ||
    TO_CHAR(refund_amount, 'FM999999990.00') || ',' ||
    TO_CHAR(
        ROUND(
            100 * refund_amount /
            NULLIF(SUM(refund_amount) OVER (), 0),
            2
        ),
        'FM990.00'
    )
FROM refund_reason
ORDER BY refund_amount DESC;

SPOOL OFF

-- ============================================================================
-- EXHIBIT D1.4 - WHY: DOMINANT RETURN REASON BY ITEM CATEGORY
-- Supporting table only.
-- No separate CSV/chart export is required because the category-level reason
-- pattern is already visualised in Exhibit D1.2.
-- ============================================================================

-- ============================================================================
-- EXHIBIT D1.5 - WHEN: RETURN TIMING
-- ============================================================================

SPOOL C:\Users\tpq11\task3_csv\d1_return_timing.csv

PROMPT Return Window,Return Lines,Qty Returned,Qty Share %,Refund Amount,Avg Days to Return

WITH timing_base AS (
    SELECT
        CASE
            WHEN rf.days_to_return BETWEEN 0 AND 3 THEN '0-3 days'
            WHEN rf.days_to_return BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN rf.days_to_return BETWEEN 8 AND 14 THEN '8-14 days'
            ELSE '15+ days'
        END AS return_window,
        CASE
            WHEN rf.days_to_return BETWEEN 0 AND 3 THEN 1
            WHEN rf.days_to_return BETWEEN 4 AND 7 THEN 2
            WHEN rf.days_to_return BETWEEN 8 AND 14 THEN 3
            ELSE 4
        END AS window_order,
        rf.quantity_returned,
        rf.refund_amount,
        rf.days_to_return
    FROM return_fact rf
    JOIN item_dim i
      ON i.item_key = rf.item_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
),
timing_summary AS (
    SELECT
        return_window,
        window_order,
        COUNT(*) AS return_lines,
        SUM(quantity_returned) AS qty_returned,
        SUM(refund_amount) AS refund_amount,
        AVG(days_to_return) AS avg_days_to_return
    FROM timing_base
    GROUP BY return_window, window_order
)
SELECT
    '"' || return_window || '",' ||
    TO_CHAR(return_lines) || ',' ||
    TO_CHAR(qty_returned) || ',' ||
    TO_CHAR(
        ROUND(
            100 * qty_returned /
            NULLIF(SUM(qty_returned) OVER (), 0),
            2
        ),
        'FM990.00'
    ) || ',' ||
    TO_CHAR(refund_amount, 'FM999999990.00') || ',' ||
    TO_CHAR(ROUND(avg_days_to_return, 2), 'FM990.00')
FROM timing_summary
ORDER BY window_order;

SPOOL OFF

SET TERMOUT ON
SET HEADING ON
SET FEEDBACK ON

PROMPT
PROMPT Export complete.
PROMPT Files created:
PROMPT   C:\Users\tpq11\task3_csv\d1_return_rate_by_category.csv
PROMPT   C:\Users\tpq11\task3_csv\d1_reason_mix.csv
PROMPT   C:\Users\tpq11\task3_csv\d1_refund_by_reason_category.csv
PROMPT   C:\Users\tpq11\task3_csv\d1_return_timing.csv
PROMPT

UNDEFINE p_year
