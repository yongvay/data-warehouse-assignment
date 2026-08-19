-- ============================================================================
--  TASK 2(b) : CUSTOMER_DIM  -  SLOWLY CHANGING DIMENSION TYPE 2
--                               incremental / subsequent load
-- ----------------------------------------------------------------------------
--  This is the procedure the Type 2 requirement is graded on.  Four things
--  happen, in this order, and the order matters:
--
--    STEP 1  TYPE 1 OVERWRITE
--            customer_name, customer_ic, customer_email, membership_expiry are
--            corrections, not business changes.  A typo fixed in the source
--            should look as if it had always been correct, so the CURRENT row
--            is overwritten and no new version is produced.
--
--    STEP 2  TYPE 2 EXPIRY
--            customer_status, member_flag and membership_type are the tracked
--            attributes.  When one of them changes, the current row is closed
--            off:  effective_end_date = SYSDATE, is_current_flag = 'N'.
--            SYSDATE (not SYSDATE - 1) is used because the initial load stamped
--            effective_start_date with SYSDATE; subtracting a day would break
--            chk_customer_dim_dates for a customer that changed on load day.
--
--    STEP 3  TYPE 2 NEW VERSION
--            A fresh row is inserted for each customer expired in step 2, with
--            version_no = previous MAX + 1 and effective_end_date = 9999-12-31.
--
--    STEP 4  BRAND NEW CUSTOMERS
--            version_no = 1.
--
--  annual_fee and point_earn_rate are deliberately NOT part of step 1: they are
--  properties of membership_type, so they must travel with the Type 2 version
--  rather than be back-written onto expired history.
--
--  The intervals produced are half-open  [effective_start_date,
--  effective_end_date)  so that a point-in-time fact lookup can never match two
--  versions of the same customer.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_customer_dim_scd2 AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_t1    NUMBER := 0;   -- Type 1 overwrites
    v_exp   NUMBER := 0;   -- rows expired
    v_ver   NUMBER := 0;   -- new versions inserted
    v_new   NUMBER := 0;   -- brand new customers
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    ------------------------------------------------------------------
    -- STEP 1 : TYPE 1 - overwrite corrections on the current row
    ------------------------------------------------------------------
    UPDATE customer_dim d
       SET (customer_name, customer_ic, customer_email, membership_expiry,
            etl_update_dt, etl_batch_id, dq_flag) =
           (SELECT s.customer_name, s.customer_ic, s.customer_email,
                   s.membership_expiry, SYSDATE, v_batch, s.dq_flag
              FROM vw_stg_customer s
             WHERE s.customer_id = d.customer_id)
     WHERE d.is_current_flag = 'Y'
       AND d.customer_key   <> -1
       AND EXISTS (SELECT 1
                     FROM vw_stg_customer s
                    WHERE s.customer_id = d.customer_id
                      AND s.dq_flag    <> 'D'
                      AND (   s.customer_name  <> d.customer_name
                           OR s.customer_ic    <> d.customer_ic
                           OR s.customer_email <> d.customer_email
                           OR NVL(s.membership_expiry, DATE '9999-12-31')
                              <> NVL(d.membership_expiry, DATE '9999-12-31')));
    v_t1 := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- STEP 2 : TYPE 2 - expire the current row when a tracked
    --                   attribute has changed
    ------------------------------------------------------------------
    UPDATE customer_dim d
       SET d.effective_end_date = GREATEST(d.effective_start_date, SYSDATE),
           d.is_current_flag    = 'N',
           d.etl_update_dt      = SYSDATE,
           d.etl_batch_id       = v_batch
     WHERE d.is_current_flag = 'Y'
       AND d.customer_key   <> -1
       AND EXISTS (SELECT 1
                     FROM vw_stg_customer s
                    WHERE s.customer_id = d.customer_id
                      AND s.dq_flag    <> 'D'
                      AND (   s.customer_status <> d.customer_status
                           OR s.member_flag     <> d.member_flag
                           OR s.membership_type <> d.membership_type));
    v_exp := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- STEP 3 : TYPE 2 - insert the new current version
    --          (identified by the rows step 2 just closed in THIS batch)
    ------------------------------------------------------------------
    INSERT INTO customer_dim
        (customer_key, customer_id, customer_name, customer_ic, customer_email,
         customer_status, member_flag, membership_type, annual_fee,
         point_earn_rate, membership_expiry, effective_start_date,
         effective_end_date, is_current_flag, version_no, etl_batch_id, dq_flag)
    SELECT seq_dw_cust.NEXTVAL,
           s.customer_id, s.customer_name, s.customer_ic, s.customer_email,
           s.customer_status, s.member_flag, s.membership_type, s.annual_fee,
           s.point_earn_rate, s.membership_expiry,
           SYSDATE,
           DATE '9999-12-31',
           'Y',
           v.next_version,
           v_batch, s.dq_flag
      FROM vw_stg_customer s
      JOIN (SELECT customer_id, MAX(version_no) + 1 AS next_version
              FROM customer_dim
             WHERE customer_key <> -1
             GROUP BY customer_id) v
        ON v.customer_id = s.customer_id
     WHERE s.dq_flag <> 'D'
       AND EXISTS (SELECT 1
                     FROM customer_dim x
                    WHERE x.customer_id     = s.customer_id
                      AND x.is_current_flag = 'N'
                      AND x.etl_batch_id    = v_batch);
    v_ver := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- STEP 4 : brand new customers  (version 1)
    ------------------------------------------------------------------
    INSERT INTO customer_dim
        (customer_key, customer_id, customer_name, customer_ic, customer_email,
         customer_status, member_flag, membership_type, annual_fee,
         point_earn_rate, membership_expiry, effective_start_date,
         effective_end_date, is_current_flag, version_no, etl_batch_id, dq_flag)
    SELECT seq_dw_cust.NEXTVAL,
           s.customer_id, s.customer_name, s.customer_ic, s.customer_email,
           s.customer_status, s.member_flag, s.membership_type, s.annual_fee,
           s.point_earn_rate, s.membership_expiry,
           SYSDATE, DATE '9999-12-31', 'Y', 1, v_batch, s.dq_flag
      FROM vw_stg_customer s
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM customer_dim d
                        WHERE d.customer_id = s.customer_id);
    v_new := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- STEP 5 : AUDIT
    ------------------------------------------------------------------
    FOR r IN (SELECT customer_id, raw_email, raw_ic, raw_status, dq_flag, dq_note
                FROM vw_stg_customer
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.CUSTOMER', r.customer_id, 'CUSTOMER_DIM',
                           'EMAIL/ICNO/STATUS',
                           r.raw_email || ' / ' || r.raw_ic || ' / ' || r.raw_status,
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('   SCD2 detail : type1_overwrites=' || v_t1 ||
                         '  versions_expired=' || v_exp ||
                         '  versions_created=' || v_ver ||
                         '  new_customers='   || v_new);

    etl_ctl.log_step('CUSTOMER_DIM', v_new + v_ver, v_t1 + v_exp, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('CUSTOMER_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_customer_dim_scd2;
/
SHOW ERRORS
