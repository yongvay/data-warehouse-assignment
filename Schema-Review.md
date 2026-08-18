# Star Schema Design Review — BMIT3003 Task 1(a)

**Reviewed against:** `01 Assignment Question.pdf` and the source OLTP ERD (`ADM Task 1.png`)
**Date:** 18 August 2026
**Scope rule applied:** the ADM ERD is the *only* permitted source. Any DW column with no lineage back to it is treated as a defect.

---

## Verdict

The **shape** of the model is right. Grain is transactional in both facts, dimensions are properly denormalised (no snowflaking), the conformed-dimension story is correct, and the Type 2 requirement is met. That is a genuinely good starting point.

But it is **not ready to code**. There are **6 blocking defects** — two of which (unsourceable columns, and primary keys that do not enforce the grain) will hurt you in Task 1(b) *and* Task 2, because you cannot write a source-to-target mapping for columns that have no source, and you cannot write a safe incremental load against a PK that does not identify a row.

Fix the six below, adopt the should-fixes, and this becomes a strong submission.

---

## 1. What is correct — keep it

| # | Item | Why it's right |
|---|---|---|
| 1 | **Fact constellation with conformed dimensions** | DATE, PRODUCT, CUSTOMER, BRANCH are shared by both facts with identical keys and identical meaning. That is the textbook definition of conformed. Your note calling it a galaxy schema is accurate. |
| 2 | **Grain choice** | SALES_FACT at order-line level maps 1:1 to `OrderDetails`; RETURNS_FACT at returned-line level maps 1:1 to `ReturnDetails`. Both are atomic. Do not aggregate. |
| 3 | **Role-playing DATE_DIM** | One physical calendar referenced three times is correct, and far better than building three separate date tables. |
| 4 | **CUSTOMER_DIM as the Type 2** | Correct choice — membership tier and customer status are exactly the attributes whose history matters. Satisfies the rubric's "at least one Type 2". |
| 5 | **Denormalising Category and Supplier into PRODUCT_DIM** | Correct. `Item → Category` and `Item → Supplier` are both M:1, so flattening loses nothing and avoids a snowflake. |
| 6 | **Denormalising Member + MembershipType into CUSTOMER_DIM** | Correct. `Member` is a 1:1 subtype of `Customer`, so one row per customer with a `member_flag` is the right shape. |
| 7 | **Surrogate keys everywhere + natural key retained** | Correct DW practice. |
| 8 | **The `-1` Unknown row seeded per dimension** | Correct, and exactly what the Task 2 dirty-data marks are looking for. (One refinement — see S1.) |
| 9 | **`order_no` / `return_id` carried into the facts** | Correct use of degenerate dimensions; they give you drill-back to the operational system. |
| 10 | **`days_to_return` pre-computed** | Good. Computing it in ETL rather than at query time is right. |
| 11 | **Leaving `PointBalance` out of CUSTOMER_DIM** | Whether deliberate or not, this is correct. A balance that changes on every transaction would explode your Type 2 versions. Do not be tempted to add it. |

---

## 2. Blocking defects — fix before writing DDL

### B1. The composite primary keys do not enforce the stated grain

**SALES_FACT** declares `PK(date_key, customer_key, product_key, branch_key, promo_key, order_no)` — six columns.

The minimal key for the declared grain is **`(order_no, product_key)`** — that is exactly the PK of `OrderDetails`. Everything else (`date_key`, `customer_key`, `branch_key`, `promo_key`) is functionally determined by `order_no`, so adding them to the PK does not tighten it. It *loosens* it: the PK will happily accept the same order line twice as long as any one of those four columns differs.

This is not theoretical. **CUSTOMER_DIM is Type 2.** When a customer upgrades from Silver to Gold, they get a new `customer_key`. If your subsequent-load script re-reads an order that was already loaded, the six-column PK sees a different `customer_key` and lets the duplicate through. You will silently double-count revenue — and "handle dirty data and maintain data integrity" is where 15 of your marks live.

**RETURNS_FACT** has the same problem. Minimal key is **`(return_id, product_key)`** (`order_no` is functionally determined by `return_id`, since a return belongs to exactly one order).

**Fix**

- `SALES_FACT` → `PRIMARY KEY (order_no, product_key)`; all dimension keys become plain `NOT NULL` FKs.
- `RETURNS_FACT` → `PRIMARY KEY (return_id, product_key)`; keep `order_no` as a `NOT NULL` degenerate column.
- Index the dimension FKs separately for query performance — that is what they are for, not the PK.

