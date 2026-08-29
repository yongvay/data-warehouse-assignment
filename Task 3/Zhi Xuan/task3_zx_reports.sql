-- ============================================================================
--  Task 3 - Business Analytics Queries        STUDENT: ZX
--  Domain B : Branch and Regional Operations
--  RUN AS THE DW USER, FROM THE REPOSITORY ROOT
--
--      SQL> SPOOL "Task 3 output\Zhi Xuan\task3_output.txt"
--      SQL> @"Task 3\Zhi Xuan\task3_zx_reports.sql"
--      SQL> SPOOL OFF
--
--  ---------------------------------------------------------------------------
--  EXPORTING FOR POWER BI
--
--  Power BI cannot read the formatted text above. Export each CHART FEED
--  exhibit to CSV separately, then load the folder in Power BI:
--
--      SQL> SET MARKUP CSV ON
--      SQL> SET PAGESIZE 50000
--      SQL> SET FEEDBACK OFF
--      SQL> SET TRIMSPOOL ON
--      SQL> TTITLE OFF
--      SQL> SPOOL "Task 3 output\Zhi Xuan\csv\b1_1_branch_scorecard.csv"
--      ... paste ONLY the query for that exhibit ...
--      SQL> SPOOL OFF
--      SQL> SET MARKUP CSV OFF
--
--  The six files to export, and what each one draws:
--      b1_1_branch_scorecard.csv   -> Chart B1a  horizontal bar, branch net
--                                     sales, colour-grouped by region
--      b1_2_region_yoy.csv         -> Chart B1b  line, regional net sales
--                                     &p_cur_yr vs prior year
--      b2_1_hour_blocks.csv        -> Chart B2a  grouped column, hour block
--                                     x region
--      b2_2_hour_profile.csv       -> Chart B2b  line, hour 0-23 by region,
--                                     weekday vs weekend
--      b3_1_leakage_by_branch.csv  -> Chart B3a  bar, refund-to-sales % with
--                                     the company average as a constant line
--      b3_2_cause_split.csv        -> Chart B3b  stacked bar, Fulfilment vs
--                                     Product Quality
--
--  IMPORTANT: export the CSV from the RAW query. Do NOT export the version
--  with BREAK / COMPUTE active - the subtotal rows would be read by Power BI
--  as ordinary branches and every region would be counted twice. Run
--  CLEAR BREAK first if you are unsure.
--
--  ---------------------------------------------------------------------------
--  FOUR STANDING RULES, APPLIED THROUGHOUT
--
--  1. BRANCH ROLLOUT CONFOUNDS EVERY CROSS-BRANCH COMPARISON.  Four branches
--     traded in 2016; all twelve only from 2023. A branch that opened in
--     2023 cannot be ranked against one that opened in 2016 on lifetime
--     revenue. EVERY report in this file is therefore restricted to the
--     all-branches era, &p_era_yr onward. This is the single most important
--     control in Domain B and it is stated in the write-up for all three
--     reports.
--
--  2. 2026 IS A PART YEAR.  It covers January to August only. It is excluded
--     from every growth and year-on-year column. Reports 2 and 3 are level
--     measures (hour mix, refund ratio) rather than growth, so the part year
--     does them no harm and is left in - but the write-up says so.
--
--  3. RETURNS ARE MATCHED TO SALES ON THE ORDER DATE, NOT THE RETURN DATE.
--     Refund-to-sales % in Report 3 divides refunds by the sales of the same
--     order cohort. Dividing December returns by December sales would charge
--     a branch for November's mistakes.
--
--  4. THE TWO FACTS ARE AGGREGATED BEFORE THEY ARE JOINED.  sales_fact and
--     return_fact are both at line grain. Joining them directly on branch_key
--     would fan out - every sales line multiplied by every return line - and
--     inflate net sales several hundred fold. Report 3 collapses each fact to
--     one row per branch first, then joins.
-- ============================================================================

-- SET DEFINE ON MUST COME FIRST.
-- Several scripts in this repository run SET DEFINE OFF so that an '&' inside
-- a string literal is not treated as a substitution variable. That setting
-- survives for the rest of the SQL*Plus session. If it is still off when this
-- script runs, every '&p_cur_yr' below is passed through to the server
-- unresolved and you get:
--      SP2-0552: Bind variable "P_CUR_YR" not declared.
-- on all eight statements. Turning it back on here makes the script
-- independent of whatever ran before it.
SET DEFINE ON
SET SCAN ON

SET SQLBLANKLINES ON
SET LINESIZE 160
SET PAGESIZE 60
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMSPOOL ON
SET ECHO OFF
TTITLE OFF
CLEAR COLUMNS
CLEAR BREAK
CLEAR COMPUTES

