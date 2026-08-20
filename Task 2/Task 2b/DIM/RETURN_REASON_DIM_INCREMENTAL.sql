CREATE OR REPLACE PROCEDURE load_return_reason_dim_incr AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Records
    INSERT INTO return_reason_dim (reason_key, reason_id, reason_name, reason_category, etl_batch_id)
    SELECT 
        seq_dw_reason.NEXTVAL, 
        v.reason_id, 
        NVL(TRIM(v.reason_name), 'Unknown'), -- Scrubbing: Handle missing reason text
        v.reason_category, -- Category derived in the view
        2
    FROM vw_load_return_reason_dim v
    WHERE NOT EXISTS (SELECT 1 FROM return_reason_dim t WHERE t.reason_id = v.reason_id);
    v_count := SQL%ROWCOUNT;

    -- 2. Update Existing Records if attributes changed
    UPDATE return_reason_dim t
    SET (reason_name, reason_category, etl_update_dt) =
        (SELECT NVL(TRIM(v.reason_name), 'Unknown'), v.reason_category, SYSDATE
         FROM vw_load_return_reason_dim v WHERE v.reason_id = t.reason_id)
    WHERE EXISTS (
        SELECT 1 FROM vw_load_return_reason_dim v WHERE v.reason_id = t.reason_id
        AND (t.reason_name != NVL(TRIM(v.reason_name), 'Unknown') OR t.reason_category != v.reason_category)
    );
    v_updated := SQL%ROWCOUNT;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('RETURN_REASON_DIM incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
END;
/