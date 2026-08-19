CREATE OR REPLACE PROCEDURE load_item_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO item_dim (item_key, item_id, item_name, item_unit_price, item_status, category_id, category_name, supplier_id, supplier_name, supplier_contact_no, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 0, 'Unknown', 'UNKN', 'Unknown', 'UNKN', 'Unknown', 'Unknown', v_batch_id);

    INSERT INTO item_dim (
        item_key, item_id, item_name, item_unit_price, item_status, 
        category_id, category_name, supplier_id, supplier_name, supplier_contact_no, etl_batch_id
    )
    SELECT 
        seq_dw_item.NEXTVAL,
        i.ItemID,
        i.ItemName,
        i.UnitPrice,
        i.Status,
        c.CategoryID,
        c.CategoryName,
        s.SupplierID,
        s.SupplierName,
        s.ContactNo,
        v_batch_id
    FROM adm.Item i
    JOIN adm.Category c ON i.CategoryID = c.CategoryID
    JOIN adm.Supplier s ON i.SupplierID = s.SupplierID;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ITEM_DIM loaded.');
END;
/