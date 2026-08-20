CREATE OR REPLACE VIEW vw_load_return_fact AS
SELECT 
    TO_NUMBER(TO_CHAR(r.ReturnDate, 'YYYYMMDD')) AS return_date_key,
    TO_NUMBER(TO_CHAR(o.OrderDateTime, 'YYYYMMDD')) AS order_date_key,
    cd.customer_key,
    id.item_key,
    bd.branch_key,
    rrd.reason_key,
    NVL(pd.promo_key, 0) AS promo_key,
    r.ReturnID AS return_id,
    o.OrderNo AS order_no,
    r.Status AS return_status,
    rd.QuantityReturned AS quantity_returned,
    rd.RefundAmount AS refund_amount,
    TRUNC(r.ReturnDate) - TRUNC(o.OrderDateTime) AS days_to_return
FROM adm.ReturnDetails rd
JOIN adm.Returns r ON rd.ReturnID = r.ReturnID
JOIN adm.Orders o ON r.OrderNo = o.OrderNo
JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND cd.is_current_flag = 'Y'
JOIN item_dim id ON rd.ItemID = id.item_id
JOIN branch_dim bd ON o.BranchID = bd.branch_id
JOIN return_reason_dim rrd ON rd.ReasonID = rrd.reason_id
LEFT JOIN (
    SELECT OrderNo, ItemID, PromoPrice, PromotionID
    FROM (
        SELECT 
            o.OrderNo, od.ItemID, ip.PromoPrice, p.PromotionID,
            ROW_NUMBER() OVER (PARTITION BY o.OrderNo, od.ItemID ORDER BY ip.PromoPrice ASC) as rn
        FROM adm.Orders o
        JOIN adm.OrderDetails od ON o.OrderNo = od.OrderNo
        JOIN adm.ItemPromotion ip ON od.ItemID = ip.ItemID
        JOIN adm.Promotion p ON ip.PromotionID = p.PromotionID
        WHERE o.OrderDateTime BETWEEN p.StartDate AND p.EndDate
    )
    WHERE rn = 1
) active_promo ON o.OrderNo = active_promo.OrderNo AND rd.ItemID = active_promo.ItemID
LEFT JOIN promotion_dim pd ON active_promo.PromotionID = pd.promotion_id;

CREATE OR REPLACE PROCEDURE load_return_fact AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO return_fact (
        return_date_key, order_date_key, customer_key, item_key, branch_key, 
        reason_key, promo_key, return_id, order_no, return_status, 
        quantity_returned, refund_amount, days_to_return, etl_batch_id
    )
    SELECT 
        v.return_date_key,
        v.order_date_key,
        v.customer_key,
        v.item_key,
        v.branch_key,
        v.reason_key,
        v.promo_key,
        v.return_id,
        v.order_no,
        v.return_status,
        v.quantity_returned,
        v.refund_amount,
        v.days_to_return,
        v_batch_id
    FROM vw_load_return_fact v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('RETURN_FACT loaded.');
END;
/