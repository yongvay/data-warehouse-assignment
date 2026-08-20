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
    maintain_customer_dim_scd2();

    -- 4. Fact Tables (Looking back 7 days to catch recent entries)
    load_sales_fact_incr(SYSDATE - 7);
    load_return_fact_incr(SYSDATE - 7);
    load_delivery_fact_incr(SYSDATE - 7);
    load_point_fact_incr(SYSDATE - 7);

    DBMS_OUTPUT.PUT_LINE('--- INCREMENTAL LOAD COMPLETE ---');
END;
/

-- SET SERVEROUTPUT ON;
-- EXEC run_task2b;