-- ============================================================================
--  run_task2a_initial_load.sql   -   RUN AS THE DW USER
--
--  Defines the Task 2(a) driver procedure.  It does NOT run the load.
--
--  Do not call this file directly - compile_task2a.sql runs it LAST, after
--  every load_* procedure it calls already exists.  PL/SQL resolves called
--  procedures at compile time, so the driver will not compile before them.
--
--      SQL> @"Task 2\Task 2a\compile_task2a.sql"    -- compiles this too
--      SQL> @"utils\delete_table.sql"
--      SQL> SET SERVEROUTPUT ON
--      SQL> EXEC run_task2a_initial_load
-- ============================================================================
CREATE OR REPLACE PROCEDURE run_task2a_initial_load AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- STARTING TASK 2A: INITIAL HISTORICAL LOAD ---');

    -- PHASE 1: LOAD DIMENSION TABLES
    -- These have no dependencies and must be loaded first.
    load_date_dim();
    load_return_reason_dim();
    load_delivery_company_dim();
    load_branch_dim();
    load_address_dim();
    load_promotion_dim();
    load_item_dim();
    load_customer_dim_init(); 
    
    DBMS_OUTPUT.PUT_LINE('--- PHASE 1 COMPLETE: ALL DIMENSIONS LOADED ---');

    -- PHASE 2: LOAD FACT TABLES
    -- These depend on the surrogate keys generated in Phase 1.
    load_sales_fact();
    load_return_fact();
    load_delivery_fact();
    load_point_fact();

    DBMS_OUTPUT.PUT_LINE('--- PHASE 2 COMPLETE: ALL FACT TABLES LOADED ---');
    DBMS_OUTPUT.PUT_LINE('--- TASK 2A SUCCESSFULLY COMPLETED ---');
    
EXCEPTION
    -- Basic error handling to catch and display where the load fails
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('CRITICAL ERROR DURING LOAD: ' || SQLERRM);
        RAISE;
END;
/

