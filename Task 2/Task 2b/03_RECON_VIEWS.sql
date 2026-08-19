-- ============================================================================
--  TASK 2(b) : VERIFICATION / RECONCILIATION VIEWS
-- ----------------------------------------------------------------------------
--  These are the views to SELECT from after a run - and the ones to screenshot
--  for the report.  An incremental load is only trustworthy if it can be
--  proved, so each view answers one question a marker (or an auditor) will ask:
--      1. What did this run do?                    vw_etl_batch_summary
--      2. Which table did what?                    vw_etl_step_summary
--      3. What dirty data was found, and why?      vw_etl_reject_summary
--      4. How clean is the warehouse right now?    vw_dw_dq_dashboard
--      5. Does the warehouse still tie to source?  vw_dw_reconciliation
--      6. Is the Type 2 history correct?           vw_scd2_customer_history
--                                                  vw_scd2_integrity_check
-- ============================================================================

SET DEFINE OFF

-- ----------------------------------------------------------------------------
--  1. One line per ETL run
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_etl_batch_summary AS
SELECT
    b.batch_id,
    b.batch_type,
    TO_CHAR(b.batch_start_dt, 'YYYY-MM-DD HH24:MI:SS') AS started,
    TO_CHAR(b.batch_end_dt,   'YYYY-MM-DD HH24:MI:SS') AS ended,
    ROUND((b.batch_end_dt - b.batch_start_dt) * 86400, 1) AS elapsed_secs,
    b.batch_status,
    b.rows_inserted,
    b.rows_updated,
    b.rows_scrubbed,
    b.rows_rejected,
    CASE WHEN NVL(b.rows_inserted,0) + NVL(b.rows_updated,0) = 0 THEN 0
         ELSE ROUND(100 * b.rows_rejected /
                    (b.rows_inserted + b.rows_updated + b.rows_rejected), 2)
    END                                                AS reject_pct,
    b.hwm_order_dt,
    b.hwm_return_dt,
    b.hwm_delivery_dt,
    b.hwm_point_dt,
    b.error_msg
FROM etl_batch_control b
ORDER BY b.batch_id DESC;


-- ----------------------------------------------------------------------------
--  2. One line per target table per run
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_etl_step_summary AS
SELECT
    s.batch_id,
    s.step_seq,
    s.target_object,
    TO_CHAR(s.step_dt, 'YYYY-MM-DD HH24:MI:SS') AS step_time,
    s.rows_inserted,
    s.rows_updated,
    s.rows_scrubbed,
    s.rows_rejected,
    s.step_status
FROM etl_step_log s
ORDER BY s.batch_id DESC, s.step_seq;


-- ----------------------------------------------------------------------------
--  3. Data-quality findings, grouped by the rule that fired
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_etl_reject_summary AS
SELECT
    r.batch_id,
    r.target_object,
    r.rule_code,
    r.action_taken,
    COUNT(*)                                   AS occurrences,
    MIN(r.source_key)                          AS example_key,
    MAX(SUBSTR(r.rule_desc, 1, 120))           AS rule_description
FROM etl_reject_log r
GROUP BY r.batch_id, r.target_object, r.rule_code, r.action_taken
ORDER BY r.batch_id DESC, occurrences DESC;


-- ----------------------------------------------------------------------------
--  4. Current cleanliness of every table in the warehouse
--     V = clean, S = loaded after scrubbing, D = should never appear here
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_dw_dq_dashboard AS
SELECT CAST('CUSTOMER_DIM' AS VARCHAR2(24)) AS table_name, dq_flag,
       COUNT(*) AS row_count FROM customer_dim   GROUP BY dq_flag
UNION ALL
SELECT 'ITEM_DIM',            dq_flag, COUNT(*) FROM item_dim             GROUP BY dq_flag
UNION ALL
SELECT 'BRANCH_DIM',          dq_flag, COUNT(*) FROM branch_dim           GROUP BY dq_flag
UNION ALL
SELECT 'ADDRESS_DIM',         dq_flag, COUNT(*) FROM address_dim          GROUP BY dq_flag
UNION ALL
SELECT 'PROMOTION_DIM',       dq_flag, COUNT(*) FROM promotion_dim        GROUP BY dq_flag
UNION ALL
SELECT 'RETURN_REASON_DIM',   dq_flag, COUNT(*) FROM return_reason_dim    GROUP BY dq_flag
UNION ALL
SELECT 'DELIVERY_COMPANY_DIM',dq_flag, COUNT(*) FROM delivery_company_dim GROUP BY dq_flag
UNION ALL
SELECT 'DATE_DIM',            dq_flag, COUNT(*) FROM date_dim             GROUP BY dq_flag
UNION ALL
SELECT 'SALES_FACT',          dq_flag, COUNT(*) FROM sales_fact           GROUP BY dq_flag
UNION ALL
SELECT 'RETURN_FACT',         dq_flag, COUNT(*) FROM return_fact          GROUP BY dq_flag
UNION ALL
SELECT 'DELIVERY_FACT',       dq_flag, COUNT(*) FROM delivery_fact        GROUP BY dq_flag
UNION ALL
SELECT 'POINT_FACT',          dq_flag, COUNT(*) FROM point_fact           GROUP BY dq_flag;


