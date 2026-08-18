# Task 1(a) — Logical Design
## 88 Speedmart Grocery — Sales, Returns, Delivery & Loyalty Data Warehouse

**Source system:** the operational Oracle database defined in `Task2_DDL.sql` (21 tables)
**Architecture:** fact constellation (galaxy schema) — **8 dimensions, 4 fact tables**
**SCD Type 2:** `CUSTOMER_DIM`

---

## 1. Kimball Bus Matrix

Draw this first — it tells you exactly where every relationship line goes.

| Dimension | SALES_FACT | RETURN_FACT | DELIVERY_FACT | POINT_FACT |
|---|---|---|---|---|
| **DATE_DIM** | `order_date_key` | `return_date_key` + `order_date_key` | `delivery_date_key` + `order_date_key` | `trans_date_key` |
| **CUSTOMER_DIM** *(Type 2)* | ✔ | ✔ | ✔ | ✔ |
| **ITEM_DIM** | ✔ | ✔ | — | — |
| **BRANCH_DIM** | ✔ | ✔ | ✔ | ✔ |
| **PROMOTION_DIM** | ✔ | ✔ | — | — |
| **RETURN_REASON_DIM** | — | ✔ | — | — |
| **ADDRESS_DIM** | — | — | ✔ | — |
| **DELIVERY_COMPANY_DIM** | — | — | ✔ | — |

`DATE_DIM` and `CUSTOMER_DIM` are shared by all four facts; `BRANCH_DIM` by all four; `ITEM_DIM` and
`PROMOTION_DIM` by two. These are the **conformed dimensions** — one physical table, identical keys and
identical meaning in every fact.

**Layout tip:** put `DATE_DIM` and `CUSTOMER_DIM` in the centre column, `SALES_FACT` and `POINT_FACT` on the
left, `RETURN_FACT` and `DELIVERY_FACT` on the right.

---

## 2. Grain statements

| Fact | Fact type | Grain — one row per… | Source |
|---|---|---|---|
| `SALES_FACT` | Transaction | item line per order | `OrderDetails` + `Orders` + `ItemPromotion` |
| `RETURN_FACT` | Transaction | returned item line | `ReturnDetails` + `Returns` + `Orders` |
| `DELIVERY_FACT` | Transaction | delivery | `Delivery` + `Orders` |
| `POINT_FACT` | Transaction | loyalty point transaction | `PointTransaction` |

---

## 3. Dimension tables

Notation for your drawing: **PK** = primary key · **FK** = foreign key · *(derived)* = computed by the ETL,
not copied from a source column.

### 3.1 DATE_DIM — generated calendar, day grain (role-playing)

```
PK  date_key             NUMBER(8)   -- YYYYMMDD "smart key";  -1 = Unknown
    cal_date
    full_desc
    day_week
    day_num_month
    day_num_year
    last_day_ind         'Y'/'N'
    cal_week_end_date
    cal_week_year
    cal_month_name
    cal_month_year
    cal_year_month
    cal_quarter          'Q1'..'Q4'
    cal_year_quarter
    cal_year
    holiday_ind          'Y'/'N'
    weekday_ind          'Y'/'N'
    festive_event        DEFAULT 'None'   -- never NULL
    [ETL audit block]
```

Referenced **five times** across the four facts (order date, return date, delivery date, point transaction
date). One physical calendar table, not five. No FK back to the source — the calendar is generated, not
extracted.

### 3.2 CUSTOMER_DIM — *** SLOWLY CHANGING DIMENSION TYPE 2 ***

Source: `Customer` + `Member` + `MembershipType`. `Member` is a 1:1 subtype of `Customer`, so members and
walk-in non-members share one dimension and are separated by `memberFlag`.

```
PK  customer_key         NUMBER(10)
FK  customerID           -> Customer(CustomerID)
    customerName         [Type 1 overwrite]
    customerICNo         [Type 1 overwrite]   DEFAULT 'Unknown'
    customerEmail        [Type 1 overwrite]   DEFAULT 'Unknown'
    customerStatus       [Type 2 trigger]     'Active'/'Inactive'/'Unknown'
    memberFlag           [Type 2 trigger]     'Y'/'N' — derived: EXISTS in Member
    membershipType       [Type 2 trigger]     'Normal'/'VIP'/'Non-Member'
    annualFee                                 MembershipType.AnnualFee, 0 if non-member
    pointEarnRate                             MembershipType.PointEarnRate, 0 if non-member
    membershipExpiry     [Type 1 overwrite]
    effective_start_date
    effective_end_date   DEFAULT DATE '9999-12-31'
    is_current_flag      'Y'/'N'
    version_no
    [ETL audit block]
```

