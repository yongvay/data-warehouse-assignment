-- ============================================================================
--  TASK 2(b) : RETURN_REASON_DIM  -  incremental Type 1 load
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_return_reason_dim_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    -- 1. UPDATE changed reasons
    UPDATE return_reason_dim d
       SET (reason_name, reason_category, etl_update_dt, etl_batch_id, dq_flag) =
           (SELECT s.reason_name, s.reason_category, SYSDATE, v_batch, s.dq_flag
              FROM vw_stg_return_reason s
             WHERE s.reason_id = d.reason_id)
     WHERE d.reason_key <> -1
       AND EXISTS (SELECT 1
                     FROM vw_stg_return_reason s
                    WHERE s.reason_id = d.reason_id
                      AND s.dq_flag  <> 'D'
                      AND (   s.reason_name     <> d.reason_name
                           OR s.reason_category <> d.reason_category));
    v_upd := SQL%ROWCOUNT;

    -- 2. INSERT new reasons
    INSERT INTO return_reason_dim
        (reason_key, reason_id, reason_name, reason_category, etl_batch_id, dq_flag)
    SELECT seq_dw_reason.NEXTVAL, s.reason_id, s.reason_name,
           s.reason_category, v_batch, s.dq_flag
      FROM vw_stg_return_reason s
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM return_reason_dim d
                        WHERE d.reason_id = s.reason_id);
    v_ins := SQL%ROWCOUNT;

    -- 3. AUDIT
    FOR r IN (SELECT reason_id, raw_name, dq_flag, dq_note
                FROM vw_stg_return_reason
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.RETURNREASON', r.reason_id, 'RETURN_REASON_DIM',
                           'REASONNAME', r.raw_name,
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('RETURN_REASON_DIM', v_ins, v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('RETURN_REASON_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_return_reason_dim_delta;
/
SHOW ERRORS
