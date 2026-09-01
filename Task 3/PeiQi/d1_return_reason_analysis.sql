-- ============================================================================
-- TASK 3 - STUDENT D (TEO PEI QI)
-- D1. RETURN REASON ANALYSIS BY ITEM CATEGORY
--
-- Business Question:
--   What are we getting back, and why?
--
-- 5W Analytical Structure:
--   WHERE : Which item categories carry the highest return exposure?
--   WHAT  : What return reasons are occurring?
--   WHO   : Which responsibility area carries the refund exposure?
--           (Fulfilment vs Product Quality)
--   WHY   : What is the dominant return reason within each category?
--   WHEN  : How soon after the original sale are products returned?
--
-- Facts / Dimensions:
--   RETURN_FACT + RETURN_REASON_DIM + ITEM_DIM
--   SALES_FACT is used separately for the quantity-sold denominator.
--   DATE_DIM is used to select the original-order cohort year.
--
-- Analytical Rule:
--   Returns are filtered by RETURN_FACT.ORDER_DATE_KEY (original sale date),
--   and SALES_FACT is filtered by the same year.
--
--   Return Rate % = Qty Returned / Qty Sold * 100
--
--   RETURN_FACT and SALES_FACT are aggregated separately before joining
--   to prevent fact-to-fact fan-out / double counting.
-- ============================================================================

SET DEFINE ON
SET SQLBLANKLINES ON
SET VERIFY OFF
SET FEEDBACK OFF
SET TRIMSPOOL ON
SET TAB OFF
SET LINESIZE 170
SET PAGESIZE 100
SET NULL '-'

ACCEPT p_year CHAR DEFAULT '2025' PROMPT 'Enter original order cohort year [2025]: '

PROMPT
PROMPT ==========================================================================================
PROMPT D1 - RETURN REASON ANALYSIS BY ITEM CATEGORY
PROMPT Business Question : What are we getting back, and why?
PROMPT Cohort            : Items originally sold in &p_year
PROMPT ==========================================================================================
PROMPT

-- ============================================================================
-- EXHIBIT D1.1
-- WHERE: WHICH ITEM CATEGORIES CARRY THE HIGHEST RETURN EXPOSURE?
-- ============================================================================

PROMPT ==========================================================================================
PROMPT EXHIBIT D1.1 - WHERE: RETURN EXPOSURE BY ITEM CATEGORY
PROMPT Chart type : Horizontal Bar Chart
PROMPT Purpose    : Ranks item categories by Return Rate % to show where exposure is highest.
PROMPT Ranked by Return Rate %, then returned quantity and refund amount.
PROMPT ==========================================================================================
PROMPT

TTITLE LEFT 'D1 - RETURN REASON ANALYSIS BY ITEM CATEGORY' SKIP 1 -
       LEFT 'Original Order Cohort Year: &p_year' SKIP 2

COLUMN return_rank         HEADING 'Rank'                   FORMAT 99999
COLUMN category_name       HEADING 'Category'               FORMAT A22
COLUMN missing_qty         HEADING 'Missing'                FORMAT 999,990
COLUMN broken_qty          HEADING 'Broken'                 FORMAT 999,990
COLUMN expired_qty         HEADING 'Expired'                FORMAT 999,990
COLUMN wrong_item_qty      HEADING 'Wrong|Item'             FORMAT 999,990
COLUMN total_qty_returned  HEADING 'Total Qty|Returned'     FORMAT 999,990
COLUMN refund_amount       HEADING 'Refund Amount|(RM)'     FORMAT 999,999,990.00
COLUMN return_rate_pct     HEADING 'Return|Rate %'          FORMAT 990.99
COLUMN avg_days_to_return  HEADING 'Avg Days|to Return'     FORMAT 990.99

BREAK ON REPORT
COMPUTE SUM LABEL 'TOTAL' OF missing_qty broken_qty expired_qty wrong_item_qty -
    total_qty_returned refund_amount ON REPORT

