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
        AddressID,
        AddressLine,
        State,
        Postcode,
        CASE 
            WHEN State IN ('Perlis', 'Kedah', 'Pulau Pinang', 'Perak') THEN 'Northern'
            WHEN State IN ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan') THEN 'Central'
            WHEN State IN ('Melaka', 'Johor') THEN 'Southern'
            WHEN State IN ('Pahang', 'Terengganu', 'Kelantan') THEN 'East Coast'
            WHEN State IN ('Sabah', 'Sarawak', 'Labuan') THEN 'East Malaysia'
            ELSE 'Unknown'
        END,
        v_batch_id
    FROM adm.MemberAddress;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ADDRESS_DIM loaded.');
END;
/