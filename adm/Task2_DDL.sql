DROP TABLE ReturnDetails    CASCADE CONSTRAINTS;
DROP TABLE Voucher          CASCADE CONSTRAINTS;
DROP TABLE Returns          CASCADE CONSTRAINTS;
DROP TABLE Delivery         CASCADE CONSTRAINTS;
DROP TABLE PointTransaction CASCADE CONSTRAINTS;
DROP TABLE Payment          CASCADE CONSTRAINTS;
DROP TABLE OrderDetails     CASCADE CONSTRAINTS;
DROP TABLE Orders           CASCADE CONSTRAINTS;
DROP TABLE ItemPromotion    CASCADE CONSTRAINTS;
DROP TABLE BranchStock      CASCADE CONSTRAINTS;
DROP TABLE MemberAddress    CASCADE CONSTRAINTS;
DROP TABLE Item             CASCADE CONSTRAINTS;
DROP TABLE Member           CASCADE CONSTRAINTS;
DROP TABLE Promotion        CASCADE CONSTRAINTS;
DROP TABLE ReturnReason     CASCADE CONSTRAINTS;
DROP TABLE DeliveryCompany  CASCADE CONSTRAINTS;
DROP TABLE Customer         CASCADE CONSTRAINTS;
DROP TABLE MembershipType   CASCADE CONSTRAINTS;
DROP TABLE Branch           CASCADE CONSTRAINTS;
DROP TABLE Supplier         CASCADE CONSTRAINTS;
DROP TABLE Category         CASCADE CONSTRAINTS;

-- Sequences must be dropped explicitly (DROP TABLE does not remove them).
-- Re-running this script resets every sequence back to 1, which the coded
-- ID literals in Task3_Inserts_Data.sql depend on.
DROP SEQUENCE seq_customer;
DROP SEQUENCE seq_memberaddress;
DROP SEQUENCE seq_item;
DROP SEQUENCE seq_orders;
DROP SEQUENCE seq_payment;
DROP SEQUENCE seq_delivery;
DROP SEQUENCE seq_returns;
DROP SEQUENCE seq_pointtrans;
DROP SEQUENCE seq_voucher;


-- ============================================================================
-- SECTION 1 : BASE (PARENT) TABLES - no foreign key dependencies
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Category : lookup table for grocery item categories
-- ----------------------------------------------------------------------------
CREATE TABLE Category (
    CategoryID    VARCHAR2(4)
        CONSTRAINT pk_category PRIMARY KEY,
    CategoryName  VARCHAR2(50)   NOT NULL
        CONSTRAINT uq_category_name UNIQUE
);

-- ----------------------------------------------------------------------------
-- 2. Supplier : companies supplying grocery items
-- ----------------------------------------------------------------------------
CREATE TABLE Supplier (
    SupplierID    VARCHAR2(5)
        CONSTRAINT pk_supplier PRIMARY KEY,
    SupplierName  VARCHAR2(100)  NOT NULL,
    ContactNo     VARCHAR2(15)   NOT NULL
        CONSTRAINT chk_supplier_contact
        CHECK (REGEXP_LIKE(ContactNo, '^0[0-9]{1,2}-?[0-9]{7,8}$'))
);

-- ----------------------------------------------------------------------------
-- 3. Branch : 88 Speedmart branches (supports Mandatory Module 4)
-- ----------------------------------------------------------------------------
CREATE TABLE Branch (
    BranchID      VARCHAR2(5)
        CONSTRAINT pk_branch PRIMARY KEY,
    City          VARCHAR2(50)   NOT NULL,
    State         VARCHAR2(30)   NOT NULL
        CONSTRAINT chk_branch_state
        CHECK (State IN ('Johor','Kedah','Kelantan','Melaka','Negeri Sembilan',
                         'Pahang','Perak','Perlis','Pulau Pinang','Sabah',
                         'Sarawak','Selangor','Terengganu','Kuala Lumpur',
                         'Labuan','Putrajaya')),
    ContactNo     VARCHAR2(15)   NOT NULL
);

