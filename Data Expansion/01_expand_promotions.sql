-- ============================================================================
--  01_expand_promotions.sql
--  RUN AS THE ADM (OPERATIONAL) USER.  RUN AFTER 00_backup_adm.sql.
--
--      SQL> @"Data Expansion\01_expand_promotions.sql"
--
--  WHAT THIS DOES
--
--  1. Creates three "existence year" helper tables.  The source schema has no
--     JoinDate, no item launch date and no branch opening date, so those facts
--     are encoded here instead of by adding columns.  02_expand_orders.sql
--     reads them to decide which customers, items and branches may appear in
--     an order of a given year.  A customer simply places no orders before the
--     year they were acquired.
--
--  2. Adds 32 promotions covering 2016-2023 (four per year), each aligned to a
--     real Malaysian festive window so the promotion calendar matches the
--     demand peaks the order generator produces.  Without this, every
--     pre-2024 order would resolve to promo_key = 0 and eight of the ten
--     years would be promotion-blind in Task 3.
--
--  3. Attaches ~25 items to each new promotion.  PromoPrice is always
--     computed from the item's list price and clamped so that
--     0 < PromoPrice <= UnitPrice.  chk_itempromotion_price only enforces
--     PromoPrice > 0; the upper clamp is what keeps
--     (UnitPrice - PromoPrice) non-negative and therefore keeps
--     chk_sales_fact_discount satisfied in the warehouse.
--
--  SAFE TO RE-RUN: every insert is guarded, and the script aborts if the
--  promotions it creates are already present.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK ON

-- ----------------------------------------------------------------------------
--  PART 1 : EXISTENCE-YEAR HELPER TABLES
-- ----------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE gen_item_launch';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE gen_branch_open';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE gen_customer_cohort';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE gen_item_launch (
    ItemID      VARCHAR2(5) PRIMARY KEY,
    LaunchYear  NUMBER(4)   NOT NULL
);

CREATE TABLE gen_branch_open (
    BranchID    VARCHAR2(5) PRIMARY KEY,
    OpenYear    NUMBER(4)   NOT NULL
);

CREATE TABLE gen_customer_cohort (
    CustomerID  VARCHAR2(5) PRIMARY KEY,
    FirstYear   NUMBER(4)   NOT NULL
);

-- ---- Items -----------------------------------------------------------------
--  30 items exist from the start, then roughly four new lines a year, all 60
--  listed by 2023 so the existing 2024-2026 order lines stay valid.
INSERT INTO gen_item_launch (ItemID, LaunchYear)
SELECT i.ItemID,
       CASE
           WHEN rn <= 30 THEN 2016
           WHEN rn <= 34 THEN 2017
           WHEN rn <= 38 THEN 2018
           WHEN rn <= 42 THEN 2019
           WHEN rn <= 46 THEN 2020
           WHEN rn <= 50 THEN 2021
           WHEN rn <= 54 THEN 2022
           ELSE               2023
       END
FROM ( SELECT ItemID, ROW_NUMBER() OVER (ORDER BY ItemID) AS rn
       FROM   Item ) i;

-- ---- Branches --------------------------------------------------------------
--  Four branches at the start of 2016, all twelve open by 2023.  This is the
--  branch-rollout trend for Task 3.
INSERT INTO gen_branch_open (BranchID, OpenYear)
SELECT b.BranchID,
       CASE
           WHEN rn <= 4  THEN 2016
           WHEN rn <= 6  THEN 2017
           WHEN rn =  7  THEN 2018
           WHEN rn <= 9  THEN 2019
           WHEN rn = 10  THEN 2021
           WHEN rn = 11  THEN 2022
           ELSE               2023
       END
FROM ( SELECT BranchID, ROW_NUMBER() OVER (ORDER BY BranchID) AS rn
       FROM   Branch ) b;

