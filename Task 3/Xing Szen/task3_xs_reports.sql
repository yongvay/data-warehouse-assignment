-- ============================================================================
--  Task 3 - Business Analytics Queries        STUDENT: XS
--  Domain A : Sales & Product
--  RUN AS THE DW USER
--
--      SQL> SPOOL C:\Users\PC\Desktop\DW\task3_output.txt
--      SQL> @"C:\Users\PC\Desktop\DW\Task 3\task3_xs_reports.sql"
--      SQL> SPOOL OFF
--
--  TO EXPORT FOR CHARTING IN EXCEL (Oracle 12.2 and later):
--      SQL> SET MARKUP CSV ON
--      SQL> SPOOL C:\Users\PC\Desktop\DW\r1.csv
--      ... run just the exhibit you want ...
--      SQL> SPOOL OFF
--      SQL> SET MARKUP CSV OFF
--
--  ......................................................................
--  COLUMN NAMING - every measured column carries its unit
--
--      _RM        Malaysian Ringgit
--      _PCT       percentage (0-100)
--      _DAYS      whole days
--      _UNITS     physical units of stock
--      _BASE100   an index where 100 = the average of the series
--      _SD        standard deviations from an expected value
--
--  Plain counts - orders, order_lines, branches, items, deliveries - carry
--  no suffix because a count has no unit.
--  ......................................................................
--  THREE STANDING RULES, APPLIED THROUGHOUT
--
--  1. 2026 IS A PART YEAR.  It covers January to August only.  Any query
--     that compares whole years excludes it, and any query that includes
--     it says so.  Charted raw against 2025 it reads as a 26% collapse,
--     which is false.
--
--  2. ONLINE SHARE RISES EVERY YEAR.  Branches that opened late therefore
--     trade only in the online-heavy era and look digitally advanced when
--     they are merely young.  Every cross-branch channel comparison is
--     restricted to 2024-2026, where all twelve branches were trading.
--
--  3. PROMOTIONAL COVERAGE FALLS ACROSS THE DECADE for an arithmetic
--     reason - campaign breadth held at ~25 SKUs while the range grew from
--     28 to 54 - so promotion figures are compared WITHIN a year, never
--     across years.
--  ......................................................................
-- ============================================================================
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 400
SET FEEDBACK OFF
SET TRIMSPOOL ON

COLUMN category_name  FORMAT A24
COLUMN supplier_name  FORMAT A34
COLUMN branch_region  FORMAT A16
COLUMN membership     FORMAT A14
COLUMN reason_name    FORMAT A14
COLUMN reason_group   FORMAT A18
COLUMN channel        FORMAT A10
COLUMN metric         FORMAT A44
COLUMN verdict        FORMAT A34
COLUMN component      FORMAT A24
COLUMN value_2016     FORMAT A12
COLUMN value_2025     FORMAT A12
COLUMN period         FORMAT A12


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 1 - RANGE EXPANSION AND SEASONAL DEMAND
PROMPT   Dimensions: date_dim (year, quarter) x item_dim (category)
PROMPT   Measures  : orders, order lines, gross, discount, net revenue
PROMPT ============================================================================

PROMPT
PROMPT --- EXHIBIT 1.1  Trading range and revenue, by year ===
PROMPT WHAT: the headline, and the three components growth can be split into.
PROMPT WHO   = active_customers.  WHERE = branches_trading.
PROMPT Revenue = customers x orders_per_customer x avg_basket, so this one
PROMPT table carries every driver Exhibit 1.7 decomposes.
PROMPT NOTE: 2026 is Jan-Aug only and is shown for completeness, not comparison.
SELECT d.cal_year,
       COUNT(DISTINCT b.branch_key)    AS branches_trading,
       COUNT(DISTINCT s.customer_key)  AS active_customers,
       COUNT(DISTINCT i.category_id)   AS categories,
       COUNT(DISTINCT i.item_key)      AS items_sold,
       COUNT(DISTINCT s.order_no)      AS orders,
       ROUND(COUNT(DISTINCT s.order_no)
             / COUNT(DISTINCT s.customer_key), 2) AS orders_per_customer,
       ROUND(SUM(s.net_sales_amt))     AS net_revenue_rm,
       ROUND(SUM(s.net_sales_amt) / COUNT(DISTINCT s.order_no), 2) AS avg_basket_rm
