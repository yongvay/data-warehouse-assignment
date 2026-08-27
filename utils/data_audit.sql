-- ============================================================================
--  utils/data_audit.sql   -   RUN AS THE DW USER
--
--      SQL> @"utils\data_audit.sql"
--
--  A plausibility audit, not a constraint audit.  final_acceptance.sql already
--  proves the warehouse is internally CORRECT - every FK resolves, every CHECK
--  holds, nothing reconciles wrong.  This script asks a different question:
--  is the data BELIEVABLE, and is there anything an examiner could point at
--  and ask "how can that be true?"
--
--  Severity column:
--    BLOCKER  - fix before submission
--    REPORT   - not wrong, but must be explained in the write-up
--    COSMETIC - note it if you have time
--
--  Nothing here is a pass/fail gate.  Read the counts and decide.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 170
SET PAGESIZE 300
COLUMN severity   FORMAT A9
COLUMN finding    FORMAT A62
COLUMN detail     FORMAT A46
COLUMN item_name  FORMAT A34
COLUMN category   FORMAT A22
COLUMN supplier   FORMAT A34

PROMPT
PROMPT ####################################################################
PROMPT #  PLAUSIBILITY AUDIT                                              #
PROMPT ####################################################################
WITH findings AS (
    -- ---------- PRODUCT LIFECYCLE ----------
    SELECT 'BLOCKER' AS severity,
           'Order lines selling items still marked Pending QC' AS finding,
           COUNT(*) AS how_many,
           'Not approved for sale, yet sold' AS detail
    FROM   sales_fact s JOIN item_dim i ON i.item_key = s.item_key
    WHERE  i.item_status = 'Pending QC'
    UNION ALL
    SELECT 'REPORT',
           'Discontinued items sold in 2022 or later',
           COUNT(*),
           'Off the shelf but still transacting'
    FROM   sales_fact s
    JOIN   item_dim i ON i.item_key = s.item_key
    JOIN   date_dim d ON d.date_key = s.order_date_key
    WHERE  i.item_status = 'Discontinued' AND d.cal_year >= 2022
    UNION ALL
    SELECT 'COSMETIC',
           'Promotions attached to items that can never be sold',
           COUNT(*),
           'ItemPromotion rows on Pending QC stock'
    FROM   adm.ItemPromotion ip JOIN adm.Item i ON i.ItemID = ip.ItemID
    WHERE  i.Status = 'Pending QC'
    -- ---------- MEMBERSHIP PLAUSIBILITY ----------
    UNION ALL
    SELECT 'REPORT',
           'Members earning points years before their membership expiry',
           COUNT(DISTINCT p.customer_key),
           'Implies continuous annual renewal'
    FROM   point_fact p
    JOIN   customer_dim c ON c.customer_key = p.customer_key
    JOIN   date_dim    d ON d.date_key      = p.trans_date_key
    WHERE  c.membership_expiry IS NOT NULL
    AND    d.cal_year <= EXTRACT(YEAR FROM c.membership_expiry) - 5
    UNION ALL
    SELECT 'REPORT',
           'Customer versions opening at the 1900 epoch',
           COUNT(*),
           'Dimension cannot date customer acquisition'
    FROM   customer_dim
    WHERE  customer_key <> -1 AND version_no = 1
    AND    effective_start_date = DATE '1900-01-01'
    -- ---------- CALENDAR ATTRIBUTES NEVER POPULATED ----------
    UNION ALL
    SELECT 'BLOCKER',
           'Calendar days flagged as a public holiday',
           COUNT(*),
           'holiday_ind is N on every single row'
    FROM   date_dim WHERE holiday_ind = 'Y'
    UNION ALL
    SELECT 'BLOCKER',
           'Calendar days carrying a festive_event label',
           COUNT(*),
           'festive_event is None on every single row'
    FROM   date_dim WHERE festive_event <> 'None'
    -- ---------- DATA QUALITY FLAGS ----------
    UNION ALL
    SELECT 'REPORT',
           'Fact rows ever flagged suspect or dirty',
           (SELECT COUNT(*) FROM sales_fact    WHERE dq_flag <> 'V')
         + (SELECT COUNT(*) FROM return_fact   WHERE dq_flag <> 'V')
         + (SELECT COUNT(*) FROM delivery_fact WHERE dq_flag <> 'V')
         + (SELECT COUNT(*) FROM point_fact    WHERE dq_flag <> 'V'),
           'dq_flag is declared but never written'
    FROM   dual
    -- ---------- ANALYSIS CONFOUNDS ----------
    UNION ALL
    SELECT 'REPORT',
           'Months of 2026 with no data (partial year)',
           12 - COUNT(DISTINCT d.cal_month_year),
           'Plotted raw, 2026 looks like a collapse'
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
    WHERE  d.cal_year = 2026
    UNION ALL
    SELECT 'REPORT',
           'Distinct suppliers whose return rate differs materially',
           0,
           'Returns were drawn uniformly: no real outlier'
    FROM   dual
    -- ---------- ORIGINAL 2024-2026 DATA, NOT GENERATED ----------
    UNION ALL
    SELECT 'REPORT',
           'Deliveries sent to an address that is not the buyers',
           COUNT(*),
           'All in the original pre-expansion rows'
    FROM   adm.Delivery d
    JOIN   adm.Orders o        ON o.OrderNo   = d.OrderNo
    JOIN   adm.MemberAddress a ON a.AddressID = d.AddressID
    WHERE  a.MemberID <> o.CustomerID
    UNION ALL
    SELECT 'REPORT',
           'Deliveries against Walk-in orders',
           COUNT(*),
           'A walk-in customer carried it home'
    FROM   adm.Delivery d JOIN adm.Orders o ON o.OrderNo = d.OrderNo
    WHERE  o.OrderType = 'Walk-in'
    -- NOTE: BranchStock, Payment and Voucher are deliberately NOT granted to
    -- the DW user - Task1b_Grants_RunAsADM.sql lists them as out of warehouse
    -- scope - so nothing here may reference them.  An earlier version did and
    -- took the whole findings query down with ORA-00942.
)
SELECT severity, finding, how_many, detail
FROM   findings
ORDER  BY CASE severity WHEN 'BLOCKER' THEN 1 WHEN 'REPORT' THEN 2 ELSE 3 END,
          how_many DESC, finding;

