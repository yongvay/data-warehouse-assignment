-- ============================================================================
--  03_validate_source.sql
--  RUN AS THE ADM (OPERATIONAL) USER, after 02_expand_orders.sql.
--
--      SQL> @"C:\Users\PC\Desktop\DW\Data Expansion\03_validate_source.sql"
--
--  Validates the SOURCE before any ETL touches it.  Catching an incoherent
--  row here costs one query; catching it after the warehouse load means
--  reading an ORA-02291 or ORA-02290 out of a half-finished procedure and
--  rebuilding from scratch.
--
--  EVERY CHECK BELOW MUST RETURN ZERO FAILURES.
--
--  TWO SQL*PLUS RULES THIS FILE OBEYS, BOTH LEARNED THE HARD WAY:
--    1. SQLBLANKLINES is OFF by default, so a blank line INSIDE a SQL
--       statement ends the statement without running it.  The big WITH query
--       below therefore contains no blank lines, and SQLBLANKLINES is turned
--       on as a second line of defence.
--    2. A line ending in a hyphen is a continuation marker: SQL*Plus joins it
--       to the next line and REMOVES the hyphen.  No line here ends in "-",
--       which is why arithmetic operators start the following line instead of
--       ending the current one.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 150
SET PAGESIZE 200
COLUMN check_name FORMAT A52
COLUMN verdict    FORMAT A10
COLUMN month_name FORMAT A12

