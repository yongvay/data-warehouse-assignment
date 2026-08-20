-- SALES FACT INCREMENTAL
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
        NVL(pd.promo_key, 0) AS promo_key, 
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
    LEFT JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND cd.is_current_flag = 'Y'
    LEFT JOIN item_dim id ON od.ItemID = id.item_id
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id
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
    ) active_promo ON od.OrderNo = active_promo.OrderNo AND od.ItemID = active_promo.ItemID
    LEFT JOIN promotion_dim pd ON active_promo.PromotionID = pd.promotion_id
    
    -- Filter out records that already exist in the warehouse
    WHERE NOT EXISTS (
        SELECT 1 FROM sales_fact sf 
        WHERE sf.order_no = o.OrderNo AND sf.item_key = id.item_key
    )
    -- Filter for recent data (Lookback window of 1 day to catch late entries)
    AND o.OrderDateTime >= p_load_date - 1;

    v_count := SQL%ROWCOUNT;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('SALES_FACT incremental load: ' || v_count || ' inserted.');
END;
/

-- RETURN FACT INCREMENTAL
CREATE OR REPLACE PROCEDURE load_return_fact_incr (p_load_date IN DATE DEFAULT SYSDATE) AS
    v_count NUMBER := 0;
BEGIN
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
        CASE WHEN r.Status IN ('Pending','Approved','Rejected','Refunded') THEN r.Status ELSE 'Pending' END, -- Data Scrubbing
        ABS(rd.QuantityReturned), -- Data Scrubbing
        ABS(rd.RefundAmount), -- Data Scrubbing
        GREATEST(TRUNC(r.ReturnDate) - TRUNC(o.OrderDateTime), 0),
        2
    FROM adm.ReturnDetails rd
    JOIN adm.Returns r ON rd.ReturnID = r.ReturnID
    JOIN adm.Orders o ON r.OrderNo = o.OrderNo
    LEFT JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND cd.is_current_flag = 'Y'
    LEFT JOIN item_dim id ON rd.ItemID = id.item_id
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id
    LEFT JOIN return_reason_dim rrd ON rd.ReasonID = rrd.reason_id
    LEFT JOIN promotion_dim pd ON pd.promotion_id = 'NONE' -- Simplified promo logic for returns
    WHERE NOT EXISTS (
        SELECT 1 FROM return_fact rf 
        WHERE rf.return_id = r.ReturnID AND rf.item_key = id.item_key
    )
    AND r.ReturnDate >= p_load_date - 1;

    v_count := SQL%ROWCOUNT;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('RETURN_FACT incremental load: ' || v_count || ' inserted.');
END;
/

-- DELIVERY FACT INCREMENTAL
CREATE OR REPLACE PROCEDURE load_delivery_fact_incr (p_load_date IN DATE DEFAULT SYSDATE) AS
    v_count NUMBER := 0;
BEGIN
    INSERT INTO delivery_fact (
        delivery_date_key, order_date_key, customer_key, branch_key, 
        delivery_company_key, address_key, delivery_id, order_no, 
        delivery_status, delivery_charge, order_total_amount, delivery_lead_days, etl_batch_id
    )
    SELECT 
        NVL(TO_NUMBER(TO_CHAR(d.DeliveryDate, 'YYYYMMDD')), -1) AS delivery_date_key,
        NVL(TO_NUMBER(TO_CHAR(o.OrderDateTime, 'YYYYMMDD')), -1) AS order_date_key,
        NVL(cd.customer_key, -1),
        NVL(bd.branch_key, -1),
        NVL(dcd.delivery_company_key, -1),
        NVL(ad.address_key, -1),
        d.DeliveryID,
        o.OrderNo,
        CASE WHEN d.Status IN ('Pending','In Transit','Delivered','Cancelled') THEN d.Status ELSE 'Pending' END, -- Data Scrubbing
        ABS(d.DeliveryCharge), -- Data Scrubbing
        ABS(o.TotalAmount), -- Data Scrubbing
        GREATEST(TRUNC(d.DeliveryDate) - TRUNC(o.OrderDateTime), 0),
        2
    FROM adm.Delivery d
    JOIN adm.Orders o ON d.OrderNo = o.OrderNo
    LEFT JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND cd.is_current_flag = 'Y'
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id
    LEFT JOIN delivery_company_dim dcd ON d.DeliveryCompanyID = dcd.delivery_company_id
    LEFT JOIN address_dim ad ON d.AddressID = ad.address_id
    WHERE NOT EXISTS (
        SELECT 1 FROM delivery_fact df WHERE df.delivery_id = d.DeliveryID
    )
    AND d.DeliveryDate >= p_load_date - 1;

    v_count := SQL%ROWCOUNT;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DELIVERY_FACT incremental load: ' || v_count || ' inserted.');
END;
/

-- POINT FACT INCREMENTAL
CREATE OR REPLACE PROCEDURE load_point_fact_incr (p_load_date IN DATE DEFAULT SYSDATE) AS
    v_count NUMBER := 0;
BEGIN
    INSERT INTO point_fact (
        trans_date_key, customer_key, branch_key, point_trans_id, 
        order_no, trans_type, points_earned, points_redeemed, net_points, etl_batch_id
    )
    SELECT 
        NVL(TO_NUMBER(TO_CHAR(pt.TransDate, 'YYYYMMDD')), -1) AS trans_date_key,
        NVL(cd.customer_key, -1),
        NVL(bd.branch_key, -1),
        pt.PointTransID,
        CASE WHEN pt.TransType = 'Redeem' THEN NULL ELSE pt.OrderNo END AS order_no, -- Data Scrubbing
        CASE WHEN pt.TransType IN ('Earn','Redeem') THEN pt.TransType ELSE 'Earn' END AS trans_type, -- Data Scrubbing
        CASE WHEN pt.TransType = 'Earn' THEN ABS(pt.Point) ELSE 0 END AS points_earned,
        CASE WHEN pt.TransType = 'Redeem' THEN ABS(pt.Point) ELSE 0 END AS points_redeemed,
        CASE WHEN pt.TransType = 'Earn' THEN ABS(pt.Point) ELSE -ABS(pt.Point) END AS net_points,
        2
    FROM adm.PointTransaction pt
    LEFT JOIN customer_dim cd ON pt.MemberID = cd.customer_id AND cd.is_current_flag = 'Y'
    LEFT JOIN adm.Orders o ON pt.OrderNo = o.OrderNo
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id
    WHERE NOT EXISTS (
        SELECT 1 FROM point_fact pf WHERE pf.point_trans_id = pt.PointTransID
    )
    AND pt.TransDate >= p_load_date - 1;

    v_count := SQL%ROWCOUNT;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('POINT_FACT incremental load: ' || v_count || ' inserted.');
END;
/