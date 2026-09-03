-- ============================================================================
-- TASK 3 - STUDENT D (TEO PEI QI)
-- D3. PROMOTION EFFECTIVENESS AND DISCOUNT ROI
--
-- Business Question:
--   Which promotions generate the strongest sales uplift for the discount
--   value given, and do Percentage or Fixed promotions perform better?
--
-- Analytical Structure:
--   D3.1 WHAT + WHICH : Promotion effectiveness scorecard
--   D3.2 WHY          : Promo vs matched non-promo sales for the same items
--   D3.3 WHICH MECHANIC: Percentage vs Fixed discount performance
--   D3.4 AFTER SALE   : Promotion return and refund exposure
--
-- Facts / Dimensions:
--   SALES_FACT + PROMOTION_DIM + ITEM_DIM + DATE_DIM
--   RETURN_FACT is used as a supporting post-sale quality check.
--
-- Definitions
-- -----------
-- Duration Days:
--   active campaign days that fall inside the selected report year.
--
-- Sales per Promo Day:
--   promotion NET SALES / active campaign days in the report year.
--
-- Matched Non-Promo Baseline:
--   non-promotion sales (promo_key = 0) for the SAME item_keys that were
--   actually sold under the focal promotion, outside the focal campaign dates.
--   Baseline daily sales use all eligible calendar days outside the campaign,
--   so zero-sale days remain represented in the denominator.
--
-- Uplift %:
--   (Promo daily net sales - matched baseline daily net sales)
--   / matched baseline daily net sales * 100
--
-- Uplift per RM Discount:
--   estimated uplift value / discount given.
--   This is a discount-efficiency indicator, NOT accounting profit or causal ROI.
--
-- Final Charts:
--   1. D3.1 Combo Chart:
--      Net Sales bars + Discount-to-Gross % line by promotion
--   2. D3.2 Grouped Bar Chart:
--      Promo Daily Net Sales vs Matched Non-Promo Daily Net Sales
-- ============================================================================

SET DEFINE ON
SET SQLBLANKLINES ON
SET VERIFY OFF
SET FEEDBACK OFF
SET TRIMSPOOL ON
SET TAB OFF
SET LINESIZE 220
SET PAGESIZE 100
SET NULL '-'

ACCEPT p_year CHAR DEFAULT '2025' PROMPT 'Enter promotion analysis year [2025]: '

PROMPT
PROMPT ==========================================================================================================
PROMPT D3 - PROMOTION EFFECTIVENESS AND DISCOUNT ROI
PROMPT Business Question : Which promotions generate the strongest uplift for the discount value given?
PROMPT Analysis Year     : &p_year
PROMPT Final Charts      : 2
PROMPT ==========================================================================================================
PROMPT

-- ============================================================================
-- EXHIBIT D3.1 - WHAT + WHICH
-- ============================================================================

PROMPT ==========================================================================================================
PROMPT EXHIBIT D3.1 - WHAT + WHICH: PROMOTION EFFECTIVENESS SCORECARD
PROMPT Chart type : Combo Chart
PROMPT Chart      : Net Sales (bars) + Discount-to-Gross % (line) by Promotion
PROMPT Purpose    : Ranks campaigns by sales uplift generated per RM of discount.
PROMPT Note       : Duration Days = active promotion days inside the selected report year.
PROMPT ==========================================================================================================
PROMPT

