-- SET SQLBLANKLINES ON;
-- SET SERVEROUTPUT ON;

-- PROMPT --- COMPILING TASK 2A DIMENSIONS ---
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\CREATE_SEQUENCE.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\ADDRESS_DIM.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\BRANCH_DIM.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\CUSTOMER_DIM_INIT.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\DATE_DIM.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\DELIVERY_COMPANY_DIM.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\ITEM_DIM.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\PROMOTION_DIM.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\DIM\RETURN_REASON_DIM.sql"

-- PROMPT --- COMPILING TASK 2A FACTS ---
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\FACT\DELIVERY_FACT.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\FACT\POINT_FACT.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\FACT\RETURN_FACT.sql"
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\FACT\SALES_FACT.sql"

-- PROMPT --- COMPILING TASK 2A DRIVER ---
-- @"C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment\Task 2\Task 2a\run_task2a_initial_load.sql"

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

-- To run it,  
--EXEC run_task2a_initial_load
