-- ============================================================================
--  TASK 2(b) - DIRTY DATA INJECTION
--  RUN AS THE ADM (OPERATIONAL) USER
--
--  THIS SCRIPT IS SAFE TO RE-RUN.  Every insert is guarded by NOT EXISTS, so
--  rows that already landed are skipped rather than raising ORA-00001.  That
--  matters here because the previous attempts partially succeeded.
-- ----------------------------------------------------------------------------
--  WHAT CHANGED FROM THE PREVIOUS VERSION
--
--  1. ReturnDetails.OrderNo is now supplied.
--     TRG_RETURNDETAILS_REFUND reads :NEW.OrderNo to look up the original
--     unit price.  Omitting the column made that lookup search for
--     OrderNo = NULL, which found nothing and raised ORA-01403 inside the
--     trigger.
--
--  2. RefundAmount is passed as 0.
--     The same trigger overwrites it with QuantityReturned * UnitPrice, so
--     whatever is supplied is discarded.  Passing 0 makes it obvious in the
--     code that the value is derived, not asserted.
--
--  3. Test C no longer claims to demonstrate a refund-header mismatch.
--     TRG_RETURNS_TOTAL fires AFTER INSERT on ReturnDetails and recomputes
--     Returns.TotalRefundAmount from the lines, so a mismatched header cannot
--     survive in this source.  Test C now demonstrates over-return only.
--
--  4. Orders.TotalAmount is no longer patched by hand.
--     TRG_ORDERS_TOTAL maintains it automatically after each OrderDetails
--     insert.
-- ----------------------------------------------------------------------------
--  WHAT THIS SOURCE SYSTEM ALREADY PREVENTS  (report this - it is a finding)
--
--  CHECK constraints block: negative or zero quantity, negative price,
--  subtotal mismatch, negative delivery charge, invalid order type, invalid
--  status values on Orders/Delivery/Returns/PointTransaction, malformed
--  email and IC format, negative points, negative refund, negative member
--  balance, promo price at or below zero.
--
--  TRIGGERS additionally derive: OrderDetails.UnitPrice, Orders.TotalAmount,
--  ReturnDetails.RefundAmount, Returns.TotalRefundAmount,
--  Member.PointsBalance - and enforce stock and item status on order entry.
--
--  CONCLUSION FOR THE REPORT: the corresponding ABS() and domain-validation
--  scrubbing in Task 2(b) is DEFENCE IN DEPTH.  It guards the warehouse
--  against bulk loads, migrations and direct SQL that bypass the application
--  and its triggers - not against faults this source can currently produce.
--  Keep the ORA-02290 and ORA-01403 error output from the earlier attempts as
--  the evidence for that claim.  A demonstration where every rule fires would
--  actually be a WORSE finding, because it would mean the operational system
--  had no integrity controls at all.
-- ----------------------------------------------------------------------------
--  THE GAPS THAT REMAIN OPEN, AND WHICH TEST EXERCISES EACH
--
--    Gap 1  No constraint orders ReturnDate or DeliveryDate against
--           OrderDateTime                                    -> Tests B and E
--    Gap 2  No constraint caps QuantityReturned at the quantity sold -> Test C
--    Gap 4  CHK_ITEMPROMOTION_PRICE enforces PromoPrice > 0 but not
--           PromoPrice <= UnitPrice, so a negative discount is possible
--                                                                   -> Test G
--    Gap 5  REGEXP_LIKE returns NULL on NULL input, and a CHECK rejects only
--           on FALSE - so NULL Email and NULL ICNo pass CHK_CUSTOMER_EMAIL
--           and CHK_CUSTOMER_IC untouched                            -> Test F
--    Gap 6  Customer.Name is only NOT NULL - unlimited whitespace and casing
--           inconsistency permitted                                  -> Test F
-- ============================================================================

-- ============================================================================
-- Please note that if you encountered access issue: (Run this as sysdba)
-- sqlplus sys/your_sys_password@localhost:1521/FREEPDB1 as sysdba
-- GRANT SELECT, INSERT, UPDATE, DELETE ON adm.Customer TO dw;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON adm.Orders TO dw;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON adm.OrderDetails TO dw;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON adm.Returns TO dw;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON adm.ReturnDetails TO dw;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON adm.Delivery TO dw;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON adm.ItemPromotion TO dw;
-- ============================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200


-- ============================================================================
--  TEST A : SCD TYPE 2 TRIGGER
--  customer_status is a Type 2 attribute in Task 1(a), so the warehouse must
--  close version 1 and open version 2 rather than overwriting in place.
-- ============================================================================
UPDATE adm.Customer SET Status = 'Inactive' WHERE CustomerID = 'C0187';


