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
        CASE WHEN pt.TransType = 'Redeem' THEN NULL ELSE pt.OrderNo END AS order_no, -- Scrubbing: Redemptions cannot have an order
        CASE WHEN pt.TransType IN ('Earn','Redeem') THEN pt.TransType ELSE 'Earn' END AS trans_type, -- Scrubbing: Domain validation
        CASE WHEN pt.TransType = 'Earn' THEN ABS(pt.Point) ELSE 0 END AS points_earned,
        CASE WHEN pt.TransType = 'Redeem' THEN ABS(pt.Point) ELSE 0 END AS points_redeemed,
        CASE WHEN pt.TransType = 'Earn' THEN ABS(pt.Point) ELSE -ABS(pt.Point) END AS net_points,
        2
    FROM adm.PointTransaction pt
    LEFT JOIN customer_dim cd ON pt.MemberID = cd.customer_id AND TRUNC(pt.TransDate) BETWEEN TRUNC(cd.effective_start_date) AND TRUNC(cd.effective_end_date)
    LEFT JOIN adm.Orders o ON pt.OrderNo = o.OrderNo
    LEFT JOIN branch_dim bd ON o.BranchID = bd.branch_id
    WHERE NOT EXISTS (
        SELECT 1 FROM point_fact pf WHERE pf.point_trans_id = pt.PointTransID
    )
    AND pt.TransDate >= p_load_date - 1;

    v_count := SQL%ROWCOUNT;
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('POINT_FACT incremental load: ' || v_count || ' inserted.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error in POINT_FACT incremental load: ' || SQLERRM);
        RAISE;
END;
/