`customerID` is **deliberately not unique** — one customer has many version rows. Uniqueness is
`UNIQUE (customerID, effective_start_date)`.

`Member.PointsBalance` is **excluded on purpose**: it changes on every transaction and would create a new
version row per order. The balance is obtained instead by `SUM(POINT_FACT.netPoints)` per customer.

### 3.3 ITEM_DIM — Type 1

Source: `Item` + `Category` + `Supplier`. Both relationships are many-to-one, so they are flattened into one
dimension rather than snowflaked.

```
PK  item_key             NUMBER(10)
FK  itemID               -> Item(ItemID)
    itemName
    itemUnitPrice                     -- Item.UnitPrice (current catalogue price)
    itemStatus                        'Pending QC'/'Active'/'Discontinued'
    categoryID
    categoryName                      -- Category.CategoryName
    supplierID
    supplierName                      -- Supplier.SupplierName
    supplierContactNo                 -- Supplier.ContactNo
    [ETL audit block]
```

`supplierID` is retained because `Supplier.SupplierName` carries **no UNIQUE constraint** in the source and
therefore cannot safely be used on its own as a grouping key in Task 3.

### 3.4 BRANCH_DIM — Type 1

Source: `Branch` — which has only four columns (`BranchID`, `City`, `State`, `ContactNo`).

```
PK  branch_key           NUMBER(10)
FK  branchID             -> Branch(BranchID)
    branchName           (derived)    -- branchCity || ' Branch'
    branchCity
    branchState
    branchRegion         (derived)    -- see mapping below
    branchContactNo
    [ETL audit block]
```

**Region mapping** (covers all 16 states in the source `chk_branch_state` constraint):

| Region | States |
|---|---|
| Northern | Perlis, Kedah, Pulau Pinang, Perak |
| Central | Selangor, Kuala Lumpur, Putrajaya, Negeri Sembilan |
| Southern | Melaka, Johor |
| East Coast | Pahang, Terengganu, Kelantan |
| East Malaysia | Sabah, Sarawak, Labuan |

### 3.5 ADDRESS_DIM — Type 1 (ship-to geography)

Source: `MemberAddress`. Note the source has **no City column**.

```
PK  address_key          NUMBER(10)
FK  addressID            -> MemberAddress(AddressID)
    addressLine
    addressState
    addressPostcode      CHAR(5)
    addressRegion        (derived)    -- same mapping as BRANCH_DIM
    [ETL audit block]
```

Having `branchRegion` and `addressRegion` on the same mapping lets a report compare *the branch that sold
the order* against *the state it shipped to*.

### 3.6 PROMOTION_DIM — Type 1

```
PK  promo_key            NUMBER(10)    --  0 = 'No Promotion',  -1 = 'Unknown'
FK  promotionID          -> Promotion(PromotionID)
    promoName
    discountType                       'Percentage'/'Fixed'/'None'
    discountValue
    promoStartDate
    promoEndDate
    promoStatus                        'Active'/'Inactive'/'None'
    promoDurationDays    (derived)     -- promoEndDate - promoStartDate
    [ETL audit block]
```

Two seed rows, and the distinction matters: **0** means the sale genuinely had no promotion, **-1** means the
promotion reference was dirty and could not be resolved. Collapsing them into one value makes promotion
coverage unreportable.

`ItemPromotion.PromoPrice` is **item-specific**, so it belongs at fact grain — the ETL uses it to derive
`SALES_FACT.discountAmt` and it is not stored in this dimension.

### 3.7 RETURN_REASON_DIM — Type 1

```
PK  reason_key           NUMBER(10)
FK  reasonID             -> ReturnReason(ReasonID)
    reasonName                         'Missing'/'Broken'/'Expired'/'Wrong Item'
    reasonCategory       (derived)     'Fulfilment' / 'Product Quality'
    [ETL audit block]
```