COLUMN effectiveness_rank       HEADING 'Rank'                    FORMAT 9999
COLUMN promo_name               HEADING 'Promotion'               FORMAT A30
COLUMN discount_type            HEADING 'Type'                    FORMAT A10
COLUMN active_days              HEADING 'Duration|Days'           FORMAT 9990
COLUMN qty_sold                 HEADING 'Qty Sold'                FORMAT 999,990
COLUMN gross_sales              HEADING 'Gross Sales|(RM)'        FORMAT 999,990.00
COLUMN discount_given           HEADING 'Discount|(RM)'           FORMAT 999,990.00
COLUMN net_sales                HEADING 'Net Sales|(RM)'          FORMAT 999,990.00
COLUMN discount_to_gross_pct    HEADING 'Discount/Gross|%'        FORMAT 990.99
COLUMN sales_per_promo_day      HEADING 'Sales / Promo Day|(RM)'  FORMAT 999,990.00
COLUMN uplift_pct               HEADING 'Uplift vs|Baseline %'    FORMAT 9990.99
COLUMN uplift_per_rm_discount   HEADING 'Uplift / RM|Discount'    FORMAT 9990.99

WITH
year_bounds AS (
    SELECT
        TO_DATE('&p_year' || '0101', 'YYYYMMDD') AS year_start,
        TO_DATE('&p_year' || '1231', 'YYYYMMDD') AS year_end
    FROM dual
),
promo_sales AS (
    SELECT
        sf.promo_key,
        SUM(sf.quantity) AS qty_sold,
        SUM(sf.gross_sales_amt) AS gross_sales,
        SUM(sf.discount_amt) AS discount_given,
        SUM(sf.net_sales_amt) AS net_sales
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key
),
promo_window AS (
    SELECT
        p.promo_key,
        p.promo_name,
        p.discount_type,
        GREATEST(p.promo_start_date, y.year_start) AS active_start,
        LEAST(p.promo_end_date, y.year_end) AS active_end,
        CASE
            WHEN LEAST(p.promo_end_date, y.year_end)
                 >= GREATEST(p.promo_start_date, y.year_start)
            THEN LEAST(p.promo_end_date, y.year_end)
                 - GREATEST(p.promo_start_date, y.year_start) + 1
            ELSE 0
        END AS active_days,
        y.year_end - y.year_start + 1 AS year_days
    FROM promotion_dim p
    CROSS JOIN year_bounds y
    WHERE p.promo_key > 0
),
promo_items AS (
    SELECT DISTINCT
        sf.promo_key,
        sf.item_key
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
),
baseline_sales AS (
    SELECT
        pi.promo_key,
        SUM(sf.net_sales_amt) AS baseline_net_sales
    FROM promo_items pi
    JOIN promo_window pw
      ON pw.promo_key = pi.promo_key
    JOIN sales_fact sf
      ON sf.item_key = pi.item_key
     AND sf.promo_key = 0
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND (d.cal_date < pw.active_start OR d.cal_date > pw.active_end)
    GROUP BY pi.promo_key
),
campaign AS (
    SELECT
        ps.promo_key,
        pw.promo_name,
        pw.discount_type,
        pw.active_days,
        ps.qty_sold,
        ps.gross_sales,
        ps.discount_given,
        ps.net_sales,
        100 * ps.discount_given / NULLIF(ps.gross_sales, 0)
            AS discount_to_gross_pct,
        ps.net_sales / NULLIF(pw.active_days, 0)
            AS sales_per_promo_day,
        NVL(bs.baseline_net_sales, 0)
            / NULLIF(pw.year_days - pw.active_days, 0)
            AS baseline_sales_per_day
    FROM promo_sales ps
    JOIN promo_window pw
      ON pw.promo_key = ps.promo_key
    LEFT JOIN baseline_sales bs
      ON bs.promo_key = ps.promo_key
),
scored AS (
    SELECT
        c.*,
        100 * (c.sales_per_promo_day - c.baseline_sales_per_day)
            / NULLIF(c.baseline_sales_per_day, 0)
            AS uplift_pct,
        (c.sales_per_promo_day - c.baseline_sales_per_day) * c.active_days
            AS estimated_uplift_value,
        ((c.sales_per_promo_day - c.baseline_sales_per_day) * c.active_days)
            / NULLIF(c.discount_given, 0)
            AS uplift_per_rm_discount
    FROM campaign c
),
ranked AS (
    SELECT
        s.*,
        DENSE_RANK() OVER (
            ORDER BY
                s.uplift_per_rm_discount DESC NULLS LAST,
                s.uplift_pct DESC NULLS LAST,
                s.net_sales DESC
        ) AS effectiveness_rank
    FROM scored s
)
SELECT
    effectiveness_rank,
    promo_name,
    discount_type,
    active_days,
    qty_sold,
    ROUND(gross_sales, 2) AS gross_sales,
    ROUND(discount_given, 2) AS discount_given,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(discount_to_gross_pct, 2) AS discount_to_gross_pct,
    ROUND(sales_per_promo_day, 2) AS sales_per_promo_day,
    ROUND(uplift_pct, 2) AS uplift_pct,
    ROUND(uplift_per_rm_discount, 2) AS uplift_per_rm_discount
