-- ============================================================================
--  TASK 2(b) : MASTER DRIVER  -  run_task2b_subsequent_load
-- ----------------------------------------------------------------------------
--  LOAD ORDER (the same dependency order as Task 2a, plus the calendar first)
--
--    PHASE 0  extend_date_dim                every fact has an FK to DATE_DIM,
--                                            so the calendar must cover the
--                                            source range before anything else
--    PHASE 1  independent dimensions         reason, courier, branch, address,
--                                            promotion, item
--    PHASE 2  CUSTOMER_DIM (Type 2)          runs last among the dimensions so
--                                            that the fact loads see the final
--                                            set of versions
--    PHASE 3  fact tables                    depend on every surrogate key
--                                            produced by phases 0-2
--
--  RE-RUNNABILITY
--    Every step is idempotent.  Running this procedure twice in a row produces
--    a second batch with ins=0 upd=0 on every table, because the anti-joins and
--    the attribute comparisons both come up empty.  That is the single best
--    proof that an incremental load is correct, and it is worth showing in the
--    report as two consecutive runs of vw_etl_batch_summary.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE run_task2b_subsequent_load AS
    v_batch NUMBER;
    v_err   VARCHAR2(4000);
BEGIN
    v_batch := etl_ctl.start_batch('SUBSEQUENT');

    DBMS_OUTPUT.PUT_LINE('============================================================');
    DBMS_OUTPUT.PUT_LINE(' TASK 2B - SUBSEQUENT (INCREMENTAL) LOAD   batch_id = ' || v_batch);
    DBMS_OUTPUT.PUT_LINE(' started ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('============================================================');

    ----------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('-- PHASE 0 : calendar coverage');
    extend_date_dim;

    ----------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('-- PHASE 1 : Type 1 dimensions');
    load_return_reason_dim_delta;
    load_delivery_company_dim_delta;
    load_branch_dim_delta;
    load_address_dim_delta;
    load_promotion_dim_delta;
    load_item_dim_delta;

    ----------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('-- PHASE 2 : Type 2 dimension (SCD2)');
    load_customer_dim_scd2;

    ----------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('-- PHASE 3 : fact tables');
    load_sales_fact_delta;
    load_return_fact_delta;
    load_delivery_fact_delta;
    load_point_fact_delta;

    ----------------------------------------------------------------
    etl_ctl.end_batch('SUCCESS');

    DBMS_OUTPUT.PUT_LINE('============================================================');
    FOR r IN (SELECT rows_inserted, rows_updated, rows_scrubbed, rows_rejected
                FROM etl_batch_control WHERE batch_id = v_batch)
    LOOP
        DBMS_OUTPUT.PUT_LINE(' BATCH ' || v_batch || ' COMPLETED'
            || '   inserted=' || r.rows_inserted
            || '  updated='   || r.rows_updated
            || '  scrubbed='  || r.rows_scrubbed
            || '  rejected='  || r.rows_rejected);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE(' Review:  SELECT * FROM vw_etl_step_summary   WHERE batch_id = ' || v_batch || ';');
    DBMS_OUTPUT.PUT_LINE('          SELECT * FROM vw_etl_reject_summary WHERE batch_id = ' || v_batch || ';');
    DBMS_OUTPUT.PUT_LINE('============================================================');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        v_err := SQLERRM || ' :: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
        etl_ctl.end_batch('FAILED', v_err);
        DBMS_OUTPUT.PUT_LINE('*** BATCH FAILED *** ' || v_err);
        RAISE;
END run_task2b_subsequent_load;
/
SHOW ERRORS

-- ----------------------------------------------------------------------------
--  To run:
--      SET SERVEROUTPUT ON SIZE UNLIMITED
--      EXEC run_task2b_subsequent_load
-- ----------------------------------------------------------------------------