FROM   sales_fact s
JOIN   item_dim   i ON i.item_key   = s.item_key
JOIN   date_dim   d ON d.date_key   = s.order_date_key
JOIN   branch_dim b ON b.branch_key = s.branch_key
WHERE  b.branch_key <> -1
GROUP  BY d.cal_year
ORDER  BY d.cal_year;

PROMPT
PROMPT --- EXHIBIT 1.2  Year-on-year growth, and the 2020 shock ===
PROMPT WHY: isolates the pandemic dip and the speed of recovery.
PROMPT 2026 excluded - a part year cannot carry a YoY percentage.
SELECT cal_year,
       orders,
       net_revenue_rm,
       net_revenue_rm - LAG(net_revenue_rm) OVER (ORDER BY cal_year) AS revenue_change_rm,
       ROUND(100 * (net_revenue_rm - LAG(net_revenue_rm) OVER (ORDER BY cal_year))
             / NULLIF(LAG(net_revenue_rm) OVER (ORDER BY cal_year), 0), 1) AS yoy_pct
FROM ( SELECT d.cal_year,
              COUNT(DISTINCT s.order_no)  AS orders,
              ROUND(SUM(s.net_sales_amt)) AS net_revenue_rm
       FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
       WHERE  d.cal_year < 2026
       GROUP  BY d.cal_year )
ORDER  BY cal_year;

PROMPT
PROMPT --- EXHIBIT 1.3  Revenue by category by year  [CHART: stacked area] ===
PROMPT Long format on purpose - this is the shape Excel wants for a stacked chart.
SELECT d.cal_year, i.category_name,
       ROUND(SUM(s.net_sales_amt)) AS net_revenue_rm
FROM   sales_fact s
JOIN   item_dim   i ON i.item_key = s.item_key
JOIN   date_dim   d ON d.date_key = s.order_date_key
GROUP  BY d.cal_year, i.category_name
ORDER  BY d.cal_year, i.category_name;

PROMPT
PROMPT --- EXHIBIT 1.4  When each category entered the range ===
PROMPT WHAT CAUSED IT: revenue growth is partly volume, partly a wider range.
PROMPT This separates the two.
SELECT i.category_name,
       MIN(d.cal_year)                 AS first_year_sold,
       COUNT(DISTINCT i.item_key)      AS items_in_category,
       ROUND(SUM(s.net_sales_amt))     AS lifetime_revenue_rm,
       ROUND(SUM(s.net_sales_amt) / COUNT(DISTINCT i.item_key))
                                       AS revenue_per_item_rm,
       ROUND(100 * SUM(s.net_sales_amt)
             / SUM(SUM(s.net_sales_amt)) OVER (), 1) AS pct_of_total
FROM   sales_fact s
JOIN   item_dim   i ON i.item_key = s.item_key
JOIN   date_dim   d ON d.date_key = s.order_date_key
GROUP  BY i.category_name
ORDER  BY first_year_sold, lifetime_revenue_rm DESC;

PROMPT
PROMPT --- EXHIBIT 1.5  Quarterly seasonality  [CHART: column] ===
PROMPT Indexed so 100 = the average quarter. Q1 is Chinese New Year,
PROMPT Q4 the year-end run, Q3 the mid-year trough.
PROMPT 2026 excluded: it contributes to Q1-Q3 only and would distort the index.
SELECT d.cal_quarter,
       COUNT(DISTINCT s.order_no)      AS orders,
       ROUND(SUM(s.net_sales_amt))     AS net_revenue_rm,
       ROUND(100 * COUNT(DISTINCT s.order_no)
             / AVG(COUNT(DISTINCT s.order_no)) OVER ()) AS order_index_base100
FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
WHERE  d.cal_year < 2026
GROUP  BY d.cal_quarter
ORDER  BY d.cal_quarter;

PROMPT
PROMPT --- EXHIBIT 1.6  Does every category share the same season? ===
PROMPT HOW: a category whose Q1 share is well above 25% is CNY-driven.
-- PIVOT insists on a bare aggregate, so ROUND(SUM(x)) inside it raises
-- ORA-56902. Conditional aggregation does the same job, works on every
-- Oracle version, and lets the Q1 share be computed in the same pass.
SELECT i.category_name,
       ROUND(SUM(CASE WHEN d.cal_quarter='Q1' THEN s.net_sales_amt ELSE 0 END)) AS q1_rm,
       ROUND(SUM(CASE WHEN d.cal_quarter='Q2' THEN s.net_sales_amt ELSE 0 END)) AS q2_rm,
       ROUND(SUM(CASE WHEN d.cal_quarter='Q3' THEN s.net_sales_amt ELSE 0 END)) AS q3_rm,
       ROUND(SUM(CASE WHEN d.cal_quarter='Q4' THEN s.net_sales_amt ELSE 0 END)) AS q4_rm,
       ROUND(100 * SUM(CASE WHEN d.cal_quarter='Q1' THEN s.net_sales_amt ELSE 0 END)
             / NULLIF(SUM(s.net_sales_amt), 0), 1) AS q1_share_pct
FROM   sales_fact s
JOIN   item_dim   i ON i.item_key = s.item_key
JOIN   date_dim   d ON d.date_key = s.order_date_key
WHERE  d.cal_year < 2026
GROUP  BY i.category_name
ORDER  BY q1_share_pct DESC;


PROMPT
PROMPT --- EXHIBIT 1.7  What actually drove the growth? ===
PROMPT Revenue is the product of three things: how many customers bought, how
PROMPT often each bought, and how much each order was worth. Comparing 2016
PROMPT with 2025 shows which of the three did the work.
PROMPT The three multiples multiply back to the revenue multiple.
WITH yr AS (
    SELECT d.cal_year,
           COUNT(DISTINCT s.customer_key)                   AS customers,
           COUNT(DISTINCT s.order_no)                       AS orders,
           SUM(s.net_sales_amt)                             AS revenue
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
    WHERE  d.cal_year IN (2016, 2025)
    GROUP  BY d.cal_year
), base AS (
    SELECT MAX(CASE WHEN cal_year = 2016 THEN customers END) AS c16,
           MAX(CASE WHEN cal_year = 2025 THEN customers END) AS c25,
           MAX(CASE WHEN cal_year = 2016 THEN orders    END) AS o16,
           MAX(CASE WHEN cal_year = 2025 THEN orders    END) AS o25,
           MAX(CASE WHEN cal_year = 2016 THEN revenue   END) AS r16,
           MAX(CASE WHEN cal_year = 2025 THEN revenue   END) AS r25
    FROM   yr
)
SELECT 'Active customers'        AS component,
       TO_CHAR(c16)              AS value_2016,
       TO_CHAR(c25)              AS value_2025,
       ROUND(c25 / c16, 2)       AS multiple
FROM   base
UNION ALL
SELECT 'Orders per customer',
       TO_CHAR(ROUND(o16 / c16, 2)),
       TO_CHAR(ROUND(o25 / c25, 2)),
       ROUND((o25 / c25) / (o16 / c16), 2)
FROM   base
UNION ALL
SELECT 'Average basket (RM)',
       TO_CHAR(ROUND(r16 / o16, 2)),
       TO_CHAR(ROUND(r25 / o25, 2)),
       ROUND((r25 / o25) / (r16 / o16), 2)
FROM   base
UNION ALL
SELECT 'NET REVENUE (RM)',
       TO_CHAR(ROUND(r16)),
       TO_CHAR(ROUND(r25)),
       ROUND(r25 / r16, 2)
