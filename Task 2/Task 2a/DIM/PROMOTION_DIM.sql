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
        PromotionID,
        PromoName,
        DiscountType,
        DiscountValue,
        StartDate,
        EndDate,
        Status,
        (EndDate - StartDate) AS promo_duration_days, -- Duration Calculation
        v_batch_id
    FROM adm.Promotion;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('PROMOTION_DIM loaded.');
END;
/