PROMPT
PROMPT ####################################################################
PROMPT #  SOURCE VALIDATION - every FAILURES column must read 0           #
PROMPT ####################################################################
WITH checks AS (
    -- 1. Chronology: a customer cannot buy before they were acquired
    SELECT 'Order before its customer''s cohort year' AS check_name,
           COUNT(*) AS failures
    FROM   Orders o
    JOIN   gen_customer_cohort g ON g.CustomerID = o.CustomerID
    WHERE  EXTRACT(YEAR FROM o.OrderDateTime) < g.FirstYear
    -- 2. Chronology: a branch cannot trade before it opened
    UNION ALL
    SELECT 'Order at a branch before it opened',
           COUNT(*)
    FROM   Orders o
    JOIN   gen_branch_open g ON g.BranchID = o.BranchID
    WHERE  EXTRACT(YEAR FROM o.OrderDateTime) < g.OpenYear
    -- 3. Chronology: an item cannot be sold before it was listed
    UNION ALL
    SELECT 'Order line for an item before its launch year',
           COUNT(*)
    FROM   OrderDetails od
    JOIN   Orders o          ON o.OrderNo = od.OrderNo
    JOIN   gen_item_launch g ON g.ItemID  = od.ItemID
    WHERE  EXTRACT(YEAR FROM o.OrderDateTime) < g.LaunchYear
    -- 4. Delivery cannot precede its order.  No source constraint enforces
    --    this (Gap 1).  Compared at full timestamp precision, NOT truncated,
    --    because a truncating comparison hides a same-day inversion.
    UNION ALL
    SELECT 'Delivery timestamped before its order',
           COUNT(*)
    FROM   Delivery d
    JOIN   Orders o ON o.OrderNo = d.OrderNo
    WHERE  d.DeliveryDate IS NOT NULL
    AND    d.DeliveryDate < o.OrderDateTime
    -- 5. Return cannot precede its order.  Same gap, same full-precision rule.
    UNION ALL
    SELECT 'Return timestamped before its order',
           COUNT(*)
    FROM   Returns r
    JOIN   Orders o ON o.OrderNo = r.OrderNo
    WHERE  r.ReturnDate < o.OrderDateTime
    -- 6. No transaction may be dated in the future
    UNION ALL
    SELECT 'Order dated in the future',
           COUNT(*) FROM Orders WHERE OrderDateTime > SYSDATE
    UNION ALL
    SELECT 'Delivery dated in the future',
           COUNT(*) FROM Delivery WHERE DeliveryDate > SYSDATE
    UNION ALL
    SELECT 'Return dated in the future',
           COUNT(*) FROM Returns WHERE ReturnDate > SYSDATE
    UNION ALL
    SELECT 'Point transaction dated in the future',
           COUNT(*) FROM PointTransaction WHERE TransDate > SYSDATE
    -- 7. Every transaction must sit inside the date_dim calendar (2016-2030)
    UNION ALL
    SELECT 'Order outside the 2016-2030 calendar window',
           COUNT(*) FROM Orders
    WHERE  OrderDateTime <  DATE '2016-01-01'
    OR     OrderDateTime >= DATE '2031-01-01'
    -- 8. An order with no lines leaves TotalAmount at 0, which breaks
    --    chk_payment_amount (Amount > 0)
    UNION ALL
    SELECT 'Order carrying no order lines',
           COUNT(*)
    FROM   Orders o
    WHERE  NOT EXISTS (SELECT 1 FROM OrderDetails od
                       WHERE od.OrderNo = o.OrderNo)
    -- 9. Derived values the triggers should have populated
    UNION ALL
    SELECT 'Order line where Subtotal <> Quantity * UnitPrice',
           COUNT(*) FROM OrderDetails
    WHERE  Subtotal <> Quantity * UnitPrice
    UNION ALL
    SELECT 'Order where TotalAmount <> sum of its lines',
           COUNT(*)
    FROM   Orders o
    WHERE  ABS(o.TotalAmount
               - NVL((SELECT SUM(od.Subtotal) FROM OrderDetails od
                      WHERE od.OrderNo = o.OrderNo), 0)) > 0.01
    -- 10. Promotion pricing.  chk_itempromotion_price only enforces > 0; a
    --     PromoPrice above list makes discount_amt negative and aborts the
    --     warehouse load on chk_sales_fact_discount.
    UNION ALL
    SELECT 'PromoPrice above the item list price',
           COUNT(*)
    FROM   ItemPromotion ip
    JOIN   Item i ON i.ItemID = ip.ItemID
    WHERE  ip.PromoPrice > i.UnitPrice
    -- 11. Returns must not exceed what was sold (Gap 2).  Scoped to rows this
    --     expansion created: RET00135/RET00136 are Test C in
    --     insert_dirty_data.sql, which returns 99 of 2 units ON PURPOSE.
    UNION ALL
    SELECT 'Return qty above qty sold (generated rows only)',
           COUNT(*)
    FROM   ReturnDetails rd
    JOIN   OrderDetails od ON od.OrderNo = rd.OrderNo
                          AND od.ItemID  = rd.ItemID
    WHERE  rd.QuantityReturned > od.Quantity
    AND    rd.ReturnID > 'RET00136'
    -- 12. Point transaction shape (chk_pointtrans_order)
    UNION ALL
    SELECT 'Earn row with no order, or Redeem row with one',
           COUNT(*)
    FROM   PointTransaction
    WHERE  (TransType = 'Earn'   AND OrderNo IS NULL)
    OR     (TransType = 'Redeem' AND OrderNo IS NOT NULL)
    -- 13. A delivery should go to an address belonging to the buyer.  No FK
    --     enforces that - Delivery.AddressID only has to be SOME
    --     MemberAddress - so the generator enforces it itself.  Scoped to
    --     generated rows; the original 641 were not built under this rule.
    UNION ALL
    SELECT 'Delivery address not the buyer''s (generated rows)',
           COUNT(*)
    FROM   Delivery d
    JOIN   Orders o        ON o.OrderNo   = d.OrderNo
    JOIN   MemberAddress a ON a.AddressID = d.AddressID
    WHERE  a.MemberID <> o.CustomerID
    AND    d.DeliveryID > 'DLV00643'
    -- 14. ID format integrity, so nothing overflows its VARCHAR2 width
    UNION ALL
    SELECT 'Malformed OrderNo',
           COUNT(*) FROM Orders
    WHERE  NOT REGEXP_LIKE(OrderNo, '^ORD[0-9]{5}$')
    UNION ALL
    SELECT 'Malformed DeliveryID',
           COUNT(*) FROM Delivery
    WHERE  NOT REGEXP_LIKE(DeliveryID, '^DLV[0-9]{5}$')
    UNION ALL
    SELECT 'Malformed ReturnID',
           COUNT(*) FROM Returns
    WHERE  NOT REGEXP_LIKE(ReturnID, '^RET[0-9]{5}$')
    UNION ALL
    SELECT 'Malformed PointTransID',
           COUNT(*) FROM PointTransaction
    WHERE  NOT REGEXP_LIKE(PointTransID, '^PT[0-9]{5}$')
    -- 15. The IDs insert_dirty_data.sql reserves must still be free WHEN THIS
    --     RUNS.  Expect 0 at step 4 of RUN_ORDER.md.  Re-running this script
    --     AFTER the dirty data correctly reports 6, which is not a failure.
    UNION ALL
    SELECT 'Reserved dirty-data IDs taken (0 before dirty data)',
           (SELECT COUNT(*) FROM Orders
            WHERE OrderNo IN ('ORD02001','ORD02002'))
         + (SELECT COUNT(*) FROM Delivery
            WHERE DeliveryID IN ('DLV00642','DLV00643'))
         + (SELECT COUNT(*) FROM Returns
            WHERE ReturnID IN ('RET00135','RET00136'))
    FROM dual
    -- 16. Member balances must never have gone negative
    UNION ALL
    SELECT 'Member with a negative points balance',
           COUNT(*) FROM Member WHERE PointsBalance < 0
    -- 17. Every customer must have a cohort year, or check 1 misses them
    UNION ALL
    SELECT 'Customer with no row in gen_customer_cohort',
           COUNT(*)
    FROM   Customer c
    WHERE  NOT EXISTS (SELECT 1 FROM gen_customer_cohort g
                       WHERE g.CustomerID = c.CustomerID)
)
SELECT check_name, failures,
       CASE WHEN failures = 0 THEN 'PASS' ELSE '>> FAIL <<' END AS verdict