FROM ranked
ORDER BY effectiveness_rank, promo_name;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D3.2 - WHY
-- ============================================================================

PROMPT
PROMPT ==========================================================================================================
PROMPT EXHIBIT D3.2 - WHY: PROMO VS MATCHED NON-PROMO SALES FOR THE SAME ITEMS
PROMPT Chart type : Grouped Bar Chart
PROMPT Chart      : Promo Daily Net Sales vs Matched Non-Promo Daily Net Sales
PROMPT Purpose    : Tests whether the same promoted items sell more strongly during the campaign.
PROMPT ==========================================================================================================
PROMPT

COLUMN promo_name                HEADING 'Promotion'               FORMAT A30
COLUMN promoted_item_count       HEADING 'Items'                   FORMAT 9990
COLUMN active_days               HEADING 'Promo|Days'              FORMAT 9990
COLUMN baseline_days             HEADING 'Baseline|Days'           FORMAT 9990
COLUMN promo_sales_per_day       HEADING 'Promo Sales / Day|(RM)'  FORMAT 999,990.00
COLUMN baseline_sales_per_day    HEADING 'Non-Promo / Day|(RM)'    FORMAT 999,990.00
COLUMN uplift_pct                HEADING 'Uplift|%'                FORMAT 9990.99
COLUMN estimated_uplift_value    HEADING 'Est. Uplift|(RM)'        FORMAT 999,990.00

WITH
year_bounds AS (
    SELECT
        TO_DATE('&p_year' || '0101', 'YYYYMMDD') AS year_start,
        TO_DATE('&p_year' || '1231', 'YYYYMMDD') AS year_end
    FROM dual
),
promo_window AS (
    SELECT
        p.promo_key,
        p.promo_name,
        GREATEST(p.promo_start_date, y.year_start) AS active_start,
        LEAST(p.promo_end_date, y.year_end) AS active_end,
        CASE
            WHEN LEAST(p.promo_end_date, y.year_end)
                 >= GREATEST(p.promo_start_date, y.year_start)
            THEN LEAST(p.promo_end_date, y.year_end)
                 - GREATEST(p.promo_start_date, y.year_start) + 1
            ELSE 0
        END AS active_days,
        y.year_end - y.year_start + 1 AS year_days
    FROM promotion_dim p
    CROSS JOIN year_bounds y
    WHERE p.promo_key > 0
),
promo_sales AS (
    SELECT
        sf.promo_key,
        SUM(sf.net_sales_amt) AS promo_net_sales
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key
),
promo_items AS (
    SELECT sf.promo_key, sf.item_key
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key, sf.item_key
),
item_counts AS (
    SELECT promo_key, COUNT(*) AS promoted_item_count
    FROM promo_items
    GROUP BY promo_key
),
baseline_sales AS (
    SELECT
        pi.promo_key,
        SUM(sf.net_sales_amt) AS baseline_net_sales
    FROM promo_items pi
    JOIN promo_window pw
      ON pw.promo_key = pi.promo_key
    JOIN sales_fact sf
      ON sf.item_key = pi.item_key
     AND sf.promo_key = 0
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND (d.cal_date < pw.active_start OR d.cal_date > pw.active_end)
    GROUP BY pi.promo_key
),
comparison AS (
    SELECT
        pw.promo_name,
        ic.promoted_item_count,
        pw.active_days,
        pw.year_days - pw.active_days AS baseline_days,
        ps.promo_net_sales / NULLIF(pw.active_days, 0)
            AS promo_sales_per_day,
        NVL(bs.baseline_net_sales, 0)
            / NULLIF(pw.year_days - pw.active_days, 0)
            AS baseline_sales_per_day
    FROM promo_window pw
    JOIN promo_sales ps
      ON ps.promo_key = pw.promo_key
    JOIN item_counts ic
      ON ic.promo_key = pw.promo_key
    LEFT JOIN baseline_sales bs
      ON bs.promo_key = pw.promo_key
)
SELECT
    promo_name,
    promoted_item_count,
    active_days,
    baseline_days,
    ROUND(promo_sales_per_day, 2) AS promo_sales_per_day,
    ROUND(baseline_sales_per_day, 2) AS baseline_sales_per_day,
    ROUND(
        100 * (promo_sales_per_day - baseline_sales_per_day)
        / NULLIF(baseline_sales_per_day, 0),
        2
    ) AS uplift_pct,
    ROUND(
        (promo_sales_per_day - baseline_sales_per_day) * active_days,
        2
    ) AS estimated_uplift_value