-- ---- Customers -------------------------------------------------------------
--  Customer acquisition curve.  The rank is scrambled with MOD(n * 617, 1000)
--  - 617 is coprime with 1000, so this is a bijection - which stops the early
--  cohorts from being exactly C0001..C0120 (who are all members, and would
--  make the early years implausibly member-heavy).
--
--  The modulus is a FIXED 1000, not COUNT(*).  617 is coprime with 1000, so
--  the mapping is a bijection at exactly that size.  Deriving the modulus
--  from COUNT(*) would look tidier but would reshuffle every customer's
--  cohort the moment one customer is added - and insert_dirty_data.sql adds
--  C9901.  Orders generated under the old cohorts would then appear to
--  predate their customers and validation check 1 would start failing on
--  data that was correct when it was written.
--
--  Cumulative customers active by year:
--      2016  120     2020  490   (slow year)
--      2017  210     2021  590
--      2018  310     2022  770
--      2019  420     2023 1000
INSERT INTO gen_customer_cohort (CustomerID, FirstYear)
SELECT c.CustomerID,
       CASE
           WHEN scrambled <= 120  THEN 2016
           WHEN scrambled <= 210  THEN 2017
           WHEN scrambled <= 310  THEN 2018
           WHEN scrambled <= 420  THEN 2019
           WHEN scrambled <= 490  THEN 2020
           WHEN scrambled <= 590  THEN 2021
           WHEN scrambled <= 770  THEN 2022
           ELSE                        2023
       END
FROM ( SELECT CustomerID,
              MOD(ROW_NUMBER() OVER (ORDER BY CustomerID) * 617, 1000) + 1
                  AS scrambled
       FROM   Customer ) c;

COMMIT;

SET LINESIZE 140
COLUMN what FORMAT A34
PROMPT
PROMPT === EXISTENCE-YEAR TABLES BUILT ===
SELECT 'gen_item_launch'      AS what, COUNT(*) AS rows_built FROM gen_item_launch
UNION ALL SELECT 'gen_branch_open',        COUNT(*) FROM gen_branch_open
UNION ALL SELECT 'gen_customer_cohort',    COUNT(*) FROM gen_customer_cohort;

PROMPT
PROMPT === CUSTOMER ACQUISITION CURVE (cumulative) ===
SELECT FirstYear,
       COUNT(*) AS acquired_this_year,
       SUM(COUNT(*)) OVER (ORDER BY FirstYear) AS cumulative_customers
FROM   gen_customer_cohort
GROUP  BY FirstYear
ORDER  BY FirstYear;


-- ----------------------------------------------------------------------------
--  PART 2 : PROMOTIONS FOR 2016-2023
--
--  Four campaigns a year, anchored to the real festive calendar:
--     CNY          - late Jan / Feb, date shifts each year
--     Hari Raya    - runs the four weeks before Eid, which moves ~11 days
--                    earlier each year
--     Merdeka      - late August
--     Year End     - late November into December
--
--  PM013 .. PM044.  All carry Status 'Inactive' because every one of them
--  has already ended.
-- ----------------------------------------------------------------------------
DECLARE
    TYPE t_date IS TABLE OF DATE INDEX BY PLS_INTEGER;
    v_cny_start  t_date;   -- CNY campaign opens ~3 weeks before the day
    v_raya_start t_date;   -- Raya campaign opens ~4 weeks before Eid

    v_id       VARCHAR2(5);
    v_existing NUMBER;
    v_made     NUMBER := 0;

    PROCEDURE add_promo (p_seq   IN NUMBER,
                         p_name  IN VARCHAR2,
                         p_type  IN VARCHAR2,
                         p_value IN NUMBER,
                         p_start IN DATE,
                         p_days  IN NUMBER) IS
        v_pid VARCHAR2(5) := 'PM' || LPAD(p_seq, 3, '0');
        v_n   NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_n FROM Promotion WHERE PromotionID = v_pid;
        IF v_n = 0 THEN
            INSERT INTO Promotion (PromotionID, PromoName, DiscountType,
                                   DiscountValue, StartDate, EndDate, Status)
            VALUES (v_pid, p_name, p_type, p_value,
                    p_start, p_start + p_days, 'Inactive');
            v_made := v_made + 1;
        END IF;
    END add_promo;
