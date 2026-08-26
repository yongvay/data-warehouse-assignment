CREATE OR REPLACE VIEW vw_load_customer_dim AS
SELECT 
    c.CustomerID AS customer_id,
    INITCAP(
        REGEXP_REPLACE(
            TRIM(c.Name),
            '[[:space:]]+',
            ' '
        )
    ) AS customer_name,
    NVL(TRIM(c.ICNo), 'Unknown') AS customer_ic,
    NVL(LOWER(TRIM(c.Email)), 'Unknown') AS customer_email,
    c.Status AS customer_status,
    CASE WHEN m.MemberID IS NOT NULL THEN 'Y' ELSE 'N' END AS member_flag,
    NVL(mt.TypeName, 'Non-Member') AS membership_type,
    NVL(mt.AnnualFee, 0) AS annual_fee,
    NVL(mt.PointEarnRate, 0) AS point_earn_rate,
    m.MembershipExpiry AS membership_expiry,
    DATE '1900-01-01' AS effective_start_date,
    TO_DATE('9999-12-31', 'YYYY-MM-DD') AS effective_end_date,
    'Y' AS is_current_flag,
    1 AS version_no
FROM adm.Customer c
LEFT JOIN adm.Member m ON c.CustomerID = m.MemberID
LEFT JOIN adm.MembershipType mt ON m.MembershipTypeID = mt.MembershipTypeID;

CREATE OR REPLACE PROCEDURE load_customer_dim_init AS
    v_batch_id NUMBER := 1;
BEGIN
    -- Seeded Row
    INSERT INTO customer_dim (customer_key, customer_id, customer_name, customer_ic, customer_email, customer_status, member_flag, membership_type, annual_fee, point_earn_rate, effective_start_date, is_current_flag, version_no, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'N', 'Unknown', 0, 0, TO_DATE('1900-01-01', 'YYYY-MM-DD'), 'Y', 1, v_batch_id);

    -- Load from View
    INSERT INTO customer_dim (
        customer_key, customer_id, customer_name, customer_ic, customer_email, 
        customer_status, member_flag, membership_type, annual_fee, point_earn_rate, 
        membership_expiry, effective_start_date, effective_end_date, is_current_flag, version_no, etl_batch_id
    )
    SELECT 
        seq_dw_cust.NEXTVAL,
        v.customer_id,
        v.customer_name,
        v.customer_ic,
        v.customer_email,
        v.customer_status,
        v.member_flag,
        v.membership_type,
        v.annual_fee,
        v.point_earn_rate,
        v.membership_expiry,
        v.effective_start_date,
        v.effective_end_date,
        v.is_current_flag,
        v.version_no,
        v_batch_id
    FROM vw_load_customer_dim v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CUSTOMER_DIM initial load complete.');
END;
/
