-- ============================================================================
--  Task 2/Task 2a/verify_task2a.sql
--  GATE CHECK: run this AS DW after  EXEC run_task2a_initial_load
--  Every gate must pass BEFORE you run Task 2b.
--
--      SQL> SET SERVEROUTPUT ON
--      SQL> @"Task 2\Task 2a\verify_task2a.sql"
--
--  Gate 10 saves a BASELINE row-count snapshot so that after Task 2b you can
--  prove the incremental load actually added/changed rows.
--
--  NOTE: no PROMPT line in this file may end with a hyphen - in SQL*Plus a
--  trailing "-" is the line-continuation character and swallows the next line.
-- ============================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200
SET FEEDBACK ON
COLUMN object_name  FORMAT A32
COLUMN object_type  FORMAT A12
COLUMN status       FORMAT A14
COLUMN tbl          FORMAT A24
COLUMN check_name   FORMAT A46
COLUMN result       FORMAT A26
COLUMN detail       FORMAT A40
COLUMN name         FORMAT A30
COLUMN type         FORMAT A10
COLUMN text         FORMAT A70
COLUMN dq_flag      FORMAT A7
COLUMN customer_id  FORMAT A12

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 1 - DID EVERY PROCEDURE / VIEW COMPILE?                    #
PROMPT #  Expected: MISSING/INVALID list is EMPTY (0 rows).               #
PROMPT ####################################################################
WITH expected (obj_name, obj_type) AS (
    SELECT 'VW_LOAD_ADDRESS_DIM',          'VIEW'      FROM dual UNION ALL
    SELECT 'LOAD_DATE_DIM',                'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_REASON_DIM',       'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_COMPANY_DIM',    'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_BRANCH_DIM',              'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ADDRESS_DIM',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_PROMOTION_DIM',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ITEM_DIM',                'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_CUSTOMER_DIM_INIT',       'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_SALES_FACT',              'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_FACT',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_FACT',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_POINT_FACT',              'PROCEDURE' FROM dual UNION ALL
    SELECT 'RUN_TASK2A_INITIAL_LOAD',      'PROCEDURE' FROM dual
)
SELECT e.obj_name AS object_name,
       e.obj_type AS object_type,
       NVL(o.status, '>> MISSING <<') AS status
FROM   expected e
LEFT   JOIN user_objects o
       ON  o.object_name = e.obj_name
       AND o.object_type = e.obj_type
WHERE  o.object_name IS NULL
   OR  o.status <> 'VALID';