-- ----------------------------------------------------------------------------
-- 4. MembershipType : Normal (free) vs VIP (RM12.00/year)
-- ----------------------------------------------------------------------------
CREATE TABLE MembershipType (
    MembershipTypeID  VARCHAR2(4)
        CONSTRAINT pk_membershiptype PRIMARY KEY,
    TypeName          VARCHAR2(20)  NOT NULL
        CONSTRAINT uq_membershiptype_name UNIQUE
        CONSTRAINT chk_membershiptype_name
        CHECK (TypeName IN ('Normal','VIP')),
    AnnualFee         NUMBER(6,2)   DEFAULT 0 NOT NULL
        CONSTRAINT chk_membershiptype_fee CHECK (AnnualFee >= 0),
    PointEarnRate     NUMBER(4,2)   DEFAULT 1 NOT NULL
        CONSTRAINT chk_membershiptype_rate CHECK (PointEarnRate > 0)
);

-- ----------------------------------------------------------------------------
-- 5. Customer : every buyer (member or walk-in non-member) is a customer
-- ----------------------------------------------------------------------------
CREATE TABLE Customer (
    CustomerID    VARCHAR2(5)
        CONSTRAINT pk_customer PRIMARY KEY,
    Name          VARCHAR2(100)  NOT NULL,
    ICNo          VARCHAR2(14)
        CONSTRAINT uq_customer_ic UNIQUE
        CONSTRAINT chk_customer_ic
        CHECK (REGEXP_LIKE(ICNo, '^[0-9]{6}-[0-9]{2}-[0-9]{4}$')),
    Email         VARCHAR2(100)
        CONSTRAINT chk_customer_email
        CHECK (REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),
    Status        VARCHAR2(10)   DEFAULT 'Active' NOT NULL
        CONSTRAINT chk_customer_status
        CHECK (Status IN ('Active','Inactive'))
);

-- ----------------------------------------------------------------------------
-- 6. DeliveryCompany : e.g. Grab Grocery, Grocery Panda
-- ----------------------------------------------------------------------------
CREATE TABLE DeliveryCompany (
    DeliveryCompanyID  VARCHAR2(4)
        CONSTRAINT pk_deliverycompany PRIMARY KEY,
    CompanyName        VARCHAR2(100)  NOT NULL
        CONSTRAINT uq_deliverycompany_name UNIQUE,
    ContactNo          VARCHAR2(15)   NOT NULL
);

-- ----------------------------------------------------------------------------
-- 7. ReturnReason : lookup for the Refund/Return module
-- ----------------------------------------------------------------------------
CREATE TABLE ReturnReason (
    ReasonID      VARCHAR2(4)
        CONSTRAINT pk_returnreason PRIMARY KEY,
    ReasonName    VARCHAR2(30)   NOT NULL
        CONSTRAINT uq_returnreason_name UNIQUE
        CONSTRAINT chk_returnreason_name
        CHECK (ReasonName IN ('Missing','Broken','Expired','Wrong Item'))
);

-- ----------------------------------------------------------------------------
-- 8. Promotion : promotion campaigns for grocery items
-- ----------------------------------------------------------------------------
CREATE TABLE Promotion (
    PromotionID    VARCHAR2(5)
        CONSTRAINT pk_promotion PRIMARY KEY,
    PromoName      VARCHAR2(100)  NOT NULL,
    DiscountType   VARCHAR2(12)   NOT NULL
        CONSTRAINT chk_promotion_type
        CHECK (DiscountType IN ('Percentage','Fixed')),
    DiscountValue  NUMBER(6,2)    NOT NULL
        CONSTRAINT chk_promotion_value CHECK (DiscountValue > 0),
    StartDate      DATE           NOT NULL,
    EndDate        DATE           NOT NULL,
    Status         VARCHAR2(10)   DEFAULT 'Active' NOT NULL
        CONSTRAINT chk_promotion_status
        CHECK (Status IN ('Active','Inactive')),
    CONSTRAINT chk_promotion_dates CHECK (EndDate >= StartDate)
);


