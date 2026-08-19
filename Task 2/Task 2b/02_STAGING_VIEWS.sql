-- ============================================================================
--  TASK 2(b) : SUBSEQUENT (INCREMENTAL) ETL LOADING
--  FILE 02   : STAGING / SCRUBBING VIEWS  (the Extract + Transform layer)
-- ----------------------------------------------------------------------------
--  ARCHITECTURE
--    view   = EXTRACT + TRANSFORM   read adm.*, clean it, de-duplicate it,
--                                   and stamp every row with a dq_flag
--    proc   = LOAD                  resolve surrogate keys and apply the
--                                   insert / update / expire logic
--
--    Splitting the two means the cleansing rules can be inspected with a plain
--    SELECT before a single row is written to the warehouse, e.g.
--        SELECT dq_flag, COUNT(*) FROM vw_stg_customer GROUP BY dq_flag;
--        SELECT * FROM vw_stg_sales WHERE dq_flag = 'D';
--
--  dq_flag contract (matches chk_*_dqflag CHECK (dq_flag IN ('V','S','D')))
--    'V'  valid      loaded as-is
--    'S'  scrubbed   at least one value was repaired, row is still loaded
--    'D'  dirty      row cannot satisfy the warehouse constraints, rejected
--                    and written to ETL_REJECT_LOG instead
--
--  DE-DUPLICATION
--    Every view ends in  WHERE rn = 1  over a ROW_NUMBER() partitioned by the
--    declared grain.  Duplicate source rows are the single most common cause of
--    an incremental load aborting on a UNIQUE constraint, so the grain is
--    enforced here rather than being discovered by ORA-00001.
-- ============================================================================

SET DEFINE OFF

-- ============================================================================
--  SECTION A : DIMENSION STAGING VIEWS
-- ============================================================================

