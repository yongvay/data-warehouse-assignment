-- ============================================================================
--  Task 3 - CSV EXPORT FOR POWER BI            STUDENT: YV
--  Domain C : Customer, Membership and Loyalty
--  RUN AS THE DW USER, FROM THE REPOSITORY ROOT
--
--      cd "C:\...\data-warehouse-assignment"
--      sqlplus dw/<password>@localhost:1521/FREEPDB1
--      SQL> @"Task 3\Yong Vay\task3_yv_csv_export.sql"
--
--  WHAT THIS IS FOR
--  task3_yv_reports.sql produces the eighteen exhibits as SPOOLED TEXT, which
--  is the written chapter. This file produces the same eighteen exhibits as
--  CSV, which is what Power BI charts. The SQL stays the single source of
--  truth: every one of the four standing rules is enforced here exactly as it
--  is in the report, so the charts cannot drift away from the prose.
--
--  Step-by-step Power BI instructions: see POWERBI_GUIDE.md in this folder.
--
--  ......................................................................
--  WHY THIS FILE LOOKS DIFFERENT FROM Zhi Xuan's task3_zx_csv_export.sql
--
--  His builds each CSV line by concatenating columns with || ',' || because
--  SET MARKUP CSV ON needs SQL*Plus 12.2 or later and he was on an 11g
--  client. This machine runs Oracle 26ai, so MARKUP CSV is available and is
--  used instead - it writes the header row, quotes text and escapes embedded
--  quotes on its own. Do not copy his PROMPT-as-header technique into this
--  file: with MARKUP CSV on, a PROMPT inside a SPOOL block lands in the file
--  as a junk data row.
--  ......................................................................
--
--  FIVE THINGS THIS EXPORT DOES DELIBERATELY. Each one is a way a CSV export
--  of THESE exhibits goes wrong, and each has cost somebody an afternoon.
--
--  1. NO TO_CHAR NUMBER MASKS. Exhibit 2.1 of the report prints its figures
--     through TO_CHAR(..., '999G999G999') and appends ' %'. Those thousands
--     separators and that percent sign make Power BI type the whole column as
--     text, and a text column cannot go in a Values well. The export returns
--     bare numerics and lets Power BI do the formatting.
--
--  2. NO BREAK, NO COMPUTE. The report's Exhibit 3.2 carries
--     COMPUTE SUM LABEL 'State total'. Written into a CSV, that subtotal row
--     is read by Power BI as an ordinary city and every state is counted
--     twice. They are cleared below and never re-enabled.
--
--  3. QUOTED MIXED-CASE ALIASES. MARKUP CSV emits the alias verbatim, so
--     AS "Spend per Customer" gives a header that is already a readable axis
--     title. Unquoted, Oracle would hand Power BI SPEND_PER_CUST.
--
--  4. EXPLICIT SORT COLUMNS ON THE TWO MONTHLY SERIES (c2_4, c3_3).
--     cal_year_month is CHAR(7) 'YYYY-MM' so it happens to sort correctly as
--     text, but relying on that is fragile. Year and month number are
--     exported alongside so the axis can be given a proper Sort-by column.
--
--  5. c3_1 CARRIES THE NATIONAL RATE AS ITS OWN COLUMN. Power BI's Analytics
--     pane offers an "Average line" that looks like the reference line
--     Exhibit 3.1 asks for. It is not. It averages the twelve plotted STATE
--     PERCENTAGES - an unweighted mean, which is not the national dormancy
--     rate, because states hold different numbers of customers. The true
--     figure is computed here over the same population and exported as a
--     column, to be plotted as a second series.
--
--  DEFINE, NOT ACCEPT. The report script prompts for its year window; this
--  one does not, so it can be re-run unattended after every ETL reload.
--  Edit the four DEFINE lines below if you need a different window.
-- ============================================================================

SET DEFINE ON
SET SCAN   ON

-- >>> EDIT THESE IF YOU NEED A DIFFERENT WINDOW <<<
-- csv_dir is relative to the directory SQL*Plus was STARTED from, which the
-- README requires to be the repository root. Use an absolute path if you
-- prefer; SQL*Plus will not create a missing folder, which is what SP2-0606
-- means, so the HOST mkdir below creates it for you. Windows prints a
-- harmless "already exists" if it is there.
DEFINE csv_dir    = "Task 3 output\Yong Vay\csv"
DEFINE p_start_yr = 2016
DEFINE p_end_yr   = 2026
DEFINE p_era_yr   = 2024

HOST mkdir "&csv_dir"

CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF

