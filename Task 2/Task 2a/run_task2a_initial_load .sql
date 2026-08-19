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