-- ----------------------------------------------------------------------------
--  A1. vw_stg_customer -> CUSTOMER_DIM  (Type 2)
--      Grain: one row per CustomerID.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_customer AS
SELECT customer_id, customer_name, customer_ic, customer_email, customer_status,
       member_flag, membership_type, annual_fee, point_earn_rate, membership_expiry,
       raw_name, raw_email, raw_ic, raw_status, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(c.CustomerID)                          AS customer_id,
        etl_scrub.clean_name(c.Name, 100)                          AS customer_name,
        etl_scrub.clean_ic(c.ICNo)                                 AS customer_ic,
        etl_scrub.clean_email(c.Email)                             AS customer_email,
        etl_scrub.std_cust_status(c.Status)                        AS customer_status,
        CASE WHEN m.MemberID IS NOT NULL THEN 'Y' ELSE 'N' END     AS member_flag,
        CASE WHEN m.MemberID IS NULL THEN 'Non-Member'
             ELSE etl_scrub.std_membership_type(mt.TypeName) END   AS membership_type,
        etl_scrub.clamp_num(mt.AnnualFee,      0, 9999.99, 0)      AS annual_fee,
        etl_scrub.clamp_num(mt.PointEarnRate,  0,   99.99, 0)      AS point_earn_rate,
        m.MembershipExpiry                                         AS membership_expiry,
        c.Name    AS raw_name,
        c.Email   AS raw_email,
        c.ICNo    AS raw_ic,
        c.Status  AS raw_status,
        CASE
            WHEN etl_scrub.clean_key(c.CustomerID) IS NULL THEN 'D'
            WHEN etl_scrub.clean_name(c.Name, 100)      = 'Unknown'
              OR etl_scrub.clean_email(c.Email)         = 'Unknown'
              OR etl_scrub.clean_ic(c.ICNo)             = 'Unknown'
              OR etl_scrub.std_cust_status(c.Status)    = 'Unknown'
              OR NVL(c.Name,'~')  <> etl_scrub.clean_name(c.Name, 100)
              OR NVL(mt.AnnualFee,0)     < 0
              OR NVL(mt.PointEarnRate,0) < 0
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(c.CustomerID) IS NULL
                 THEN 'R101 missing business key; '           END ||
            CASE WHEN etl_scrub.clean_name(c.Name,100) = 'Unknown'
                 THEN 'R102 unusable name; '                  END ||
            CASE WHEN etl_scrub.clean_email(c.Email) = 'Unknown'
                 THEN 'R103 invalid email format; '           END ||
            CASE WHEN etl_scrub.clean_ic(c.ICNo) = 'Unknown'
                 THEN 'R104 IC not 12 digits; '               END ||
            CASE WHEN etl_scrub.std_cust_status(c.Status) = 'Unknown'
                 THEN 'R105 status outside domain; '          END ||
            CASE WHEN NVL(mt.AnnualFee,0) < 0 OR NVL(mt.PointEarnRate,0) < 0
                 THEN 'R106 negative fee or earn rate clamped to 0; ' END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (
            PARTITION BY etl_scrub.clean_key(c.CustomerID)
            ORDER BY CASE WHEN m.MemberID IS NOT NULL THEN 0 ELSE 1 END,
                     c.Name NULLS LAST)                            AS rn
    FROM       adm.Customer       c
    LEFT JOIN  adm.Member         m  ON c.CustomerID       = m.MemberID
    LEFT JOIN  adm.MembershipType mt ON m.MembershipTypeID = mt.MembershipTypeID
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  A2. vw_stg_item -> ITEM_DIM  (Type 1)
--      LEFT JOIN (not JOIN as in Task 2a): an item whose CategoryID or
--      SupplierID is orphaned must still reach the warehouse, defaulted to the
--      reserved 'UNKN' code, otherwise its sales silently disappear.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_item AS
SELECT item_id, item_name, item_unit_price, item_status,
       category_id, category_name, supplier_id, supplier_name, supplier_contact_no,
       raw_name, raw_price, raw_status, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(i.ItemID)                              AS item_id,
        etl_scrub.clean_name(i.ItemName, 100)                      AS item_name,
        ROUND(etl_scrub.clamp_num(i.UnitPrice, 0, 999999.99, 0), 2) AS item_unit_price,
        etl_scrub.std_item_status(i.Status)                        AS item_status,
        NVL(etl_scrub.clean_key(c.CategoryID), 'UNKN')             AS category_id,
        etl_scrub.clean_name(c.CategoryName, 50)                   AS category_name,
        NVL(etl_scrub.clean_key(s.SupplierID), 'UNKN')             AS supplier_id,
        etl_scrub.clean_name(s.SupplierName, 100)                  AS supplier_name,
        etl_scrub.clean_phone(s.ContactNo)                         AS supplier_contact_no,
        i.ItemName  AS raw_name,
        i.UnitPrice AS raw_price,
        i.Status    AS raw_status,
        CASE
            WHEN etl_scrub.clean_key(i.ItemID) IS NULL THEN 'D'
            WHEN c.CategoryID IS NULL
              OR s.SupplierID IS NULL
              OR i.UnitPrice IS NULL OR i.UnitPrice < 0
              OR etl_scrub.std_item_status(i.Status) = 'Unknown'
              OR etl_scrub.clean_name(i.ItemName,100) = 'Unknown'
              OR etl_scrub.clean_phone(s.ContactNo)   = 'Unknown'
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(i.ItemID) IS NULL
                 THEN 'R201 missing ItemID; '                      END ||
            CASE WHEN c.CategoryID IS NULL
                 THEN 'R202 orphan CategoryID defaulted to UNKN; '  END ||
            CASE WHEN s.SupplierID IS NULL
                 THEN 'R203 orphan SupplierID defaulted to UNKN; '  END ||
            CASE WHEN i.UnitPrice IS NULL OR i.UnitPrice < 0
                 THEN 'R204 null or negative unit price set to 0; ' END ||
            CASE WHEN etl_scrub.std_item_status(i.Status) = 'Unknown'
                 THEN 'R205 item status outside domain; '           END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(i.ItemID)
                           ORDER BY i.ItemName NULLS LAST)         AS rn
    FROM       adm.Item     i
    LEFT JOIN  adm.Category c ON i.CategoryID = c.CategoryID
    LEFT JOIN  adm.Supplier s ON i.SupplierID = s.SupplierID
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  A3. vw_stg_branch -> BRANCH_DIM  (Type 1)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_branch AS
SELECT branch_id, branch_name, branch_city, branch_state, branch_region,
       branch_contact_no, raw_city, raw_state, raw_contact, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(b.BranchID)                            AS branch_id,
        SUBSTR(etl_scrub.clean_name(b.City, 50) || ' Branch', 1, 60) AS branch_name,
        etl_scrub.clean_name(b.City, 50)                           AS branch_city,
        etl_scrub.std_state(b.State)                               AS branch_state,
        etl_scrub.std_region(b.State)                              AS branch_region,
        etl_scrub.clean_phone(b.ContactNo)                         AS branch_contact_no,
        b.City      AS raw_city,
        b.State     AS raw_state,
        b.ContactNo AS raw_contact,
        CASE
            WHEN etl_scrub.clean_key(b.BranchID) IS NULL THEN 'D'
            WHEN etl_scrub.std_state(b.State)      = 'Unknown'
              OR etl_scrub.clean_name(b.City,50)   = 'Unknown'
              OR etl_scrub.clean_phone(b.ContactNo)= 'Unknown'
              OR NVL(b.State,'~') <> etl_scrub.std_state(b.State)
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(b.BranchID) IS NULL
                 THEN 'R301 missing BranchID; '                    END ||
            CASE WHEN etl_scrub.std_state(b.State) = 'Unknown'
                 THEN 'R302 state not recognised; '                END ||
            CASE WHEN NVL(b.State,'~') <> etl_scrub.std_state(b.State)
                  AND etl_scrub.std_state(b.State) <> 'Unknown'
                 THEN 'R303 state spelling standardised; '         END ||
            CASE WHEN etl_scrub.clean_phone(b.ContactNo) = 'Unknown'
                 THEN 'R304 contact number invalid; '              END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(b.BranchID)
                           ORDER BY b.City NULLS LAST)             AS rn
    FROM adm.Branch b
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  A4. vw_stg_address -> ADDRESS_DIM  (Type 1)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_address AS
SELECT address_id, address_line, address_state, address_postcode, address_region,
       raw_line, raw_state, raw_postcode, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(a.AddressID)                           AS address_id,
        SUBSTR(etl_scrub.clean_text(a.AddressLine), 1, 150)        AS address_line,
        etl_scrub.std_state(a.State)                               AS address_state,
        etl_scrub.clean_postcode(a.Postcode)                       AS address_postcode,
        etl_scrub.std_region(a.State)                              AS address_region,
        a.AddressLine AS raw_line,
        a.State       AS raw_state,
        a.Postcode    AS raw_postcode,
        CASE
            WHEN etl_scrub.clean_key(a.AddressID) IS NULL THEN 'D'
            WHEN etl_scrub.std_state(a.State)         = 'Unknown'
              OR etl_scrub.clean_postcode(a.Postcode) = '00000'
              OR etl_scrub.clean_text(a.AddressLine)  = 'Unknown'
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(a.AddressID) IS NULL
                 THEN 'R401 missing AddressID; '                   END ||
            CASE WHEN etl_scrub.clean_text(a.AddressLine) = 'Unknown'
                 THEN 'R402 blank address line; '                  END ||
            CASE WHEN etl_scrub.std_state(a.State) = 'Unknown'
                 THEN 'R403 state not recognised; '                END ||
            CASE WHEN etl_scrub.clean_postcode(a.Postcode) = '00000'
                 THEN 'R404 postcode not 5 digits; '               END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(a.AddressID)
                           ORDER BY a.AddressLine NULLS LAST)      AS rn
    FROM adm.MemberAddress a
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  A5. vw_stg_promotion -> PROMOTION_DIM  (Type 1)
--      chk_promotion_dim_dates requires end >= start, and
--      chk_promotion_dim_duration stores the gap in a NUMBER(6), so a promotion
--      with reversed or missing dates has to be repaired AND capped here.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_promotion AS
SELECT promotion_id, promo_name, discount_type, discount_value,
       promo_start_date, promo_end_date, promo_status, promo_duration_days,
       raw_start, raw_end, raw_value, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(p.PromotionID)                         AS promotion_id,
        etl_scrub.clean_name(p.PromoName, 100)                     AS promo_name,
        etl_scrub.std_discount_type(p.DiscountType)                AS discount_type,
        ROUND(
          CASE WHEN etl_scrub.std_discount_type(p.DiscountType) = 'Percentage'
               THEN etl_scrub.clamp_num(p.DiscountValue, 0, 100,    0)
               ELSE etl_scrub.clamp_num(p.DiscountValue, 0, 9999.99, 0)
          END, 2)                                                  AS discount_value,
        NVL(p.StartDate, DATE '1900-01-01')                        AS promo_start_date,
        GREATEST(NVL(p.EndDate,   DATE '9999-12-31'),
                 NVL(p.StartDate, DATE '1900-01-01'))              AS promo_end_date,
        etl_scrub.std_promo_status(p.Status)                       AS promo_status,
        CASE
            WHEN p.StartDate IS NULL OR p.EndDate IS NULL THEN 0
            ELSE LEAST(GREATEST(TRUNC(p.EndDate) - TRUNC(p.StartDate), 0), 999999)
        END                                                        AS promo_duration_days,
        p.StartDate     AS raw_start,
        p.EndDate       AS raw_end,
        p.DiscountValue AS raw_value,
        CASE
            WHEN etl_scrub.clean_key(p.PromotionID) IS NULL THEN 'D'
            WHEN etl_scrub.clean_key(p.PromotionID) IN ('NONE','UNKN') THEN 'D'
            WHEN p.StartDate IS NULL OR p.EndDate IS NULL
              OR p.EndDate < p.StartDate
              OR NVL(p.DiscountValue, -1) < 0
              OR (etl_scrub.std_discount_type(p.DiscountType) = 'Percentage'
                  AND NVL(p.DiscountValue,0) > 100)
              OR etl_scrub.std_discount_type(p.DiscountType) = 'Unknown'
              OR etl_scrub.std_promo_status(p.Status)        = 'Unknown'
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(p.PromotionID) IS NULL
                 THEN 'R501 missing PromotionID; '                 END ||
            CASE WHEN etl_scrub.clean_key(p.PromotionID) IN ('NONE','UNKN')
                 THEN 'R502 clashes with reserved seeded key; '    END ||
            CASE WHEN p.EndDate < p.StartDate
                 THEN 'R503 end date before start date, end reset to start; ' END ||
            CASE WHEN p.StartDate IS NULL OR p.EndDate IS NULL
                 THEN 'R504 null promo date defaulted; '           END ||
            CASE WHEN NVL(p.DiscountValue,-1) < 0
                 THEN 'R505 negative discount clamped to 0; '      END ||
            CASE WHEN etl_scrub.std_discount_type(p.DiscountType)='Percentage'
                  AND NVL(p.DiscountValue,0) > 100
                 THEN 'R506 percentage discount above 100 capped; ' END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(p.PromotionID)
                           ORDER BY p.StartDate DESC NULLS LAST)   AS rn
    FROM adm.Promotion p
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  A6. vw_stg_return_reason -> RETURN_REASON_DIM  (Type 1)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_return_reason AS
SELECT reason_id, reason_name, reason_category, raw_name, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(r.ReasonID)                            AS reason_id,
        etl_scrub.std_reason_name(r.ReasonName)                    AS reason_name,
        etl_scrub.std_reason_cat(r.ReasonName)                     AS reason_category,
        r.ReasonName                                               AS raw_name,
        CASE
            WHEN etl_scrub.clean_key(r.ReasonID) IS NULL THEN 'D'
            WHEN etl_scrub.std_reason_name(r.ReasonName) = 'Unknown' THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        CASE WHEN etl_scrub.clean_key(r.ReasonID) IS NULL
             THEN 'R601 missing ReasonID'
             WHEN etl_scrub.std_reason_name(r.ReasonName) = 'Unknown'
             THEN 'R602 reason text outside domain, mapped to Unknown'
        END                                                        AS dq_note,
        ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(r.ReasonID)
                           ORDER BY r.ReasonName NULLS LAST)       AS rn
    FROM adm.ReturnReason r
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  A7. vw_stg_delivery_company -> DELIVERY_COMPANY_DIM  (Type 1)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_delivery_company AS
SELECT delivery_company_id, company_name, company_contact_no,
       raw_name, raw_contact, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(d.DeliveryCompanyID)                   AS delivery_company_id,
        etl_scrub.clean_name(d.CompanyName, 100)                   AS company_name,
        etl_scrub.clean_phone(d.ContactNo)                         AS company_contact_no,
        d.CompanyName AS raw_name,
        d.ContactNo   AS raw_contact,
        CASE
            WHEN etl_scrub.clean_key(d.DeliveryCompanyID) IS NULL THEN 'D'
            WHEN etl_scrub.clean_name(d.CompanyName,100) = 'Unknown'
              OR etl_scrub.clean_phone(d.ContactNo)      = 'Unknown'
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(d.DeliveryCompanyID) IS NULL
                 THEN 'R701 missing DeliveryCompanyID; '           END ||
            CASE WHEN etl_scrub.clean_name(d.CompanyName,100) = 'Unknown'
                 THEN 'R702 blank company name; '                  END ||
            CASE WHEN etl_scrub.clean_phone(d.ContactNo) = 'Unknown'
                 THEN 'R703 contact number invalid; '              END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(d.DeliveryCompanyID)
                           ORDER BY d.CompanyName NULLS LAST)      AS rn
    FROM adm.DeliveryCompany d
)
WHERE rn = 1;


