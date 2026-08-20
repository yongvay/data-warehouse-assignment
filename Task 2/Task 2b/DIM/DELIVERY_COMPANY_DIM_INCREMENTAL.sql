CREATE OR REPLACE PROCEDURE load_delivery_company_dim_incr AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Records
    INSERT INTO delivery_company_dim (delivery_company_key, delivery_company_id, company_name, company_contact_no, etl_batch_id)
    SELECT 
        seq_dw_company.NEXTVAL, 
        v.delivery_company_id, 
        NVL(TRIM(v.company_name), 'Unknown'), -- Scrubbing: Clean company name
        NVL(TRIM(v.company_contact_no), 'Unknown'), -- Scrubbing: Clean contact number
        2
    FROM vw_load_delivery_company_dim v
    WHERE NOT EXISTS (SELECT 1 FROM delivery_company_dim t WHERE t.delivery_company_id = v.delivery_company_id);
    v_count := SQL%ROWCOUNT;

    -- 2. Update Existing Records if attributes changed
    UPDATE delivery_company_dim t
    SET (company_name, company_contact_no, etl_update_dt) =
        (SELECT NVL(TRIM(v.company_name), 'Unknown'), NVL(TRIM(v.company_contact_no), 'Unknown'), SYSDATE
         FROM vw_load_delivery_company_dim v WHERE v.delivery_company_id = t.delivery_company_id)
    WHERE EXISTS (
        SELECT 1 FROM vw_load_delivery_company_dim v WHERE v.delivery_company_id = t.delivery_company_id
        AND (t.company_name != NVL(TRIM(v.company_name), 'Unknown') 
          OR t.company_contact_no != NVL(TRIM(v.company_contact_no), 'Unknown'))
    );
    v_updated := SQL%ROWCOUNT;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DELIVERY_COMPANY_DIM incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
END;
/