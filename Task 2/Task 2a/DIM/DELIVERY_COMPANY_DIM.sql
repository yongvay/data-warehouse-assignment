CREATE OR REPLACE PROCEDURE load_delivery_company_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO delivery_company_dim (delivery_company_key, delivery_company_id, company_name, company_contact_no, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 'Unknown', v_batch_id);

    INSERT INTO delivery_company_dim (
        delivery_company_key, delivery_company_id, company_name, company_contact_no, etl_batch_id
    )
    SELECT 
        seq_dw_company.NEXTVAL, DeliveryCompanyID, CompanyName, ContactNo, v_batch_id
    FROM adm.DeliveryCompany;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DELIVERY_COMPANY_DIM loaded.');
END;
/