FROM   checks
ORDER  BY CASE WHEN failures = 0 THEN 1 ELSE 0 END, check_name;

PROMPT
PROMPT ####################################################################
PROMPT #  SHAPE OF THE DATA - this is what Task 3 will analyse            #
PROMPT ####################################################################

PROMPT
PROMPT === ORDERS AND REVENUE PER YEAR ===
SELECT EXTRACT(YEAR FROM OrderDateTime) AS order_year,
       COUNT(*)                         AS orders,
       COUNT(DISTINCT CustomerID)       AS active_customers,
       COUNT(DISTINCT BranchID)         AS branches_trading,
       ROUND(SUM(TotalAmount), 2)       AS revenue
FROM   Orders
GROUP  BY EXTRACT(YEAR FROM OrderDateTime)
ORDER  BY order_year;

PROMPT
PROMPT === SEASONALITY: TOTAL ORDERS PER CALENDAR MONTH, ALL YEARS ===
PROMPT Expect Jan/Feb (CNY) and Nov/Dec (year end) to lead, Jul/Aug to lag.
SELECT TO_CHAR(OrderDateTime, 'MM')     AS mth,
       TO_CHAR(OrderDateTime, 'Month')  AS month_name,
       COUNT(*)                         AS total_orders
FROM   Orders
GROUP  BY TO_CHAR(OrderDateTime, 'MM'), TO_CHAR(OrderDateTime, 'Month')
ORDER  BY mth;

PROMPT
PROMPT === CHANNEL MIX BY YEAR ===
SELECT EXTRACT(YEAR FROM OrderDateTime) AS order_year,
       COUNT(*) AS orders,
       SUM(CASE WHEN OrderType = 'Online' THEN 1 ELSE 0 END) AS online_orders,
       ROUND(100 * SUM(CASE WHEN OrderType = 'Online' THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS online_pct
FROM   Orders
GROUP  BY EXTRACT(YEAR FROM OrderDateTime)
ORDER  BY order_year;

PROMPT
PROMPT === PROMOTION COVERAGE: ORDER LINES WITH AN ACTIVE PROMOTION ===
PROMPT This is the number that would have been zero for 2016-2023 if the
PROMPT promotion calendar had not been extended.
-- The inner GROUP BY collapses the LEFT JOIN back to one row per order line.
-- Without it an item sitting in two overlapping campaigns would be counted
-- twice and order_lines would be inflated.
SELECT order_year,
       COUNT(*)      AS order_lines,
       SUM(on_promo) AS lines_on_promotion,
       ROUND(100 * SUM(on_promo) / COUNT(*), 1) AS pct_on_promotion
FROM (
    SELECT ord_no, item_id, order_year, MAX(hit) AS on_promo
    FROM (
        SELECT od.OrderNo                         AS ord_no,
               od.ItemID                          AS item_id,
               EXTRACT(YEAR FROM o.OrderDateTime) AS order_year,
               CASE WHEN ap.ItemID IS NULL THEN 0 ELSE 1 END AS hit
        FROM   OrderDetails od
        JOIN   Orders o ON o.OrderNo = od.OrderNo
        LEFT   JOIN ( SELECT DISTINCT ip.ItemID, p.StartDate, p.EndDate
                      FROM   ItemPromotion ip
                      JOIN   Promotion p ON p.PromotionID = ip.PromotionID ) ap
               ON  ap.ItemID = od.ItemID
               AND o.OrderDateTime BETWEEN ap.StartDate AND ap.EndDate
    )
    GROUP BY ord_no, item_id, order_year
)
GROUP  BY order_year
ORDER  BY order_year;

PROMPT
PROMPT ####################################################################
PROMPT #  If every check reads PASS, the source is ready.                 #
PROMPT #  Next: insert_dirty_data.sql, then rebuild the warehouse.        #
PROMPT ####################################################################
SET SQLBLANKLINES OFF