> **Watch out:** `(order_no, product_key)` is only safe because PRODUCT_DIM is Type 1, so one `itemID` maps to exactly one `product_key`. If you later make PRODUCT_DIM Type 2, the PK must become `(order_no, item_id)` using the durable natural key.

### B2. `unit_cost`, `total_cost_amt` and `gross_profit_amt` have no source

There is **no cost column anywhere in the ADM ERD.** `Item` has `UnitPrice` (the selling price). `Supplier` has `SupplierID`, `SupplierName`, `ContactNo` — no cost. `ItemPromotion.PromoPrice` is a discounted *selling* price, not a cost.

The label "unit_cost (from Supplier/Item)" in your diagram points at columns that do not exist. In Task 2 you will be asked to show the source-to-target mapping and there is nothing to put in the source column. In Task 3, any gross-profit report built on it is fabricated data.

**Fix — pick one and state it explicitly in the report:**

- **(a) Drop them** *(recommended given your source constraint)*. Re-point your profitability angle at **discount effectiveness and revenue leakage** instead: `discount_amt` as a % of `gross_sales_amt`, net revenue after returns, refund exposure by product and reason. These are fully sourced and are just as strong for management commentary.
- **(b) Extend the operational source.** Add `Item.UnitCost` to the ADM design, document it in "System Overview & Background" as a scope extension, and restore all three measures. This is a one-column change and is defensible — but only if you say you did it. Do not smuggle it in.

### B3. BRANCH_DIM is roughly 80% unsourceable

Source `Branch` has exactly four columns: `BranchID`, `City`, `State`, `ContactNo`.

| Your BRANCH_DIM column | Source? |
|---|---|
| `branchID`, `city`, `state`, `contact_no` | Yes |
| `region` | Derivable from `state` via a documented mapping — keep |
| `branch_name` | No — derivable as a formatted label (e.g. `City \|\| ' Branch'`) if you document the rule |
| `branch_type`, `address_line`, `postcode`, `email`, `manager_name`, `opening_date`, `floor_area_sqft`, `no_of_staff`, `branch_status` | **No source at all** |

Nine invented columns is the single most visible problem in the diagram — it reads as if the DW was designed without looking at the source.

**Fix:** cut BRANCH_DIM to `branch_key, branchID, branch_name (derived), city, state, region (derived), contact_no`. A thin dimension is not a weakness; region / state / city still supports every branch and geography report you need for Task 3. If you want the richer version, extend `Branch` in the OLTP first (option (b) above) and say so.

### B4. Natural keys are mislabelled as foreign keys

Every dimension marks its business key as **FK**: `PRODUCT_DIM.itemID (FK)`, `CUSTOMER_DIM.customerID (FK)`, `BRANCH_DIM.branchID (FK)`, `PROMOTION_DIM.promotionID (FK)`, `RETURN_REASON_DIM.reasonID (FK)`.

These are **not** foreign keys. A foreign key references a parent table inside the warehouse, and there is no parent — the operational database is not part of the DW. They are **natural keys** (also called business or durable keys), and they should be labelled **NK** and enforced with a `UNIQUE` constraint, not a `REFERENCES` clause. A marker will notice this immediately.

**Fix**

- Type 1 dimensions (PRODUCT, BRANCH, PROMOTION, RETURN_REASON): `NK`, with `UNIQUE (natural_key)`.
- **CUSTOMER_DIM is Type 2, so `customerID` is deliberately NOT unique** — one customer has many versions. The correct constraint is `UNIQUE (customerID, effective_start_date)` (or `UNIQUE (customerID, version_no)`). Getting this right is direct evidence you understand SCD2, so make it visible in your DDL.

### B5. `promo_key` inside the PK creates a real double-counting risk

`ItemPromotion` is many-to-many: one item can sit in **two overlapping promotions** at the same time. Because `promo_key` is part of the SALES_FACT PK, an ETL join that finds two active promotions for an item on the order date will produce **two fact rows for one order line** — and the PK will not stop it. That is fan-out, and it inflates your revenue.

**Fix**

1. Remove `promo_key` from the PK (already covered by B1).
2. Write an explicit deduplication rule into the ETL and state it in the report, e.g.: *"where more than one promotion is active for an item on the order date, the one with the highest discount value is applied; ties broken by lowest PromotionID."*
3. Enforce it with `ROW_NUMBER() OVER (PARTITION BY OrderNo, ItemID ORDER BY DiscountValue DESC, PromotionID) = 1` in the load view.

