-- ============================================================================
--  TASK 2(b) : DELIVERY_COMPANY_DIM  -  incremental Type 1 load
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_delivery_company_dim_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    -- 1. UPDATE changed couriers
    UPDATE delivery_company_dim d
       SET (company_name, company_contact_no, etl_update_dt, etl_batch_id, dq_flag) =
           (SELECT s.company_name, s.company_contact_no, SYSDATE, v_batch, s.dq_flag
              FROM vw_stg_delivery_company s
             WHERE s.delivery_company_id = d.delivery_company_id)
     WHERE d.delivery_company_key <> -1
       AND EXISTS (SELECT 1
                     FROM vw_stg_delivery_company s
                    WHERE s.delivery_company_id = d.delivery_company_id
                      AND s.dq_flag <> 'D'
                      AND (   s.company_name       <> d.company_name
                           OR s.company_contact_no <> d.company_contact_no));
    v_upd := SQL%ROWCOUNT;

    -- 2. INSERT new couriers
    INSERT INTO delivery_company_dim
        (delivery_company_key, delivery_company_id, company_name,
         company_contact_no, etl_batch_id, dq_flag)
    SELECT seq_dw_company.NEXTVAL, s.delivery_company_id, s.company_name,
           s.company_contact_no, v_batch, s.dq_flag
      FROM vw_stg_delivery_company s
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM delivery_company_dim d
                        WHERE d.delivery_company_id = s.delivery_company_id);
    v_ins := SQL%ROWCOUNT;

    -- 3. AUDIT
    FOR r IN (SELECT delivery_company_id, raw_name, raw_contact, dq_flag, dq_note
                FROM vw_stg_delivery_company
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.DELIVERYCOMPANY', r.delivery_company_id,
                           'DELIVERY_COMPANY_DIM', 'COMPANYNAME/CONTACTNO',
                           r.raw_name || ' / ' || r.raw_contact,
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('DELIVERY_COMPANY_DIM', v_ins, v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('DELIVERY_COMPANY_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_delivery_company_dim_delta;
/
SHOW ERRORS
