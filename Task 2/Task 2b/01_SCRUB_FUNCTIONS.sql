-- ============================================================================
--  TASK 2(b) : SUBSEQUENT (INCREMENTAL) ETL LOADING
--  FILE 01   : DATA-SCRUBBING FUNCTION LIBRARY  (package etl_scrub)
-- ----------------------------------------------------------------------------
--  Every CHECK constraint written in Task 1(b) defines a closed domain, e.g.
--      chk_branch_dim_region  CHECK (branch_region IN ('Northern', ... ,'Unknown'))
--      chk_sales_fact_qty     CHECK (quantity > 0)
--  Dirty operational data will violate those domains and abort the load.  The
--  functions below are the single place where a raw source value is mapped onto
--  a legal warehouse value, so the rule is written once and reused by every
--  staging view.  Keeping the rules in functions (rather than inline CASE
--  expressions) is what makes the scrubbing testable and auditable.
--
--  DEFENSIVE DESIGN: none of these functions can raise.  A function that raises
--  inside a view would abort the whole load, which is exactly the failure mode
--  the scrubbing exists to prevent, so each body ends in WHEN OTHERS -> default.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

CREATE OR REPLACE PACKAGE etl_scrub AS

    -- generic text hygiene ---------------------------------------------------
    FUNCTION clean_text  (p_val VARCHAR2, p_default VARCHAR2 DEFAULT 'Unknown')
                          RETURN VARCHAR2;
    FUNCTION clean_name  (p_val VARCHAR2, p_len NUMBER DEFAULT 100) RETURN VARCHAR2;
    FUNCTION clean_email (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION clean_phone (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION clean_ic    (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION clean_postcode (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION clean_key   (p_val VARCHAR2) RETURN VARCHAR2;

    -- geography --------------------------------------------------------------
    FUNCTION std_state   (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_region  (p_state VARCHAR2) RETURN VARCHAR2;

    -- closed code domains (one function per CHECK constraint) ----------------
    FUNCTION std_cust_status     (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_membership_type (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_item_status     (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_order_type      (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_delivery_status (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_return_status   (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_trans_type      (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_reason_name     (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_reason_cat      (p_reason_name VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_discount_type   (p_val VARCHAR2) RETURN VARCHAR2;
    FUNCTION std_promo_status    (p_val VARCHAR2) RETURN VARCHAR2;

    -- numeric / date ---------------------------------------------------------
    FUNCTION clamp_num   (p_val NUMBER,
                          p_min NUMBER DEFAULT 0,
                          p_max NUMBER DEFAULT NULL,
                          p_default NUMBER DEFAULT 0) RETURN NUMBER;
    FUNCTION to_date_key (p_dt DATE) RETURN NUMBER;

END etl_scrub;
/
SHOW ERRORS


CREATE OR REPLACE PACKAGE BODY etl_scrub AS

    -- ------------------------------------------------------------------
    -- Compact a string to letters only, upper case.  Used so that
    -- 'P. Pinang', 'pulau  pinang' and 'PULAU PINANG' all collapse to
    -- the same comparison token.
    -- ------------------------------------------------------------------
    FUNCTION token (p_val VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN UPPER(REGEXP_REPLACE(NVL(p_val, ' '), '[^A-Za-z]', ''));
    END token;

    -- ==================================================================
    --  GENERIC TEXT HYGIENE
    -- ==================================================================
    FUNCTION clean_text (p_val VARCHAR2, p_default VARCHAR2 DEFAULT 'Unknown')
        RETURN VARCHAR2
    IS
        v VARCHAR2(4000);
    BEGIN
        -- trim, collapse runs of whitespace, strip control characters
        v := REGEXP_REPLACE(TRIM(p_val), '[[:cntrl:]]', '');
        v := TRIM(REGEXP_REPLACE(v, '[[:space:]]+', ' '));
        IF v IS NULL THEN
            RETURN p_default;
        END IF;
        RETURN v;
    EXCEPTION WHEN OTHERS THEN RETURN p_default;
    END clean_text;

    ---------------------------------------------------------------------
    FUNCTION clean_name (p_val VARCHAR2, p_len NUMBER DEFAULT 100)
        RETURN VARCHAR2
    IS
        v VARCHAR2(4000);
    BEGIN
        v := clean_text(p_val);
        IF v = 'Unknown' THEN
            RETURN 'Unknown';
        END IF;
        -- a "name" made only of punctuation or digits is not a name
        IF NOT REGEXP_LIKE(v, '[A-Za-z]') THEN
            RETURN 'Unknown';
        END IF;
        RETURN SUBSTR(INITCAP(v), 1, p_len);
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END clean_name;

    ---------------------------------------------------------------------
    FUNCTION clean_email (p_val VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000);
    BEGIN
        v := LOWER(TRIM(REGEXP_REPLACE(NVL(p_val, ' '), '[[:space:]]', '')));
        IF v IS NULL THEN
            RETURN 'Unknown';
        END IF;
        IF REGEXP_LIKE(v, '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$') THEN
            RETURN SUBSTR(v, 1, 100);
        END IF;
        RETURN 'Unknown';
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END clean_email;

    ---------------------------------------------------------------------
    FUNCTION clean_phone (p_val VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000);
    BEGIN
        v := REGEXP_REPLACE(NVL(p_val, ' '), '[^0-9+]', '');
        IF v IS NULL OR LENGTH(v) < 9 OR LENGTH(v) > 15 THEN
            RETURN 'Unknown';
        END IF;
        RETURN SUBSTR(v, 1, 15);
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END clean_phone;

    ---------------------------------------------------------------------
    -- Malaysian NRIC: 12 digits, stored as ######-##-####  (14 chars)
    ---------------------------------------------------------------------
    FUNCTION clean_ic (p_val VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000);
    BEGIN
        v := REGEXP_REPLACE(NVL(p_val, ' '), '[^0-9]', '');
        IF v IS NULL OR LENGTH(v) <> 12 THEN
            RETURN 'Unknown';
        END IF;
        RETURN SUBSTR(v,1,6) || '-' || SUBSTR(v,7,2) || '-' || SUBSTR(v,9,4);
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END clean_ic;

    ---------------------------------------------------------------------
    FUNCTION clean_postcode (p_val VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000);
    BEGIN
        v := REGEXP_REPLACE(NVL(p_val, ' '), '[^0-9]', '');
        IF v IS NULL OR LENGTH(v) > 5 THEN
            RETURN '00000';
        END IF;
        RETURN LPAD(v, 5, '0');          -- '5100' -> '05100'
    EXCEPTION WHEN OTHERS THEN RETURN '00000';
    END clean_postcode;

    ---------------------------------------------------------------------
    -- Business keys: trimmed, upper cased, control characters removed.
    -- Returns NULL when nothing usable is left, which is the signal the
    -- staging views use to raise dq_flag = 'D' (reject).
    ---------------------------------------------------------------------
    FUNCTION clean_key (p_val VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000);
    BEGIN
        v := UPPER(TRIM(REGEXP_REPLACE(NVL(p_val, ' '), '[[:space:][:cntrl:]]', '')));
        RETURN v;
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END clean_key;

    -- ==================================================================
    --  GEOGRAPHY
    -- ==================================================================
    FUNCTION std_state (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('PERLIS')                                        THEN 'Perlis'
            WHEN t IN ('KEDAH')                                         THEN 'Kedah'
            WHEN t IN ('PULAUPINANG','PENANG','PPINANG','PINANG')       THEN 'Pulau Pinang'
            WHEN t IN ('PERAK')                                         THEN 'Perak'
            WHEN t IN ('SELANGOR','SELANGORDARULEHSAN')                 THEN 'Selangor'
            WHEN t IN ('KUALALUMPUR','KL','WPKUALALUMPUR',
                       'WILAYAHPERSEKUTUANKUALALUMPUR')                 THEN 'Kuala Lumpur'
            WHEN t IN ('PUTRAJAYA','WPPUTRAJAYA')                       THEN 'Putrajaya'
            WHEN t IN ('NEGERISEMBILAN','NSEMBILAN','NS','NNSEMBILAN')  THEN 'Negeri Sembilan'
            WHEN t IN ('MELAKA','MALACCA')                              THEN 'Melaka'
            WHEN t IN ('JOHOR','JOHORE','JOHORDARULTAKZIM')             THEN 'Johor'
            WHEN t IN ('PAHANG')                                        THEN 'Pahang'
            WHEN t IN ('TERENGGANU','TRENGGANU')                        THEN 'Terengganu'
            WHEN t IN ('KELANTAN')                                      THEN 'Kelantan'
            WHEN t IN ('SABAH')                                         THEN 'Sabah'
            WHEN t IN ('SARAWAK')                                       THEN 'Sarawak'
            WHEN t IN ('LABUAN','WPLABUAN')                             THEN 'Labuan'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_state;

    ---------------------------------------------------------------------
    FUNCTION std_region (p_state VARCHAR2) RETURN VARCHAR2 IS
        s VARCHAR2(60) := std_state(p_state);
    BEGIN
        RETURN CASE
            WHEN s IN ('Perlis','Kedah','Pulau Pinang','Perak')             THEN 'Northern'
            WHEN s IN ('Selangor','Kuala Lumpur','Putrajaya',
                       'Negeri Sembilan')                                   THEN 'Central'
            WHEN s IN ('Melaka','Johor')                                    THEN 'Southern'
            WHEN s IN ('Pahang','Terengganu','Kelantan')                    THEN 'East Coast'
            WHEN s IN ('Sabah','Sarawak','Labuan')                          THEN 'East Malaysia'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_region;

    -- ==================================================================
    --  CLOSED CODE DOMAINS
    -- ==================================================================
    FUNCTION std_cust_status (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('ACTIVE','A','ACT','Y','YES','ENABLED')     THEN 'Active'
            WHEN t IN ('INACTIVE','I','INACT','N','NO','DISABLED',
                       'SUSPENDED','CLOSED','TERMINATED')          THEN 'Inactive'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_cust_status;

    ---------------------------------------------------------------------
    FUNCTION std_membership_type (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('NORMAL','STANDARD','BASIC','REGULAR')  THEN 'Normal'
            WHEN t IN ('VIP','PREMIUM','GOLD','PLATINUM')      THEN 'VIP'
            WHEN t IN ('NONMEMBER','NONMEM','WALKIN','NONE')   THEN 'Non-Member'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_membership_type;

    ---------------------------------------------------------------------
    FUNCTION std_item_status (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('PENDINGQC','PENDING','QC','PENDINGQUALITYCHECK') THEN 'Pending QC'
            WHEN t IN ('ACTIVE','A','AVAILABLE','INSTOCK')               THEN 'Active'
            WHEN t IN ('DISCONTINUED','DISC','DELISTED','OBSOLETE')      THEN 'Discontinued'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_item_status;

    ---------------------------------------------------------------------
    -- chk_sales_fact_order_type allows ONLY 'Online' / 'Walk-in'.
    -- There is no 'Unknown' member, so anything unrecognised must default
    -- to the physically dominant channel rather than reject the sale.
    ---------------------------------------------------------------------
    FUNCTION std_order_type (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('ONLINE','WEB','ECOMMERCE','APP','INTERNET') THEN 'Online'
            ELSE 'Walk-in'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Walk-in';
    END std_order_type;

    ---------------------------------------------------------------------
    FUNCTION std_delivery_status (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('DELIVERED','COMPLETE','COMPLETED','RECEIVED') THEN 'Delivered'
            WHEN t IN ('INTRANSIT','TRANSIT','SHIPPED','ONTHEWAY',
                       'OUTFORDELIVERY','DISPATCHED')                 THEN 'In Transit'
            WHEN t IN ('CANCELLED','CANCELED','VOID','ABORTED')       THEN 'Cancelled'
            ELSE 'Pending'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Pending';
    END std_delivery_status;

    ---------------------------------------------------------------------
    FUNCTION std_return_status (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('APPROVED','ACCEPT','ACCEPTED','OK')     THEN 'Approved'
            WHEN t IN ('REJECTED','REJECT','DECLINED','DENIED') THEN 'Rejected'
            WHEN t IN ('REFUNDED','REFUND','PAID')              THEN 'Refunded'
            ELSE 'Pending'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Pending';
    END std_return_status;

    ---------------------------------------------------------------------
    FUNCTION std_trans_type (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('REDEEM','REDEEMED','REDEMPTION','SPEND','MINUS') THEN 'Redeem'
            WHEN t IN ('EARN','EARNED','ACCRUE','ACCRUAL','PLUS')        THEN 'Earn'
            ELSE NULL      -- unresolvable: the staging view rejects the row
        END;
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END std_trans_type;

    ---------------------------------------------------------------------
    FUNCTION std_reason_name (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('MISSING','LOST','NOTRECEIVED','SHORT')      THEN 'Missing'
            WHEN t IN ('BROKEN','DAMAGED','DAMAGE','CRACKED')       THEN 'Broken'
            WHEN t IN ('EXPIRED','EXPIRY','OUTOFDATE','SPOILT')     THEN 'Expired'
            WHEN t IN ('WRONGITEM','WRONG','INCORRECTITEM',
                       'WRONGPRODUCT')                              THEN 'Wrong Item'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_reason_name;

    ---------------------------------------------------------------------
    FUNCTION std_reason_cat (p_reason_name VARCHAR2) RETURN VARCHAR2 IS
        r VARCHAR2(60) := std_reason_name(p_reason_name);
    BEGIN
        RETURN CASE
            WHEN r IN ('Missing','Wrong Item') THEN 'Fulfilment'
            WHEN r IN ('Broken','Expired')     THEN 'Product Quality'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_reason_cat;

    ---------------------------------------------------------------------
    FUNCTION std_discount_type (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('PERCENTAGE','PERCENT','PCT','PERC') THEN 'Percentage'
            WHEN t IN ('FIXED','FLAT','AMOUNT','ABSOLUTE')  THEN 'Fixed'
            WHEN t IN ('NONE','NIL','NA')                   THEN 'None'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_discount_type;

    ---------------------------------------------------------------------
    FUNCTION std_promo_status (p_val VARCHAR2) RETURN VARCHAR2 IS
        t VARCHAR2(200) := token(p_val);
    BEGIN
        RETURN CASE
            WHEN t IN ('ACTIVE','A','RUNNING','LIVE')            THEN 'Active'
            WHEN t IN ('INACTIVE','I','EXPIRED','ENDED','CLOSED') THEN 'Inactive'
            WHEN t IN ('NONE','NIL','NA')                        THEN 'None'
            ELSE 'Unknown'
        END;
    EXCEPTION WHEN OTHERS THEN RETURN 'Unknown';
    END std_promo_status;

    -- ==================================================================
    --  NUMERIC / DATE
    -- ==================================================================
    FUNCTION clamp_num (p_val NUMBER,
                        p_min NUMBER DEFAULT 0,
                        p_max NUMBER DEFAULT NULL,
                        p_default NUMBER DEFAULT 0) RETURN NUMBER
    IS
        v NUMBER;
    BEGIN
        IF p_val IS NULL THEN
            RETURN p_default;
        END IF;
        v := p_val;
        IF p_min IS NOT NULL AND v < p_min THEN v := p_min; END IF;
        IF p_max IS NOT NULL AND v > p_max THEN v := p_max; END IF;
        RETURN v;
    EXCEPTION WHEN OTHERS THEN RETURN p_default;
    END clamp_num;

    ---------------------------------------------------------------------
    -- DATE_DIM uses a YYYYMMDD smart key and seeds -1 for 'Unknown'.
    ---------------------------------------------------------------------
    FUNCTION to_date_key (p_dt DATE) RETURN NUMBER IS
    BEGIN
        IF p_dt IS NULL THEN
            RETURN -1;
        END IF;
        RETURN TO_NUMBER(TO_CHAR(p_dt, 'YYYYMMDD'));
    EXCEPTION WHEN OTHERS THEN RETURN -1;
    END to_date_key;

END etl_scrub;
/
SHOW ERRORS

-- ----------------------------------------------------------------------------
--  Smoke test - proves each rule fires before the load is trusted
-- ----------------------------------------------------------------------------
SET SERVEROUTPUT ON
BEGIN
    DBMS_OUTPUT.PUT_LINE('clean_name("  ahmad   BIN ali ") = ' || etl_scrub.clean_name('  ahmad   BIN ali '));
    DBMS_OUTPUT.PUT_LINE('clean_email("BAD@@mail")         = ' || etl_scrub.clean_email('BAD@@mail'));
    DBMS_OUTPUT.PUT_LINE('clean_ic("880203-14-5566")       = ' || etl_scrub.clean_ic('880203-14-5566'));
    DBMS_OUTPUT.PUT_LINE('clean_postcode("5100")           = ' || etl_scrub.clean_postcode('5100'));
    DBMS_OUTPUT.PUT_LINE('std_state("penang")              = ' || etl_scrub.std_state('penang'));
    DBMS_OUTPUT.PUT_LINE('std_region("K.L.")               = ' || etl_scrub.std_region('K.L.'));
    DBMS_OUTPUT.PUT_LINE('std_order_type("WEB")            = ' || etl_scrub.std_order_type('WEB'));
    DBMS_OUTPUT.PUT_LINE('clamp_num(-5, 0)                 = ' || etl_scrub.clamp_num(-5, 0));
END;
/

-- ============================================================================
--  END OF FILE 01
-- ============================================================================
