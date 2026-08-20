-- BRANCH DIMENSION INCREMENTAL
CREATE OR REPLACE PROCEDURE load_branch_dim_incr AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    INSERT INTO branch_dim (branch_key, branch_id, branch_name, branch_city, branch_state, branch_region, branch_contact_no, etl_batch_id)
    SELECT seq_dw_branch.NEXTVAL, v.branch_id, v.branch_name, v.branch_city, v.branch_state, v.branch_region, v.branch_contact_no, 2
    FROM vw_load_branch_dim v
    WHERE NOT EXISTS (SELECT 1 FROM branch_dim t WHERE t.branch_id = v.branch_id);
    v_count := SQL%ROWCOUNT;

    UPDATE branch_dim t
    SET (branch_name, branch_city, branch_state, branch_region, branch_contact_no, etl_update_dt) =
        (SELECT v.branch_name, v.branch_city, v.branch_state, v.branch_region, v.branch_contact_no, SYSDATE
         FROM vw_load_branch_dim v WHERE v.branch_id = t.branch_id)
    WHERE EXISTS (
        SELECT 1 FROM vw_load_branch_dim v WHERE v.branch_id = t.branch_id
        AND (t.branch_name != v.branch_name OR t.branch_city != v.branch_city OR t.branch_region != v.branch_region)
    );
    v_updated := SQL%ROWCOUNT;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('BRANCH_DIM incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
END;
/