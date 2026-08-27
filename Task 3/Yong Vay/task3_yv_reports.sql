-- ============================================================================
--  Task 3 - Business Analytics Queries        STUDENT: YV
--  Domain C : Customer, Membership and Loyalty
--  RUN AS THE DW USER
--
--      SQL> SPOOL "Task 3 output\Yong Vay\task3_output.txt"
--      SQL> @"Task 3\Yong Vay\task3_yv_reports.sql"
--      SQL> SPOOL OFF
--
--  TO EXPORT ONE EXHIBIT FOR CHARTING (Oracle 12.2 and later):
--      SQL> SET MARKUP CSV ON
--      SQL> SPOOL c1_1.csv
--      ... run just the exhibit you want ...
--      SQL> SPOOL OFF
--      SQL> SET MARKUP CSV OFF
--
--  ......................................................................
--  FOUR STANDING RULES, APPLIED THROUGHOUT
--
--  1. 2026 IS A PART YEAR.  It covers January to August only.  No YoY or
--     growth column includes it, because a part year charted against a
--     whole one reads as a collapse that did not happen.  Level tables
--     show it and say so.
--
--  2. CUSTOMER_DIM IS TYPE 2.  A customer who upgraded Normal -> VIP owns
--     more than one customer_key.  Joining sales_fact straight through the
--     surrogate key is therefore CORRECT for revenue - each order is
--     attributed to the tier in force on the day it was placed.  But every
--     HEADCOUNT in this file uses COUNT(DISTINCT customer_id), never
--     customer_key, or an upgrader would be counted twice.
--
--  3. REDEMPTIONS ARE SPARSE AND LATE-CLUSTERED.  In the source, a member
--     holds at most one redemption and it is dated at their most recent
--     earn.  A monthly earn-versus-redeem line across the whole decade
--     would therefore show a generator artefact, not a business trend.
--     Report 2 leads with the STANDING LIABILITY, which needs no time
--     series, and confines its monthly series to 2024-2026.
--
--  4. BRANCH ROLLOUT CONFOUNDS ANY CROSS-STATE COMPARISON.  Four branches
--     traded in 2016; all twelve only from 2023.  A state whose branches
--     opened late has a structurally younger customer base and will look
--     artificially well-retained.  Report 3 restricts its population to
--     the all-branches era (default 2024 onward).
--
--  A NOTE ON POINT VALUATION.  The schema records points, not the ringgit
--  value of a point - there is no reward catalogue table.  Report 2
--  therefore quantifies the liability in POINTS and states the earn rates
--  (Normal 1.00/RM, VIP 2.00/RM) rather than inventing a conversion.
--  ......................................................................
-- ============================================================================
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 400
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMSPOOL ON

COLUMN membership      FORMAT A14
COLUMN membership_type FORMAT A14
COLUMN branch_state    FORMAT A20
COLUMN branch_city     FORMAT A20
COLUMN cal_year_month  FORMAT A9
COLUMN recency_band    FORMAT A22
COLUMN metric          FORMAT A46
COLUMN figure          FORMAT A18
COLUMN verdict         FORMAT A22
COLUMN movement        FORMAT A26
COLUMN band            FORMAT A20

-- Flexible reporting window.  Press ENTER at each prompt to take the default.
ACCEPT p_start_yr NUMBER DEFAULT 2016 PROMPT 'Report START year (default 2016): '
ACCEPT p_end_yr   NUMBER DEFAULT 2026 PROMPT 'Report END year   (default 2026): '
ACCEPT p_era_yr   NUMBER DEFAULT 2024 PROMPT 'All-branches era begins (default 2024): '


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 1 - MEMBERSHIP TIER ECONOMICS: DOES VIP EARN ITS KEEP
PROMPT   Dimensions: customer_dim (membership_type) x date_dim (year)
PROMPT   Measures  : orders, net revenue, basket value, spend per customer,
PROMPT               annual fee revenue, points accrued
PROMPT
PROMPT   THE QUESTION: VIP costs the member RM12 a year and costs the company
PROMPT   a doubled point-earn rate. Report 1 asks whether the extra spend a
PROMPT   VIP brings is large enough to cover what the tier gives away.
PROMPT ============================================================================

