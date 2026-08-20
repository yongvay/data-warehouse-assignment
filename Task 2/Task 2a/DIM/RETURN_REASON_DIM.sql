CREATE OR REPLACE VIEW vw_load_return_reason_dim AS
SELECT 
    ReasonID AS reason_id,
    ReasonName AS reason_name,
    CASE 
        WHEN ReasonName IN ('Missing', 'Wrong Item') THEN 'Fulfilment'
        WHEN ReasonName IN ('Broken', 'Expired') THEN 'Product Quality'
        ELSE 'Unknown'
    END AS reason_category
FROM adm.ReturnReason;

CREATE OR REPLACE PROCEDURE load_return_reason_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    -- Seeded Row
    INSERT INTO return_reason_dim (reason_key, reason_id, reason_name, reason_category, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 'Unknown', v_batch_id);

    -- Extraction and Transformation
    INSERT INTO return_reason_dim (
        reason_key, reason_id, reason_name, reason_category, etl_batch_id
    )
    SELECT 
        seq_dw_reason.NEXTVAL,
        v.reason_id,
        v.reason_name,
        v.reason_category,
        v_batch_id
    FROM vw_load_return_reason_dim v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('RETURN_REASON_DIM loaded.');
END;
/