-- ---------------------------------------------------------------------------
-- Flexible reporting window. Press ENTER at each prompt to take the default.
-- ---------------------------------------------------------------------------
-- Defined first, then overwritten by ACCEPT. If ACCEPT is skipped or the
-- prompts are answered with ENTER, the variables still exist and the script
-- runs on the defaults instead of failing.
DEFINE p_era_yr = 2024
DEFINE p_cur_yr = 2025

ACCEPT p_era_yr CHAR DEFAULT 2024 PROMPT 'All-branches era begins (default 2024): '
ACCEPT p_cur_yr CHAR DEFAULT 2025 PROMPT 'Reporting year, last COMPLETE year (default 2025): '

-- Echo the resolved values. If these two lines print the variable NAMES
-- rather than numbers, substitution is still off and nothing below will run.
PROMPT
PROMPT   Resolved parameters:  era = &p_era_yr    reporting year = &p_cur_yr
PROMPT

-- Run date and derived year labels, for the TTITLE headers.
COLUMN RUN_DT NOPRINT NEW_VALUE RUN_DT
COLUMN CUR_YR NOPRINT NEW_VALUE CUR_YR
COLUMN PRV_YR NOPRINT NEW_VALUE PRV_YR
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY')   AS RUN_DT,
       TO_CHAR(&p_cur_yr)                AS CUR_YR,
       TO_CHAR(&p_cur_yr - 1)            AS PRV_YR
FROM   dual;


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 1 - BRANCH PERFORMANCE SCORECARD BY REGION
PROMPT   Facts / Dims : sales_fact x branch_dim x date_dim
PROMPT   Measures     : orders, net sales, average order value, items per
PROMPT                  order, YoY growth, share of region, rank in region
PROMPT
PROMPT   THE QUESTION: every region has a leader and a laggard. Ranking the
PROMPT   twelve branches nationally hides that, because a weak branch in a
PROMPT   strong region still outsells a strong branch in a weak one. This
PROMPT   report ranks each branch WITHIN its own region, and the regional
PROMPT   subtotals show how much of the region one branch is carrying.
PROMPT ============================================================================

-- ---------------------------------------------------------------------------
--  EXHIBIT 1.1  Branch scorecard, with regional subtotals   [CHART FEED B1a]
-- ---------------------------------------------------------------------------
PROMPT
PROMPT --- EXHIBIT 1.1  Branch scorecard by region  [CHART: horizontal bar] ===
PROMPT WHAT EACH COLUMN IS FOR: Orders counts DISTINCT order numbers, not fact
PROMPT rows, because sales_fact is at line grain and a five-item basket is one
PROMPT order. AOV is how large a visit is; Items per Order is how full the
PROMPT basket is - the two together separate a price effect from a volume one.
PROMPT Share of Region is the branch measured against its own peers, and Rank
PROMPT in Region is the same thing ordered. YoY Growth compares two complete
PROMPT years only.

CLEAR BREAK
CLEAR COMPUTES
CLEAR COLUMNS

COLUMN branch_region    HEADING 'REGION'            FORMAT A14
COLUMN branch_name      HEADING 'BRANCH'            FORMAT A22
COLUMN orders           HEADING 'ORDERS'            FORMAT 999,990
COLUMN net_sales        HEADING 'NET SALES|(RM)'    FORMAT 999,999,990.99
COLUMN aov              HEADING 'AVG ORDER|VALUE'   FORMAT 9,990.99
COLUMN items_per_order  HEADING 'ITEMS|/ORDER'      FORMAT 990.99
COLUMN yoy_growth_pct   HEADING 'YoY %|&CUR_YR v &PRV_YR' FORMAT 990.9
COLUMN region_share_pct HEADING 'SHARE OF|REGION %' FORMAT 990.9
COLUMN rank_in_region   HEADING 'RANK|IN RGN'       FORMAT 990

BREAK ON branch_region SKIP 1
COMPUTE SUM LABEL 'REGION TOTAL' OF orders net_sales ON branch_region

TTITLE LEFT 'REPORT 1 - BRANCH PERFORMANCE SCORECARD BY REGION' -
       RIGHT 'Run: ' RUN_DT SKIP 1 -
       LEFT 'All-branches era &p_era_yr onward.  Growth = &CUR_YR against &PRV_YR.' SKIP 2

