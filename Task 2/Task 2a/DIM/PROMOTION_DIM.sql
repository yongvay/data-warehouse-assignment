CREATE OR REPLACE VIEW vw_load_promotion_dim AS
SELECT 
    PromotionID AS promotion_id,
    PromoName AS promo_name,
    DiscountType AS discount_type,
    DiscountValue AS discount_value,
    StartDate AS promo_start_date,
    EndDate AS promo_end_date,
    Status AS promo_status,
    (EndDate - StartDate) AS promo_duration_days
FROM adm.Promotion;

CREATE OR REPLACE PROCEDURE load_promotion_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    -- Seeded Row: No Promotion (Key 0)
    INSERT INTO promotion_dim (promo_key, promotion_id, promo_name, discount_type, discount_value, promo_status, etl_batch_id) 
    VALUES (0, 'NONE', 'No Promotion', 'None', 0, 'None', v_batch_id);

    -- Seeded Row: Unknown (Key -1)
    INSERT INTO promotion_dim (promo_key, promotion_id, promo_name, discount_type, discount_value, promo_status, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 'Unknown', 0, 'Unknown', v_batch_id);

    INSERT INTO promotion_dim (
        promo_key, promotion_id, promo_name, discount_type, discount_value, 
        promo_start_date, promo_end_date, promo_status, promo_duration_days, etl_batch_id
    )
    SELECT 
        seq_dw_promo.NEXTVAL,
        v.promotion_id,
        v.promo_name,
        v.discount_type,
        v.discount_value,
        v.promo_start_date,
        v.promo_end_date,
        v.promo_status,
        v.promo_duration_days,
        v_batch_id
    FROM vw_load_promotion_dim v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('PROMOTION_DIM loaded.');
END;
/