PROMPT
PROMPT ####################################################################
PROMPT #  SUPPORTING DETAIL                                               #
PROMPT ####################################################################

PROMPT
PROMPT === S1. WHICH ITEMS ARE BEING SOLD WHILE NOT SELLABLE ===
SELECT i.item_id, i.item_name, i.item_status, i.category_name AS category,
       COUNT(*) AS lines_sold,
       MIN(d.cal_year) AS first_year, MAX(d.cal_year) AS last_year
FROM   sales_fact s
JOIN   item_dim i ON i.item_key = s.item_key
JOIN   date_dim d ON d.date_key = s.order_date_key
WHERE  i.item_status IN ('Pending QC', 'Discontinued')
GROUP  BY i.item_id, i.item_name, i.item_status, i.category_name
ORDER  BY i.item_status, lines_sold DESC;

PROMPT
PROMPT === S2. CATEGORY RANGE EXPANSION - the real A1 story ===
PROMPT Expect roughly six categories trading in 2016 rising to twelve by 2023.
SELECT d.cal_year,
       COUNT(DISTINCT i.category_id) AS categories_trading,
       COUNT(DISTINCT i.item_key)    AS items_sold,
       ROUND(SUM(s.net_sales_amt), 2) AS revenue
FROM   sales_fact s
JOIN   item_dim i ON i.item_key = s.item_key
JOIN   date_dim d ON d.date_key = s.order_date_key
GROUP  BY d.cal_year
ORDER  BY d.cal_year;

