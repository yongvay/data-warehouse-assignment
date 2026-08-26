# Task 3 — 12 Analytical Report Ideas (88 Speedmart DW)

**Context:** Task 3 is an *individual* task — each student produces **3 reports**. 12 ideas = 4 students × 3 reports, grouped below so no two students overlap on the same fact/dimension combination.

**Complexity target (matched to `Chapter 3 - Sample.pdf`):**

- SQL*Plus formatting: `SET`, `ACCEPT` parameter, `TTITLE`, `COLUMN … HEADING/FORMAT`, `BREAK`, `COMPUTE SUM`
- One `WITH` block of 3–5 CTEs: current period → prior period → (optional second fact) → `CASE` pivot → final `SELECT`
- Final select carries: pivoted period columns, a total, a growth %, a share %, and a `RANK() OVER (...)`
- 2–3 dimensions + 1–2 facts. No cubes, no statistics, no PL/SQL.
- Output = formatted table + 2 charts (usually 1 bar/stacked-column + 1 line or pie) + a 4-paragraph justification (column purposes → what the data says → why/what caused it → what management should do).

**Star schema available**

| Fact | Grain | Key measures |
|---|---|---|
| `sales_fact` | one order line | `quantity`, `unit_price`, `gross_sales_amt`, `discount_amt`, `net_sales_amt`, `order_type`, `order_hour` |
| `return_fact` | one return line | `quantity_returned`, `refund_amount`, `days_to_return`, `return_status` |
| `delivery_fact` | one delivery | `delivery_charge`, `order_total_amount`, `delivery_lead_days`, `delivery_status` |
| `point_fact` | one point transaction | `points_earned`, `points_redeemed`, `net_points`, `trans_type` |

Dimensions: `date_dim`, `customer_dim` (SCD2, `member_flag` / `membership_type` / `customer_status`), `item_dim` (`category_name`, `supplier_name`, `item_status`), `branch_dim` (`branch_city`, `branch_state`, `branch_region`), `promotion_dim`, `return_reason_dim` (`reason_category` = Fulfilment / Product Quality), `delivery_company_dim`, `address_dim` (`address_region`).

> ⚠️ **Data-span check before you pick:** any report with a YoY column needs order dates spanning **two calendar years**. If your generated data only covers one year, swap YoY for **quarter-over-quarter** or **month-over-month** — same SQL shape, just a different offset.

---

## Student A (Xing Szen) — Sales & Product Performance

### A1. Quarterly Sales Trend & Seasonality by Item Category
- **Question:** Which grocery categories drive revenue, and when in the year do they peak?
- **Facts / Dims:** `sales_fact` + `date_dim` + `item_dim`
- **Columns:** Rank | Category | Q1 | Q2 | Q3 | Q4 | Total Net Sales | Peak Quarter | YoY Growth % | Category Share %
- **Charts:** Stacked column (Q1–Q4 per category) + line (YoY growth % vs share %)
- **Angle:** Seasonality drives purchasing calendar — which categories to bulk-order before their peak quarter, which to sunset. *(This is the direct analogue of the sample report — safest choice.)*

### A2. Supplier Contribution & Quality Scorecard
- **Question:** Which suppliers give us the most revenue, and which cost us the most in returns?
- **Facts / Dims:** `sales_fact` + `return_fact` + `item_dim`
- **Columns:** Rank | Supplier | Active SKUs | Qty Sold | Net Sales | Sales Share % | Qty Returned | Refund Amount | Return Rate % | Net Contribution
- **Charts:** Bar (net sales by supplier) + line/combo (return rate % overlaid)
- **Angle:** Revenue alone is misleading — a top-3 supplier with a high return rate is a renegotiation or delisting candidate.

### A3. Online vs Walk-in Channel Mix by Month
- **Question:** Is the online channel growing, and does it behave differently from walk-in?
- **Facts / Dims:** `sales_fact` + `date_dim` (+ `customer_dim` for member flag)
- **Columns:** Month | Online Orders | Walk-in Orders | Online Net Sales | Walk-in Net Sales | Online Share % | Online AOV | Walk-in AOV | MoM Growth %
- **Charts:** 100% stacked column (channel share by month) + line (AOV of both channels)
- **Angle:** If online AOV is higher but volume share is flat, the fix is acquisition, not merchandising — informs where the marketing budget goes.

---

## Student B (Zhi Xuan) — Branch & Regional Operations

### B1. Branch Performance Scorecard by Region
- **Question:** Which branches out- and under-perform their region?
- **Facts / Dims:** `sales_fact` + `branch_dim` + `date_dim`
- **Columns:** Region | Branch | Orders | Net Sales | Avg Order Value | Items per Order | YoY Growth % | Share of Region % | Rank in Region
- **Charts:** Horizontal bar (net sales by branch, colour-grouped by region) + line (regional YoY growth)
- **Angle:** Use `BREAK ON region SKIP 1` with `COMPUTE SUM` for regional subtotals — makes the "who's dragging the region down" story obvious.

### B2. Peak Trading Hours & Weekday/Weekend Pattern by Region
- **Question:** When are we busiest, and does the pattern differ North vs Central vs East Malaysia?
- **Facts / Dims:** `sales_fact` (`order_hour`) + `date_dim` (`weekday_ind`, `day_week`) + `branch_dim`
- **Columns:** Region | Morning (6–11) | Afternoon (12–17) | Evening (18–22) | Night (23–5) | Peak Block | Weekday Sales | Weekend Sales | Weekend Share % | Rank
- **Charts:** Grouped column (hour block × region) + line (weekday vs weekend trend)
- **Angle:** Direct staff-rostering and delivery-slot decisions — extend evening shifts only in regions where the evening block dominates.

