CREATE OR REPLACE VIEW vw_load_address_dim AS
SELECT 
    AddressID AS address_id,
    AddressLine AS address_line,
    State AS address_state,
    Postcode AS address_postcode,
    CASE 
        WHEN State IN ('Perlis', 'Kedah', 'Pulau Pinang', 'Perak') THEN 'Northern'
        WHEN State IN ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan') THEN 'Central'
        WHEN State IN ('Melaka', 'Johor') THEN 'Southern'
        WHEN State IN ('Pahang', 'Terengganu', 'Kelantan') THEN 'East Coast'
        WHEN State IN ('Sabah', 'Sarawak', 'Labuan') THEN 'East Malaysia'
        ELSE 'Unknown'
    END AS address_region
FROM adm.MemberAddress;

CREATE OR REPLACE PROCEDURE load_address_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    INSERT INTO address_dim (address_key, address_id, address_line, address_state, address_postcode, address_region, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown', 'Unknown', '00000', 'Unknown', v_batch_id);

    INSERT INTO address_dim (
        address_key, address_id, address_line, address_state, address_postcode, address_region, etl_batch_id
    )
    SELECT 
        seq_dw_address.NEXTVAL,
        v.address_id,
        v.address_line,
        v.address_state,
        v.address_postcode,
        v.address_region,
        v_batch_id
    FROM vw_load_address_dim v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ADDRESS_DIM loaded.');
END;
/