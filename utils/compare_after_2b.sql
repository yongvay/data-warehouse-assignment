-- ============================================================================
--  utils/compare_after_2b.sql
--  Run AS DW *after*  EXEC run_task2b  to prove the incremental load worked.
--  Requires that verify_task2a.sql was run first (it saves the BEFORE_2B rows).
--
--      SQL> SET SERVEROUTPUT ON
--      SQL> @"utils\compare_after_2b.sql"
--
--  NOTE: no PROMPT line may end with a hyphen - in SQL*Plus a trailing "-"
--  is the line-continuation character and swallows the next line.
-- ============================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200
COLUMN table_name      FORMAT A24
COLUMN verdict         FORMAT A16
COLUMN tbl             FORMAT A16
COLUMN customer_id     FORMAT A12
COLUMN customer_status FORMAT A10
COLUMN order_no        FORMAT A10
COLUMN delivery_id     FORMAT A12
COLUMN dq_flag         FORMAT A7
COLUMN object_name     FORMAT A32
COLUMN object_type     FORMAT A12
COLUMN status          FORMAT A10

PROMPT
PROMPT ####################################################################
PROMPT #  1 - BEFORE vs AFTER ROW COUNTS                                  #
PROMPT ####################################################################
WITH after_counts AS (
    SELECT 'date_dim'             AS table_name, COUNT(*) AS n FROM date_dim
    UNION ALL SELECT 'customer_dim',         COUNT(*) FROM customer_dim
    UNION ALL SELECT 'item_dim',             COUNT(*) FROM item_dim
    UNION ALL SELECT 'branch_dim',           COUNT(*) FROM branch_dim
    UNION ALL SELECT 'address_dim',          COUNT(*) FROM address_dim
    UNION ALL SELECT 'promotion_dim',        COUNT(*) FROM promotion_dim
    UNION ALL SELECT 'return_reason_dim',    COUNT(*) FROM return_reason_dim
    UNION ALL SELECT 'delivery_company_dim', COUNT(*) FROM delivery_company_dim
    UNION ALL SELECT 'sales_fact',           COUNT(*) FROM sales_fact
    UNION ALL SELECT 'return_fact',          COUNT(*) FROM return_fact
    UNION ALL SELECT 'delivery_fact',        COUNT(*) FROM delivery_fact
    UNION ALL SELECT 'point_fact',           COUNT(*) FROM point_fact
)
SELECT b.table_name,
       b.row_count AS before_2b,
       a.n         AS after_2b,
       a.n - b.row_count AS delta,
       CASE WHEN a.n > b.row_count THEN 'ROWS ADDED'
            WHEN a.n = b.row_count THEN 'unchanged'
            ELSE '>> ROWS LOST <<' END AS verdict
FROM   etl_row_snapshot b
JOIN   after_counts a ON a.table_name = b.table_name
WHERE  b.snapshot_label = 'BEFORE_2B'
ORDER  BY b.table_name;

PROMPT
PROMPT ####################################################################
PROMPT #  2 - SCD TYPE 2 PROOF (customer C0187 was set Inactive)          #
PROMPT #  Expect TWO rows:                                                #
PROMPT #    version 1 - Active,   is_current = N, end date closed         #
PROMPT #    version 2 - Inactive, is_current = Y, end date 9999-12-31     #
PROMPT ####################################################################
SELECT customer_key, customer_id, customer_status, version_no,
       effective_start_date, effective_end_date, is_current_flag
FROM   customer_dim
WHERE  customer_id = 'C0187'
ORDER  BY version_no;

PROMPT
PROMPT ####################################################################
PROMPT #  3 - SCD2 INTEGRITY (every query below must return 0 rows)       #
PROMPT ####################################################################
PROMPT
PROMPT === 3a. Customers with more than one current row ===
SELECT customer_id, COUNT(*) AS current_rows
FROM   customer_dim WHERE is_current_flag = 'Y'
GROUP  BY customer_id HAVING COUNT(*) <> 1;

PROMPT
PROMPT === 3b. Overlapping effective date ranges ===
SELECT a.customer_id, a.version_no AS ver_a, b.version_no AS ver_b
FROM   customer_dim a
JOIN   customer_dim b
       ON  a.customer_id = b.customer_id
       AND a.customer_key < b.customer_key
       AND a.effective_start_date <= b.effective_end_date
       AND b.effective_start_date <= a.effective_end_date;

PROMPT
PROMPT === 3c. Closed rows still flagged current ===
SELECT customer_key, customer_id, is_current_flag, effective_end_date
FROM   customer_dim
WHERE  is_current_flag = 'N' AND effective_end_date = DATE '9999-12-31';

PROMPT
PROMPT === 3d. Version distribution (expect a few rows at version 2) ===
SELECT version_no, COUNT(*) AS rows_at_this_version
FROM   customer_dim GROUP BY version_no ORDER BY version_no;

