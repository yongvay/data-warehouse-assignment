-- ============================================================================
--  RETURN FACT INCREMENTAL
-- ----------------------------------------------------------------------------
--  CORRECTIONS APPLIED TO THIS FILE
--
--  1. NVL(id.item_key, -1) in the NOT EXISTS guard and in the UPDATE match.
--     id.item_key is NULL when the item is absent from ITEM_DIM, and a
--     comparison against NULL is UNKNOWN rather than TRUE - so the guard
--     never matched and the row was re-inserted on every run.
--
--  2. THE REAL PROMOTION LOOKUP IS RESTORED.
--     The previous version wrote  LEFT JOIN promotion_dim pd ON
--     pd.promotion_id = 'NONE' , which pins promo_key to 0 on every return
--     regardless of whether the item was actually bought on promotion.  That
--     makes "promotion performance net of returns" impossible to report,
--     which is a real analytical loss in Task 3.  The subquery below is the
--     same one used by SALES_FACT, so a promotion's sales and its returns
--     attribute to the same promotion.
--
--  3. THE MUTABLE-STATUS UPDATE IS PRESERVED.
--     Returns.Status moves Pending -> Approved -> Refunded over several days.
--     Without the UPDATE branch a return loaded once as Pending stays Pending
--     for ever.  (A weaker copy of this procedure without the UPDATE used to
--     live at the bottom of SALES_FACT_INCREMENTAL.sql and silently replaced
--     this one; that copy has been deleted.)
-- ============================================================================

CREATE OR REPLACE PROCEDURE load_return_fact_incr (p_load_date IN DATE DEFAULT SYSDATE) AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Returns
    INSERT INTO return_fact (
        return_date_key, order_date_key, customer_key, item_key, branch_key, 
        reason_key, promo_key, return_id, order_no, return_status, 
        quantity_returned, refund_amount, days_to_return, etl_batch_id
    )
    SELECT 
        NVL(TO_NUMBER(TO_CHAR(r.ReturnDate, 'YYYYMMDD')), -1) AS return_date_key,
        NVL(TO_NUMBER(TO_CHAR(o.OrderDateTime, 'YYYYMMDD')), -1) AS order_date_key,
        NVL(cd.customer_key, -1),
        NVL(id.item_key, -1),
        NVL(bd.branch_key, -1),
        NVL(rrd.reason_key, -1),
        NVL(pd.promo_key, 0),
        r.ReturnID,
        o.OrderNo,
        CASE WHEN r.Status IN ('Pending','Approved','Rejected','Refunded') THEN r.Status ELSE 'Pending' END, -- Scrubbing: Domain validation
        ABS(rd.QuantityReturned), -- Scrubbing: Prevent negative returns
        ABS(rd.RefundAmount), -- Scrubbing: Prevent negative refunds
        GREATEST(TRUNC(r.ReturnDate) - TRUNC(o.OrderDateTime), 0), -- Scrubbing: chk_return_fact_days requires >= 0
        2
    FROM adm.ReturnDetails rd
    JOIN adm.Returns r ON rd.ReturnID = r.ReturnID
    JOIN adm.Orders o ON r.OrderNo = o.OrderNo
    LEFT JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND cd.is_current_flag = 'Y'
    LEFT JOIN item_dim id ON rd.ItemID = id.item_id
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id
    LEFT JOIN return_reason_dim rrd ON rd.ReasonID = rrd.reason_id

    -- Same active-promotion logic as SALES_FACT, so that a promotion's sales
    -- and its returns are attributed to the same promotion.
    LEFT JOIN (
        SELECT OrderNo, ItemID, PromoPrice, PromotionID FROM (
            SELECT o.OrderNo, od.ItemID, ip.PromoPrice, p.PromotionID,
            ROW_NUMBER() OVER (PARTITION BY o.OrderNo, od.ItemID ORDER BY ip.PromoPrice ASC) as rn
            FROM adm.Orders o
            JOIN adm.OrderDetails od ON o.OrderNo = od.OrderNo
            JOIN adm.ItemPromotion ip ON od.ItemID = ip.ItemID
            JOIN adm.Promotion p ON ip.PromotionID = p.PromotionID
            WHERE o.OrderDateTime BETWEEN p.StartDate AND p.EndDate
        ) WHERE rn = 1
    ) active_promo ON active_promo.OrderNo = r.OrderNo AND active_promo.ItemID = rd.ItemID
    LEFT JOIN promotion_dim pd ON active_promo.PromotionID = pd.promotion_id

    WHERE NOT EXISTS (
        SELECT 1 FROM return_fact rf 
        WHERE rf.return_id = r.ReturnID AND rf.item_key = NVL(id.item_key, -1)
    )
    AND r.ReturnDate >= p_load_date - 1;

    v_count := SQL%ROWCOUNT;

    -- 2. Update Mutable Statuses
    UPDATE return_fact rf
    SET (return_status, quantity_returned, refund_amount, etl_update_dt) = (
        SELECT 
            CASE WHEN r.Status IN ('Pending','Approved','Rejected','Refunded') THEN r.Status ELSE 'Pending' END,
            ABS(rd.QuantityReturned),
            ABS(rd.RefundAmount),
            SYSDATE
        FROM adm.ReturnDetails rd
        JOIN adm.Returns r ON rd.ReturnID = r.ReturnID
        WHERE rf.return_id = r.ReturnID 
          AND rf.item_key = NVL((SELECT i.item_key FROM item_dim i WHERE i.item_id = rd.ItemID), -1)
    )
    WHERE EXISTS (
        SELECT 1 FROM adm.ReturnDetails rd
        JOIN adm.Returns r ON rd.ReturnID = r.ReturnID
        WHERE rf.return_id = r.ReturnID 
          AND rf.item_key = NVL((SELECT i.item_key FROM item_dim i WHERE i.item_id = rd.ItemID), -1)
        AND (rf.return_status != CASE WHEN r.Status IN ('Pending','Approved','Rejected','Refunded') THEN r.Status ELSE 'Pending' END
             OR rf.quantity_returned != ABS(rd.QuantityReturned)
             OR rf.refund_amount != ABS(rd.RefundAmount))
    );
    
    v_updated := SQL%ROWCOUNT;
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('RETURN_FACT incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error in RETURN_FACT incremental load: ' || SQLERRM);
        RAISE;
END;
/