### B3. Branch Return Leakage Analysis
- **Question:** Which branches lose the largest share of revenue to refunds?
- **Facts / Dims:** `sales_fact` + `return_fact` + `branch_dim` + `return_reason_dim`
- **Columns:** Region | Branch | Net Sales | Refund Amount | Refund-to-Sales % | Fulfilment-Cause Returns | Quality-Cause Returns | Avg Days to Return | Rank (worst first)
- **Charts:** Bar (refund-to-sales % by branch with a company-average reference line) + stacked bar (Fulfilment vs Product Quality split)
- **Angle:** Fulfilment-caused returns = a branch process problem (retrain, re-pick); quality-caused = a supplier or cold-chain problem. Different owner, different fix.

---

## Student C (Yong Vay) — Customer, Membership & Loyalty

### C1. Membership Tier Value Analysis (VIP vs Normal vs Non-Member)
- **Question:** Is the RM12/year VIP tier actually earning its keep?
- **Facts / Dims:** `sales_fact` + `customer_dim` + `date_dim`
- **Columns:** Tier | Customers | Orders | Orders per Customer | Net Sales | Sales Share % | Avg Order Value | Spend per Customer | Annual Fee Revenue | YoY Growth %
- **Charts:** Grouped column (spend per customer & AOV by tier) + pie (sales share by tier)
- **Angle:** Compare VIP spend-per-customer against Normal. If the gap doesn't cover the 2× point-earn cost, the tier economics need repricing.

### C2. Loyalty Points Earn vs Redeem & Outstanding Liability
- **Question:** Are points being redeemed, or are we accumulating an unfunded liability?
- **Facts / Dims:** `point_fact` + `customer_dim` + `date_dim`
- **Columns:** Month | Points Earned | Points Redeemed | Net Points | Redemption Rate % | Cumulative Balance | VIP Share of Earnings % | MoM Change %
- **Charts:** Combo column+line (earned vs redeemed bars, cumulative balance line) + pie (earn vs redeem by tier)
- **Angle:** A low redemption rate with a rising balance is a growing liability *and* a sign the reward catalogue is unattractive — triggers a voucher campaign or an expiry policy.

### C3. Customer Retention & Dormancy by State
- **Question:** Where are we losing customers?
- **Facts / Dims:** `sales_fact` + `customer_dim` + `branch_dim` (or `address_dim`)
- **Columns:** State | City | Active Customers | Dormant Customers (no order in last 6 months) | Retention Rate % | Dormancy Rate % | Avg Months Since Last Order | State Share of Base %
- **Charts:** Bar (retention rate % by state) + line (active customer count by month)
- **Angle:** Mirrors sample report 3.1.2. Rank states by dormancy to target win-back vouchers where the leakage is worst rather than spraying nationally.

---

## Student D (Pei Qi) — Returns, Delivery & Promotions

### D1. Return Reason Analysis by Item Category
- **Question:** What are we getting back, and why?
- **Facts / Dims:** `return_fact` + `return_reason_dim` + `item_dim` (+ `sales_fact` for the denominator)
- **Columns:** Rank | Category | Missing | Broken | Expired | Wrong Item | Total Qty Returned | Refund Amount | Return Rate % (vs qty sold) | Avg Days to Return
- **Charts:** Stacked column (reason mix per category) + pie (refund value by reason category)
- **Angle:** "Expired" concentrated in Fresh/Dairy = stock rotation failure; "Wrong Item" concentrated in one category = picking/labelling failure. Each maps to a named corrective action.

### D2. Delivery Partner Performance by Region
- **Question:** Which courier should get more volume, and where?
- **Facts / Dims:** `delivery_fact` + `delivery_company_dim` + `address_dim` (+ `date_dim`)
- **Columns:** Region | Delivery Company | Deliveries | Volume Share % | Avg Lead Days | On-Time % (lead ≤ 3 days) | Cancelled % | Avg Delivery Charge | Cost per Delivered Order | Rank
- **Charts:** Grouped bar (avg lead days by courier × region) + line (on-time % trend by month)
- **Angle:** A courier that is cheapest but slowest in East Malaysia is a false economy once cancellations are priced in — supports a region-by-region contract split.

### D3. Promotion Effectiveness & Discount ROI
- **Question:** Did each campaign generate real uplift, or did we just discount sales we would have made anyway?
- **Facts / Dims:** `sales_fact` + `promotion_dim` + `item_dim` (+ `return_fact` for promo-item returns)
- **Columns:** Rank | Promotion | Discount Type | Duration (days) | Qty Sold | Gross Sales | Discount Given | Net Sales | Discount-to-Gross % | Sales per Promo Day | Uplift vs Non-Promo Baseline %
- **Charts:** Combo (net sales bars vs discount-to-gross % line per campaign) + bar (promo vs non-promo sales for the same items)
- **Angle:** Rank campaigns by uplift-per-ringgit-discounted. Percentage vs Fixed discount types usually behave very differently on low-price grocery items — that comparison alone is a strong recommendation.

---

## Quick selection guide

| If you want… | Pick |
|---|---|
| Closest match to the marked sample | A1, C3 |
| Two facts in one query (shows more skill) | A2, B3, D1, D3 |
| Strongest management/decision story | B3, C2, D2 |
| Safest if your data only spans one year | B2, C1, D1, D2 (no YoY needed) |

**Coverage check:** all 4 fact tables and all 8 dimensions are used at least once across the 12; no two students share the same fact + dimension pairing, so the reports won't read as duplicates in the final compiled document.
