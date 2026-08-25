-- ============================================================================
--  CUSTOMER_DIM INCREMENTAL - NEW RECORDS AND SCD TYPE 2 MAINTENANCE
-- ----------------------------------------------------------------------------
--  CORRECTIONS APPLIED TO THIS FILE
--
--  1. THE EXPIRY DATE NO LONGER VIOLATES chk_customer_dim_dates.
--     The expire step previously wrote  effective_end_date = SYSDATE - 1 .
--     Task 2(a) stamps every version-1 row with effective_start_date = SYSDATE,
--     so closing a row created earlier today set its end date to YESTERDAY -
--     before its own start date - and the CHECK constraint aborted the load
--     with ORA-02290.  This fires the first time any customer changes, which
--     is exactly what Test A in insert_dirty_data.sql does.
--     GREATEST(...) now guarantees end >= start.
--
--  2. DATES ARE TRUNCATED TO WHOLE DAYS.
--     With SYSDATE on both sides, the old version ended at (say) 11:00
--     yesterday and the new version started at 11:00 today, leaving a
--     24-hour window belonging to NEITHER version.  Any fact dated inside
--     that window resolves to no version at all.  TRUNC on the new version's
--     start date closes the gap: the old version ends the day before the new
--     one begins, with no time-of-day component to fall between them.
--
--  3. THE DRIVER PROCEDURE HAS BEEN REMOVED FROM THIS FILE.
--     run_task2b was defined both here and in run_task_2b.sql.  Whichever
--     compiled last silently won.  The driver now lives only in
--     run_task_2b.sql.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART A: Insert completely new customers
-- ----------------------------------------------------------------------------
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
            rec.membership_expiry, TRUNC(SYSDATE), DATE '9999-12-31', 'Y', 1, 2
        );
        v_new_records := v_new_records + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CUSTOMER_DIM New Records: ' || v_new_records || ' inserted.');
END;
/

-- ----------------------------------------------------------------------------
-- PART B: Maintain SCD Type 2 History for existing customers
--
--   Type 2 attributes (a change creates a new version row):
--       customer_status, member_flag, membership_type
--   These are the attributes reports SEGMENT by, so their history must be
--   preserved - otherwise a member who upgraded to VIP last month would
--   appear to have been VIP all year and every tier comparison would be wrong.
-- ----------------------------------------------------------------------------
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
        AND cd.customer_key <> -1
        AND (
            NVL(cd.customer_status, 'X') != NVL(s.customer_status, 'X') OR
            NVL(cd.member_flag, 'X') != NVL(s.member_flag, 'X') OR
            NVL(cd.membership_type, 'X') != NVL(s.membership_type, 'X')
        );
BEGIN
    FOR rec IN changed_cust_cursor LOOP
        -- Expire the old record.
        -- GREATEST guards chk_customer_dim_dates: a version created earlier
        -- today would otherwise be closed one day BEFORE it opened.
        UPDATE customer_dim
        SET effective_end_date = GREATEST(TRUNC(SYSDATE) - 1, effective_start_date), 
            is_current_flag = 'N', 
            etl_update_dt = SYSDATE
        WHERE customer_key = rec.customer_key;

        -- Insert the new version, starting at the beginning of today so that
        -- it abuts the closed version with no uncovered gap between them.
        INSERT INTO customer_dim (
            customer_key, customer_id, customer_name, customer_ic, customer_email, 
            customer_status, member_flag, membership_type, annual_fee, point_earn_rate, 
            membership_expiry, effective_start_date, effective_end_date, is_current_flag, version_no, etl_batch_id
        ) VALUES (
            seq_dw_cust.NEXTVAL, rec.customer_id, rec.customer_name, rec.customer_ic, rec.customer_email,
            rec.customer_status, rec.member_flag, rec.membership_type, rec.annual_fee, rec.point_earn_rate,
            rec.membership_expiry, TRUNC(SYSDATE), DATE '9999-12-31', 'Y', rec.old_version_no + 1, 2
        );
        v_updated_records := v_updated_records + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CUSTOMER_DIM SCD2 Maintenance: ' || v_updated_records || ' versions updated.');
END;
/

-- ----------------------------------------------------------------------------
--  NOTE: run_task2b is deliberately NOT defined here.
--        It is defined once, in run_task_2b.sql.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
--  VERIFY AFTER RUNNING (expect no rows from either query)
-- ----------------------------------------------------------------------------
--  More than one current version per customer:
--    SELECT customer_id, COUNT(*) FROM customer_dim
--    WHERE is_current_flag = 'Y' AND customer_key <> -1
--    GROUP BY customer_id HAVING COUNT(*) > 1;
--
--  A version that ends before it starts:
--    SELECT customer_id, version_no, effective_start_date, effective_end_date
--    FROM customer_dim WHERE effective_end_date < effective_start_date;
-- ----------------------------------------------------------------------------