### B6. `gross_sales_amt` and `subtotal` are the same number

You store `subtotal` (from `OrderDetails.Subtotal`) *and* `gross_sales_amt (quantity * unit_price)`. In the source, `Subtotal` is `Quantity × UnitPrice`. Storing both is redundant, and worse, if they ever disagree no one knows which is authoritative.

**Fix — and turn it into marks:** store the computed `gross_sales_amt = quantity * unit_price` only, and use `OrderDetails.Subtotal` as a **data-quality check** in Task 2: reject or flag any line where `ABS(Subtotal - Quantity*UnitPrice) > 0.01`. That is exactly the "scrubbing dirty data" evidence the rubric asks for, and it costs you one extra `CASE` expression.

---

## 3. Should-fix — marks at risk

**S1. `-1` conflates "Unknown" with "No promotion".**
Your note says non-promotional sales point to `promo_key = -1`. But `-1` also means "the source data was dirty and we could not resolve it". Those are different facts and you will not be able to tell them apart when reporting promotion coverage.
→ Seed **two** rows in PROMOTION_DIM: `0 = 'No Promotion'` and `-1 = 'Unknown'`. Non-promo sales get `0`; unresolvable promo references get `-1`.

**S2. No ETL audit columns anywhere.** Task 2 is worth 30 marks and is entirely about initial vs. incremental loading. Without audit columns you cannot demonstrate incremental behaviour or prove a load ran.
→ Add to every fact and dimension: `etl_batch_id`, `etl_load_dt`, `etl_update_dt`, `dq_flag` (`'V'` valid / `'S'` scrubbed / `'D'` defaulted), `source_system`. Consider a small `ETL_AUDIT_LOG` control table (batch id, table name, rows read / inserted / updated / rejected, start, end, status) — it is cheap and it is very visible evidence for the rubric.

**S3. NULLs in dimension attributes.** `DATE_DIM.festive_event (NULL initially)` and an open-ended `CUSTOMER_DIM.effective_end_date` will both be NULL. Kimball's rule is that dimension attributes are never NULL, because `WHERE festive_event <> 'Deepavali'` silently drops NULL rows.
→ `festive_event DEFAULT 'None'`; `effective_end_date DEFAULT DATE '9999-12-31'`. Keep `is_current_flag` as the fast filter.

**S4. `order_type` and `return_status` are text flags sitting in fact tables.** Not fatal — a lone low-cardinality flag qualifying the event is defensible — but constrain them: store short codes with a `CHECK` constraint rather than free text. If you later bring `Payment.Status` or a delivery flag into scope, combine them into an `ORDER_JUNK_DIM`; a junk dimension only earns its keep once you have two or more flags to cross.

**S5. SCD2 join semantics are undocumented.** With a Type 2 CUSTOMER_DIM you must state which version a fact points to. The standard answer: **the version current at the time of the event** — so SALES_FACT gets the customer version valid on the order date, and RETURNS_FACT gets the version valid on the *return* date. Write that sentence into the report; it is the difference between "we used SCD2" and "we understand SCD2".

**S6. RETURNS_FACT cannot analyse returns against promotions.** Adding `promo_key` to RETURNS_FACT (inherited from the matching sales line) unlocks a strong Task 3 report: *do discounted items get returned more often?* Cheap to populate, high analytical value.

**S7. Role-playing needs views to be usable.** Physically you have one DATE_DIM, but a BI tool cannot join it twice to RETURNS_FACT without aliasing. Create `ORDER_DATE_DIM` and `RETURN_DATE_DIM` as `CREATE VIEW ... AS SELECT ... FROM DATE_DIM` with renamed columns. The rubric explicitly asks for VIEWS in Task 2 — this is a free place to use them.

**S8. PRODUCT_DIM is missing the list price.** `Item.UnitPrice` is the current catalogue price and it is not in the dimension. Add `current_unit_price` — it lets you measure realised price vs. list price, which is a good discount-leakage report.

**S9. Time of day is thrown away.** `Orders.OrderDateTime` has a time component, but DATE_DIM is day-grain only. Peak-hour analysis is one of the most natural retail reports and you currently cannot do it.
→ Either add `order_hour` (0–23) directly to SALES_FACT, or add a proper `TIME_DIM`. The `order_hour` column is the cheap 90% answer.

