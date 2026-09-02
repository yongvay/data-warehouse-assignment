-- ===========================================================================
--  BMIT3003 DATA WAREHOUSE TECHNOLOGY - ASSIGNMENT
--  Task 3: Business Analytics Queries & Decision Support
--  Section 4.3  Chan Xing Szen     Domain A: Sales and Product
-- ===========================================================================
--
--  HOW TO RUN
--     SQL> connect dw
--     SQL> SPOOL "Task 3\Xing Szen\task3_output.txt"
--     SQL> @"Task 3\Xing Szen\task3_xs_reports.sql"
--     SQL> SPOOL OFF
--
--  YOU ARE PROMPTED SIX TIMES
--     1. Start Year                        applies to all three reports
--     2. End Year                          applies to all three reports
--     3. Report 1 drill-down year          e.g. 2025
--     4. Report 2 drill-down supplier      e.g. KleenHome Supplies
--     5. Report 3 like-for-like start year e.g. 2024
--     6. Report 3 drill-down year          e.g. 2025
--
--     The warehouse holds 2016-2026, but 2026 is January to August only.
--     Enter 2016 and 2025 for a report built entirely from complete years.
--
--     Prompt 5 exists because online share rises every year, so a branch that
--     opened late trades only in the online-heavy period and looks digitally
--     advanced when it is merely young. Entering the year by which every
--     branch was trading makes the regional comparison like-for-like.
--
--  THREE REPORTS, TEN OUTPUTS
--     Report 1  Range Expansion and Seasonal Demand
--               (date_dim x item_dim x branch_dim x customer_dim)
--        1  Annual trading summary with year-on-year movement
--        2  Growth decomposition: which driver did the work
--        3  Drill-down: category demand by quarter for one year
--     Report 2  Supplier Concentration and Return Exposure
--               (item_dim x return_reason_dim x date_dim)
--        1  Supplier Pareto with cumulative share
--        2  Return-rate outlier test against expected returns
--        3  Concentration compared across two halves of the period
--        4  Drill-down: return reasons for one supplier
--     Report 3  Channel Migration - Online versus Walk-in
--               (date_dim x branch_dim x customer_dim)
--        1  Channel mix by year with basket comparison
--        2  Channel mix by region, like-for-like window
--        3  Drill-down: membership tier x channel for one year
--
--  NOTE ON THE VIEWS
--     The seven views are period-agnostic - they carry no year filter. The
--     year range is applied in the report queries instead, so a view stays
--     valid whatever range is entered and a drill-down cannot silently return
--     nothing because its year sits outside the range a view was built with.
--
--  UNIT CONVENTION IN COLUMN ALIASES
--     _rm  Ringgit    _pct  percentage    _sd  standard deviations
--     plain counts carry no suffix
-- ===========================================================================

SET VERIFY        OFF
SET FEEDBACK      OFF
SET PAGESIZE      50
SET LINESIZE      80
SET TRIMSPOOL     ON
SET SQLBLANKLINES ON
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS


-- ===========================================================================
--  V I E W S
-- ===========================================================================

PROMPT
PROMPT Creating analytical views ...

-- Report 1 -----------------------------------------------------------------
CREATE OR REPLACE VIEW vw_xs_trading_year AS
SELECT d.cal_year,
       COUNT(DISTINCT b.branch_key)    AS branches_trading,
       COUNT(DISTINCT s.customer_key)  AS active_customers,
       COUNT(DISTINCT i.category_id)   AS categories,
       COUNT(DISTINCT i.item_key)      AS items_sold,
       COUNT(DISTINCT s.order_no)      AS orders,
       SUM(s.net_sales_amt)            AS net_sales_amt
FROM   sales_fact s
JOIN   date_dim   d ON d.date_key   = s.order_date_key
JOIN   item_dim   i ON i.item_key   = s.item_key
JOIN   branch_dim b ON b.branch_key = s.branch_key
WHERE  b.branch_key <> -1
GROUP  BY d.cal_year;

CREATE OR REPLACE VIEW vw_xs_category_quarter AS
SELECT d.cal_year,
       d.cal_quarter,
       i.category_name,
       COUNT(DISTINCT s.order_no)  AS orders,
       SUM(s.quantity)             AS units_sold,
       SUM(s.net_sales_amt)        AS net_sales_amt