PROMPT
PROMPT --- EXHIBIT 1.1  Tier value scorecard  [CHART: grouped column] ===
PROMPT WHAT: the headline. Spend per customer is the column that decides the
PROMPT question - average order value alone hides how OFTEN each tier shops.
PROMPT Headcount is DISTINCT customer_id, so tier upgraders are counted once.
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
SELECT membership_type,
       customers,
       orders,
       ROUND(orders / NULLIF(customers, 0), 2)     AS orders_per_cust,
       ROUND(net_sales)                            AS net_sales,
       ROUND(100 * net_sales / SUM(net_sales) OVER (), 1) AS sales_share_pct,
       ROUND(net_sales / NULLIF(orders, 0), 2)     AS avg_order_value,
       ROUND(net_sales / NULLIF(customers, 0), 2)  AS spend_per_cust,
       RANK() OVER (ORDER BY net_sales / NULLIF(customers, 0) DESC) AS value_rank
FROM   tier_sales
ORDER  BY spend_per_cust DESC;

PROMPT
PROMPT --- EXHIBIT 1.2  What the tier costs, against what it collects ===
PROMPT WHY IT MATTERS: fee revenue is the only DIRECT income the tier earns.
PROMPT Points accrued are the direct cost, and VIP accrues at twice the rate
PROMPT per ringgit spent. If VIP fee income is trivial next to the point
PROMPT overhang, the tier has to justify itself on incremental spend alone.
PROMPT Fee revenue counts CURRENT member versions only, so a lapsed
PROMPT membership is not still billed.
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
SELECT f.membership_type,
       f.current_members,
       f.earn_rate_per_rm,
       ROUND(f.annual_fee_revenue, 2)          AS annual_fee_revenue,
       NVL(p.points_earned, 0)                 AS points_earned,
       NVL(p.points_redeemed, 0)               AS points_redeemed,
       NVL(p.points_earned, 0) - NVL(p.points_redeemed, 0) AS points_outstanding,
       ROUND(NVL(p.points_earned, 0) / NULLIF(r.net_sales, 0), 2)
           AS points_per_rm_sold
FROM   fee f
LEFT   JOIN pts p ON p.membership_type = f.membership_type
LEFT   JOIN rev r ON r.membership_type = f.membership_type
ORDER  BY f.annual_fee_revenue DESC;

PROMPT
PROMPT --- EXHIBIT 1.3  Revenue by tier by year  [CHART: stacked column] ===
PROMPT Long format on purpose - this is the shape a stacked chart wants.
PROMPT Because customer_dim is Type 2, a customer who upgraded mid-decade
PROMPT appears under Normal in the early years and VIP in the later ones.
PROMPT That is the Type 2 dimension doing real work, not a data error.
SELECT d.cal_year,
       c.membership_type AS membership,
       COUNT(DISTINCT s.order_no)  AS orders,
       ROUND(SUM(s.net_sales_amt)) AS net_sales
FROM   sales_fact   s
JOIN   customer_dim c ON c.customer_key = s.customer_key
JOIN   date_dim     d ON d.date_key     = s.order_date_key
WHERE  c.customer_key <> -1
AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
GROUP  BY d.cal_year, c.membership_type
ORDER  BY d.cal_year, net_sales DESC;

PROMPT
PROMPT --- EXHIBIT 1.4  Year on year growth by tier ===
PROMPT 2026 EXCLUDED: a part year cannot carry a growth percentage.
PROMPT WHAT TO LOOK FOR: a tier whose share is rising is winning the mix even
PROMPT if every tier is growing in absolute terms.
SELECT cal_year,
       membership,
       net_sales,
       net_sales - LAG(net_sales) OVER (PARTITION BY membership ORDER BY cal_year)
           AS sales_change,
       ROUND(100 * (net_sales - LAG(net_sales) OVER (PARTITION BY membership
                                                     ORDER BY cal_year))
             / NULLIF(LAG(net_sales) OVER (PARTITION BY membership
                                           ORDER BY cal_year), 0), 1) AS yoy_pct,
       ROUND(100 * net_sales / SUM(net_sales) OVER (PARTITION BY cal_year), 1)
           AS share_of_year_pct
FROM ( SELECT d.cal_year,
              c.membership_type           AS membership,
              ROUND(SUM(s.net_sales_amt)) AS net_sales
       FROM   sales_fact   s
       JOIN   customer_dim c ON c.customer_key = s.customer_key
       JOIN   date_dim     d ON d.date_key     = s.order_date_key
       WHERE  c.customer_key <> -1
       AND    d.cal_year BETWEEN &p_start_yr AND LEAST(&p_end_yr, 2025)
       GROUP  BY d.cal_year, c.membership_type )
