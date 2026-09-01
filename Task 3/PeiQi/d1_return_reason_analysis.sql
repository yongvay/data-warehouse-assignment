-- ============================================================================
-- TASK 3 - STUDENT D (PEI QI)
-- D1. RETURN REASON ANALYSIS BY ITEM CATEGORY
--
-- Question:
--   What are we getting back, and why?
--
-- Facts / Dimensions:
--   RETURN_FACT + RETURN_REASON_DIM + ITEM_DIM
--   SALES_FACT is used separately for the quantity-sold denominator.
--   DATE_DIM is used only to select a comparable original-order cohort year.
--
-- IMPORTANT ANALYTICAL RULE:
--   Returns are filtered by RETURN_FACT.ORDER_DATE_KEY (the original sale date),
--   and SALES_FACT is filtered by the same year. This keeps:
--
--      Return Rate % = Qty Returned / Qty Sold
--
--   on the same sales cohort.
--
--   RETURN_FACT and SALES_FACT are aggregated separately BEFORE joining, to
--   prevent fact-to-fact fan-out/double counting.
-- ============================================================================

SET SQLBLANKLINES ON
SET VERIFY OFF
SET FEEDBACK OFF
SET TRIMSPOOL ON
SET LINESIZE 220
SET PAGESIZE 100

ACCEPT p_year NUMBER DEFAULT 2025 PROMPT 'Enter original order cohort year [2025]: '

PROMPT
PROMPT ============================================================================
PROMPT D1 - RETURN REASON ANALYSIS BY ITEM CATEGORY
PROMPT Question: What are we getting back, and why?
PROMPT Cohort: Items originally sold in &p_year
PROMPT ============================================================================
PROMPT

TTITLE CENTER 'D1 - RETURN REASON ANALYSIS BY ITEM CATEGORY' -
       RIGHT 'Page:' FORMAT 999 SQL.PNO SKIP 1 -
       CENTER 'Original Order Cohort Year: &p_year' SKIP 2

COLUMN return_rank         HEADING 'Rank'              FORMAT 999
COLUMN category_name       HEADING 'Category'          FORMAT A24
COLUMN missing_qty         HEADING 'Missing'           FORMAT 999,990
COLUMN broken_qty          HEADING 'Broken'            FORMAT 999,990
COLUMN expired_qty         HEADING 'Expired'           FORMAT 999,990
COLUMN wrong_item_qty      HEADING 'Wrong|Item'        FORMAT 999,990
COLUMN total_qty_returned  HEADING 'Total Qty|Returned' FORMAT 999,990
COLUMN refund_amount       HEADING 'Refund|Amount (RM)' FORMAT 999,999,990.00
COLUMN return_rate_pct     HEADING 'Return|Rate %'     FORMAT 990.99
COLUMN avg_days_to_return  HEADING 'Avg Days|to Return' FORMAT 990.99

BREAK ON REPORT
COMPUTE SUM LABEL 'TOTAL' OF missing_qty broken_qty expired_qty wrong_item_qty -
    total_qty_returned refund_amount ON REPORT

WITH
-- CTE 1: quantity sold by item category for the selected original-order year.
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
    WHERE d.cal_year = &p_year
      AND i.category_id <> 'UNKN'
    GROUP BY
        i.category_id,
        i.category_name
),

-- CTE 2: returned quantity by reason, category, and the SAME original-order year.
-- The four reason names are constrained by RETURN_REASON_DIM:
-- Missing, Broken, Expired, Wrong Item.
returns_by_category AS (
    SELECT
        i.category_id,
        i.category_name,

        SUM(CASE
                WHEN rr.reason_name = 'Missing'
                THEN rf.quantity_returned
                ELSE 0
            END) AS missing_qty,

        SUM(CASE
                WHEN rr.reason_name = 'Broken'
                THEN rf.quantity_returned
                ELSE 0
            END) AS broken_qty,

        SUM(CASE
                WHEN rr.reason_name = 'Expired'
                THEN rf.quantity_returned
                ELSE 0
            END) AS expired_qty,

        SUM(CASE
                WHEN rr.reason_name = 'Wrong Item'
                THEN rf.quantity_returned
                ELSE 0
            END) AS wrong_item_qty,

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
    WHERE d.cal_year = &p_year
      AND i.category_id <> 'UNKN'
      AND rr.reason_name <> 'Unknown'
    GROUP BY
        i.category_id,
        i.category_name
),