FROM   sales_fact s
JOIN   item_dim   i ON i.item_key = s.item_key
JOIN   date_dim   d ON d.date_key = s.order_date_key
WHERE  i.item_key <> -1
GROUP  BY d.cal_year, d.cal_quarter, i.category_name;

-- Report 2 -----------------------------------------------------------------
CREATE OR REPLACE VIEW vw_xs_supplier_year AS
SELECT d.cal_year,
       REPLACE(i.supplier_name, ' Sdn Bhd', '') AS supplier_name,
       i.category_name,
       COUNT(DISTINCT i.item_key)  AS items_supplied,
       SUM(s.quantity)             AS units_sold,
       SUM(s.net_sales_amt)        AS net_sales_amt
FROM   sales_fact s
JOIN   item_dim   i ON i.item_key = s.item_key
JOIN   date_dim   d ON d.date_key = s.order_date_key
WHERE  i.item_key <> -1
GROUP  BY d.cal_year, REPLACE(i.supplier_name, ' Sdn Bhd', ''), i.category_name;

CREATE OR REPLACE VIEW vw_xs_supplier_returns_year AS
SELECT d.cal_year,
       REPLACE(i.supplier_name, ' Sdn Bhd', '') AS supplier_name,
       rr.reason_category,
       rr.reason_name,
       COUNT(*)                    AS return_lines,
       SUM(r.quantity_returned)    AS units_returned,
       SUM(r.refund_amount)        AS refund_amount,
       AVG(r.days_to_return)       AS avg_days_to_return
FROM   return_fact r
JOIN   item_dim          i  ON i.item_key    = r.item_key
JOIN   date_dim          d  ON d.date_key    = r.return_date_key
JOIN   return_reason_dim rr ON rr.reason_key = r.reason_key
WHERE  i.item_key <> -1
GROUP  BY d.cal_year, REPLACE(i.supplier_name, ' Sdn Bhd', ''),
          rr.reason_category, rr.reason_name;

-- Report 3 -----------------------------------------------------------------
CREATE OR REPLACE VIEW vw_xs_channel_year AS
SELECT d.cal_year,
       s.order_type                   AS channel,
       COUNT(DISTINCT s.customer_key) AS customers,
       COUNT(DISTINCT s.order_no)     AS orders,
       SUM(s.net_sales_amt)           AS net_sales_amt
FROM   sales_fact s
JOIN   date_dim   d ON d.date_key   = s.order_date_key
JOIN   branch_dim b ON b.branch_key = s.branch_key
WHERE  b.branch_key <> -1
GROUP  BY d.cal_year, s.order_type;

CREATE OR REPLACE VIEW vw_xs_channel_region AS
SELECT d.cal_year,
       b.branch_region,
       b.branch_key,
       s.order_type                AS channel,
       COUNT(DISTINCT s.order_no)  AS orders,
       SUM(s.net_sales_amt)        AS net_sales_amt
FROM   sales_fact s
JOIN   date_dim   d ON d.date_key   = s.order_date_key
JOIN   branch_dim b ON b.branch_key = s.branch_key
WHERE  b.branch_key <> -1
GROUP  BY d.cal_year, b.branch_region, b.branch_key, s.order_type;

CREATE OR REPLACE VIEW vw_xs_channel_member AS
SELECT d.cal_year,
       c.membership_type,
       s.order_type                   AS channel,
       COUNT(DISTINCT s.customer_key) AS customers,
       COUNT(DISTINCT s.order_no)     AS orders,
       SUM(s.net_sales_amt)           AS net_sales_amt
FROM   sales_fact   s
JOIN   date_dim     d ON d.date_key     = s.order_date_key
JOIN   customer_dim c ON c.customer_key = s.customer_key
WHERE  c.customer_key <> -1
GROUP  BY d.cal_year, c.membership_type, s.order_type;

PROMPT Views created.
PROMPT


-- ===========================================================================
--  R E P O R T   1
--  Range Expansion and Seasonal Demand
--  Dimensions: date_dim (year, quarter) x item_dim (category)
--              x branch_dim x customer_dim
-- ===========================================================================

PROMPT
PROMPT ============================================================
PROMPT Report 1 - Range Expansion and Seasonal Demand
PROMPT ============================================================
PROMPT Please provide the analysis period. It applies to all three reports.
ACCEPT start_year_prompt CHAR PROMPT 'Enter Start Year (e.g., 2016): '
ACCEPT end_year_prompt   CHAR PROMPT 'Enter End Year   (e.g., 2025): '
PROMPT