WITH scoped AS (
    SELECT b.branch_region,
           b.branch_name,
           d.cal_year,
           s.order_no,
           s.quantity,
           s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year BETWEEN LEAST(&p_era_yr, &p_cur_yr - 1) AND &p_cur_yr
), cur AS (
    SELECT branch_region,
           branch_name,
           COUNT(DISTINCT order_no) AS orders,
           SUM(quantity)            AS units,
           SUM(net_sales_amt)       AS net_sales
    FROM   scoped
    WHERE  cal_year = &p_cur_yr
    GROUP  BY branch_region, branch_name
), prv AS (
    SELECT branch_region,
           branch_name,
           SUM(net_sales_amt) AS net_sales_prv
    FROM   scoped
    WHERE  cal_year = &p_cur_yr - 1
    GROUP  BY branch_region, branch_name
)
SELECT c.branch_region,
       c.branch_name,
       c.orders,
       ROUND(c.net_sales, 2)                                      AS net_sales,
       ROUND(c.net_sales / NULLIF(c.orders, 0), 2)                AS aov,
       ROUND(c.units     / NULLIF(c.orders, 0), 2)                AS items_per_order,
       ROUND(100 * (c.net_sales - p.net_sales_prv)
                 / NULLIF(p.net_sales_prv, 0), 1)                 AS yoy_growth_pct,
       ROUND(100 * c.net_sales
                 / NULLIF(SUM(c.net_sales) OVER
                          (PARTITION BY c.branch_region), 0), 1)  AS region_share_pct,
       RANK() OVER (PARTITION BY c.branch_region
                    ORDER BY c.net_sales DESC)                    AS rank_in_region
FROM   cur c
LEFT   JOIN prv p
       ON  p.branch_region = c.branch_region
       AND p.branch_name   = c.branch_name
ORDER  BY c.branch_region, c.net_sales DESC;

TTITLE OFF
CLEAR BREAK
CLEAR COMPUTES

-- ---------------------------------------------------------------------------
--  EXHIBIT 1.2  Regional roll-up and growth               [CHART FEED B1b]
-- ---------------------------------------------------------------------------
PROMPT
PROMPT --- EXHIBIT 1.2  Region roll-up and growth  [CHART: line] ===
PROMPT WHY IT MATTERS: Exhibit 1.1 answers who is winning inside a region.
PROMPT This one answers whether the region itself is growing. A branch ranked
PROMPT first in a region shrinking 8 percent is not a success story, and the
PROMPT two exhibits have to be read together for that to be visible.
PROMPT Branches Trading is printed because a region that gained a branch
PROMPT between the two years will show growth that is not like-for-like.

CLEAR COLUMNS
COLUMN branch_region     HEADING 'REGION'              FORMAT A14
COLUMN branches_trading  HEADING 'BRANCHES|TRADING'    FORMAT 990
COLUMN sales_prv         HEADING '&PRV_YR|NET SALES'   FORMAT 999,999,990.99
COLUMN sales_cur         HEADING '&CUR_YR|NET SALES'   FORMAT 999,999,990.99
COLUMN yoy_growth_pct    HEADING 'YoY|GROWTH %'        FORMAT 990.9
COLUMN natl_share_pct    HEADING 'NATIONAL|SHARE %'    FORMAT 990.9
COLUMN aov_cur           HEADING '&CUR_YR|AVG ORDER'   FORMAT 9,990.99
COLUMN growth_rank       HEADING 'GROWTH|RANK'         FORMAT 990

WITH scoped AS (
    SELECT b.branch_region,
           b.branch_name,
           d.cal_year,
           s.order_no,
           s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year BETWEEN LEAST(&p_era_yr, &p_cur_yr - 1) AND &p_cur_yr
), reg AS (
    SELECT branch_region,
           COUNT(DISTINCT branch_name)                                       AS branches_trading,
           SUM(CASE WHEN cal_year = &p_cur_yr - 1 THEN net_sales_amt END)    AS sales_prv,
           SUM(CASE WHEN cal_year = &p_cur_yr     THEN net_sales_amt END)    AS sales_cur,
           COUNT(DISTINCT CASE WHEN cal_year = &p_cur_yr THEN order_no END)  AS orders_cur
    FROM   scoped
    GROUP  BY branch_region
)
SELECT branch_region,
       branches_trading,
       ROUND(sales_prv, 2)                                      AS sales_prv,
       ROUND(sales_cur, 2)                                      AS sales_cur,
       ROUND(100 * (sales_cur - sales_prv)
                 / NULLIF(sales_prv, 0), 1)                     AS yoy_growth_pct,
       ROUND(100 * sales_cur
                 / NULLIF(SUM(sales_cur) OVER (), 0), 1)        AS natl_share_pct,
       ROUND(sales_cur / NULLIF(orders_cur, 0), 2)              AS aov_cur,
       RANK() OVER (ORDER BY (sales_cur - sales_prv)
                             / NULLIF(sales_prv, 0) DESC)       AS growth_rank