FROM   base;


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 2 - SUPPLIER CONTRIBUTION AND RETURN EXPOSURE
PROMPT   Dimensions: item_dim (supplier, category) x return_reason_dim x date_dim
PROMPT   Measures  : revenue, concentration, units returned, return rate
PROMPT
PROMPT   FRAMING: this is a CONCENTRATION and EXPOSURE report, not a quality
PROMPT   scorecard. Exhibit 2.3 shows why - return rates cluster too tightly
PROMPT   for any supplier to be called an outlier.
PROMPT ============================================================================

PROMPT
PROMPT --- EXHIBIT 2.1  Supplier revenue Pareto  [CHART: Pareto] ===
PROMPT WHAT: how much of the business rests on how few suppliers.
SELECT supplier_name,
       items_supplied,
       net_revenue_rm,
       pct_of_total,
       SUM(pct_of_total) OVER (ORDER BY net_revenue_rm DESC
                               ROWS UNBOUNDED PRECEDING) AS cumulative_pct
FROM ( SELECT i.supplier_name,
              COUNT(DISTINCT i.item_key)  AS items_supplied,
              ROUND(SUM(s.net_sales_amt)) AS net_revenue_rm,
              ROUND(100 * SUM(s.net_sales_amt)
                    / SUM(SUM(s.net_sales_amt)) OVER (), 1) AS pct_of_total
       FROM   sales_fact s JOIN item_dim i ON i.item_key = s.item_key
       GROUP  BY i.supplier_name )
ORDER  BY net_revenue_rm DESC;

PROMPT
PROMPT --- EXHIBIT 2.2  Supplier x category contribution ===
PROMPT WHERE the dependency sits: a supplier that is the sole source of a
PROMPT category is a single point of failure regardless of its revenue rank.
SELECT i.supplier_name, i.category_name,
       COUNT(DISTINCT i.item_key)  AS items,
       ROUND(SUM(s.net_sales_amt)) AS net_revenue_rm
FROM   sales_fact s JOIN item_dim i ON i.item_key = s.item_key
GROUP  BY i.supplier_name, i.category_name
ORDER  BY net_revenue_rm DESC;

PROMPT
PROMPT --- EXHIBIT 2.3  Return rate by supplier, WITH the noise band ===
PROMPT THE KEY EXHIBIT. expected_units is what each supplier would see if
PROMPT returns were distributed purely in proportion to units sold.
PROMPT z_score_sd measures how far the actual result sits from expectation
PROMPT in standard deviations. Roughly: |z| under 2 is indistinguishable from
PROMPT chance. If every supplier lands inside that band, there is no quality
PROMPT outlier and the honest finding is that no supplier warrants action.
WITH sold AS (
    SELECT i.supplier_name,
           SUM(s.quantity) AS units_sold,
           COUNT(*)        AS lines_sold
    FROM   sales_fact s JOIN item_dim i ON i.item_key = s.item_key
    GROUP  BY i.supplier_name
), returned AS (
    SELECT i.supplier_name,
           SUM(r.quantity_returned) AS units_returned
    FROM   return_fact r JOIN item_dim i ON i.item_key = r.item_key
    GROUP  BY i.supplier_name
), tot_sold AS (
    -- Two separate CTEs on purpose. Putting a scalar subquery next to an
    -- aggregate in one SELECT with no GROUP BY raises ORA-00937.
    SELECT SUM(units_sold) AS all_sold FROM sold
), tot_ret AS (
    SELECT NVL(SUM(units_returned), 0) AS all_returned FROM returned
)
SELECT s.supplier_name,
       s.units_sold,
       NVL(r.units_returned, 0) AS units_returned,
       ROUND(100 * NVL(r.units_returned, 0) / NULLIF(s.units_sold, 0), 2)
           AS return_pct,
       ROUND(tr.all_returned * s.units_sold / ts.all_sold, 1) AS expected_units,
       ROUND( (NVL(r.units_returned,0) - tr.all_returned * s.units_sold / ts.all_sold)
              / NULLIF(SQRT(tr.all_returned * s.units_sold / ts.all_sold), 0), 2)
           AS z_score_sd