-- --- Section 1: Annual trading summary ------------------------------------
--     WHAT the business did, WHO bought (active_customers),
--     WHERE it traded (branches_trading), WHEN it moved (yoy_pct).

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Annual Trading Summary' SKIP 1 -
       CENTER 'For Years &start_year_prompt to &end_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN cal_year         FORMAT 9999         HEADING 'Year'
COLUMN branches_trading FORMAT 999          HEADING 'Brch'
COLUMN active_customers FORMAT 9,999        HEADING 'Cust'
COLUMN items_sold       FORMAT 999          HEADING 'Items'
COLUMN orders           FORMAT 99,999       HEADING 'Orders'
COLUMN orders_per_cust  FORMAT 990.99       HEADING 'Ord per|Cust'
COLUMN net_revenue_rm   FORMAT 9,999,990.99 HEADING 'Net Revenue|(RM)'
COLUMN avg_basket_rm    FORMAT 9,990.99     HEADING 'Avg Basket|(RM)'
COLUMN yoy_pct          FORMAT A8           HEADING 'YoY'

BREAK ON REPORT

COMPUTE SUM LABEL 'TOTAL:' OF orders net_revenue_rm ON REPORT

WITH yr AS (
    SELECT cal_year, branches_trading, active_customers, items_sold,
           orders, net_sales_amt
    FROM   vw_xs_trading_year
    WHERE  cal_year BETWEEN TO_NUMBER('&start_year_prompt')
                        AND TO_NUMBER('&end_year_prompt')
)
SELECT y.cal_year,
       y.branches_trading,
       y.active_customers,
       y.items_sold,
       y.orders,
       ROUND(y.orders / NULLIF(y.active_customers, 0), 2) AS orders_per_cust,
       ROUND(y.net_sales_amt, 2)                          AS net_revenue_rm,
       ROUND(y.net_sales_amt / NULLIF(y.orders, 0), 2)    AS avg_basket_rm,
       CASE WHEN LAG(y.net_sales_amt) OVER (ORDER BY y.cal_year) IS NULL
            THEN '     -'
            ELSE TO_CHAR(ROUND((y.net_sales_amt
                 - LAG(y.net_sales_amt) OVER (ORDER BY y.cal_year)) * 100
                 / NULLIF(LAG(y.net_sales_amt) OVER (ORDER BY y.cal_year), 0), 1),
                 'S990.9') || '%'
       END AS yoy_pct
FROM   yr y
ORDER  BY y.cal_year;

CLEAR COMPUTES
CLEAR BREAKS
CLEAR COLUMNS

-- --- Section 2: Growth decomposition --------------------------------------
--     WHY revenue moved. Revenue is exactly customers x orders-per-customer
--     x average basket, so the three multiples reconcile to the revenue
--     multiple with nothing left over. Anything below 1.00 worked against
--     growth rather than for it.

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Growth Decomposition' SKIP 1 -
       CENTER '&start_year_prompt compared with &end_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN component   FORMAT A24  HEADING 'Component'
COLUMN value_start FORMAT A14  HEADING 'Start Year'
COLUMN value_end   FORMAT A14  HEADING 'End Year'
COLUMN multiple    FORMAT 990.99 HEADING 'Multiple'

WITH bnd AS (
    SELECT MAX(CASE WHEN cal_year = TO_NUMBER('&start_year_prompt')
                    THEN active_customers END) AS c0,
           MAX(CASE WHEN cal_year = TO_NUMBER('&end_year_prompt')
                    THEN active_customers END) AS c1,
           MAX(CASE WHEN cal_year = TO_NUMBER('&start_year_prompt')
                    THEN orders END)           AS o0,
           MAX(CASE WHEN cal_year = TO_NUMBER('&end_year_prompt')
                    THEN orders END)           AS o1,
           MAX(CASE WHEN cal_year = TO_NUMBER('&start_year_prompt')
                    THEN net_sales_amt END)    AS r0,
           MAX(CASE WHEN cal_year = TO_NUMBER('&end_year_prompt')
                    THEN net_sales_amt END)    AS r1
    FROM   vw_xs_trading_year
    WHERE  cal_year IN (TO_NUMBER('&start_year_prompt'),
                        TO_NUMBER('&end_year_prompt'))
)
SELECT 'Active customers'    AS component,
       TO_CHAR(c0)           AS value_start,
       TO_CHAR(c1)           AS value_end,
       ROUND(c1 / NULLIF(c0, 0), 2) AS multiple