PROMPT
PROMPT === 1b. Exact compilation errors, if any appeared above ===
SELECT name, type, line, text
FROM   user_errors
ORDER  BY name, sequence;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 2 - ARE THE 7 SEQUENCES THERE, AND HAVE THEY BEEN USED?    #
PROMPT #  last_number still = 1 means that dimension never loaded.        #
PROMPT ####################################################################
SELECT sequence_name, last_number
FROM   user_sequences
ORDER  BY sequence_name;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 3 - IS THERE DATA IN EVERY TABLE?                          #
PROMPT #  Expected: every row says LOADED. Any EMPTY = 2a did not finish. #
PROMPT ####################################################################
WITH counts AS (
    SELECT 'date_dim'             AS tbl, COUNT(*) AS n FROM date_dim
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
SELECT tbl, n AS row_count,
       CASE WHEN n = 0 THEN '>> EMPTY <<' ELSE 'LOADED' END AS result
FROM   counts
ORDER  BY CASE WHEN n = 0 THEN 0 ELSE 1 END, tbl;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 4 - DOES EVERY DIMENSION HAVE ITS -1 "UNKNOWN" ROW?        #
PROMPT #  Facts point orphan keys at -1; a missing one breaks the load.   #
PROMPT #  promotion_dim also seeds key 0 = "No Promotion" by design.      #
PROMPT ####################################################################
SELECT 'customer_dim'         AS tbl, COUNT(*) AS unknown_rows FROM customer_dim         WHERE customer_key         = -1
UNION ALL SELECT 'item_dim',             COUNT(*) FROM item_dim             WHERE item_key             = -1
UNION ALL SELECT 'branch_dim',           COUNT(*) FROM branch_dim           WHERE branch_key           = -1
UNION ALL SELECT 'address_dim',          COUNT(*) FROM address_dim          WHERE address_key          = -1
UNION ALL SELECT 'promotion_dim',        COUNT(*) FROM promotion_dim        WHERE promo_key            = -1
UNION ALL SELECT 'return_reason_dim',    COUNT(*) FROM return_reason_dim    WHERE reason_key           = -1
UNION ALL SELECT 'delivery_company_dim', COUNT(*) FROM delivery_company_dim WHERE delivery_company_key = -1
UNION ALL SELECT 'date_dim',             COUNT(*) FROM date_dim             WHERE date_key             = -1
UNION ALL SELECT 'promotion_dim (key 0)',COUNT(*) FROM promotion_dim        WHERE promo_key            =  0;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 5 - SOURCE vs WAREHOUSE RECONCILIATION                     #
PROMPT #  SOURCE_ROWS and DW_ROWS should match exactly (seed rows are     #
PROMPT #  excluded below). A gap on the FACT rows = rows your DQ logic    #
PROMPT #  rejected: fine, as long as you can explain it in the report.    #
PROMPT ####################################################################
WITH recon AS (
    SELECT 'address_dim  vs MemberAddress' AS check_name,
           (SELECT COUNT(*) FROM adm.MemberAddress) AS source_rows,
           (SELECT COUNT(*) FROM address_dim WHERE address_key <> -1) AS dw_rows FROM dual
    UNION ALL
    SELECT 'item_dim     vs Item',
           (SELECT COUNT(*) FROM adm.Item),
           (SELECT COUNT(*) FROM item_dim WHERE item_key <> -1) FROM dual
    UNION ALL
    SELECT 'branch_dim   vs Branch',
           (SELECT COUNT(*) FROM adm.Branch),
           (SELECT COUNT(*) FROM branch_dim WHERE branch_key <> -1) FROM dual
    UNION ALL
    SELECT 'promotion_dim vs Promotion',
           (SELECT COUNT(*) FROM adm.Promotion),
           (SELECT COUNT(*) FROM promotion_dim WHERE promo_key NOT IN (-1, 0)) FROM dual
    UNION ALL
    SELECT 'return_reason_dim vs ReturnReason',
           (SELECT COUNT(*) FROM adm.ReturnReason),
           (SELECT COUNT(*) FROM return_reason_dim WHERE reason_key <> -1) FROM dual
    UNION ALL
    SELECT 'delivery_company_dim vs DeliveryCompany',
           (SELECT COUNT(*) FROM adm.DeliveryCompany),
           (SELECT COUNT(*) FROM delivery_company_dim WHERE delivery_company_key <> -1) FROM dual
    UNION ALL
    SELECT 'customer_dim vs Customer (current only)',
           (SELECT COUNT(*) FROM adm.Customer),
           (SELECT COUNT(*) FROM customer_dim WHERE customer_key <> -1 AND is_current_flag = 'Y') FROM dual
    UNION ALL
    SELECT 'sales_fact   vs OrderDetails',
           (SELECT COUNT(*) FROM adm.OrderDetails),
           (SELECT COUNT(*) FROM sales_fact) FROM dual
    UNION ALL
    SELECT 'return_fact  vs ReturnDetails',
           (SELECT COUNT(*) FROM adm.ReturnDetails),
           (SELECT COUNT(*) FROM return_fact) FROM dual
    UNION ALL
    SELECT 'delivery_fact vs Delivery',
           (SELECT COUNT(*) FROM adm.Delivery),
           (SELECT COUNT(*) FROM delivery_fact) FROM dual
    UNION ALL
    SELECT 'point_fact   vs PointTransaction',
           (SELECT COUNT(*) FROM adm.PointTransaction),
           (SELECT COUNT(*) FROM point_fact) FROM dual
)
SELECT check_name, source_rows, dw_rows,
       dw_rows - source_rows AS diff,
       CASE WHEN dw_rows = source_rows THEN 'MATCH'
            WHEN dw_rows <  source_rows THEN 'rows rejected - explain'
            ELSE '>> MORE THAN SOURCE <<' END AS result
FROM   recon
ORDER  BY CASE WHEN dw_rows = source_rows THEN 1 ELSE 0 END, check_name;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 6 - SCD TYPE 2 STARTING STATE (customer_dim)               #
PROMPT #  Before 2b: every customer must have EXACTLY ONE current row,    #
PROMPT #  version_no = 1, end date 9999-12-31.                            #
PROMPT ####################################################################
PROMPT
PROMPT === 6a. Customers whose current-row count is not 1 (want 0 rows) ===
SELECT customer_id, COUNT(*) AS current_rows
FROM   customer_dim
WHERE  is_current_flag = 'Y'
GROUP  BY customer_id
HAVING COUNT(*) <> 1;

PROMPT
PROMPT === 6b. Current rows that are not open-ended (want 0 rows) ===
SELECT customer_key, customer_id, effective_end_date
FROM   customer_dim
WHERE  is_current_flag = 'Y'
AND    effective_end_date <> DATE '9999-12-31';

PROMPT
PROMPT === 6c. Closed rows wrongly still flagged current (want 0 rows) ===
SELECT customer_key, customer_id, is_current_flag, effective_end_date
FROM   customer_dim
WHERE  is_current_flag = 'N'
AND    effective_end_date = DATE '9999-12-31';

PROMPT
PROMPT === 6d. Version distribution (before 2b: all should be version 1) ===
SELECT version_no, COUNT(*) AS rows_at_this_version
FROM   customer_dim
GROUP  BY version_no
ORDER  BY version_no;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 7 - DOES date_dim COVER THE WINDOW 2b WILL USE?            #
PROMPT #  run_task2b loads facts from SYSDATE-7, so the calendar must     #
PROMPT #  reach at least today. The -1 Unknown row (1900-01-01) is        #
PROMPT #  excluded so the real calendar range is what you see.            #
PROMPT ####################################################################
WITH cal AS (
    SELECT MIN(cal_date) AS min_cal_date,
           MAX(cal_date) AS max_cal_date,
           COUNT(*)      AS calendar_days
    FROM   date_dim
    WHERE  date_key <> -1
), src AS (
    SELECT MIN(OrderDateTime) AS first_order,
           MAX(OrderDateTime) AS last_order
    FROM   adm.Orders
)
SELECT c.min_cal_date, c.max_cal_date, c.calendar_days,
       c.max_cal_date - c.min_cal_date + 1 AS days_in_span,
       TRUNC(s.first_order) AS first_order,
       TRUNC(s.last_order)  AS last_order,
       CASE WHEN c.calendar_days <> c.max_cal_date - c.min_cal_date + 1
                 THEN '>> CALENDAR HAS GAPS <<'
            WHEN c.max_cal_date < TRUNC(SYSDATE)
                 THEN '>> TOO SHORT FOR 2b <<'
            WHEN c.min_cal_date > TRUNC(s.first_order)
                 THEN '>> STARTS AFTER 1ST ORDER <<'
            WHEN c.max_cal_date < TRUNC(s.last_order)
                 THEN '>> ENDS BEFORE LAST ORDER <<'
            ELSE 'OK' END AS result
FROM   cal c CROSS JOIN src s;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 8 - UNKNOWN (-1) KEY USAGE IN FACTS                        #
PROMPT #  A few are normal. A large share means a dim lookup failed.      #
PROMPT #  sales/return promo_key = 0 is "No Promotion" and is expected.   #
PROMPT ####################################################################
PROMPT
PROMPT === 8a. sales_fact ===
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN customer_key   = -1 THEN 1 ELSE 0 END) AS unk_customer,
       SUM(CASE WHEN item_key       = -1 THEN 1 ELSE 0 END) AS unk_item,
       SUM(CASE WHEN branch_key     = -1 THEN 1 ELSE 0 END) AS unk_branch,
       SUM(CASE WHEN promo_key      = -1 THEN 1 ELSE 0 END) AS unk_promo,
       SUM(CASE WHEN promo_key      =  0 THEN 1 ELSE 0 END) AS no_promo,
       SUM(CASE WHEN order_date_key = -1 THEN 1 ELSE 0 END) AS unk_date
