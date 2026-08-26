-- ============================================================================
--  CREATE_SEQUENCE.sql   -   RUN AS THE DW USER
--
--  Each sequence is dropped before it is created.
--
--  WHY THE DROP MATTERS.  Task1b_Physical_Design.sql opens with
--  DROP TABLE ... CASCADE CONSTRAINTS, but DROP TABLE does not remove
--  sequences.  On a second build the plain CREATE fails with ORA-00955
--  (name is already used), and if you skip this script instead, the surviving
--  sequence carries on from wherever it stopped - so the rebuilt warehouse
--  starts its surrogate keys at 1002 rather than 1.  Nothing breaks, but the
--  keys no longer line up with anything in the report.
--
--  ORA-02289 is "sequence does not exist", which is the expected outcome on
--  a first run and is swallowed here.  Any other error is re-raised.
-- ============================================================================
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
            DBMS_OUTPUT.PUT_LINE('Dropped ' || v_seqs(i));
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE != -2289 THEN RAISE; END IF;
        END;
    END LOOP;
END;
/

CREATE SEQUENCE seq_dw_reason  START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_dw_company START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_dw_branch  START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_dw_address START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_dw_promo   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_dw_item    START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_dw_cust    START WITH 1 INCREMENT BY 1 NOCACHE;