FROM   sold s
LEFT   JOIN returned r ON r.supplier_name = s.supplier_name
CROSS  JOIN tot_sold ts
CROSS  JOIN tot_ret  tr
ORDER  BY return_pct DESC;

PROMPT
PROMPT --- EXHIBIT 2.4  Why customers return  [CHART: 100% stacked bar] ===
PROMPT Fulfilment failures are an operations problem; Product Quality is a
PROMPT supplier problem. The split tells management which lever to pull.
SELECT rr.reason_category AS reason_group,
       rr.reason_name,
       COUNT(*)                        AS return_lines,
       SUM(r.quantity_returned)        AS units_returned,
       ROUND(SUM(r.refund_amount))     AS refund_value_rm,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_returns
FROM   return_fact r
JOIN   return_reason_dim rr ON rr.reason_key = r.reason_key
GROUP  BY rr.reason_category, rr.reason_name
ORDER  BY return_lines DESC;

PROMPT
PROMPT --- EXHIBIT 2.5  Is the return rate getting worse over time? ===
PROMPT 2026 included but flagged: a part year, so read the RATE not the volume.
SELECT d.cal_year,
       SUM(s.quantity) AS units_sold,
       NVL(( SELECT SUM(r.quantity_returned)
             FROM   return_fact r JOIN date_dim rd ON rd.date_key = r.order_date_key
             WHERE  rd.cal_year = d.cal_year ), 0) AS units_returned,
       ROUND(100 * NVL(( SELECT SUM(r.quantity_returned)
                         FROM   return_fact r
                         JOIN   date_dim rd ON rd.date_key = r.order_date_key
                         WHERE  rd.cal_year = d.cal_year ), 0)
             / NULLIF(SUM(s.quantity), 0), 2) AS return_pct
FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
GROUP  BY d.cal_year
ORDER  BY d.cal_year;

PROMPT
PROMPT --- EXHIBIT 2.6  Speed of return - an operational service metric ===
SELECT rr.reason_category AS reason_group,
       COUNT(*)                          AS return_lines,
       ROUND(AVG(r.days_to_return), 1)   AS avg_days_to_return,
       MIN(r.days_to_return)             AS fastest_days,
       MAX(r.days_to_return)             AS slowest_days
FROM   return_fact r
JOIN   return_reason_dim rr ON rr.reason_key = r.reason_key
GROUP  BY rr.reason_category
ORDER  BY avg_days_to_return;


PROMPT
PROMPT --- EXHIBIT 2.7  Has supplier concentration changed over time? ===
PROMPT WHEN: splits the decade in two and re-measures. Revenue concentration
PROMPT and STRUCTURAL exposure can move in opposite directions - a wider range
PROMPT spreads revenue across more suppliers while creating more categories
PROMPT that are each still single-sourced.
PROMPT 2026 excluded as a part year.
WITH per_supplier AS (
    SELECT CASE WHEN d.cal_year <= 2020 THEN '2016-2020'
                ELSE '2021-2025' END          AS period,
           i.supplier_name,
           SUM(s.net_sales_amt)               AS revenue
    FROM   sales_fact s
    JOIN   item_dim i ON i.item_key = s.item_key
    JOIN   date_dim d ON d.date_key = s.order_date_key
    WHERE  d.cal_year < 2026
    GROUP  BY CASE WHEN d.cal_year <= 2020 THEN '2016-2020'
                   ELSE '2021-2025' END, i.supplier_name
), ranked AS (
    SELECT period, supplier_name,
           ROUND(revenue) AS revenue_rm,
           ROUND(100 * revenue
                 / SUM(revenue) OVER (PARTITION BY period), 1) AS share_pct,
           RANK() OVER (PARTITION BY period ORDER BY revenue DESC) AS rank_in_period
    FROM   per_supplier
)
SELECT period, rank_in_period, supplier_name, revenue_rm, share_pct
FROM   ranked
WHERE  rank_in_period <= 4
ORDER  BY period, rank_in_period;

