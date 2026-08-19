-- ============================================================================
--  BMIT3003 DATA WAREHOUSE TECHNOLOGY - ASSIGNMENT
--  TASK 2(b) : SUBSEQUENT (INCREMENTAL) ETL LOADING
--  FILE 00   : ETL CONTROL, AUDIT AND REJECT INFRASTRUCTURE
--  System    : 88 Speedmart Grocery Data Warehouse
--  Run as    : the DW schema owner (NOT adm)
-- ----------------------------------------------------------------------------
--  WHY THIS FILE EXISTS
--    Task 2(a) hard-coded  v_batch_id := 1  in every procedure.  An incremental
--    load must be repeatable, so every run needs its own batch identifier, its
--    own row counts, and a permanent record of every dirty value it repaired or
--    rejected.  Those three needs map onto the three tables below:
--
--      ETL_BATCH_CONTROL  one row per execution of the whole load
--      ETL_STEP_LOG       one row per target table within a batch
--      ETL_REJECT_LOG     one row per dirty value scrubbed or row rejected
--
--    All logging runs as an AUTONOMOUS TRANSACTION so the audit trail survives
--    even when the data transaction is rolled back by the error handler.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100

-- ----------------------------------------------------------------------------
--  Re-runnable drop block (silently ignores "does not exist" on a first run)
-- ----------------------------------------------------------------------------
DECLARE
    TYPE t_ddl IS TABLE OF VARCHAR2(200);
    v_ddl t_ddl := t_ddl(
        'DROP TABLE etl_reject_log    CASCADE CONSTRAINTS',
        'DROP TABLE etl_step_log      CASCADE CONSTRAINTS',
        'DROP TABLE etl_batch_control CASCADE CONSTRAINTS',
        'DROP SEQUENCE seq_etl_batch',
        'DROP SEQUENCE seq_etl_step',
        'DROP SEQUENCE seq_etl_reject'
    );
BEGIN
    FOR i IN 1 .. v_ddl.COUNT LOOP
        BEGIN
            EXECUTE IMMEDIATE v_ddl(i);
        EXCEPTION
            WHEN OTHERS THEN NULL;   -- object did not exist: first run
        END;
    END LOOP;
END;
/

-- ----------------------------------------------------------------------------
--  1. ETL_BATCH_CONTROL : one row per run of the load
-- ----------------------------------------------------------------------------
CREATE TABLE etl_batch_control
(
    batch_id         NUMBER(8)      NOT NULL,
    batch_type       VARCHAR2(12)   NOT NULL,
    batch_start_dt   DATE           DEFAULT SYSDATE NOT NULL,
    batch_end_dt     DATE,
    batch_status     VARCHAR2(10)   DEFAULT 'RUNNING' NOT NULL,
    rows_inserted    NUMBER(10)     DEFAULT 0 NOT NULL,
    rows_updated     NUMBER(10)     DEFAULT 0 NOT NULL,
    rows_rejected    NUMBER(10)     DEFAULT 0 NOT NULL,
    rows_scrubbed    NUMBER(10)     DEFAULT 0 NOT NULL,
    hwm_order_dt     DATE,      -- highest order date present in SALES_FACT
    hwm_return_dt    DATE,      -- highest return date present in RETURN_FACT
    hwm_delivery_dt  DATE,      -- highest delivery date present in DELIVERY_FACT
    hwm_point_dt     DATE,      -- highest point trans date present in POINT_FACT
    error_msg        VARCHAR2(4000),
    CONSTRAINT etl_batch_control_pk PRIMARY KEY (batch_id),
    CONSTRAINT chk_etl_batch_type
        CHECK (batch_type IN ('INITIAL','SUBSEQUENT')),
    CONSTRAINT chk_etl_batch_status
        CHECK (batch_status IN ('RUNNING','SUCCESS','FAILED')),
    CONSTRAINT chk_etl_batch_dates
        CHECK (batch_end_dt IS NULL OR batch_end_dt >= batch_start_dt)
);

-- ----------------------------------------------------------------------------
--  2. ETL_STEP_LOG : one row per target table inside a batch
-- ----------------------------------------------------------------------------
CREATE TABLE etl_step_log
(
    step_id         NUMBER(10)    NOT NULL,
    batch_id        NUMBER(8)     NOT NULL,
    step_seq        NUMBER(4)     NOT NULL,
    target_object   VARCHAR2(30)  NOT NULL,
    step_dt         DATE          DEFAULT SYSDATE NOT NULL,
    rows_inserted   NUMBER(10)    DEFAULT 0 NOT NULL,
    rows_updated    NUMBER(10)    DEFAULT 0 NOT NULL,
    rows_rejected   NUMBER(10)    DEFAULT 0 NOT NULL,
    rows_scrubbed   NUMBER(10)    DEFAULT 0 NOT NULL,
    step_status     VARCHAR2(10)  DEFAULT 'SUCCESS' NOT NULL,
    CONSTRAINT etl_step_log_pk PRIMARY KEY (step_id),
    CONSTRAINT etl_step_log_batch_fk FOREIGN KEY (batch_id)
        REFERENCES etl_batch_control (batch_id),
    CONSTRAINT chk_etl_step_status CHECK (step_status IN ('SUCCESS','FAILED'))
);

