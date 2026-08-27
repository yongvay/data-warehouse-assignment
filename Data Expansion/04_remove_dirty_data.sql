-- ============================================================================
--  04_remove_dirty_data.sql
--  RUN AS THE ADM (OPERATIONAL) USER.
--
--      SQL> @"Data Expansion\04_remove_dirty_data.sql"
--
--  WHY THIS EXISTS
--
--  insert_dirty_data.sql plants rows that BREAK the warehouse's own CHECK
--  constraints on purpose.  Test B lodges RET00135 two days BEFORE its order
--  was placed, so the warehouse computes
--      days_to_return = TRUNC(ReturnDate) - TRUNC(OrderDateTime) = -2
--  and chk_return_fact_days (days_to_return >= 0) aborts the load with
--  ORA-02290.  Test E does the same to chk_delivery_fact_lead via DLV00643.
--
--  That is the intended behaviour.  The scrubbing that neutralises those rows
--  - the GREATEST(...) clamps - lives in the Task 2(b) INCREMENTAL procedures,
--  not in the Task 2(a) initial load.  Task 2(a) is a first-time historical
--  load of clean operational data and has no such clamp.
--
--  So the dirty data must arrive AFTER the initial load, which is the whole
--  point of Task 2(b): the warehouse is already built, new and faulty records
--  turn up in the source, and the incremental load has to cope.  Loading it
--  before Task 2(a) is simply the wrong order and there is nothing to fix in
--  either script.
--
--  This removes only the six test rows and the C9901 test customer, and
--  restores C0187 to Active.  It touches nothing the generator produced.
--
--  SAFE TO RE-RUN.
-- ============================================================================
SET SERVEROUTPUT ON
SET DEFINE OFF
SET FEEDBACK ON

-- Children first.  ReturnDetails must go before Returns (its parent), and
-- Delivery before Orders.  OrderDetails cascades from Orders, but it is
-- deleted explicitly here so the order of operations is obvious.
DELETE FROM adm.ItemPromotion
WHERE  PromotionID IN (SELECT PromotionID FROM adm.Promotion
                       WHERE  SYSDATE BETWEEN StartDate AND EndDate)
AND    ItemID IN (SELECT ItemID FROM adm.OrderDetails
                  WHERE  OrderNo = 'ORD02001')
AND    PromoPrice > (SELECT i.UnitPrice FROM adm.Item i
                     WHERE  i.ItemID = adm.ItemPromotion.ItemID);

DELETE FROM adm.Delivery      WHERE DeliveryID IN ('DLV00642','DLV00643');
DELETE FROM adm.ReturnDetails WHERE ReturnID   IN ('RET00135','RET00136');
DELETE FROM adm.Returns       WHERE ReturnID   IN ('RET00135','RET00136');
DELETE FROM adm.Payment       WHERE OrderNo    IN ('ORD02001','ORD02002');
DELETE FROM adm.OrderDetails  WHERE OrderNo    IN ('ORD02001','ORD02002');
DELETE FROM adm.Orders        WHERE OrderNo    IN ('ORD02001','ORD02002');
DELETE FROM adm.Customer      WHERE CustomerID = 'C9901';

UPDATE adm.Customer SET Status = 'Active' WHERE CustomerID = 'C0187';

COMMIT;

-- ----------------------------------------------------------------------------
--  VERIFY - every count must be 0, and C0187 must read Active
-- ----------------------------------------------------------------------------
SET LINESIZE 130
COLUMN what FORMAT A40
PROMPT
PROMPT === DIRTY TEST ROWS REMAINING (all must be 0) ===
SELECT 'Orders ORD02001/02002'  AS what, COUNT(*) AS remaining
FROM   adm.Orders WHERE OrderNo IN ('ORD02001','ORD02002')
UNION ALL SELECT 'OrderDetails for those orders', COUNT(*)
FROM   adm.OrderDetails WHERE OrderNo IN ('ORD02001','ORD02002')
UNION ALL SELECT 'Returns RET00135/136', COUNT(*)
FROM   adm.Returns WHERE ReturnID IN ('RET00135','RET00136')
UNION ALL SELECT 'ReturnDetails for those returns', COUNT(*)
FROM   adm.ReturnDetails WHERE ReturnID IN ('RET00135','RET00136')
UNION ALL SELECT 'Delivery DLV00642/643', COUNT(*)
FROM   adm.Delivery WHERE DeliveryID IN ('DLV00642','DLV00643')
UNION ALL SELECT 'Customer C9901', COUNT(*)
FROM   adm.Customer WHERE CustomerID = 'C9901'
UNION ALL SELECT 'PromoPrice above list price', COUNT(*)
FROM   adm.ItemPromotion ip JOIN adm.Item i ON i.ItemID = ip.ItemID
WHERE  ip.PromoPrice > i.UnitPrice;

PROMPT
PROMPT === C0187 SHOULD BE BACK TO Active ===
COLUMN CustomerID FORMAT A12
COLUMN Status     FORMAT A10
SELECT CustomerID, Status FROM adm.Customer WHERE CustomerID = 'C0187';

PROMPT
PROMPT === CHRONOLOGY RESTORED (both must be 0) ===
SELECT (SELECT COUNT(*) FROM adm.Returns r JOIN adm.Orders o
        ON o.OrderNo = r.OrderNo
        WHERE TRUNC(r.ReturnDate) < TRUNC(o.OrderDateTime))  AS bad_returns,
       (SELECT COUNT(*) FROM adm.Delivery d JOIN adm.Orders o
        ON o.OrderNo = d.OrderNo
        WHERE d.DeliveryDate IS NOT NULL
        AND   TRUNC(d.DeliveryDate) < TRUNC(o.OrderDateTime)) AS bad_deliveries
FROM   dual;

PROMPT
PROMPT ####################################################################
PROMPT #  Now, as DW:                                                     #
PROMPT #     @utils\delete_table.sql                                      #
PROMPT #     EXEC run_task2a_initial_load                                 #
PROMPT #     @"Task 2\Task 2a\verify_task2a.sql"                          #
PROMPT #                                                                  #
PROMPT #  THEN, back as ADM, re-run insert_dirty_data.sql, and only       #
PROMPT #  after that run Task 2b.  That is the correct order.             #
PROMPT ####################################################################