FROM comparison
ORDER BY uplift_pct DESC NULLS LAST, promo_name;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D3.3 - WHICH MECHANIC
-- ============================================================================

PROMPT
PROMPT ==========================================================================================================
PROMPT EXHIBIT D3.3 - WHICH MECHANIC: PERCENTAGE VS FIXED DISCOUNT PERFORMANCE
PROMPT Chart type : Supporting Table (No Separate Chart)
PROMPT Purpose    : Compares whether Percentage or Fixed campaigns create stronger average uplift and efficiency.
PROMPT ==========================================================================================================
PROMPT

COLUMN discount_type              HEADING 'Discount Type'        FORMAT A14
COLUMN campaign_count             HEADING 'Campaigns'            FORMAT 9990
COLUMN qty_sold                   HEADING 'Qty Sold'              FORMAT 999,990
COLUMN gross_sales                HEADING 'Gross Sales|(RM)'      FORMAT 999,990.00
COLUMN discount_given             HEADING 'Discount|(RM)'         FORMAT 999,990.00
COLUMN net_sales                  HEADING 'Net Sales|(RM)'        FORMAT 999,990.00
COLUMN discount_to_gross_pct      HEADING 'Discount/Gross|%'      FORMAT 990.99
COLUMN avg_uplift_pct             HEADING 'Avg Uplift|%'          FORMAT 9990.99
COLUMN uplift_per_rm_discount     HEADING 'Uplift / RM|Discount'  FORMAT 9990.99