-- ============================================================================
-- SECTION 2 : TABLES WITH SINGLE-LEVEL DEPENDENCIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 9. Member : subtype of Customer (MemberID is both PK and FK)
-- ----------------------------------------------------------------------------
CREATE TABLE Member (
    MemberID          VARCHAR2(5)
        CONSTRAINT pk_member PRIMARY KEY
        CONSTRAINT fk_member_customer REFERENCES Customer(CustomerID),
    MembershipExpiry  DATE,
    PointsBalance     NUMBER(8)      DEFAULT 0 NOT NULL
        CONSTRAINT chk_member_points CHECK (PointsBalance >= 0),
    MembershipTypeID  VARCHAR2(4)    NOT NULL
        CONSTRAINT fk_member_type REFERENCES MembershipType(MembershipTypeID)
);

-- ----------------------------------------------------------------------------
-- 10. Item : grocery items (Status starts as 'Pending QC' - Assumption 1)
-- ----------------------------------------------------------------------------
CREATE TABLE Item (
    ItemID        VARCHAR2(5)
        CONSTRAINT pk_item PRIMARY KEY,
    ItemName      VARCHAR2(100)  NOT NULL,
    UnitPrice     NUMBER(8,2)    NOT NULL
        CONSTRAINT chk_item_price CHECK (UnitPrice > 0),
    Status        VARCHAR2(12)   DEFAULT 'Pending QC' NOT NULL
        CONSTRAINT chk_item_status
        CHECK (Status IN ('Pending QC','Active','Discontinued')),
    CategoryID    VARCHAR2(4)    NOT NULL
        CONSTRAINT fk_item_category REFERENCES Category(CategoryID),
    SupplierID    VARCHAR2(5)    NOT NULL
        CONSTRAINT fk_item_supplier REFERENCES Supplier(SupplierID)
);