ORDER  BY membership, cal_year;

PROMPT
PROMPT --- EXHIBIT 1.5  Tier movement, straight out of the Type 2 dimension ===
PROMPT HOW: a customer with more than one version row has changed tier at
PROMPT least once. version_no and the effective dates record exactly when.
PROMPT This exhibit exists because it is the clearest single piece of
PROMPT evidence that the SCD Type 2 requirement in Task 1b actually works.
SELECT movement,
       COUNT(*) AS customers
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
ORDER  BY customers DESC;

PROMPT
PROMPT --- EXHIBIT 1.6  Basket behaviour by tier ===
PROMPT SO WHAT: separates the two ways a tier can be worth more - bigger
PROMPT baskets, or more frequent visits. The fix differs. A tier that buys
PROMPT big but rarely needs a frequency campaign; one that visits often for
PROMPT little needs basket-building at the till.
SELECT c.membership_type AS membership,
       COUNT(DISTINCT s.order_no)                          AS orders,
       ROUND(AVG(s.quantity), 2)                           AS avg_units_per_line,
       ROUND(COUNT(*) / NULLIF(COUNT(DISTINCT s.order_no), 0), 2)
           AS lines_per_order,
       ROUND(SUM(s.net_sales_amt) / NULLIF(COUNT(DISTINCT s.order_no), 0), 2)
           AS avg_basket,
       ROUND(SUM(s.discount_amt))                          AS discount_given,
       ROUND(100 * SUM(s.discount_amt) / NULLIF(SUM(s.gross_sales_amt), 0), 2)
           AS discount_take_pct
FROM   sales_fact   s
JOIN   customer_dim c ON c.customer_key = s.customer_key
JOIN   date_dim     d ON d.date_key     = s.order_date_key
WHERE  c.customer_key <> -1
AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
GROUP  BY c.membership_type
ORDER  BY avg_basket DESC;


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 2 - LOYALTY POINTS: EARN, REDEEM AND THE OUTSTANDING LIABILITY
PROMPT   Dimensions: customer_dim (membership_type) x date_dim (year, month)
PROMPT   Measures  : points earned, points redeemed, net points, redemption
PROMPT               rate, participation, cumulative balance
PROMPT
PROMPT   FRAMING: this is a LIABILITY and PARTICIPATION report, not a trend
PROMPT   report. See standing rule 3 - redemptions in this source are sparse
PROMPT   and late-clustered, so the decade-long monthly series would describe
PROMPT   the data generator rather than the business. Exhibits 2.1 to 2.3 and
PROMPT   2.5 need no time axis at all; 2.4 carries one and is restricted.
PROMPT
PROMPT   Redeem rows carry no order and therefore no branch - they land on
PROMPT   branch_key = -1. Nothing in this report groups points by branch.
PROMPT ============================================================================

PROMPT
PROMPT --- EXHIBIT 2.1  The standing position ===
PROMPT WHAT: the headline liability. Every point ever issued, every point
PROMPT ever taken back, and the gap the company still owes its members.
SELECT metric, figure
FROM ( SELECT 'Points issued (Earn)'                       AS metric,
              TO_CHAR(SUM(points_earned), '999G999G999')   AS figure,
              1 AS ord
       FROM   point_fact WHERE customer_key <> -1
       UNION ALL
       SELECT 'Points returned (Redeem)',
              TO_CHAR(SUM(points_redeemed), '999G999G999'), 2
       FROM   point_fact WHERE customer_key <> -1
       UNION ALL
       SELECT 'Outstanding balance (unfunded liability)',
              TO_CHAR(SUM(net_points), '999G999G999'), 3
       FROM   point_fact WHERE customer_key <> -1
       UNION ALL
       SELECT 'Redemption rate, points redeemed over issued',
              TO_CHAR(ROUND(100 * SUM(points_redeemed)
                    / NULLIF(SUM(points_earned), 0), 2), '990D00') || ' %', 4
       FROM   point_fact WHERE customer_key <> -1
       UNION ALL
       SELECT 'Members holding points',
              TO_CHAR(COUNT(DISTINCT c.customer_id), '999G999'), 5
       FROM   point_fact p JOIN customer_dim c ON c.customer_key = p.customer_key
       WHERE  p.customer_key <> -1
       UNION ALL
       SELECT 'Members who have EVER redeemed',
              TO_CHAR(COUNT(DISTINCT c.customer_id), '999G999'), 6
       FROM   point_fact p JOIN customer_dim c ON c.customer_key = p.customer_key
       WHERE  p.customer_key <> -1 AND p.trans_type = 'Redeem' )
