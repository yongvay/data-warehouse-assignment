-- ============================================================================
--  02_expand_orders.sql
--  RUN AS THE ADM (OPERATIONAL) USER.  RUN AFTER 01_expand_promotions.sql.
--
--      SQL> @"Data Expansion\02_expand_orders.sql"
--
--  Generates transaction history for 2016 onwards so the warehouse spans a
--  full decade instead of two and a half years.
--
--  ADDITIVE ONLY.  Not one existing row is updated or deleted.  The 2,000
--  orders already in the source keep their dates, their keys and their
--  children.  For 2024-2026 the generator tops the year up to a target and
--  adds only the shortfall, so re-running cannot double-count.
--
--  DERIVED VALUES ARE LEFT TO THE SOURCE'S OWN TRIGGERS.  This script never
--  supplies OrderDetails.UnitPrice or Subtotal, Orders.TotalAmount,
--  Payment.Amount, ReturnDetails.RefundAmount, Returns.TotalRefundAmount,
--  PointTransaction.Point for Earn rows, or Member.PointsBalance.  Every one
--  of those is computed by trg_* exactly as it is for the existing data, so
--  generated rows are indistinguishable in structure from hand-written ones.
--  The consequence is that order lines are priced at the item's CURRENT list
--  price - there is no historical price drift.  Introducing one would mean
--  disabling trg_orderdetails_price, which would also disable the Subtotal
--  derivation that chk_orderdetails_subtotal depends on.  Not worth it.
--
--  RESERVED IDS.  Task 2(b)'s insert_dirty_data.sql hardcodes ORD02001,
--  ORD02002, DLV00642, DLV00643, RET00135 and RET00136.  The sequences are
--  wound past those values before generation so nothing collides.
--
--  RESUMABLE AND IDEMPOTENT, committing once per month.
--
--  Each year's work is computed as  target - orders already present, so the
--  generator naturally converges:
--    - run it twice and the second run adds nothing
--    - run it after a partial failure and it adds only the shortfall
--
--  It commits per month rather than holding one transaction for the whole
--  run.  A single transaction would be tidier, but ~30,000 inserts plus the
--  trigger updates behind them can exhaust the small UNDO tablespace on an
--  Oracle XE instance and fail with ORA-30036.  Per-month commits keep undo
--  bounded, and the resumability above makes a partial run harmless.
--
--  NOTE ON ERRORS: this script does NOT use WHENEVER SQLERROR EXIT.  That
--  directive closes SQL*Plus on any error, which looks exactly like a crash
--  and takes the error message with it.  Errors are reported and the session
--  stays open so you can read them.
-- ============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET FEEDBACK ON
SET TIMING ON
WHENEVER SQLERROR CONTINUE

-- ----------------------------------------------------------------------------
--  PREREQUISITE CHECK.
--  This has to be its own block.  The main block references
--  gen_customer_cohort statically, so if 01 has not been run the main block
--  fails at COMPILE time with PLS-00201 and any friendly message inside it
--  would never execute.  Checking dynamically here gets the useful error out
--  first.  If you see the message below, stop and run 01 - everything after
--  it will fail too.
-- ----------------------------------------------------------------------------
DECLARE
    v_n NUMBER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM gen_customer_cohort' INTO v_n;
    IF v_n = 0 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'gen_customer_cohort is empty - run 01_expand_promotions.sql first.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -942 THEN
            RAISE_APPLICATION_ERROR(-20001,
                'gen_customer_cohort does not exist - run ' ||
                '01_expand_promotions.sql first.');
        ELSE
            RAISE;
        END IF;
END;
/