FROM   reg
ORDER  BY sales_cur DESC;


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 2 - PEAK TRADING HOURS AND WEEKDAY/WEEKEND PATTERN BY REGION
PROMPT   Facts / Dims : sales_fact (order_hour) x date_dim (weekday_ind,
PROMPT                  day_week) x branch_dim (branch_region)
PROMPT   Measures     : net sales by hour block, peak block, weekday and
PROMPT                  weekend sales, weekend share, rank
PROMPT
PROMPT   THE QUESTION: staff rosters and delivery slots are set regionally,
PROMPT   not nationally. Four of the five regions turn out to peak in the
PROMPT   same After-work block, so the block mix alone does not justify a
PROMPT   regional roster - Exhibit 2.3 is where the regions actually differ.
PROMPT
PROMPT   NOTE: this report measures the SHAPE of the trading day, not growth,
PROMPT   so the part year 2026 is included without distortion. Hour blocks
PROMPT
PROMPT   BLOCK BOUNDARIES ARE SET FROM THE DATA, NOT FROM CONVENTION. The
PROMPT   warehouse holds no orders before 08:00 and effectively none after
PROMPT   22:00 - one order at 23:00 in the whole era - so the branches trade
PROMPT   08:00-22:00. A conventional Morning/Afternoon/Evening/Night split
PROMPT   would leave the Night column empty, and it would put 17:00 on a
PROMPT   block boundary. 17:00 is the busiest single hour in the Southern
PROMPT   region, so that boundary alone would decide whether Southern is
PROMPT   classed Afternoon or Evening. The blocks below follow the shape of
PROMPT   the trading day instead: Opening 08-11, Midday 12-16, After-work
PROMPT   17-19, Late 20-22.
PROMPT ============================================================================

-- ---------------------------------------------------------------------------
--  EXHIBIT 2.1  Hour block and weekend mix by region      [CHART FEED B2a]
-- ---------------------------------------------------------------------------
PROMPT
PROMPT --- EXHIBIT 2.1  Trading day shape by region  [CHART: grouped column] ===
PROMPT WHAT EACH COLUMN IS FOR: the four block columns are a CASE pivot of
PROMPT order_hour, so they sum to the region total and can be read as a mix.
PROMPT Peak Block names the winning column so the reader does not have to
PROMPT compare four figures by eye. Weekend Share is the roster-critical
PROMPT number: two days carry that share, five days carry the rest, so any
PROMPT figure above 28.6 percent means the weekend is trading ABOVE its
PROMPT calendar weight.

CLEAR COLUMNS
CLEAR BREAK
CLEAR COMPUTES

COLUMN branch_region     HEADING 'REGION'               FORMAT A14
COLUMN morning_amt       HEADING 'OPENING|08-11'        FORMAT 999,999,990
COLUMN afternoon_amt     HEADING 'MIDDAY|12-16'         FORMAT 999,999,990
COLUMN evening_amt       HEADING 'AFTER-WORK|17-19'     FORMAT 999,999,990
COLUMN night_amt         HEADING 'LATE|20-22'           FORMAT 999,999,990
COLUMN peak_block        HEADING 'PEAK|BLOCK'           FORMAT A11
COLUMN weekday_amt       HEADING 'WEEKDAY|SALES'        FORMAT 999,999,990
COLUMN weekend_amt       HEADING 'WEEKEND|SALES'        FORMAT 999,999,990
COLUMN weekend_share_pct HEADING 'WEEKEND|SHARE %'      FORMAT 990.9
COLUMN sales_rank        HEADING 'SALES|RANK'           FORMAT 990

TTITLE LEFT 'REPORT 2 - PEAK TRADING HOURS AND WEEKDAY/WEEKEND PATTERN' -
       RIGHT 'Run: ' RUN_DT SKIP 1 -
       LEFT 'All-branches era &p_era_yr onward.  Weekend calendar weight = 28.6%.' SKIP 2