ORDER  BY ord;

PROMPT
PROMPT --- EXHIBIT 2.2  Participation: who has ever taken anything back ===
PROMPT THE KEY EXHIBIT. A redemption RATE measured in points can be dragged
PROMPT around by a handful of large redemptions. Participation - the share of
PROMPT point-holding members who have ever redeemed even once - cannot. If
PROMPT participation is low while balances rise, the reward catalogue is the
PROMPT problem, not the earn rate.
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
SELECT membership,
       COUNT(*)                                        AS point_holders,
       SUM(CASE WHEN redeemed > 0 THEN 1 ELSE 0 END)   AS ever_redeemed,
       ROUND(100 * SUM(CASE WHEN redeemed > 0 THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0), 1)                 AS participation_pct,
       ROUND(AVG(earned))                              AS avg_points_earned,
       ROUND(AVG(earned - redeemed))                   AS avg_balance_held,
       MAX(earned - redeemed)                          AS largest_balance
FROM   holders
GROUP  BY membership
ORDER  BY participation_pct DESC;

PROMPT
PROMPT --- EXHIBIT 2.3  Where the liability sits  [CHART: stacked bar] ===
PROMPT WHY: VIP earns at 2.00 points per ringgit against Normal at 1.00, so
PROMPT VIP should hold a share of the liability well above its share of the
PROMPT membership. Quantifying that gap is what turns Report 1's repricing
PROMPT question into a number.
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
SELECT membership_type,
       members,
       ROUND(100 * members / SUM(members) OVER (), 1)   AS member_share_pct,
       earned,
       redeemed,
       balance,
       ROUND(100 * balance / NULLIF(SUM(balance) OVER (), 0), 1)
           AS liability_share_pct,
       ROUND(100 * redeemed / NULLIF(earned, 0), 2)     AS redemption_pct
FROM   tier_pts
ORDER  BY balance DESC;

PROMPT
PROMPT --- EXHIBIT 2.4  Monthly earn against redeem  [CHART: column plus line] ===
PROMPT RESTRICTED WINDOW, AND HERE IS WHY. In the source a member holds at
PROMPT most one redemption, dated at their most recent earn, so redemptions
PROMPT bunch toward the end of each member's life rather than spreading
PROMPT across the decade. Charted from 2016 the series would show a generator
PROMPT artefact. From the all-branches era onward the monthly shape is
PROMPT trustworthy. Read the cumulative balance line, not the redeem bars.
SELECT d.cal_year_month,
       SUM(p.points_earned)   AS points_earned,
       SUM(p.points_redeemed) AS points_redeemed,
       SUM(p.net_points)      AS net_points,
       ROUND(100 * SUM(p.points_redeemed) / NULLIF(SUM(p.points_earned), 0), 2)
           AS redemption_pct,
       SUM(SUM(p.net_points)) OVER (ORDER BY d.cal_year_month
                                    ROWS UNBOUNDED PRECEDING)
           AS cumulative_balance
FROM   point_fact p
JOIN   date_dim   d ON d.date_key = p.trans_date_key
WHERE  p.customer_key <> -1
AND    d.cal_year >= &p_era_yr
GROUP  BY d.cal_year_month
ORDER  BY d.cal_year_month;

PROMPT
PROMPT --- EXHIBIT 2.5  What a point costs to issue ===
PROMPT HOW the programme scales with trade. Points issued per ringgit of net
PROMPT sales should track the tier mix - if it drifts upward year on year
PROMPT without a tier-mix shift behind it, the programme is getting more
PROMPT generous by accident.
PROMPT 2026 shown but flagged: a part year, so read the RATIO not the volume.
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
SELECT s.cal_year,
       ROUND(s.net_sales)          AS net_sales,
       NVL(e.points_earned, 0)     AS points_earned,
       ROUND(NVL(e.points_earned, 0) / NULLIF(s.net_sales, 0), 3)
           AS points_per_rm,
       CASE WHEN s.cal_year = 2026 THEN 'Part year, Jan-Aug'
            ELSE '-' END           AS verdict
