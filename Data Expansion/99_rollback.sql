-- ============================================================================
--  99_rollback.sql
--  RUN AS THE ADM (OPERATIONAL) USER.
--
--      SQL> @"Data Expansion\99_rollback.sql"
--
--  Restores the source schema to the state 00_backup_adm.sql captured.
--  Use this if the generation goes wrong, or if you decide against the
--  expansion after seeing the shape of the data.
--
--  HOW IT WORKS
--  Deletes live rows child-first, then re-inserts from the _BAK copies
--  parent-first.  Triggers are disabled for the duration, because the
--  backups already hold the derived values (Subtotal, TotalAmount, Point,
--  PointsBalance and so on) and letting the triggers recompute them would
--  double-count.  They are re-enabled at the end, unconditionally.
--
--  AFTER RUNNING THIS, the warehouse still holds rows loaded from the
--  expanded source.  Rebuild it: Task1b_Physical_Design.sql, CREATE_SEQUENCE,
--  the Task 2a scripts, then EXEC run_task2a_initial_load.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK ON

-- This script is destructive.  If the restore fails, STOP - do not carry on
-- to the sequence resets and the helper-table drops against a schema that is
-- now empty.  Without this, a failed restore becomes a data-loss amplifier.
--
-- BE AWARE: this closes SQL*Plus if anything goes wrong, which looks like a
-- crash.  That is intentional here and only here.  Spool to a file first so
-- you keep the error message:
--     SQL> SPOOL rollback.log
WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
    TYPE t_names IS TABLE OF VARCHAR2(30);

    -- Child first for the delete pass
    v_delete_order t_names := t_names(
        'RETURNDETAILS', 'VOUCHER', 'RETURNS', 'DELIVERY', 'POINTTRANSACTION',
        'PAYMENT', 'ORDERDETAILS', 'ORDERS', 'ITEMPROMOTION', 'BRANCHSTOCK',
        'MEMBERADDRESS', 'ITEM', 'MEMBER', 'PROMOTION', 'RETURNREASON',
        'DELIVERYCOMPANY', 'CUSTOMER', 'MEMBERSHIPTYPE', 'BRANCH',
        'SUPPLIER', 'CATEGORY'
    );

    -- Only the triggers that were enabled when we started get re-enabled, so
    -- a trigger somebody had deliberately disabled stays disabled.
    v_was_on  t_names := t_names();

    v_missing NUMBER := 0;
    v_n       NUMBER;
BEGIN
    -- Refuse to run unless every backup is present.  A partial restore would
    -- be worse than no restore.
    FOR i IN 1 .. v_delete_order.COUNT LOOP
        SELECT COUNT(*) INTO v_n FROM user_tables
        WHERE  table_name = v_delete_order(i) || '_BAK';
        IF v_n = 0 THEN
            DBMS_OUTPUT.PUT_LINE('MISSING BACKUP: ' || v_delete_order(i) || '_BAK');
            v_missing := v_missing + 1;
        END IF;
    END LOOP;

    IF v_missing > 0 THEN
        RAISE_APPLICATION_ERROR(-20002,
            v_missing || ' backup tables are missing. Rollback aborted.');
    END IF;

    -- Disable triggers so the backed-up derived values are restored verbatim
    FOR t IN (SELECT trigger_name FROM user_triggers WHERE status = 'ENABLED') LOOP
        v_was_on.EXTEND;
        v_was_on(v_was_on.COUNT) := t.trigger_name;
        EXECUTE IMMEDIATE 'ALTER TRIGGER ' || t.trigger_name || ' DISABLE';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Triggers disabled: ' || v_was_on.COUNT);

    BEGIN
        -- Delete child first
        FOR i IN 1 .. v_delete_order.COUNT LOOP
            EXECUTE IMMEDIATE 'DELETE FROM ' || v_delete_order(i);
            DBMS_OUTPUT.PUT_LINE('Cleared  ' || v_delete_order(i) ||
                                 ' (' || SQL%ROWCOUNT || ' rows)');
        END LOOP;

        -- Re-insert parent first: walk the same list backwards
        FOR i IN REVERSE 1 .. v_delete_order.COUNT LOOP
            EXECUTE IMMEDIATE 'INSERT INTO ' || v_delete_order(i) ||
                              ' SELECT * FROM ' || v_delete_order(i) || '_BAK';
            DBMS_OUTPUT.PUT_LINE('Restored ' || v_delete_order(i) ||
                                 ' (' || SQL%ROWCOUNT || ' rows)');
        END LOOP;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('RESTORE FAILED, rolled back: ' || SQLERRM);
            -- Put the triggers back before re-raising, so the schema is never
            -- left running without its derivation logic.
            FOR i IN 1 .. v_was_on.COUNT LOOP
                EXECUTE IMMEDIATE 'ALTER TRIGGER ' || v_was_on(i) || ' ENABLE';
            END LOOP;
            RAISE;
    END;

    FOR i IN 1 .. v_was_on.COUNT LOOP
        EXECUTE IMMEDIATE 'ALTER TRIGGER ' || v_was_on(i) || ' ENABLE';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Triggers re-enabled: ' || v_was_on.COUNT);
END;
/

