-- ============================================================================
--  utils/final_acceptance.sql   -   RUN AS THE DW USER
--
--      SQL> @"C:\Users\PC\Desktop\DW\utils\final_acceptance.sql"
--
--  One run, one verdict table.  Checks every deliverable from Task 1(a)
--  through Task 2(b) plus the 2016-2026 data span, then prints the supporting
--  detail underneath so you can screenshot both for the report.
--
--  EVERY ROW IN THE VERDICT TABLE MUST READ PASS.
--
--  SQL*Plus rules this file obeys, all learned the hard way in this project:
--    - SQLBLANKLINES ON, and no blank line inside any single SQL statement
--    - no line ends in a hyphen (that is the continuation character)
--    - no reserved word used as a column alias (ONLINE, LEVEL, SIZE, ...)
--    - no local PL/SQL function called from inside a SQL statement
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 160
SET PAGESIZE 300
SET FEEDBACK OFF
COLUMN area       FORMAT A9
COLUMN check_name FORMAT A56
COLUMN expected   FORMAT 99999999
COLUMN actual     FORMAT 99999999
COLUMN verdict    FORMAT A10

PROMPT
PROMPT ####################################################################
PROMPT #  FINAL ACCEPTANCE - TASK 1 THROUGH TASK 2                        #
PROMPT #  Every row must read PASS before starting Task 3.                #
PROMPT ####################################################################
WITH etl_objects (obj_name, obj_type) AS (
    SELECT 'VW_LOAD_ADDRESS_DIM',            'VIEW'      FROM dual UNION ALL
    SELECT 'VW_LOAD_CUSTOMER_DIM',           'VIEW'      FROM dual UNION ALL
    SELECT 'VW_LOAD_SALES_FACT',             'VIEW'      FROM dual UNION ALL
    SELECT 'ORDER_DATE_DIM',                 'VIEW'      FROM dual UNION ALL
    SELECT 'RETURN_DATE_DIM',                'VIEW'      FROM dual UNION ALL
    SELECT 'DELIVERY_DATE_DIM',              'VIEW'      FROM dual UNION ALL
    SELECT 'TRANS_DATE_DIM',                 'VIEW'      FROM dual UNION ALL
    SELECT 'LOAD_DATE_DIM',                  'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_REASON_DIM',         'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_COMPANY_DIM',      'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_BRANCH_DIM',                'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ADDRESS_DIM',               'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_PROMOTION_DIM',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ITEM_DIM',                  'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_CUSTOMER_DIM_INIT',         'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_SALES_FACT',                'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_FACT',               'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_FACT',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_POINT_FACT',                'PROCEDURE' FROM dual UNION ALL
    SELECT 'RUN_TASK2A_INITIAL_LOAD',        'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DATE_DIM_INCR',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ADDRESS_DIM_INCR',          'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_BRANCH_DIM_INCR',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_COMPANY_DIM_INCR', 'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ITEM_DIM_INCR',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_PROMOTION_DIM_INCR',        'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_REASON_DIM_INCR',    'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_CUSTOMER_DIM_NEW_RECORDS',  'PROCEDURE' FROM dual UNION ALL
    SELECT 'MAINTAIN_CUSTOMER_DIM_TYPE1',    'PROCEDURE' FROM dual UNION ALL
    SELECT 'MAINTAIN_CUSTOMER_DIM_SCD2',     'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_SALES_FACT_INCR',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_FACT_INCR',          'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_FACT_INCR',        'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_POINT_FACT_INCR',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'RUN_TASK2B',                     'PROCEDURE' FROM dual
), dw_tables (tab_name) AS (
    SELECT 'DATE_DIM'             FROM dual UNION ALL
    SELECT 'CUSTOMER_DIM'         FROM dual UNION ALL
    SELECT 'ITEM_DIM'             FROM dual UNION ALL
    SELECT 'BRANCH_DIM'           FROM dual UNION ALL
    SELECT 'ADDRESS_DIM'          FROM dual UNION ALL
    SELECT 'PROMOTION_DIM'        FROM dual UNION ALL
    SELECT 'RETURN_REASON_DIM'    FROM dual UNION ALL
    SELECT 'DELIVERY_COMPANY_DIM' FROM dual UNION ALL
    SELECT 'SALES_FACT'           FROM dual UNION ALL
    SELECT 'RETURN_FACT'          FROM dual UNION ALL
    SELECT 'DELIVERY_FACT'        FROM dual UNION ALL
    SELECT 'POINT_FACT'           FROM dual
), chk AS (
    ---------------------------------------------------------------- TASK 1b
    SELECT 'TASK 1b' AS area,
           'All 12 star-schema tables exist' AS check_name,
           12 AS expected,
           (SELECT COUNT(*) FROM user_tables t
            WHERE  t.table_name IN (SELECT tab_name FROM dw_tables)) AS actual
    FROM dual
    UNION ALL
    SELECT 'TASK 1b', 'Every table has a primary key', 12,
           (SELECT COUNT(*) FROM user_constraints c
            WHERE  c.constraint_type = 'P'
            AND    c.table_name IN (SELECT tab_name FROM dw_tables))
    FROM dual
    UNION ALL
    SELECT 'TASK 1b', 'Fact tables with no foreign key (want 0)', 0,
           (SELECT COUNT(*) FROM user_tables t
            WHERE  t.table_name IN ('SALES_FACT','RETURN_FACT',
                                    'DELIVERY_FACT','POINT_FACT')
            AND NOT EXISTS (SELECT 1 FROM user_constraints c
                            WHERE  c.table_name = t.table_name
                            AND    c.constraint_type = 'R'))
    FROM dual
    UNION ALL
    SELECT 'TASK 1b', 'Tables with no CHECK constraint (want 0)', 0,
           (SELECT COUNT(*) FROM user_tables t
            WHERE  t.table_name IN (SELECT tab_name FROM dw_tables)
            AND NOT EXISTS (SELECT 1 FROM user_constraints c
                            WHERE  c.table_name = t.table_name
                            AND    c.constraint_type = 'C'
                            AND    c.search_condition IS NOT NULL))
    FROM dual
    UNION ALL
    SELECT 'TASK 1b', 'Type 2 dimension columns on customer_dim', 4,
           (SELECT COUNT(*) FROM user_tab_columns
            WHERE  table_name = 'CUSTOMER_DIM'
            AND    column_name IN ('EFFECTIVE_START_DATE','EFFECTIVE_END_DATE',
                                   'IS_CURRENT_FLAG','VERSION_NO'))
    FROM dual
    ---------------------------------------------------------------- TASK 2a
    UNION ALL
    SELECT 'TASK 2a', 'All 35 ETL views and procedures VALID', 35,
           (SELECT COUNT(*) FROM etl_objects e
            JOIN   user_objects o ON o.object_name = e.obj_name
                                 AND o.object_type = e.obj_type
            WHERE  o.status = 'VALID')
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'Invalid objects anywhere in schema (want 0)', 0,
           (SELECT COUNT(*) FROM user_objects WHERE status <> 'VALID')
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'Surrogate key sequences present', 7,
           (SELECT COUNT(*) FROM user_sequences
            WHERE  sequence_name LIKE 'SEQ\_DW\_%' ESCAPE '\')
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'Empty warehouse tables (want 0)', 0,
             (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM date_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM customer_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM item_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM branch_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM address_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM promotion_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM return_reason_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM delivery_company_dim)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM sales_fact)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM return_fact)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM delivery_fact)
           + (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM point_fact)
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'Every dimension has its -1 Unknown row', 8,
             (SELECT COUNT(*) FROM date_dim             WHERE date_key = -1)
           + (SELECT COUNT(*) FROM customer_dim         WHERE customer_key = -1)
           + (SELECT COUNT(*) FROM item_dim             WHERE item_key = -1)
           + (SELECT COUNT(*) FROM branch_dim           WHERE branch_key = -1)
           + (SELECT COUNT(*) FROM address_dim          WHERE address_key = -1)
           + (SELECT COUNT(*) FROM promotion_dim        WHERE promo_key = -1)
           + (SELECT COUNT(*) FROM return_reason_dim    WHERE reason_key = -1)
           + (SELECT COUNT(*) FROM delivery_company_dim WHERE delivery_company_key = -1)
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'promotion_dim key 0 = No Promotion seeded', 1,
           (SELECT COUNT(*) FROM promotion_dim WHERE promo_key = 0)
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'sales_fact reconciles to adm.OrderDetails', 0,
           (SELECT COUNT(*) FROM sales_fact)
         - (SELECT COUNT(*) FROM adm.OrderDetails)
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'Fact rows exceeding their source (want 0)', 0,
             (SELECT CASE WHEN (SELECT COUNT(*) FROM return_fact)
                             > (SELECT COUNT(*) FROM adm.ReturnDetails)
                          THEN 1 ELSE 0 END FROM dual)
           + (SELECT CASE WHEN (SELECT COUNT(*) FROM delivery_fact)
                             > (SELECT COUNT(*) FROM adm.Delivery)
                          THEN 1 ELSE 0 END FROM dual)
           + (SELECT CASE WHEN (SELECT COUNT(*) FROM point_fact)
                             > (SELECT COUNT(*) FROM adm.PointTransaction)
                          THEN 1 ELSE 0 END FROM dual)
    FROM dual
    UNION ALL
    SELECT 'TASK 2a', 'Negative or impossible sales measures (want 0)', 0,
           (SELECT COUNT(*) FROM sales_fact
            WHERE  quantity <= 0 OR unit_price < 0 OR net_sales_amt < 0
            OR     net_sales_amt > gross_sales_amt)
    FROM dual
    ------------------------------------------------------------- DATA SPAN
    UNION ALL
    SELECT 'DATA SPAN', 'Earliest year present in sales_fact', 2016,
           (SELECT MIN(d.cal_year) FROM sales_fact s
            JOIN   date_dim d ON d.date_key = s.order_date_key)
    FROM dual
    UNION ALL
    SELECT 'DATA SPAN', 'Latest year present in sales_fact',
           EXTRACT(YEAR FROM SYSDATE),
           (SELECT MAX(d.cal_year) FROM sales_fact s
            JOIN   date_dim d ON d.date_key = s.order_date_key)
    FROM dual
    UNION ALL
    SELECT 'DATA SPAN', 'Distinct years of sales history', 11,
           (SELECT COUNT(DISTINCT d.cal_year) FROM sales_fact s
            JOIN   date_dim d ON d.date_key = s.order_date_key)
    FROM dual
    UNION ALL
    SELECT 'DATA SPAN', 'Years with zero sales inside the span (want 0)', 0,
           (SELECT COUNT(*) FROM
              (SELECT DISTINCT cal_year FROM date_dim
               WHERE  date_key <> -1
               AND    cal_year BETWEEN 2016 AND EXTRACT(YEAR FROM SYSDATE)) y
            WHERE NOT EXISTS (SELECT 1 FROM sales_fact s
                              JOIN   date_dim d2 ON d2.date_key = s.order_date_key
                              WHERE  d2.cal_year = y.cal_year))
    FROM dual
    UNION ALL
    SELECT 'DATA SPAN', 'date_dim calendar starts 2016-01-01', 20160101,
           (SELECT MIN(date_key) FROM date_dim WHERE date_key <> -1)
    FROM dual
    UNION ALL
    SELECT 'DATA SPAN', 'Gaps in the calendar (want 0)', 0,
           (SELECT (MAX(cal_date) - MIN(cal_date) + 1) - COUNT(*)
            FROM   date_dim WHERE date_key <> -1)
    FROM dual
    UNION ALL
    SELECT 'DATA SPAN', 'Facts landing on the -1 Unknown date (want 0)', 0,
           (SELECT COUNT(*) FROM sales_fact WHERE order_date_key = -1)
    FROM dual
    ---------------------------------------------------------- STALE LOGIC
    UNION ALL
    SELECT 'STALENESS', 'load_date_dim still hardcodes 2020 (want 0)', 0,
           (SELECT COUNT(*) FROM user_source
            WHERE  name = 'LOAD_DATE_DIM' AND type = 'PROCEDURE'
            AND    text LIKE '%2020-01-01%')
    FROM dual
    UNION ALL
    SELECT 'STALENESS', 'customer view still stamps SYSDATE (want 0)', 0,
           (SELECT COUNT(*) FROM user_source
            WHERE  name = 'VW_LOAD_CUSTOMER_DIM'
            AND    UPPER(text) LIKE '%SYSDATE AS EFFECTIVE_START_DATE%')
    FROM dual
    UNION ALL
    SELECT 'STALENESS', 'sales view still joins is_current_flag (want 0)', 0,
           (SELECT COUNT(*) FROM user_source
            WHERE  name = 'VW_LOAD_SALES_FACT'
            AND    UPPER(text) LIKE '%IS_CURRENT_FLAG%')
    FROM dual
    ---------------------------------------------------------------- TASK 2b
    UNION ALL
    SELECT 'TASK 2b', 'Customers with other than one current row (want 0)', 0,
           (SELECT COUNT(*) FROM
              (SELECT customer_id FROM customer_dim
               WHERE  is_current_flag = 'Y'
               GROUP  BY customer_id HAVING COUNT(*) <> 1))
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Overlapping SCD2 date ranges (want 0)', 0,
           (SELECT COUNT(*) FROM customer_dim a JOIN customer_dim b
            ON  a.customer_id = b.customer_id
            AND a.customer_key < b.customer_key
            AND a.effective_start_date <= b.effective_end_date
            AND b.effective_start_date <= a.effective_end_date)
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Closed rows still flagged current (want 0)', 0,
           (SELECT COUNT(*) FROM customer_dim
            WHERE  is_current_flag = 'N'
            AND    effective_end_date = DATE '9999-12-31')
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'A version 2 row exists (proves SCD2 fired)', 1,
           (SELECT CASE WHEN COUNT(*) >= 1 THEN 1 ELSE 0 END
            FROM   customer_dim WHERE version_no >= 2)
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Incremental rows carry etl_batch_id 2', 1,
           (SELECT CASE WHEN COUNT(*) >= 1 THEN 1 ELSE 0 END
            FROM   sales_fact WHERE etl_batch_id = 2)
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Scrubbed customer C9901 loaded and cleaned', 1,
           (SELECT COUNT(*) FROM customer_dim
            WHERE  customer_id = 'C9901'
            AND    customer_name = 'Lim Wei Jian'
            AND    customer_email = 'Unknown'
            AND    customer_ic = 'Unknown')
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Pending delivery routed to Unknown date key', 1,
           (SELECT COUNT(*) FROM delivery_fact
            WHERE  delivery_id = 'DLV00642' AND delivery_date_key = -1)
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Impossible returns rejected, not loaded (want 0)', 0,
           (SELECT COUNT(*) FROM return_fact
            WHERE  return_id IN ('RET00135','RET00136'))
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Negative days_to_return in warehouse (want 0)', 0,
           (SELECT COUNT(*) FROM return_fact WHERE days_to_return < 0)
    FROM dual
    UNION ALL
    SELECT 'TASK 2b', 'Negative delivery_lead_days in warehouse (want 0)', 0,
           (SELECT COUNT(*) FROM delivery_fact WHERE delivery_lead_days < 0)
    FROM dual
)
SELECT area, check_name, expected, actual,
       CASE WHEN actual = expected THEN 'PASS' ELSE '>> FAIL <<' END AS verdict