SET MARKUP CSV ON QUOTE ON
SET HEADING     ON
SET PAGESIZE    50000
SET LINESIZE    32767
SET LONG        32767
SET FEEDBACK    OFF
SET VERIFY      OFF
SET ECHO        OFF
SET TRIMSPOOL   ON
SET TRIMOUT     ON
SET SQLBLANKLINES ON

-- Screen output is suppressed so eighteen result sets do not scroll past.
-- IF A CSV COMES OUT CONTAINING AN ORA- OR SP2- MESSAGE, that is the error
-- this line hid. Comment out the next line and re-run to see it on screen.
SET TERMOUT OFF


-- ###########################################################################
--  REPORT 1 - MEMBERSHIP TIER ECONOMICS
-- ###########################################################################

-- ---------------------------------------------------------------------------
--  c1_1  Tier value scorecard              CHART: clustered column
--        Spend per customer against average order value. The headline.
--        Headcount is COUNT(DISTINCT customer_id) - customer_dim is Type 2,
--        so a tier upgrader owns more than one customer_key.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c1_1_tier_value.csv"
WITH tier_sales AS (
    SELECT c.membership_type,
           COUNT(DISTINCT c.customer_id) AS customers,
           COUNT(DISTINCT s.order_no)    AS orders,
           SUM(s.net_sales_amt)          AS net_sales
    FROM   sales_fact   s
    JOIN   customer_dim c ON c.customer_key = s.customer_key
    JOIN   date_dim     d ON d.date_key     = s.order_date_key
    WHERE  c.customer_key <> -1
    AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
    GROUP  BY c.membership_type
)
SELECT membership_type                                     AS "Tier",
       customers                                           AS "Customers",
       orders                                              AS "Orders",
       ROUND(orders / NULLIF(customers, 0), 2)             AS "Orders per Customer",
       ROUND(net_sales, 2)                                 AS "Net Sales",
       ROUND(100 * net_sales / SUM(net_sales) OVER (), 1)  AS "Sales Share Pct",
       ROUND(net_sales / NULLIF(orders, 0), 2)             AS "Avg Order Value",
       ROUND(net_sales / NULLIF(customers, 0), 2)          AS "Spend per Customer",
       RANK() OVER (ORDER BY net_sales / NULLIF(customers, 0) DESC)
                                                           AS "Value Rank"
FROM   tier_sales
ORDER  BY "Spend per Customer" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c1_2  What the tier costs against what it collects   CHART: table
--        RM and points do not share an axis, so this stays a table.
--        Fee revenue counts CURRENT member versions only.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c1_2_tier_cost_vs_income.csv"
WITH fee AS (
    SELECT membership_type,
           COUNT(DISTINCT customer_id) AS current_members,
           SUM(annual_fee)             AS annual_fee_revenue,
           MAX(point_earn_rate)        AS earn_rate_per_rm
    FROM   customer_dim
    WHERE  customer_key <> -1
    AND    is_current_flag = 'Y'
    GROUP  BY membership_type
), pts AS (
    SELECT c.membership_type,
           SUM(p.points_earned)   AS points_earned,
           SUM(p.points_redeemed) AS points_redeemed
    FROM   point_fact   p
    JOIN   customer_dim c ON c.customer_key = p.customer_key
    JOIN   date_dim     d ON d.date_key     = p.trans_date_key
    WHERE  c.customer_key <> -1
    AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
    GROUP  BY c.membership_type
), rev AS (
    SELECT c.membership_type,
           SUM(s.net_sales_amt) AS net_sales
    FROM   sales_fact   s
    JOIN   customer_dim c ON c.customer_key = s.customer_key
    JOIN   date_dim     d ON d.date_key     = s.order_date_key
    WHERE  c.customer_key <> -1
    AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
    GROUP  BY c.membership_type
)
SELECT f.membership_type                        AS "Tier",
       f.current_members                        AS "Current Members",
       f.earn_rate_per_rm                       AS "Earn Rate per RM",
       ROUND(f.annual_fee_revenue, 2)           AS "Annual Fee Revenue",
       NVL(p.points_earned, 0)                  AS "Points Earned",
       NVL(p.points_redeemed, 0)                AS "Points Redeemed",
       NVL(p.points_earned, 0) - NVL(p.points_redeemed, 0)
                                                AS "Points Outstanding",
       ROUND(NVL(p.points_earned, 0) / NULLIF(r.net_sales, 0), 2)
                                                AS "Points per RM Sold"
