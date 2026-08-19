-- ============================================================================
--  TASK 2(a) : ONE-SHOT INSTALLER  (added for convenience - compiles the
--              existing Task 2a objects in dependency order and runs the
--              historical load)
--
--  RUN AS THE DW USER, after:
--      1. the adm operational schema exists and is populated
--      2. Task 1/Task1b_Grants_RunAsADM.sql has been run AS ADM
--      3. Task 1/Task1b_Physical_Design.sql has been run AS DW
--
--  USAGE (full path works - @@ resolves relative to this file's folder):
--      SQL> @"C:\Users\USER\Desktop\DWT\Task 2\Task 2a\RUN_ALL_TASK2A.sql"
--
--  WARNING - THIS IS A FIRST-TIME LOAD, NOT AN INCREMENTAL ONE.
--      run_task2a_initial_load inserts the seeded -1 rows unconditionally.
--      Running it twice without re-running Task1b_Physical_Design.sql first
--      will fail on ORA-00001 (unique constraint).  To start over cleanly:
--          @"...\Task 1\Task1b_Physical_Design.sql"     -- drops + recreates
--          @"...\Task 2\Task 2a\RUN_ALL_TASK2A.sql"
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT ############ SEQUENCES ####################################################
PROMPT (ORA-00955 "name is already used" here is harmless - it means the
PROMPT  sequences already exist from a previous run.)
@@DIM/CREATE_SEQUENCE.sql

PROMPT
PROMPT ############ DIMENSION LOAD PROCEDURES ####################################
@@DIM/DATE_DIM.sql
@@DIM/RETURN_REASON_DIM.sql
@@DIM/DELIVERY_COMPANY_DIM.sql
@@DIM/BRANCH_DIM.sql
@@DIM/ADDRESS_DIM.sql
@@DIM/PROMOTION_DIM.sql
@@DIM/ITEM_DIM.sql
@@DIM/CUSTOMER_DIM_INIT.sql

PROMPT
PROMPT ############ FACT LOAD PROCEDURES #########################################
@@FACT/SALES_FACT.sql
@@FACT/RETURN_FACT.sql
@@FACT/DELIVERY_FACT.sql
@@FACT/POINT_FACT.sql

PROMPT
PROMPT ############ MASTER DRIVER ################################################
-- note the space in the original file name, hence the quotes
@@"run_task2a_initial_load .sql"

PROMPT
PROMPT ############ COMPILATION CHECK - this MUST return no rows #################
COLUMN object_name FORMAT A34
COLUMN object_type FORMAT A14
SELECT object_name, object_type, status
  FROM user_objects
 WHERE status <> 'VALID'
 ORDER BY object_type, object_name;

PROMPT
PROMPT ############ RUNNING THE HISTORICAL LOAD ##################################
EXEC run_task2a_initial_load

PROMPT
PROMPT ############ ROW COUNTS ###################################################
SELECT 'date_dim'             AS table_name, COUNT(*) AS rows_loaded FROM date_dim
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
PROMPT ############ TASK 2A COMPLETE - now run Task 2b ###########################
