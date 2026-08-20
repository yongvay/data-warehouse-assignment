CREATE OR REPLACE VIEW vw_load_delivery_fact AS
SELECT 
    NVL(TO_NUMBER(TO_CHAR(d.DeliveryDate, 'YYYYMMDD')), -1) AS delivery_date_key,
    TO_NUMBER(TO_CHAR(o.OrderDateTime, 'YYYYMMDD')) AS order_date_key,
    cd.customer_key,
    bd.branch_key,
    dcd.delivery_company_key,
    ad.address_key,
    d.DeliveryID AS delivery_id,
    o.OrderNo AS order_no,
    d.Status AS delivery_status,
    d.DeliveryCharge AS delivery_charge,
    o.TotalAmount AS order_total_amount,
    TRUNC(d.DeliveryDate) - TRUNC(o.OrderDateTime) AS delivery_lead_days
FROM adm.Delivery d
JOIN adm.Orders o ON d.OrderNo = o.OrderNo
JOIN customer_dim cd ON o.CustomerID = cd.customer_id AND cd.is_current_flag = 'Y'
JOIN branch_dim bd ON o.BranchID = bd.branch_id
JOIN delivery_company_dim dcd ON d.DeliveryCompanyID = dcd.delivery_company_id
JOIN address_dim ad ON d.AddressID = ad.address_id;

CREATE OR REPLACE PROCEDURE load_delivery_fact AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO delivery_fact (
        delivery_date_key, order_date_key, customer_key, branch_key, 
        delivery_company_key, address_key, delivery_id, order_no, 
        delivery_status, delivery_charge, order_total_amount, delivery_lead_days, etl_batch_id
    )
    SELECT 
        v.delivery_date_key,
        v.order_date_key,
        v.customer_key,
        v.branch_key,
        v.delivery_company_key,
        v.address_key,
        v.delivery_id,
        v.order_no,
        v.delivery_status,
        v.delivery_charge,
        v.order_total_amount,
        v.delivery_lead_days,
        v_batch_id
    FROM vw_load_delivery_fact v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DELIVERY_FACT loaded.');
END;
/