FROM   fee f
LEFT   JOIN pts p ON p.membership_type = f.membership_type
LEFT   JOIN rev r ON r.membership_type = f.membership_type
ORDER  BY "Annual Fee Revenue" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c1_3  Revenue by tier by year            CHART: stacked column
--        Long format on purpose - Year on the axis, Tier in the legend.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c1_3_revenue_by_tier_year.csv"
SELECT d.cal_year                        AS "Year",
       c.membership_type                 AS "Tier",
       COUNT(DISTINCT s.order_no)        AS "Orders",
       ROUND(SUM(s.net_sales_amt), 2)    AS "Net Sales",
       CASE WHEN d.cal_year = 2026 THEN 'Part year to ' || TO_CHAR((SELECT MAX(dd.cal_date) FROM sales_fact ss JOIN date_dim dd ON dd.date_key = ss.order_date_key), 'DD Mon')
            ELSE 'Full year' END         AS "Year Type"
FROM   sales_fact   s
JOIN   customer_dim c ON c.customer_key = s.customer_key
JOIN   date_dim     d ON d.date_key     = s.order_date_key
WHERE  c.customer_key <> -1
AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
GROUP  BY d.cal_year, c.membership_type
ORDER  BY d.cal_year, "Net Sales" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c1_4  Year on year growth by tier        CHART: line (share of year pct)
--        2026 EXCLUDED BY THE QUERY. A part year cannot carry a growth
--        percentage, so it must not reach Power BI at all - a caption is not
--        enough when somebody later drags the measure onto a new visual.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c1_4_tier_yoy.csv"
SELECT cal_year     AS "Year",
       membership   AS "Tier",
       net_sales    AS "Net Sales",
       net_sales - LAG(net_sales) OVER (PARTITION BY membership
                                        ORDER BY cal_year)      AS "Sales Change",
       ROUND(100 * (net_sales - LAG(net_sales) OVER (PARTITION BY membership
                                                     ORDER BY cal_year))
             / NULLIF(LAG(net_sales) OVER (PARTITION BY membership
                                           ORDER BY cal_year), 0), 1)
                                                                AS "YoY Pct",
       ROUND(100 * net_sales / SUM(net_sales) OVER (PARTITION BY cal_year), 1)
                                                                AS "Share of Year Pct"
FROM ( SELECT d.cal_year,
              c.membership_type              AS membership,
              ROUND(SUM(s.net_sales_amt), 2) AS net_sales
       FROM   sales_fact   s
       JOIN   customer_dim c ON c.customer_key = s.customer_key
       JOIN   date_dim     d ON d.date_key     = s.order_date_key
       WHERE  c.customer_key <> -1
       AND    d.cal_year BETWEEN &p_start_yr AND LEAST(&p_end_yr, 2025)
       GROUP  BY d.cal_year, c.membership_type )
ORDER  BY "Tier", "Year";
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c1_5  Tier movement out of the Type 2 dimension    CHART: bar
--        The clearest single piece of evidence that the SCD Type 2
--        requirement in Task 1b actually works.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c1_5_tier_movement.csv"
SELECT movement AS "Movement",
       COUNT(*) AS "Customers",
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS "Pct of Customers"
FROM ( SELECT c.customer_id,
              CASE WHEN COUNT(*) = 1 THEN 'Never changed tier'
                   WHEN MIN(CASE WHEN c.version_no = 1
                                 THEN c.membership_type END) = 'Non-Member'
                    AND MAX(CASE WHEN c.is_current_flag = 'Y'
                                 THEN c.membership_type END) <> 'Non-Member'
                        THEN 'Joined the programme'
                   WHEN MAX(CASE WHEN c.is_current_flag = 'Y'
                                 THEN c.membership_type END) = 'VIP'
                        THEN 'Upgraded to VIP'
                   ELSE 'Other tier change'
              END AS movement
       FROM   customer_dim c
       WHERE  c.customer_key <> -1
       GROUP  BY c.customer_id )
GROUP  BY movement
ORDER  BY "Customers" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c1_6  Basket behaviour by tier   CHART: line and clustered column
--        Column = avg basket, line = discount take pct.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c1_6_basket_by_tier.csv"
SELECT c.membership_type                                       AS "Tier",
       COUNT(DISTINCT s.order_no)                              AS "Orders",
       ROUND(AVG(s.quantity), 2)                               AS "Avg Units per Line",
       ROUND(COUNT(*) / NULLIF(COUNT(DISTINCT s.order_no), 0), 2)
                                                               AS "Lines per Order",
       ROUND(SUM(s.net_sales_amt) / NULLIF(COUNT(DISTINCT s.order_no), 0), 2)
                                                               AS "Avg Basket",
       ROUND(SUM(s.discount_amt), 2)                           AS "Discount Given",
       ROUND(100 * SUM(s.discount_amt) / NULLIF(SUM(s.gross_sales_amt), 0), 2)
                                                               AS "Discount Take Pct"