BEGIN
    -- Chinese New Year day, 2016-2023
    v_cny_start(2016) := DATE '2016-01-18';   -- CNY 08 Feb
    v_cny_start(2017) := DATE '2017-01-07';   -- CNY 28 Jan
    v_cny_start(2018) := DATE '2018-01-26';   -- CNY 16 Feb
    v_cny_start(2019) := DATE '2019-01-15';   -- CNY 05 Feb
    v_cny_start(2020) := DATE '2020-01-04';   -- CNY 25 Jan
    v_cny_start(2021) := DATE '2021-01-22';   -- CNY 12 Feb
    v_cny_start(2022) := DATE '2022-01-11';   -- CNY 01 Feb
    v_cny_start(2023) := DATE '2023-01-01';   -- CNY 22 Jan

    -- Four weeks before Eid al-Fitr, 2016-2023
    v_raya_start(2016) := DATE '2016-06-08';  -- Raya 06 Jul
    v_raya_start(2017) := DATE '2017-05-28';  -- Raya 25 Jun
    v_raya_start(2018) := DATE '2018-05-18';  -- Raya 15 Jun
    v_raya_start(2019) := DATE '2019-05-08';  -- Raya 05 Jun
    v_raya_start(2020) := DATE '2020-04-26';  -- Raya 24 May
    v_raya_start(2021) := DATE '2021-04-15';  -- Raya 13 May
    v_raya_start(2022) := DATE '2022-04-04';  -- Raya 02 May
    v_raya_start(2023) := DATE '2023-03-25';  -- Raya 22 Apr

    FOR y IN 2016 .. 2023 LOOP
        -- Sequence numbers 13,14,15,16 for 2016; 17..20 for 2017; and so on.
        add_promo( 13 + (y - 2016) * 4 + 0,
                   'Chinese New Year Mega Sale ' || y,
                   'Percentage', 10, v_cny_start(y), 34 );

        add_promo( 13 + (y - 2016) * 4 + 1,
                   'Hari Raya Aidilfitri Savers ' || y,
                   'Percentage', 15, v_raya_start(y), 34 );

        add_promo( 13 + (y - 2016) * 4 + 2,
                   'Merdeka Month Special ' || y,
                   'Fixed', 3, TO_DATE(y || '-08-16', 'YYYY-MM-DD'), 29 );

        add_promo( 13 + (y - 2016) * 4 + 3,
                   'Year End Grocery Clearance ' || y,
                   'Percentage', 12, TO_DATE(y || '-11-20', 'YYYY-MM-DD'), 41 );
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Promotions inserted: ' || v_made ||
                         ' (0 means they were already present).');
END;
/


-- ----------------------------------------------------------------------------
--  PART 3 : ITEMPROMOTION LINES FOR THE NEW PROMOTIONS
--
--  About 25 items per promotion, chosen deterministically so a re-run
--  produces the same set.  Only items already launched by the promotion's
--  start year are eligible.
--
--  PromoPrice clamp:
--     Percentage v  ->  UnitPrice * (1 - v/100)
--     Fixed      v  ->  UnitPrice - LEAST(v, UnitPrice * 0.4)
--  then floored at 0.01 and capped at UnitPrice.  This guarantees
--     0 < PromoPrice <= UnitPrice
--  which satisfies chk_itempromotion_price AND keeps the warehouse's
--  chk_sales_fact_discount (discount_amt >= 0) satisfied.
-- ----------------------------------------------------------------------------
INSERT INTO ItemPromotion (ItemID, PromotionID, PromoPrice)
SELECT x.ItemID,
       x.PromotionID,
       GREATEST(
           LEAST(
               ROUND(
                   CASE x.DiscountType
                       WHEN 'Percentage'
                           THEN x.UnitPrice * (1 - x.DiscountValue / 100)
                       ELSE x.UnitPrice
                              - LEAST(x.DiscountValue, x.UnitPrice * 0.4)
                   END, 2),
               x.UnitPrice),
           0.01) AS PromoPrice
