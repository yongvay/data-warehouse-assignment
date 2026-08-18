-- ============================================================================
--  BMIT3003 DATA WAREHOUSE TECHNOLOGY - ASSIGNMENT
--  TASK 1(b) : PHYSICAL DESIGN
--  System    : 88 Speedmart Grocery - Sales, Returns, Delivery & Loyalty
--              Data Warehouse
--  DBMS      : Oracle
-- ----------------------------------------------------------------------------
--  STRUCTURE : 8 dimension tables + 4 fact tables (fact constellation)
--              CUSTOMER_DIM is a Slowly Changing Dimension Type 2.
--
--  CONVENTION: The warehouse is created in the SAME Oracle schema as the
--              operational tables built by Task2_DDL.sql.  Every dimension
--              therefore keeps its operational identifier and declares it as
--              a FOREIGN KEY back to the source table, and every fact keeps
--              the operational transaction number and declares it as a
--              FOREIGN KEY back to its source table.  This follows the
--              convention used in the 1.2 Physical Design sample.
--
--  NAMING    : snake_case for surrogate keys and ETL audit columns
--              camelCase for columns carried across from the source system
--
--  NOTE ON NULLABLE SOURCE IDs
--              The operational identifier in each dimension is deliberately
--              declared without NOT NULL.  Each dimension is seeded with one
--              "Unknown" row (key = -1) that has no counterpart in the
--              operational system; because the column carries a FOREIGN KEY
--              to that system, the seeded row must hold NULL.  Every row
--              loaded by the ETL carries a real identifier.
-- ============================================================================


-- ----------------------------------------------------------------------------
--  Drop in reverse dependency order so the script can be re-run
-- ----------------------------------------------------------------------------
DROP TABLE point_fact            CASCADE CONSTRAINTS;
DROP TABLE delivery_fact         CASCADE CONSTRAINTS;
DROP TABLE return_fact           CASCADE CONSTRAINTS;
DROP TABLE sales_fact            CASCADE CONSTRAINTS;
DROP TABLE delivery_company_dim  CASCADE CONSTRAINTS;
DROP TABLE return_reason_dim     CASCADE CONSTRAINTS;
DROP TABLE promotion_dim         CASCADE CONSTRAINTS;
DROP TABLE address_dim           CASCADE CONSTRAINTS;
DROP TABLE branch_dim            CASCADE CONSTRAINTS;
DROP TABLE item_dim              CASCADE CONSTRAINTS;
DROP TABLE customer_dim          CASCADE CONSTRAINTS;
DROP TABLE date_dim              CASCADE CONSTRAINTS;