FROM   sales_fact   s
JOIN   customer_dim c ON c.customer_key = s.customer_key
JOIN   date_dim     d ON d.date_key     = s.order_date_key
WHERE  c.customer_key <> -1
AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
GROUP  BY c.membership_type
ORDER  BY "Avg Basket" DESC;
SPOOL OFF


-- ###########################################################################
--  REPORT 2 - LOYALTY POINTS: EARN, REDEEM AND THE OUTSTANDING LIABILITY
-- ###########################################################################

-- ---------------------------------------------------------------------------
--  c2_1  The standing position              CHART: six Card visuals
--
--        RESHAPED FROM THE REPORT. Exhibit 2.1 is a tall metric/figure list,
--        which reads well as text but is useless to Power BI - a Card wants a
--        numeric column, and "1,234,567" or "12.34 %" is a string. This
--        returns ONE ROW with one bare numeric column per metric, so each
--        Card just picks its own field. Same numbers, different shape.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c2_1_standing_position.csv"
SELECT (SELECT SUM(points_earned)   FROM point_fact WHERE customer_key <> -1)
           AS "Points Issued",
       (SELECT SUM(points_redeemed) FROM point_fact WHERE customer_key <> -1)
           AS "Points Redeemed",
       (SELECT SUM(net_points)      FROM point_fact WHERE customer_key <> -1)
           AS "Outstanding Balance",
       (SELECT ROUND(100 * SUM(points_redeemed) / NULLIF(SUM(points_earned), 0), 2)
        FROM   point_fact WHERE customer_key <> -1)
           AS "Redemption Pct",
       (SELECT COUNT(DISTINCT c.customer_id)
        FROM   point_fact p JOIN customer_dim c ON c.customer_key = p.customer_key
        WHERE  p.customer_key <> -1)
           AS "Members Holding Points",
       (SELECT COUNT(DISTINCT c.customer_id)
        FROM   point_fact p JOIN customer_dim c ON c.customer_key = p.customer_key
        WHERE  p.customer_key <> -1 AND p.trans_type = 'Redeem')
           AS "Members Ever Redeemed",
       (SELECT ROUND(100 *
                 (SELECT COUNT(DISTINCT c.customer_id)
                  FROM   point_fact p JOIN customer_dim c
                         ON c.customer_key = p.customer_key
                  WHERE  p.customer_key <> -1 AND p.trans_type = 'Redeem')
                 / NULLIF((SELECT COUNT(DISTINCT c.customer_id)
                           FROM   point_fact p JOIN customer_dim c
                                  ON c.customer_key = p.customer_key
                           WHERE  p.customer_key <> -1), 0), 1)
        FROM   dual)
           AS "Participation Pct"
FROM   dual;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c2_2  Participation: who has ever taken anything back    CHART: bar
--        A redemption RATE in points can be dragged around by a handful of
--        large redemptions. Participation cannot.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c2_2_participation.csv"
WITH holders AS (
    SELECT c.customer_id,
           MAX(c.membership_type) KEEP (DENSE_RANK LAST ORDER BY c.version_no)
               AS membership,
           SUM(p.points_earned)   AS earned,
           SUM(p.points_redeemed) AS redeemed
    FROM   point_fact   p
    JOIN   customer_dim c ON c.customer_key = p.customer_key
    WHERE  p.customer_key <> -1
    GROUP  BY c.customer_id
)
SELECT membership                                      AS "Tier",
       COUNT(*)                                        AS "Point Holders",
       SUM(CASE WHEN redeemed > 0 THEN 1 ELSE 0 END)   AS "Ever Redeemed",
       ROUND(100 * SUM(CASE WHEN redeemed > 0 THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0), 1)                 AS "Participation Pct",
       ROUND(AVG(earned))                              AS "Avg Points Earned",
       ROUND(AVG(earned - redeemed))                   AS "Avg Balance Held",
       MAX(earned - redeemed)                          AS "Largest Balance"
FROM   holders
GROUP  BY membership
ORDER  BY "Participation Pct" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c2_3  Where the liability sits           CHART: clustered bar
--        Plot Member Share Pct against Liability Share Pct. The GAP between
--        the two bars is the entire point: VIP earns at 2.00 per ringgit
--        against Normal's 1.00, so it should hold a share of the liability
--        well above its share of the membership.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c2_3_liability_by_tier.csv"
WITH tier_pts AS (
    SELECT c.membership_type,
           COUNT(DISTINCT c.customer_id) AS members,
           SUM(p.points_earned)          AS earned,
           SUM(p.points_redeemed)        AS redeemed,
           SUM(p.net_points)             AS balance
    FROM   point_fact   p
    JOIN   customer_dim c ON c.customer_key = p.customer_key
    WHERE  p.customer_key <> -1
    GROUP  BY c.membership_type
)
SELECT membership_type                                  AS "Tier",
       members                                          AS "Members",
       ROUND(100 * members / SUM(members) OVER (), 1)   AS "Member Share Pct",
       earned                                           AS "Points Earned",
       redeemed                                         AS "Points Redeemed",
       balance                                          AS "Balance",
       ROUND(100 * balance / NULLIF(SUM(balance) OVER (), 0), 1)
                                                        AS "Liability Share Pct",
       ROUND(100 * redeemed / NULLIF(earned, 0), 2)     AS "Redemption Pct"