-- ============================================================================
--  TEST B : RETURN DATED BEFORE ITS ORDER          (Gap 1)
--  Order placed today, return lodged two days ago - a physical impossibility
--  the source accepts without complaint.  chk_return_fact_days in the
--  warehouse requires days_to_return >= 0, so without the GREATEST(...) scrub
--  this row aborts the load with ORA-02290.
-- ============================================================================
INSERT INTO adm.Orders (OrderNo, CustomerID, BranchID, OrderDateTime, OrderType, TotalAmount)
SELECT 'ORD02001',
       (SELECT MIN(CustomerID) FROM adm.Customer),
       (SELECT MIN(BranchID)   FROM adm.Branch),
       SYSDATE, 'Walk-in', 0
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.Orders WHERE OrderNo = 'ORD02001');

INSERT INTO adm.OrderDetails (OrderNo, ItemID, Quantity, UnitPrice, Subtotal)
SELECT 'ORD02001', i.ItemID, 4, i.UnitPrice, 4 * i.UnitPrice
FROM   adm.Item i
WHERE  i.ItemID = (SELECT MIN(ItemID) FROM adm.Item WHERE Status = 'Active')
  AND  NOT EXISTS (SELECT 1 FROM adm.OrderDetails WHERE OrderNo = 'ORD02001');

INSERT INTO adm.Returns (ReturnID, OrderNo, ReturnDate, Status, TotalRefundAmount)
SELECT 'RET00135', 'ORD02001', SYSDATE - 2, 'Approved', 0
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.Returns WHERE ReturnID = 'RET00135');

--  OrderNo is required by TRG_RETURNDETAILS_REFUND.
--  RefundAmount is passed as 0 because that trigger derives the real value.
INSERT INTO adm.ReturnDetails (ReturnID, OrderNo, ItemID, ReasonID, QuantityReturned, RefundAmount)
SELECT 'RET00135', 'ORD02001',
       (SELECT ItemID FROM adm.OrderDetails WHERE OrderNo = 'ORD02001' AND ROWNUM = 1),
       (SELECT MIN(ReasonID) FROM adm.ReturnReason),
       1, 0
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.ReturnDetails WHERE ReturnID = 'RET00135');


-- ============================================================================
--  TEST C : RETURNED MORE THAN WAS SOLD            (Gap 2)
--  ORD02002 sells 2 units.  The return claims 99 back.  No source constraint
--  compares the two, and no warehouse constraint does either -
--  chk_return_fact_qty only requires quantity_returned > 0.
--
--  THIS ONE SURVIVES THE ENTIRE PIPELINE UNCHANGED.  It is the clearest
--  example of a defect that ABS()-style scrubbing cannot catch, because
--  nothing is negative - the value is simply impossible.  In Task 3 it
--  produces a return rate above 100% for that item.
--
--  Either add a cap against the originating order line, or state the
--  limitation explicitly in the report.  Naming it reads as judgement;
--  leaving it silent reads as an oversight.
-- ============================================================================
INSERT INTO adm.Orders (OrderNo, CustomerID, BranchID, OrderDateTime, OrderType, TotalAmount)
SELECT 'ORD02002',
       (SELECT MIN(CustomerID) FROM adm.Customer),
       (SELECT MIN(BranchID)   FROM adm.Branch),
       SYSDATE - 1, 'Online', 0
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.Orders WHERE OrderNo = 'ORD02002');

INSERT INTO adm.OrderDetails (OrderNo, ItemID, Quantity, UnitPrice, Subtotal)
SELECT 'ORD02002', i.ItemID, 2, i.UnitPrice, 2 * i.UnitPrice
FROM   adm.Item i
WHERE  i.ItemID = (SELECT MIN(ItemID) FROM adm.Item WHERE Status = 'Active')
  AND  NOT EXISTS (SELECT 1 FROM adm.OrderDetails WHERE OrderNo = 'ORD02002');

--  This insert failed silently on the previous attempt and the row never
--  landed.  It is isolated here so that if it fails again the error is
--  visible on its own rather than buried in a batch.
INSERT INTO adm.Returns (ReturnID, OrderNo, ReturnDate, Status, TotalRefundAmount)
SELECT 'RET00136', 'ORD02002', SYSDATE, 'Pending', 0
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.Returns WHERE ReturnID = 'RET00136');