PROMPT
PROMPT === S3. IS THERE A REAL SUPPLIER QUALITY SIGNAL? ===
PROMPT If return_pct clusters tightly around the average, there is no outlier
PROMPT and a "quality scorecard" would be narrating random noise.
SELECT i.supplier_name AS supplier,
       COUNT(DISTINCT s.order_no || s.item_key) AS lines_sold,
       NVL(SUM(r.qty_returned), 0)              AS units_returned,
       ROUND(100 * NVL(SUM(r.qty_returned), 0)
             / NULLIF(SUM(s.quantity), 0), 2)   AS return_pct
FROM   sales_fact s
JOIN   item_dim i ON i.item_key = s.item_key
LEFT   JOIN ( SELECT item_key, order_no, SUM(quantity_returned) AS qty_returned
              FROM   return_fact GROUP BY item_key, order_no ) r
       ON  r.item_key = s.item_key AND r.order_no = s.order_no
GROUP  BY i.supplier_name
ORDER  BY return_pct DESC;

PROMPT
PROMPT === S4. SEASONALITY, COMPLETE YEARS ONLY (2026 excluded) ===
PROMPT 2026 contributes to Jan-Aug only; including it distorts every month.
SELECT d.cal_month_year AS mth, MIN(d.cal_month_name) AS month_name,
       COUNT(DISTINCT s.order_no) AS orders,
       ROUND(SUM(s.net_sales_amt), 2) AS revenue
FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
WHERE  d.cal_year < 2026
GROUP  BY d.cal_month_year
ORDER  BY mth;

PROMPT
PROMPT === S5. CHANNEL MIX BY REGION, ALL YEARS - DO NOT USE THIS ONE ===
PROMPT Kept only to show the trap. Online share rises every year, and later
PROMPT branches trade ONLY in the online-heavy years, so a region opened in
PROMPT 2021 looks digitally advanced when it is merely young. This table
PROMPT measures branch age, not regional preference.
SELECT b.branch_region,
       COUNT(*) AS order_lines,
       MIN(d.cal_year) AS first_year_trading,
       ROUND(100 * SUM(CASE WHEN s.order_type = 'Online' THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS online_pct
FROM   sales_fact s
JOIN   branch_dim b ON b.branch_key = s.branch_key
JOIN   date_dim   d ON d.date_key   = s.order_date_key
WHERE  b.branch_key <> -1
GROUP  BY b.branch_region
ORDER  BY online_pct DESC;

PROMPT
PROMPT === S5b. CHANNEL MIX BY REGION, 2024-2026 ONLY - USE THIS ONE ===
PROMPT Every region has been trading throughout this window, so the
PROMPT comparison is like for like and any gap is real.
SELECT b.branch_region,
       COUNT(*) AS order_lines,
       SUM(CASE WHEN s.order_type = 'Online' THEN 1 ELSE 0 END) AS online_lines,
       ROUND(100 * SUM(CASE WHEN s.order_type = 'Online' THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS online_pct
FROM   sales_fact s
JOIN   branch_dim b ON b.branch_key = s.branch_key
JOIN   date_dim   d ON d.date_key   = s.order_date_key
WHERE  b.branch_key <> -1 AND d.cal_year >= 2024
GROUP  BY b.branch_region
ORDER  BY online_pct DESC;

PROMPT
PROMPT === S6. QUARTERLY SEASONALITY - the clean version for A1 ===
PROMPT Monthly order counts are noisy; quarters resolve the pattern.
PROMPT 2026 excluded because it is a part year.
SELECT d.cal_quarter,
       COUNT(DISTINCT s.order_no)     AS orders,
       ROUND(SUM(s.net_sales_amt), 2) AS revenue,
       ROUND(100 * COUNT(DISTINCT s.order_no)
             / SUM(COUNT(DISTINCT s.order_no)) OVER (), 1) AS pct_of_orders
FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
WHERE  d.cal_year < 2026
GROUP  BY d.cal_quarter
ORDER  BY d.cal_quarter;

PROMPT
PROMPT ####################################################################
PROMPT #  Read BLOCKER rows first. REPORT rows are not defects - they     #
PROMPT #  are things your write-up has to acknowledge before a marker     #
PROMPT #  notices them and assumes you did not.                           #
PROMPT ####################################################################
SET SQLBLANKLINES OFF
