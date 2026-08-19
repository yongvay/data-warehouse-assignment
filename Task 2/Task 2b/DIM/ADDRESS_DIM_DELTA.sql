-- ============================================================================
--  TASK 2(b) : ADDRESS_DIM  -  incremental Type 1 load
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_address_dim_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    -- 1. UPDATE changed addresses
    UPDATE address_dim d
       SET (address_line, address_state, address_postcode, address_region,
            etl_update_dt, etl_batch_id, dq_flag) =
           (SELECT s.address_line, s.address_state, s.address_postcode,
                   s.address_region, SYSDATE, v_batch, s.dq_flag
              FROM vw_stg_address s
             WHERE s.address_id = d.address_id)
     WHERE d.address_key <> -1
       AND EXISTS (SELECT 1
                     FROM vw_stg_address s
                    WHERE s.address_id = d.address_id
                      AND s.dq_flag   <> 'D'
                      AND (   s.address_line     <> d.address_line
                           OR s.address_state    <> d.address_state
                           OR s.address_postcode <> d.address_postcode
                           OR s.address_region   <> d.address_region));
    v_upd := SQL%ROWCOUNT;

    -- 2. INSERT new addresses
    INSERT INTO address_dim
        (address_key, address_id, address_line, address_state,
         address_postcode, address_region, etl_batch_id, dq_flag)
    SELECT seq_dw_address.NEXTVAL, s.address_id, s.address_line, s.address_state,
           s.address_postcode, s.address_region, v_batch, s.dq_flag
      FROM vw_stg_address s
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM address_dim d
                        WHERE d.address_id = s.address_id);
    v_ins := SQL%ROWCOUNT;

    -- 3. AUDIT
    FOR r IN (SELECT address_id, raw_state, raw_postcode, dq_flag, dq_note
                FROM vw_stg_address
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.MEMBERADDRESS', r.address_id, 'ADDRESS_DIM',
                           'ADDRESS_STATE/POSTCODE',
                           r.raw_state || ' / ' || r.raw_postcode,
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('ADDRESS_DIM', v_ins, v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('ADDRESS_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_address_dim_delta;
/
SHOW ERRORS
