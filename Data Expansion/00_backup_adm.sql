-- ============================================================================
--  00_backup_adm.sql
--  RUN AS THE ADM (OPERATIONAL) USER.  RUN THIS FIRST.  NON-NEGOTIABLE.
--
--      SQL> @"Data Expansion\00_backup_adm.sql"
--
--  Takes a CTAS snapshot of every table the expansion touches, plus a row
--  count record.  99_rollback.sql restores from these.
--
--  Backups are plain heap copies without constraints or triggers, which is
--  exactly what a restore needs - the rollback deletes the live rows and
--  re-inserts from the copy.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK ON

DECLARE
    TYPE t_names IS TABLE OF VARCHAR2(30);
    -- Every table the generator writes to, plus the parents it reads, so a
    -- restore can put the whole source schema back exactly as it was.
    v_tables t_names := t_names(
        'CATEGORY', 'SUPPLIER', 'BRANCH', 'MEMBERSHIPTYPE', 'CUSTOMER',
        'DELIVERYCOMPANY', 'RETURNREASON', 'PROMOTION', 'MEMBER', 'ITEM',
        'MEMBERADDRESS', 'BRANCHSTOCK', 'ITEMPROMOTION', 'ORDERS',
        'ORDERDETAILS', 'PAYMENT', 'POINTTRANSACTION', 'DELIVERY',
        'RETURNS', 'VOUCHER', 'RETURNDETAILS'
    );
    v_exists NUMBER;
BEGIN
    FOR i IN 1 .. v_tables.COUNT LOOP
        SELECT COUNT(*) INTO v_exists
        FROM   user_tables
        WHERE  table_name = v_tables(i) || '_BAK';

        IF v_exists > 0 THEN
            DBMS_OUTPUT.PUT_LINE('SKIP   ' || v_tables(i) ||
                                 '_BAK already exists - not overwritten.');
        ELSE
            EXECUTE IMMEDIATE 'CREATE TABLE ' || v_tables(i) || '_BAK AS ' ||
                              'SELECT * FROM ' || v_tables(i);
            DBMS_OUTPUT.PUT_LINE('BACKUP ' || v_tables(i) || '_BAK created.');
        END IF;
    END LOOP;
END;
/

-- ----------------------------------------------------------------------------
--  Row-count record, so you can prove afterwards what the expansion added.
-- ----------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE '
        CREATE TABLE adm_row_snapshot (
            snapshot_label VARCHAR2(30),
            taken_at       DATE DEFAULT SYSDATE,
            table_name     VARCHAR2(30),
            row_count      NUMBER
        )';
    DBMS_OUTPUT.PUT_LINE('adm_row_snapshot created.');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN
            DBMS_OUTPUT.PUT_LINE('adm_row_snapshot already exists - reusing.');
        ELSE RAISE; END IF;
END;
/

DELETE FROM adm_row_snapshot WHERE snapshot_label = 'BEFORE_EXPANSION';

INSERT INTO adm_row_snapshot (snapshot_label, table_name, row_count)
SELECT 'BEFORE_EXPANSION', 'Customer',         COUNT(*) FROM Customer
UNION ALL SELECT 'BEFORE_EXPANSION','Category',         COUNT(*) FROM Category
UNION ALL SELECT 'BEFORE_EXPANSION','Supplier',         COUNT(*) FROM Supplier
UNION ALL SELECT 'BEFORE_EXPANSION','MembershipType',   COUNT(*) FROM MembershipType
UNION ALL SELECT 'BEFORE_EXPANSION','DeliveryCompany',  COUNT(*) FROM DeliveryCompany
UNION ALL SELECT 'BEFORE_EXPANSION','ReturnReason',     COUNT(*) FROM ReturnReason
UNION ALL SELECT 'BEFORE_EXPANSION','BranchStock',      COUNT(*) FROM BranchStock
UNION ALL SELECT 'BEFORE_EXPANSION','Member',           COUNT(*) FROM Member
UNION ALL SELECT 'BEFORE_EXPANSION','MemberAddress',    COUNT(*) FROM MemberAddress
UNION ALL SELECT 'BEFORE_EXPANSION','Item',             COUNT(*) FROM Item
UNION ALL SELECT 'BEFORE_EXPANSION','Branch',           COUNT(*) FROM Branch
UNION ALL SELECT 'BEFORE_EXPANSION','Promotion',        COUNT(*) FROM Promotion
UNION ALL SELECT 'BEFORE_EXPANSION','ItemPromotion',    COUNT(*) FROM ItemPromotion
UNION ALL SELECT 'BEFORE_EXPANSION','Orders',           COUNT(*) FROM Orders
UNION ALL SELECT 'BEFORE_EXPANSION','OrderDetails',     COUNT(*) FROM OrderDetails
UNION ALL SELECT 'BEFORE_EXPANSION','Payment',          COUNT(*) FROM Payment
UNION ALL SELECT 'BEFORE_EXPANSION','Delivery',         COUNT(*) FROM Delivery
UNION ALL SELECT 'BEFORE_EXPANSION','Returns',          COUNT(*) FROM Returns
UNION ALL SELECT 'BEFORE_EXPANSION','ReturnDetails',    COUNT(*) FROM ReturnDetails
UNION ALL SELECT 'BEFORE_EXPANSION','PointTransaction', COUNT(*) FROM PointTransaction
UNION ALL SELECT 'BEFORE_EXPANSION','Voucher',          COUNT(*) FROM Voucher;

COMMIT;

SET LINESIZE 120
COLUMN table_name FORMAT A24
PROMPT
PROMPT === BASELINE ROW COUNTS (BEFORE EXPANSION) ===
SELECT table_name, row_count
FROM   adm_row_snapshot
WHERE  snapshot_label = 'BEFORE_EXPANSION'
ORDER  BY table_name;

PROMPT
PROMPT === BACKUP COMPLETE.  Next: 01_expand_promotions.sql ===
