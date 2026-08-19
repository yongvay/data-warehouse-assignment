-- ============================================================================
--  TASK 2(b) : RETURN_FACT  -  incremental load
-- ----------------------------------------------------------------------------
--  A return is NOT immutable: its status walks Pending -> Approved -> Refunded
--  (or -> Rejected) over several days, and the refund amount can be revised.
--  return_date_key and reason_key both sit inside return_fact_pk, so a changed
--  return is deleted and re-inserted rather than updated in place.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_return_fact_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    ------------------------------------------------------------------
    -- 1. Remove returns whose source state has moved on
    ------------------------------------------------------------------
    DELETE FROM return_fact f
     WHERE EXISTS (SELECT 1
                     FROM vw_stg_return s
                     JOIN item_dim i ON i.item_id = s.item_id
                    WHERE s.return_id = f.return_id
                      AND s.order_no  = f.order_no
                      AND i.item_key  = f.item_key
                      AND s.dq_flag  <> 'D'
                      AND (   s.return_status     <> f.return_status
                           OR s.quantity_returned <> f.quantity_returned
                           OR s.refund_amount     <> f.refund_amount
                           OR s.days_to_return    <> f.days_to_return
                           OR etl_scrub.to_date_key(s.return_dt)
                              <> f.return_date_key));
    v_upd := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- 2. Insert every clean return line not already in the fact
    ------------------------------------------------------------------
    INSERT INTO return_fact
        (return_date_key, order_date_key, customer_key, item_key, branch_key,
         reason_key, promo_key, return_id, order_no, return_status,
         quantity_returned, refund_amount, days_to_return, etl_batch_id, dq_flag)
    SELECT
        NVL(rdt.date_key, -1)                               AS return_date_key,
        NVL(odt.date_key, -1)                               AS order_date_key,
        NVL(NVL(cv.customer_key, cc.customer_key), -1)      AS customer_key,
        NVL(id.item_key,   -1)                              AS item_key,
        NVL(bd.branch_key, -1)                              AS branch_key,
        NVL(rr.reason_key, -1)                              AS reason_key,
        NVL(pd.promo_key,   0)                              AS promo_key,
        s.return_id, s.order_no, s.return_status,
        s.quantity_returned, s.refund_amount, s.days_to_return,
        v_batch, s.dq_flag
      FROM vw_stg_return s
      LEFT JOIN date_dim rdt ON rdt.date_key = etl_scrub.to_date_key(s.return_dt)
      LEFT JOIN date_dim odt ON odt.date_key = etl_scrub.to_date_key(s.order_dt)
      LEFT JOIN customer_dim cv ON cv.customer_id = s.customer_id
                               AND s.order_dt >= cv.effective_start_date
                               AND s.order_dt <  cv.effective_end_date
      LEFT JOIN customer_dim cc ON cc.customer_id = s.customer_id
                               AND cc.is_current_flag = 'Y'
      LEFT JOIN item_dim          id ON id.item_id      = s.item_id
      LEFT JOIN branch_dim        bd ON bd.branch_id    = s.branch_id
      LEFT JOIN return_reason_dim rr ON rr.reason_id    = s.reason_id
      LEFT JOIN promotion_dim     pd ON pd.promotion_id = s.promotion_id
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1
                         FROM return_fact f
                        WHERE f.return_id = s.return_id
                          AND f.order_no  = s.order_no
                          AND f.item_key  = NVL(id.item_key, -1));
    v_ins := SQL%ROWCOUNT - v_upd;

    ------------------------------------------------------------------
    -- 3. AUDIT
    ------------------------------------------------------------------
    FOR r IN (SELECT return_id, item_id, raw_quantity, raw_refund, raw_days,
                     dq_flag, dq_note
                FROM vw_stg_return
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.RETURNDETAILS',
                           r.return_id || '/' || r.item_id, 'RETURN_FACT',
                           'QTYRETURNED/REFUND/DAYS',
                           TO_CHAR(r.raw_quantity) || ' / ' ||
                           TO_CHAR(r.raw_refund)   || ' / ' || TO_CHAR(r.raw_days),
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('RETURN_FACT', GREATEST(v_ins, 0), v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('RETURN_FACT', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_return_fact_delta;
/
SHOW ERRORS