WITH
sales_by_category AS (
    SELECT
        i.category_id,
        i.category_name,
        SUM(sf.quantity) AS qty_sold
    FROM sales_fact sf
    JOIN item_dim i
      ON i.item_key = sf.item_key
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
    GROUP BY
        i.category_id,
        i.category_name
),
returns_by_category AS (
    SELECT
        i.category_id,
        i.category_name,
        SUM(CASE WHEN rr.reason_name = 'Missing'
                 THEN rf.quantity_returned ELSE 0 END) AS missing_qty,
        SUM(CASE WHEN rr.reason_name = 'Broken'
                 THEN rf.quantity_returned ELSE 0 END) AS broken_qty,
        SUM(CASE WHEN rr.reason_name = 'Expired'
                 THEN rf.quantity_returned ELSE 0 END) AS expired_qty,
        SUM(CASE WHEN rr.reason_name = 'Wrong Item'
                 THEN rf.quantity_returned ELSE 0 END) AS wrong_item_qty,
        SUM(rf.quantity_returned) AS total_qty_returned,
        SUM(rf.refund_amount) AS refund_amount,
        AVG(rf.days_to_return) AS avg_days_to_return
    FROM return_fact rf
    JOIN return_reason_dim rr
      ON rr.reason_key = rf.reason_key
    JOIN item_dim i
      ON i.item_key = rf.item_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
      AND rr.reason_name <> 'Unknown'
    GROUP BY
        i.category_id,
        i.category_name
),
category_metrics AS (
    SELECT
        r.category_id,
        r.category_name,
        r.missing_qty,
        r.broken_qty,
        r.expired_qty,
        r.wrong_item_qty,
        r.total_qty_returned,
        r.refund_amount,
        s.qty_sold,
        ROUND(100 * r.total_qty_returned / NULLIF(s.qty_sold, 0), 2)
            AS return_rate_pct,
        ROUND(r.avg_days_to_return, 2) AS avg_days_to_return
    FROM returns_by_category r
    JOIN sales_by_category s
      ON s.category_id = r.category_id
),
ranked AS (
    SELECT
        cm.*,
        RANK() OVER (
            ORDER BY
                cm.return_rate_pct DESC NULLS LAST,
                cm.total_qty_returned DESC,
                cm.refund_amount DESC
        ) AS return_rank
    FROM category_metrics cm
)
SELECT
    return_rank,
    category_name,
    missing_qty,
    broken_qty,
    expired_qty,
    wrong_item_qty,
    total_qty_returned,
    refund_amount,
    return_rate_pct,
    avg_days_to_return
FROM ranked
ORDER BY return_rank, category_name;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF

-- ============================================================================
-- EXHIBIT D1.2
-- WHAT: WHAT RETURN REASONS ARE OCCURRING?
-- CHART: STACKED COLUMN
-- ============================================================================

PROMPT
PROMPT ==========================================================================================
PROMPT EXHIBIT D1.2 - WHAT: RETURN REASON MIX PER ITEM CATEGORY
PROMPT Chart type : Stacked Column Chart
PROMPT Purpose    : Shows Missing, Broken, Expired and Wrong Item quantities by category.
PROMPT ==========================================================================================
PROMPT

COLUMN category_name   HEADING 'Category'   FORMAT A22
COLUMN missing_qty     HEADING 'Missing'    FORMAT 999,990
COLUMN broken_qty      HEADING 'Broken'     FORMAT 999,990
COLUMN expired_qty     HEADING 'Expired'    FORMAT 999,990
COLUMN wrong_item_qty  HEADING 'Wrong Item' FORMAT 999,990

WITH reason_mix AS (
    SELECT
        i.category_id,
        i.category_name,
        SUM(CASE WHEN rr.reason_name = 'Missing'
                 THEN rf.quantity_returned ELSE 0 END) AS missing_qty,
        SUM(CASE WHEN rr.reason_name = 'Broken'
                 THEN rf.quantity_returned ELSE 0 END) AS broken_qty,
        SUM(CASE WHEN rr.reason_name = 'Expired'
                 THEN rf.quantity_returned ELSE 0 END) AS expired_qty,
        SUM(CASE WHEN rr.reason_name = 'Wrong Item'
                 THEN rf.quantity_returned ELSE 0 END) AS wrong_item_qty
    FROM return_fact rf
    JOIN return_reason_dim rr
      ON rr.reason_key = rf.reason_key
    JOIN item_dim i
      ON i.item_key = rf.item_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
      AND rr.reason_name <> 'Unknown'
    GROUP BY i.category_id, i.category_name
)
SELECT
    category_name,
    missing_qty,
    broken_qty,
    expired_qty,
    wrong_item_qty
