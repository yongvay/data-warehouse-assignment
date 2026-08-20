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
        ReasonID,
        ReasonName,
        CASE 
            WHEN ReasonName IN ('Missing', 'Wrong Item') THEN 'Fulfilment'
            WHEN ReasonName IN ('Broken', 'Expired') THEN 'Product Quality'
            ELSE 'Unknown'
        END,
        v_batch_id
    FROM adm.ReturnReason;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('RETURN_REASON_DIM loaded.');
END;
/