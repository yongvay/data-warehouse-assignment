CREATE OR REPLACE PROCEDURE load_promotion_dim_incr AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Records
    INSERT INTO promotion_dim (promo_key, promotion_id, promo_name, discount_type, discount_value, promo_start_date, promo_end_date, promo_status, promo_duration_days, etl_batch_id)
    SELECT 
        seq_dw_promo.NEXTVAL, 
        v.promotion_id, 
        NVL(TRIM(v.promo_name), 'Unknown'),
        CASE WHEN v.discount_type IN ('Percentage','Fixed','None') THEN v.discount_type ELSE 'Unknown' END, -- Scrubbing: Domain validation
        GREATEST(NVL(v.discount_value, 0), 0), -- Scrubbing: Prevent negative discounts
        NVL(v.promo_start_date, DATE '1900-01-01'),
        NVL(v.promo_end_date, DATE '9999-12-31'),
        CASE WHEN v.promo_status IN ('Active','Inactive','None') THEN v.promo_status ELSE 'Unknown' END, -- Scrubbing: Domain validation
        GREATEST(NVL(v.promo_duration_days, 0), 0),
        2
    FROM vw_load_promotion_dim v
    WHERE NOT EXISTS (SELECT 1 FROM promotion_dim t WHERE t.promotion_id = v.promotion_id);
    v_count := SQL%ROWCOUNT;

    -- 2. Update Existing Records if attributes changed
    UPDATE promotion_dim t
    SET (promo_name, discount_type, discount_value, promo_start_date, promo_end_date, promo_status, promo_duration_days, etl_update_dt) =
        (SELECT 
            NVL(TRIM(v.promo_name), 'Unknown'), 
            CASE WHEN v.discount_type IN ('Percentage','Fixed','None') THEN v.discount_type ELSE 'Unknown' END,
            GREATEST(NVL(v.discount_value, 0), 0),
            NVL(v.promo_start_date, DATE '1900-01-01'),
            NVL(v.promo_end_date, DATE '9999-12-31'),
            CASE WHEN v.promo_status IN ('Active','Inactive','None') THEN v.promo_status ELSE 'Unknown' END,
            GREATEST(NVL(v.promo_duration_days, 0), 0),
            SYSDATE
         FROM vw_load_promotion_dim v WHERE v.promotion_id = t.promotion_id)
    WHERE EXISTS (
        SELECT 1 FROM vw_load_promotion_dim v WHERE v.promotion_id = t.promotion_id
        AND (t.promo_name != NVL(TRIM(v.promo_name), 'Unknown') 
          OR t.discount_type != CASE WHEN v.discount_type IN ('Percentage','Fixed','None') THEN v.discount_type ELSE 'Unknown' END
          OR t.discount_value != GREATEST(NVL(v.discount_value, 0), 0)
          OR t.promo_status != CASE WHEN v.promo_status IN ('Active','Inactive','None') THEN v.promo_status ELSE 'Unknown' END)
    );
    v_updated := SQL%ROWCOUNT;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('PROMOTION_DIM incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
END;
/