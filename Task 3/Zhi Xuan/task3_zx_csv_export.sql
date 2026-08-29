-- ============================================================================
--  Task 3 - CSV EXPORT FOR POWER BI            STUDENT: ZX
--  Domain B : Branch and Regional Operations
--  RUN AS THE DW USER
--
--  WHY THIS FILE EXISTS
--  SET MARKUP CSV ON needs SQL*Plus 12.2 or later. On an older client it
--  fails with SP2-0158: unknown SET option "CSV". This script builds each
--  CSV by concatenating the columns inside the query instead, which works on
--  every SQL*Plus version ever shipped. The header row is written with
--  PROMPT, because PROMPT output goes into the spool file too.
--
--  BEFORE YOU RUN IT
--  Edit the csv_dir line below to a folder path that exists on your machine.
--  Use an ABSOLUTE path. SQL*Plus resolves a relative spool path against the
--  directory it was launched from, not the directory the script sits in, and
--  it will not create a missing folder - that is what SP2-0606 means. The
--  HOST mkdir line tries to create it for you; if the folder already exists
--  Windows prints a harmless "already exists" message and the script carries
--  on.
--
--      SQL> @C:\Users\USER\Downloads\task3_zx_csv_export.sql
--
--  WHAT YOU GET - seven files, one per chart:
--      b1_1_branch_scorecard.csv  bar, branch net sales grouped by region
--      b1_2_region_yoy.csv        line, regional growth
--      b2_1_hour_blocks.csv       grouped column, block mix by region
--      b2_2_hour_profile.csv      line, hour 08-23 weekday vs weekend
--      b2_3_weekend_by_block.csv  grouped column, weekend share by block
--      b3_2_leakage_by_branch.csv bar, refund-to-sales % + reference line
--      b3_3_cause_split.csv       stacked bar, Fulfilment vs Quality
--
--  The company reference line for the B3 chart is a single number, printed
--  by Exhibit 3.1 of the main report - read it off there rather than
--  exporting it.
--
--  NOTE ON BREAK AND COMPUTE. They are cleared below and never re-enabled.
--  A COMPUTE SUM subtotal row written into a CSV would be read by Power BI
--  as an ordinary branch and every region would be counted twice. The
--  subtotals belong only in the spooled text report.
-- ============================================================================

SET DEFINE ON
SET SCAN ON

-- >>> EDIT THIS LINE <<<
DEFINE csv_dir = "C:\Users\USER\Downloads\task3_csv"

HOST mkdir "&csv_dir"

DEFINE p_era_yr = 2024
DEFINE p_cur_yr = 2025
ACCEPT p_era_yr CHAR DEFAULT 2024 PROMPT 'All-branches era begins (default 2024): '
ACCEPT p_cur_yr CHAR DEFAULT 2025 PROMPT 'Reporting year, last COMPLETE year (default 2025): '

CLEAR COLUMNS
CLEAR BREAK
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF

SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET LONG 32767
SET TRIMSPOOL ON
SET TRIMOUT ON
SET FEEDBACK OFF
SET VERIFY OFF
SET ECHO OFF
SET SQLBLANKLINES ON

PROMPT
PROMPT Writing CSV files to &csv_dir
PROMPT


-- ===========================================================================
--  b1_1  Branch scorecard
-- ===========================================================================
SPOOL "&csv_dir\b1_1_branch_scorecard.csv"
PROMPT Region,Branch,Orders,NetSales,AOV,ItemsPerOrder,YoYGrowthPct,RegionSharePct,RankInRegion
WITH scoped AS (
    SELECT b.branch_region, b.branch_name, d.cal_year,
           s.order_no, s.quantity, s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year BETWEEN LEAST(&p_era_yr, &p_cur_yr - 1) AND &p_cur_yr
), cur AS (
    SELECT branch_region, branch_name,
           COUNT(DISTINCT order_no) AS orders,
           SUM(quantity)            AS units,
           SUM(net_sales_amt)       AS net_sales
    FROM   scoped WHERE cal_year = &p_cur_yr
    GROUP  BY branch_region, branch_name
), prv AS (
    SELECT branch_region, branch_name, SUM(net_sales_amt) AS net_sales_prv
    FROM   scoped WHERE cal_year = &p_cur_yr - 1
    GROUP  BY branch_region, branch_name
)
SELECT c.branch_region                                          || ',' ||
       c.branch_name                                            || ',' ||
       TO_CHAR(c.orders, 'FM999999')                            || ',' ||
       TO_CHAR(ROUND(c.net_sales, 2), 'FM99999990.00')          || ',' ||
       TO_CHAR(ROUND(c.net_sales / NULLIF(c.orders, 0), 2), 'FM99990.00')  || ',' ||
       TO_CHAR(ROUND(c.units / NULLIF(c.orders, 0), 2), 'FM990.00')        || ',' ||
       NVL(TO_CHAR(ROUND(100 * (c.net_sales - p.net_sales_prv)
                       / NULLIF(p.net_sales_prv, 0), 1), 'FM9990.0'), '')  || ',' ||
       TO_CHAR(ROUND(100 * c.net_sales
                   / NULLIF(SUM(c.net_sales) OVER
                            (PARTITION BY c.branch_region), 0), 1), 'FM990.0') || ',' ||
       TO_CHAR(RANK() OVER (PARTITION BY c.branch_region
                            ORDER BY c.net_sales DESC), 'FM90')