FROM   sold s
LEFT   JOIN earned e ON e.cal_year = s.cal_year
WHERE  s.cal_year BETWEEN &p_start_yr AND &p_end_yr
ORDER  BY s.cal_year;

PROMPT
PROMPT --- EXHIBIT 2.6  Size of the balances being carried ===
PROMPT SO WHAT: an expiry policy or a voucher sweep only pays for itself if
PROMPT the balances are concentrated. If most members hold very little, the
PROMPT liability is diffuse and a blanket campaign wastes most of its budget.
WITH bal AS (
    SELECT c.customer_id, SUM(p.net_points) AS balance
    FROM   point_fact   p
    JOIN   customer_dim c ON c.customer_key = p.customer_key
    WHERE  p.customer_key <> -1
    GROUP  BY c.customer_id
)
SELECT band,
       members,
       ROUND(100 * members / SUM(members) OVER (), 1) AS pct_of_members,
       total_points,
       ROUND(100 * total_points / NULLIF(SUM(total_points) OVER (), 0), 1)
           AS pct_of_liability
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
ORDER  BY band;


PROMPT
PROMPT ============================================================================
PROMPT   REPORT 3 - CUSTOMER RETENTION AND DORMANCY BY STATE
PROMPT   Dimensions: branch_dim (state, city) x customer_dim x date_dim
PROMPT   Measures  : active and dormant headcount, retention rate, dormancy
PROMPT               rate, months since last order
PROMPT
PROMPT   TWO DEFINITIONS THIS REPORT COMMITS TO, BOTH DEFENSIBLE, BOTH STATED
PROMPT   BECAUSE THEY ARE CHOICES RATHER THAN FACTS:
PROMPT
PROMPT   (a) A CUSTOMER'S STATE is the state of the branch they LAST shopped
PROMPT       at. customer_dim holds no geography and address_dim only reaches
PROMPT       delivery_fact, so branch is the available proxy. A customer who
PROMPT       moved is attributed to where they shop now, which is the right
PROMPT       answer for a win-back campaign.
PROMPT
PROMPT   (b) THE AS-AT DATE is the latest order date in the warehouse, not
PROMPT       SYSDATE. Anchoring to the data keeps the report reproducible
PROMPT       when it is re-run on a rebuilt database next week.
PROMPT
PROMPT   Population restricted to the all-branches era - see standing rule 4.
PROMPT ============================================================================

PROMPT
PROMPT --- EXHIBIT 3.1  Retention and dormancy by state  [CHART: bar] ===
PROMPT WHAT: where the leakage is. Dormant means no order in the six months
PROMPT to the as-at date. The national average is the reference line the
PROMPT chart needs - a state below it is losing customers faster than the
PROMPT company as a whole, which is the only comparison that justifies
PROMPT spending win-back budget there rather than everywhere.
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
)
SELECT cs.branch_state,
       COUNT(*) AS base_customers,
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                THEN 1 ELSE 0 END) AS active,
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) >  6
                THEN 1 ELSE 0 END) AS dormant,
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1) AS retention_pct,
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) >  6
                            THEN 1 ELSE 0 END) / COUNT(*), 1) AS dormancy_pct,
       ROUND(AVG(MONTHS_BETWEEN(bo.as_of, cl.last_order_date)), 1)
           AS avg_months_since,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS state_share_pct,
       RANK() OVER (ORDER BY SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of,
                                            cl.last_order_date) > 6
                                      THEN 1 ELSE 0 END) / COUNT(*) DESC)
           AS worst_first_rank
FROM   cust_last  cl
JOIN   cust_state cs ON cs.customer_id = cl.customer_id
CROSS  JOIN bounds bo
GROUP  BY cs.branch_state
ORDER  BY dormancy_pct DESC;

PROMPT
PROMPT --- EXHIBIT 3.2  Down to city, so the campaign has an address ===
PROMPT WHERE exactly. A state-level dormancy figure is not actionable; a
PROMPT branch city is. Subtotals per state come from BREAK and COMPUTE.
BREAK ON branch_state SKIP 1
COMPUTE SUM LABEL 'State total' OF base_customers dormant ON branch_state

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
SELECT cs.branch_state,
       cs.branch_city,
       COUNT(*) AS base_customers,
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) > 6
                THEN 1 ELSE 0 END) AS dormant,
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) > 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1) AS dormancy_pct,
       ROUND(AVG(MONTHS_BETWEEN(bo.as_of, cl.last_order_date)), 1)
           AS avg_months_since