DECLARE
    ---------------------------------------------------------------------------
    -- CONFIGURATION.  Everything tunable lives here.
    ---------------------------------------------------------------------------
    c_first_year  CONSTANT PLS_INTEGER := 2016;
    c_today       CONSTANT DATE        := TRUNC(SYSDATE);
    c_last_year   CONSTANT PLS_INTEGER := EXTRACT(YEAR FROM TRUNC(SYSDATE));

    -- No order is generated later than YESTERDAY.  Deliveries and returns are
    -- dated at least one whole day after their order, so an order placed at
    -- 19:43 today would need a delivery dated "today at 00:00" once the day
    -- is capped - which is BEFORE the order.  Truncating comparisons hide
    -- that inversion; the ETL that does not truncate would produce a negative
    -- delivery_lead_days and abort on chk_delivery_fact_lead.  Stopping a day
    -- short removes the case entirely.
    c_cutoff      CONSTANT DATE        := TRUNC(SYSDATE) - 1;

    c_return_rate CONSTANT NUMBER := 0.067;  -- share of orders that get a return
    c_deliv_rate  CONSTANT NUMBER := 0.85;   -- share of eligible online orders
    c_redeem_rate CONSTANT NUMBER := 0.09;   -- share of members who redeem

    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    -- TARGET ORDERS PER YEAR (total, not incremental).
    -- Growth from 250 to ~1350 with a deliberate 2020-2021 pandemic dip, then
    -- recovery.  2023 lands just above the existing 2024 volume so the
    -- generated years flow into the real ones without a visible seam.
    v_target      t_num;

    -- MONTHLY SEASONALITY.  CNY in Jan/Feb and the year-end run in Nov/Dec are
    -- the two peaks; the mid-year lull sits in Jul/Aug.
    v_month_w     t_num;

    ---------------------------------------------------------------------------
    -- REFERENCE DATA, LOADED ONCE
    ---------------------------------------------------------------------------
    TYPE t_vc5   IS TABLE OF VARCHAR2(5) INDEX BY PLS_INTEGER;
    TYPE t_vc4   IS TABLE OF VARCHAR2(4) INDEX BY PLS_INTEGER;
    TYPE t_int   IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;
    TYPE t_flag  IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(5);
    TYPE t_addr  IS TABLE OF VARCHAR2(5) INDEX BY VARCHAR2(5);
    TYPE t_used  IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(5);

    v_cust_id     t_vc5;   v_cust_year  t_int;   v_cust_n  PLS_INTEGER := 0;
    v_item_id     t_vc5;   v_item_year  t_int;
    v_item_lastyr t_int;                          v_item_n  PLS_INTEGER := 0;
    v_brch_id     t_vc5;   v_brch_year  t_int;   v_brch_n  PLS_INTEGER := 0;
    v_comp_id     t_vc4;                          v_comp_n  PLS_INTEGER := 0;
    v_reas_id     t_vc4;                          v_reas_n  PLS_INTEGER := 0;

    v_is_member   t_flag;  -- CustomerID -> 1 when the customer is a Member
    v_addr_of     t_addr;  -- CustomerID -> one of that member's AddressID values

    -- Per-year eligible index lists, rebuilt at the top of each year
    v_ec          t_int;   v_ec_n    PLS_INTEGER := 0;   -- eligible customers
    v_ei          t_int;   v_ei_n    PLS_INTEGER := 0;   -- eligible items
    v_eb          t_int;   v_eb_n    PLS_INTEGER := 0;   -- eligible branches

    ---------------------------------------------------------------------------
    -- WORKING STATE
    ---------------------------------------------------------------------------
    v_order_no     VARCHAR2(8);
    v_delivery_id  VARCHAR2(8);
    v_return_id    VARCHAR2(8);
    v_payment_id   VARCHAR2(8);
    v_pt_id        VARCHAR2(7);

    v_cust         VARCHAR2(5);
    v_branch       VARCHAR2(5);
    v_type         VARCHAR2(10);

    -- Values are computed into these locals before every INSERT.  A function
    -- declared in a PL/SQL block (rnd, pick_line_count) CANNOT be called from
    -- inside a SQL statement, and a VALUES list is a SQL context - doing so
    -- fails at compile time with PLS-00231.  Packaged functions such as
    -- DBMS_RANDOM.VALUE are fine there; locally declared ones are not.
    v_deliv_date   DATE;
    v_deliv_charge NUMBER(6,2);
    v_comp         VARCHAR2(4);
    v_addr         VARCHAR2(5);
    v_ret_date     DATE;
    v_ret_stat     VARCHAR2(10);
    v_ret_qty      PLS_INTEGER;
    v_reason       VARCHAR2(4);
    v_odt          DATE;
    v_day          PLS_INTEGER;
    v_hour         PLS_INTEGER;
    v_minute       PLS_INTEGER;

    v_month_start  DATE;
    v_month_end    DATE;
    v_days_in_mth  PLS_INTEGER;

    v_line_item    t_vc5;
    v_line_qty     t_int;
    v_lines        PLS_INTEGER;
    v_used         t_used;

    v_existing     PLS_INTEGER;
    v_to_add       PLS_INTEGER;
    v_weight_sum   NUMBER;
    v_month_add    PLS_INTEGER;
    v_alloc        PLS_INTEGER;

    v_online_p     NUMBER;
    v_r            NUMBER;
    v_tries        PLS_INTEGER;
    v_idx          PLS_INTEGER;

    v_orders_made  PLS_INTEGER := 0;
    v_lines_made   PLS_INTEGER := 0;
    v_deliv_made   PLS_INTEGER := 0;
    v_ret_made     PLS_INTEGER := 0;
    v_pt_made      PLS_INTEGER := 0;

    v_guard        PLS_INTEGER;
    v_seqval       NUMBER;

    ---------------------------------------------------------------------------
    -- HELPERS
    ---------------------------------------------------------------------------
    -- Random integer in [p_lo, p_hi] inclusive.
    FUNCTION rnd (p_lo PLS_INTEGER, p_hi PLS_INTEGER) RETURN PLS_INTEGER IS
    BEGIN
        IF p_hi <= p_lo THEN RETURN p_lo; END IF;
        RETURN TRUNC(DBMS_RANDOM.VALUE(p_lo, p_hi + 1));
    END rnd;

    -- Number of order lines: 1..6, mean about 2.75, matching the existing
    -- 5602 lines across 2000 orders.
    FUNCTION pick_line_count RETURN PLS_INTEGER IS
        r NUMBER := DBMS_RANDOM.VALUE(0, 1);
    BEGIN
        IF    r < 0.25 THEN RETURN 1;
        ELSIF r < 0.50 THEN RETURN 2;
        ELSIF r < 0.70 THEN RETURN 3;
        ELSIF r < 0.85 THEN RETURN 4;
        ELSIF r < 0.95 THEN RETURN 5;
        ELSE                RETURN 6;
        END IF;
    END pick_line_count;