FROM   cur c
LEFT   JOIN prv p ON  p.branch_region = c.branch_region
                  AND p.branch_name   = c.branch_name
ORDER  BY c.branch_region, c.net_sales DESC;
SPOOL OFF


-- ===========================================================================
--  b1_2  Region roll-up and growth
-- ===========================================================================
SPOOL "&csv_dir\b1_2_region_yoy.csv"
PROMPT Region,BranchesTrading,SalesPrevYear,SalesCurYear,YoYGrowthPct,NationalSharePct,AOVCurYear,GrowthRank
WITH scoped AS (
    SELECT b.branch_region, b.branch_name, d.cal_year,
           s.order_no, s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year BETWEEN LEAST(&p_era_yr, &p_cur_yr - 1) AND &p_cur_yr
), reg AS (
    SELECT branch_region,
           COUNT(DISTINCT branch_name)                                      AS branches_trading,
           SUM(CASE WHEN cal_year = &p_cur_yr - 1 THEN net_sales_amt END)   AS sales_prv,
           SUM(CASE WHEN cal_year = &p_cur_yr     THEN net_sales_amt END)   AS sales_cur,
           COUNT(DISTINCT CASE WHEN cal_year = &p_cur_yr THEN order_no END) AS orders_cur
    FROM   scoped
    GROUP  BY branch_region
)
SELECT branch_region                                            || ',' ||
       TO_CHAR(branches_trading, 'FM990')                       || ',' ||
       TO_CHAR(ROUND(sales_prv, 2), 'FM99999990.00')            || ',' ||
       TO_CHAR(ROUND(sales_cur, 2), 'FM99999990.00')            || ',' ||
       TO_CHAR(ROUND(100 * (sales_cur - sales_prv)
                   / NULLIF(sales_prv, 0), 1), 'FM9990.0')      || ',' ||
       TO_CHAR(ROUND(100 * sales_cur
                   / NULLIF(SUM(sales_cur) OVER (), 0), 1), 'FM990.0') || ',' ||
       TO_CHAR(ROUND(sales_cur / NULLIF(orders_cur, 0), 2), 'FM99990.00') || ',' ||
       TO_CHAR(RANK() OVER (ORDER BY (sales_cur - sales_prv)
                                     / NULLIF(sales_prv, 0) DESC), 'FM90')
FROM   reg
ORDER  BY sales_cur DESC;
SPOOL OFF


-- ===========================================================================
--  b2_1  Trading day shape by region
-- ===========================================================================
SPOOL "&csv_dir\b2_1_hour_blocks.csv"
PROMPT Region,Opening0811,Midday1216,AfterWork1719,Late2022,PeakBlock,WeekdaySales,WeekendSales,WeekendSharePct,SalesRank
WITH blocks AS (
    SELECT b.branch_region,
           CASE WHEN s.order_hour BETWEEN  8 AND 11 THEN 'Opening'
                WHEN s.order_hour BETWEEN 12 AND 16 THEN 'Midday'
                WHEN s.order_hour BETWEEN 17 AND 19 THEN 'After-work'
                ELSE 'Late'
           END AS hour_block,
           d.weekday_ind, s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
), pivoted AS (
    SELECT branch_region,
           SUM(CASE WHEN hour_block = 'Opening'    THEN net_sales_amt ELSE 0 END) AS opening_amt,
           SUM(CASE WHEN hour_block = 'Midday'     THEN net_sales_amt ELSE 0 END) AS midday_amt,
           SUM(CASE WHEN hour_block = 'After-work' THEN net_sales_amt ELSE 0 END) AS afterwork_amt,
           SUM(CASE WHEN hour_block = 'Late'       THEN net_sales_amt ELSE 0 END) AS late_amt,
           SUM(CASE WHEN weekday_ind = 'Y' THEN net_sales_amt ELSE 0 END)         AS weekday_amt,
           SUM(CASE WHEN weekday_ind = 'N' THEN net_sales_amt ELSE 0 END)         AS weekend_amt,
           SUM(net_sales_amt)                                                     AS total_amt
    FROM   blocks
    GROUP  BY branch_region
)
SELECT branch_region                                    || ',' ||
       TO_CHAR(ROUND(opening_amt),   'FM99999990')      || ',' ||
       TO_CHAR(ROUND(midday_amt),    'FM99999990')      || ',' ||
       TO_CHAR(ROUND(afterwork_amt), 'FM99999990')      || ',' ||
       TO_CHAR(ROUND(late_amt),      'FM99999990')      || ',' ||
       CASE WHEN opening_amt   >= midday_amt
             AND opening_amt   >= afterwork_amt
             AND opening_amt   >= late_amt      THEN 'Opening'
            WHEN midday_amt    >= afterwork_amt
             AND midday_amt    >= late_amt      THEN 'Midday'
            WHEN afterwork_amt >= late_amt      THEN 'After-work'
            ELSE 'Late'
       END                                              || ',' ||
       TO_CHAR(ROUND(weekday_amt), 'FM99999990')        || ',' ||
       TO_CHAR(ROUND(weekend_amt), 'FM99999990')        || ',' ||
       TO_CHAR(ROUND(100 * weekend_amt
                   / NULLIF(total_amt, 0), 1), 'FM990.0') || ',' ||
       TO_CHAR(RANK() OVER (ORDER BY total_amt DESC), 'FM90')
