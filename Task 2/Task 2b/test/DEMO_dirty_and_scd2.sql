-- ============================================================================
--  TASK 2(b) : OPTIONAL DEMONSTRATION SCRIPT
--  Run as the ADM (operational) owner, NOT as the DW owner.
-- ----------------------------------------------------------------------------
--  PURPOSE
--    The incremental load is only convincing in the report if the marker can
--    see it react.  This script injects one example of each defect class into
--    the operational schema so that the next run of run_task2b_subsequent_load
--    visibly produces: a Type 2 version, a Type 1 overwrite, a scrubbed value,
--    a rejected row, and a pending-to-delivered transition.
--
--    It changes at most six existing rows and inserts nothing, so it is safe on
--    a coursework database.  Every statement prints what it touched, and the
--    UNDO section at the bottom restores the original values.
--
--  SUGGESTED SEQUENCE FOR THE REPORT
--    1. run_task2b_subsequent_load          -> baseline batch, all zeros
--    2. this script                          -> inject the defects
--    3. run_task2b_subsequent_load          -> the batch that does the work
--    4. screenshot vw_etl_step_summary, vw_etl_reject_summary,
--       vw_scd2_customer_history, vw_scd2_integrity_check
--    5. run_task2b_subsequent_load again    -> proves idempotency (all zeros)
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

DECLARE
    v_cust   VARCHAR2(5);
    v_branch VARCHAR2(5);
    v_order  VARCHAR2(8);
    v_item   VARCHAR2(5);
    v_dlv    VARCHAR2(8);
BEGIN
    ------------------------------------------------------------------
    -- 1. TYPE 2 TRIGGER : flip one customer's status
    --    Expect: CUSTOMER_DIM gains a version_no = 2 row, the old row
    --            is closed with is_current_flag = 'N'.
    ------------------------------------------------------------------
    SELECT MIN(CustomerID) INTO v_cust
      FROM adm.Customer WHERE Status = 'Active';

    IF v_cust IS NOT NULL THEN
        UPDATE adm.Customer SET Status = 'Inactive' WHERE CustomerID = v_cust;
        DBMS_OUTPUT.PUT_LINE('1. TYPE 2  : customer ' || v_cust
                          || ' Active -> Inactive');
    END IF;

    ------------------------------------------------------------------
    -- 2. TYPE 1 TRIGGER + EMAIL SCRUB : messy name, broken email
    --    Expect: the CURRENT customer row is overwritten in place,
    --            email becomes 'Unknown', rule R103 logged as SCRUBBED.
    ------------------------------------------------------------------
    UPDATE adm.Customer
       SET Name  = '   ahmad    BIN  ali   ',
           Email = 'not-an-email@@'
     WHERE CustomerID = v_cust;
    DBMS_OUTPUT.PUT_LINE('2. TYPE 1  : customer ' || v_cust
                      || ' name padded, email corrupted');

    ------------------------------------------------------------------
    -- 3. STATE SPELLING SCRUB : non-canonical state name
    --    Expect: BRANCH_DIM state becomes 'Pulau Pinang',
    --            region becomes 'Northern', rule R303 logged.
    ------------------------------------------------------------------
    SELECT MIN(BranchID) INTO v_branch FROM adm.Branch;
    IF v_branch IS NOT NULL THEN
        UPDATE adm.Branch SET State = 'penang ' WHERE BranchID = v_branch;
        DBMS_OUTPUT.PUT_LINE('3. SCRUB   : branch ' || v_branch
                          || ' state set to "penang "');
    END IF;

    ------------------------------------------------------------------
    -- 4. REJECT : a negative order quantity
    --    Expect: the line never reaches SALES_FACT, rule R803 logged
    --            as REJECTED (chk_sales_fact_qty would have aborted the
    --            whole load without this rule).
    ------------------------------------------------------------------
    SELECT OrderNo, ItemID INTO v_order, v_item
      FROM (SELECT OrderNo, ItemID FROM adm.OrderDetails
             WHERE Quantity > 0 ORDER BY OrderNo, ItemID)
     WHERE ROWNUM = 1;

    UPDATE adm.OrderDetails SET Quantity = -3
     WHERE OrderNo = v_order AND ItemID = v_item;
    DBMS_OUTPUT.PUT_LINE('4. REJECT  : order line ' || v_order || '/' || v_item
                      || ' quantity set to -3');

    ------------------------------------------------------------------
    -- 5. INCREMENTAL UPDATE : a pending delivery completes
    --    Expect: DELIVERY_FACT row moves from delivery_date_key = -1 to a
    --            real date key and is counted as an UPDATE, not an INSERT.
    ------------------------------------------------------------------
    SELECT MIN(DeliveryID) INTO v_dlv
      FROM adm.Delivery WHERE DeliveryDate IS NULL;

    IF v_dlv IS NOT NULL THEN
        UPDATE adm.Delivery
           SET DeliveryDate = SYSDATE, Status = 'delivered'
         WHERE DeliveryID = v_dlv;
        DBMS_OUTPUT.PUT_LINE('5. UPDATE  : delivery ' || v_dlv
                          || ' despatched, status "delivered" (lower case)');
    ELSE
        DBMS_OUTPUT.PUT_LINE('5. UPDATE  : skipped, no pending delivery found');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('--- defects injected, now run '
                      || 'EXEC run_task2b_subsequent_load as the DW user ---');
END;
/

-- ============================================================================
--  UNDO SECTION - uncomment and run to restore the operational data.
--  Replace the literals with the identifiers printed above.
-- ============================================================================
-- UPDATE adm.Customer      SET Status = 'Active',
--                              Name   = '<original name>',
--                              Email  = '<original email>'
--                        WHERE CustomerID = '<v_cust>';
-- UPDATE adm.Branch        SET State  = '<original state>'
--                        WHERE BranchID = '<v_branch>';
-- UPDATE adm.OrderDetails  SET Quantity = <original qty>
--                        WHERE OrderNo = '<v_order>' AND ItemID = '<v_item>';
-- UPDATE adm.Delivery      SET DeliveryDate = NULL, Status = 'Pending'
--                        WHERE DeliveryID = '<v_dlv>';
-- COMMIT;
