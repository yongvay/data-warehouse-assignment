CREATE OR REPLACE PROCEDURE load_address_dim_incr AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Records
    INSERT INTO address_dim (address_key, address_id, address_line, address_state, address_postcode, address_region, etl_batch_id)
    SELECT 
        seq_dw_address.NEXTVAL, 
        v.address_id, 
        NVL(TRIM(v.address_line), 'Unknown'), -- Scrubbing: Handle missing/padded address
        NVL(TRIM(v.address_state), 'Unknown'), -- Scrubbing: Handle missing state
        NVL(TRIM(v.address_postcode), '00000'), -- Scrubbing: Default missing postcode
        v.address_region, 
        2
    FROM vw_load_address_dim v
    WHERE NOT EXISTS (SELECT 1 FROM address_dim t WHERE t.address_id = v.address_id);
    v_count := SQL%ROWCOUNT;

    -- 2. Update Existing Records if attributes changed
    UPDATE address_dim t
    SET (address_line, address_state, address_postcode, address_region, etl_update_dt) =
        (SELECT NVL(TRIM(v.address_line), 'Unknown'), NVL(TRIM(v.address_state), 'Unknown'), NVL(TRIM(v.address_postcode), '00000'), v.address_region, SYSDATE
         FROM vw_load_address_dim v WHERE v.address_id = t.address_id)
    WHERE EXISTS (
        SELECT 1 FROM vw_load_address_dim v WHERE v.address_id = t.address_id
        AND (t.address_line != NVL(TRIM(v.address_line), 'Unknown') 
          OR t.address_state != NVL(TRIM(v.address_state), 'Unknown') 
          OR t.address_postcode != NVL(TRIM(v.address_postcode), '00000'))
    );
    v_updated := SQL%ROWCOUNT;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ADDRESS_DIM incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
END;
/