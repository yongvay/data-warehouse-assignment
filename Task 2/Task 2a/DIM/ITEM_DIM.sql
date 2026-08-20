CREATE OR REPLACE VIEW vw_load_item_dim AS
SELECT 
    i.ItemID AS item_id,
    i.ItemName AS item_name,
    i.UnitPrice AS item_unit_price,
    i.Status AS item_status,
    c.CategoryID AS category_id,
    c.CategoryName AS category_name,
    s.SupplierID AS supplier_id,
    s.SupplierName AS supplier_name,
    s.ContactNo AS supplier_contact_no
FROM adm.Item i
JOIN adm.Category c ON i.CategoryID = c.CategoryID
JOIN adm.Supplier s ON i.SupplierID = s.SupplierID;

CREATE OR REPLACE PROCEDURE load_item_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    -- Seeded Row
    INSERT INTO item_dim (item_key, item_id, item_name, item_unit_price, item_status, category_id, category_name, supplier_id, supplier_name, supplier_contact_no, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 0, 'Unknown', 'UNKN', 'Unknown', 'UNKN', 'Unknown', 'Unknown', v_batch_id);

    -- Load from View
    INSERT INTO item_dim (
        item_key, item_id, item_name, item_unit_price, item_status, 
        category_id, category_name, supplier_id, supplier_name, supplier_contact_no, etl_batch_id
    )
    SELECT 
        seq_dw_item.NEXTVAL,
        v.item_id,
        v.item_name,
        v.item_unit_price,
        v.item_status,
        v.category_id,
        v.category_name,
        v.supplier_id,
        v.supplier_name,
        v.supplier_contact_no,
        v_batch_id
    FROM vw_load_item_dim v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ITEM_DIM loaded.');
END;
/