WITH blocks AS (
    SELECT b.branch_region,
           CASE WHEN s.order_hour BETWEEN  8 AND 11 THEN 'Opening'
                WHEN s.order_hour BETWEEN 12 AND 16 THEN 'Midday'
                WHEN s.order_hour BETWEEN 17 AND 19 THEN 'After-work'
                ELSE 'Late'
           END               AS hour_block,
           d.weekday_ind,
           s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
), pivoted AS (
    SELECT branch_region,
           SUM(CASE WHEN hour_block = 'Opening'    THEN net_sales_amt ELSE 0 END) AS morning_amt,
           SUM(CASE WHEN hour_block = 'Midday'     THEN net_sales_amt ELSE 0 END) AS afternoon_amt,
           SUM(CASE WHEN hour_block = 'After-work' THEN net_sales_amt ELSE 0 END) AS evening_amt,
           SUM(CASE WHEN hour_block = 'Late'       THEN net_sales_amt ELSE 0 END) AS night_amt,
           SUM(CASE WHEN weekday_ind = 'Y' THEN net_sales_amt ELSE 0 END)        AS weekday_amt,
           SUM(CASE WHEN weekday_ind = 'N' THEN net_sales_amt ELSE 0 END)        AS weekend_amt,
           SUM(net_sales_amt)                                                    AS total_amt
    FROM   blocks
    GROUP  BY branch_region
)
SELECT branch_region,
       ROUND(morning_amt)   AS morning_amt,
       ROUND(afternoon_amt) AS afternoon_amt,
       ROUND(evening_amt)   AS evening_amt,
       ROUND(night_amt)     AS night_amt,
       CASE WHEN morning_amt   >= afternoon_amt
             AND morning_amt   >= evening_amt
             AND morning_amt   >= night_amt      THEN 'Opening'
            WHEN afternoon_amt >= evening_amt
             AND afternoon_amt >= night_amt      THEN 'Midday'
            WHEN evening_amt   >= night_amt      THEN 'After-work'
            ELSE 'Late'
       END                  AS peak_block,
       ROUND(weekday_amt)   AS weekday_amt,
       ROUND(weekend_amt)   AS weekend_amt,
       ROUND(100 * weekend_amt / NULLIF(total_amt, 0), 1) AS weekend_share_pct,
       RANK() OVER (ORDER BY total_amt DESC)              AS sales_rank
FROM   pivoted
ORDER  BY total_amt DESC;

TTITLE OFF

-- ---------------------------------------------------------------------------
--  EXHIBIT 2.2  Hour-by-hour profile, weekday vs weekend  [CHART FEED B2b]
-- ---------------------------------------------------------------------------
PROMPT
PROMPT --- EXHIBIT 2.2  Hour-by-hour profile by region  [CHART: line] ===
PROMPT WHY IT MATTERS: the four blocks in 2.1 are a management summary, but
PROMPT they hide where inside a block the peak actually sits. A shift cannot
PROMPT be scheduled on a six-hour bucket. This exhibit is the same data at
PROMPT hourly resolution, split weekday against weekend, and it is the one
PROMPT that tells the roster which hour to add a cashier to.
PROMPT The output is 15 to 16 rows per region and is meant for the chart rather
PROMPT than for reading in the report body.

CLEAR COLUMNS
COLUMN branch_region  HEADING 'REGION'          FORMAT A14
COLUMN order_hour     HEADING 'HOUR'            FORMAT 90
COLUMN weekday_amt    HEADING 'WEEKDAY|SALES'   FORMAT 999,999,990
COLUMN weekend_amt    HEADING 'WEEKEND|SALES'   FORMAT 999,999,990
COLUMN weekday_orders HEADING 'WEEKDAY|ORDERS'  FORMAT 999,990
COLUMN weekend_orders HEADING 'WEEKEND|ORDERS'  FORMAT 999,990
COLUMN hour_share_pct HEADING 'SHARE OF|REGION %' FORMAT 990.99

SELECT b.branch_region,
       s.order_hour,
       ROUND(SUM(CASE WHEN d.weekday_ind = 'Y' THEN s.net_sales_amt ELSE 0 END))    AS weekday_amt,
       ROUND(SUM(CASE WHEN d.weekday_ind = 'N' THEN s.net_sales_amt ELSE 0 END))    AS weekend_amt,
       COUNT(DISTINCT CASE WHEN d.weekday_ind = 'Y' THEN s.order_no END)            AS weekday_orders,
       COUNT(DISTINCT CASE WHEN d.weekday_ind = 'N' THEN s.order_no END)            AS weekend_orders,
       ROUND(100 * SUM(s.net_sales_amt)
                 / NULLIF(SUM(SUM(s.net_sales_amt))
                          OVER (PARTITION BY b.branch_region), 0), 2)               AS hour_share_pct
FROM   sales_fact s
JOIN   branch_dim b ON b.branch_key = s.branch_key
JOIN   date_dim   d ON d.date_key   = s.order_date_key
WHERE  b.branch_key <> -1
AND    d.cal_year >= &p_era_yr
GROUP  BY b.branch_region, s.order_hour
ORDER  BY b.branch_region, s.order_hour;


PROMPT
PROMPT --- EXHIBIT 2.3  Weekend concentration by block  [CHART: grouped column] ===
PROMPT WHY IT MATTERS: Exhibit 2.1 shows that four of the five regions peak in
PROMPT the same After-work block, so the block mix alone is a weak basis for
PROMPT regional rostering. The real divergence is WHEN IN THE WEEK each block
PROMPT is busy. A weekend share above 28.6 percent means those two days are
PROMPT pulling more than their calendar weight in that block, and that is the
PROMPT number a regional roster is actually built on.

