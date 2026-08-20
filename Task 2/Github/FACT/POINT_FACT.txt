CREATE OR REPLACE PROCEDURE load_point_fact AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO point_fact (
        trans_date_key, customer_key, branch_key, point_trans_id, 
        order_no, trans_type, points_earned, points_redeemed, net_points, etl_batch_id
    )
    SELECT 
        TO_NUMBER(TO_CHAR(pt.TransDate, 'YYYYMMDD')),
        cd.customer_key,
        NVL(bd.branch_key, -1) AS branch_key,
        pt.PointTransID,
        pt.OrderNo,
        pt.TransType,
        CASE WHEN pt.TransType = 'Earn' THEN pt.Point ELSE 0 END AS points_earned,
        CASE WHEN pt.TransType = 'Redeem' THEN pt.Point ELSE 0 END AS points_redeemed,
        -- Net points = Earned - Redeemed
        CASE WHEN pt.TransType = 'Earn' THEN pt.Point ELSE -pt.Point END AS net_points,
        v_batch_id
    FROM adm.PointTransaction pt
    JOIN customer_dim cd ON pt.MemberID = cd.customer_id AND cd.is_current_flag = 'Y'
    -- Left join Orders because Redemptions carry no order
    LEFT JOIN adm.Orders o ON pt.OrderNo = o.OrderNo
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('POINT_FACT loaded.');
END;
/