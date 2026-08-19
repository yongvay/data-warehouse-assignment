-- ============================================================================
--  TASK 2(b) : PROMOTION_DIM  -  incremental Type 1 load
-- ----------------------------------------------------------------------------
--  The two seeded rows are protected:
--      promo_key =  0  'No Promotion'  (promotion_id = 'NONE')
--      promo_key = -1  'Unknown'       (promotion_id = 'UNKN')
--  vw_stg_promotion already rejects any source row that tries to reuse those
--  reserved identifiers, so this procedure additionally guards on the key.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_promotion_dim_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    -- 1. UPDATE changed promotions
    UPDATE promotion_dim d
       SET (promo_name, discount_type, discount_value, promo_start_date,
            promo_end_date, promo_status, promo_duration_days,
            etl_update_dt, etl_batch_id, dq_flag) =
           (SELECT s.promo_name, s.discount_type, s.discount_value,
                   s.promo_start_date, s.promo_end_date, s.promo_status,
                   s.promo_duration_days, SYSDATE, v_batch, s.dq_flag
              FROM vw_stg_promotion s
             WHERE s.promotion_id = d.promotion_id)
     WHERE d.promo_key NOT IN (0, -1)
       AND EXISTS (SELECT 1
                     FROM vw_stg_promotion s
                    WHERE s.promotion_id = d.promotion_id
                      AND s.dq_flag     <> 'D'
                      AND (   s.promo_name          <> d.promo_name
                           OR s.discount_type       <> d.discount_type
                           OR s.discount_value      <> d.discount_value
                           OR s.promo_start_date    <> d.promo_start_date
                           OR s.promo_end_date      <> d.promo_end_date
                           OR s.promo_status        <> d.promo_status
                           OR s.promo_duration_days <> d.promo_duration_days));
    v_upd := SQL%ROWCOUNT;

    -- 2. INSERT new promotions
    INSERT INTO promotion_dim
        (promo_key, promotion_id, promo_name, discount_type, discount_value,
         promo_start_date, promo_end_date, promo_status, promo_duration_days,
         etl_batch_id, dq_flag)
    SELECT seq_dw_promo.NEXTVAL, s.promotion_id, s.promo_name, s.discount_type,
           s.discount_value, s.promo_start_date, s.promo_end_date,
           s.promo_status, s.promo_duration_days, v_batch, s.dq_flag
      FROM vw_stg_promotion s
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM promotion_dim d
                        WHERE d.promotion_id = s.promotion_id);
    v_ins := SQL%ROWCOUNT;

    -- 3. AUDIT
    FOR r IN (SELECT promotion_id, raw_start, raw_end, raw_value,
                     dq_flag, dq_note
                FROM vw_stg_promotion
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.PROMOTION', r.promotion_id, 'PROMOTION_DIM',
                           'STARTDATE/ENDDATE/DISCOUNTVALUE',
                           TO_CHAR(r.raw_start,'YYYY-MM-DD') || ' / ' ||
                           TO_CHAR(r.raw_end,  'YYYY-MM-DD') || ' / ' ||
                           TO_CHAR(r.raw_value),
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('PROMOTION_DIM', v_ins, v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('PROMOTION_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_promotion_dim_delta;
/
SHOW ERRORS