FROM (
    SELECT i.ItemID,
           i.UnitPrice,
           p.PromotionID,
           p.DiscountType,
           p.DiscountValue,
           ROW_NUMBER() OVER (
               PARTITION BY p.PromotionID
               ORDER BY MOD(TO_NUMBER(SUBSTR(i.ItemID, 2)) * 37
                            + TO_NUMBER(SUBSTR(p.PromotionID, 3)), 61),
                        i.ItemID
           ) AS pick_rank
    FROM   Promotion p
    JOIN   gen_item_launch gil
           ON  gil.LaunchYear <= EXTRACT(YEAR FROM p.StartDate)
    JOIN   Item i
           ON  i.ItemID = gil.ItemID
    -- Only stock that can actually be sold.  02_expand_orders.sql never puts
    -- a 'Pending QC' item on an order line, so attaching a promotion to one
    -- would create a row that can never match anything and would inflate the
    -- promotion-coverage figure in Task 3.
    WHERE  i.Status IN ('Active', 'Discontinued')
    AND    TO_NUMBER(SUBSTR(p.PromotionID, 3)) BETWEEN 13 AND 44
) x
WHERE  x.pick_rank <= 25
AND    NOT EXISTS (
           SELECT 1 FROM ItemPromotion ip
           WHERE  ip.ItemID = x.ItemID AND ip.PromotionID = x.PromotionID);

COMMIT;

-- ----------------------------------------------------------------------------
--  VERIFY
-- ----------------------------------------------------------------------------
COLUMN PromoName FORMAT A38
COLUMN check_name FORMAT A46
PROMPT
PROMPT === PROMOTION COVERAGE BY YEAR (expect 4 per year 2016-2023) ===
SELECT EXTRACT(YEAR FROM StartDate) AS promo_year,
       COUNT(*)                     AS campaigns,
       MIN(StartDate)               AS earliest,
       MAX(EndDate)                 AS latest
FROM   Promotion
GROUP  BY EXTRACT(YEAR FROM StartDate)
ORDER  BY promo_year;

PROMPT
PROMPT === ITEMPROMOTION SANITY (both must be 0) ===
SELECT (SELECT COUNT(*) FROM ItemPromotion ip JOIN Item i ON i.ItemID = ip.ItemID
        WHERE ip.PromoPrice > i.UnitPrice)  AS promo_above_list,
       (SELECT COUNT(*) FROM ItemPromotion WHERE PromoPrice <= 0)
                                            AS promo_not_positive
FROM   dual;

PROMPT
PROMPT === ITEMS ATTACHED PER NEW PROMOTION ===
PROMPT Up to 25 each.  Early years show fewer because fewer items had
PROMPT launched by then - that is the product-range trend, not a fault.
PROMPT More than 25 would be a fault; that list must be empty.
SELECT EXTRACT(YEAR FROM p.StartDate) AS promo_year,
       MIN(cnt) AS fewest_items, MAX(cnt) AS most_items
FROM ( SELECT PromotionID, COUNT(*) AS cnt
       FROM   ItemPromotion
       WHERE  TO_NUMBER(SUBSTR(PromotionID, 3)) BETWEEN 13 AND 44
       GROUP  BY PromotionID ) c
JOIN   Promotion p ON p.PromotionID = c.PromotionID
GROUP  BY EXTRACT(YEAR FROM p.StartDate)
ORDER  BY promo_year;

PROMPT
PROMPT === OVER-ATTACHED PROMOTIONS (must be 0 rows) ===
SELECT PromotionID, COUNT(*) AS items_attached
FROM   ItemPromotion
WHERE  TO_NUMBER(SUBSTR(PromotionID, 3)) BETWEEN 13 AND 44
GROUP  BY PromotionID
HAVING COUNT(*) > 25
ORDER  BY PromotionID;

PROMPT
PROMPT === DONE.  Next: 02_expand_orders.sql ===
