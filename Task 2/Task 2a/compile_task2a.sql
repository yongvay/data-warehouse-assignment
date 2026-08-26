-- ============================================================================
--  compile_task2a.sql   -   RUN AS THE DW USER
--
--      SQL> @"C:\Users\PC\Desktop\DW\Task 2\Task 2a\compile_task2a.sql"
--
--  Recompiles every Task 2(a) view and procedure in dependency order, then
--  reports anything that failed.
--
--  WHY YOU NEED THIS
--
--  DROP TABLE does not drop procedures.  Rebuilding the warehouse with
--  Task1b_Physical_Design.sql replaces the tables but leaves whatever
--  load_* procedures were last compiled still sitting in the schema - so a
--  "rebuild" happily reloads using MONTHS-OLD ETL logic, with no error and no
--  warning.  That is how a stale load_date_dim kept building a 2020 calendar
--  after the script on disk had been changed to 2016.
--
--  Run this after ANY change to the Task 2(a) scripts, and always as part of
--  a rebuild, BEFORE delete_table.sql and run_task2a_initial_load.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK ON

PROMPT
PROMPT === COMPILING TASK 2A DIMENSIONS ===
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\DATE_DIM.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\RETURN_REASON_DIM.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\DELIVERY_COMPANY_DIM.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\BRANCH_DIM.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\ADDRESS_DIM.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\PROMOTION_DIM.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\ITEM_DIM.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\DIM\CUSTOMER_DIM_INIT.sql"

PROMPT
PROMPT === COMPILING TASK 2A FACTS ===
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\FACT\SALES_FACT.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\FACT\RETURN_FACT.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\FACT\DELIVERY_FACT.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\FACT\POINT_FACT.sql"

PROMPT
PROMPT === COMPILING THE DRIVER (must be last) ===
@"C:\Users\PC\Desktop\DW\Task 2\Task 2a\run_task2a_initial_load.sql"

SET LINESIZE 160
SET PAGESIZE 200
COLUMN object_name FORMAT A32
COLUMN object_type FORMAT A12
COLUMN status      FORMAT A14
COLUMN name        FORMAT A30
COLUMN type        FORMAT A10
COLUMN text        FORMAT A70

PROMPT
PROMPT === MISSING OR INVALID OBJECTS (must be 0 rows) ===
WITH expected (obj_name, obj_type) AS (
    SELECT 'VW_LOAD_ADDRESS_DIM',       'VIEW'      FROM dual UNION ALL
    SELECT 'VW_LOAD_CUSTOMER_DIM',      'VIEW'      FROM dual UNION ALL
    SELECT 'VW_LOAD_SALES_FACT',        'VIEW'      FROM dual UNION ALL
    SELECT 'ORDER_DATE_DIM',            'VIEW'      FROM dual UNION ALL
    SELECT 'RETURN_DATE_DIM',           'VIEW'      FROM dual UNION ALL
    SELECT 'DELIVERY_DATE_DIM',         'VIEW'      FROM dual UNION ALL
    SELECT 'TRANS_DATE_DIM',            'VIEW'      FROM dual UNION ALL
    SELECT 'LOAD_DATE_DIM',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_REASON_DIM',    'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_COMPANY_DIM', 'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_BRANCH_DIM',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ADDRESS_DIM',          'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_PROMOTION_DIM',        'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_ITEM_DIM',             'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_CUSTOMER_DIM_INIT',    'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_SALES_FACT',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_RETURN_FACT',          'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_FACT',        'PROCEDURE' FROM dual UNION ALL
    SELECT 'LOAD_POINT_FACT',           'PROCEDURE' FROM dual UNION ALL
    SELECT 'RUN_TASK2A_INITIAL_LOAD',   'PROCEDURE' FROM dual
)
SELECT e.obj_name AS object_name, e.obj_type AS object_type,
       NVL(o.status, '>> MISSING <<') AS status
FROM   expected e
LEFT   JOIN user_objects o
       ON  o.object_name = e.obj_name AND o.object_type = e.obj_type
WHERE  o.object_name IS NULL OR o.status <> 'VALID';

PROMPT
PROMPT === COMPILATION ERRORS, IF ANY ===
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

PROMPT
PROMPT === IS THE COMPILED LOGIC ACTUALLY CURRENT? (all must read 0) ===
PROMPT A non-zero count means the OLD version is still what the database will
PROMPT run, whatever the file on disk says.
COLUMN stale_check FORMAT A52
SELECT 'load_date_dim still starts the calendar in 2020' AS stale_check,
       COUNT(*) AS stale_lines
FROM   user_source
WHERE  name = 'LOAD_DATE_DIM' AND type = 'PROCEDURE'
AND    text LIKE '%2020-01-01%'
UNION ALL
SELECT 'vw_load_customer_dim still stamps SYSDATE', COUNT(*)
FROM   user_source
WHERE  name = 'VW_LOAD_CUSTOMER_DIM'
AND    UPPER(text) LIKE '%SYSDATE AS EFFECTIVE_START_DATE%'
UNION ALL
SELECT 'vw_load_sales_fact still joins is_current_flag', COUNT(*)
FROM   user_source
WHERE  name = 'VW_LOAD_SALES_FACT'
AND    UPPER(text) LIKE '%IS_CURRENT_FLAG%';

PROMPT
PROMPT === CALENDAR RANGE THE COMPILED PROCEDURE WILL BUILD ===
PROMPT Expect 2016-01-01 to 2030-12-31.
SELECT line, TRIM(text) AS text
FROM   user_source
WHERE  name = 'LOAD_DATE_DIM'
AND    type = 'PROCEDURE'
AND    (UPPER(text) LIKE '%V_CURR_DATE DATE%'
        OR UPPER(text) LIKE '%V_END_DATE  DATE%')
ORDER  BY line;

PROMPT
PROMPT ####################################################################
PROMPT #  If the lists above are clean, continue:                         #
PROMPT #     @utils\delete_table.sql                                      #
PROMPT #     EXEC run_task2a_initial_load                                 #
PROMPT #     @utils\verify_task2a.sql                                     #
PROMPT ####################################################################
