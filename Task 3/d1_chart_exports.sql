-- ============================================================================
-- D1 CHART CSV EXPORT
-- Run with the same p_year used for d1_return_reason_analysis.sql
--
-- Creates:
--   d1_reason_mix.csv
--   d1_refund_by_reason_category.csv
--
-- Before running, create a folder called:
--   task3_csv
-- in your current SQL*Plus working directory.
-- ============================================================================

SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 0
SET LINESIZE 32767
SET TRIMSPOOL ON
SET MARKUP CSV ON DELIMITER , QUOTE ON

ACCEPT p_year NUMBER DEFAULT 2025 PROMPT 'Enter original order cohort year [2025]: '

SPOOL task3_csv/d1_reason_mix.csv

SELECT
    i.category_name AS "Category",
    SUM(CASE WHEN rr.reason_name = 'Missing'
             THEN rf.quantity_returned ELSE 0 END) AS "Missing",
    SUM(CASE WHEN rr.reason_name = 'Broken'
             THEN rf.quantity_returned ELSE 0 END) AS "Broken",
    SUM(CASE WHEN rr.reason_name = 'Expired'
             THEN rf.quantity_returned ELSE 0 END) AS "Expired",
    SUM(CASE WHEN rr.reason_name = 'Wrong Item'
             THEN rf.quantity_returned ELSE 0 END) AS "Wrong Item"
FROM return_fact rf
JOIN return_reason_dim rr
  ON rr.reason_key = rf.reason_key
JOIN item_dim i
  ON i.item_key = rf.item_key
JOIN date_dim d
  ON d.date_key = rf.order_date_key
WHERE d.cal_year = &p_year
  AND i.category_id <> 'UNKN'
  AND rr.reason_name <> 'Unknown'
GROUP BY
    i.category_id,
    i.category_name
ORDER BY i.category_name;

SPOOL OFF

SPOOL task3_csv/d1_refund_by_reason_category.csv

WITH refund_reason AS (
    SELECT
        rr.reason_category,
        SUM(rf.refund_amount) AS refund_amount
    FROM return_fact rf
    JOIN return_reason_dim rr
      ON rr.reason_key = rf.reason_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = &p_year
      AND rr.reason_category <> 'Unknown'
    GROUP BY rr.reason_category
)
SELECT
    reason_category AS "Reason Category",
    ROUND(refund_amount, 2) AS "Refund Amount",
    ROUND(
        100 * refund_amount /
        NULLIF(SUM(refund_amount) OVER (), 0),
        2
    ) AS "Refund Share %"
FROM refund_reason
ORDER BY refund_amount DESC;

SPOOL OFF

SET MARKUP CSV OFF
SET HEADING ON
SET FEEDBACK ON

UNDEFINE p_year