-- ----------------------------------------------------------------------------
--  3. ETL_REJECT_LOG : the data-quality evidence trail
--     action_taken = 'SCRUBBED'  value repaired, row still loaded
--                    'DEFAULTED' value replaced by Unknown / seeded key
--                    'REJECTED'  whole row withheld from the warehouse
-- ----------------------------------------------------------------------------
CREATE TABLE etl_reject_log
(
    reject_id      NUMBER(12)     NOT NULL,
    batch_id       NUMBER(8)      NOT NULL,
    source_table   VARCHAR2(40)   NOT NULL,
    source_key     VARCHAR2(60),
    target_object  VARCHAR2(30)   NOT NULL,
    column_name    VARCHAR2(40),
    raw_value      VARCHAR2(400),
    rule_code      VARCHAR2(8)    NOT NULL,
    rule_desc      VARCHAR2(200)  NOT NULL,
    action_taken   VARCHAR2(10)   NOT NULL,
    logged_dt      DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT etl_reject_log_pk PRIMARY KEY (reject_id),
    CONSTRAINT etl_reject_log_batch_fk FOREIGN KEY (batch_id)
        REFERENCES etl_batch_control (batch_id),
    CONSTRAINT chk_etl_reject_action
        CHECK (action_taken IN ('SCRUBBED','DEFAULTED','REJECTED'))
);

CREATE INDEX etl_reject_log_batch_ix ON etl_reject_log (batch_id, target_object);

-- ----------------------------------------------------------------------------
--  4. Sequences
-- ----------------------------------------------------------------------------
CREATE SEQUENCE seq_etl_batch  START WITH 2 INCREMENT BY 1 NOCACHE;  -- batch 1 = Task 2a
CREATE SEQUENCE seq_etl_step   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_etl_reject START WITH 1 INCREMENT BY 1 NOCACHE;

-- ----------------------------------------------------------------------------
--  5. Back-fill the Task 2(a) historical load as batch 1 so that every row
--     already in the warehouse points at a real batch record.
-- ----------------------------------------------------------------------------
INSERT INTO etl_batch_control
    (batch_id, batch_type, batch_start_dt, batch_end_dt, batch_status)
VALUES
    (1, 'INITIAL', SYSDATE, SYSDATE, 'SUCCESS');
COMMIT;

-- ============================================================================
--  6. PACKAGE etl_ctl : batch / step / reject logging API
-- ============================================================================
CREATE OR REPLACE PACKAGE etl_ctl AS

    g_batch_id  NUMBER(8) := NULL;

    FUNCTION  start_batch  (p_batch_type VARCHAR2 DEFAULT 'SUBSEQUENT') RETURN NUMBER;
    PROCEDURE end_batch    (p_status VARCHAR2, p_error_msg VARCHAR2 DEFAULT NULL);
    PROCEDURE log_step     (p_target VARCHAR2,
                            p_ins    NUMBER   DEFAULT 0,
                            p_upd    NUMBER   DEFAULT 0,
                            p_rej    NUMBER   DEFAULT 0,
                            p_scr    NUMBER   DEFAULT 0,
                            p_status VARCHAR2 DEFAULT 'SUCCESS');
    PROCEDURE log_reject   (p_source_table VARCHAR2,
                            p_source_key   VARCHAR2,
                            p_target       VARCHAR2,
                            p_column       VARCHAR2,
                            p_raw_value    VARCHAR2,
                            p_rule_code    VARCHAR2,
                            p_rule_desc    VARCHAR2,
                            p_action       VARCHAR2 DEFAULT 'REJECTED');
    FUNCTION  current_batch RETURN NUMBER;