FROM   tier_pts
ORDER  BY "Balance" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c2_4  Monthly earn against redeem   CHART: line and clustered column
--        Columns = earned and redeemed, LINE = cumulative balance.
--
--        RESTRICTED WINDOW, AND HERE IS WHY. In this source a member holds at
--        most one redemption, dated at their most recent earn, so redemptions
--        bunch toward the end of each member's life rather than spreading
--        across the decade. Charted from 2016 the series shows a generator
--        artefact. From the all-branches era the monthly shape is honest.
--
--        Year and Month No are exported so the Month axis can be given a
--        Sort-by column in Power BI instead of trusting text order.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c2_4_monthly_points.csv"
SELECT d.cal_year_month        AS "Month",
       d.cal_year              AS "Year",
       d.cal_month_year        AS "Month No",
       SUM(p.points_earned)    AS "Points Earned",
       SUM(p.points_redeemed)  AS "Points Redeemed",
       SUM(p.net_points)       AS "Net Points",
       ROUND(100 * SUM(p.points_redeemed) / NULLIF(SUM(p.points_earned), 0), 2)
                               AS "Redemption Pct",
       SUM(SUM(p.net_points)) OVER (ORDER BY d.cal_year_month
                                    ROWS UNBOUNDED PRECEDING)
                               AS "Cumulative Balance"
FROM   point_fact p
JOIN   date_dim   d ON d.date_key = p.trans_date_key
WHERE  p.customer_key <> -1
AND    d.cal_year >= &p_era_yr
GROUP  BY d.cal_year_month, d.cal_year, d.cal_month_year
ORDER  BY d.cal_year_month;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c2_5  What a point costs to issue        CHART: line
--        Read the RATIO, not the volume - 2026 is a part year and is flagged
--        in its own column so a caption can be driven off it.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c2_5_points_per_rm.csv"
WITH earned AS (
    SELECT d.cal_year, SUM(p.points_earned) AS points_earned
    FROM   point_fact p JOIN date_dim d ON d.date_key = p.trans_date_key
    WHERE  p.customer_key <> -1
    GROUP  BY d.cal_year
), sold AS (
    SELECT d.cal_year, SUM(s.net_sales_amt) AS net_sales
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
    WHERE  s.customer_key <> -1
    GROUP  BY d.cal_year
)
SELECT s.cal_year                    AS "Year",
       ROUND(s.net_sales, 2)         AS "Net Sales",
       NVL(e.points_earned, 0)       AS "Points Earned",
       ROUND(NVL(e.points_earned, 0) / NULLIF(s.net_sales, 0), 3)
                                     AS "Points per RM",
       CASE WHEN s.cal_year = 2026 THEN 'Part year to ' || TO_CHAR((SELECT MAX(dd.cal_date) FROM sales_fact ss JOIN date_dim dd ON dd.date_key = ss.order_date_key), 'DD Mon')
            ELSE 'Full year' END     AS "Year Type"
FROM   sold s
LEFT   JOIN earned e ON e.cal_year = s.cal_year
WHERE  s.cal_year BETWEEN &p_start_yr AND &p_end_yr
ORDER  BY "Year";
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c2_6  Size of the balances being carried  CHART: clustered bar
--        Plot Pct of Members against Pct of Liability. An expiry policy or a
--        voucher sweep only pays for itself if the two diverge.
--        The '1.' to '5.' prefixes are LOAD-BEARING - they are what makes
--        Power BI sort the bands in order rather than alphabetically.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c2_6_balance_bands.csv"
WITH bal AS (
    SELECT c.customer_id, SUM(p.net_points) AS balance
    FROM   point_fact   p
    JOIN   customer_dim c ON c.customer_key = p.customer_key
    WHERE  p.customer_key <> -1
    GROUP  BY c.customer_id
)
SELECT band                                          AS "Balance Band",
       members                                       AS "Members",
       ROUND(100 * members / SUM(members) OVER (), 1) AS "Pct of Members",
       total_points                                  AS "Total Points",
       ROUND(100 * total_points / NULLIF(SUM(total_points) OVER (), 0), 1)
                                                     AS "Pct of Liability"
