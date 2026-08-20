-- ITEM DIMENSION INCREMENTAL
CREATE OR REPLACE PROCEDURE load_item_dim_incr AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Records
    INSERT INTO item_dim (item_key, item_id, item_name, item_unit_price, item_status, category_id, category_name, supplier_id, supplier_name, supplier_contact_no, etl_batch_id)
    SELECT seq_dw_item.NEXTVAL, v.item_id, v.item_name, v.item_unit_price, v.item_status, v.category_id, v.category_name, v.supplier_id, v.supplier_name, v.supplier_contact_no, 2
    FROM vw_load_item_dim v
    WHERE NOT EXISTS (SELECT 1 FROM item_dim t WHERE t.item_id = v.item_id);
    v_count := SQL%ROWCOUNT;

    -- 2. Update Existing Records if attributes changed
    UPDATE item_dim t
    SET (item_name, item_unit_price, item_status, category_id, category_name, supplier_id, supplier_name, supplier_contact_no, etl_update_dt) =
        (SELECT v.item_name, v.item_unit_price, v.item_status, v.category_id, v.category_name, v.supplier_id, v.supplier_name, v.supplier_contact_no, SYSDATE
         FROM vw_load_item_dim v WHERE v.item_id = t.item_id)
    WHERE EXISTS (
        SELECT 1 FROM vw_load_item_dim v WHERE v.item_id = t.item_id
        AND (t.item_name != v.item_name OR t.item_unit_price != v.item_unit_price OR t.item_status != v.item_status)
    );
    v_updated := SQL%ROWCOUNT;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ITEM_DIM incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
END;
/