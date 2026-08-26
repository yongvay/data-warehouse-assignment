-- ============================================================================
--  SALES FACT INCREMENTAL
-- ----------------------------------------------------------------------------
--  CORRECTIONS APPLIED TO THIS FILE
--
--  1. REMOVED the three trailing procedures that used to follow this one.
--     This file previously also contained copies of load_return_fact_incr,
--     load_delivery_fact_incr and load_point_fact_incr.  Because the compile
--     order in run_task_2b.sql loads DELIVERY, POINT and RETURN before SALES,
--     those copies silently replaced the proper versions - discarding the
--     mutable-status UPDATE branches and the exception handlers.  Nothing
--     errored, so the loss was invisible.  Each fact now lives in exactly one
--     file.
--
--  2. NVL(id.item_key, -1) in the NOT EXISTS guard.
--     id.item_key arrives from a LEFT JOIN, so it is NULL when the item is
--     absent from ITEM_DIM.  "sf.item_key = NULL" evaluates to UNKNOWN rather
--     than TRUE, so the guard never matched and the row was re-inserted on
--     every run.  Comparing against the seeded -1 key matches what is
--     actually written to the fact.
-- ============================================================================

CREATE OR REPLACE PROCEDURE load_sales_fact_incr (p_load_date IN DATE DEFAULT SYSDATE) AS
    v_count NUMBER := 0;
BEGIN
    INSERT INTO sales_fact (
        order_date_key, customer_key, item_key, branch_key, promo_key, 
        order_no, order_type, order_hour, quantity, unit_price, 
        gross_sales_amt, discount_amt, net_sales_amt, etl_batch_id
    )
    SELECT 
        NVL(TO_NUMBER(TO_CHAR(o.OrderDateTime, 'YYYYMMDD')), -1) AS order_date_key,
        NVL(cd.customer_key, -1) AS customer_key,
        NVL(id.item_key, -1) AS item_key,
        NVL(bd.branch_key, -1) AS branch_key,
        CASE
            WHEN active_promo.PromotionID IS NULL THEN 0
            WHEN pd.promo_key IS NULL THEN -1
            ELSE pd.promo_key
        END AS promo_key,
        o.OrderNo,
        CASE WHEN o.OrderType IN ('Online', 'Walk-in') THEN o.OrderType ELSE 'Walk-in' END AS order_type, -- Data Scrubbing
        NVL(TO_NUMBER(TO_CHAR(o.OrderDateTime, 'HH24')), 0) AS order_hour,
        ABS(od.Quantity) AS quantity, -- Data Scrubbing
        ABS(od.UnitPrice) AS unit_price, -- Data Scrubbing
        (ABS(od.Quantity) * ABS(od.UnitPrice)) AS gross_sales_amt,
        CASE 
            WHEN active_promo.PromotionID IS NOT NULL 
            THEN GREATEST((ABS(od.UnitPrice) - active_promo.PromoPrice), 0) * ABS(od.Quantity)
            ELSE 0 
        END AS discount_amt,
        ((ABS(od.Quantity) * ABS(od.UnitPrice)) - 
         CASE 
            WHEN active_promo.PromotionID IS NOT NULL 
            THEN GREATEST((ABS(od.UnitPrice) - active_promo.PromoPrice), 0) * ABS(od.Quantity)
            ELSE 0 
         END) AS net_sales_amt,
        2 AS etl_batch_id
    FROM adm.OrderDetails od
    JOIN adm.Orders o ON od.OrderNo = o.OrderNo
    LEFT JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND TRUNC(o.OrderDateTime) BETWEEN TRUNC(cd.effective_start_date) AND TRUNC(cd.effective_end_date)
    LEFT JOIN item_dim id ON od.ItemID = id.item_id
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id
    LEFT JOIN (
        SELECT OrderNo, ItemID, PromoPrice, PromotionID FROM (
            SELECT o.OrderNo, od.ItemID, ip.PromoPrice, p.PromotionID,
            ROW_NUMBER() OVER (PARTITION BY o.OrderNo, od.ItemID ORDER BY ip.PromoPrice ASC, p.PromotionID ASC) as rn
            FROM adm.Orders o
            JOIN adm.OrderDetails od ON o.OrderNo = od.OrderNo
            JOIN adm.ItemPromotion ip ON od.ItemID = ip.ItemID
            JOIN adm.Promotion p ON ip.PromotionID = p.PromotionID
            WHERE o.OrderDateTime BETWEEN p.StartDate AND p.EndDate
        ) WHERE rn = 1
    ) active_promo ON od.OrderNo = active_promo.OrderNo AND od.ItemID = active_promo.ItemID
    LEFT JOIN promotion_dim pd ON active_promo.PromotionID = pd.promotion_id
    
    -- Filter out records that already exist in the warehouse
    -- NVL is required: id.item_key is NULL for an unresolved item, and a
    -- comparison against NULL never matches, which caused re-insertion.
    WHERE NOT EXISTS (
        SELECT 1 FROM sales_fact sf 
        WHERE sf.order_no = o.OrderNo AND sf.item_key = NVL(id.item_key, -1)
    )
    -- Filter for recent data (Lookback window to catch late entries)
    AND o.OrderDateTime >= p_load_date - 1;

    v_count := SQL%ROWCOUNT;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('SALES_FACT incremental load: ' || v_count || ' inserted.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error in SALES_FACT incremental load: ' || SQLERRM);
        RAISE;
END;
/