-- ============================================================================
--  SECTION 1 : DIMENSION TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
--  1. DATE_DIM  (Slowly Changing Dimension Type 0 - generated calendar)
--     Role-playing: referenced as order date, return date, delivery date and
--     point transaction date.  date_key is a "smart key" in YYYYMMDD form.
--     Seeded row: date_key = -1  ('Unknown', cal_date = 1900-01-01), used by
--     DELIVERY_FACT for deliveries that have not yet been despatched.
--     No FOREIGN KEY to the source: the calendar is generated, not extracted.
-- ----------------------------------------------------------------------------
CREATE TABLE date_dim
(
    date_key           NUMBER(8)     NOT NULL,
    cal_date           DATE          NOT NULL,
    full_desc          VARCHAR2(50)  NOT NULL,
    day_week           VARCHAR2(10)  NOT NULL,
    day_num_month      NUMBER(2)     NOT NULL,
    day_num_year       NUMBER(3)     NOT NULL,
    last_day_ind       CHAR(1)       DEFAULT 'N' NOT NULL,
    cal_week_end_date  DATE          NOT NULL,
    cal_week_year      NUMBER(2)     NOT NULL,
    cal_month_name     VARCHAR2(15)  NOT NULL,
    cal_month_year     NUMBER(2)     NOT NULL,
    cal_year_month     CHAR(7)       NOT NULL,
    cal_quarter        CHAR(2)       NOT NULL,
    cal_year_quarter   CHAR(7)       NOT NULL,
    cal_year           NUMBER(4)     NOT NULL,
    holiday_ind        CHAR(1)       DEFAULT 'N'    NOT NULL,
    weekday_ind        CHAR(1)       DEFAULT 'Y'    NOT NULL,
    festive_event      VARCHAR2(50)  DEFAULT 'None' NOT NULL,
    etl_batch_id       NUMBER(8)     NOT NULL,
    etl_load_dt        DATE          DEFAULT SYSDATE NOT NULL,
    etl_update_dt      DATE,
    dq_flag            CHAR(1)       DEFAULT 'V'    NOT NULL,
    CONSTRAINT date_dim_pk PRIMARY KEY (date_key),
    CONSTRAINT chk_date_dim_lastday CHECK (last_day_ind IN ('Y','N')),
    CONSTRAINT chk_date_dim_holiday CHECK (holiday_ind  IN ('Y','N')),
    CONSTRAINT chk_date_dim_weekday CHECK (weekday_ind  IN ('Y','N')),
    CONSTRAINT chk_date_dim_quarter CHECK (cal_quarter  IN ('Q1','Q2','Q3','Q4')),
    CONSTRAINT chk_date_dim_dqflag  CHECK (dq_flag      IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
--  2. CUSTOMER_DIM  ***  SLOWLY CHANGING DIMENSION TYPE 2  ***
--     Source : Customer + Member + MembershipType
--     Member is a 1:1 subtype of Customer, so members and walk-in non-members
--     share one dimension and are separated by memberFlag.
--
--     Type 2 (a new version row is created)  : customerStatus, memberFlag,
--                                              membershipType
--     Type 1 (the existing row is overwritten): customerName, customerICNo,
--                                              customerEmail, membershipExpiry
--
--     customerID is intentionally NOT unique on its own - one customer has
--     many versions.  Uniqueness is (customerID, effective_start_date).
--
--     Member.PointsBalance is deliberately excluded: it changes on every
--     transaction and would create a new version row per order.  The balance
--     is obtained instead by summing POINT_FACT.netPoints.
-- ----------------------------------------------------------------------------
CREATE TABLE customer_dim
(
    customer_key          NUMBER(10)    NOT NULL,
    customerID            VARCHAR2(5),
    customerName          VARCHAR2(100) DEFAULT 'Unknown'    NOT NULL,
    customerICNo          VARCHAR2(14)  DEFAULT 'Unknown'    NOT NULL,
    customerEmail         VARCHAR2(100) DEFAULT 'Unknown'    NOT NULL,
    customerStatus        VARCHAR2(10)  DEFAULT 'Unknown'    NOT NULL,
    memberFlag            CHAR(1)       DEFAULT 'N'          NOT NULL,
    membershipType        VARCHAR2(20)  DEFAULT 'Non-Member' NOT NULL,
    annualFee             NUMBER(6,2)   DEFAULT 0            NOT NULL,
    pointEarnRate         NUMBER(4,2)   DEFAULT 0            NOT NULL,
    membershipExpiry      DATE,
    effective_start_date  DATE          NOT NULL,
    effective_end_date    DATE          DEFAULT DATE '9999-12-31' NOT NULL,
    is_current_flag       CHAR(1)       DEFAULT 'Y'          NOT NULL,
    version_no            NUMBER(4)     DEFAULT 1            NOT NULL,
    etl_batch_id          NUMBER(8)     NOT NULL,
    etl_load_dt           DATE          DEFAULT SYSDATE      NOT NULL,
    etl_update_dt         DATE,
    dq_flag               CHAR(1)       DEFAULT 'V'          NOT NULL,
    CONSTRAINT customer_dim_pk PRIMARY KEY (customer_key),
    CONSTRAINT customer_dim_customerid_fk
        FOREIGN KEY (customerID) REFERENCES Customer (CustomerID),
    CONSTRAINT customer_dim_version_uq
        UNIQUE (customerID, effective_start_date),
    CONSTRAINT chk_customer_dim_status
        CHECK (customerStatus IN ('Active','Inactive','Unknown')),
    CONSTRAINT chk_customer_dim_memberflag
        CHECK (memberFlag IN ('Y','N')),
    CONSTRAINT chk_customer_dim_type
        CHECK (membershipType IN ('Normal','VIP','Non-Member','Unknown')),
    CONSTRAINT chk_customer_dim_current
        CHECK (is_current_flag IN ('Y','N')),
    CONSTRAINT chk_customer_dim_fee     CHECK (annualFee     >= 0),
    CONSTRAINT chk_customer_dim_rate    CHECK (pointEarnRate >= 0),
    CONSTRAINT chk_customer_dim_version CHECK (version_no    >= 1),
    CONSTRAINT chk_customer_dim_dates
        CHECK (effective_end_date >= effective_start_date),
    CONSTRAINT chk_customer_dim_dqflag  CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
--  3. ITEM_DIM  (Type 1)
--     Source : Item + Category + Supplier
--     Item -> Category and Item -> Supplier are both many-to-one, so both are
--     flattened into this dimension rather than snowflaked.
--     categoryID and supplierID are retained because Supplier.SupplierName
--     carries no UNIQUE constraint in the source and therefore cannot safely
--     be used on its own as a grouping key in Task 3.
-- ----------------------------------------------------------------------------
CREATE TABLE item_dim
(
    item_key           NUMBER(10)    NOT NULL,
    itemID             VARCHAR2(5),
    itemName           VARCHAR2(100) DEFAULT 'Unknown' NOT NULL,
    itemUnitPrice      NUMBER(8,2)   DEFAULT 0         NOT NULL,
    itemStatus         VARCHAR2(12)  DEFAULT 'Unknown' NOT NULL,
    categoryID         VARCHAR2(4)   DEFAULT 'UNKN'    NOT NULL,
    categoryName       VARCHAR2(50)  DEFAULT 'Unknown' NOT NULL,
    supplierID         VARCHAR2(5)   DEFAULT 'UNKN'    NOT NULL,
    supplierName       VARCHAR2(100) DEFAULT 'Unknown' NOT NULL,
    supplierContactNo  VARCHAR2(15)  DEFAULT 'Unknown' NOT NULL,
    etl_batch_id       NUMBER(8)     NOT NULL,
    etl_load_dt        DATE          DEFAULT SYSDATE   NOT NULL,
    etl_update_dt      DATE,
    dq_flag            CHAR(1)       DEFAULT 'V'       NOT NULL,
    CONSTRAINT item_dim_pk PRIMARY KEY (item_key),
    CONSTRAINT item_dim_itemid_fk
        FOREIGN KEY (itemID) REFERENCES Item (ItemID),
    CONSTRAINT item_dim_itemid_uq UNIQUE (itemID),
    CONSTRAINT chk_item_dim_status
        CHECK (itemStatus IN ('Pending QC','Active','Discontinued','Unknown')),
    CONSTRAINT chk_item_dim_price  CHECK (itemUnitPrice >= 0),
    CONSTRAINT chk_item_dim_dqflag CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
--  4. BRANCH_DIM  (Type 1)
--     Source : Branch  (BranchID, City, State, ContactNo only)
--     branchName  is derived  : branchCity || ' Branch'
--     branchRegion is derived : Northern      = Perlis, Kedah, Pulau Pinang, Perak
--                               Central       = Selangor, Kuala Lumpur,
--                                               Putrajaya, Negeri Sembilan
--                               Southern      = Melaka, Johor
--                               East Coast    = Pahang, Terengganu, Kelantan
--                               East Malaysia = Sabah, Sarawak, Labuan
--     Seeded row branch_key = -1 ('Unknown / Not Applicable') is used by
--     POINT_FACT for point redemptions, which carry no order and therefore
--     no branch.
-- ----------------------------------------------------------------------------
CREATE TABLE branch_dim
(
    branch_key       NUMBER(10)    NOT NULL,
    branchID         VARCHAR2(5),
    branchName       VARCHAR2(60)  DEFAULT 'Unknown' NOT NULL,
    branchCity       VARCHAR2(50)  DEFAULT 'Unknown' NOT NULL,
    branchState      VARCHAR2(30)  DEFAULT 'Unknown' NOT NULL,
    branchRegion     VARCHAR2(20)  DEFAULT 'Unknown' NOT NULL,
    branchContactNo  VARCHAR2(15)  DEFAULT 'Unknown' NOT NULL,
    etl_batch_id     NUMBER(8)     NOT NULL,
    etl_load_dt      DATE          DEFAULT SYSDATE   NOT NULL,
    etl_update_dt    DATE,
    dq_flag          CHAR(1)       DEFAULT 'V'       NOT NULL,
    CONSTRAINT branch_dim_pk PRIMARY KEY (branch_key),
    CONSTRAINT branch_dim_branchid_fk
        FOREIGN KEY (branchID) REFERENCES Branch (BranchID),
    CONSTRAINT branch_dim_branchid_uq UNIQUE (branchID),
    CONSTRAINT chk_branch_dim_region
        CHECK (branchRegion IN ('Northern','Central','Southern',
                                'East Coast','East Malaysia','Unknown')),
    CONSTRAINT chk_branch_dim_dqflag CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
--  5. ADDRESS_DIM  (Type 1)  -  ship-to geography for DELIVERY_FACT
--     Source : MemberAddress  (AddressLine, State, Postcode)
--     MemberAddress holds no City column, so addressRegion is derived from
--     addressState using the same mapping as BRANCH_DIM.  This lets a report
--     compare the branch that sold an order with the state it shipped to.
-- ----------------------------------------------------------------------------
CREATE TABLE address_dim
(
    address_key       NUMBER(10)    NOT NULL,
    addressID         VARCHAR2(5),
    addressLine       VARCHAR2(150) DEFAULT 'Unknown' NOT NULL,
    addressState      VARCHAR2(30)  DEFAULT 'Unknown' NOT NULL,
    addressPostcode   CHAR(5)       DEFAULT '00000'   NOT NULL,
    addressRegion     VARCHAR2(20)  DEFAULT 'Unknown' NOT NULL,
    etl_batch_id      NUMBER(8)     NOT NULL,
    etl_load_dt       DATE          DEFAULT SYSDATE   NOT NULL,
    etl_update_dt     DATE,
    dq_flag           CHAR(1)       DEFAULT 'V'       NOT NULL,
    CONSTRAINT address_dim_pk PRIMARY KEY (address_key),
    CONSTRAINT address_dim_addressid_fk
        FOREIGN KEY (addressID) REFERENCES MemberAddress (AddressID),
    CONSTRAINT address_dim_addressid_uq UNIQUE (addressID),
    CONSTRAINT chk_address_dim_region
        CHECK (addressRegion IN ('Northern','Central','Southern',
                                 'East Coast','East Malaysia','Unknown')),
    CONSTRAINT chk_address_dim_dqflag CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
--  6. PROMOTION_DIM  (Type 1)
--     Source : Promotion
--     Two rows are seeded and must be distinguished:
--         promo_key =  0  'No Promotion'  - the sale genuinely had no promotion
--         promo_key = -1  'Unknown'       - the promotion reference was dirty
--                                           and could not be resolved
--     ItemPromotion.PromoPrice is item-specific and therefore belongs at fact
--     grain; it is used by the ETL to derive SALES_FACT.discountAmt and is not
--     stored in this dimension.
-- ----------------------------------------------------------------------------
CREATE TABLE promotion_dim
(
    promo_key          NUMBER(10)    NOT NULL,
    promotionID        VARCHAR2(5),
    promoName          VARCHAR2(100) DEFAULT 'No Promotion' NOT NULL,
    discountType       VARCHAR2(12)  DEFAULT 'None'         NOT NULL,
    discountValue      NUMBER(6,2)   DEFAULT 0              NOT NULL,
    promoStartDate     DATE          DEFAULT DATE '1900-01-01' NOT NULL,
    promoEndDate       DATE          DEFAULT DATE '9999-12-31' NOT NULL,
    promoStatus        VARCHAR2(10)  DEFAULT 'None'         NOT NULL,
    promoDurationDays  NUMBER(6)     DEFAULT 0              NOT NULL,
    etl_batch_id       NUMBER(8)     NOT NULL,
    etl_load_dt        DATE          DEFAULT SYSDATE        NOT NULL,
    etl_update_dt      DATE,
    dq_flag            CHAR(1)       DEFAULT 'V'            NOT NULL,
    CONSTRAINT promotion_dim_pk PRIMARY KEY (promo_key),
    CONSTRAINT promotion_dim_promotionid_fk
        FOREIGN KEY (promotionID) REFERENCES Promotion (PromotionID),
    CONSTRAINT promotion_dim_promotionid_uq UNIQUE (promotionID),
    CONSTRAINT chk_promotion_dim_type
        CHECK (discountType IN ('Percentage','Fixed','None','Unknown')),
    CONSTRAINT chk_promotion_dim_status
        CHECK (promoStatus IN ('Active','Inactive','None','Unknown')),
    CONSTRAINT chk_promotion_dim_value    CHECK (discountValue     >= 0),
    CONSTRAINT chk_promotion_dim_duration CHECK (promoDurationDays >= 0),
    CONSTRAINT chk_promotion_dim_dates    CHECK (promoEndDate >= promoStartDate),
    CONSTRAINT chk_promotion_dim_dqflag   CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
--  7. RETURN_REASON_DIM  (Type 1)
--     Source : ReturnReason
--     reasonCategory is derived so that management can separate causes the
--     business controls from causes it does not:
--         'Fulfilment'      = Missing, Wrong Item   (picking / despatch error)
--         'Product Quality' = Broken, Expired       (stock or supplier issue)
-- ----------------------------------------------------------------------------
CREATE TABLE return_reason_dim
(
    reason_key      NUMBER(10)   NOT NULL,
    reasonID        VARCHAR2(4),
    reasonName      VARCHAR2(30) DEFAULT 'Unknown' NOT NULL,
    reasonCategory  VARCHAR2(20) DEFAULT 'Unknown' NOT NULL,
    etl_batch_id    NUMBER(8)    NOT NULL,
    etl_load_dt     DATE         DEFAULT SYSDATE   NOT NULL,
    etl_update_dt   DATE,
    dq_flag         CHAR(1)      DEFAULT 'V'       NOT NULL,
    CONSTRAINT return_reason_dim_pk PRIMARY KEY (reason_key),
    CONSTRAINT return_reason_dim_reasonid_fk
        FOREIGN KEY (reasonID) REFERENCES ReturnReason (ReasonID),
    CONSTRAINT return_reason_dim_reasonid_uq UNIQUE (reasonID),
    CONSTRAINT chk_return_reason_dim_name
        CHECK (reasonName IN ('Missing','Broken','Expired','Wrong Item','Unknown')),
    CONSTRAINT chk_return_reason_dim_cat
        CHECK (reasonCategory IN ('Fulfilment','Product Quality','Unknown')),
    CONSTRAINT chk_return_reason_dim_dqflag CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
--  8. DELIVERY_COMPANY_DIM  (Type 1)
--     Source : DeliveryCompany
-- ----------------------------------------------------------------------------
CREATE TABLE delivery_company_dim
(
    delivery_company_key  NUMBER(10)    NOT NULL,
    deliveryCompanyID     VARCHAR2(4),
    companyName           VARCHAR2(100) DEFAULT 'Unknown' NOT NULL,
    companyContactNo      VARCHAR2(15)  DEFAULT 'Unknown' NOT NULL,
    etl_batch_id          NUMBER(8)     NOT NULL,
    etl_load_dt           DATE          DEFAULT SYSDATE   NOT NULL,
    etl_update_dt         DATE,
    dq_flag               CHAR(1)       DEFAULT 'V'       NOT NULL,
    CONSTRAINT delivery_company_dim_pk PRIMARY KEY (delivery_company_key),
    CONSTRAINT delivery_company_dim_id_fk
        FOREIGN KEY (deliveryCompanyID)
        REFERENCES DeliveryCompany (DeliveryCompanyID),
    CONSTRAINT delivery_company_dim_id_uq UNIQUE (deliveryCompanyID),
    CONSTRAINT chk_dlv_company_dim_dqflag CHECK (dq_flag IN ('V','S','D'))
);


-- ============================================================================
--  SECTION 2 : FACT TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
--  9. SALES_FACT   (Transaction fact)
--     GRAIN  : one row per item line per order
--     SOURCE : OrderDetails, joined to Orders and ItemPromotion
--
--     Measures
--       quantity      additive
--       unitPrice     non-additive  (average it, never sum it)
--       grossSalesAmt additive      = quantity * unitPrice
--       discountAmt   additive      = (unitPrice - PromoPrice) * quantity,
--                                     0 when no promotion applies
--       netSalesAmt   additive      = grossSalesAmt - discountAmt
--
--     sales_fact_grain_uq enforces the declared grain.  It is required
--     because CUSTOMER_DIM is Type 2: if an order were re-read after the
--     customer changed version, the composite primary key alone would accept
--     the same order line a second time under a new customer_key and revenue
--     would be double counted.
--
--     Cost and gross-profit measures are omitted: the operational system
--     records no cost column anywhere.  Profitability is analysed through
--     discount leakage and net-of-returns revenue instead.
-- ----------------------------------------------------------------------------
CREATE TABLE sales_fact
(
    order_date_key  NUMBER(8)     NOT NULL,
    customer_key    NUMBER(10)    NOT NULL,
    item_key        NUMBER(10)    NOT NULL,
    branch_key      NUMBER(10)    NOT NULL,
    promo_key       NUMBER(10)    NOT NULL,
    orderNo         VARCHAR2(8)   NOT NULL,
    orderType       VARCHAR2(10)  NOT NULL,
    orderHour       NUMBER(2)     NOT NULL,
    quantity        NUMBER(4)     NOT NULL,
    unitPrice       NUMBER(8,2)   NOT NULL,
    grossSalesAmt   NUMBER(10,2)  NOT NULL,
    discountAmt     NUMBER(10,2)  DEFAULT 0 NOT NULL,
    netSalesAmt     NUMBER(10,2)  NOT NULL,
    etl_batch_id    NUMBER(8)     NOT NULL,
    etl_load_dt     DATE          DEFAULT SYSDATE NOT NULL,
    etl_update_dt   DATE,
    dq_flag         CHAR(1)       DEFAULT 'V' NOT NULL,
    CONSTRAINT sales_fact_pk PRIMARY KEY
        (order_date_key, customer_key, item_key, branch_key, promo_key, orderNo),
    CONSTRAINT sf_date_fk     FOREIGN KEY (order_date_key)
                              REFERENCES date_dim (date_key),
    CONSTRAINT sf_customer_fk FOREIGN KEY (customer_key)
                              REFERENCES customer_dim (customer_key),
    CONSTRAINT sf_item_fk     FOREIGN KEY (item_key)
                              REFERENCES item_dim (item_key),
    CONSTRAINT sf_branch_fk   FOREIGN KEY (branch_key)
                              REFERENCES branch_dim (branch_key),
    CONSTRAINT sf_promo_fk    FOREIGN KEY (promo_key)
                              REFERENCES promotion_dim (promo_key),
    CONSTRAINT sf_orderno_fk  FOREIGN KEY (orderNo)
                              REFERENCES Orders (OrderNo),
    CONSTRAINT sales_fact_grain_uq UNIQUE (orderNo, item_key),
    CONSTRAINT chk_sales_fact_ordertype
        CHECK (orderType IN ('Online','Walk-in')),
    CONSTRAINT chk_sales_fact_hour     CHECK (orderHour BETWEEN 0 AND 23),
    CONSTRAINT chk_sales_fact_qty      CHECK (quantity      > 0),
    CONSTRAINT chk_sales_fact_price    CHECK (unitPrice     >= 0),
    CONSTRAINT chk_sales_fact_gross    CHECK (grossSalesAmt >= 0),
    CONSTRAINT chk_sales_fact_discount CHECK (discountAmt   >= 0),
    CONSTRAINT chk_sales_fact_net      CHECK (netSalesAmt   >= 0),
    CONSTRAINT chk_sales_fact_dqflag   CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
-- 10. RETURN_FACT   (Transaction fact)
--     GRAIN  : one row per returned item line
--     SOURCE : ReturnDetails, joined to Returns and Orders
--
--     Measures
--       quantityReturned  additive
--       refundAmount      additive
--       daysToReturn      non-additive  (average it, never sum it)
--
--     order_date_key is DATE_DIM in a second role (the original order date),
--     which allows returns to be aged against the sale.
--     branch_key is the branch that SOLD the item: the Returns table carries
--     no BranchID, so it is inherited from the originating order.
--     promo_key is inherited from the matching sales line so that promotion
--     performance can be measured net of returns.
-- ----------------------------------------------------------------------------
CREATE TABLE return_fact
(
    return_date_key   NUMBER(8)     NOT NULL,
    order_date_key    NUMBER(8)     NOT NULL,
    customer_key      NUMBER(10)    NOT NULL,
    item_key          NUMBER(10)    NOT NULL,
    branch_key        NUMBER(10)    NOT NULL,
    reason_key        NUMBER(10)    NOT NULL,
    promo_key         NUMBER(10)    NOT NULL,
    returnID          VARCHAR2(8)   NOT NULL,
    orderNo           VARCHAR2(8)   NOT NULL,
    returnStatus      VARCHAR2(10)  NOT NULL,
    quantityReturned  NUMBER(4)     NOT NULL,
    refundAmount      NUMBER(10,2)  NOT NULL,
    daysToReturn      NUMBER(6)     DEFAULT 0 NOT NULL,
    etl_batch_id      NUMBER(8)     NOT NULL,
    etl_load_dt       DATE          DEFAULT SYSDATE NOT NULL,
    etl_update_dt     DATE,
    dq_flag           CHAR(1)       DEFAULT 'V' NOT NULL,
    CONSTRAINT return_fact_pk PRIMARY KEY
        (return_date_key, customer_key, item_key, branch_key,
         reason_key, returnID),
    CONSTRAINT rf_retdate_fk  FOREIGN KEY (return_date_key)
                              REFERENCES date_dim (date_key),
    CONSTRAINT rf_orddate_fk  FOREIGN KEY (order_date_key)
                              REFERENCES date_dim (date_key),
    CONSTRAINT rf_customer_fk FOREIGN KEY (customer_key)
                              REFERENCES customer_dim (customer_key),
    CONSTRAINT rf_item_fk     FOREIGN KEY (item_key)
                              REFERENCES item_dim (item_key),
    CONSTRAINT rf_branch_fk   FOREIGN KEY (branch_key)
                              REFERENCES branch_dim (branch_key),
    CONSTRAINT rf_reason_fk   FOREIGN KEY (reason_key)
                              REFERENCES return_reason_dim (reason_key),
    CONSTRAINT rf_promo_fk    FOREIGN KEY (promo_key)
                              REFERENCES promotion_dim (promo_key),
    CONSTRAINT rf_returnid_fk FOREIGN KEY (returnID)
                              REFERENCES Returns (ReturnID),
    CONSTRAINT rf_orderno_fk  FOREIGN KEY (orderNo)
                              REFERENCES Orders (OrderNo),
    CONSTRAINT return_fact_grain_uq UNIQUE (returnID, orderNo, item_key),
    CONSTRAINT chk_return_fact_status
        CHECK (returnStatus IN ('Pending','Approved','Rejected','Refunded')),
    CONSTRAINT chk_return_fact_qty    CHECK (quantityReturned > 0),
    CONSTRAINT chk_return_fact_refund CHECK (refundAmount    >= 0),
    CONSTRAINT chk_return_fact_days   CHECK (daysToReturn    >= 0),
    CONSTRAINT chk_return_fact_dqflag CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
-- 11. DELIVERY_FACT   (Transaction fact)
--     GRAIN  : one row per delivery
--     SOURCE : Delivery, joined to Orders
--
--     Measures
--       deliveryCharge    additive
--       orderTotalAmount  additive      (safe at this grain: Delivery.OrderNo
--                                        is UNIQUE, so one delivery per order)
--       deliveryLeadDays  non-additive  = DeliveryDate - OrderDateTime,
--                                        NULL until the order is delivered
--
--     Delivery.DeliveryDate is NULL until despatch completes, so pending and
--     cancelled deliveries carry delivery_date_key = -1 (the seeded Unknown
--     date).  Keeping them in the fact allows the pending and cancellation
--     rate per courier to be reported, rather than silently dropping them.
-- ----------------------------------------------------------------------------
CREATE TABLE delivery_fact
(
    delivery_date_key     NUMBER(8)     NOT NULL,
    order_date_key        NUMBER(8)     NOT NULL,
    customer_key          NUMBER(10)    NOT NULL,
    branch_key            NUMBER(10)    NOT NULL,
    delivery_company_key  NUMBER(10)    NOT NULL,
    address_key           NUMBER(10)    NOT NULL,
    deliveryID            VARCHAR2(8)   NOT NULL,
    orderNo               VARCHAR2(8)   NOT NULL,
    deliveryStatus        VARCHAR2(15)  NOT NULL,
    deliveryCharge        NUMBER(6,2)   DEFAULT 0 NOT NULL,
    orderTotalAmount      NUMBER(10,2)  DEFAULT 0 NOT NULL,
    deliveryLeadDays      NUMBER(6),
    etl_batch_id          NUMBER(8)     NOT NULL,
    etl_load_dt           DATE          DEFAULT SYSDATE NOT NULL,
    etl_update_dt         DATE,
    dq_flag               CHAR(1)       DEFAULT 'V' NOT NULL,
    CONSTRAINT delivery_fact_pk PRIMARY KEY
        (delivery_date_key, customer_key, branch_key,
         delivery_company_key, address_key, deliveryID),
    CONSTRAINT df_dlvdate_fk  FOREIGN KEY (delivery_date_key)
                              REFERENCES date_dim (date_key),
    CONSTRAINT df_orddate_fk  FOREIGN KEY (order_date_key)
                              REFERENCES date_dim (date_key),
    CONSTRAINT df_customer_fk FOREIGN KEY (customer_key)
                              REFERENCES customer_dim (customer_key),
    CONSTRAINT df_branch_fk   FOREIGN KEY (branch_key)
                              REFERENCES branch_dim (branch_key),
    CONSTRAINT df_company_fk  FOREIGN KEY (delivery_company_key)
                              REFERENCES delivery_company_dim (delivery_company_key),
    CONSTRAINT df_address_fk  FOREIGN KEY (address_key)
                              REFERENCES address_dim (address_key),
    CONSTRAINT df_deliveryid_fk FOREIGN KEY (deliveryID)
                              REFERENCES Delivery (DeliveryID),
    CONSTRAINT df_orderno_fk  FOREIGN KEY (orderNo)
                              REFERENCES Orders (OrderNo),
    CONSTRAINT delivery_fact_grain_uq UNIQUE (deliveryID),
    CONSTRAINT chk_delivery_fact_status
        CHECK (deliveryStatus IN ('Pending','In Transit','Delivered','Cancelled')),
    CONSTRAINT chk_delivery_fact_charge CHECK (deliveryCharge   >= 0),
    CONSTRAINT chk_delivery_fact_total  CHECK (orderTotalAmount >= 0),
    CONSTRAINT chk_delivery_fact_lead   CHECK (deliveryLeadDays >= 0),
    CONSTRAINT chk_delivery_fact_dqflag CHECK (dq_flag IN ('V','S','D'))
);

-- ----------------------------------------------------------------------------
-- 12. POINT_FACT   (Transaction fact)
--     GRAIN  : one row per loyalty point transaction
--     SOURCE : PointTransaction
--
--     Measures
--       pointsEarned    additive
--       pointsRedeemed  additive
--       netPoints       additive  = pointsEarned - pointsRedeemed
--
--     The source stores a single positive Point value and carries the sign in
--     TransType.  Splitting it into two measures lets earn and redeem be
--     summed independently without a CASE expression at query time, and
--     SUM(netPoints) per customer reproduces Member.PointsBalance - which is
--     the reason PointsBalance is not stored in CUSTOMER_DIM.
--
--     chk_pointtrans_order in the source enforces that an 'Earn' row has an
--     OrderNo and a 'Redeem' row does not.  Redemptions therefore have no
--     order and no branch: orderNo is NULL and branch_key points at the
--     seeded branch_key = -1 'Unknown / Not Applicable' row, which keeps the
--     fact uniform and every dimension join valid.
-- ----------------------------------------------------------------------------
CREATE TABLE point_fact
(
    trans_date_key  NUMBER(8)     NOT NULL,
    customer_key    NUMBER(10)    NOT NULL,
    branch_key      NUMBER(10)    NOT NULL,
    pointTransID    VARCHAR2(7)   NOT NULL,
    orderNo         VARCHAR2(8),
    transType       VARCHAR2(10)  NOT NULL,
    pointsEarned    NUMBER(8)     DEFAULT 0 NOT NULL,
    pointsRedeemed  NUMBER(8)     DEFAULT 0 NOT NULL,
    netPoints       NUMBER(9)     DEFAULT 0 NOT NULL,
    etl_batch_id    NUMBER(8)     NOT NULL,
    etl_load_dt     DATE          DEFAULT SYSDATE NOT NULL,
    etl_update_dt   DATE,
    dq_flag         CHAR(1)       DEFAULT 'V' NOT NULL,
    CONSTRAINT point_fact_pk PRIMARY KEY
        (trans_date_key, customer_key, branch_key, pointTransID),
    CONSTRAINT pf_date_fk     FOREIGN KEY (trans_date_key)
                              REFERENCES date_dim (date_key),
    CONSTRAINT pf_customer_fk FOREIGN KEY (customer_key)
                              REFERENCES customer_dim (customer_key),
    CONSTRAINT pf_branch_fk   FOREIGN KEY (branch_key)
                              REFERENCES branch_dim (branch_key),
    CONSTRAINT pf_pointtrans_fk FOREIGN KEY (pointTransID)
                              REFERENCES PointTransaction (PointTransID),
    CONSTRAINT pf_orderno_fk  FOREIGN KEY (orderNo)
                              REFERENCES Orders (OrderNo),
    CONSTRAINT point_fact_grain_uq UNIQUE (pointTransID),
    CONSTRAINT chk_point_fact_type
        CHECK (transType IN ('Earn','Redeem')),
    CONSTRAINT chk_point_fact_earned   CHECK (pointsEarned   >= 0),
    CONSTRAINT chk_point_fact_redeemed CHECK (pointsRedeemed >= 0),
    CONSTRAINT chk_point_fact_net      CHECK (netPoints = pointsEarned - pointsRedeemed),
    CONSTRAINT chk_point_fact_order
        CHECK ((transType = 'Earn'   AND orderNo IS NOT NULL) OR
               (transType = 'Redeem' AND orderNo IS NULL)),
    CONSTRAINT chk_point_fact_dqflag   CHECK (dq_flag IN ('V','S','D'))
);

-- ============================================================================
--  END OF TASK 1(b) PHYSICAL DESIGN
-- ============================================================================