FROM ( SELECT CASE WHEN balance <  100 THEN '1. Under 100'
                   WHEN balance <  400 THEN '2. 100 to 399'
                   WHEN balance < 1000 THEN '3. 400 to 999'
                   WHEN balance < 2500 THEN '4. 1,000 to 2,499'
                   ELSE                     '5. 2,500 and over'
              END              AS band,
              COUNT(*)         AS members,
              SUM(balance)     AS total_points
       FROM   bal
       GROUP  BY CASE WHEN balance <  100 THEN '1. Under 100'
                      WHEN balance <  400 THEN '2. 100 to 399'
                      WHEN balance < 1000 THEN '3. 400 to 999'
                      WHEN balance < 2500 THEN '4. 1,000 to 2,499'
                      ELSE                     '5. 2,500 and over'
                 END )
ORDER  BY "Balance Band";
SPOOL OFF


-- ###########################################################################
--  REPORT 3 - CUSTOMER RETENTION AND DORMANCY BY STATE
--
--  Two definitions this report commits to, both choices rather than facts:
--  (a) a customer's STATE is the state of the branch they LAST shopped at;
--  (b) the AS-AT DATE is the latest order date in the warehouse, not SYSDATE,
--      so the report reproduces when re-run on a rebuilt database.
--  Population restricted to the all-branches era.
-- ###########################################################################

-- ---------------------------------------------------------------------------
--  c3_1  Retention and dormancy by state
--        CHART: line and clustered column. Column = Dormancy Pct by state,
--        LINE = National Dormancy Pct, which is flat and acts as the
--        reference line.
--
--        DO NOT USE THE ANALYTICS PANE'S "AVERAGE LINE" INSTEAD. It averages
--        the twelve plotted state percentages, which is an unweighted mean
--        and is NOT the national rate - a state with 40 customers would pull
--        it as hard as one with 400. The correct figure is computed below
--        over the same population and carried on every row.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c3_1_state_retention.csv"
WITH bounds AS (
    SELECT MAX(d.cal_date) AS as_of
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
), cust_last AS (
    SELECT c.customer_id,
           MAX(d.cal_date) AS last_order_date
    FROM   sales_fact   s
    JOIN   customer_dim c ON c.customer_key = s.customer_key
    JOIN   date_dim     d ON d.date_key     = s.order_date_key
    WHERE  c.customer_key <> -1
    AND    d.cal_year >= &p_era_yr
    GROUP  BY c.customer_id
), cust_state AS (
    SELECT customer_id, branch_state, branch_city
    FROM ( SELECT c.customer_id, b.branch_state, b.branch_city,
                  ROW_NUMBER() OVER (PARTITION BY c.customer_id
                                     ORDER BY s.order_date_key DESC) AS rn
           FROM   sales_fact   s
           JOIN   customer_dim c ON c.customer_key = s.customer_key
           JOIN   branch_dim   b ON b.branch_key   = s.branch_key
           JOIN   date_dim     d ON d.date_key     = s.order_date_key
           WHERE  c.customer_key <> -1
           AND    b.branch_key   <> -1
           AND    d.cal_year >= &p_era_yr )
    WHERE  rn = 1
), nat AS (
    -- The national rate over EXACTLY the population the states are drawn
    -- from, so the reference line and the columns are commensurable.
    SELECT ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of,
                                       cl.last_order_date) > 6
                                THEN 1 ELSE 0 END) / COUNT(*), 1)
               AS national_dormancy_pct,
           ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of,
                                       cl.last_order_date) <= 6
                                THEN 1 ELSE 0 END) / COUNT(*), 1)
               AS national_retention_pct
    FROM   cust_last  cl
    JOIN   cust_state cs ON cs.customer_id = cl.customer_id
    CROSS  JOIN bounds bo
)
SELECT cs.branch_state                     AS "State",
       COUNT(*)                            AS "Base Customers",
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                THEN 1 ELSE 0 END)         AS "Active",
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) >  6
                THEN 1 ELSE 0 END)         AS "Dormant",
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1)
                                           AS "Retention Pct",
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) >  6
                            THEN 1 ELSE 0 END) / COUNT(*), 1)
                                           AS "Dormancy Pct",
       n.national_dormancy_pct             AS "National Dormancy Pct",
       n.national_retention_pct            AS "National Retention Pct",
       ROUND(AVG(MONTHS_BETWEEN(bo.as_of, cl.last_order_date)), 1)
                                           AS "Avg Months Since",
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)
                                           AS "State Share Pct"
