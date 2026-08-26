-- ============================================================================
--  utils/check_status.sql
--  Run this AS DW after any script to confirm it really succeeded.
--      SQL> @"C:\Users\PC\Desktop\DW\utils\check_status.sql"
-- ============================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A20
COLUMN status      FORMAT A10
COLUMN name        FORMAT A30
COLUMN text        FORMAT A80
COLUMN table_name  FORMAT A30

PROMPT
PROMPT ============ 1. WHO AM I / WHERE AM I ============
SELECT USER AS connected_as FROM dual;

PROMPT
PROMPT ============ 2. CAN I SEE THE SOURCE (ADM) TABLES? ============
PROMPT (Expect 18 rows. 0 rows = the GRANT script was never run as ADM.)
SELECT owner, table_name
FROM   all_tables
WHERE  owner = 'ADM'
ORDER  BY table_name;

PROMPT
PROMPT ============ 3. DO I HAVE THE SYSTEM PRIVILEGES I NEED? ============
PROMPT (Expect CREATE VIEW, CREATE PROCEDURE, CREATE SEQUENCE, CREATE TABLE.)
SELECT privilege
FROM   user_sys_privs
ORDER  BY privilege;

PROMPT
PROMPT ============ 4. ARE THE ADM GRANTS DIRECT (not via a role)? ============
PROMPT (Direct grants are REQUIRED to compile views/procedures over ADM.)
SELECT owner, table_name, privilege, grantee
FROM   user_tab_privs_recd
WHERE  owner = 'ADM'
ORDER  BY table_name;

PROMPT
PROMPT ============ 5. DW TABLES CREATED ============
SELECT table_name FROM user_tables ORDER BY table_name;

PROMPT
PROMPT ============ 6. ANY BROKEN OBJECTS? ============
PROMPT (An empty result here is the success signal.)
SELECT object_type, object_name, status
FROM   user_objects
WHERE  status <> 'VALID'
ORDER  BY object_type, object_name;

PROMPT
PROMPT ============ 7. THE ACTUAL COMPILATION ERRORS ============
SELECT name, type, line, position, text
FROM   user_errors
ORDER  BY name, sequence;

PROMPT
PROMPT ============ 8. ROW COUNTS AFTER A LOAD ============
SELECT 'date_dim'             AS tbl, COUNT(*) AS rows_loaded FROM date_dim
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
UNION ALL SELECT 'point_fact',           COUNT(*) FROM point_fact;

PROMPT
PROMPT ============ DONE ============
