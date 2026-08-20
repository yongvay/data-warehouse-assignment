CREATE OR REPLACE VIEW vw_load_delivery_company_dim AS
SELECT 
    DeliveryCompanyID AS delivery_company_id, 
    CompanyName AS company_name, 
    ContactNo AS company_contact_no
FROM adm.DeliveryCompany;

CREATE OR REPLACE PROCEDURE load_delivery_company_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO delivery_company_dim (delivery_company_key, delivery_company_id, company_name, company_contact_no, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 'Unknown', v_batch_id);

    INSERT INTO delivery_company_dim (
        delivery_company_key, delivery_company_id, company_name, company_contact_no, etl_batch_id
    )
    SELECT 
        seq_dw_company.NEXTVAL, 
        v.delivery_company_id, 
        v.company_name, 
        v.company_contact_no, 
        v_batch_id
    FROM vw_load_delivery_company_dim v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DELIVERY_COMPANY_DIM loaded.');
END;
/