`reasonCategory` separates causes the business controls from causes it does not:
**Fulfilment** = Missing, Wrong Item (picking/despatch error) · **Product Quality** = Broken, Expired
(stock or supplier issue). Publish the mapping in an appendix.

### 3.8 DELIVERY_COMPANY_DIM — Type 1

```
PK  delivery_company_key NUMBER(10)
FK  deliveryCompanyID    -> DeliveryCompany(DeliveryCompanyID)
    companyName
    companyContactNo
    [ETL audit block]
```

---

## 4. Fact tables

### 4.1 SALES_FACT — grain: one item line per order

```
PK  (order_date_key, customer_key, item_key, branch_key, promo_key, orderNo)
FK  order_date_key   -> DATE_DIM
FK  customer_key     -> CUSTOMER_DIM     (version current at the order date)
FK  item_key         -> ITEM_DIM
FK  branch_key       -> BRANCH_DIM
FK  promo_key        -> PROMOTION_DIM    (0 when no promotion applies)
FK  orderNo          -> Orders(OrderNo)
    orderType                            'Online'/'Walk-in'
    orderHour                            0-23, from Orders.OrderDateTime
    quantity                 [additive]
    unitPrice                [non-additive — average it, never sum it]
    grossSalesAmt            [additive]      = quantity * unitPrice
    discountAmt              [additive]      = (unitPrice - PromoPrice) * quantity, else 0
    netSalesAmt              [additive]      = grossSalesAmt - discountAmt
    [ETL audit block]
UNIQUE (orderNo, item_key)   -- enforces the declared grain
```

### 4.2 RETURN_FACT — grain: one returned item line

```
PK  (return_date_key, customer_key, item_key, branch_key, reason_key, returnID)
FK  return_date_key  -> DATE_DIM         (role: return date)
FK  order_date_key   -> DATE_DIM         (role: original order date)
FK  customer_key     -> CUSTOMER_DIM     (version current at the return date)
FK  item_key         -> ITEM_DIM
FK  branch_key       -> BRANCH_DIM       (the branch that SOLD the item)
FK  reason_key       -> RETURN_REASON_DIM
FK  promo_key        -> PROMOTION_DIM    (inherited from the matching sales line)
FK  returnID         -> Returns(ReturnID)
FK  orderNo          -> Orders(OrderNo)
    returnStatus                         'Pending'/'Approved'/'Rejected'/'Refunded'
    quantityReturned         [additive]
    refundAmount             [additive]
    daysToReturn             [non-additive] = ReturnDate - OrderDateTime
    [ETL audit block]
UNIQUE (returnID, orderNo, item_key)   -- matches the ReturnDetails primary key
```

### 4.3 DELIVERY_FACT — grain: one delivery

```
PK  (delivery_date_key, customer_key, branch_key,
     delivery_company_key, address_key, deliveryID)
FK  delivery_date_key    -> DATE_DIM     (-1 while the order is not yet delivered)
FK  order_date_key       -> DATE_DIM     (role: order date)
FK  customer_key         -> CUSTOMER_DIM
FK  branch_key           -> BRANCH_DIM
FK  delivery_company_key -> DELIVERY_COMPANY_DIM
FK  address_key          -> ADDRESS_DIM
FK  deliveryID           -> Delivery(DeliveryID)
FK  orderNo              -> Orders(OrderNo)
    deliveryStatus                       'Pending'/'In Transit'/'Delivered'/'Cancelled'
    deliveryCharge           [additive]
    orderTotalAmount         [additive]  -- Orders.TotalAmount
    deliveryLeadDays         [non-additive] = DeliveryDate - OrderDateTime, NULL until delivered
    [ETL audit block]
UNIQUE (deliveryID)
```

`Delivery.OrderNo` carries a UNIQUE constraint in the source (one delivery per order), so storing
`orderTotalAmount` at this grain does **not** double-count — it gives the fact a revenue measure and enables
"delivery charge as a percentage of order value".

Pending and cancelled deliveries are **kept** in the fact with `delivery_date_key = -1`, so the pending and
cancellation rate per courier is reportable rather than silently dropped.

### 4.4 POINT_FACT — grain: one loyalty point transaction