-- CTE 3: combine the two fact aggregates only after each has reached category grain.
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
        ROUND(
            100 * r.total_qty_returned / NULLIF(s.qty_sold, 0),
            2
        ) AS return_rate_pct,
        ROUND(r.avg_days_to_return, 2) AS avg_days_to_return
    FROM returns_by_category r
    JOIN sales_by_category s
      ON s.category_id = r.category_id
),

-- CTE 4: rank categories by return-rate exposure, then returned volume.
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
ORDER BY
    return_rank,
    category_name;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF

PROMPT
PROMPT ============================================================================
PROMPT CHART EXHIBIT D1-A
PROMPT STACKED COLUMN: RETURN REASON MIX PER ITEM CATEGORY
PROMPT Use Category as X-axis and the four reason-quantity columns as stacks.
PROMPT ============================================================================
PROMPT

COLUMN category_name   HEADING 'Category'   FORMAT A24
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
    WHERE d.cal_year = &p_year
      AND i.category_id <> 'UNKN'
      AND rr.reason_name <> 'Unknown'
    GROUP BY
        i.category_id,
        i.category_name
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

PROMPT
PROMPT ============================================================================
PROMPT CHART EXHIBIT D1-B
PROMPT PIE: REFUND VALUE BY REASON CATEGORY
PROMPT RETURN_REASON_DIM maps:
PROMPT   Fulfilment     = Missing + Wrong Item
PROMPT   Product Quality = Broken + Expired
PROMPT ============================================================================
PROMPT

COLUMN reason_category HEADING 'Reason Category' FORMAT A20
COLUMN refund_amount   HEADING 'Refund Amount (RM)' FORMAT 999,999,990.00
COLUMN refund_share_pct HEADING 'Refund Share %' FORMAT 990.99

WITH refund_reason AS (
    SELECT
        rr.reason_category,
        SUM(rf.refund_amount) AS refund_amount
    FROM return_fact rf
    JOIN return_reason_dim rr
      ON rr.reason_key = rf.reason_key
    JOIN date_dim d
      ON d.date_key = rf.order_date_key
    WHERE d.cal_year = &p_year
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

PROMPT
PROMPT ============================================================================
PROMPT D1 DATA-QUALITY CHECK
PROMPT Categories with Return Rate > 100% indicate inconsistent source/test data.
PROMPT Do NOT hide these rows; mention them in the report if they appear.
PROMPT ============================================================================
PROMPT

WITH
sales_by_category AS (
    SELECT
        i.category_id,
        i.category_name,
        SUM(sf.quantity) AS qty_sold
    FROM sales_fact sf
    JOIN item_dim i ON i.item_key = sf.item_key
    JOIN date_dim d ON d.date_key = sf.order_date_key
    WHERE d.cal_year = &p_year
      AND i.category_id <> 'UNKN'
    GROUP BY i.category_id, i.category_name
),
returns_by_category AS (
    SELECT
        i.category_id,
        i.category_name,
        SUM(rf.quantity_returned) AS qty_returned
    FROM return_fact rf
    JOIN item_dim i ON i.item_key = rf.item_key
    JOIN date_dim d ON d.date_key = rf.order_date_key
    WHERE d.cal_year = &p_year
      AND i.category_id <> 'UNKN'
    GROUP BY i.category_id, i.category_name
)
SELECT
    r.category_name,
    s.qty_sold,
    r.qty_returned,
    ROUND(100 * r.qty_returned / NULLIF(s.qty_sold, 0), 2) AS return_rate_pct
FROM returns_by_category r
JOIN sales_by_category s
  ON s.category_id = r.category_id
WHERE 100 * r.qty_returned / NULLIF(s.qty_sold, 0) > 100
ORDER BY return_rate_pct DESC;

PROMPT
PROMPT End of D1.
PROMPT

UNDEFINE p_year