-- ============================================================================
--  SECTION B : FACT STAGING VIEWS
-- ============================================================================

-- ----------------------------------------------------------------------------
--  B0. vw_stg_active_promo
--      One promotion per (OrderNo, ItemID).  Overlapping promotions are ranked
--      and the cheapest price wins, exactly as Task 2(a) decided, but the logic
--      now lives in ONE view instead of being copy-pasted into two procedures.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_active_promo AS
SELECT order_no, item_id, promo_price, promotion_id
FROM (
    SELECT
        etl_scrub.clean_key(o.OrderNo)  AS order_no,
        etl_scrub.clean_key(od.ItemID)  AS item_id,
        ip.PromoPrice                   AS promo_price,
        etl_scrub.clean_key(p.PromotionID) AS promotion_id,
        ROW_NUMBER() OVER (
            PARTITION BY etl_scrub.clean_key(o.OrderNo), etl_scrub.clean_key(od.ItemID)
            ORDER BY ip.PromoPrice ASC NULLS LAST, p.PromotionID) AS rn
    FROM adm.Orders        o
    JOIN adm.OrderDetails  od ON o.OrderNo  = od.OrderNo
    JOIN adm.ItemPromotion ip ON od.ItemID  = ip.ItemID
    JOIN adm.Promotion     p  ON ip.PromotionID = p.PromotionID
    WHERE o.OrderDateTime BETWEEN p.StartDate AND p.EndDate
      AND ip.PromoPrice IS NOT NULL
      AND ip.PromoPrice >= 0
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  B1. vw_stg_sales -> SALES_FACT
--      Grain: one row per (OrderNo, ItemID)  = sales_fact_grain_uq
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_sales AS
SELECT
    order_no, item_id, customer_id, branch_id, promotion_id,
    order_dt, order_type, order_hour, quantity, unit_price,
    gross_sales_amt,
    LEAST(raw_discount_amt, gross_sales_amt)                       AS discount_amt,
    ROUND(gross_sales_amt - LEAST(raw_discount_amt, gross_sales_amt), 2)
                                                                   AS net_sales_amt,
    raw_quantity, raw_unit_price, raw_order_type,
    CASE
        WHEN order_no    IS NULL OR item_id   IS NULL
          OR customer_id IS NULL OR branch_id IS NULL
          OR quantity <= 0
        THEN 'D'
        WHEN raw_quantity   IS NULL OR raw_quantity   <> quantity
          OR raw_unit_price IS NULL OR raw_unit_price <> unit_price
          OR order_dt IS NULL
          OR NVL(raw_order_type,'~') <> order_type
          OR raw_discount_amt > gross_sales_amt
        THEN 'S'
        ELSE 'V'
    END                                                            AS dq_flag,
    RTRIM(
        CASE WHEN order_no IS NULL OR item_id IS NULL
             THEN 'R801 missing OrderNo or ItemID; '               END ||
        CASE WHEN customer_id IS NULL OR branch_id IS NULL
             THEN 'R802 order has no customer or branch; '         END ||
        CASE WHEN NVL(raw_quantity, 0) <= 0
             THEN 'R803 quantity null or not positive, row rejected '
               || '(chk_sales_fact_qty); '                         END ||
        CASE WHEN raw_unit_price IS NULL OR raw_unit_price < 0
             THEN 'R804 unit price null or negative, replaced by '
               || 'ITEM.UnitPrice; '                               END ||
        CASE WHEN order_dt IS NULL
             THEN 'R805 null order date mapped to date_key -1; '   END ||
        CASE WHEN NVL(raw_order_type,'~') <> order_type
             THEN 'R806 order type standardised; '                 END ||
        CASE WHEN raw_discount_amt > gross_sales_amt
             THEN 'R807 discount exceeded gross sales, capped to '
               || 'keep net >= 0 (chk_sales_fact_net); '           END
    , '; ')                                                        AS dq_note
FROM (
    -- level 2 : derive the measures from the already-cleaned columns
    SELECT
        order_no, item_id, customer_id, branch_id, promotion_id,
        order_dt, order_type, order_hour, quantity, unit_price,
        ROUND(quantity * unit_price, 2)                            AS gross_sales_amt,
        ROUND(CASE
                 WHEN promotion_id IS NULL          THEN 0
                 WHEN promo_price  IS NULL          THEN 0
                 WHEN promo_price  >= unit_price    THEN 0
                 ELSE (unit_price - promo_price) * quantity
              END, 2)                                              AS raw_discount_amt,
        raw_quantity, raw_unit_price, raw_order_type
    FROM (
        -- level 1 : clean every source column and enforce the grain
        SELECT
            etl_scrub.clean_key(o.OrderNo)                         AS order_no,
            etl_scrub.clean_key(od.ItemID)                         AS item_id,
            etl_scrub.clean_key(o.CustomerID)                      AS customer_id,
            etl_scrub.clean_key(o.BranchID)                        AS branch_id,
            ap.promotion_id                                        AS promotion_id,
            ap.promo_price                                         AS promo_price,
            o.OrderDateTime                                        AS order_dt,
            etl_scrub.std_order_type(o.OrderType)                  AS order_type,
            NVL(TO_NUMBER(TO_CHAR(o.OrderDateTime,'HH24')), 0)     AS order_hour,
            NVL(od.Quantity, 0)                                    AS quantity,
            ROUND(CASE WHEN od.UnitPrice IS NULL OR od.UnitPrice < 0
                       THEN etl_scrub.clamp_num(i.UnitPrice, 0, 999999.99, 0)
                       ELSE od.UnitPrice
                  END, 2)                                          AS unit_price,
            od.Quantity   AS raw_quantity,
            od.UnitPrice  AS raw_unit_price,
            o.OrderType   AS raw_order_type,
            ROW_NUMBER() OVER (
                PARTITION BY etl_scrub.clean_key(o.OrderNo),
                             etl_scrub.clean_key(od.ItemID)
                ORDER BY od.Quantity DESC NULLS LAST)              AS rn
        FROM       adm.OrderDetails od
        JOIN       adm.Orders       o  ON od.OrderNo = o.OrderNo
        LEFT JOIN  adm.Item         i  ON od.ItemID  = i.ItemID
        LEFT JOIN  vw_stg_active_promo ap
               ON  ap.order_no = etl_scrub.clean_key(od.OrderNo)
               AND ap.item_id  = etl_scrub.clean_key(od.ItemID)
    )
    WHERE rn = 1
);


-- ----------------------------------------------------------------------------
--  B2. vw_stg_return -> RETURN_FACT
--      Grain: one row per (ReturnID, OrderNo, ItemID) = return_fact_grain_uq
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_return AS
SELECT return_id, order_no, item_id, customer_id, branch_id, reason_id,
       promotion_id, return_dt, order_dt, return_status,
       quantity_returned, refund_amount, days_to_return,
       raw_quantity, raw_refund, raw_status, raw_days, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(r.ReturnID)                            AS return_id,
        etl_scrub.clean_key(o.OrderNo)                             AS order_no,
        etl_scrub.clean_key(rd.ItemID)                             AS item_id,
        etl_scrub.clean_key(o.CustomerID)                          AS customer_id,
        etl_scrub.clean_key(o.BranchID)                            AS branch_id,
        etl_scrub.clean_key(rd.ReasonID)                           AS reason_id,
        ap.promotion_id                                            AS promotion_id,
        r.ReturnDate                                               AS return_dt,
        o.OrderDateTime                                            AS order_dt,
        etl_scrub.std_return_status(r.Status)                      AS return_status,
        NVL(rd.QuantityReturned, 0)                                AS quantity_returned,
        ROUND(etl_scrub.clamp_num(rd.RefundAmount, 0, 99999999.99, 0), 2)
                                                                   AS refund_amount,
        GREATEST(NVL(TRUNC(r.ReturnDate) - TRUNC(o.OrderDateTime), 0), 0)
                                                                   AS days_to_return,
        rd.QuantityReturned AS raw_quantity,
        rd.RefundAmount     AS raw_refund,
        r.Status            AS raw_status,
        TRUNC(r.ReturnDate) - TRUNC(o.OrderDateTime)               AS raw_days,
        CASE
            WHEN etl_scrub.clean_key(r.ReturnID) IS NULL
              OR etl_scrub.clean_key(rd.ItemID)  IS NULL
              OR etl_scrub.clean_key(o.OrderNo)  IS NULL
              OR NVL(rd.QuantityReturned, 0) <= 0
            THEN 'D'
            WHEN r.ReturnDate IS NULL
              OR NVL(TRUNC(r.ReturnDate) - TRUNC(o.OrderDateTime), 0) < 0
              OR NVL(rd.RefundAmount, -1) < 0
              OR NVL(r.Status,'~') <> etl_scrub.std_return_status(r.Status)
              OR etl_scrub.clean_key(rd.ReasonID) IS NULL
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(r.ReturnID) IS NULL
                   OR etl_scrub.clean_key(rd.ItemID) IS NULL
                 THEN 'R901 missing ReturnID or ItemID; '          END ||
            CASE WHEN NVL(rd.QuantityReturned,0) <= 0
                 THEN 'R902 returned quantity not positive, row rejected '
                   || '(chk_return_fact_qty); '                    END ||
            CASE WHEN NVL(TRUNC(r.ReturnDate)-TRUNC(o.OrderDateTime),0) < 0
                 THEN 'R903 return dated before its order, days_to_return '
                   || 'floored at 0 (chk_return_fact_days); '      END ||
            CASE WHEN NVL(rd.RefundAmount,-1) < 0
                 THEN 'R904 negative refund clamped to 0; '        END ||
            CASE WHEN r.ReturnDate IS NULL
                 THEN 'R905 null return date mapped to date_key -1; ' END ||
            CASE WHEN etl_scrub.clean_key(rd.ReasonID) IS NULL
                 THEN 'R906 missing reason, mapped to reason_key -1; ' END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (
            PARTITION BY etl_scrub.clean_key(r.ReturnID),
                         etl_scrub.clean_key(o.OrderNo),
                         etl_scrub.clean_key(rd.ItemID)
            ORDER BY rd.QuantityReturned DESC NULLS LAST)          AS rn
    FROM       adm.ReturnDetails rd
    JOIN       adm.Returns       r  ON rd.ReturnID = r.ReturnID
    JOIN       adm.Orders        o  ON r.OrderNo   = o.OrderNo
    LEFT JOIN  vw_stg_active_promo ap
           ON  ap.order_no = etl_scrub.clean_key(o.OrderNo)
           AND ap.item_id  = etl_scrub.clean_key(rd.ItemID)
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  B3. vw_stg_delivery -> DELIVERY_FACT
--      Grain: one row per DeliveryID = delivery_fact_grain_uq
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_delivery AS
SELECT delivery_id, order_no, customer_id, branch_id, delivery_company_id,
       address_id, delivery_dt, order_dt, delivery_status,
       delivery_charge, order_total_amount, delivery_lead_days,
       raw_charge, raw_total, raw_status, raw_lead, dq_flag, dq_note
FROM (
    SELECT
        etl_scrub.clean_key(d.DeliveryID)                          AS delivery_id,
        etl_scrub.clean_key(o.OrderNo)                             AS order_no,
        etl_scrub.clean_key(o.CustomerID)                          AS customer_id,
        etl_scrub.clean_key(o.BranchID)                            AS branch_id,
        etl_scrub.clean_key(d.DeliveryCompanyID)                   AS delivery_company_id,
        etl_scrub.clean_key(d.AddressID)                           AS address_id,
        d.DeliveryDate                                             AS delivery_dt,
        o.OrderDateTime                                            AS order_dt,
        etl_scrub.std_delivery_status(d.Status)                    AS delivery_status,
        ROUND(etl_scrub.clamp_num(d.DeliveryCharge, 0, 9999.99, 0), 2)
                                                                   AS delivery_charge,
        ROUND(etl_scrub.clamp_num(o.TotalAmount, 0, 99999999.99, 0), 2)
                                                                   AS order_total_amount,
        CASE WHEN d.DeliveryDate IS NULL THEN NULL
             ELSE GREATEST(TRUNC(d.DeliveryDate) - TRUNC(o.OrderDateTime), 0)
        END                                                        AS delivery_lead_days,
        d.DeliveryCharge AS raw_charge,
        o.TotalAmount    AS raw_total,
        d.Status         AS raw_status,
        TRUNC(d.DeliveryDate) - TRUNC(o.OrderDateTime)             AS raw_lead,
        CASE
            WHEN etl_scrub.clean_key(d.DeliveryID) IS NULL
              OR etl_scrub.clean_key(o.OrderNo)    IS NULL
            THEN 'D'
            WHEN d.DeliveryDate IS NULL
              OR TRUNC(d.DeliveryDate) - TRUNC(o.OrderDateTime) < 0
              OR NVL(d.DeliveryCharge, -1) < 0
              OR NVL(o.TotalAmount,    -1) < 0
              OR NVL(d.Status,'~') <> etl_scrub.std_delivery_status(d.Status)
              OR etl_scrub.clean_key(d.AddressID)         IS NULL
              OR etl_scrub.clean_key(d.DeliveryCompanyID) IS NULL
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN etl_scrub.clean_key(d.DeliveryID) IS NULL
                 THEN 'RA01 missing DeliveryID; '                  END ||
            CASE WHEN d.DeliveryDate IS NULL
                 THEN 'RA02 not yet despatched, delivery_date_key set to -1; ' END ||
            CASE WHEN TRUNC(d.DeliveryDate)-TRUNC(o.OrderDateTime) < 0
                 THEN 'RA03 delivered before ordered, lead days floored at 0 '
                   || '(chk_delivery_fact_lead); '                 END ||
            CASE WHEN NVL(d.DeliveryCharge,-1) < 0
                 THEN 'RA04 negative delivery charge clamped to 0; ' END ||
            CASE WHEN NVL(o.TotalAmount,-1) < 0
                 THEN 'RA05 negative order total clamped to 0; '   END ||
            CASE WHEN NVL(d.Status,'~') <> etl_scrub.std_delivery_status(d.Status)
                 THEN 'RA06 delivery status standardised; '        END ||
            CASE WHEN etl_scrub.clean_key(d.AddressID) IS NULL
                 THEN 'RA07 missing address, mapped to address_key -1; ' END
        , '; ')                                                    AS dq_note,
        ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(d.DeliveryID)
                           ORDER BY d.DeliveryDate DESC NULLS LAST) AS rn
    FROM adm.Delivery d
    JOIN adm.Orders   o ON d.OrderNo = o.OrderNo
)
WHERE rn = 1;