FROM   cust_last  cl
JOIN   cust_state cs ON cs.customer_id = cl.customer_id
CROSS  JOIN bounds bo
GROUP  BY cs.branch_state, cs.branch_city
ORDER  BY cs.branch_state, dormancy_pct DESC;

CLEAR BREAKS
CLEAR COMPUTES

PROMPT
PROMPT --- EXHIBIT 3.3  Active customers by month  [CHART: line] ===
PROMPT WHEN the base grew and when it stalled. Counted as customers who
PROMPT placed at least one order in the month, so this is a trading base, not
PROMPT a registration count - a registered customer who never shops again is
PROMPT correctly absent.
SELECT d.cal_year_month,
       COUNT(DISTINCT c.customer_id) AS active_customers,
       COUNT(DISTINCT s.order_no)    AS orders,
       ROUND(SUM(s.net_sales_amt))   AS net_sales,
       ROUND(COUNT(DISTINCT s.order_no)
             / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2) AS orders_per_active
FROM   sales_fact   s
JOIN   customer_dim c ON c.customer_key = s.customer_key
JOIN   date_dim     d ON d.date_key     = s.order_date_key
WHERE  c.customer_key <> -1
AND    d.cal_year BETWEEN &p_start_yr AND &p_end_yr
GROUP  BY d.cal_year_month
ORDER  BY d.cal_year_month;

PROMPT
PROMPT --- EXHIBIT 3.4  Does the membership programme actually retain ===
PROMPT THE PAYOFF EXHIBIT, and the one that closes the loop with Report 1.
PROMPT Report 1 asks whether VIP spends more. This asks whether VIP STAYS.
PROMPT A tier that spends more but churns at the same rate is buying revenue,
PROMPT not loyalty, and the fee cannot be defended on retention grounds.
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
SELECT cl.membership,
       COUNT(*) AS base_customers,
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                THEN 1 ELSE 0 END) AS active,
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1) AS retention_pct,
       ROUND(AVG(MONTHS_BETWEEN(bo.as_of, cl.last_order_date)), 1)
           AS avg_months_since
FROM   cust_last cl
CROSS  JOIN bounds bo
GROUP  BY cl.membership
ORDER  BY retention_pct DESC;

PROMPT
PROMPT --- EXHIBIT 3.5  Recency bands: how far gone is the dormant base ===
PROMPT HOW to spend the budget. A customer three months quiet needs a nudge;
PROMPT one two years quiet needs a reacquisition offer or writing off. The
PROMPT bands price the difference.
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
SELECT recency_band,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_base,
       SUM(COUNT(*)) OVER (ORDER BY recency_band ROWS UNBOUNDED PRECEDING)
           AS cumulative_customers
FROM   banded
GROUP  BY recency_band
ORDER  BY recency_band;

PROMPT
PROMPT --- EXHIBIT 3.6  Acquisition cohorts: do newer customers stick ===
PROMPT WHY the base looks the way it does. Grouping by the year of a
PROMPT customer's FIRST order shows whether retention is a recent problem or
PROMPT a long-standing one, and whether the cohorts acquired during the
PROMPT growth years were ever as loyal as the earlier ones.
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
SELECT cl.cohort_year,
       COUNT(*) AS customers_acquired,
       SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                THEN 1 ELSE 0 END) AS still_active,
       ROUND(100 * SUM(CASE WHEN MONTHS_BETWEEN(bo.as_of, cl.last_order_date) <= 6
                            THEN 1 ELSE 0 END) / COUNT(*), 1) AS still_active_pct,
       ROUND(AVG(cl.lifetime_orders), 1)          AS avg_lifetime_orders,
       ROUND(AVG(cl.lifetime_sales), 2)           AS avg_lifetime_sales
FROM   cust_life cl
CROSS  JOIN bounds bo
GROUP  BY cl.cohort_year
ORDER  BY cl.cohort_year;

PROMPT
PROMPT ============================================================================
PROMPT   END OF REPORTS - STUDENT YV
PROMPT ============================================================================

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE p_start_yr
UNDEFINE p_end_yr
UNDEFINE p_era_yr
SET FEEDBACK ON
SET VERIFY ON
