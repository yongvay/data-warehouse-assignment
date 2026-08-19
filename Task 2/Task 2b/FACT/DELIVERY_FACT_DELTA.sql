-- ============================================================================
--  TASK 2(b) : DELIVERY_FACT  -  incremental load
-- ----------------------------------------------------------------------------
--  THIS IS THE MOST IMPORTANT INCREMENTAL CASE IN THE WAREHOUSE.
--  Task 2(a) loaded pending deliveries with delivery_date_key = -1 because
--  Delivery.DeliveryDate is NULL until despatch completes.  On every subsequent
--  run those same rows must be REVISITED, not re-inserted: the courier has
--  since delivered them, so the status moves Pending -> In Transit -> Delivered
--  and the date key changes from -1 to a real YYYYMMDD value.
--
--  delivery_date_key is part of delivery_fact_pk, so the transition is
--  implemented as DELETE + re-INSERT inside one transaction.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_delivery_fact_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    ------------------------------------------------------------------
    -- 1. Remove deliveries whose status or despatch date has moved on
    ------------------------------------------------------------------
    DELETE FROM delivery_fact f
     WHERE EXISTS (SELECT 1
                     FROM vw_stg_delivery s
                    WHERE s.delivery_id = f.delivery_id
                      AND s.dq_flag    <> 'D'
                      AND (   s.delivery_status  <> f.delivery_status
                           OR s.delivery_charge  <> f.delivery_charge
                           OR s.order_total_amount <> f.order_total_amount
                           OR NVL(s.delivery_lead_days, -999)
                              <> NVL(f.delivery_lead_days, -999)
                           OR etl_scrub.to_date_key(s.delivery_dt)
                              <> f.delivery_date_key));
    v_upd := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- 2. Insert every clean delivery not already in the fact
    ------------------------------------------------------------------
    INSERT INTO delivery_fact
        (delivery_date_key, order_date_key, customer_key, branch_key,
         delivery_company_key, address_key, delivery_id, order_no,
         delivery_status, delivery_charge, order_total_amount,
         delivery_lead_days, etl_batch_id, dq_flag)
    SELECT
        NVL(ddt.date_key, -1)                               AS delivery_date_key,
        NVL(odt.date_key, -1)                               AS order_date_key,
        NVL(NVL(cv.customer_key, cc.customer_key), -1)      AS customer_key,
        NVL(bd.branch_key, -1)                              AS branch_key,
        NVL(dc.delivery_company_key, -1)                    AS delivery_company_key,
        NVL(ad.address_key, -1)                             AS address_key,
        s.delivery_id, s.order_no, s.delivery_status,
        s.delivery_charge, s.order_total_amount, s.delivery_lead_days,
        v_batch, s.dq_flag
      FROM vw_stg_delivery s
      LEFT JOIN date_dim ddt ON ddt.date_key = etl_scrub.to_date_key(s.delivery_dt)
      LEFT JOIN date_dim odt ON odt.date_key = etl_scrub.to_date_key(s.order_dt)
      LEFT JOIN customer_dim cv ON cv.customer_id = s.customer_id
                               AND s.order_dt >= cv.effective_start_date
                               AND s.order_dt <  cv.effective_end_date
      LEFT JOIN customer_dim cc ON cc.customer_id = s.customer_id
                               AND cc.is_current_flag = 'Y'
      LEFT JOIN branch_dim           bd ON bd.branch_id = s.branch_id
      LEFT JOIN delivery_company_dim dc ON dc.delivery_company_id = s.delivery_company_id
      LEFT JOIN address_dim          ad ON ad.address_id = s.address_id
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM delivery_fact f
                        WHERE f.delivery_id = s.delivery_id);
    v_ins := SQL%ROWCOUNT - v_upd;

    ------------------------------------------------------------------
    -- 3. AUDIT
    ------------------------------------------------------------------
    FOR r IN (SELECT delivery_id, raw_status, raw_charge, raw_lead,
                     dq_flag, dq_note
                FROM vw_stg_delivery
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.DELIVERY', r.delivery_id, 'DELIVERY_FACT',
                           'STATUS/CHARGE/LEADDAYS',
                           r.raw_status || ' / ' || TO_CHAR(r.raw_charge)
                                        || ' / ' || TO_CHAR(r.raw_lead),
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('DELIVERY_FACT', GREATEST(v_ins, 0), v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('DELIVERY_FACT', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_delivery_fact_delta;
/
SHOW ERRORS
