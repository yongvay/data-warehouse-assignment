CREATE OR REPLACE VIEW vw_load_sales_fact AS
SELECT 
    TO_NUMBER(TO_CHAR(o.OrderDateTime, 'YYYYMMDD')) AS order_date_key,
    cd.customer_key,
    id.item_key,
    bd.branch_key,
    NVL(pd.promo_key, 0) AS promo_key, 
    o.OrderNo AS order_no,
    o.OrderType AS order_type,
    TO_NUMBER(TO_CHAR(o.OrderDateTime, 'HH24')) AS order_hour,
    od.Quantity AS quantity,
    od.UnitPrice AS unit_price,
    (od.Quantity * od.UnitPrice) AS gross_sales_amt,
    CASE 
        WHEN active_promo.PromotionID IS NOT NULL 
        THEN (od.UnitPrice - active_promo.PromoPrice) * od.Quantity 
        ELSE 0 
    END AS discount_amt,
    ((od.Quantity * od.UnitPrice) - 
     CASE 
        WHEN active_promo.PromotionID IS NOT NULL 
        THEN (od.UnitPrice - active_promo.PromoPrice) * od.Quantity 
        ELSE 0 
     END) AS net_sales_amt
FROM adm.OrderDetails od
JOIN adm.Orders o ON od.OrderNo = o.OrderNo
JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND cd.is_current_flag = 'Y'
JOIN item_dim id ON od.ItemID = id.item_id
JOIN branch_dim bd ON o.BranchID = bd.branch_id
LEFT JOIN (
    SELECT OrderNo, ItemID, PromoPrice, PromotionID
    FROM (
        SELECT 
            o.OrderNo, od.ItemID, ip.PromoPrice, p.PromotionID,
            ROW_NUMBER() OVER (PARTITION BY o.OrderNo, od.ItemID ORDER BY ip.PromoPrice ASC, p.PromotionID ASC) as rn
        FROM adm.Orders o
        JOIN adm.OrderDetails od ON o.OrderNo = od.OrderNo
        JOIN adm.ItemPromotion ip ON od.ItemID = ip.ItemID
        JOIN adm.Promotion p ON ip.PromotionID = p.PromotionID
        WHERE o.OrderDateTime BETWEEN p.StartDate AND p.EndDate
    )
    WHERE rn = 1
) active_promo ON od.OrderNo = active_promo.OrderNo AND od.ItemID = active_promo.ItemID
LEFT JOIN promotion_dim pd ON active_promo.PromotionID = pd.promotion_id;

CREATE OR REPLACE PROCEDURE load_sales_fact AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO sales_fact (
        order_date_key, customer_key, item_key, branch_key, promo_key, 
        order_no, order_type, order_hour, quantity, unit_price, 
        gross_sales_amt, discount_amt, net_sales_amt, etl_batch_id
    )
    SELECT 
        v.order_date_key,
        v.customer_key,
        v.item_key,
        v.branch_key,
        v.promo_key,
        v.order_no,
        v.order_type,
        v.order_hour,
        v.quantity,
        v.unit_price,
        v.gross_sales_amt,
        v.discount_amt,
        v.net_sales_amt,
        v_batch_id
    FROM vw_load_sales_fact v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('SALES_FACT loaded.');
END;
/
