-- ============================================================================
--  BRANCH DIMENSION INCREMENTAL
-- ----------------------------------------------------------------------------
--  CORRECTION APPLIED TO THIS FILE
--
--  NULL-SAFE CHANGE DETECTION.
--  "t.branch_name != v.branch_name" evaluates to UNKNOWN, not TRUE, when
--  either side is NULL - so a branch whose contact number went from NULL to a
--  real value, or from a value to NULL, was never detected as changed and the
--  dimension silently kept the stale value.
--
--  NVL on both sides with a sentinel that cannot occur in the data makes the
--  comparison behave the way the code reads: two NULLs are equal, and NULL
--  against a value is a difference.
--
--  branch_contact_no has also been added to the change test.  It was updated
--  by the SET clause but was not part of the WHERE, so a contact-number-only
--  change never triggered the update at all.
-- ============================================================================

CREATE OR REPLACE PROCEDURE load_branch_dim_incr AS
    v_count NUMBER := 0;
    v_updated NUMBER := 0;
BEGIN
    -- 1. Insert New Records
    INSERT INTO branch_dim (branch_key, branch_id, branch_name, branch_city, branch_state, branch_region, branch_contact_no, etl_batch_id)
    SELECT seq_dw_branch.NEXTVAL, v.branch_id, v.branch_name, v.branch_city, v.branch_state, v.branch_region, v.branch_contact_no, 2
    FROM vw_load_branch_dim v
    WHERE NOT EXISTS (SELECT 1 FROM branch_dim t WHERE t.branch_id = v.branch_id);
    v_count := SQL%ROWCOUNT;

    -- 2. Update Existing Records if attributes changed
    UPDATE branch_dim t
    SET (branch_name, branch_city, branch_state, branch_region, branch_contact_no, etl_update_dt) =
        (SELECT v.branch_name, v.branch_city, v.branch_state, v.branch_region, v.branch_contact_no, SYSDATE
         FROM vw_load_branch_dim v WHERE v.branch_id = t.branch_id)
    WHERE EXISTS (
        SELECT 1 FROM vw_load_branch_dim v WHERE v.branch_id = t.branch_id
        AND (   NVL(t.branch_name, '~')       != NVL(v.branch_name, '~')
             OR NVL(t.branch_city, '~')       != NVL(v.branch_city, '~')
             OR NVL(t.branch_state, '~')      != NVL(v.branch_state, '~')
             OR NVL(t.branch_region, '~')     != NVL(v.branch_region, '~')
             OR NVL(t.branch_contact_no, '~') != NVL(v.branch_contact_no, '~'))
    );
    v_updated := SQL%ROWCOUNT;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('BRANCH_DIM incremental load: ' || v_count || ' inserted, ' || v_updated || ' updated.');
END;
/