INSERT INTO adm.ReturnDetails (ReturnID, OrderNo, ItemID, ReasonID, QuantityReturned, RefundAmount)
SELECT 'RET00136', 'ORD02002',
       (SELECT ItemID FROM adm.OrderDetails WHERE OrderNo = 'ORD02002' AND ROWNUM = 1),
       (SELECT MIN(ReasonID) FROM adm.ReturnReason),
       99, 0
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.ReturnDetails WHERE ReturnID = 'RET00136');


-- ============================================================================
--  TEST D : MUTABLE DELIVERY
--  Loads as Pending with delivery_date_key = -1 and delivery_lead_days NULL.
--  Section 2 below then despatches it.  This is the test that distinguishes a
--  genuine incremental load from a plain "insert what is new" - nothing new
--  is created, an existing row merely changes state.
-- ============================================================================
INSERT INTO adm.Delivery (DeliveryID, OrderNo, DeliveryCompanyID, AddressID,
                          DeliveryDate, Status, DeliveryCharge)
SELECT 'DLV00642', 'ORD02001',
       (SELECT MIN(DeliveryCompanyID) FROM adm.DeliveryCompany),
       (SELECT MIN(AddressID)         FROM adm.MemberAddress),
       NULL, 'Pending', 15.50
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.Delivery WHERE DeliveryID = 'DLV00642');


-- ============================================================================
--  TEST E : DELIVERY DATED BEFORE ITS ORDER        (Gap 1)
--  ORD02002 was placed yesterday; this delivery claims to have arrived three
--  days ago.  chk_delivery_fact_lead requires delivery_lead_days >= 0, so the
--  GREATEST(...) scrub is what keeps the row loadable.
-- ============================================================================
INSERT INTO adm.Delivery (DeliveryID, OrderNo, DeliveryCompanyID, AddressID,
                          DeliveryDate, Status, DeliveryCharge)
SELECT 'DLV00643', 'ORD02002',
       (SELECT MIN(DeliveryCompanyID) FROM adm.DeliveryCompany),
       (SELECT MIN(AddressID)         FROM adm.MemberAddress),
       SYSDATE - 3, 'Delivered', 8.00
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.Delivery WHERE DeliveryID = 'DLV00643');


-- ============================================================================
--  TEST F : MESSY NAME, NULL EMAIL, NULL IC        (Gaps 5 and 6)
--  CHK_CUSTOMER_EMAIL and CHK_CUSTOMER_IC both use REGEXP_LIKE, which returns
--  NULL for a NULL input - and a CHECK constraint rejects only on FALSE,
--  never on UNKNOWN.  Both constraints therefore appear to forbid missing
--  values and neither actually does.  A subtle and very reportable finding
--  about the operational design.
--
--  The name arrives with leading, trailing and repeated internal spaces plus
--  inconsistent casing.  Unscrubbed it becomes a second, distinct spelling of
--  one customer in every Task 3 report that groups by customer name.
-- ============================================================================
INSERT INTO adm.Customer (CustomerID, Name, ICNo, Email, Status)
SELECT 'C9901', '   lim    WEI   jian  ', NULL, NULL, 'Active'
FROM   dual
WHERE  NOT EXISTS (SELECT 1 FROM adm.Customer WHERE CustomerID = 'C9901');


-- ============================================================================
--  TEST G : PROMOTIONAL PRICE ABOVE LIST PRICE     (Gap 4)
--  CHK_ITEMPROMOTION_PRICE enforces PromoPrice > 0 but says nothing about the
--  list price, so a promotion can be priced ABOVE the item it discounts.
--  That yields (UnitPrice - PromoPrice) < 0, and chk_sales_fact_discount
--  forbids a negative discount - so without the GREATEST(...,0) clamp in
--  load_sales_fact_incr the entire load aborts.
--
--  Inserts nothing unless a promotion is active today.  Check with:
--    SELECT PromotionID, StartDate, EndDate FROM adm.Promotion
--    WHERE SYSDATE BETWEEN StartDate AND EndDate;
--  If that returns no rows, say so in the report rather than leaving the
--  test unexplained.
-- ============================================================================
INSERT INTO adm.ItemPromotion (ItemID, PromotionID, PromoPrice)
SELECT i.ItemID, p.PromotionID, i.UnitPrice * 2      -- deliberately above list
FROM   adm.Item i
CROSS  JOIN (SELECT MIN(PromotionID) AS PromotionID
             FROM   adm.Promotion
             WHERE  SYSDATE BETWEEN StartDate AND EndDate) p