**S10. Reconciliation gaps worth writing up as DQ checks.**
- `SUM(OrderDetails.Subtotal) ≠ Orders.TotalAmount` — because `TotalAmount` also absorbs delivery charges and voucher redemptions, neither of which is in scope. Say this explicitly so the marker knows it is a deliberate boundary, not an error.
- `SUM(ReturnDetails.RefundAmount)` should equal `Returns.TotalRefundAmount` — make it a Task 2 validation rule.

**S11. `RETURNS_FACT.branch_key` is an assumption.** `Returns` has no `BranchID`, so the branch must come from the original `Orders` row. That means you are modelling *the branch that sold the item*, not the branch that processed the return. State the assumption; if cross-branch returns are possible in your business rules, the model cannot currently express them.

**S12. Naming consistency.** You mix `snake_case` (`product_key`, `net_sales_amt`) with `camelCase` natural keys (`itemID`, `customerID`, `branchID`). Pick one — `item_id`, `customer_id`, `branch_id` — and apply it everywhere. Also consider renaming `SALES_FACT.date_key` to `order_date_key` so it conforms with RETURNS_FACT. Cheap marks under "clarity".

---

## 4. Corrected schema

### SALES_FACT — grain: one row per item line per order (source: `OrderDetails`)

```
PK  (order_no, product_key)
FK  order_date_key   -> DATE_DIM        NOT NULL
FK  customer_key     -> CUSTOMER_DIM    NOT NULL   (version current at order date)
FK  product_key      -> PRODUCT_DIM     NOT NULL
FK  branch_key       -> BRANCH_DIM      NOT NULL
FK  promo_key        -> PROMOTION_DIM   NOT NULL   (0 = No Promotion)
DD  order_no                            NOT NULL
    order_type                CHECK IN (...)
    order_hour                0-23
    quantity                  additive
    unit_price                non-additive
    gross_sales_amt           additive     = quantity * unit_price
    discount_amt              additive     = (unit_price - promo_price) * quantity, else 0
    net_sales_amt             additive     = gross_sales_amt - discount_amt
    etl_batch_id / etl_load_dt / etl_update_dt / dq_flag
```
*Removed:* `subtotal` (duplicate of `gross_sales_amt`), `unit_cost`, `total_cost_amt`, `gross_profit_amt` (no source).

### RETURNS_FACT — grain: one row per returned item line (source: `ReturnDetails`)

```
PK  (return_id, product_key)
FK  return_date_key  -> DATE_DIM        NOT NULL   (role: return date)
FK  order_date_key   -> DATE_DIM        NOT NULL   (role: original order date)
FK  customer_key     -> CUSTOMER_DIM    NOT NULL   (version current at return date)
FK  product_key      -> PRODUCT_DIM     NOT NULL
FK  branch_key       -> BRANCH_DIM      NOT NULL   (branch of original sale)
FK  reason_key       -> RETURN_REASON_DIM NOT NULL
FK  promo_key        -> PROMOTION_DIM   NOT NULL   (inherited from the sales line)  [new]
DD  return_id, order_no                 NOT NULL
    return_status             CHECK IN ('Approved','Rejected','Pending')
    quantity_returned         additive
    refund_amount             additive
    days_to_return            non-additive (average it, never sum it)
    etl_batch_id / etl_load_dt / etl_update_dt / dq_flag
```

### CUSTOMER_DIM — Type 2

```
PK  customer_key (surrogate)
NK  customer_id            UNIQUE (customer_id, effective_start_date)
    customer_name, ic_no, email, customer_status
    member_flag ('Y'/'N')  -- derived: EXISTS in Member
    membership_type        -- MembershipType.TypeName,  'Non-Member' if not a member
    membership_fee         -- MembershipType.AnnualFee, 0 if not a member
    effective_start_date
    effective_end_date  DEFAULT DATE '9999-12-31'
    is_current_flag     CHAR(1) 'Y'/'N'
    version_no
    etl audit columns
```
Type 2 triggers on: `membership_type`, `customer_status`, `member_flag`. Type 1 overwrite on: `customer_name`, `email`, `ic_no` (corrections, not history).
**Do not add `PointBalance`** — it changes on every transaction and would create a new version per order.

### PRODUCT_DIM — Type 1

```
PK  product_key (surrogate)
NK  item_id  UNIQUE
    item_name, item_status
    current_unit_price      -- Item.UnitPrice                      [new]
    category_name           -- Category.CategoryName
    supplier_name           -- Supplier.SupplierName
    supplier_contact_no     -- Supplier.ContactNo
    etl audit columns
```