FROM reason_mix
ORDER BY category_name;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D1.3
-- WHO: WHICH RESPONSIBILITY AREA CARRIES THE REFUND EXPOSURE?
-- CHART: PIE
-- ============================================================================

PROMPT
PROMPT ==========================================================================================
PROMPT EXHIBIT D1.3 - WHO: REFUND RESPONSIBILITY BY RETURN REASON CATEGORY
PROMPT Chart type      : Pie Chart
PROMPT Purpose         : Compares refund exposure between Fulfilment and Product Quality.
PROMPT Fulfilment      : Missing + Wrong Item
PROMPT Product Quality : Broken + Expired
PROMPT ==========================================================================================
PROMPT

COLUMN reason_category   HEADING 'Responsibility'     FORMAT A20
COLUMN refund_amount     HEADING 'Refund Amount|(RM)' FORMAT 999,999,990.00
COLUMN refund_share_pct  HEADING 'Refund|Share %'     FORMAT 990.99

WITH refund_reason AS (
    SELECT
        rr.reason_category,
        SUM(rf.refund_amount) AS refund_amount
    FROM return_fact rf
    JOIN return_reason_dim rr
      ON rr.reason_key = rf.reason_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND rr.reason_category <> 'Unknown'
    GROUP BY rr.reason_category
)
SELECT
    reason_category,
    refund_amount,
    ROUND(
        100 * refund_amount /
        NULLIF(SUM(refund_amount) OVER (), 0),
        2
    ) AS refund_share_pct
FROM refund_reason
ORDER BY refund_amount DESC;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D1.4
-- WHY: DOMINANT RETURN REASON WITHIN EACH ITEM CATEGORY
-- ============================================================================

PROMPT
PROMPT ==========================================================================================
PROMPT EXHIBIT D1.4 - WHY: DOMINANT RETURN REASON BY ITEM CATEGORY
PROMPT Chart type : Supporting Table (No Separate Chart)
PROMPT Purpose    : Identifies the main return driver within each category.
PROMPT ==========================================================================================
PROMPT

COLUMN category_name     HEADING 'Category'        FORMAT A22
COLUMN dominant_reason   HEADING 'Dominant Reason' FORMAT A16
COLUMN qty_returned      HEADING 'Qty|Returned'    FORMAT 999,990
COLUMN reason_share_pct  HEADING 'Reason|Share %'  FORMAT 990.99

WITH reason_totals AS (
    SELECT
        i.category_id,
        i.category_name,
        rr.reason_name,
        SUM(rf.quantity_returned) AS qty_returned
    FROM return_fact rf
    JOIN return_reason_dim rr
      ON rr.reason_key = rf.reason_key
    JOIN item_dim i
      ON i.item_key = rf.item_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
      AND rr.reason_name <> 'Unknown'
    GROUP BY
        i.category_id,
        i.category_name,
        rr.reason_name
),
category_totals AS (
    SELECT
        category_id,
        SUM(qty_returned) AS total_qty_returned
    FROM reason_totals
    GROUP BY category_id
),
ranked_reasons AS (
    SELECT
        r.category_id,
        r.category_name,
        r.reason_name,
        r.qty_returned,
        c.total_qty_returned,
        RANK() OVER (
            PARTITION BY r.category_id
            ORDER BY r.qty_returned DESC
        ) AS reason_rank
    FROM reason_totals r
    JOIN category_totals c
      ON c.category_id = r.category_id
)
SELECT
    category_name,
    reason_name AS dominant_reason,
    qty_returned,
    ROUND(
        100 * qty_returned /
        NULLIF(total_qty_returned, 0),
        2
    ) AS reason_share_pct
FROM ranked_reasons
WHERE reason_rank = 1
ORDER BY category_name, dominant_reason;

CLEAR COLUMNS

-- ============================================================================
-- EXHIBIT D1.5
-- WHEN: HOW SOON AFTER THE ORIGINAL SALE ARE PRODUCTS RETURNED?
-- ============================================================================