FROM   chk
ORDER  BY CASE WHEN actual = expected THEN 1 ELSE 0 END,
          CASE area WHEN 'TASK 1b' THEN 1 WHEN 'TASK 2a' THEN 2
                    WHEN 'DATA SPAN' THEN 3 WHEN 'STALENESS' THEN 4
                    ELSE 5 END,
          check_name;

SET FEEDBACK ON

PROMPT
PROMPT ####################################################################
PROMPT #  SUPPORTING DETAIL - screenshot these for the report             #
PROMPT ####################################################################

PROMPT
PROMPT === D1. ELEVEN YEARS OF SALES HISTORY IN THE STAR SCHEMA ===
COLUMN revenue FORMAT 9999999.99
SELECT d.cal_year,
       COUNT(DISTINCT s.order_no)      AS orders,
       COUNT(*)                        AS order_lines,
       ROUND(SUM(s.gross_sales_amt),2) AS gross,
       ROUND(SUM(s.discount_amt),2)    AS discount,
       ROUND(SUM(s.net_sales_amt),2)   AS revenue
FROM   sales_fact s
JOIN   date_dim   d ON d.date_key = s.order_date_key
GROUP  BY d.cal_year
ORDER  BY d.cal_year;

PROMPT
PROMPT === D2. SOURCE vs WAREHOUSE, WITH THE GAP EXPLAINED ===
PROMPT A negative gap on return_fact or delivery_fact is CORRECT: those are
PROMPT the dirty rows Task 2b rejected on purpose.
COLUMN check_name FORMAT A44
COLUMN note       FORMAT A40
SELECT 'sales_fact vs OrderDetails' AS check_name,
       (SELECT COUNT(*) FROM adm.OrderDetails) AS source_rows,
       (SELECT COUNT(*) FROM sales_fact)       AS dw_rows,
       (SELECT COUNT(*) FROM sales_fact)
     - (SELECT COUNT(*) FROM adm.OrderDetails) AS gap,
       'must be 0' AS note