```
PK  (trans_date_key, customer_key, branch_key, pointTransID)
FK  trans_date_key   -> DATE_DIM
FK  customer_key     -> CUSTOMER_DIM     (version current at the transaction date)
FK  branch_key       -> BRANCH_DIM       (-1 for redemptions — see below)
FK  pointTransID     -> PointTransaction(PointTransID)
FK  orderNo          -> Orders(OrderNo)  (NULL for redemptions — source enforces this)
    transType                            'Earn'/'Redeem'
    pointsEarned             [additive]
    pointsRedeemed           [additive]
    netPoints                [additive]  = pointsEarned - pointsRedeemed
    [ETL audit block]
UNIQUE (pointTransID)
```

The source stores a single **positive** `Point` value and carries the sign in `TransType`. Splitting it into
two measures lets earn and redeem be summed independently without a `CASE` expression at query time.

`chk_pointtrans_order` in the source enforces that an `'Earn'` row has an `OrderNo` and a `'Redeem'` row does
not. Redemptions therefore have no order and no branch: `orderNo` is NULL and `branch_key` points at the
seeded **`branch_key = -1` 'Unknown / Not Applicable'** row. This keeps the fact uniform and every dimension
join valid.

---

## 5. Design notes — put these on the diagram

1. **Fact constellation (galaxy schema).** `DATE`, `CUSTOMER`, `BRANCH`, `ITEM` and `PROMOTION` are conformed
   — one physical table, identical keys and identical meaning in every fact that uses them.
2. **`DATE_DIM` is role-playing**, referenced five times. Expose it as views (`ORDER_DATE_DIM`,
   `RETURN_DATE_DIM`, `DELIVERY_DATE_DIM`, `TRANS_DATE_DIM`) in Task 2 so a BI tool can join it more than
   once. `date_key` is a `YYYYMMDD` smart key.
3. **`CUSTOMER_DIM` is the Type 2 dimension** (assignment requirement). Type 2 triggers: `customerStatus`,
   `memberFlag`, `membershipType`. Type 1 overwrite: `customerName`, `customerICNo`, `customerEmail`,
   `membershipExpiry`.
4. **SCD2 join rule.** A fact points at the customer version **current at the time of the event** —
   `SALES_FACT` uses the order date, `RETURN_FACT` the return date, `DELIVERY_FACT` the order date,
   `POINT_FACT` the transaction date.
5. **Surrogate keys everywhere.** Every dimension has a system-generated `xxx_key`; the operational
   identifier is retained alongside it and declared as a `FOREIGN KEY` back to its source table.
6. **Unknown handling.** Every dimension is seeded with key `-1` = 'Unknown'. `PROMOTION_DIM` additionally
   seeds key `0` = 'No Promotion'. `DATE_DIM`'s `-1` row uses `cal_date = 1900-01-01`. The operational
   identifier column is the one column left nullable so that this seeded row — which has no counterpart in
   the operational system — does not violate its foreign key.
7. **Grain-enforcing UNIQUE constraints.** The composite primary keys follow the sample convention, but each
   fact also carries a `UNIQUE` constraint on its true grain. This is required because `CUSTOMER_DIM` is Type
   2: if an order were re-read after the customer changed version, the composite PK alone would accept the
   same order line again under a new `customer_key` and revenue would be **double counted**.
8. **Promotion fan-out rule.** `ItemPromotion` is many-to-many, so one item can sit in two overlapping
   promotions at once. ETL rule: *where more than one promotion is active for an item on the order date,
   apply the one with the highest discount value; ties broken by lowest `PromotionID`.*
9. **No cost or gross-profit measures.** The operational system records **no cost column anywhere** —
   `Item.UnitPrice` is a selling price and `ItemPromotion.PromoPrice` is a discounted selling price.
   Profitability is analysed through discount leakage and net-of-returns revenue instead.
10. **Dimension attributes are never NULL.** Text attributes default to `'Unknown'`, `festive_event` to
    `'None'`, `effective_end_date` to `9999-12-31`. This matters because `WHERE festive_event <> 'Deepavali'`
    silently drops NULL rows.
11. **Warehouse CHECK lists are deliberately wider than the source.** Each carries an extra `'Unknown'` (and
    `'None'` for promotions) value so the seeded default rows are legal.
