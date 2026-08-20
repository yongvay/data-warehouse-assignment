-- PART A: Insert completely new customers
CREATE OR REPLACE PROCEDURE load_customer_dim_new_records AS
    v_new_records NUMBER := 0;
    CURSOR new_cust_cursor IS
        SELECT s.* FROM vw_load_customer_dim s
        WHERE NOT EXISTS (SELECT 1 FROM customer_dim cd WHERE cd.customer_id = s.customer_id);
BEGIN
    FOR rec IN new_cust_cursor LOOP
        INSERT INTO customer_dim (
            customer_key, customer_id, customer_name, customer_ic, customer_email, 
            customer_status, member_flag, membership_type, annual_fee, point_earn_rate, 
            membership_expiry, effective_start_date, effective_end_date, is_current_flag, version_no, etl_batch_id
        ) VALUES (
            seq_dw_cust.NEXTVAL, rec.customer_id, rec.customer_name, rec.customer_ic, rec.customer_email,
            rec.customer_status, rec.member_flag, rec.membership_type, rec.annual_fee, rec.point_earn_rate,
            rec.membership_expiry, SYSDATE, DATE '9999-12-31', 'Y', 1, 2
        );
        v_new_records := v_new_records + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CUSTOMER_DIM New Records: ' || v_new_records || ' inserted.');
END;
/

-- PART B: Maintain SCD Type 2 History for existing customers
-- 1. RECREATE THE SCD2 MAINTENANCE PROCEDURE (FIXED)
CREATE OR REPLACE PROCEDURE maintain_customer_dim_scd2 AS
    v_updated_records NUMBER := 0;
    CURSOR changed_cust_cursor IS
        SELECT 
            s.customer_id, s.customer_name, s.customer_ic, s.customer_email, 
            s.customer_status, s.member_flag, s.membership_type, s.annual_fee, 
            s.point_earn_rate, s.membership_expiry, 
            cd.customer_key, cd.version_no AS old_version_no
        FROM vw_load_customer_dim s
        JOIN customer_dim cd ON s.customer_id = cd.customer_id
        WHERE cd.is_current_flag = 'Y'
        AND (
            NVL(cd.customer_status, 'X') != NVL(s.customer_status, 'X') OR
            NVL(cd.member_flag, 'X') != NVL(s.member_flag, 'X') OR
            NVL(cd.membership_type, 'X') != NVL(s.membership_type, 'X')
        );
BEGIN
    FOR rec IN changed_cust_cursor LOOP
        -- Expire the old record
        UPDATE customer_dim
        SET effective_end_date = SYSDATE - 1, is_current_flag = 'N', etl_update_dt = SYSDATE
        WHERE customer_key = rec.customer_key;

        -- Insert the new version
        INSERT INTO customer_dim (
            customer_key, customer_id, customer_name, customer_ic, customer_email, 
            customer_status, member_flag, membership_type, annual_fee, point_earn_rate, 
            membership_expiry, effective_start_date, effective_end_date, is_current_flag, version_no, etl_batch_id
        ) VALUES (
            seq_dw_cust.NEXTVAL, rec.customer_id, rec.customer_name, rec.customer_ic, rec.customer_email,
            rec.customer_status, rec.member_flag, rec.membership_type, rec.annual_fee, rec.point_earn_rate,
            rec.membership_expiry, SYSDATE, DATE '9999-12-31', 'Y', rec.old_version_no + 1, 2
        );
        v_updated_records := v_updated_records + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CUSTOMER_DIM SCD2 Maintenance: ' || v_updated_records || ' versions updated.');
END;
/

-- 2. RECOMPILE THE MASTER DRIVER
CREATE OR REPLACE PROCEDURE run_task2b AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- STARTING TASK 2B INCREMENTAL LOAD ---');

    load_date_dim_incr();
    load_address_dim_incr();
    load_branch_dim_incr();
    load_delivery_company_dim_incr();
    load_item_dim_incr();
    load_promotion_dim_incr();
    load_return_reason_dim_incr();
    load_customer_dim_new_records();
    maintain_customer_dim_scd2();
    load_sales_fact_incr(SYSDATE - 7);
    load_return_fact_incr(SYSDATE - 7);
    load_delivery_fact_incr(SYSDATE - 7);
    load_point_fact_incr(SYSDATE - 7);

    DBMS_OUTPUT.PUT_LINE('--- INCREMENTAL LOAD COMPLETE ---');
END;
/