-- ============================================================================
--  TASK 2(b) : ONE-SHOT INSTALLER
--  Compiles every Task 2b object in dependency order, then runs the load.
--
--  HOW TO USE IN SQL*PLUS
--      1. cd into this folder first, so the @@ relative paths resolve:
--             sqlplus dw/password@xe
--             SQL> HOST cd "C:\Users\USER\Desktop\DWT\Task 2\Task 2b"
--         (or just open SQL*Plus from that folder)
--      2. SQL> @RUN_ALL_TASK2B.sql
--
--  PREREQUISITES
--      - Task 1b physical design has been run (12 tables exist)
--      - Task 2a initial load has been run (dimensions seeded, facts populated)
--      - The adm owner has granted SELECT on all 18 source tables to this user
--        (Task 1/Task1b_Grants_RunAsADM.sql)
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK ON
SET TIMING ON
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT ############ 00 : ETL control, audit and reject infrastructure ############
@@00_ETL_CONTROL_DDL.sql

PROMPT
PROMPT ############ 01 : data-scrubbing function library ##########################
@@01_SCRUB_FUNCTIONS.sql

PROMPT
PROMPT ############ 02 : staging / scrubbing views ################################
@@02_STAGING_VIEWS.sql

PROMPT
PROMPT ############ DIM : dimension load procedures ###############################
@@DIM/DATE_DIM_EXTEND.sql
@@DIM/RETURN_REASON_DIM_DELTA.sql
@@DIM/DELIVERY_COMPANY_DIM_DELTA.sql
@@DIM/BRANCH_DIM_DELTA.sql
@@DIM/ADDRESS_DIM_DELTA.sql
@@DIM/PROMOTION_DIM_DELTA.sql
@@DIM/ITEM_DIM_DELTA.sql
@@DIM/CUSTOMER_DIM_SCD2.sql

PROMPT
PROMPT ############ FACT : fact load procedures ###################################
@@FACT/SALES_FACT_DELTA.sql
@@FACT/RETURN_FACT_DELTA.sql
@@FACT/DELIVERY_FACT_DELTA.sql
@@FACT/POINT_FACT_DELTA.sql

PROMPT
PROMPT ############ 03 : verification / reconciliation views ######################
@@03_RECON_VIEWS.sql

PROMPT
PROMPT ############ 99 : master driver ############################################
@@99_run_task2b_subsequent_load.sql

PROMPT
PROMPT ############ COMPILATION CHECK - this MUST return no rows #################
COLUMN object_name FORMAT A34
COLUMN object_type FORMAT A14
SELECT object_name, object_type, status
  FROM user_objects
 WHERE status <> 'VALID'
 ORDER BY object_type, object_name;

PROMPT
PROMPT ############ RUNNING THE INCREMENTAL LOAD #################################
EXEC run_task2b_subsequent_load

PROMPT
PROMPT ############ WHAT THE RUN DID #############################################
COLUMN target_object FORMAT A24
COLUMN step_time     FORMAT A20
SELECT * FROM vw_etl_step_summary
 WHERE batch_id = (SELECT MAX(batch_id) FROM etl_batch_control);

PROMPT
PROMPT ############ DIRTY DATA FOUND ############################################
COLUMN rule_description FORMAT A62
COLUMN example_key      FORMAT A16
SELECT * FROM vw_etl_reject_summary
 WHERE batch_id = (SELECT MAX(batch_id) FROM etl_batch_control);

PROMPT
PROMPT ############ SCD2 INTEGRITY - this MUST return no rows ###################
SELECT * FROM vw_scd2_integrity_check;

SET TIMING OFF
PROMPT
PROMPT ############ TASK 2B INSTALL COMPLETE ####################################