PROMPT
PROMPT ==========================================================================================
PROMPT EXHIBIT D1.5 - WHEN: RETURN TIMING AFTER ORIGINAL SALE
PROMPT Chart type : Column Chart
PROMPT Purpose    : Shows how quickly returned units come back after the original purchase.
PROMPT ==========================================================================================
PROMPT

COLUMN return_window       HEADING 'Return Window'      FORMAT A14
COLUMN return_lines        HEADING 'Return|Lines'       FORMAT 999,990
COLUMN qty_returned        HEADING 'Qty|Returned'       FORMAT 999,990
COLUMN qty_share_pct       HEADING 'Qty|Share %'        FORMAT 990.99
COLUMN refund_amount       HEADING 'Refund Amount|(RM)' FORMAT 999,999,990.00
COLUMN avg_days_to_return  HEADING 'Avg Days|to Return' FORMAT 990.99

WITH timing_base AS (
    SELECT
        CASE
            WHEN rf.days_to_return BETWEEN 0 AND 3 THEN '0-3 days'
            WHEN rf.days_to_return BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN rf.days_to_return BETWEEN 8 AND 14 THEN '8-14 days'
            ELSE '15+ days'
        END AS return_window,
        CASE
            WHEN rf.days_to_return BETWEEN 0 AND 3 THEN 1
            WHEN rf.days_to_return BETWEEN 4 AND 7 THEN 2
            WHEN rf.days_to_return BETWEEN 8 AND 14 THEN 3
            ELSE 4
        END AS window_order,
        rf.quantity_returned,
        rf.refund_amount,
        rf.days_to_return
    FROM return_fact rf
    JOIN item_dim i
      ON i.item_key = rf.item_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
),
timing_summary AS (
    SELECT
        return_window,
        window_order,
        COUNT(*) AS return_lines,
        SUM(quantity_returned) AS qty_returned,
        SUM(refund_amount) AS refund_amount,
        AVG(days_to_return) AS avg_days_to_return
    FROM timing_base
    GROUP BY return_window, window_order
)
SELECT
    return_window,
    return_lines,
    qty_returned,
    ROUND(
        100 * qty_returned /
        NULLIF(SUM(qty_returned) OVER (), 0),
        2
    ) AS qty_share_pct,
    refund_amount,
    ROUND(avg_days_to_return, 2) AS avg_days_to_return
FROM timing_summary
ORDER BY window_order;

CLEAR COLUMNS

-- ============================================================================
-- DATA QUALITY CHECK
-- ============================================================================

PROMPT
PROMPT ==========================================================================================
PROMPT D1 DATA QUALITY CHECK - RETURN RATE ABOVE 100%
PROMPT ==========================================================================================
PROMPT

COLUMN dq_status FORMAT A72 HEADING 'DQ Status'

WITH
sales_by_category AS (
    SELECT
        i.category_id,
        SUM(sf.quantity) AS qty_sold
    FROM sales_fact sf
    JOIN item_dim i
      ON i.item_key = sf.item_key
    JOIN date_dim d
      ON d.date_key = sf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
    GROUP BY i.category_id
),
returns_by_category AS (
    SELECT
        i.category_id,
        SUM(rf.quantity_returned) AS qty_returned
    FROM return_fact rf
    JOIN item_dim i
      ON i.item_key = rf.item_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = TO_NUMBER('&p_year')
      AND i.category_id <> 'UNKN'
    GROUP BY i.category_id
),
bad_categories AS (
    SELECT COUNT(*) AS bad_count
    FROM returns_by_category r
    JOIN sales_by_category s
      ON s.category_id = r.category_id
    WHERE 100 * r.qty_returned / NULLIF(s.qty_sold, 0) > 100
)
SELECT
    CASE
        WHEN bad_count = 0
        THEN 'PASS - No item category has a return rate above 100%.'
        ELSE 'CHECK - ' || bad_count ||
             ' item category/categories exceed a 100% return rate.'
    END AS dq_status
FROM bad_categories;

CLEAR COLUMNS

PROMPT
PROMPT ==========================================================================================
PROMPT END OF D1 - RETURN REASON ANALYSIS BY ITEM CATEGORY
PROMPT ==========================================================================================
PROMPT

UNDEFINE p_year
SET FEEDBACK ON