BEGIN
    ---------------------------------------------------------------------------
    -- RESUME NOTICE.  Not a guard: each year adds only its shortfall, so a
    -- re-run after a partial failure fills the gap and a re-run after a
    -- complete run adds nothing.
    ---------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_guard
    FROM   Orders
    WHERE  OrderDateTime < DATE '2024-01-01';

    IF v_guard > 0 THEN
        DBMS_OUTPUT.PUT_LINE('RESUMING: ' || v_guard || ' pre-2024 orders are ' ||
            'already present. Each year will be topped up to its target.');
    END IF;

    ---------------------------------------------------------------------------
    -- DETERMINISTIC RANDOMNESS.  Every teammate who runs this gets identical
    -- data, so the figures in the report match everybody's database.
    ---------------------------------------------------------------------------
    DBMS_RANDOM.SEED(42);

    ---------------------------------------------------------------------------
    -- WIND SEQUENCES PAST THE IDS insert_dirty_data.sql HARDCODES
    ---------------------------------------------------------------------------
    -- ">=" not ">": exit having just CONSUMED the last reserved value, so the
    -- next NEXTVAL is the first free one.  With ">" the loop burns one extra
    -- value and leaves a gap in the numbering.
    LOOP
        SELECT seq_orders.NEXTVAL INTO v_seqval FROM dual;
        EXIT WHEN v_seqval >= 2002;
    END LOOP;
    LOOP
        SELECT seq_delivery.NEXTVAL INTO v_seqval FROM dual;
        EXIT WHEN v_seqval >= 643;
    END LOOP;
    LOOP
        SELECT seq_returns.NEXTVAL INTO v_seqval FROM dual;
        EXIT WHEN v_seqval >= 136;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Sequences wound past the reserved dirty-data IDs.');

    ---------------------------------------------------------------------------
    -- TARGETS AND WEIGHTS
    ---------------------------------------------------------------------------
    v_target(2016) :=  250;   v_target(2017) :=  330;
    v_target(2018) :=  430;   v_target(2019) :=  540;
    v_target(2020) :=  330;   -- pandemic dip
    v_target(2021) :=  450;   -- partial recovery
    v_target(2022) :=  680;   v_target(2023) :=  900;
    v_target(2024) := 1100;   v_target(2025) := 1350;
    v_target(2026) := 1000;   -- part year, Jan to today

    v_month_w(1)  := 1.20;  v_month_w(2)  := 1.30;  v_month_w(3)  := 1.00;
    v_month_w(4)  := 1.05;  v_month_w(5)  := 1.05;  v_month_w(6)  := 1.05;
    v_month_w(7)  := 0.90;  v_month_w(8)  := 0.95;  v_month_w(9)  := 0.95;
    v_month_w(10) := 1.05;  v_month_w(11) := 1.10;  v_month_w(12) := 1.30;

    ---------------------------------------------------------------------------
    -- LOAD REFERENCE DATA
    ---------------------------------------------------------------------------
    FOR r IN (SELECT c.CustomerID, g.FirstYear
              FROM   Customer c
              JOIN   gen_customer_cohort g ON g.CustomerID = c.CustomerID
              ORDER  BY c.CustomerID) LOOP
        v_cust_n := v_cust_n + 1;
        v_cust_id(v_cust_n)   := r.CustomerID;
        v_cust_year(v_cust_n) := r.FirstYear;
    END LOOP;

    FOR r IN (SELECT MemberID FROM Member) LOOP
        v_is_member(r.MemberID) := 1;
    END LOOP;

    -- One saved address per member, chosen deterministically.
    FOR r IN (SELECT MemberID, MIN(AddressID) AS AddressID
              FROM   MemberAddress GROUP BY MemberID) LOOP
        v_addr_of(r.MemberID) := r.AddressID;
    END LOOP;

    -- Items.  'Pending QC' stock is never sold.  'Discontinued' lines are
    -- sellable only up to 2021, after which they are off the shelf.
    FOR r IN (SELECT i.ItemID, g.LaunchYear, i.Status
              FROM   Item i
              JOIN   gen_item_launch g ON g.ItemID = i.ItemID
              WHERE  i.Status IN ('Active', 'Discontinued')
              ORDER  BY i.ItemID) LOOP
        v_item_n := v_item_n + 1;
        v_item_id(v_item_n)   := r.ItemID;
        v_item_year(v_item_n) := r.LaunchYear;
        v_item_lastyr(v_item_n) :=
            CASE WHEN r.Status = 'Discontinued' THEN 2021 ELSE 9999 END;
    END LOOP;

    FOR r IN (SELECT b.BranchID, g.OpenYear
              FROM   Branch b
              JOIN   gen_branch_open g ON g.BranchID = b.BranchID
              ORDER  BY b.BranchID) LOOP
        v_brch_n := v_brch_n + 1;
        v_brch_id(v_brch_n)   := r.BranchID;
        v_brch_year(v_brch_n) := r.OpenYear;
    END LOOP;

    FOR r IN (SELECT DeliveryCompanyID FROM DeliveryCompany
              ORDER BY DeliveryCompanyID) LOOP
        v_comp_n := v_comp_n + 1;
        v_comp_id(v_comp_n) := r.DeliveryCompanyID;
    END LOOP;

    FOR r IN (SELECT ReasonID FROM ReturnReason ORDER BY ReasonID) LOOP
        v_reas_n := v_reas_n + 1;
        v_reas_id(v_reas_n) := r.ReasonID;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Reference data loaded: ' || v_cust_n ||
        ' customers, ' || v_item_n || ' sellable items, ' ||
        v_brch_n || ' branches.');

    ---------------------------------------------------------------------------
    -- MAIN GENERATION LOOP
    ---------------------------------------------------------------------------
    FOR y IN c_first_year .. c_last_year LOOP

        -- Eligible customers for this year
        v_ec_n := 0;
        FOR i IN 1 .. v_cust_n LOOP
            IF v_cust_year(i) <= y THEN
                v_ec_n := v_ec_n + 1;  v_ec(v_ec_n) := i;
            END IF;
        END LOOP;

        -- Eligible items for this year
        v_ei_n := 0;
        FOR i IN 1 .. v_item_n LOOP
            IF v_item_year(i) <= y AND v_item_lastyr(i) >= y THEN
                v_ei_n := v_ei_n + 1;  v_ei(v_ei_n) := i;
            END IF;
        END LOOP;

        -- Branches open in this year
        v_eb_n := 0;
        FOR i IN 1 .. v_brch_n LOOP
            IF v_brch_year(i) <= y THEN
                v_eb_n := v_eb_n + 1;  v_eb(v_eb_n) := i;
            END IF;
        END LOOP;

        IF v_ec_n = 0 OR v_ei_n = 0 OR v_eb_n = 0 THEN
            DBMS_OUTPUT.PUT_LINE(y || ': SKIPPED - nothing eligible ' ||
                '(customers ' || v_ec_n || ', items ' || v_ei_n ||
                ', branches ' || v_eb_n || ').');
            CONTINUE;
        END IF;

        -- Reading a missing subscript from an associative array raises
        -- NO_DATA_FOUND - NVL cannot rescue it - so test EXISTS first.  This
        -- is what keeps the script working if it is ever run in a year with
        -- no target defined above.
        IF NOT v_target.EXISTS(y) THEN
            DBMS_OUTPUT.PUT_LINE(y || ': no target defined, skipped.');
            CONTINUE;
        END IF;

        -- How many orders does this year still need?
        SELECT COUNT(*) INTO v_existing
        FROM   Orders
        WHERE  OrderDateTime >= TO_DATE(y   || '-01-01', 'YYYY-MM-DD')
        AND    OrderDateTime <  TO_DATE(y+1 || '-01-01', 'YYYY-MM-DD');

        v_to_add := GREATEST(v_target(y) - v_existing, 0);

        DBMS_OUTPUT.PUT_LINE(y || ': target ' || v_target(y) ||
            ', existing ' || v_existing || ', generating ' || v_to_add ||
            '  [customers ' || v_ec_n || ', items ' || v_ei_n ||
            ', branches ' || v_eb_n || ']');

        IF v_to_add = 0 THEN
            CONTINUE;
        END IF;

        -- Online share climbs from 18% in 2016 to about 55% by 2026.
        v_online_p := LEAST(0.18 + (y - c_first_year) * 0.037, 0.60);

        -- Total weight of the months that are actually in range (the current
        -- year is only partly elapsed).
        v_weight_sum := 0;
        FOR m IN 1 .. 12 LOOP
            IF TO_DATE(y || '-' || LPAD(m,2,'0') || '-01', 'YYYY-MM-DD')
               <= c_cutoff THEN
                v_weight_sum := v_weight_sum + v_month_w(m);
            END IF;
        END LOOP;

        IF v_weight_sum = 0 THEN
            CONTINUE;
        END IF;

        v_alloc := 0;

        FOR m IN 1 .. 12 LOOP
            v_month_start := TO_DATE(y || '-' || LPAD(m,2,'0') || '-01',
                                     'YYYY-MM-DD');
            EXIT WHEN v_month_start > c_cutoff;

            v_month_end   := LEAST(LAST_DAY(v_month_start), c_cutoff);
            v_days_in_mth := TO_NUMBER(TO_CHAR(v_month_end, 'DD'));
            EXIT WHEN v_days_in_mth < 1;

            -- Last in-range month absorbs the rounding remainder.
            IF m = 12 OR ADD_MONTHS(v_month_start, 1) > c_cutoff THEN
                v_month_add := v_to_add - v_alloc;
            ELSE
                v_month_add := ROUND(v_to_add * v_month_w(m) / v_weight_sum);
            END IF;
            v_month_add := GREATEST(v_month_add, 0);
            v_alloc     := v_alloc + v_month_add;

            FOR k IN 1 .. v_month_add LOOP

                ------------------------------------------------------------
                -- 1. ORDER HEADER
                ------------------------------------------------------------
                -- Day of month, with weekends favoured.  Bounded retries, so
                -- this can never spin.
                v_tries := 0;
                LOOP
                    v_day   := rnd(1, v_days_in_mth);
                    v_tries := v_tries + 1;
                    EXIT WHEN v_tries >= 3
                          OR  TO_CHAR(v_month_start + v_day - 1, 'DY',
                                      'NLS_DATE_LANGUAGE=ENGLISH')
                              IN ('SAT','SUN')
                          OR  DBMS_RANDOM.VALUE(0,1) < 0.72;
                END LOOP;

                -- Trading hours, evening-weighted.
                IF DBMS_RANDOM.VALUE(0,1) < 0.55 THEN
                    v_hour := rnd(17, 21);
                ELSE
                    v_hour := rnd(10, 22);
                END IF;
                v_minute := rnd(0, 59);

                v_odt := v_month_start + (v_day - 1)
                         + v_hour / 24 + v_minute / 1440;

                -- Belt and braces.  v_days_in_mth already stops at the cutoff,
                -- so this should never fire; if it ever does, clamp WITHIN the
                -- same month rather than subtracting a day, which could push
                -- the order into the previous month - or, on 1 January, into
                -- the previous year, wrecking the per-year accounting and the
                -- customer-cohort check.
                IF v_odt > c_cutoff + 1 THEN
                    v_odt := v_month_start + (v_days_in_mth - 1) + 12/24;
                END IF;

                v_idx    := v_ec(rnd(1, v_ec_n));
                v_cust   := v_cust_id(v_idx);
                v_branch := v_brch_id(v_eb(rnd(1, v_eb_n)));
                v_type   := CASE WHEN DBMS_RANDOM.VALUE(0,1) < v_online_p
                                 THEN 'Online' ELSE 'Walk-in' END;

                SELECT 'ORD' || LPAD(seq_orders.NEXTVAL, 5, '0')
                INTO   v_order_no FROM dual;

                INSERT INTO Orders (OrderNo, OrderType, OrderDateTime,
                                    CustomerID, BranchID)
                VALUES (v_order_no, v_type, v_odt, v_cust, v_branch);

                v_orders_made := v_orders_made + 1;

                ------------------------------------------------------------
                -- 2. ORDER LINES.  Items must be distinct: pk_orderdetails is
                --    (OrderNo, ItemID).  UnitPrice and Subtotal are left to
                --    trg_orderdetails_price.
                ------------------------------------------------------------
                v_used.DELETE;
                v_lines := LEAST(pick_line_count, v_ei_n);

                FOR n IN 1 .. v_lines LOOP
                    v_tries := 0;
                    LOOP
                        v_idx   := v_ei(rnd(1, v_ei_n));
                        v_tries := v_tries + 1;
                        EXIT WHEN NOT v_used.EXISTS(v_item_id(v_idx))
                               OR v_tries >= 12;
                    END LOOP;

                    IF NOT v_used.EXISTS(v_item_id(v_idx)) THEN
                        v_used(v_item_id(v_idx)) := 1;

                        v_line_item(n) := v_item_id(v_idx);
                        v_line_qty(n)  := rnd(1, 5);

                        INSERT INTO OrderDetails (OrderNo, ItemID, Quantity)
                        VALUES (v_order_no, v_line_item(n), v_line_qty(n));

                        v_lines_made := v_lines_made + 1;
                    ELSE
                        v_line_item(n) := NULL;   -- gave up on a distinct item
                    END IF;
                END LOOP;

                ------------------------------------------------------------
                -- 3. PAYMENT.  Must come after the lines: trg_payment_amount
                --    copies Orders.TotalAmount, and chk_payment_amount
                --    requires it to be greater than zero.
                ------------------------------------------------------------
                SELECT 'PAY' || LPAD(seq_payment.NEXTVAL, 5, '0')
                INTO   v_payment_id FROM dual;

                INSERT INTO Payment (PaymentID, PaymentDate, Status, OrderNo)
                VALUES (v_payment_id, TRUNC(v_odt),
                        CASE WHEN DBMS_RANDOM.VALUE(0,1) < 0.97
                             THEN 'Paid' ELSE 'Failed' END,
                        v_order_no);

                ------------------------------------------------------------
                -- 4. DELIVERY.  Online orders only, and only for members who
                --    have a saved address - Delivery.AddressID references
                --    MemberAddress, which references Member.
                ------------------------------------------------------------
                IF v_type = 'Online'
                   AND v_is_member.EXISTS(v_cust)
                   AND v_addr_of.EXISTS(v_cust)
                   AND DBMS_RANDOM.VALUE(0,1) < c_deliv_rate THEN

                    SELECT 'DLV' || LPAD(seq_delivery.NEXTVAL, 5, '0')
                    INTO   v_delivery_id FROM dual;

                    -- Everything is worked out into locals FIRST.  A function
                    -- declared inside a PL/SQL block cannot be called from a
                    -- SQL statement, and a VALUES list is SQL: calling rnd()
                    -- there fails with PLS-00231.
                    v_deliv_date   := LEAST(TRUNC(v_odt) + rnd(1, 7), c_today);
                    v_deliv_charge := ROUND(DBMS_RANDOM.VALUE(0, 15), 2);
                    v_comp         := v_comp_id(rnd(1, v_comp_n));
                    v_addr         := v_addr_of(v_cust);

                    IF DBMS_RANDOM.VALUE(0,1) < 0.92 THEN
                        -- Delivered: dated after the order, never in the future
                        INSERT INTO Delivery (DeliveryID, DeliveryCharge,
                                              DeliveryDate, Status, OrderNo,
                                              DeliveryCompanyID, AddressID)
                        VALUES (v_delivery_id, v_deliv_charge, v_deliv_date,
                                'Delivered', v_order_no, v_comp, v_addr);
                    ELSE
                        -- Cancelled: no delivery date, which is exactly the
                        -- case the warehouse routes to date_key -1
                        INSERT INTO Delivery (DeliveryID, DeliveryCharge,
                                              DeliveryDate, Status, OrderNo,
                                              DeliveryCompanyID, AddressID)
                        VALUES (v_delivery_id, v_deliv_charge, NULL,
                                'Cancelled', v_order_no, v_comp, v_addr);
                    END IF;

                    v_deliv_made := v_deliv_made + 1;
                END IF;

                ------------------------------------------------------------
                -- 5. POINTS EARNED.  Members only.  Point is computed by
                --    trg_pointtrans_point from Orders.TotalAmount, so this
                --    must also come after the lines.
                ------------------------------------------------------------
                IF v_is_member.EXISTS(v_cust) THEN
                    SELECT 'PT' || LPAD(seq_pointtrans.NEXTVAL, 5, '0')
                    INTO   v_pt_id FROM dual;

                    INSERT INTO PointTransaction (PointTransID, TransType,
                                                  TransDate, MemberID, OrderNo)
                    VALUES (v_pt_id, 'Earn', TRUNC(v_odt), v_cust, v_order_no);

                    v_pt_made := v_pt_made + 1;
                END IF;

                ------------------------------------------------------------
                -- 6. RETURN.  Dated after the order and never in the future,
                --    and every return line references a real order line,
                --    because fk_returndetails_orderline is a composite FK on
                --    (OrderNo, ItemID).
                ------------------------------------------------------------
                IF DBMS_RANDOM.VALUE(0,1) < c_return_rate
                   AND v_line_item.EXISTS(1)
                   AND v_line_item(1) IS NOT NULL THEN

                    SELECT 'RET' || LPAD(seq_returns.NEXTVAL, 5, '0')
                    INTO   v_return_id FROM dual;

                    -- Locals first: rnd() cannot appear in a VALUES list.
                    v_ret_date := LEAST(TRUNC(v_odt) + rnd(1, 14), c_today);
                    v_r        := DBMS_RANDOM.VALUE(0, 1);
                    v_ret_stat := CASE WHEN v_r < 0.80 THEN 'Refunded'
                                       WHEN v_r < 0.92 THEN 'Approved'
                                       ELSE 'Rejected' END;

                    INSERT INTO Returns (ReturnID, ReturnDate, Status, OrderNo)
                    VALUES (v_return_id, v_ret_date, v_ret_stat, v_order_no);

                    -- One or two lines, never more than were actually sold.
                    FOR n IN 1 .. LEAST(v_lines, 2) LOOP
                        IF v_line_item.EXISTS(n)
                           AND v_line_item(n) IS NOT NULL THEN
                            v_ret_qty  := rnd(1, LEAST(v_line_qty(n), 3));
                            v_reason   := v_reas_id(rnd(1, v_reas_n));

                            INSERT INTO ReturnDetails
                                (ReturnID, OrderNo, ItemID,
                                 QuantityReturned, ReasonID)
                            VALUES (v_return_id, v_order_no, v_line_item(n),
                                    v_ret_qty, v_reason);
                        END IF;
                    END LOOP;

                    v_ret_made := v_ret_made + 1;
                END IF;

                v_line_item.DELETE;
                v_line_qty.DELETE;

            END LOOP;   -- orders in month

            -- Commit per month.  Keeps undo bounded on a small instance; the
            -- shortfall arithmetic makes a partial run safe to resume.
            COMMIT;
        END LOOP;       -- month
    END LOOP;           -- year

    ---------------------------------------------------------------------------
    -- POINT REDEMPTIONS.
    --
    -- Run as a final pass, after every Earn row is in, so Member.PointsBalance
    -- is at its maximum when chk_member_points is evaluated.  A redemption is
    -- capped at a quarter of the balance, so the balance can never go
    -- negative and trg_member_balance always succeeds.
    --
    -- chk_pointtrans_order requires OrderNo to be NULL on a Redeem row.  These
    -- are the transactions that land on branch_key = -1 in the warehouse,
    -- because a redemption has no order and therefore no branch.
    ---------------------------------------------------------------------------
    DECLARE
        v_amount   PLS_INTEGER;
        v_redeemed PLS_INTEGER := 0;
    BEGIN
        -- Members who already have a Redeem row are skipped, so a re-run
        -- cannot pile redemption on redemption.
        FOR r IN (SELECT m.MemberID, m.PointsBalance,
                         (SELECT MAX(pt.TransDate)
                          FROM   PointTransaction pt
                          WHERE  pt.MemberID = m.MemberID
                          AND    pt.TransType = 'Earn') AS last_earn
                  FROM   Member m
                  WHERE  m.PointsBalance >= 400
                  AND    NOT EXISTS (SELECT 1 FROM PointTransaction pt2
                                     WHERE  pt2.MemberID  = m.MemberID
                                     AND    pt2.TransType = 'Redeem')
                  ORDER  BY m.MemberID) LOOP

            IF DBMS_RANDOM.VALUE(0,1) < c_redeem_rate
               AND r.last_earn IS NOT NULL THEN

                v_amount := GREATEST(TRUNC(r.PointsBalance * 0.25), 1);

                SELECT 'PT' || LPAD(seq_pointtrans.NEXTVAL, 5, '0')
                INTO   v_pt_id FROM dual;

                INSERT INTO PointTransaction (PointTransID, TransType, Point,
                                              TransDate, MemberID, OrderNo)
                VALUES (v_pt_id, 'Redeem', v_amount,
                        LEAST(r.last_earn, c_today), r.MemberID, NULL);

                v_redeemed := v_redeemed + 1;
            END IF;
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('Point redemptions created: ' || v_redeemed);
    END;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('===========================================');
    DBMS_OUTPUT.PUT_LINE('GENERATION COMPLETE');
    DBMS_OUTPUT.PUT_LINE('  Orders        : ' || v_orders_made);
    DBMS_OUTPUT.PUT_LINE('  Order lines   : ' || v_lines_made);
    DBMS_OUTPUT.PUT_LINE('  Deliveries    : ' || v_deliv_made);
    DBMS_OUTPUT.PUT_LINE('  Returns       : ' || v_ret_made);
    DBMS_OUTPUT.PUT_LINE('  Earn point tx : ' || v_pt_made);
    DBMS_OUTPUT.PUT_LINE('===========================================');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('=======================================');
        DBMS_OUTPUT.PUT_LINE('FAILED after ' || v_orders_made || ' orders.');
        DBMS_OUTPUT.PUT_LINE('ERROR : ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('WHERE : ' ||
            SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 800));
        DBMS_OUTPUT.PUT_LINE('The uncommitted month was rolled back. Months ' ||
            'already committed are kept - just fix the cause and re-run, ' ||
            'the script tops up whatever is missing.');
        DBMS_OUTPUT.PUT_LINE('=======================================');
        RAISE;
