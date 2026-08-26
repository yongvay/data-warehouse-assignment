-- ============================================================================
--  utils/delete_table.sql   -   RUN AS THE DW USER
--
--  Empties every warehouse table and resets the surrogate-key sequences, so
--  the next  EXEC run_task2a_initial_load  starts from a clean slate with
--  keys numbered from 1.
--
--  Use this INSTEAD of re-running Task1b_Physical_Design.sql when you only
--  want to reload data and keep the table definitions as they are.
--
--  Two fixes over the previous version:
--    1. The closing DBMS_OUTPUT.PUT_LINE was a bare call outside any PL/SQL
--       block.  SQL*Plus cannot execute that and answered with
--       SP2-0734: unknown command.  It is wrapped in BEGIN/END now.
--    2. Sequences are reset.  DELETE removes the rows but leaves the
--       sequences where they were, so a reload used to continue numbering
--       from 1002 instead of restarting at 1.
-- ============================================================================
SET SERVEROUTPUT ON

-- 1. EMPTY THE FACT TABLES FIRST (they hold the foreign keys)
DELETE FROM sales_fact;
DELETE FROM return_fact;
DELETE FROM delivery_fact;
DELETE FROM point_fact;

-- 2. EMPTY THE DIMENSION TABLES
DELETE FROM item_dim;
DELETE FROM customer_dim;
DELETE FROM address_dim;
DELETE FROM branch_dim;
DELETE FROM delivery_company_dim;
DELETE FROM promotion_dim;
DELETE FROM return_reason_dim;
DELETE FROM date_dim;

COMMIT;

-- 3. RESET THE SURROGATE-KEY SEQUENCES BACK TO 1
DECLARE
    TYPE t_names IS TABLE OF VARCHAR2(30);
    v_seqs t_names := t_names(
        'SEQ_DW_REASON', 'SEQ_DW_COMPANY', 'SEQ_DW_BRANCH', 'SEQ_DW_ADDRESS',
        'SEQ_DW_PROMO',  'SEQ_DW_ITEM',    'SEQ_DW_CUST'
    );
BEGIN
    FOR i IN 1 .. v_seqs.COUNT LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP SEQUENCE ' || v_seqs(i);
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE != -2289 THEN RAISE; END IF;  -- no such sequence
        END;
        EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || v_seqs(i) ||
                          ' START WITH 1 INCREMENT BY 1 NOCACHE';
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(
        'All warehouse tables cleared and sequences reset to 1. ' ||
        'Ready for EXEC run_task2a_initial_load.');
END;
/