-- ----------------------------------------------------------------------------
--  Reset the sequences so a fresh expansion produces the same IDs again.
--  Each is dropped and recreated starting one past the highest live value.
-- ----------------------------------------------------------------------------
--  Every MAX() below is guarded by REGEXP_LIKE.  A single row whose ID does
--  not match its coded format would otherwise make TO_NUMBER(SUBSTR(...))
--  raise ORA-01722 and leave the sequences half reset.
DECLARE
    PROCEDURE reset_seq (p_seq IN VARCHAR2, p_next IN NUMBER) IS
    BEGIN
        BEGIN
            EXECUTE IMMEDIATE 'DROP SEQUENCE ' || p_seq;
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE != -2289 THEN RAISE; END IF;   -- ORA-02289: no sequence
        END;
        EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || p_seq ||
                          ' START WITH ' || GREATEST(p_next, 1) ||
                          ' INCREMENT BY 1 NOCACHE NOCYCLE';
        DBMS_OUTPUT.PUT_LINE(RPAD(p_seq, 20) || ' next value ' ||
                             GREATEST(p_next, 1));
    END reset_seq;

    v_n NUMBER;
BEGIN
    SELECT NVL(MAX(TO_NUMBER(SUBSTR(OrderNo, 4))), 0) + 1 INTO v_n
    FROM   Orders WHERE REGEXP_LIKE(OrderNo, '^ORD[0-9]{5}$');
    reset_seq('SEQ_ORDERS', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(DeliveryID, 4))), 0) + 1 INTO v_n
    FROM   Delivery WHERE REGEXP_LIKE(DeliveryID, '^DLV[0-9]{5}$');
    reset_seq('SEQ_DELIVERY', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(ReturnID, 4))), 0) + 1 INTO v_n
    FROM   Returns WHERE REGEXP_LIKE(ReturnID, '^RET[0-9]{5}$');
    reset_seq('SEQ_RETURNS', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(PaymentID, 4))), 0) + 1 INTO v_n
    FROM   Payment WHERE REGEXP_LIKE(PaymentID, '^PAY[0-9]{5}$');
    reset_seq('SEQ_PAYMENT', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(PointTransID, 3))), 0) + 1 INTO v_n
    FROM   PointTransaction WHERE REGEXP_LIKE(PointTransID, '^PT[0-9]{5}$');
    reset_seq('SEQ_POINTTRANS', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(CustomerID, 2))), 0) + 1 INTO v_n
    FROM   Customer WHERE REGEXP_LIKE(CustomerID, '^C[0-9]{4}$');
    reset_seq('SEQ_CUSTOMER', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(AddressID, 2))), 0) + 1 INTO v_n
    FROM   MemberAddress WHERE REGEXP_LIKE(AddressID, '^A[0-9]{4}$');
    reset_seq('SEQ_MEMBERADDRESS', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(ItemID, 2))), 0) + 1 INTO v_n
    FROM   Item WHERE REGEXP_LIKE(ItemID, '^I[0-9]{4}$');
    reset_seq('SEQ_ITEM', v_n);

    SELECT NVL(MAX(TO_NUMBER(SUBSTR(VoucherID, 4))), 0) + 1 INTO v_n
    FROM   Voucher WHERE REGEXP_LIKE(VoucherID, '^VCH[0-9]{5}$');
    reset_seq('SEQ_VOUCHER', v_n);
END;
/

-- ----------------------------------------------------------------------------
--  Drop the helper tables so 01 can rebuild them cleanly
-- ----------------------------------------------------------------------------
BEGIN EXECUTE IMMEDIATE 'DROP TABLE gen_item_launch';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE gen_branch_open';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE gen_customer_cohort';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

SET LINESIZE 130
COLUMN table_name FORMAT A24
PROMPT
PROMPT === ROW COUNTS AFTER ROLLBACK vs THE BACKUP BASELINE ===
PROMPT Every DIFF must be 0.
WITH now_counts AS (
    SELECT 'Customer'         AS table_name, COUNT(*) AS n FROM Customer
    UNION ALL SELECT 'Category',         COUNT(*) FROM Category
    UNION ALL SELECT 'Supplier',         COUNT(*) FROM Supplier
    UNION ALL SELECT 'MembershipType',   COUNT(*) FROM MembershipType
    UNION ALL SELECT 'DeliveryCompany',  COUNT(*) FROM DeliveryCompany
    UNION ALL SELECT 'ReturnReason',     COUNT(*) FROM ReturnReason
    UNION ALL SELECT 'BranchStock',      COUNT(*) FROM BranchStock
    UNION ALL SELECT 'Member',           COUNT(*) FROM Member
    UNION ALL SELECT 'MemberAddress',    COUNT(*) FROM MemberAddress
    UNION ALL SELECT 'Item',             COUNT(*) FROM Item
    UNION ALL SELECT 'Branch',           COUNT(*) FROM Branch
    UNION ALL SELECT 'Promotion',        COUNT(*) FROM Promotion
    UNION ALL SELECT 'ItemPromotion',    COUNT(*) FROM ItemPromotion
    UNION ALL SELECT 'Orders',           COUNT(*) FROM Orders
    UNION ALL SELECT 'OrderDetails',     COUNT(*) FROM OrderDetails
    UNION ALL SELECT 'Payment',          COUNT(*) FROM Payment
    UNION ALL SELECT 'Delivery',         COUNT(*) FROM Delivery
    UNION ALL SELECT 'Returns',          COUNT(*) FROM Returns
    UNION ALL SELECT 'ReturnDetails',    COUNT(*) FROM ReturnDetails
    UNION ALL SELECT 'PointTransaction', COUNT(*) FROM PointTransaction
    UNION ALL SELECT 'Voucher',          COUNT(*) FROM Voucher
)
SELECT b.table_name, b.row_count AS at_backup, c.n AS now, c.n - b.row_count AS diff
FROM   adm_row_snapshot b
JOIN   now_counts c ON c.table_name = b.table_name
WHERE  b.snapshot_label = 'BEFORE_EXPANSION'
ORDER  BY b.table_name;

PROMPT
PROMPT === ROLLBACK COMPLETE ===
WHENEVER SQLERROR CONTINUE
