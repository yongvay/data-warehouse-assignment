CREATE OR REPLACE PROCEDURE load_delivery_fact_incr (p_load_date IN DATE DEFAULT SYSDATE) AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Deliveries
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
        CASE WHEN d.Status IN ('Pending','In Transit','Delivered','Cancelled') THEN d.Status ELSE 'Pending' END, -- Scrubbing
        ABS(d.DeliveryCharge), -- Scrubbing
        ABS(o.TotalAmount), -- Scrubbing
        CASE WHEN d.DeliveryDate IS NULL THEN NULL ELSE GREATEST(TRUNC(d.DeliveryDate) - TRUNC(o.OrderDateTime), 0) END,
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
    -- Use OrderDateTime for filtering because DeliveryDate is initially NULL
    AND o.OrderDateTime >= p_load_date - 1; 

    v_count := SQL%ROWCOUNT;

    -- 2. Update Mutable Statuses
    UPDATE delivery_fact df
    SET (delivery_status, delivery_date_key, delivery_lead_days, delivery_charge, etl_update_dt) = (
        SELECT 
            CASE WHEN d.Status IN ('Pending','In Transit','Delivered','Cancelled') THEN d.Status ELSE 'Pending' END,
            NVL(TO_NUMBER(TO_CHAR(d.DeliveryDate, 'YYYYMMDD')), -1),
            CASE WHEN d.DeliveryDate IS NULL THEN NULL ELSE GREATEST(TRUNC(d.DeliveryDate) - TRUNC(o.OrderDateTime), 0) END,
            ABS(d.DeliveryCharge),
            SYSDATE
        FROM adm.Delivery d
        JOIN adm.Orders o ON d.OrderNo = o.OrderNo
        WHERE df.delivery_id = d.DeliveryID
    )
    WHERE EXISTS (
        SELECT 1 FROM adm.Delivery d
        WHERE df.delivery_id = d.DeliveryID
        AND (df.delivery_status != CASE WHEN d.Status IN ('Pending','In Transit','Delivered','Cancelled') THEN d.Status ELSE 'Pending' END
             OR df.delivery_date_key != NVL(TO_NUMBER(TO_CHAR(d.DeliveryDate, 'YYYYMMDD')), -1)
             OR df.delivery_charge != ABS(d.DeliveryCharge))
    );

    v_updated := SQL%ROWCOUNT;
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('DELIVERY_FACT incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error in DELIVERY_FACT incremental load: ' || SQLERRM);
        RAISE;
END;
/