-- ----------------------------------------------------------------------------
-- 11. MemberAddress : saved delivery addresses (required before delivery)
-- ----------------------------------------------------------------------------
CREATE TABLE MemberAddress (
    AddressID     VARCHAR2(5)
        CONSTRAINT pk_memberaddress PRIMARY KEY,
    AddressLine   VARCHAR2(150)  NOT NULL,
    State         VARCHAR2(30)   NOT NULL,
    Postcode      CHAR(5)        NOT NULL
        CONSTRAINT chk_memberaddress_postcode
        CHECK (REGEXP_LIKE(Postcode, '^[0-9]{5}$')),
    MemberID      VARCHAR2(5)    NOT NULL
        CONSTRAINT fk_memberaddress_member
        REFERENCES Member(MemberID) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 12. BranchStock : associative table Branch <-> Item (Mandatory Module 5)
-- ----------------------------------------------------------------------------
CREATE TABLE BranchStock (
    BranchID        VARCHAR2(5)
        CONSTRAINT fk_branchstock_branch
        REFERENCES Branch(BranchID) ON DELETE CASCADE,
    ItemID          VARCHAR2(5)
        CONSTRAINT fk_branchstock_item
        REFERENCES Item(ItemID) ON DELETE CASCADE,
    QuantityOnHand  NUMBER(6)   DEFAULT 0  NOT NULL
        CONSTRAINT chk_branchstock_qoh CHECK (QuantityOnHand >= 0),
    ReorderLevel    NUMBER(6)   DEFAULT 10 NOT NULL
        CONSTRAINT chk_branchstock_reorder CHECK (ReorderLevel >= 0),
    CONSTRAINT pk_branchstock PRIMARY KEY (BranchID, ItemID)
);

-- ----------------------------------------------------------------------------
-- 13. ItemPromotion : associative table Item <-> Promotion
-- ----------------------------------------------------------------------------
CREATE TABLE ItemPromotion (
    ItemID        VARCHAR2(5)
        CONSTRAINT fk_itempromotion_item
        REFERENCES Item(ItemID) ON DELETE CASCADE,
    PromotionID   VARCHAR2(5)
        CONSTRAINT fk_itempromotion_promo
        REFERENCES Promotion(PromotionID) ON DELETE CASCADE,
    PromoPrice    NUMBER(8,2)   NOT NULL
        CONSTRAINT chk_itempromotion_price CHECK (PromoPrice > 0),
    CONSTRAINT pk_itempromotion PRIMARY KEY (ItemID, PromotionID)
);

-- ----------------------------------------------------------------------------
-- 14. Orders : online / walk-in orders (Mandatory Module 2)
--     CustomerID is NOT NULL: walk-in non-members are still stored as
--     Customer records without a Member record (Assumption 2)
--     TotalAmount starts at 0 and is accumulated by trg_orders_total
-- ----------------------------------------------------------------------------
CREATE TABLE Orders (
    OrderNo        VARCHAR2(8)
        CONSTRAINT pk_orders PRIMARY KEY,
    OrderType      VARCHAR2(10)   DEFAULT 'Walk-in' NOT NULL
        CONSTRAINT chk_orders_type
        CHECK (OrderType IN ('Online','Walk-in')),
    OrderDateTime  DATE           DEFAULT SYSDATE NOT NULL,
    TotalAmount    NUMBER(10,2)   DEFAULT 0 NOT NULL
        CONSTRAINT chk_orders_total CHECK (TotalAmount >= 0),
    CustomerID     VARCHAR2(5)    NOT NULL
        CONSTRAINT fk_orders_customer REFERENCES Customer(CustomerID),
    BranchID       VARCHAR2(5)    NOT NULL
        CONSTRAINT fk_orders_branch REFERENCES Branch(BranchID)
);


-- ============================================================================
-- SECTION 3 : TRANSACTION / CHILD TABLES DEPENDING ON ORDERS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 15. OrderDetails : associative table Orders <-> Item
--     UnitPrice is captured at time of sale (Assumption 5) and Subtotal is
--     derived - both are populated by trg_orderdetails_price
-- ----------------------------------------------------------------------------
CREATE TABLE OrderDetails (
    OrderNo       VARCHAR2(8)
        CONSTRAINT fk_orderdetails_order
        REFERENCES Orders(OrderNo) ON DELETE CASCADE,
    ItemID        VARCHAR2(5)
        CONSTRAINT fk_orderdetails_item REFERENCES Item(ItemID),
    Quantity      NUMBER(4)      NOT NULL
        CONSTRAINT chk_orderdetails_qty CHECK (Quantity > 0),
    UnitPrice     NUMBER(8,2)    NOT NULL
        CONSTRAINT chk_orderdetails_price CHECK (UnitPrice >= 0),
    Subtotal      NUMBER(10,2)   NOT NULL,
    CONSTRAINT pk_orderdetails PRIMARY KEY (OrderNo, ItemID),
    CONSTRAINT chk_orderdetails_subtotal
        CHECK (Subtotal = Quantity * UnitPrice)
);

-- ----------------------------------------------------------------------------
-- 16. Payment : one payment record per order (Business Rule 12)
--     Amount is copied from Orders.TotalAmount by trg_payment_amount
-- ----------------------------------------------------------------------------
CREATE TABLE Payment (
    PaymentID     VARCHAR2(8)
        CONSTRAINT pk_payment PRIMARY KEY,
    PaymentDate   DATE           DEFAULT SYSDATE NOT NULL,
    Amount        NUMBER(10,2)   NOT NULL
        CONSTRAINT chk_payment_amount CHECK (Amount > 0),
    Status        VARCHAR2(10)   DEFAULT 'Pending' NOT NULL
        CONSTRAINT chk_payment_status
        CHECK (Status IN ('Pending','Paid','Failed','Refunded')),
    OrderNo       VARCHAR2(8)    NOT NULL
        CONSTRAINT fk_payment_order REFERENCES Orders(OrderNo)
        CONSTRAINT uq_payment_order UNIQUE     -- enforces 1:1 Order-Payment
);

-- ----------------------------------------------------------------------------
-- 17. PointTransaction : Earn references an order; Redeem does not (Rule 14)
--     Earn points are computed by trg_pointtrans_point; Redeem supplies its
--     own Point value
-- ----------------------------------------------------------------------------
CREATE TABLE PointTransaction (
    PointTransID  VARCHAR2(7)
        CONSTRAINT pk_pointtransaction PRIMARY KEY,
    TransType     VARCHAR2(10)   NOT NULL
        CONSTRAINT chk_pointtrans_type
        CHECK (TransType IN ('Earn','Redeem')),
    Point         NUMBER(6)      NOT NULL
        CONSTRAINT chk_pointtrans_point CHECK (Point > 0),
    TransDate     DATE           DEFAULT SYSDATE NOT NULL,
    MemberID      VARCHAR2(5)    NOT NULL
        CONSTRAINT fk_pointtrans_member REFERENCES Member(MemberID),
    OrderNo       VARCHAR2(8)                    -- NULL for redemptions
        CONSTRAINT fk_pointtrans_order REFERENCES Orders(OrderNo),
    CONSTRAINT chk_pointtrans_order
        CHECK ((TransType = 'Earn'   AND OrderNo IS NOT NULL) OR
               (TransType = 'Redeem' AND OrderNo IS NULL))
);

-- ----------------------------------------------------------------------------
-- 18. Delivery : delivery to one of the member's saved addresses only
-- ----------------------------------------------------------------------------
CREATE TABLE Delivery (
    DeliveryID         VARCHAR2(8)
        CONSTRAINT pk_delivery PRIMARY KEY,
    DeliveryCharge     NUMBER(6,2)   DEFAULT 0 NOT NULL
        CONSTRAINT chk_delivery_charge CHECK (DeliveryCharge >= 0),
    DeliveryDate       DATE,                       -- NULL until delivered
    Status             VARCHAR2(15)  DEFAULT 'Pending' NOT NULL
        CONSTRAINT chk_delivery_status
        CHECK (Status IN ('Pending','In Transit','Delivered','Cancelled')),
    OrderNo            VARCHAR2(8)   NOT NULL
        CONSTRAINT fk_delivery_order REFERENCES Orders(OrderNo)
        CONSTRAINT uq_delivery_order UNIQUE,   -- at most one delivery per order
    DeliveryCompanyID  VARCHAR2(4)   NOT NULL
        CONSTRAINT fk_delivery_company
        REFERENCES DeliveryCompany(DeliveryCompanyID),
    AddressID          VARCHAR2(5)   NOT NULL
        CONSTRAINT fk_delivery_address REFERENCES MemberAddress(AddressID)
);

-- ----------------------------------------------------------------------------
-- 19. Returns : return request against one existing order (Rule 16)
--     TotalRefundAmount starts at 0 and is accumulated by trg_returns_total
-- ----------------------------------------------------------------------------
CREATE TABLE Returns (
    ReturnID           VARCHAR2(8)
        CONSTRAINT pk_returns PRIMARY KEY,
    ReturnDate         DATE           DEFAULT SYSDATE NOT NULL,
    Status             VARCHAR2(10)   DEFAULT 'Pending' NOT NULL
        CONSTRAINT chk_returns_status
        CHECK (Status IN ('Pending','Approved','Rejected','Refunded')),
    TotalRefundAmount  NUMBER(10,2)   DEFAULT 0 NOT NULL
        CONSTRAINT chk_returns_amount CHECK (TotalRefundAmount >= 0),
    OrderNo            VARCHAR2(8)    NOT NULL
        CONSTRAINT fk_returns_order REFERENCES Orders(OrderNo)
);

-- ----------------------------------------------------------------------------
-- 20. Voucher : issued via point redemption (Rule 15), applied to at most
--     one future order (Rule 21, Assumption 6)
-- ----------------------------------------------------------------------------
CREATE TABLE Voucher (
    VoucherID     VARCHAR2(8)
        CONSTRAINT pk_voucher PRIMARY KEY,
    VoucherType   VARCHAR2(15)   NOT NULL
        CONSTRAINT chk_voucher_type
        CHECK (VoucherType IN ('Discount','Free Delivery')),
    Value         NUMBER(6,2)    NOT NULL
        CONSTRAINT chk_voucher_value CHECK (Value > 0),
    ExpiryDate    DATE           NOT NULL,
    Status        VARCHAR2(10)   DEFAULT 'Active' NOT NULL
        CONSTRAINT chk_voucher_status
        CHECK (Status IN ('Active','Used','Expired')),
    MemberID      VARCHAR2(5)    NOT NULL
        CONSTRAINT fk_voucher_member REFERENCES Member(MemberID),
    OrderNo       VARCHAR2(8)
        CONSTRAINT fk_voucher_order REFERENCES Orders(OrderNo),
    PointTransID  VARCHAR2(7)
        CONSTRAINT fk_voucher_pointtrans
        REFERENCES PointTransaction(PointTransID)
        CONSTRAINT uq_voucher_pointtrans UNIQUE
);

-- ----------------------------------------------------------------------------
-- 21. ReturnDetails : each return line references the exact purchased
--     order line via composite FK (OrderNo, ItemID) -> OrderDetails (Rule 17)
--     RefundAmount is computed by trg_returndetails_refund
-- ----------------------------------------------------------------------------
CREATE TABLE ReturnDetails (
    ReturnID          VARCHAR2(8)
        CONSTRAINT fk_returndetails_return
        REFERENCES Returns(ReturnID) ON DELETE CASCADE,
    OrderNo           VARCHAR2(8),
    ItemID            VARCHAR2(5),
    QuantityReturned  NUMBER(4)     NOT NULL
        CONSTRAINT chk_returndetails_qty CHECK (QuantityReturned > 0),
    RefundAmount      NUMBER(10,2)  NOT NULL
        CONSTRAINT chk_returndetails_amount CHECK (RefundAmount >= 0),
    ReasonID          VARCHAR2(4)   NOT NULL
        CONSTRAINT fk_returndetails_reason
        REFERENCES ReturnReason(ReasonID),
    CONSTRAINT pk_returndetails PRIMARY KEY (ReturnID, OrderNo, ItemID),
    CONSTRAINT fk_returndetails_orderline
        FOREIGN KEY (OrderNo, ItemID)
        REFERENCES OrderDetails(OrderNo, ItemID)
);


-- ============================================================================
-- SECTION 4 : SEQUENCES - generate the coded primary keys used in Task 3
--   'C'   || LPAD(seq_customer.NEXTVAL,      4, '0')  ->  C0001 .. C1000
--   'A'   || LPAD(seq_memberaddress.NEXTVAL, 4, '0')  ->  A0001 ..
--   'I'   || LPAD(seq_item.NEXTVAL,          4, '0')  ->  I0001 ..
--   'ORD' || LPAD(seq_orders.NEXTVAL,        5, '0')  ->  ORD00001 ..
--   'PAY' || LPAD(seq_payment.NEXTVAL,       5, '0')  ->  PAY00001 ..
--   'DLV' || LPAD(seq_delivery.NEXTVAL,      5, '0')  ->  DLV00001 ..
--   'RET' || LPAD(seq_returns.NEXTVAL,       5, '0')  ->  RET00001 ..
--   'PT'  || LPAD(seq_pointtrans.NEXTVAL,    5, '0')  ->  PT00001 ..
--   'VCH' || LPAD(seq_voucher.NEXTVAL,       5, '0')  ->  VCH00001 ..
--
-- NOCACHE is REQUIRED, not cosmetic: Task 3 hardcodes these generated values
-- as foreign keys (e.g. Member.MemberID = 'C0001', OrderDetails.OrderNo =
-- 'ORD00001'). A cached sequence may leave gaps, which would shift every
-- generated ID and break those references with ORA-02291.
-- ============================================================================

CREATE SEQUENCE seq_customer      START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_memberaddress START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_item          START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_orders        START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_payment       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_delivery      START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_returns       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_pointtrans    START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE seq_voucher       START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;


-- ============================================================================
-- SECTION 5 : TRIGGERS - calculate every derived value
--   The INSERT statements in Task 3 deliberately omit these columns:
--     OrderDetails.UnitPrice / Subtotal   Orders.TotalAmount
--     Payment.Amount                      ReturnDetails.RefundAmount
--     Returns.TotalRefundAmount           PointTransaction.Point (Earn only)
--     Member.PointsBalance
-- ============================================================================

-- ----------------------------------------------------------------------------
-- T1. Price each order line from the item's current price (Assumption 5)
--     and derive Subtotal, satisfying chk_orderdetails_subtotal exactly.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_orderdetails_price
    BEFORE INSERT ON OrderDetails
    FOR EACH ROW
BEGIN
    SELECT i.UnitPrice
      INTO :NEW.UnitPrice
      FROM Item i
     WHERE i.ItemID = :NEW.ItemID;

    :NEW.Subtotal := :NEW.Quantity * :NEW.UnitPrice;
END;
/

-- ----------------------------------------------------------------------------
-- T2. Accumulate the order total as each line is inserted.
--     Orders.TotalAmount starts at its DEFAULT of 0.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_orders_total
    AFTER INSERT ON OrderDetails
    FOR EACH ROW
BEGIN
    UPDATE Orders
       SET TotalAmount = TotalAmount + :NEW.Subtotal
     WHERE OrderNo = :NEW.OrderNo;
END;
/

-- ----------------------------------------------------------------------------
-- T3. A payment always settles the full order total (Business Rule 12).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_payment_amount
    BEFORE INSERT ON Payment
    FOR EACH ROW
BEGIN
    SELECT o.TotalAmount
      INTO :NEW.Amount
      FROM Orders o
     WHERE o.OrderNo = :NEW.OrderNo;
END;
/

-- ----------------------------------------------------------------------------
-- T4. Refund the returned quantity at the price actually paid on that
--     order line (Rule 17).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_returndetails_refund
    BEFORE INSERT ON ReturnDetails
    FOR EACH ROW
DECLARE
    v_unitprice  OrderDetails.UnitPrice%TYPE;
BEGIN
    SELECT d.UnitPrice
      INTO v_unitprice
      FROM OrderDetails d
     WHERE d.OrderNo = :NEW.OrderNo
       AND d.ItemID  = :NEW.ItemID;

    :NEW.RefundAmount := :NEW.QuantityReturned * v_unitprice;
END;
/

-- ----------------------------------------------------------------------------
-- T5. Accumulate the return total as each return line is inserted.
--     Returns.TotalRefundAmount starts at its DEFAULT of 0.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_returns_total
    AFTER INSERT ON ReturnDetails
    FOR EACH ROW
BEGIN
    UPDATE Returns
       SET TotalRefundAmount = TotalRefundAmount + :NEW.RefundAmount
     WHERE ReturnID = :NEW.ReturnID;
END;
/

-- ----------------------------------------------------------------------------
-- T6. Earn points = order total x the member's PointEarnRate, rounded down
--     (Normal = 1.00/RM, VIP = 2.00/RM).  Redeem rows carry their own Point
--     value and are left untouched.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_pointtrans_point
    BEFORE INSERT ON PointTransaction
    FOR EACH ROW
BEGIN
    IF :NEW.TransType = 'Earn' THEN
        SELECT FLOOR(o.TotalAmount * mt.PointEarnRate)
          INTO :NEW.Point
          FROM Orders o, Member m, MembershipType mt
         WHERE o.OrderNo           = :NEW.OrderNo
           AND m.MemberID          = :NEW.MemberID
           AND mt.MembershipTypeID = m.MembershipTypeID;

        -- chk_pointtrans_point requires Point > 0
        IF :NEW.Point < 1 THEN
            :NEW.Point := 1;
        END IF;
    END IF;
END;
/

-- ----------------------------------------------------------------------------
-- T7. Keep Member.PointsBalance in step with every point transaction.
--     PointsBalance starts at its DEFAULT of 0.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_member_balance
    AFTER INSERT ON PointTransaction
    FOR EACH ROW
BEGIN
    IF :NEW.TransType = 'Earn' THEN
        UPDATE Member
           SET PointsBalance = PointsBalance + :NEW.Point
         WHERE MemberID = :NEW.MemberID;
    ELSE
        UPDATE Member
           SET PointsBalance = PointsBalance - :NEW.Point
         WHERE MemberID = :NEW.MemberID;
    END IF;
END;
/
