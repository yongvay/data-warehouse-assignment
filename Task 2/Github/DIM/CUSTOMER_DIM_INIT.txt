CREATE OR REPLACE PROCEDURE load_customer_dim_init AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO customer_dim (customer_key, customer_id, customer_name, customer_ic, customer_email, customer_status, member_flag, membership_type, annual_fee, point_earn_rate, effective_start_date, is_current_flag, version_no, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'N', 'Unknown', 0, 0, TO_DATE('1900-01-01', 'YYYY-MM-DD'), 'Y', 1, v_batch_id);

    INSERT INTO customer_dim (
        customer_key, customer_id, customer_name, customer_ic, customer_email, 
        customer_status, member_flag, membership_type, annual_fee, point_earn_rate, 
        membership_expiry, effective_start_date, effective_end_date, is_current_flag, version_no, etl_batch_id
    )
    SELECT 
        seq_dw_cust.NEXTVAL,
        c.CustomerID,
        c.Name,
        NVL(c.ICNo, 'Unknown'),
        NVL(c.Email, 'Unknown'),
        c.Status,
        CASE WHEN m.MemberID IS NOT NULL THEN 'Y' ELSE 'N' END AS member_flag,
        NVL(mt.TypeName, 'Non-Member') AS membership_type,
        NVL(mt.AnnualFee, 0) AS annual_fee,
        NVL(mt.PointEarnRate, 0) AS point_earn_rate,
        m.MembershipExpiry,
        SYSDATE AS effective_start_date,
        TO_DATE('9999-12-31', 'YYYY-MM-DD') AS effective_end_date,
        'Y' AS is_current_flag,
        1 AS version_no,
        v_batch_id
    FROM adm.Customer c
    LEFT JOIN adm.Member m ON c.CustomerID = m.MemberID
    LEFT JOIN adm.MembershipType mt ON m.MembershipTypeID = mt.MembershipTypeID;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CUSTOMER_DIM initial load complete.');
END;
/