FROM   bnd
UNION ALL
SELECT 'Orders per customer',
       TO_CHAR(ROUND(o0 / NULLIF(c0, 0), 2)),
       TO_CHAR(ROUND(o1 / NULLIF(c1, 0), 2)),
       ROUND((o1 / NULLIF(c1, 0)) / NULLIF(o0 / NULLIF(c0, 0), 0), 2)
FROM   bnd
UNION ALL
SELECT 'Average basket (RM)',
       TO_CHAR(ROUND(r0 / NULLIF(o0, 0), 2)),
       TO_CHAR(ROUND(r1 / NULLIF(o1, 0), 2)),
       ROUND((r1 / NULLIF(o1, 0)) / NULLIF(r0 / NULLIF(o0, 0), 0), 2)
FROM   bnd
UNION ALL
SELECT 'NET REVENUE (RM)',
       TO_CHAR(ROUND(r0)),
       TO_CHAR(ROUND(r1)),
       ROUND(r1 / NULLIF(r0, 0), 2)
FROM   bnd;

CLEAR COLUMNS

-- --- Section 3: Drill-down, category demand by quarter --------------------
--     WHEN within the year demand falls, and whether any category has a
--     different season from the store as a whole.

PROMPT
ACCEPT drilldown_year_prompt CHAR PROMPT 'Enter Year to Drill Down (e.g., 2025): '

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Category Demand by Quarter' SKIP 1 -
       CENTER 'For Year &drilldown_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN category_name FORMAT A20     HEADING 'Category'
COLUMN q1_rm         FORMAT 999,999 HEADING 'Q1 (RM)'
COLUMN q2_rm         FORMAT 999,999 HEADING 'Q2 (RM)'
COLUMN q3_rm         FORMAT 999,999 HEADING 'Q3 (RM)'
COLUMN q4_rm         FORMAT 999,999 HEADING 'Q4 (RM)'
COLUMN q1_share_pct  FORMAT A8      HEADING 'Q1|Share'

BREAK ON REPORT

COMPUTE SUM LABEL 'TOTAL:' OF q1_rm q2_rm q3_rm q4_rm ON REPORT

SELECT v.category_name,
       ROUND(SUM(CASE WHEN v.cal_quarter = 'Q1'
                      THEN v.net_sales_amt ELSE 0 END)) AS q1_rm,
       ROUND(SUM(CASE WHEN v.cal_quarter = 'Q2'
                      THEN v.net_sales_amt ELSE 0 END)) AS q2_rm,
       ROUND(SUM(CASE WHEN v.cal_quarter = 'Q3'
                      THEN v.net_sales_amt ELSE 0 END)) AS q3_rm,
       ROUND(SUM(CASE WHEN v.cal_quarter = 'Q4'
                      THEN v.net_sales_amt ELSE 0 END)) AS q4_rm,
       TO_CHAR(ROUND(100 * SUM(CASE WHEN v.cal_quarter = 'Q1'
                                    THEN v.net_sales_amt ELSE 0 END)
              / NULLIF(SUM(v.net_sales_amt), 0), 1), '990.9') || '%'
              AS q1_share_pct
FROM   vw_xs_category_quarter v
WHERE  v.cal_year = TO_NUMBER('&drilldown_year_prompt')
GROUP  BY v.category_name
ORDER  BY SUM(v.net_sales_amt) DESC;

CLEAR COMPUTES
CLEAR BREAKS
CLEAR COLUMNS
TTITLE OFF

PROMPT
PROMPT Report 1 complete.
PROMPT


-- ===========================================================================
--  R E P O R T   2
--  Supplier Concentration and Return Exposure
--  Dimensions: item_dim (supplier, category) x return_reason_dim x date_dim
-- ===========================================================================

PROMPT
PROMPT ============================================================
PROMPT Report 2 - Supplier Concentration and Return Exposure
PROMPT ============================================================
PROMPT

-- Midpoint of the entered range, used by Section 3 to split the period in two
COLUMN mid_year NEW_VALUE mid_year_val NOPRINT
SELECT FLOOR((TO_NUMBER('&start_year_prompt')
            + TO_NUMBER('&end_year_prompt')) / 2) AS mid_year