FROM   cust_last  cl
JOIN   cust_state cs ON cs.customer_id = cl.customer_id
CROSS  JOIN bounds bo
CROSS  JOIN nat    n
GROUP  BY cs.branch_state, n.national_dormancy_pct, n.national_retention_pct
ORDER  BY "Dormancy Pct" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c3_2  Down to city, so the campaign has an address   CHART: matrix
--        NO BREAK, NO COMPUTE - see rule 2 in the header. Let Power BI's
--        matrix compute the state subtotals from the city rows instead.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c3_2_city_dormancy.csv"
WITH bounds AS (
    SELECT MAX(d.cal_date) AS as_of
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
), cust_last AS (
    SELECT c.customer_id, MAX(d.cal_date) AS last_order_date
    FROM   sales_fact   s
    JOIN   customer_dim c ON c.customer_key = s.customer_key
    JOIN   date_dim     d ON d.date_key     = s.order_date_key
    WHERE  c.customer_key <> -1 AND d.cal_year >= &p_era_yr
    GROUP  BY c.customer_id
), cust_state AS (
    SELECT customer_id, branch_state, branch_city
    FROM ( SELECT c.customer_id, b.branch_state, b.branch_city,
                  ROW_NUMBER() OVER (PARTITION BY c.customer_id
                                     ORDER BY s.order_date_key DESC) AS rn
           FROM   sales_fact   s
           JOIN   customer_dim c ON c.customer_key = s.customer_key
           JOIN   branch_dim   b ON b.branch_key   = s.branch_key
           JOIN   date_dim     d ON d.date_key     = s.order_date_key
           WHERE  c.customer_key <> -1 AND b.branch_key <> -1
           AND    d.cal_year >= &p_era_yr )
    WHERE  rn = 1
)
SELECT cs.branch_state           AS "State",
       cs.branch_city            AS "City",
       COUNT(*)                  AS "Base Customers",
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) > 6
                THEN 1 ELSE 0 END) AS "Dormant",
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) > 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1)
                                 AS "Dormancy Pct",
       ROUND(AVG(MONTHS_BETWEEN(bo.as_of, cl.last_order_date)), 1)
                                 AS "Avg Months Since"
FROM   cust_last  cl
JOIN   cust_state cs ON cs.customer_id = cl.customer_id
CROSS  JOIN bounds bo
GROUP  BY cs.branch_state, cs.branch_city
ORDER  BY cs.branch_state, "Dormancy Pct" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c3_3  Active customers by month          CHART: line
--        A TRADING base, not a registration count - a customer who registered
--        and never shopped again is correctly absent.
--        Year and Month No exported for the Sort-by column.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c3_3_active_by_month.csv"
SELECT d.cal_year_month              AS "Month",
       d.cal_year                    AS "Year",
       d.cal_month_year              AS "Month No",
       COUNT(DISTINCT c.customer_id) AS "Active Customers",
       COUNT(DISTINCT s.order_no)    AS "Orders",
       ROUND(SUM(s.net_sales_amt), 2) AS "Net Sales",
       ROUND(COUNT(DISTINCT s.order_no)
             / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2)
                                     AS "Orders per Active"
FROM   sales_fact   s
JOIN   customer_dim c ON c.customer_key = s.customer_key
JOIN   date_dim     d ON d.date_key     = s.order_date_key
WHERE  c.customer_key <> -1
AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
GROUP  BY d.cal_year_month, d.cal_year, d.cal_month_year
ORDER  BY d.cal_year_month;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c3_4  Does the membership programme actually retain    CHART: bar
--        THE PAYOFF EXHIBIT. Report 1 asks whether VIP SPENDS more; this asks
--        whether VIP STAYS. A tier that spends more but churns at the same
--        rate is buying revenue, not loyalty.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c3_4_retention_by_tier.csv"
WITH bounds AS (
    SELECT MAX(d.cal_date) AS as_of
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
), cust_last AS (
    SELECT c.customer_id,
           MAX(d.cal_date) AS last_order_date,
           MAX(c.membership_type) KEEP (DENSE_RANK LAST ORDER BY c.version_no)
               AS membership
    FROM   sales_fact   s
    JOIN   customer_dim c ON c.customer_key = s.customer_key
    JOIN   date_dim     d ON d.date_key     = s.order_date_key
    WHERE  c.customer_key <> -1 AND d.cal_year >= &p_era_yr
    GROUP  BY c.customer_id
)
SELECT cl.membership       AS "Tier",
       COUNT(*)            AS "Base Customers",
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                THEN 1 ELSE 0 END) AS "Active",
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1)
                           AS "Retention Pct",
       ROUND(AVG(MONTHS_BETWEEN(bo.as_of, cl.last_order_date)), 1)
                           AS "Avg Months Since"
