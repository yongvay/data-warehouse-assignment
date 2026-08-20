CREATE OR REPLACE VIEW vw_load_point_fact AS
SELECT 
    TO_NUMBER(TO_CHAR(pt.TransDate, 'YYYYMMDD')) AS trans_date_key,
    cd.customer_key,
    NVL(bd.branch_key, -1) AS branch_key,
    pt.PointTransID AS point_trans_id,
    pt.OrderNo AS order_no,
    pt.TransType AS trans_type,
    CASE WHEN pt.TransType = 'Earn' THEN pt.Point ELSE 0 END AS points_earned,
    CASE WHEN pt.TransType = 'Redeem' THEN pt.Point ELSE 0 END AS points_redeemed,
    CASE WHEN pt.TransType = 'Earn' THEN pt.Point ELSE -pt.Point END AS net_points
FROM adm.PointTransaction pt
JOIN customer_dim cd ON pt.MemberID = cd.customer_id AND cd.is_current_flag = 'Y'
LEFT JOIN adm.Orders o ON pt.OrderNo = o.OrderNo
LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id;

CREATE OR REPLACE PROCEDURE load_point_fact AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO point_fact (
        trans_date_key, customer_key, branch_key, point_trans_id, 
        order_no, trans_type, points_earned, points_redeemed, net_points, etl_batch_id
    )
    SELECT 
        v.trans_date_key,
        v.customer_key,
        v.branch_key,
        v.point_trans_id,
        v.order_no,
        v.trans_type,
        v.points_earned,
        v.points_redeemed,
        v.net_points,
        v_batch_id
    FROM vw_load_point_fact v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('POINT_FACT loaded.');
END;
/