FROM   dual;
COLUMN mid_year CLEAR

-- --- Section 1: Supplier Pareto -------------------------------------------
--     WHAT the concentration is, WHO each supplier is, and WHERE the
--     dependency sits - the category each one solely supplies.

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Supplier Revenue Pareto and Sole-Source Exposure' SKIP 1 -
       CENTER 'For Years &start_year_prompt to &end_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN supplier_name   FORMAT A24          HEADING 'Supplier'
COLUMN category_name   FORMAT A16          HEADING 'Category Supplied'
COLUMN items_supplied  FORMAT 999          HEADING 'Itm'
COLUMN net_revenue_rm  FORMAT 9,999,990.99 HEADING 'Net Revenue|(RM)'
COLUMN pct_of_total    FORMAT A8           HEADING '% Total'
COLUMN cumulative_pct  FORMAT A8           HEADING 'Cum %'

BREAK ON REPORT

COMPUTE SUM LABEL 'TOTAL:' OF net_revenue_rm ON REPORT

WITH sold AS (
    SELECT supplier_name,
           MIN(category_name)       AS category_name,
           SUM(items_supplied)      AS items_supplied,
           SUM(net_sales_amt)       AS net_sales_amt
    FROM   vw_xs_supplier_year
    WHERE  cal_year BETWEEN TO_NUMBER('&start_year_prompt')
                        AND TO_NUMBER('&end_year_prompt')
    GROUP  BY supplier_name
)
SELECT s.supplier_name,
       s.category_name,
       ROUND(s.net_sales_amt, 2) AS net_revenue_rm,
       TO_CHAR(ROUND(s.net_sales_amt * 100
              / SUM(s.net_sales_amt) OVER (), 2), '990.99') || '%'
              AS pct_of_total,
       TO_CHAR(ROUND(SUM(s.net_sales_amt) OVER (ORDER BY s.net_sales_amt DESC
                     ROWS UNBOUNDED PRECEDING) * 100
              / SUM(s.net_sales_amt) OVER (), 2), '990.99') || '%'
              AS cumulative_pct
FROM   sold s
ORDER  BY s.net_sales_amt DESC;

CLEAR COMPUTES
CLEAR BREAKS
CLEAR COLUMNS

-- --- Section 2: Return-rate outlier test ----------------------------------
--     WHY a ranked return rate is not on its own grounds for action.
--     expected_units is what a supplier would see if returns fell purely in
--     proportion to units sold. z_score_sd is how far the actual result sits
--     from that expectation in standard deviations. As a rule of thumb, |z|
--     below 2 is indistinguishable from chance; with twelve suppliers tested
--     at once the corrected threshold is nearer 2.87.

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Return Rate by Supplier, With the Noise Band' SKIP 1 -
       CENTER 'For Years &start_year_prompt to &end_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN supplier_name  FORMAT A24    HEADING 'Supplier'
COLUMN units_sold     FORMAT 999,999 HEADING 'Units|Sold'
COLUMN units_returned FORMAT 99,999  HEADING 'Units|Returned'
COLUMN return_pct     FORMAT A8     HEADING 'Return %'
COLUMN expected_units FORMAT 99,990.9 HEADING 'Expected|Units'
COLUMN z_score_sd     FORMAT S990.99 HEADING 'z-score|(SD)'

WITH sold AS (
    SELECT supplier_name, SUM(units_sold) AS units_sold
    FROM   vw_xs_supplier_year
    WHERE  cal_year BETWEEN TO_NUMBER('&start_year_prompt')
                        AND TO_NUMBER('&end_year_prompt')
    GROUP  BY supplier_name
), ret AS (
    SELECT supplier_name, SUM(units_returned) AS units_returned
    FROM   vw_xs_supplier_returns_year
    WHERE  cal_year BETWEEN TO_NUMBER('&start_year_prompt')
                        AND TO_NUMBER('&end_year_prompt')
    GROUP  BY supplier_name
), tot_sold AS (
    SELECT SUM(units_sold) AS all_sold FROM sold
), tot_ret AS (
    SELECT NVL(SUM(units_returned), 0) AS all_ret FROM ret
)
SELECT s.supplier_name,
       s.units_sold,
       NVL(r.units_returned, 0) AS units_returned,
       TO_CHAR(ROUND(NVL(r.units_returned, 0) * 100
              / NULLIF(s.units_sold, 0), 2), '990.99') || '%' AS return_pct,
       ROUND(tr.all_ret * s.units_sold / NULLIF(ts.all_sold, 0), 1)
              AS expected_units,
       ROUND((NVL(r.units_returned, 0)
              - tr.all_ret * s.units_sold / NULLIF(ts.all_sold, 0))
              / NULLIF(SQRT(tr.all_ret * s.units_sold
                            / NULLIF(ts.all_sold, 0)), 0), 2) AS z_score_sd
