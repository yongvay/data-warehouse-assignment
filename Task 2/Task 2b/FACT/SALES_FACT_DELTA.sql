-- ============================================================================
--  TASK 2(b) : SALES_FACT  -  incremental load
-- ----------------------------------------------------------------------------
--  DELTA STRATEGY
--    The delta predicate is an ANTI-JOIN on the declared grain
--    (order_no, item_key = sales_fact_grain_uq), not a date high-water mark.
--    A high-water mark on OrderDateTime would silently miss a back-dated order
--    inserted into the operational system after the previous run; the anti-join
--    cannot.  The high-water mark is still recorded in ETL_BATCH_CONTROL, but
--    only as audit metadata.
--
--  CHANGED ROWS
--    order_date_key, customer_key, item_key, branch_key and promo_key are all
--    part of sales_fact_pk, so a restated order line cannot simply be UPDATEd.
--    Changed lines are therefore DELETEd and re-inserted inside the same
--    transaction, which is atomic and keeps the primary key intact.
--
--  LATE-ARRIVING DIMENSIONS
--    Every dimension lookup is a LEFT JOIN wrapped in NVL(..., -1) - or
--    NVL(..., 0) for promo_key, whose 'No Promotion' seed is key 0.  A sale is
--    never dropped because its dimension row has not arrived yet.
--
--  TYPE 2 CUSTOMER RESOLUTION
--    cv = the customer version that was effective ON the order date
--         (half-open interval, so exactly one version can match)
--    cc = the current version, used as a fallback for orders that pre-date the
--         first version row created by the initial load.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_sales_fact_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    ------------------------------------------------------------------
    -- 1. Remove restated order lines so they can be re-inserted
    ------------------------------------------------------------------
    DELETE FROM sales_fact f
     WHERE EXISTS (SELECT 1
                     FROM vw_stg_sales s
                     JOIN item_dim i ON i.item_id = s.item_id
                    WHERE s.order_no = f.order_no
                      AND i.item_key = f.item_key
                      AND s.dq_flag <> 'D'
                      AND (   s.quantity        <> f.quantity
                           OR s.unit_price      <> f.unit_price
                           OR s.gross_sales_amt <> f.gross_sales_amt
                           OR s.discount_amt    <> f.discount_amt
                           OR s.net_sales_amt   <> f.net_sales_amt
                           OR s.order_type      <> f.order_type
                           OR s.order_hour      <> f.order_hour));
    v_upd := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- 2. Insert every clean order line not already in the fact
    ------------------------------------------------------------------
    INSERT INTO sales_fact
        (order_date_key, customer_key, item_key, branch_key, promo_key,
         order_no, order_type, order_hour, quantity, unit_price,
         gross_sales_amt, discount_amt, net_sales_amt, etl_batch_id, dq_flag)
    SELECT
        NVL(dd.date_key, -1)                                AS order_date_key,
        NVL(NVL(cv.customer_key, cc.customer_key), -1)      AS customer_key,
        NVL(id.item_key,   -1)                              AS item_key,
        NVL(bd.branch_key, -1)                              AS branch_key,
        NVL(pd.promo_key,   0)                              AS promo_key,
        s.order_no, s.order_type, s.order_hour,
        s.quantity, s.unit_price,
        s.gross_sales_amt, s.discount_amt, s.net_sales_amt,
        v_batch, s.dq_flag
      FROM vw_stg_sales s
      LEFT JOIN date_dim      dd ON dd.date_key = etl_scrub.to_date_key(s.order_dt)
      LEFT JOIN customer_dim  cv ON cv.customer_id = s.customer_id
                                AND s.order_dt >= cv.effective_start_date
                                AND s.order_dt <  cv.effective_end_date
      LEFT JOIN customer_dim  cc ON cc.customer_id = s.customer_id
                                AND cc.is_current_flag = 'Y'
      LEFT JOIN item_dim      id ON id.item_id   = s.item_id
      LEFT JOIN branch_dim    bd ON bd.branch_id = s.branch_id
      LEFT JOIN promotion_dim pd ON pd.promotion_id = s.promotion_id
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1
                         FROM sales_fact f
                        WHERE f.order_no = s.order_no
                          AND f.item_key = NVL(id.item_key, -1));
    v_ins := SQL%ROWCOUNT - v_upd;   -- re-inserted rows count as updates

    ------------------------------------------------------------------
    -- 3. AUDIT
    ------------------------------------------------------------------
    FOR r IN (SELECT order_no, item_id, raw_quantity, raw_unit_price,
                     dq_flag, dq_note
                FROM vw_stg_sales
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.ORDERDETAILS',
                           r.order_no || '/' || r.item_id, 'SALES_FACT',
                           'QUANTITY/UNITPRICE',
                           TO_CHAR(r.raw_quantity) || ' / ' || TO_CHAR(r.raw_unit_price),
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('SALES_FACT', GREATEST(v_ins, 0), v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('SALES_FACT', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_sales_fact_delta;
/
SHOW ERRORS