END;
/

SET TIMING OFF
SET LINESIZE 140
COLUMN tbl FORMAT A20

PROMPT
PROMPT === ORDERS PER YEAR AFTER EXPANSION ===
SELECT EXTRACT(YEAR FROM OrderDateTime) AS order_year,
       COUNT(*)                         AS orders,
       COUNT(DISTINCT CustomerID)       AS active_customers,
       COUNT(DISTINCT BranchID)         AS branches_trading,
       ROUND(SUM(TotalAmount), 2)       AS revenue
FROM   Orders
GROUP  BY EXTRACT(YEAR FROM OrderDateTime)
ORDER  BY order_year;

PROMPT
PROMPT === ONLINE SHARE BY YEAR (the channel-mix trend) ===
SELECT EXTRACT(YEAR FROM OrderDateTime) AS order_year,
       COUNT(*) AS orders,
       SUM(CASE WHEN OrderType = 'Online' THEN 1 ELSE 0 END) AS online_orders,
       ROUND(100 * SUM(CASE WHEN OrderType = 'Online' THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS online_pct
FROM   Orders
GROUP  BY EXTRACT(YEAR FROM OrderDateTime)
ORDER  BY order_year;

PROMPT
PROMPT === TOTALS ===
SELECT 'Orders' AS tbl, COUNT(*) AS rows_now FROM Orders
UNION ALL SELECT 'OrderDetails',     COUNT(*) FROM OrderDetails
UNION ALL SELECT 'Payment',          COUNT(*) FROM Payment
UNION ALL SELECT 'Delivery',         COUNT(*) FROM Delivery
UNION ALL SELECT 'Returns',          COUNT(*) FROM Returns
UNION ALL SELECT 'ReturnDetails',    COUNT(*) FROM ReturnDetails
UNION ALL SELECT 'PointTransaction', COUNT(*) FROM PointTransaction;

PROMPT
PROMPT === DONE.  Next: 03_validate_source.sql ===
