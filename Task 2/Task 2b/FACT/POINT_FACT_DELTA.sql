-- ============================================================================
--  TASK 2(b) : POINT_FACT  -  incremental load
-- ----------------------------------------------------------------------------
--  A loyalty point transaction is an immutable ledger entry: it is never
--  amended, only reversed by a further transaction.  This load is therefore
--  INSERT-ONLY, anti-joined on point_trans_id (point_fact_grain_uq).
--
--  chk_point_fact_order is the constraint that breaks naive incremental loads:
--      Earn   MUST have an OrderNo
--      Redeem MUST NOT have an OrderNo
--  vw_stg_point rejects an 'Earn' with no order and strips the order from a
--  'Redeem' that wrongly carries one, so nothing reaches the fact that could
--  violate it.  Redemptions carry branch_key = -1 (the seeded
--  'Unknown / Not Applicable' branch) because they belong to no order.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_point_fact_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    ------------------------------------------------------------------
    -- 1. Insert every clean point transaction not already in the fact
    ------------------------------------------------------------------
    INSERT INTO point_fact
        (trans_date_key, customer_key, branch_key, point_trans_id,
         order_no, trans_type, points_earned, points_redeemed, net_points,
         etl_batch_id, dq_flag)
    SELECT
        NVL(dd.date_key, -1)                                AS trans_date_key,
        NVL(NVL(cv.customer_key, cc.customer_key), -1)      AS customer_key,
        NVL(bd.branch_key, -1)                              AS branch_key,
        s.point_trans_id, s.order_no, s.trans_type,
        s.points_earned, s.points_redeemed, s.net_points,
        v_batch, s.dq_flag
      FROM vw_stg_point s
      LEFT JOIN date_dim dd ON dd.date_key = etl_scrub.to_date_key(s.trans_dt)
      LEFT JOIN customer_dim cv ON cv.customer_id = s.customer_id
                               AND s.trans_dt >= cv.effective_start_date
                               AND s.trans_dt <  cv.effective_end_date
      LEFT JOIN customer_dim cc ON cc.customer_id = s.customer_id
                               AND cc.is_current_flag = 'Y'
      LEFT JOIN branch_dim   bd ON bd.branch_id = s.branch_id
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM point_fact f
                        WHERE f.point_trans_id = s.point_trans_id);
    v_ins := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- 2. AUDIT
    ------------------------------------------------------------------
    FOR r IN (SELECT point_trans_id, raw_type, raw_point, raw_order_no,
                     dq_flag, dq_note
                FROM vw_stg_point
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.POINTTRANSACTION', r.point_trans_id, 'POINT_FACT',
                           'TRANSTYPE/POINT/ORDERNO',
                           r.raw_type || ' / ' || TO_CHAR(r.raw_point)
                                      || ' / ' || r.raw_order_no,
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('POINT_FACT', v_ins, 0, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('POINT_FACT', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_point_fact_delta;
/
SHOW ERRORS