FROM   pivoted
ORDER  BY total_amt DESC;
SPOOL OFF


-- ===========================================================================
--  b2_2  Hour-by-hour profile
-- ===========================================================================
SPOOL "&csv_dir\b2_2_hour_profile.csv"
PROMPT Region,Hour,WeekdaySales,WeekendSales,WeekdayOrders,WeekendOrders,HourSharePct
SELECT b.branch_region                                  || ',' ||
       TO_CHAR(s.order_hour, 'FM90')                    || ',' ||
       TO_CHAR(ROUND(SUM(CASE WHEN d.weekday_ind = 'Y'
                              THEN s.net_sales_amt ELSE 0 END)), 'FM99999990') || ',' ||
       TO_CHAR(ROUND(SUM(CASE WHEN d.weekday_ind = 'N'
                              THEN s.net_sales_amt ELSE 0 END)), 'FM99999990') || ',' ||
       TO_CHAR(COUNT(DISTINCT CASE WHEN d.weekday_ind = 'Y'
                                   THEN s.order_no END), 'FM999990')           || ',' ||
       TO_CHAR(COUNT(DISTINCT CASE WHEN d.weekday_ind = 'N'
                                   THEN s.order_no END), 'FM999990')           || ',' ||
       TO_CHAR(ROUND(100 * SUM(s.net_sales_amt)
                   / NULLIF(SUM(SUM(s.net_sales_amt))
                            OVER (PARTITION BY b.branch_region), 0), 2), 'FM990.00')
FROM   sales_fact s
JOIN   branch_dim b ON b.branch_key = s.branch_key
JOIN   date_dim   d ON d.date_key   = s.order_date_key
WHERE  b.branch_key <> -1
AND    d.cal_year >= &p_era_yr
GROUP  BY b.branch_region, s.order_hour
ORDER  BY b.branch_region, s.order_hour;
SPOOL OFF


-- ===========================================================================
--  b2_3  Weekend concentration by block
-- ===========================================================================
SPOOL "&csv_dir\b2_3_weekend_by_block.csv"
PROMPT Region,Block,BlockOrder,WeekdaySales,WeekendSales,WeekendSharePct,VsCalendar
WITH blocks AS (
    SELECT b.branch_region,
           CASE WHEN s.order_hour BETWEEN  8 AND 11 THEN 1
                WHEN s.order_hour BETWEEN 12 AND 16 THEN 2
                WHEN s.order_hour BETWEEN 17 AND 19 THEN 3
                ELSE 4
           END AS block_ord,
           d.weekday_ind, s.net_sales_amt
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
), agg AS (
    SELECT branch_region, block_ord,
           SUM(CASE WHEN weekday_ind = 'Y' THEN net_sales_amt ELSE 0 END) AS weekday_amt,
           SUM(CASE WHEN weekday_ind = 'N' THEN net_sales_amt ELSE 0 END) AS weekend_amt
    FROM   blocks
    GROUP  BY branch_region, block_ord
)
SELECT branch_region                                    || ',' ||
       CASE block_ord WHEN 1 THEN 'Opening 08-11'
                      WHEN 2 THEN 'Midday 12-16'
                      WHEN 3 THEN 'After-work 17-19'
                      ELSE        'Late 20-22' END      || ',' ||
       TO_CHAR(block_ord, 'FM90')                       || ',' ||
       TO_CHAR(ROUND(weekday_amt), 'FM99999990')        || ',' ||
       TO_CHAR(ROUND(weekend_amt), 'FM99999990')        || ',' ||
       TO_CHAR(ROUND(100 * weekend_amt
                   / NULLIF(weekday_amt + weekend_amt, 0), 1), 'FM990.0') || ',' ||
       CASE WHEN ROUND(100 * weekend_amt
                     / NULLIF(weekday_amt + weekend_amt, 0), 1) >= 28.6
            THEN 'Over' ELSE 'Under' END