FROM   sales_fact;

PROMPT
PROMPT === 8b. return_fact ===
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN customer_key    = -1 THEN 1 ELSE 0 END) AS unk_customer,
       SUM(CASE WHEN item_key        = -1 THEN 1 ELSE 0 END) AS unk_item,
       SUM(CASE WHEN branch_key      = -1 THEN 1 ELSE 0 END) AS unk_branch,
       SUM(CASE WHEN reason_key      = -1 THEN 1 ELSE 0 END) AS unk_reason,
       SUM(CASE WHEN promo_key       = -1 THEN 1 ELSE 0 END) AS unk_promo,
       SUM(CASE WHEN return_date_key = -1 THEN 1 ELSE 0 END) AS unk_date
FROM   return_fact;

PROMPT
PROMPT === 8c. delivery_fact ===
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN customer_key         = -1 THEN 1 ELSE 0 END) AS unk_customer,
       SUM(CASE WHEN branch_key           = -1 THEN 1 ELSE 0 END) AS unk_branch,
       SUM(CASE WHEN delivery_company_key = -1 THEN 1 ELSE 0 END) AS unk_company,
       SUM(CASE WHEN address_key          = -1 THEN 1 ELSE 0 END) AS unk_address,
       SUM(CASE WHEN delivery_date_key    = -1 THEN 1 ELSE 0 END) AS unk_date
