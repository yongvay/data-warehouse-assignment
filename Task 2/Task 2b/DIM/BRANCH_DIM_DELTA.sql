-- ============================================================================
--  TASK 2(b) : BRANCH_DIM  -  incremental Type 1 load
-- ----------------------------------------------------------------------------
--  Delta rule : a row is NEW when its branch_id is absent from the dimension,
--               and CHANGED when any tracked attribute differs.  An anti-join
--               is used instead of a date high-water mark because adm.Branch
--               carries no last-modified column.
--  Type 1     : the existing row is overwritten, no history is kept - branch
--               geography corrections should apply to all past sales too.
--  Seeded row : branch_key = -1 is never touched.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_branch_dim_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    ------------------------------------------------------------------
    -- 1. UPDATE : existing branches whose attributes changed
    ------------------------------------------------------------------
    UPDATE branch_dim d
       SET (branch_name, branch_city, branch_state, branch_region,
            branch_contact_no, etl_update_dt, etl_batch_id, dq_flag) =
           (SELECT s.branch_name, s.branch_city, s.branch_state, s.branch_region,
                   s.branch_contact_no, SYSDATE, v_batch, s.dq_flag
              FROM vw_stg_branch s
             WHERE s.branch_id = d.branch_id)
     WHERE d.branch_key <> -1
       AND EXISTS (SELECT 1
                     FROM vw_stg_branch s
                    WHERE s.branch_id = d.branch_id
                      AND s.dq_flag  <> 'D'
                      AND (   s.branch_name       <> d.branch_name
                           OR s.branch_city       <> d.branch_city
                           OR s.branch_state      <> d.branch_state
                           OR s.branch_region     <> d.branch_region
                           OR s.branch_contact_no <> d.branch_contact_no));
    v_upd := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- 2. INSERT : branches that have never been loaded
    ------------------------------------------------------------------
    INSERT INTO branch_dim
        (branch_key, branch_id, branch_name, branch_city, branch_state,
         branch_region, branch_contact_no, etl_batch_id, dq_flag)
    SELECT seq_dw_branch.NEXTVAL, s.branch_id, s.branch_name, s.branch_city,
           s.branch_state, s.branch_region, s.branch_contact_no, v_batch, s.dq_flag
      FROM vw_stg_branch s
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM branch_dim d
                        WHERE d.branch_id = s.branch_id);
    v_ins := SQL%ROWCOUNT;

    ------------------------------------------------------------------
    -- 3. AUDIT : record every scrubbed value and every rejected row
    ------------------------------------------------------------------
    FOR r IN (SELECT branch_id, raw_state, dq_flag, dq_note
                FROM vw_stg_branch
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.BRANCH', r.branch_id, 'BRANCH_DIM',
                           'BRANCH_STATE', r.raw_state,
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('BRANCH_DIM', v_ins, v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('BRANCH_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_branch_dim_delta;
/
SHOW ERRORS