WHERE  i.ItemID = (SELECT ItemID FROM adm.OrderDetails
                   WHERE OrderNo = 'ORD02001' AND ROWNUM = 1)
  AND  p.PromotionID IS NOT NULL
  AND  NOT EXISTS (SELECT 1 FROM adm.ItemPromotion ip
                   WHERE ip.ItemID = i.ItemID AND ip.PromotionID = p.PromotionID);

COMMIT;


-- ============================================================================
--  CONFIRM WHAT LANDED
--  Expected: Orders 2, OrderDetails 2, Returns 2, ReturnDetails 2,
--            Delivery 2, Customer 1.
--  ItemPromotion is 1 only if a promotion is active today.
-- ============================================================================
SELECT 'Orders'          AS tbl, COUNT(*) AS rows_present FROM adm.Orders        WHERE OrderNo    IN ('ORD02001','ORD02002')
UNION ALL SELECT 'OrderDetails',  COUNT(*) FROM adm.OrderDetails  WHERE OrderNo    IN ('ORD02001','ORD02002')
UNION ALL SELECT 'Returns',       COUNT(*) FROM adm.Returns       WHERE ReturnID   IN ('RET00135','RET00136')
UNION ALL SELECT 'ReturnDetails', COUNT(*) FROM adm.ReturnDetails WHERE ReturnID   IN ('RET00135','RET00136')
UNION ALL SELECT 'Delivery',      COUNT(*) FROM adm.Delivery      WHERE DeliveryID IN ('DLV00642','DLV00643')
UNION ALL SELECT 'Customer',      COUNT(*) FROM adm.Customer      WHERE CustomerID = 'C9901';

--  The trigger-derived values, for the report.  Note that RefundAmount and
--  TotalRefundAmount hold computed figures, not the zeros passed in above -
--  which is itself worth a screenshot as evidence of the source's own
--  integrity controls.
SELECT r.ReturnID, r.OrderNo,
       TO_CHAR(r.ReturnDate, 'DD-MON-YY') AS return_date,
       r.Status, r.TotalRefundAmount,
       rd.QuantityReturned, rd.RefundAmount,
       od.Quantity AS qty_actually_sold
FROM       adm.Returns       r
JOIN       adm.ReturnDetails rd ON rd.ReturnID = r.ReturnID
LEFT JOIN  adm.OrderDetails  od ON od.OrderNo  = r.OrderNo AND od.ItemID = rd.ItemID
WHERE      r.ReturnID IN ('RET00135','RET00136')
ORDER  BY  r.ReturnID;


-- ============================================================================
--  SECTION 2 : THE MUTABLE-STATUS TEST
--  Run this only AFTER the first  EXEC run_task2b;  has loaded DLV00642 as
--  Pending and RET00136 as Pending.  Then run the load a second time and
--  compare.
-- ============================================================================
/*
UPDATE adm.Delivery
SET    Status = 'Delivered', DeliveryDate = SYSDATE
WHERE  DeliveryID = 'DLV00642';

UPDATE adm.Returns
SET    Status = 'Refunded'
WHERE  ReturnID = 'RET00136';

COMMIT;
*/


-- ============================================================================
--  SECTION 3 : CLEAN UP
--  The warehouse rows these produced are left in place deliberately - a
--  warehouse does not delete history because the operational system did.
--  Reset the warehouse by re-running Task 1(b) and Task 2(a) instead.
-- ============================================================================
/*
DELETE FROM adm.ItemPromotion
WHERE  ItemID = (SELECT ItemID FROM adm.OrderDetails WHERE OrderNo = 'ORD02001' AND ROWNUM = 1)
  AND  PromoPrice = (SELECT UnitPrice * 2 FROM adm.Item
                     WHERE ItemID = (SELECT ItemID FROM adm.OrderDetails
                                     WHERE OrderNo = 'ORD02001' AND ROWNUM = 1));
DELETE FROM adm.Delivery      WHERE DeliveryID IN ('DLV00642','DLV00643');
DELETE FROM adm.ReturnDetails WHERE ReturnID   IN ('RET00135','RET00136');
DELETE FROM adm.Returns       WHERE ReturnID   IN ('RET00135','RET00136');
DELETE FROM adm.OrderDetails  WHERE OrderNo    IN ('ORD02001','ORD02002');
DELETE FROM adm.Orders        WHERE OrderNo    IN ('ORD02001','ORD02002');
DELETE FROM adm.Customer      WHERE CustomerID = 'C9901';
UPDATE adm.Customer SET Status = 'Active' WHERE CustomerID = 'C0187';
COMMIT;
*/