12. **No staff or employee dimension** — the operational system has no `Staff` table.
13. **Deliberately out of scope:** `Payment`, `Voucher`, `BranchStock`, `ItemPromotion` (used in ETL only,
    not modelled as a dimension). Naming what was excluded and why reads as a scoping decision; leaving it
    silent reads as an oversight.

---

## 6. Source-to-target lineage — every column has a home

| Warehouse target | Operational source |
|---|---|
| `SALES_FACT.quantity` / `unitPrice` | `OrderDetails.Quantity` / `UnitPrice` |
| `SALES_FACT.orderType` / `orderHour` | `Orders.OrderType` / `Orders.OrderDateTime` |
| `SALES_FACT.gross/discount/netSalesAmt` | derived from `OrderDetails` + `ItemPromotion.PromoPrice` |
| `RETURN_FACT.quantityReturned` / `refundAmount` | `ReturnDetails.QuantityReturned` / `RefundAmount` |
| `RETURN_FACT.returnStatus` / `daysToReturn` | `Returns.Status` / `Returns.ReturnDate − Orders.OrderDateTime` |
| `DELIVERY_FACT.deliveryCharge` / `deliveryStatus` | `Delivery.DeliveryCharge` / `Delivery.Status` |
| `DELIVERY_FACT.orderTotalAmount` / `deliveryLeadDays` | `Orders.TotalAmount` / `Delivery.DeliveryDate − Orders.OrderDateTime` |
| `POINT_FACT.pointsEarned` / `pointsRedeemed` | `PointTransaction.Point` split by `TransType` |
| `CUSTOMER_DIM` | `Customer` + `Member` + `MembershipType` |
| `ITEM_DIM` | `Item` + `Category` + `Supplier` |
| `BRANCH_DIM` | `Branch` (+ derived `branchName`, `branchRegion`) |
| `ADDRESS_DIM` | `MemberAddress` (+ derived `addressRegion`) |
| `PROMOTION_DIM` | `Promotion` (+ derived `promoDurationDays`) |
| `RETURN_REASON_DIM` | `ReturnReason` (+ derived `reasonCategory`) |
| `DELIVERY_COMPANY_DIM` | `DeliveryCompany` |
| `DATE_DIM` | generated calendar |

---

## 7. Data-quality checks to reuse in Task 2 (15 marks for scrubbing)

| Check | Rule |
|---|---|
| Order line arithmetic | `ABS(OrderDetails.Subtotal − Quantity*UnitPrice) > 0.01` → flag `dq_flag = 'S'` |
| Return total | `SUM(ReturnDetails.RefundAmount)` must equal `Returns.TotalRefundAmount` |
| Order total | `SUM(OrderDetails.Subtotal)` vs `Orders.TotalAmount` — a difference is expected where a delivery charge or voucher applies; state this boundary explicitly |
| Missing customer detail | `Customer.ICNo` and `Customer.Email` are nullable in the source → default to `'Unknown'`, set `dq_flag = 'D'` |
| Unresolvable promotion | promotion reference not found → `promo_key = -1`, `dq_flag = 'D'` |
| Undelivered order | `Delivery.DeliveryDate IS NULL` → `delivery_date_key = -1`, `deliveryLeadDays` NULL |
| Point balance reconciliation | `SUM(POINT_FACT.netPoints)` per customer must equal `Member.PointsBalance` |

---

## 8. Task 3 report angles this schema supports (45 marks, 3 reports per student)

1. Revenue and **discount leakage** by region / branch / month
2. **Return rate and refund exposure** by item, category and supplier; controllable (Fulfilment) vs
   uncontrollable (Product Quality) reasons
3. **Membership tier value and migration** over time — uses the Type 2 history directly
4. **Promotion effectiveness net of returns** — a promotion that lifts gross sales but also lifts returns is
   not a win
5. **Courier performance** — lead days, cancellation rate and delivery charge recovery by company and
   ship-to region
6. **Loyalty programme ROI** — earn vs redeem, and whether VIP members (2 points/RM) outspend Normal
   members (1 point/RM) by enough to justify the RM12 annual fee
7. **Peak trading hours** by branch, using `orderHour`
8. **Branch-sold vs ship-to state mismatch** — where demand is coming from versus where the branches are