FROM   delivery_fact;

PROMPT
PROMPT === 8d. point_fact ===
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN customer_key   = -1 THEN 1 ELSE 0 END) AS unk_customer,
       SUM(CASE WHEN branch_key     = -1 THEN 1 ELSE 0 END) AS unk_branch,
       SUM(CASE WHEN trans_date_key = -1 THEN 1 ELSE 0 END) AS unk_date
FROM   point_fact;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 8e - DO THE UNKNOWN KEYS RECONCILE TO THE SOURCE?          #
PROMPT #  Every -1 above must be explained by a NULL in the source.       #
PROMPT #  DW_UNKNOWNS and SOURCE_NULLS must be equal.                     #
PROMPT ####################################################################
SELECT 'delivery_fact.delivery_date_key = -1' AS check_name,
       (SELECT COUNT(*) FROM delivery_fact WHERE delivery_date_key = -1) AS dw_unknowns,
       (SELECT COUNT(*) FROM adm.Delivery  WHERE DeliveryDate IS NULL)   AS source_nulls,
       'Deliveries not yet delivered'                                    AS reason
FROM dual
UNION ALL
SELECT 'point_fact.branch_key = -1',
       (SELECT COUNT(*) FROM point_fact WHERE branch_key = -1),
       (SELECT COUNT(*) FROM adm.PointTransaction pt
        WHERE  pt.OrderNo IS NULL
        OR NOT EXISTS (SELECT 1 FROM adm.Orders o WHERE o.OrderNo = pt.OrderNo)),
       'Point transactions not tied to an order'
FROM dual;

PROMPT
PROMPT === 8f. What kind of point transactions have no branch? ===
COLUMN trans_type FORMAT A12
SELECT trans_type, COUNT(*) AS n
FROM   point_fact WHERE branch_key = -1
GROUP  BY trans_type ORDER BY trans_type;