-- ----------------------------------------------------------------------------
--  5. Source-to-warehouse row reconciliation
--     variance should equal the number of rows the scrubbing rejected.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_dw_reconciliation AS
SELECT CAST('SALES_FACT' AS VARCHAR2(34)) AS target_object,
       (SELECT COUNT(*) FROM vw_stg_sales)                        AS staged_rows,
       (SELECT COUNT(*) FROM vw_stg_sales WHERE dq_flag = 'D')    AS rejected_rows,
       (SELECT COUNT(*) FROM sales_fact)                          AS warehouse_rows,
       (SELECT COUNT(*) FROM vw_stg_sales WHERE dq_flag <> 'D')
       - (SELECT COUNT(*) FROM sales_fact)                        AS variance
  FROM dual
UNION ALL
SELECT 'RETURN_FACT',
       (SELECT COUNT(*) FROM vw_stg_return),
       (SELECT COUNT(*) FROM vw_stg_return WHERE dq_flag = 'D'),
       (SELECT COUNT(*) FROM return_fact),
       (SELECT COUNT(*) FROM vw_stg_return WHERE dq_flag <> 'D')
       - (SELECT COUNT(*) FROM return_fact)
  FROM dual
UNION ALL
SELECT 'DELIVERY_FACT',
       (SELECT COUNT(*) FROM vw_stg_delivery),
       (SELECT COUNT(*) FROM vw_stg_delivery WHERE dq_flag = 'D'),
       (SELECT COUNT(*) FROM delivery_fact),
       (SELECT COUNT(*) FROM vw_stg_delivery WHERE dq_flag <> 'D')
       - (SELECT COUNT(*) FROM delivery_fact)
  FROM dual
UNION ALL
SELECT 'POINT_FACT',
       (SELECT COUNT(*) FROM vw_stg_point),
       (SELECT COUNT(*) FROM vw_stg_point WHERE dq_flag = 'D'),
       (SELECT COUNT(*) FROM point_fact),
       (SELECT COUNT(*) FROM vw_stg_point WHERE dq_flag <> 'D')
       - (SELECT COUNT(*) FROM point_fact)
  FROM dual
UNION ALL
SELECT 'CUSTOMER_DIM (current versions)',
       (SELECT COUNT(*) FROM vw_stg_customer),
       (SELECT COUNT(*) FROM vw_stg_customer WHERE dq_flag = 'D'),
       (SELECT COUNT(*) FROM customer_dim WHERE is_current_flag = 'Y'
                                            AND customer_key <> -1),
       (SELECT COUNT(*) FROM vw_stg_customer WHERE dq_flag <> 'D')
       - (SELECT COUNT(*) FROM customer_dim WHERE is_current_flag = 'Y'
                                              AND customer_key <> -1)
  FROM dual;


-- ----------------------------------------------------------------------------
--  6a. Type 2 history, readable version - use this for the report screenshot
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_scd2_customer_history AS
SELECT
    c.customer_id,
    c.customer_key,
    c.version_no,
    c.customer_name,
    c.customer_status,
    c.member_flag,
    c.membership_type,
    TO_CHAR(c.effective_start_date, 'YYYY-MM-DD HH24:MI:SS') AS valid_from,
    CASE WHEN c.effective_end_date = DATE '9999-12-31' THEN '(open)'
         ELSE TO_CHAR(c.effective_end_date, 'YYYY-MM-DD HH24:MI:SS') END AS valid_to,
    c.is_current_flag,
    c.etl_batch_id
FROM customer_dim c
WHERE c.customer_key <> -1
  AND c.customer_id IN (SELECT customer_id FROM customer_dim
                         GROUP BY customer_id HAVING COUNT(*) > 1)
ORDER BY c.customer_id, c.version_no;


-- ----------------------------------------------------------------------------
--  6b. Type 2 integrity checks - every row returned here is a DEFECT.
--      An empty result set is the proof the SCD2 logic is correct.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_scd2_integrity_check AS
-- a customer must have exactly one open version
SELECT CAST('MULTIPLE_CURRENT_VERSIONS' AS VARCHAR2(30)) AS defect, customer_id,
       CAST(TO_CHAR(COUNT(*)) AS VARCHAR2(60)) AS detail
  FROM customer_dim
 WHERE is_current_flag = 'Y'
 GROUP BY customer_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'NO_CURRENT_VERSION', customer_id, '0'
  FROM customer_dim
 WHERE customer_key <> -1
 GROUP BY customer_id
HAVING SUM(CASE WHEN is_current_flag = 'Y' THEN 1 ELSE 0 END) = 0
UNION ALL
-- version numbers must be a gapless 1..n sequence
SELECT 'VERSION_SEQUENCE_GAP', customer_id,
       'max=' || MAX(version_no) || ' count=' || COUNT(*)
  FROM customer_dim
 WHERE customer_key <> -1
 GROUP BY customer_id
HAVING MAX(version_no) <> COUNT(*)
UNION ALL
-- validity intervals of one customer must not overlap
SELECT 'OVERLAPPING_VALIDITY', a.customer_id,
       'v' || a.version_no || ' overlaps v' || b.version_no
  FROM customer_dim a
  JOIN customer_dim b
    ON  a.customer_id = b.customer_id
    AND a.customer_key < b.customer_key
    AND a.effective_start_date <  b.effective_end_date
    AND b.effective_start_date <  a.effective_end_date
 WHERE a.customer_key <> -1;

-- ============================================================================
--  END OF FILE 03
-- ============================================================================
