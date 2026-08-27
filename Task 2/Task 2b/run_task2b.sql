-- ============================================================================
--  run_task2b.sql   -   RUN AS THE DW USER
--
--  Defines the Task 2(b) driver procedure.  It does NOT run the load.
--
--  Do not call this file directly - compile_task2b.sql runs it LAST, after
--  every load_*_incr procedure it calls already exists.
--
--      SQL> @"Task 2\Task 2b\compile_task2b.sql"    -- compiles this too
--      SQL> SET SERVEROUTPUT ON
--      SQL> EXEC run_task2b
-- ============================================================================
CREATE OR REPLACE PROCEDURE run_task2b AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- STARTING TASK 2B INCREMENTAL LOAD ---');

    -- 1. Extend Calendar
    load_date_dim_incr();

    -- 2. Type 1 Dimensions
    load_address_dim_incr();
    load_branch_dim_incr();
    load_delivery_company_dim_incr();
    load_item_dim_incr();
    load_promotion_dim_incr();
    load_return_reason_dim_incr();

    -- 3. Type 2 Dimension (Customer)
    load_customer_dim_new_records();
    maintain_customer_dim_type1();
    maintain_customer_dim_scd2();

    -- 4. Fact Tables (Looking back 7 days to catch recent entries)
    load_sales_fact_incr(SYSDATE - 7);
    load_return_fact_incr(SYSDATE - 7);
    load_delivery_fact_incr(SYSDATE - 7);
    load_point_fact_incr(SYSDATE - 7);

    DBMS_OUTPUT.PUT_LINE('--- INCREMENTAL LOAD COMPLETE ---');
END;
/

