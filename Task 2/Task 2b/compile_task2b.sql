-- ============================================================================
--  compile_task2b.sql   -   RUN AS THE DW USER
--
--      SQL> @"C:\Users\PC\Desktop\DW\Task 2\Task 2b\compile_task2b.sql"
--
--  Compiles every Task 2(b) procedure in dependency order, then reports any
--  object that failed.  The driver run_task2b MUST come last: PL/SQL resolves
--  the procedures it calls at compile time, so load_date_dim_incr and friends
--  have to exist before the driver referencing them will compile.
--
--  Run this AFTER Task 2(a) has loaded and verify_task2a.sql is clean.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK ON

PROMPT
PROMPT === COMPILING TASK 2B DIMENSIONS ===
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\DATE_DIM_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\ADDRESS_DIM_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\BRANCH_DIM_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\DELIVERY_COMPANY_DIM_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\ITEM_DIM_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\PROMOTION_DIM_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\RETURN_REASON_DIM_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\DIM\CUSTOMER_DIM_NEW_RECORD.sql"

PROMPT
PROMPT === COMPILING TASK 2B FACTS ===
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\FACT\SALES_FACT_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\FACT\RETURN_FACT_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\FACT\DELIVERY_FACT_INCREMENTAL.sql"
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\FACT\POINT_FACT_INCREMENTAL.sql"

PROMPT
PROMPT === COMPILING THE DRIVER (must be last) ===
@"C:\Users\PC\Desktop\DW\Task 2\Task 2b\run_task2b.sql"

-- ----------------------------------------------------------------------------
--  DID EVERYTHING COMPILE?
-- ----------------------------------------------------------------------------
SET LINESIZE 160
SET PAGESIZE 200
COLUMN object_name FORMAT A34
COLUMN object_type FORMAT A12
COLUMN status      FORMAT A14
COLUMN name        FORMAT A30
COLUMN type        FORMAT A10
COLUMN text        FORMAT A70

PROMPT
PROMPT === EXPECTED TASK 2B PROCEDURES - anything MISSING or INVALID is a fault ===
WITH expected (obj_name) AS (
    SELECT 'LOAD_DATE_DIM_INCR'             FROM dual UNION ALL
    SELECT 'LOAD_ADDRESS_DIM_INCR'          FROM dual UNION ALL
    SELECT 'LOAD_BRANCH_DIM_INCR'           FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_COMPANY_DIM_INCR' FROM dual UNION ALL
    SELECT 'LOAD_ITEM_DIM_INCR'             FROM dual UNION ALL
    SELECT 'LOAD_PROMOTION_DIM_INCR'        FROM dual UNION ALL
    SELECT 'LOAD_RETURN_REASON_DIM_INCR'    FROM dual UNION ALL
    SELECT 'LOAD_CUSTOMER_DIM_NEW_RECORDS'  FROM dual UNION ALL
    SELECT 'MAINTAIN_CUSTOMER_DIM_TYPE1'    FROM dual UNION ALL
    SELECT 'MAINTAIN_CUSTOMER_DIM_SCD2'     FROM dual UNION ALL
    SELECT 'LOAD_SALES_FACT_INCR'           FROM dual UNION ALL
    SELECT 'LOAD_RETURN_FACT_INCR'          FROM dual UNION ALL
    SELECT 'LOAD_DELIVERY_FACT_INCR'        FROM dual UNION ALL
    SELECT 'LOAD_POINT_FACT_INCR'           FROM dual UNION ALL
    SELECT 'RUN_TASK2B'                     FROM dual
)
SELECT e.obj_name AS object_name,
       NVL(o.status, '>> MISSING <<') AS status
FROM   expected e
LEFT   JOIN user_objects o
       ON  o.object_name = e.obj_name
       AND o.object_type = 'PROCEDURE'
WHERE  o.object_name IS NULL
   OR  o.status <> 'VALID';

PROMPT
PROMPT === COMPILATION ERRORS, IF ANY ===
SELECT name, type, line, text
FROM   user_errors
ORDER  BY name, sequence;

PROMPT
PROMPT === ANY INVALID OBJECT AT ALL (must be 0 rows) ===
SELECT object_type, object_name, status
FROM   user_objects
WHERE  status <> 'VALID'
ORDER  BY object_type, object_name;

PROMPT
PROMPT ####################################################################
PROMPT #  If both lists above are empty, Task 2b is compiled.             #
PROMPT #                                                                  #
PROMPT #  Order from here:                                                #
PROMPT #    1. as ADM : insert_dirty_data.sql                             #
PROMPT #    2. as DW  : EXEC run_task2b                                   #
PROMPT #    3. as DW  : @utils\compare_after_2b.sql                       #
PROMPT ####################################################################