FROM dual
UNION ALL
SELECT 'return_fact vs ReturnDetails',
       (SELECT COUNT(*) FROM adm.ReturnDetails),
       (SELECT COUNT(*) FROM return_fact),
       (SELECT COUNT(*) FROM return_fact)
     - (SELECT COUNT(*) FROM adm.ReturnDetails),
       'gap = returns rejected by DQ rules'
FROM dual
UNION ALL
SELECT 'delivery_fact vs Delivery',
       (SELECT COUNT(*) FROM adm.Delivery),
       (SELECT COUNT(*) FROM delivery_fact),
       (SELECT COUNT(*) FROM delivery_fact)
     - (SELECT COUNT(*) FROM adm.Delivery),
       'gap = deliveries rejected by DQ rules'
FROM dual
UNION ALL
SELECT 'point_fact vs PointTransaction',
       (SELECT COUNT(*) FROM adm.PointTransaction),
       (SELECT COUNT(*) FROM point_fact),
       (SELECT COUNT(*) FROM point_fact)
     - (SELECT COUNT(*) FROM adm.PointTransaction),
       'must be 0'
FROM dual;

PROMPT
PROMPT === D3. THE TYPE 2 DIMENSION IN ACTION ===
COLUMN customer_id     FORMAT A12
COLUMN customer_status FORMAT A10
SELECT customer_key, customer_id, customer_status, version_no,
       effective_start_date, effective_end_date, is_current_flag