### BRANCH_DIM — Type 1 (trimmed to what the source can actually supply)

```
PK  branch_key (surrogate)
NK  branch_id  UNIQUE
    branch_name   -- derived: City || ' Branch'  (document the rule)
    city, state
    region        -- derived from state via a documented mapping table
    contact_no
    etl audit columns
```

### PROMOTION_DIM — Type 1

```
PK  promo_key (surrogate)     0 = 'No Promotion',  -1 = 'Unknown'
NK  promotion_id  UNIQUE
    promo_name, discount_type, discount_value
    promo_start_date, promo_end_date, promo_status
    promo_duration_days   -- derived                                [new]
    etl audit columns
```
`ItemPromotion.PromoPrice` is item-specific, so it belongs at fact grain — use it in ETL to compute `discount_amt`, do not store it in the dimension.

### RETURN_REASON_DIM — Type 1

```
PK  reason_key (surrogate)
NK  reason_id  UNIQUE
    reason_name       -- ReturnReason.ReasonName
    reason_category   -- derived; publish the mapping in an appendix
    etl audit columns
```

### DATE_DIM — pre-generated, day grain

Keep your attribute list; apply these changes:

- `date_key` as `INT` in `YYYYMMDD` form (a "smart key"); the Unknown row is `-1` with `cal_date = DATE '1900-01-01'`.
- `festive_event DEFAULT 'None'` — never NULL.
- Add role-playing views `ORDER_DATE_DIM` and `RETURN_DATE_DIM`.

---

## 5. Source-to-target lineage — every remaining column has a home

| DW target | Source |
|---|---|
| SALES_FACT.order_no / quantity / unit_price | `OrderDetails.OrderNo / Quantity / UnitPrice` |
| SALES_FACT.order_type / order_hour | `Orders.OrderType` / `Orders.OrderDateTime` |
| SALES_FACT.gross / discount / net | derived (see rules above) from `OrderDetails` + `ItemPromotion` |
| RETURNS_FACT.quantity_returned / refund_amount | `ReturnDetails.QuantityReturned / RefundAmount` |
| RETURNS_FACT.return_status / days_to_return | `Returns.Status` / `Returns.ReturnDate − Orders.OrderDateTime` |
| CUSTOMER_DIM | `Customer` + `Member` + `MembershipType` |
| PRODUCT_DIM | `Item` + `Category` + `Supplier` |
| BRANCH_DIM | `Branch` (+ derived region) |
| PROMOTION_DIM | `Promotion` |
| RETURN_REASON_DIM | `ReturnReason` (+ derived category) |
| DATE_DIM | generated calendar |

**Deliberately out of scope — say so in the report:** `Payment`, `Delivery`, `DeliveryCompany`, `Voucher`, `PointTransaction`, `MemberAddress`, `BranchStock`. Naming what you excluded and why reads as a scoping decision; leaving it silent reads as an oversight.

---

## 6. Does it still support Task 3? (45 marks — the biggest block)

Yes — every one of these is answerable from the corrected schema:

1. **Revenue and discount leakage by region / branch / month** — Are the discounts we give actually buying us volume, or are we just eroding margin in our strongest regions?
2. **Return rate and refund exposure by product, category and supplier** — Which suppliers are costing us money after the sale, and which return reasons are within our control (Fulfilment) vs. not (Customer)?
3. **Membership tier value and migration over time** — Uses the Type 2 history directly, which is the strongest possible demonstration that your SCD2 works. Do Silver→Gold upgrades change basket size, and how quickly?
4. **Promotion effectiveness with returns netted off** — enabled by adding `promo_key` to RETURNS_FACT (S6). A promotion that lifts gross sales but also lifts returns is not a win.

The one report you lose by dropping the cost measures is true gross-profit analysis. Report 1 covers most of that ground using discount leakage instead.

---

## 7. Priority order

| Priority | Items |
|---|---|
| **Before any DDL** | B1 (PKs), B2 (drop or source the cost measures), B3 (trim BRANCH_DIM), B4 (NK not FK), B5 (promo dedup rule), B6 (drop `subtotal`) |
| **While writing DDL** | S1 (promo key 0), S2 (audit columns), S3 (no NULLs), S4 (CHECK constraints), S8, S9 |
| **Before ETL** | S5 (SCD2 join rule), S6 (promo_key on returns), S7 (role-playing views), S10 (DQ reconciliation rules), S11 (branch assumption) |
| **Final polish** | S12 (naming consistency) |