PROMPT
PROMPT --- EXHIBIT 2.7b  Concentration summary by period ===
PROMPT suppliers_trading is the count of single points of failure, because
PROMPT every supplier is the sole source of its category.
WITH per_supplier AS (
    SELECT CASE WHEN d.cal_year <= 2020 THEN '2016-2020'
                ELSE '2021-2025' END          AS period,
           i.supplier_name,
           SUM(s.net_sales_amt)               AS revenue
    FROM   sales_fact s
    JOIN   item_dim i ON i.item_key = s.item_key
    JOIN   date_dim d ON d.date_key = s.order_date_key
    WHERE  d.cal_year < 2026
    GROUP  BY CASE WHEN d.cal_year <= 2020 THEN '2016-2020'
                   ELSE '2021-2025' END, i.supplier_name
), ranked AS (
    SELECT period, supplier_name, revenue,
           100 * revenue / SUM(revenue) OVER (PARTITION BY period) AS share_pct,
           RANK() OVER (PARTITION BY period ORDER BY revenue DESC) AS rnk
    FROM   per_supplier
)
SELECT period,
       COUNT(*)                                              AS suppliers_trading,
       ROUND(MAX(share_pct), 1)                              AS largest_share_pct,
       ROUND(SUM(CASE WHEN rnk <= 4 THEN share_pct END), 1)  AS top4_share_pct
FROM   ranked
GROUP  BY period
ORDER  BY period;


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 3 - CHANNEL MIGRATION: ONLINE VERSUS WALK-IN
PROMPT   Dimensions: date_dim x branch_dim (region) x customer_dim (membership)
PROMPT   Measures  : order share, basket value, delivery lead time
PROMPT
PROMPT   membership comes from customer_dim, which sales_fact joins on a
PROMPT   point-in-time basis - so a customer who changed tier is counted
PROMPT   correctly in each era rather than being back-dated. That is the
PROMPT   Type 2 dimension doing real work.
PROMPT ============================================================================

PROMPT
PROMPT --- EXHIBIT 3.1  The migration  [CHART: line] ===
PROMPT WHAT: online share of orders, year by year. 2026 is a part year but the
PROMPT SHARE is unaffected by that - only the volume is.
SELECT d.cal_year,
       COUNT(DISTINCT s.order_no) AS orders,
       COUNT(DISTINCT CASE WHEN s.order_type = 'Online'
                           THEN s.order_no END) AS online_orders,
       ROUND(100 * COUNT(DISTINCT CASE WHEN s.order_type = 'Online'
                                       THEN s.order_no END)
             / COUNT(DISTINCT s.order_no), 1) AS online_pct
FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
GROUP  BY d.cal_year
ORDER  BY d.cal_year;

PROMPT
PROMPT --- EXHIBIT 3.2  Channel by region, 2024-2026 ONLY  [CHART: bar] ===
PROMPT WHY RESTRICTED: online share rises every year, so a branch that opened
PROMPT in 2021 trades only in the online-heavy era and appears digitally
PROMPT advanced when it is merely young. From 2024 every branch was trading,
PROMPT so this comparison is like for like and any gap is real.
SELECT b.branch_region,
       COUNT(DISTINCT b.branch_key)   AS branches,
       COUNT(DISTINCT s.order_no)     AS orders,
       ROUND(100 * COUNT(DISTINCT CASE WHEN s.order_type = 'Online'
                                       THEN s.order_no END)
             / COUNT(DISTINCT s.order_no), 1) AS online_pct,
       ROUND(SUM(s.net_sales_amt) / COUNT(DISTINCT s.order_no), 2) AS avg_basket_rm