FROM   customer_dim
WHERE  customer_id IN (SELECT customer_id FROM customer_dim
                       WHERE version_no >= 2)
ORDER  BY customer_id, version_no;

PROMPT
PROMPT === D4. UNKNOWN KEY USAGE, RECONCILED TO SOURCE NULLS ===
SELECT 'delivery_fact.delivery_date_key = -1' AS check_name,
       (SELECT COUNT(*) FROM delivery_fact WHERE delivery_date_key = -1) AS dw_unknowns,
       (SELECT COUNT(*) FROM adm.Delivery  WHERE DeliveryDate IS NULL)   AS source_nulls
FROM dual
UNION ALL
SELECT 'point_fact.branch_key = -1',
       (SELECT COUNT(*) FROM point_fact WHERE branch_key = -1),
       (SELECT COUNT(*) FROM adm.PointTransaction WHERE OrderNo IS NULL)
FROM dual;

PROMPT
PROMPT === D5. ETL BATCH SEPARATION (1 = Task 2a, 2 = Task 2b) ===
COLUMN tbl FORMAT A20
SELECT 'sales_fact' AS tbl, etl_batch_id, COUNT(*) AS rows_loaded
FROM   sales_fact GROUP BY etl_batch_id
UNION ALL SELECT 'delivery_fact', etl_batch_id, COUNT(*)
FROM   delivery_fact GROUP BY etl_batch_id
UNION ALL SELECT 'customer_dim', etl_batch_id, COUNT(*)
FROM   customer_dim GROUP BY etl_batch_id
ORDER  BY 1, 2;

PROMPT
PROMPT === D6. WAREHOUSE TABLE SIZES ===
SELECT 'date_dim' AS tbl, COUNT(*) AS rows_now FROM date_dim
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
ORDER  BY 1;

PROMPT
PROMPT ####################################################################
PROMPT #  If the verdict table is all PASS, Tasks 1 and 2 are complete    #
PROMPT #  and the warehouse is ready for Task 3.                          #
PROMPT ####################################################################
SET SQLBLANKLINES OFF