CLEAR COLUMNS
COLUMN branch_region    HEADING 'REGION'            FORMAT A14
COLUMN hour_block       HEADING 'BLOCK'             FORMAT A12
COLUMN weekday_amt      HEADING 'WEEKDAY|SALES'     FORMAT 999,999,990
COLUMN weekend_amt      HEADING 'WEEKEND|SALES'     FORMAT 999,999,990
COLUMN weekend_share_pct HEADING 'WEEKEND|SHARE %'  FORMAT 990.9
COLUMN vs_calendar      HEADING 'VS 28.6%|CALENDAR' FORMAT A12

WITH blocks AS (
    SELECT b.branch_region,
           CASE WHEN s.order_hour BETWEEN  8 AND 11 THEN '1 Opening'
                WHEN s.order_hour BETWEEN 12 AND 16 THEN '2 Midday'
                WHEN s.order_hour BETWEEN 17 AND 19 THEN '3 After-work'
                ELSE '4 Late'
           END              AS hour_block,
           d.weekday_ind,
           s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
), agg AS (
    SELECT branch_region,
           hour_block,
           SUM(CASE WHEN weekday_ind = 'Y' THEN net_sales_amt ELSE 0 END) AS weekday_amt,
           SUM(CASE WHEN weekday_ind = 'N' THEN net_sales_amt ELSE 0 END) AS weekend_amt
    FROM   blocks
    GROUP  BY branch_region, hour_block
)
SELECT branch_region,
       hour_block,
       ROUND(weekday_amt) AS weekday_amt,
       ROUND(weekend_amt) AS weekend_amt,
       ROUND(100 * weekend_amt
                 / NULLIF(weekday_amt + weekend_amt, 0), 1) AS weekend_share_pct,
       CASE WHEN ROUND(100 * weekend_amt
                     / NULLIF(weekday_amt + weekend_amt, 0), 1) >= 28.6
            THEN 'OVER'  ELSE 'under' END                   AS vs_calendar
FROM   agg
ORDER  BY branch_region, hour_block;


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 3 - BRANCH RETURN LEAKAGE: REFUND-TO-SALES BY CAUSE
PROMPT   Facts / Dims : sales_fact + return_fact x branch_dim x
PROMPT                  return_reason_dim x date_dim
PROMPT   Measures     : net sales, refund amount, refund-to-sales percent,
PROMPT                  Fulfilment vs Product Quality split, days to return
PROMPT
PROMPT   THE QUESTION: a refund is revenue that was booked and then handed
PROMPT   back. The percentage matters more than the absolute, because the
PROMPT   largest branch will always refund the most ringgit. The cause split
PROMPT   is what makes the number actionable: Fulfilment-caused returns
PROMPT   (Missing, Wrong Item) are a branch picking and packing failure and
PROMPT   the branch manager owns them. Quality-caused returns (Broken,
PROMPT   Expired) are a supplier, handling or cold-chain failure and
PROMPT   procurement owns them. Same symptom, different department.
PROMPT
PROMPT   COUNTED AS LEAKAGE: return_status IN ('Approved','Refunded') only.
PROMPT   A Pending or Rejected return has not cost the company anything yet.
PROMPT ============================================================================

-- ---------------------------------------------------------------------------
--  EXHIBIT 3.1  Company baseline - the reference line
-- ---------------------------------------------------------------------------
PROMPT
PROMPT --- EXHIBIT 3.1  Company-wide baseline ===
PROMPT WHY IT COMES FIRST: every branch figure in 3.2 is judged against this
PROMPT one number. It is also the value to enter as the constant reference
PROMPT line on Chart B3a - without it the bar chart shows which branch is
PROMPT worst but not whether ANY of them is unacceptable.

CLEAR COLUMNS
CLEAR BREAK
CLEAR COMPUTES

COLUMN metric  HEADING 'MEASURE'  FORMAT A48
COLUMN figure  HEADING 'VALUE'    FORMAT A18