FROM   sold s
LEFT   JOIN ret r ON r.supplier_name = s.supplier_name
CROSS  JOIN tot_sold ts
CROSS  JOIN tot_ret  tr
ORDER  BY NVL(r.units_returned, 0) / NULLIF(s.units_sold, 0) DESC;

CLEAR COLUMNS

-- --- Section 3: Concentration across two halves of the period -------------
--     WHEN the exposure changed. The entered range is split at its midpoint
--     and the concentration recomputed in each half. Revenue concentration
--     and structural exposure can move in opposite directions: a wider range
--     spreads revenue over more suppliers while creating more categories
--     that are each still single-sourced.

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Supplier Concentration Compared Across Two Periods' SKIP 1 -
       CENTER 'Range &start_year_prompt to &end_year_prompt, split at &mid_year_val' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN period_years      FORMAT A11          HEADING 'Period'
COLUMN suppliers_trading FORMAT 999          HEADING 'Sole|Sources'
COLUMN net_revenue_rm    FORMAT 9,999,990.99 HEADING 'Net Revenue|(RM)'
COLUMN largest_supplier  FORMAT A22          HEADING 'Largest Supplier'
COLUMN largest_pct       FORMAT 990.9        HEADING 'Largest|%'
COLUMN top4_pct          FORMAT 990.9        HEADING 'Top 4|%'

WITH per AS (
    SELECT CASE WHEN v.cal_year <= &mid_year_val THEN 1 ELSE 2 END AS period_no,
           v.cal_year,
           v.supplier_name,
           v.net_sales_amt
    FROM   vw_xs_supplier_year v
    WHERE  v.cal_year BETWEEN TO_NUMBER('&start_year_prompt')
                          AND TO_NUMBER('&end_year_prompt')
), sup AS (
    SELECT period_no,
           MIN(cal_year)      AS y_from,
           MAX(cal_year)      AS y_to,
           supplier_name,
           SUM(net_sales_amt) AS rev
    FROM   per
    GROUP  BY period_no, supplier_name
), ranked AS (
    SELECT period_no, supplier_name, rev,
           MIN(y_from) OVER (PARTITION BY period_no) AS p_from,
           MAX(y_to)   OVER (PARTITION BY period_no) AS p_to,
           100 * rev / SUM(rev) OVER (PARTITION BY period_no) AS share_pct,
           RANK() OVER (PARTITION BY period_no ORDER BY rev DESC) AS rnk
    FROM   sup
)
SELECT TO_CHAR(MIN(p_from)) || ' - ' || TO_CHAR(MAX(p_to)) AS period_years,
       COUNT(*)                                            AS suppliers_trading,
       ROUND(SUM(rev), 2)                                  AS net_revenue_rm,
       MAX(CASE WHEN rnk = 1 THEN supplier_name END)       AS largest_supplier,
       ROUND(MAX(share_pct), 1)                            AS largest_pct,
       ROUND(SUM(CASE WHEN rnk <= 4 THEN share_pct END), 1) AS top4_pct
FROM   ranked
GROUP  BY period_no
ORDER  BY period_no;

CLEAR COLUMNS

-- --- Section 4: Drill-down, return reasons for one supplier ---------------
--     HOW the returns arise, split between a fulfilment problem the business
--     owns and a product-quality problem the supplier owns.

PROMPT
ACCEPT drilldown_supplier_prompt CHAR PROMPT 'Enter Supplier to Drill Down (e.g., KleenHome Supplies): '

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Return Reason Drill-Down' SKIP 1 -
       CENTER 'Supplier: &drilldown_supplier_prompt' SKIP 1 -
       CENTER 'For Years &start_year_prompt to &end_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN reason_category FORMAT A18       HEADING 'Reason Group'
