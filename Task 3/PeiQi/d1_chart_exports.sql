-- ============================================================================
-- TASK 3 - STUDENT D (PEI QI)
-- D1 CHART CSV EXPORT - ORACLE SQL*PLUS 11g COMPATIBLE
--
-- Creates:
--   C:\data-warehouse-assignment\Task 3\PeiQi\task3_csv\d1_reason_mix.csv
--   C:\data-warehouse-assignment\Task 3\PeiQi\task3_csv\d1_refund_by_reason_category.csv
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

-- ============================================================================
-- CSV 1: RETURN REASON MIX PER ITEM CATEGORY
-- ============================================================================

SET TERMOUT OFF

SPOOL "C:\data-warehouse-assignment\Task 3\PeiQi\task3_csv\d1_reason_mix.csv"

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
GROUP BY
    i.category_id,
    i.category_name
ORDER BY i.category_name;

SPOOL OFF

-- ============================================================================
-- CSV 2: REFUND VALUE BY REASON CATEGORY
-- ============================================================================

SPOOL "C:\data-warehouse-assignment\Task 3\PeiQi\task3_csv\d1_refund_by_reason_category.csv"

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

SET TERMOUT ON
SET HEADING ON
SET FEEDBACK ON

PROMPT
PROMPT Export complete.
PROMPT Files created:
PROMPT   D:\data-warehouse-assignment\Task 3\PeiQi\task3_csv\d1_reason_mix.csv
PROMPT   D:\data-warehouse-assignment\Task 3\PeiQi\task3_csv\d1_refund_by_reason_category.csv
PROMPT

UNDEFINE p_year