WITH sales AS (
    SELECT SUM(s.net_sales_amt) AS net_sales
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
), rets AS (
    SELECT SUM(r.refund_amount)                AS refund_amt,
           SUM(r.quantity_returned)            AS qty_returned,
           AVG(GREATEST(r.days_to_return, 0))  AS avg_days,
           SUM(CASE WHEN rr.reason_category = 'Fulfilment'
                    THEN r.refund_amount ELSE 0 END) AS fulfil_amt,
           SUM(CASE WHEN rr.reason_category = 'Product Quality'
                    THEN r.refund_amount ELSE 0 END) AS quality_amt
    FROM   return_fact       r
    JOIN   branch_dim        b  ON b.branch_key = r.branch_key
    JOIN   return_reason_dim rr ON rr.reason_key = r.reason_key
    JOIN   date_dim          d  ON d.date_key   = r.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
    AND    r.return_status IN ('Approved', 'Refunded')
)
SELECT 'Net sales, &p_era_yr onward (RM)'                AS metric,
       TO_CHAR(ROUND(s.net_sales, 2), '999,999,990.99')  AS figure
FROM sales s
UNION ALL
SELECT 'Refunds settled (RM)',
       TO_CHAR(ROUND(r.refund_amt, 2), '999,999,990.99') FROM rets r
UNION ALL
SELECT '>>> COMPANY REFUND-TO-SALES % (reference line)',
       TO_CHAR(ROUND(100 * r.refund_amt / NULLIF(s.net_sales, 0), 2), '990.99')
FROM sales s, rets r
UNION ALL
SELECT 'Refunds caused by Fulfilment (RM)',
       TO_CHAR(ROUND(r.fulfil_amt, 2), '999,999,990.99') FROM rets r
UNION ALL
SELECT 'Refunds caused by Product Quality (RM)',
       TO_CHAR(ROUND(r.quality_amt, 2), '999,999,990.99') FROM rets r
UNION ALL
SELECT 'Fulfilment share of refund value (%)',
       TO_CHAR(ROUND(100 * r.fulfil_amt
                   / NULLIF(r.fulfil_amt + r.quality_amt, 0), 1), '990.9') FROM rets r
UNION ALL
SELECT 'Units returned',
       TO_CHAR(r.qty_returned, '999,999,990')            FROM rets r
UNION ALL
SELECT 'Average days to return',
       TO_CHAR(ROUND(r.avg_days, 1), '990.9')            FROM rets r;

-- ---------------------------------------------------------------------------
--  EXHIBIT 3.2  Leakage by branch, worst first           [CHART FEED B3a]
-- ---------------------------------------------------------------------------
PROMPT
PROMPT --- EXHIBIT 3.2  Return leakage by branch  [CHART: bar + reference line] ===
PROMPT WHAT EACH COLUMN IS FOR: Refund-to-Sales % is the headline and the
PROMPT rank is built on it, not on refund ringgit, so a large branch is not
PROMPT punished for being large. The two cause columns are the same refund
PROMPT value split by who owns the fix. Avg Days to Return is a diagnostic:
PROMPT a Quality problem found in two days is damage in transit, one found in
PROMPT twenty is shelf life. The subtotal rows below each region come from
PROMPT BREAK ON with COMPUTE SUM.
PROMPT
PROMPT HOW THE TWO FACTS ARE COMBINED: each fact is collapsed to one row per
PROMPT branch in its own CTE before the join. A direct join of the two line
PROMPT grain tables would multiply every sales line by every return line.

CLEAR COLUMNS
COLUMN branch_region    HEADING 'REGION'             FORMAT A14
COLUMN branch_name      HEADING 'BRANCH'             FORMAT A22
COLUMN net_sales        HEADING 'NET SALES|(RM)'     FORMAT 999,999,990.99
COLUMN refund_amt       HEADING 'REFUNDS|(RM)'       FORMAT 9,999,990.99
COLUMN refund_pct       HEADING 'REFUND TO|SALES %'  FORMAT 990.99
COLUMN fulfil_amt       HEADING 'FULFILMENT|CAUSE RM' FORMAT 9,999,990.99
COLUMN quality_amt      HEADING 'QUALITY|CAUSE RM'   FORMAT 9,999,990.99
COLUMN avg_days_return  HEADING 'AVG DAYS|TO RETURN' FORMAT 990.9
COLUMN leak_rank        HEADING 'RANK|WORST 1st'     FORMAT 990

BREAK ON branch_region SKIP 1
COMPUTE SUM LABEL 'REGION TOTAL' OF net_sales refund_amt fulfil_amt quality_amt ON branch_region

TTITLE LEFT 'REPORT 3 - BRANCH RETURN LEAKAGE BY CAUSE' -
       RIGHT 'Run: ' RUN_DT SKIP 1 -
       LEFT 'All-branches era &p_era_yr onward.  Returns matched to sales on ORDER date.' SKIP 2

