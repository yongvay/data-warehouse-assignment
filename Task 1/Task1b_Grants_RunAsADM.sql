-- ============================================================================
--  BMIT3003 DATA WAREHOUSE TECHNOLOGY - ASSIGNMENT
--  CROSS-USER PRIVILEGES  (prerequisite for Task 2 ETL)
-- ----------------------------------------------------------------------------
--  RUN THIS AS THE OPERATIONAL (ADM) USER, NOT AS DW.
--
--  The warehouse declares no foreign key into the operational schema, but the
--  ETL in Task 2 must still READ that schema.  These grants give the DW user
--  read-only access to the 18 source tables the warehouse is loaded from.
--
--  Replace  dw  below if your warehouse user is named differently.
--
--  Not granted, because they are out of scope for the warehouse:
--      BranchStock, Payment, Voucher
-- ============================================================================

-- Dimension sources -----------------------------------------------------------
GRANT SELECT ON Customer         TO dw;
GRANT SELECT ON Member           TO dw;
GRANT SELECT ON MembershipType   TO dw;
GRANT SELECT ON Item             TO dw;
GRANT SELECT ON Category         TO dw;
GRANT SELECT ON Supplier         TO dw;
GRANT SELECT ON Branch           TO dw;
GRANT SELECT ON MemberAddress    TO dw;
GRANT SELECT ON Promotion        TO dw;
GRANT SELECT ON ReturnReason     TO dw;
GRANT SELECT ON DeliveryCompany  TO dw;

-- Fact sources ----------------------------------------------------------------
GRANT SELECT ON Orders           TO dw;
GRANT SELECT ON OrderDetails     TO dw;
GRANT SELECT ON ItemPromotion    TO dw;
GRANT SELECT ON Returns          TO dw;
GRANT SELECT ON ReturnDetails    TO dw;
GRANT SELECT ON Delivery         TO dw;
GRANT SELECT ON PointTransaction TO dw;


-- ============================================================================
--  OPTIONAL - RUN THIS PART AS THE DW USER
--
--  Private synonyms let the ETL in Task 2 write  SELECT ... FROM Orders
--  instead of  SELECT ... FROM adm.Orders  , which keeps the load scripts
--  readable and means the schema name appears in exactly one place.
--
--  Replace  adm  with the actual operational username.
-- ============================================================================

-- CREATE SYNONYM Customer         FOR adm.Customer;
-- CREATE SYNONYM Member           FOR adm.Member;
-- CREATE SYNONYM MembershipType   FOR adm.MembershipType;
-- CREATE SYNONYM Item             FOR adm.Item;
-- CREATE SYNONYM Category         FOR adm.Category;
-- CREATE SYNONYM Supplier         FOR adm.Supplier;
-- CREATE SYNONYM Branch           FOR adm.Branch;
-- CREATE SYNONYM MemberAddress    FOR adm.MemberAddress;
-- CREATE SYNONYM Promotion        FOR adm.Promotion;
-- CREATE SYNONYM ReturnReason     FOR adm.ReturnReason;
-- CREATE SYNONYM DeliveryCompany  FOR adm.DeliveryCompany;
-- CREATE SYNONYM Orders           FOR adm.Orders;
-- CREATE SYNONYM OrderDetails     FOR adm.OrderDetails;
-- CREATE SYNONYM ItemPromotion    FOR adm.ItemPromotion;
-- CREATE SYNONYM Returns          FOR adm.Returns;
-- CREATE SYNONYM ReturnDetails    FOR adm.ReturnDetails;
-- CREATE SYNONYM Delivery         FOR adm.Delivery;
-- CREATE SYNONYM PointTransaction FOR adm.PointTransaction;


-- ============================================================================
--  VERIFY  - run as DW after the grants above
-- ============================================================================
-- SELECT owner, table_name
-- FROM   all_tables
-- WHERE  owner = 'ADM'
-- ORDER  BY table_name;