WITH
year_bounds AS (
    SELECT
        TO_DATE('&p_year' || '0101', 'YYYYMMDD') AS year_start,
        TO_DATE('&p_year' || '1231', 'YYYYMMDD') AS year_end
    FROM dual
),
promo_sales AS (
    SELECT
        sf.promo_key,
        SUM(sf.quantity) AS qty_sold,
        SUM(sf.gross_sales_amt) AS gross_sales,
        SUM(sf.discount_amt) AS discount_given,
        SUM(sf.net_sales_amt) AS net_sales
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key
),
promo_window AS (
    SELECT
        p.promo_key,
        p.discount_type,
        GREATEST(p.promo_start_date, y.year_start) AS active_start,
        LEAST(p.promo_end_date, y.year_end) AS active_end,
        CASE
            WHEN LEAST(p.promo_end_date, y.year_end)
                 >= GREATEST(p.promo_start_date, y.year_start)
            THEN LEAST(p.promo_end_date, y.year_end)
                 - GREATEST(p.promo_start_date, y.year_start) + 1
            ELSE 0
        END AS active_days,
        y.year_end - y.year_start + 1 AS year_days
    FROM promotion_dim p
    CROSS JOIN year_bounds y
    WHERE p.promo_key > 0
      AND p.discount_type IN ('Percentage', 'Fixed')
),
promo_items AS (
    SELECT DISTINCT sf.promo_key, sf.item_key
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
),
baseline_sales AS (
    SELECT
        pi.promo_key,
        SUM(sf.net_sales_amt) AS baseline_net_sales
    FROM promo_items pi
    JOIN promo_window pw
      ON pw.promo_key = pi.promo_key
    JOIN sales_fact sf
      ON sf.item_key = pi.item_key
     AND sf.promo_key = 0
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND (d.cal_date < pw.active_start OR d.cal_date > pw.active_end)
    GROUP BY pi.promo_key
),
campaign AS (
    SELECT
        pw.discount_type,
        ps.qty_sold,
        ps.gross_sales,
        ps.discount_given,
        ps.net_sales,
        100 * ps.discount_given / NULLIF(ps.gross_sales, 0)
            AS discount_to_gross_pct,
        ps.net_sales / NULLIF(pw.active_days, 0)
            AS promo_sales_per_day,
        NVL(bs.baseline_net_sales, 0)
            / NULLIF(pw.year_days - pw.active_days, 0)
            AS baseline_sales_per_day,
        pw.active_days
    FROM promo_sales ps
    JOIN promo_window pw
      ON pw.promo_key = ps.promo_key
    LEFT JOIN baseline_sales bs
      ON bs.promo_key = ps.promo_key
),
scored AS (
    SELECT
        c.*,
        100 * (c.promo_sales_per_day - c.baseline_sales_per_day)
            / NULLIF(c.baseline_sales_per_day, 0)
            AS uplift_pct,
        (c.promo_sales_per_day - c.baseline_sales_per_day) * c.active_days
            AS estimated_uplift_value
    FROM campaign c
)
SELECT
    discount_type,
    COUNT(*) AS campaign_count,
    SUM(qty_sold) AS qty_sold,
    ROUND(SUM(gross_sales), 2) AS gross_sales,
    ROUND(SUM(discount_given), 2) AS discount_given,
    ROUND(SUM(net_sales), 2) AS net_sales,
    ROUND(
        100 * SUM(discount_given) / NULLIF(SUM(gross_sales), 0),
        2
    ) AS discount_to_gross_pct,
    ROUND(AVG(uplift_pct), 2) AS avg_uplift_pct,
    ROUND(
        SUM(estimated_uplift_value) / NULLIF(SUM(discount_given), 0),
        2
    ) AS uplift_per_rm_discount
FROM scored
GROUP BY discount_type
ORDER BY uplift_per_rm_discount DESC NULLS LAST, discount_type;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D3.4 - AFTER SALE
-- ============================================================================

PROMPT
PROMPT ==========================================================================================================
PROMPT EXHIBIT D3.4 - AFTER SALE: PROMOTION RETURN AND REFUND EXPOSURE
PROMPT Chart type : Supporting Table (No Separate Chart)
PROMPT Purpose    : Checks whether strong promoted sales are later reduced by approved/refunded returns.
PROMPT Note       : Returns are attributed through RETURN_FACT.ORDER_DATE_KEY to the original sale year.
PROMPT ==========================================================================================================
PROMPT

COLUMN promo_name               HEADING 'Promotion'                FORMAT A30
COLUMN qty_sold                 HEADING 'Qty Sold'                 FORMAT 999,990
COLUMN qty_returned             HEADING 'Qty Returned'             FORMAT 999,990
COLUMN return_rate_pct          HEADING 'Return|%'                 FORMAT 990.99
COLUMN refund_exposure          HEADING 'Refund|(RM)'              FORMAT 999,990.00
COLUMN net_sales                HEADING 'Net Sales|(RM)'           FORMAT 999,990.00
COLUMN net_after_returns        HEADING 'Net After Returns|(RM)'   FORMAT 999,990.00
COLUMN refund_to_net_pct        HEADING 'Refund / Net|%'           FORMAT 990.99