WITH sales AS (
    SELECT b.branch_region,
           b.branch_name,
           SUM(s.net_sales_amt) AS net_sales
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
    GROUP  BY b.branch_region, b.branch_name
), rets AS (
    SELECT b.branch_region,
           b.branch_name,
           SUM(r.refund_amount)               AS refund_amt,
           AVG(GREATEST(r.days_to_return, 0)) AS avg_days_return,
           SUM(CASE WHEN rr.reason_category = 'Fulfilment'
                    THEN r.refund_amount ELSE 0 END) AS fulfil_amt,
           SUM(CASE WHEN rr.reason_category = 'Product Quality'
                    THEN r.refund_amount ELSE 0 END) AS quality_amt
    FROM   return_fact       r
    JOIN   branch_dim        b  ON b.branch_key  = r.branch_key
    JOIN   return_reason_dim rr ON rr.reason_key = r.reason_key
    JOIN   date_dim          d  ON d.date_key    = r.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
    AND    r.return_status IN ('Approved', 'Refunded')
    GROUP  BY b.branch_region, b.branch_name
)
SELECT s.branch_region,
       s.branch_name,
       ROUND(s.net_sales, 2)                  AS net_sales,
       ROUND(NVL(r.refund_amt, 0), 2)         AS refund_amt,
       ROUND(100 * NVL(r.refund_amt, 0)
                 / NULLIF(s.net_sales, 0), 2) AS refund_pct,
       ROUND(NVL(r.fulfil_amt, 0), 2)         AS fulfil_amt,
       ROUND(NVL(r.quality_amt, 0), 2)        AS quality_amt,
       ROUND(NVL(r.avg_days_return, 0), 1)    AS avg_days_return,
       RANK() OVER (ORDER BY NVL(r.refund_amt, 0)
                             / NULLIF(s.net_sales, 0) DESC) AS leak_rank
FROM   sales s
LEFT   JOIN rets r
       ON  r.branch_region = s.branch_region
       AND r.branch_name   = s.branch_name
ORDER  BY s.branch_region, refund_pct DESC;

TTITLE OFF
CLEAR BREAK
CLEAR COMPUTES

-- ---------------------------------------------------------------------------
--  EXHIBIT 3.3  Cause split by region and reason         [CHART FEED B3b]
-- ---------------------------------------------------------------------------
PROMPT
PROMPT --- EXHIBIT 3.3  Cause split by region  [CHART: stacked bar] ===
PROMPT WHY IT MATTERS: 3.2 gives the split as two ringgit columns per branch.
PROMPT This exhibit rolls it to region and adds the four underlying reasons,
PROMPT which is what turns a percentage into an instruction. Fulfilment
PROMPT dominated by Wrong Item is a picking and labelling problem; dominated
PROMPT by Missing it is a packing or shrinkage problem. Quality dominated by
PROMPT Expired is stock rotation; dominated by Broken it is handling or
PROMPT transit.

CLEAR COLUMNS
COLUMN branch_region   HEADING 'REGION'            FORMAT A14
COLUMN reason_category HEADING 'CAUSE|CATEGORY'    FORMAT A16
COLUMN reason_name     HEADING 'REASON'            FORMAT A14
COLUMN qty_returned    HEADING 'UNITS|RETURNED'    FORMAT 999,990
COLUMN refund_amt      HEADING 'REFUND|(RM)'       FORMAT 9,999,990.99
COLUMN region_share_pct HEADING 'SHARE OF|REGION %' FORMAT 990.9
COLUMN avg_days_return HEADING 'AVG DAYS|TO RETURN' FORMAT 990.9

SELECT b.branch_region,
       rr.reason_category,
       rr.reason_name,
       SUM(r.quantity_returned)                       AS qty_returned,
       ROUND(SUM(r.refund_amount), 2)                 AS refund_amt,
       ROUND(100 * SUM(r.refund_amount)
                 / NULLIF(SUM(SUM(r.refund_amount))
                          OVER (PARTITION BY b.branch_region), 0), 1) AS region_share_pct,
       ROUND(AVG(GREATEST(r.days_to_return, 0)), 1)   AS avg_days_return
FROM   return_fact       r
JOIN   branch_dim        b  ON b.branch_key  = r.branch_key
JOIN   return_reason_dim rr ON rr.reason_key = r.reason_key
JOIN   date_dim          d  ON d.date_key    = r.order_date_key
WHERE  b.branch_key <> -1
AND    d.cal_year >= &p_era_yr
AND    r.return_status IN ('Approved', 'Refunded')
GROUP  BY b.branch_region, rr.reason_category, rr.reason_name
ORDER  BY b.branch_region, rr.reason_category, refund_amt DESC;


PROMPT
PROMPT ============================================================================
PROMPT   END OF DOMAIN B REPORTS
PROMPT ============================================================================

CLEAR COLUMNS
CLEAR BREAK
CLEAR COMPUTES
TTITLE OFF
SET FEEDBACK ON