FROM   cust_last cl
CROSS  JOIN bounds bo
GROUP  BY cl.membership
ORDER  BY "Retention Pct" DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c3_5  Recency bands: how far gone is the dormant base   CHART: column
--        A customer three months quiet needs a nudge; one two years quiet
--        needs a reacquisition offer or writing off.
--        The '1.' to '5.' prefixes force the band order - keep them.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c3_5_recency_bands.csv"
WITH bounds AS (
    SELECT MAX(d.cal_date) AS as_of
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
), cust_last AS (
    SELECT c.customer_id, MAX(d.cal_date) AS last_order_date
    FROM   sales_fact   s
    JOIN   customer_dim c ON c.customer_key = s.customer_key
    JOIN   date_dim     d ON d.date_key     = s.order_date_key
    WHERE  c.customer_key <> -1 AND d.cal_year >= &p_era_yr
    GROUP  BY c.customer_id
), banded AS (
    SELECT CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <=  3
                     THEN '1. 0 to 3 months'
                WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <=  6
                     THEN '2. 3 to 6 months'
                WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 12
                     THEN '3. 6 to 12 months'
                WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 24
                     THEN '4. 12 to 24 months'
                ELSE '5. Over 24 months'
           END AS recency_band
    FROM   cust_last cl CROSS JOIN bounds bo
)
SELECT recency_band                                     AS "Recency Band",
       COUNT(*)                                         AS "Customers",
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS "Pct of Base",
       SUM(COUNT(*)) OVER (ORDER BY recency_band ROWS UNBOUNDED PRECEDING)
                                                        AS "Cumulative Customers"
FROM   banded
GROUP  BY recency_band
ORDER  BY "Recency Band";
SPOOL OFF


-- ---------------------------------------------------------------------------
--  c3_6  Acquisition cohorts: do newer customers stick
--        CHART: line and clustered column. Column = Customers Acquired,
--        LINE = Still Active Pct.
--        Cohort year is the year of the customer's FIRST EVER order, so this
--        one is deliberately NOT restricted to the all-branches era - a
--        cohort is defined by when it was acquired.
-- ---------------------------------------------------------------------------
SPOOL "&csv_dir\c3_6_cohorts.csv"
WITH bounds AS (
    SELECT MAX(d.cal_date) AS as_of
    FROM   sales_fact s JOIN date_dim d ON d.date_key = s.order_date_key
), cust_life AS (
    SELECT c.customer_id,
           MIN(d.cal_year) AS cohort_year,
           MAX(d.cal_date) AS last_order_date,
           COUNT(DISTINCT s.order_no) AS lifetime_orders,
           SUM(s.net_sales_amt)       AS lifetime_sales
    FROM   sales_fact   s
    JOIN   customer_dim c ON c.customer_key = s.customer_key
    JOIN   date_dim     d ON d.date_key     = s.order_date_key
    WHERE  c.customer_key <> -1
    GROUP  BY c.customer_id
)
SELECT cl.cohort_year AS "Cohort Year",
       COUNT(*)       AS "Customers Acquired",
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                THEN 1 ELSE 0 END) AS "Still Active",
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1)
                      AS "Still Active Pct",
       ROUND(AVG(cl.lifetime_orders), 1) AS "Avg Lifetime Orders",
       ROUND(AVG(cl.lifetime_sales), 2)  AS "Avg Lifetime Sales"
FROM   cust_life cl
CROSS  JOIN bounds bo
GROUP  BY cl.cohort_year
ORDER  BY "Cohort Year";
SPOOL OFF


-- ---------------------------------------------------------------------------
--  Restore everything task3_yv_reports.sql expects, so the two scripts can be
--  run back to back in one SQL*Plus session.
-- ---------------------------------------------------------------------------
SET MARKUP CSV OFF
SET TERMOUT  ON
SET HEADING  ON
SET PAGESIZE 400
SET LINESIZE 200
SET FEEDBACK ON
SET VERIFY   ON

PROMPT
PROMPT ============================================================================
PROMPT   Done. Eighteen CSV files written to:  &csv_dir
PROMPT
PROMPT   NEXT: verify, then chart.
PROMPT     1. Check all eighteen exist and none is empty.
PROMPT     2. Check none contains "State total" or "rows selected".
PROMPT     3. Open Power BI Desktop and follow POWERBI_GUIDE.md in
PROMPT        "Task 3\Yong Vay\".
PROMPT
PROMPT   Re-run this script after every ETL reload. Nothing in Power BI will
PROMPT   tell you the CSVs have gone stale.
PROMPT ============================================================================
PROMPT

UNDEFINE csv_dir
UNDEFINE p_start_yr
UNDEFINE p_end_yr
UNDEFINE p_era_yr