COLUMN reason_name     FORMAT A14       HEADING 'Reason'
COLUMN return_lines    FORMAT 99,999    HEADING 'Lines'
COLUMN units_returned  FORMAT 99,999    HEADING 'Units'
COLUMN refund_value_rm FORMAT 999,990.99 HEADING 'Refund|(RM)'
COLUMN avg_days_return FORMAT 990.9     HEADING 'Avg|Days'

BREAK ON reason_category SKIP 1

COMPUTE SUM LABEL 'Group Total:' OF return_lines units_returned refund_value_rm ON reason_category

SELECT v.reason_category,
       v.reason_name,
       SUM(v.return_lines)                 AS return_lines,
       SUM(v.units_returned)               AS units_returned,
       ROUND(SUM(v.refund_amount), 2)      AS refund_value_rm,
       ROUND(AVG(v.avg_days_to_return), 1) AS avg_days_return
FROM   vw_xs_supplier_returns_year v
WHERE  UPPER(v.supplier_name) = UPPER('&drilldown_supplier_prompt')
  AND  v.cal_year BETWEEN TO_NUMBER('&start_year_prompt')
                      AND TO_NUMBER('&end_year_prompt')
GROUP  BY v.reason_category, v.reason_name
ORDER  BY v.reason_category, SUM(v.units_returned) DESC;

CLEAR COMPUTES
CLEAR BREAKS
CLEAR COLUMNS
TTITLE OFF

PROMPT
PROMPT Report 2 complete.
PROMPT


-- ===========================================================================
--  R E P O R T   3
--  Channel Migration - Online versus Walk-in
--  Dimensions: date_dim x branch_dim (region) x customer_dim (membership)
--  customer_dim is the Type 2 slowly changing dimension. sales_fact carries
--  the surrogate key that was current when the order was placed, so a member
--  who changed tier is counted under the tier held at the time rather than
--  having today's tier applied retrospectively across their whole history.
-- ===========================================================================

PROMPT
PROMPT ============================================================
PROMPT Report 3 - Channel Migration: Online versus Walk-in
PROMPT ============================================================
PROMPT

-- --- Section 1: Channel mix by year ---------------------------------------
--     WHAT the migration looks like and WHEN it happened, and WHY it matters
--     less than it appears: compare the two average baskets in each year.

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Channel Mix by Year - Online versus Walk-in' SKIP 1 -
       CENTER 'For Years &start_year_prompt to &end_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN cal_year       FORMAT 9999         HEADING 'Year'
COLUMN channel        FORMAT A10          HEADING 'Channel'
COLUMN customers      FORMAT 9,999        HEADING 'Cust'
COLUMN orders         FORMAT 99,999       HEADING 'Orders'
COLUMN pct_of_year    FORMAT A9           HEADING '% of Year'
COLUMN avg_basket_rm  FORMAT 9,990.99     HEADING 'Avg Basket|(RM)'
COLUMN net_revenue_rm FORMAT 9,999,990.99 HEADING 'Net Revenue|(RM)'

BREAK ON cal_year SKIP 1

COMPUTE SUM LABEL 'Year Total:' OF orders net_revenue_rm ON cal_year

WITH rpt AS (
    SELECT cal_year, channel, customers, orders, net_sales_amt
    FROM   vw_xs_channel_year
    WHERE  cal_year BETWEEN TO_NUMBER('&start_year_prompt')
                        AND TO_NUMBER('&end_year_prompt')
)
SELECT p.cal_year,
       p.channel,
       p.customers,
       p.orders,
       TO_CHAR(ROUND(p.orders * 100
              / SUM(p.orders) OVER (PARTITION BY p.cal_year), 2),
              '990.99') || '%' AS pct_of_year,
       ROUND(p.net_sales_amt / NULLIF(p.orders, 0), 2) AS avg_basket_rm,
       ROUND(p.net_sales_amt, 2)                       AS net_revenue_rm
FROM   rpt p
ORDER  BY p.cal_year, p.channel;

CLEAR COMPUTES
CLEAR BREAKS
CLEAR COLUMNS

-- --- Section 2: Channel mix by region, like-for-like ----------------------
--     WHERE the migration is furthest along. Restricted deliberately: online
--     share rises every year, so a branch that opened late trades only in the
--     online-heavy period and appears digitally advanced when it is merely
--     young. Enter the year by which every branch was trading.

PROMPT
ACCEPT region_from_year_prompt CHAR PROMPT 'Enter Year From Which All Branches Were Trading (e.g., 2024): '

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Channel Mix by Region' SKIP 1 -
       CENTER 'Like-for-like window: &region_from_year_prompt to &end_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN branch_region FORMAT A16      HEADING 'Region'