FROM   agg
ORDER  BY branch_region, block_ord;
SPOOL OFF


-- ===========================================================================
--  b3_2  Return leakage by branch
-- ===========================================================================
SPOOL "&csv_dir\b3_2_leakage_by_branch.csv"
PROMPT Region,Branch,NetSales,RefundAmt,RefundToSalesPct,FulfilmentRM,QualityRM,AvgDaysToReturn,LeakRank
WITH sales AS (
    SELECT b.branch_region, b.branch_name, SUM(s.net_sales_amt) AS net_sales
    FROM   sales_fact s
    JOIN   branch_dim b ON b.branch_key = s.branch_key
    JOIN   date_dim   d ON d.date_key   = s.order_date_key
    WHERE  b.branch_key <> -1
    AND    d.cal_year >= &p_era_yr
    GROUP  BY b.branch_region, b.branch_name
), rets AS (
    SELECT b.branch_region, b.branch_name,
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
SELECT s.branch_region                                  || ',' ||
       s.branch_name                                    || ',' ||
       TO_CHAR(ROUND(s.net_sales, 2), 'FM99999990.00')  || ',' ||
       TO_CHAR(ROUND(NVL(r.refund_amt, 0), 2), 'FM9999990.00')          || ',' ||
       TO_CHAR(ROUND(100 * NVL(r.refund_amt, 0)
                   / NULLIF(s.net_sales, 0), 2), 'FM990.00')            || ',' ||
       TO_CHAR(ROUND(NVL(r.fulfil_amt, 0), 2), 'FM9999990.00')          || ',' ||
       TO_CHAR(ROUND(NVL(r.quality_amt, 0), 2), 'FM9999990.00')         || ',' ||
       TO_CHAR(ROUND(NVL(r.avg_days_return, 0), 1), 'FM990.0')          || ',' ||
       TO_CHAR(RANK() OVER (ORDER BY NVL(r.refund_amt, 0)
                                     / NULLIF(s.net_sales, 0) DESC), 'FM90')
FROM   sales s
LEFT   JOIN rets r ON  r.branch_region = s.branch_region
                   AND r.branch_name   = s.branch_name
ORDER  BY s.branch_region, NVL(r.refund_amt, 0) / NULLIF(s.net_sales, 0) DESC;
SPOOL OFF


-- ===========================================================================
--  b3_3  Cause split by region and reason
-- ===========================================================================
SPOOL "&csv_dir\b3_3_cause_split.csv"
PROMPT Region,CauseCategory,Reason,UnitsReturned,RefundAmt,RegionSharePct,AvgDaysToReturn
SELECT b.branch_region                                  || ',' ||
       rr.reason_category                               || ',' ||
       rr.reason_name                                   || ',' ||
       TO_CHAR(SUM(r.quantity_returned), 'FM999990')    || ',' ||
       TO_CHAR(ROUND(SUM(r.refund_amount), 2), 'FM9999990.00')          || ',' ||
       TO_CHAR(ROUND(100 * SUM(r.refund_amount)
                   / NULLIF(SUM(SUM(r.refund_amount))
                            OVER (PARTITION BY b.branch_region), 0), 1), 'FM990.0') || ',' ||
       TO_CHAR(ROUND(AVG(GREATEST(r.days_to_return, 0)), 1), 'FM990.0')
FROM   return_fact       r
JOIN   branch_dim        b  ON b.branch_key  = r.branch_key
JOIN   return_reason_dim rr ON rr.reason_key = r.reason_key
JOIN   date_dim          d  ON d.date_key    = r.order_date_key
WHERE  b.branch_key <> -1
AND    d.cal_year >= &p_era_yr
AND    r.return_status IN ('Approved', 'Refunded')
GROUP  BY b.branch_region, rr.reason_category, rr.reason_name
ORDER  BY b.branch_region, rr.reason_category, SUM(r.refund_amount) DESC;
SPOOL OFF


-- ---------------------------------------------------------------------------
--  Restore the settings the main report script expects
-- ---------------------------------------------------------------------------
SET HEADING ON
SET PAGESIZE 60
SET LINESIZE 160
SET FEEDBACK ON

PROMPT
PROMPT Done. Seven CSV files written to &csv_dir
PROMPT In Power BI: Get Data > Folder > point at that directory, or Get Data >
PROMPT Text/CSV one file at a time. Set the numeric columns to Decimal Number
PROMPT and Hour to Whole Number on import.
PROMPT
