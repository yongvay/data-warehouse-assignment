CREATE OR REPLACE VIEW vw_load_branch_dim AS
SELECT 
    BranchID AS branch_id,
    City || ' Branch' AS branch_name, 
    City AS branch_city,
    State AS branch_state,
    CASE 
        WHEN State IN ('Perlis', 'Kedah', 'Pulau Pinang', 'Perak') THEN 'Northern'
        WHEN State IN ('Selangor', 'Kuala Lumpur', 'Putrajaya', 'Negeri Sembilan') THEN 'Central'
        WHEN State IN ('Melaka', 'Johor') THEN 'Southern'
        WHEN State IN ('Pahang', 'Terengganu', 'Kelantan') THEN 'East Coast'
        WHEN State IN ('Sabah', 'Sarawak', 'Labuan') THEN 'East Malaysia'
        ELSE 'Unknown'
    END AS branch_region,
    ContactNo AS branch_contact_no
FROM adm.Branch;

CREATE OR REPLACE PROCEDURE load_branch_dim AS
    v_batch_id NUMBER := 1;
BEGIN
    -- Seeded Row (-1 required for Point Redemptions)
    INSERT INTO branch_dim (branch_key, branch_id, branch_name, branch_city, branch_state, branch_region, branch_contact_no, etl_batch_id) 
    VALUES (-1, 'UNKN', 'Unknown / Not Applicable', 'Unknown', 'Unknown', 'Unknown', 'Unknown', v_batch_id);

    INSERT INTO branch_dim (
        branch_key, branch_id, branch_name, branch_city, branch_state, branch_region, branch_contact_no, etl_batch_id
    )
    SELECT 
        seq_dw_branch.NEXTVAL,
        v.branch_id,
        v.branch_name,
        v.branch_city,
        v.branch_state,
        v.branch_region,
        v.branch_contact_no,
        v_batch_id
    FROM vw_load_branch_dim v;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('BRANCH_DIM loaded.');
END;
/