PROMPT
PROMPT === 8g. What status are the deliveries with an unknown date? ===
COLUMN delivery_status FORMAT A16
SELECT delivery_status, COUNT(*) AS n
FROM   delivery_fact WHERE delivery_date_key = -1
GROUP  BY delivery_status ORDER BY delivery_status;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 9 - DATA QUALITY FLAGS                                     #
PROMPT #  V = valid, S = suspect, D = dirty. Before 2b these should be    #
PROMPT #  all V; the dirty rows arrive with insert_dirty_data.sql.        #
PROMPT ####################################################################
SELECT 'sales_fact'    AS tbl, dq_flag, COUNT(*) AS n FROM sales_fact    GROUP BY dq_flag
UNION ALL SELECT 'return_fact',   dq_flag, COUNT(*) FROM return_fact   GROUP BY dq_flag
UNION ALL SELECT 'delivery_fact', dq_flag, COUNT(*) FROM delivery_fact GROUP BY dq_flag
UNION ALL SELECT 'point_fact',    dq_flag, COUNT(*) FROM point_fact    GROUP BY dq_flag
UNION ALL SELECT 'customer_dim',  dq_flag, COUNT(*) FROM customer_dim  GROUP BY dq_flag
ORDER  BY 1, 2;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 9b - MEASURE SANITY (all counts must be 0)                 #
PROMPT ####################################################################
SELECT (SELECT COUNT(*) FROM sales_fact
        WHERE quantity <= 0 OR unit_price < 0 OR net_sales_amt < 0) AS bad_sales,
       (SELECT COUNT(*) FROM sales_fact
        WHERE net_sales_amt > gross_sales_amt)                      AS net_over_gross
FROM   dual;

PROMPT
PROMPT ####################################################################
PROMPT #  GATE 10 - SAVE THE BASELINE SNAPSHOT (for the 2b comparison)    #
PROMPT ####################################################################
BEGIN
    EXECUTE IMMEDIATE '
        CREATE TABLE etl_row_snapshot (
            snapshot_label  VARCHAR2(30),
            taken_at        DATE DEFAULT SYSDATE,
            table_name      VARCHAR2(30),
            row_count       NUMBER
        )';
    DBMS_OUTPUT.PUT_LINE('etl_row_snapshot created.');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN                     -- ORA-00955: already exists
            DBMS_OUTPUT.PUT_LINE('etl_row_snapshot already exists - reusing.');
        ELSE RAISE; END IF;
END;
/

DELETE FROM etl_row_snapshot WHERE snapshot_label = 'BEFORE_2B';

INSERT INTO etl_row_snapshot (snapshot_label, table_name, row_count)
SELECT 'BEFORE_2B', 'date_dim',             COUNT(*) FROM date_dim
UNION ALL SELECT 'BEFORE_2B','customer_dim',         COUNT(*) FROM customer_dim
UNION ALL SELECT 'BEFORE_2B','item_dim',             COUNT(*) FROM item_dim
UNION ALL SELECT 'BEFORE_2B','branch_dim',           COUNT(*) FROM branch_dim
UNION ALL SELECT 'BEFORE_2B','address_dim',          COUNT(*) FROM address_dim
UNION ALL SELECT 'BEFORE_2B','promotion_dim',        COUNT(*) FROM promotion_dim
UNION ALL SELECT 'BEFORE_2B','return_reason_dim',    COUNT(*) FROM return_reason_dim
UNION ALL SELECT 'BEFORE_2B','delivery_company_dim', COUNT(*) FROM delivery_company_dim
UNION ALL SELECT 'BEFORE_2B','sales_fact',           COUNT(*) FROM sales_fact
UNION ALL SELECT 'BEFORE_2B','return_fact',          COUNT(*) FROM return_fact
UNION ALL SELECT 'BEFORE_2B','delivery_fact',        COUNT(*) FROM delivery_fact
UNION ALL SELECT 'BEFORE_2B','point_fact',           COUNT(*) FROM point_fact;

COMMIT;

SELECT table_name, row_count FROM etl_row_snapshot
WHERE  snapshot_label = 'BEFORE_2B' ORDER BY table_name;

PROMPT
PROMPT ####################################################################
PROMPT #  BASELINE SAVED. If gates 1-9 are clean, Task 2a is good and     #
PROMPT #  you may proceed to Task 2b.                                     #
PROMPT #  Afterwards run:  @utils\compare_after_2b.sql                    #
PROMPT ####################################################################