PROMPT
PROMPT ####################################################################
PROMPT #  4 - DIRTY DATA HANDLING                                         #
PROMPT #  These are the IDs the CURRENT insert_dirty_data.sql plants.     #
PROMPT #  An earlier version of this script looked for ORD01154 and       #
PROMPT #  DLV00267, which are ordinary rows in the expanded source - so   #
PROMPT #  checking them proved nothing at all.                            #
PROMPT ####################################################################
PROMPT
PROMPT === 4a. ORD02001 and ORD02002, the two dirty-test orders ===
PROMPT The orders themselves are clean and should load normally.
SELECT order_no, quantity, unit_price, gross_sales_amt, net_sales_amt, dq_flag
FROM   sales_fact WHERE order_no IN ('ORD02001', 'ORD02002')
ORDER  BY order_no;

PROMPT
PROMPT === 4b. Test B: RET00135 lodged BEFORE its order was placed ===
PROMPT days_to_return must be >= 0. The GREATEST() scrub in
PROMPT load_return_fact_incr is what makes the row loadable at all;
PROMPT without it the load aborts on chk_return_fact_days.
PROMPT Zero rows means the incremental rejected it instead of scrubbing it.
SELECT return_id, order_no, return_date_key, order_date_key,
       days_to_return, quantity_returned, dq_flag
FROM   return_fact WHERE return_id IN ('RET00135', 'RET00136')
ORDER  BY return_id;

PROMPT
PROMPT === 4c. Test C: RET00136 claims 99 units back when 2 were sold ===
PROMPT This survives the whole pipeline unchanged - nothing is negative,
PROMPT the value is merely impossible. Name it in the report as a known
PROMPT limitation; it produces a return rate above 100% for that item.
SELECT rf.return_id, rf.quantity_returned, sf.quantity AS quantity_sold,
       ROUND(100 * rf.quantity_returned / NULLIF(sf.quantity,0), 1) AS pct_returned
FROM   return_fact rf
JOIN   sales_fact  sf ON sf.order_no = rf.order_no
                     AND sf.item_key = rf.item_key
WHERE  rf.return_id = 'RET00136';

PROMPT
PROMPT === 4d/4e. DLV00642 Pending with no date, DLV00643 delivered early ===
PROMPT DLV00642: expect delivery_date_key = -1, delivery_lead_days NULL.
PROMPT DLV00643: expect delivery_lead_days >= 0 after the GREATEST() scrub.
SELECT delivery_id, delivery_date_key, delivery_status,
       delivery_charge, delivery_lead_days, dq_flag
FROM   delivery_fact WHERE delivery_id IN ('DLV00642', 'DLV00643')
ORDER  BY delivery_id;

PROMPT
PROMPT === 4f. Test F: C9901 messy name, NULL email, NULL IC ===
PROMPT Expect the name cleaned to 'Lim Wei Jian' by the INITCAP and
PROMPT REGEXP_REPLACE scrub, and email and IC defaulted to 'Unknown'.
SELECT customer_id, customer_name, customer_ic, customer_email,
       customer_status, dq_flag
FROM   customer_dim WHERE customer_id = 'C9901';

PROMPT
PROMPT ####################################################################
PROMPT #  5 - MEASURE SANITY (all counts must be 0)                       #
PROMPT ####################################################################
SELECT (SELECT COUNT(*) FROM sales_fact
        WHERE quantity <= 0 OR unit_price < 0 OR net_sales_amt < 0) AS bad_sales,
       (SELECT COUNT(*) FROM sales_fact
        WHERE net_sales_amt > gross_sales_amt)                      AS net_over_gross
FROM   dual;

PROMPT
PROMPT ####################################################################
PROMPT #  6 - DQ FLAG DISTRIBUTION AFTER 2b                               #
PROMPT #  Now you should see some D or S rows from the dirty data.        #
PROMPT ####################################################################
SELECT 'sales_fact'    AS tbl, dq_flag, COUNT(*) AS n FROM sales_fact    GROUP BY dq_flag
UNION ALL SELECT 'return_fact',   dq_flag, COUNT(*) FROM return_fact   GROUP BY dq_flag
UNION ALL SELECT 'delivery_fact', dq_flag, COUNT(*) FROM delivery_fact GROUP BY dq_flag
UNION ALL SELECT 'point_fact',    dq_flag, COUNT(*) FROM point_fact    GROUP BY dq_flag
UNION ALL SELECT 'customer_dim',  dq_flag, COUNT(*) FROM customer_dim  GROUP BY dq_flag
ORDER  BY 1, 2;

PROMPT
PROMPT ####################################################################
PROMPT #  7 - ETL BATCH IDS: 2b rows should carry a NEW batch id          #
PROMPT ####################################################################
SELECT 'sales_fact' AS tbl, etl_batch_id, COUNT(*) AS n FROM sales_fact GROUP BY etl_batch_id
UNION ALL SELECT 'customer_dim',  etl_batch_id, COUNT(*) FROM customer_dim  GROUP BY etl_batch_id
UNION ALL SELECT 'delivery_fact', etl_batch_id, COUNT(*) FROM delivery_fact GROUP BY etl_batch_id
ORDER  BY 1, 2;

PROMPT
PROMPT ####################################################################
PROMPT #  8 - DID 2b BREAK ANY OBJECT? (must be 0 rows)                   #
PROMPT ####################################################################
SELECT object_type, object_name, status
FROM   user_objects WHERE status <> 'VALID';

PROMPT
PROMPT ####################################################################
PROMPT #  DONE                                                            #
PROMPT ####################################################################