WITH
promo_sales AS (
    SELECT
        sf.promo_key,
        SUM(sf.quantity) AS qty_sold,
        SUM(sf.net_sales_amt) AS net_sales
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND sf.promo_key > 0
    GROUP BY sf.promo_key
),
promo_returns AS (
    SELECT
        rf.promo_key,
        SUM(CASE
                WHEN rf.return_status IN ('Approved', 'Refunded')
                THEN rf.quantity_returned
                ELSE 0
            END) AS qty_returned,
        SUM(CASE
                WHEN rf.return_status IN ('Approved', 'Refunded')
                THEN rf.refund_amount
                ELSE 0
            END) AS refund_exposure
    FROM return_fact rf
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND rf.promo_key > 0
    GROUP BY rf.promo_key
)
SELECT
    p.promo_name,
    ps.qty_sold,
    NVL(pr.qty_returned, 0) AS qty_returned,
    ROUND(
        100 * NVL(pr.qty_returned, 0) / NULLIF(ps.qty_sold, 0),
        2
    ) AS return_rate_pct,
    ROUND(NVL(pr.refund_exposure, 0), 2) AS refund_exposure,
    ROUND(ps.net_sales, 2) AS net_sales,
    ROUND(ps.net_sales - NVL(pr.refund_exposure, 0), 2)
        AS net_after_returns,
    ROUND(
        100 * NVL(pr.refund_exposure, 0) / NULLIF(ps.net_sales, 0),
        2
    ) AS refund_to_net_pct
FROM promo_sales ps
JOIN promotion_dim p
  ON p.promo_key = ps.promo_key
LEFT JOIN promo_returns pr
  ON pr.promo_key = ps.promo_key
ORDER BY refund_to_net_pct DESC, return_rate_pct DESC, p.promo_name;

CLEAR COLUMNS

-- ============================================================================
-- DATA QUALITY CHECKS
-- ============================================================================

PROMPT
PROMPT ==========================================================================================================
PROMPT D3 DATA QUALITY CHECKS
PROMPT ==========================================================================================================
PROMPT

COLUMN dq_check   HEADING 'Check'  FORMAT A45
COLUMN dq_status  HEADING 'Status' FORMAT A70

WITH
selected_sales AS (
    SELECT sf.*
    FROM sales_fact sf
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
),
checks AS (
    SELECT
        'Net sales differs from gross - discount' AS dq_check,
        SUM(CASE
                WHEN ABS(net_sales_amt - (gross_sales_amt - discount_amt)) > 0.01
                THEN 1 ELSE 0
            END) AS bad_count
    FROM selected_sales

    UNION ALL

    SELECT
        'Promoted rows with zero discount',
        SUM(CASE
                WHEN promo_key > 0 AND discount_amt <= 0
                THEN 1 ELSE 0
            END)
    FROM selected_sales

    UNION ALL

    SELECT
        'No-promotion rows with non-zero discount',
        SUM(CASE
                WHEN promo_key = 0 AND discount_amt <> 0
                THEN 1 ELSE 0
            END)
    FROM selected_sales
)
SELECT
    dq_check,
    CASE
        WHEN bad_count = 0 THEN 'PASS'
        ELSE 'CHECK - ' || bad_count || ' row(s)'
    END AS dq_status
FROM checks
ORDER BY dq_check;

CLEAR COLUMNS

PROMPT
PROMPT ==========================================================================================================
PROMPT END OF D3 - PROMOTION EFFECTIVENESS AND DISCOUNT ROI
PROMPT ==========================================================================================================
PROMPT

UNDEFINE p_year
SET FEEDBACK ON