COLUMN branches      FORMAT 999      HEADING 'Brch'
COLUMN orders        FORMAT 99,999   HEADING 'Orders'
COLUMN online_pct    FORMAT A9       HEADING 'Online %'
COLUMN avg_basket_rm FORMAT 9,990.99 HEADING 'Avg Basket|(RM)'

BREAK ON REPORT

COMPUTE SUM LABEL 'TOTAL:' OF orders ON REPORT

SELECT v.branch_region,
       COUNT(DISTINCT v.branch_key) AS branches,
       SUM(v.orders)                AS orders,
       TO_CHAR(ROUND(100 * SUM(CASE WHEN v.channel = 'Online'
                                    THEN v.orders ELSE 0 END)
              / NULLIF(SUM(v.orders), 0), 1), '990.9') || '%' AS online_pct,
       ROUND(SUM(v.net_sales_amt) / NULLIF(SUM(v.orders), 0), 2) AS avg_basket_rm
FROM   vw_xs_channel_region v
WHERE  v.cal_year BETWEEN TO_NUMBER('&region_from_year_prompt')
                      AND TO_NUMBER('&end_year_prompt')
GROUP  BY v.branch_region
ORDER  BY SUM(CASE WHEN v.channel = 'Online' THEN v.orders ELSE 0 END)
          / NULLIF(SUM(v.orders), 0) DESC;

CLEAR COMPUTES
CLEAR BREAKS
CLEAR COLUMNS

-- --- Section 3: Drill-down, membership tier x channel ---------------------
--     WHO is migrating. Only members can take delivery, because
--     Delivery.AddressID references MemberAddress which references Member,
--     so membership is structurally tied to the online channel.

PROMPT
ACCEPT drilldown_channel_year_prompt CHAR PROMPT 'Enter Year to Drill Down (e.g., 2025): '

TTITLE CENTER '============================================================' SKIP 1 -
       CENTER 'Membership Tier and Channel Drill-Down' SKIP 1 -
       CENTER 'For Year &drilldown_channel_year_prompt' SKIP 1 -
       CENTER '============================================================' SKIP 1 -
       LEFT   'Report Generated on: ' _DATE -
       RIGHT  'Page: ' SQL.PNO SKIP 2

COLUMN membership_type FORMAT A14      HEADING 'Membership'
COLUMN channel         FORMAT A10      HEADING 'Channel'
COLUMN customers       FORMAT 9,999    HEADING 'Cust'
COLUMN orders          FORMAT 99,999   HEADING 'Orders'
COLUMN pct_of_tier     FORMAT A9       HEADING '% of Tier'
COLUMN avg_basket_rm   FORMAT 9,990.99 HEADING 'Avg Basket|(RM)'

BREAK ON membership_type SKIP 1

COMPUTE SUM LABEL 'Tier Total:' OF orders ON membership_type

WITH yr AS (
    SELECT membership_type, channel, customers, orders, net_sales_amt
    FROM   vw_xs_channel_member
    WHERE  cal_year = TO_NUMBER('&drilldown_channel_year_prompt')
)
SELECT y.membership_type,
       y.channel,
       y.customers,
       y.orders,
       TO_CHAR(ROUND(y.orders * 100
              / SUM(y.orders) OVER (PARTITION BY y.membership_type), 2),
              '990.99') || '%' AS pct_of_tier,
       ROUND(y.net_sales_amt / NULLIF(y.orders, 0), 2) AS avg_basket_rm
FROM   yr y
ORDER  BY y.membership_type, y.channel;

CLEAR COMPUTES
CLEAR BREAKS
CLEAR COLUMNS
TTITLE OFF

PROMPT
PROMPT Report 3 complete.
PROMPT


-- ===========================================================================
--  T I D Y   U P
-- ===========================================================================

UNDEFINE start_year_prompt
UNDEFINE end_year_prompt
UNDEFINE drilldown_year_prompt
UNDEFINE mid_year_val
UNDEFINE drilldown_supplier_prompt
UNDEFINE region_from_year_prompt
UNDEFINE drilldown_channel_year_prompt

SET FEEDBACK ON
SET VERIFY   ON

PROMPT
PROMPT ============================================================
PROMPT All three reports complete.
PROMPT ============================================================
PROMPT