FROM   sales_fact s
JOIN   branch_dim b ON b.branch_key = s.branch_key
JOIN   date_dim   d ON d.date_key   = s.order_date_key
WHERE  b.branch_key <> -1 AND d.cal_year >= 2024
GROUP  BY b.branch_region
ORDER  BY online_pct DESC;

PROMPT
PROMPT --- EXHIBIT 3.3  Who is migrating - by membership tier ===
PROMPT Only members can take delivery: Delivery.AddressID references
PROMPT MemberAddress, which references Member. So membership is structurally
PROMPT tied to the online channel, and this quantifies how tightly.
SELECT c.membership_type AS membership,
       COUNT(DISTINCT s.order_no)   AS orders,
       ROUND(100 * COUNT(DISTINCT CASE WHEN s.order_type = 'Online'
                                       THEN s.order_no END)
             / COUNT(DISTINCT s.order_no), 1) AS online_pct,
       ROUND(SUM(s.net_sales_amt) / COUNT(DISTINCT s.order_no), 2) AS avg_basket_rm,
       ROUND(SUM(s.net_sales_amt))  AS net_revenue_rm
FROM   sales_fact   s
JOIN   customer_dim c ON c.customer_key = s.customer_key
WHERE  c.customer_key <> -1
GROUP  BY c.membership_type
ORDER  BY net_revenue_rm DESC;

PROMPT
PROMPT --- EXHIBIT 3.4  Is an online basket worth more than a walk-in one? ===
PROMPT SO WHAT: if online baskets are larger, the migration is accretive and
PROMPT should be accelerated. If not, it is merely cannibalising the stores.
SELECT d.cal_year,
       s.order_type AS channel,
       COUNT(DISTINCT s.order_no)  AS orders,
       ROUND(AVG(s.quantity), 2)   AS avg_units_per_line,
       ROUND(SUM(s.net_sales_amt) / COUNT(DISTINCT s.order_no), 2) AS avg_basket_rm
FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
WHERE  d.cal_year >= 2022
GROUP  BY d.cal_year, s.order_type
ORDER  BY d.cal_year, channel;

PROMPT
PROMPT --- EXHIBIT 3.5  Can fulfilment keep up?  [CHART: line, dual axis] ===
PROMPT HOW the migration is being served. Rising volume with a rising lead
PROMPT time is a capacity warning; rising volume with a flat lead time says
PROMPT the network is coping.
SELECT d.cal_year,
       COUNT(*) AS deliveries,
       ROUND(AVG(f.delivery_lead_days), 2) AS avg_lead_days,
       SUM(CASE WHEN f.delivery_status = 'Delivered' THEN 1 ELSE 0 END) AS delivered,
       SUM(CASE WHEN f.delivery_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
       ROUND(100 * SUM(CASE WHEN f.delivery_status = 'Cancelled' THEN 1 ELSE 0 END)
             / COUNT(*), 2) AS cancel_pct
FROM   delivery_fact f JOIN date_dim d ON d.date_key = f.order_date_key
GROUP  BY d.cal_year
ORDER  BY d.cal_year;

PROMPT
PROMPT --- EXHIBIT 3.6  Which courier serves which region ===
SELECT dc.company_name, b.branch_region,
       COUNT(*) AS deliveries,
       ROUND(AVG(f.delivery_lead_days), 2) AS avg_lead_days,
       ROUND(AVG(f.delivery_charge), 2)    AS avg_charge_rm
FROM   delivery_fact f
JOIN   delivery_company_dim dc ON dc.delivery_company_key = f.delivery_company_key
JOIN   branch_dim b            ON b.branch_key            = f.branch_key
WHERE  f.delivery_company_key <> -1 AND b.branch_key <> -1
GROUP  BY dc.company_name, b.branch_region
ORDER  BY dc.company_name, deliveries DESC;

PROMPT
PROMPT ============================================================================
PROMPT   END OF EXHIBITS
PROMPT ============================================================================
SET FEEDBACK ON
SET SQLBLANKLINES OFF