END etl_ctl;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY etl_ctl AS

    g_step_seq NUMBER := 0;

    ------------------------------------------------------------------
    FUNCTION current_batch RETURN NUMBER IS
    BEGIN
        -- Guard: never let a load procedure run outside a batch.
        IF g_batch_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20001,
                'No ETL batch is open. Call etl_ctl.start_batch first '
             || '(or simply EXEC run_task2b_subsequent_load).');
        END IF;
        RETURN g_batch_id;
    END current_batch;

    ------------------------------------------------------------------
    FUNCTION start_batch (p_batch_type VARCHAR2 DEFAULT 'SUBSEQUENT')
        RETURN NUMBER
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_id NUMBER(8);
    BEGIN
        SELECT seq_etl_batch.NEXTVAL INTO v_id FROM dual;

        INSERT INTO etl_batch_control
            (batch_id, batch_type, batch_start_dt, batch_status)
        VALUES
            (v_id, p_batch_type, SYSDATE, 'RUNNING');
        COMMIT;

        g_batch_id := v_id;
        g_step_seq := 0;
        RETURN v_id;
    END start_batch;

    ------------------------------------------------------------------
    PROCEDURE log_step (p_target VARCHAR2,
                        p_ins    NUMBER   DEFAULT 0,
                        p_upd    NUMBER   DEFAULT 0,
                        p_rej    NUMBER   DEFAULT 0,
                        p_scr    NUMBER   DEFAULT 0,
                        p_status VARCHAR2 DEFAULT 'SUCCESS')
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        g_step_seq := g_step_seq + 1;

        INSERT INTO etl_step_log
            (step_id, batch_id, step_seq, target_object,
             rows_inserted, rows_updated, rows_rejected, rows_scrubbed, step_status)
        VALUES
            (seq_etl_step.NEXTVAL, g_batch_id, g_step_seq, UPPER(p_target),
             NVL(p_ins,0), NVL(p_upd,0), NVL(p_rej,0), NVL(p_scr,0), p_status);
        COMMIT;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(UPPER(p_target), 24) ||
            ' ins=' || LPAD(NVL(p_ins,0), 6) ||
            ' upd=' || LPAD(NVL(p_upd,0), 6) ||
            ' rej=' || LPAD(NVL(p_rej,0), 6) ||
            ' scrubbed=' || LPAD(NVL(p_scr,0), 6) ||
            '  [' || p_status || ']');
    END log_step;

    ------------------------------------------------------------------
    PROCEDURE log_reject (p_source_table VARCHAR2,
                          p_source_key   VARCHAR2,
                          p_target       VARCHAR2,
                          p_column       VARCHAR2,
                          p_raw_value    VARCHAR2,
                          p_rule_code    VARCHAR2,
                          p_rule_desc    VARCHAR2,
                          p_action       VARCHAR2 DEFAULT 'REJECTED')
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO etl_reject_log
            (reject_id, batch_id, source_table, source_key, target_object,
             column_name, raw_value, rule_code, rule_desc, action_taken)
        VALUES
            (seq_etl_reject.NEXTVAL, g_batch_id, UPPER(p_source_table),
             SUBSTR(p_source_key, 1, 60), UPPER(p_target),
             UPPER(p_column), SUBSTR(p_raw_value, 1, 400),
             p_rule_code, SUBSTR(p_rule_desc, 1, 200), p_action);
        COMMIT;
    END log_reject;

    ------------------------------------------------------------------
    PROCEDURE end_batch (p_status VARCHAR2, p_error_msg VARCHAR2 DEFAULT NULL) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        UPDATE etl_batch_control b
           SET b.batch_end_dt  = SYSDATE,
               b.batch_status  = p_status,
               b.error_msg     = SUBSTR(p_error_msg, 1, 4000),
               b.rows_inserted = NVL((SELECT SUM(s.rows_inserted) FROM etl_step_log s
                                       WHERE s.batch_id = b.batch_id), 0),
               b.rows_updated  = NVL((SELECT SUM(s.rows_updated)  FROM etl_step_log s
                                       WHERE s.batch_id = b.batch_id), 0),
               b.rows_rejected = NVL((SELECT SUM(s.rows_rejected) FROM etl_step_log s
                                       WHERE s.batch_id = b.batch_id), 0),
               b.rows_scrubbed = NVL((SELECT SUM(s.rows_scrubbed) FROM etl_step_log s
                                       WHERE s.batch_id = b.batch_id), 0),
               b.hwm_order_dt    = (SELECT MAX(d.cal_date) FROM sales_fact f
                                      JOIN date_dim d ON d.date_key = f.order_date_key),
               b.hwm_return_dt   = (SELECT MAX(d.cal_date) FROM return_fact f
                                      JOIN date_dim d ON d.date_key = f.return_date_key),
               b.hwm_delivery_dt = (SELECT MAX(d.cal_date) FROM delivery_fact f
                                      JOIN date_dim d ON d.date_key = f.delivery_date_key),
               b.hwm_point_dt    = (SELECT MAX(d.cal_date) FROM point_fact f
                                      JOIN date_dim d ON d.date_key = f.trans_date_key)
         WHERE b.batch_id = g_batch_id;
        COMMIT;
    END end_batch;

END etl_ctl;
/
SHOW ERRORS

-- ============================================================================
--  END OF FILE 00
-- ============================================================================