-- ----------------------------------------------------------------------------
--  B4. vw_stg_point -> POINT_FACT
--      Grain: one row per PointTransID = point_fact_grain_uq
--      chk_point_fact_order is the strictest rule in the warehouse:
--          Earn   MUST carry an OrderNo
--          Redeem MUST NOT carry an OrderNo
--      so an 'Earn' with no order is rejected, while a 'Redeem' that wrongly
--      carries an order has the order stripped and is flagged as scrubbed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stg_point AS
SELECT point_trans_id, customer_id, branch_id, order_no, trans_dt, trans_type,
       points_earned, points_redeemed, net_points,
       raw_order_no, raw_type, raw_point, dq_flag, dq_note
FROM (
    SELECT
        point_trans_id, customer_id, branch_id, trans_dt, trans_type,
        CASE WHEN trans_type = 'Redeem' THEN NULL ELSE order_no END AS order_no,
        CASE WHEN trans_type = 'Earn'   THEN points ELSE 0 END      AS points_earned,
        CASE WHEN trans_type = 'Redeem' THEN points ELSE 0 END      AS points_redeemed,
        CASE WHEN trans_type = 'Earn'   THEN points ELSE -points END AS net_points,
        raw_order_no, raw_type, raw_point,
        CASE
            WHEN point_trans_id IS NULL
              OR customer_id    IS NULL
              OR trans_type     IS NULL
              OR (trans_type = 'Earn' AND order_no IS NULL)
            THEN 'D'
            WHEN raw_point IS NULL OR raw_point < 0
              OR NVL(raw_type,'~') <> trans_type
              OR (trans_type = 'Redeem' AND order_no IS NOT NULL)
              OR trans_dt IS NULL
            THEN 'S'
            ELSE 'V'
        END                                                        AS dq_flag,
        RTRIM(
            CASE WHEN point_trans_id IS NULL
                 THEN 'RB01 missing PointTransID; '                END ||
            CASE WHEN trans_type IS NULL
                 THEN 'RB02 TransType not Earn or Redeem, row rejected; ' END ||
            CASE WHEN trans_type = 'Earn' AND order_no IS NULL
                 THEN 'RB03 Earn row has no OrderNo, rejected '
                   || '(chk_point_fact_order); '                   END ||
            CASE WHEN trans_type = 'Redeem' AND order_no IS NOT NULL
                 THEN 'RB04 Redeem row carried an OrderNo, stripped '
                   || '(chk_point_fact_order); '                   END ||
            CASE WHEN raw_point IS NULL OR raw_point < 0
                 THEN 'RB05 null or negative point value made absolute; ' END ||
            CASE WHEN trans_dt IS NULL
                 THEN 'RB06 null transaction date mapped to date_key -1; ' END
        , '; ')                                                    AS dq_note
    FROM (
        SELECT
            etl_scrub.clean_key(pt.PointTransID)                   AS point_trans_id,
            etl_scrub.clean_key(pt.MemberID)                       AS customer_id,
            etl_scrub.clean_key(o.BranchID)                        AS branch_id,
            etl_scrub.clean_key(pt.OrderNo)                        AS order_no,
            pt.TransDate                                           AS trans_dt,
            etl_scrub.std_trans_type(pt.TransType)                 AS trans_type,
            etl_scrub.clamp_num(ABS(pt.Point), 0, 99999999, 0)     AS points,
            pt.OrderNo   AS raw_order_no,
            pt.TransType AS raw_type,
            pt.Point     AS raw_point,
            ROW_NUMBER() OVER (PARTITION BY etl_scrub.clean_key(pt.PointTransID)
                               ORDER BY pt.TransDate DESC NULLS LAST) AS rn
        -- LEFT JOIN because a redemption legitimately carries no order,
        -- in which case branch_id stays NULL and resolves to branch_key -1.
        FROM      adm.PointTransaction pt
        LEFT JOIN adm.Orders           o ON pt.OrderNo = o.OrderNo
    )
    WHERE rn = 1
);

-- ============================================================================
--  END OF FILE 02
-- ============================================================================
