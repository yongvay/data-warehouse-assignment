/* ============================================================================
   TASK 2(a) — ETL: INITIAL (FIRST-TIME HISTORICAL) LOAD
   Sales & Returns Data Warehouse — Fact Constellation with Conformed Dimensions
   Target DBMS  : Oracle 12c or later
   Prerequisite : run task1b_physical_design.sql first (all target tables exist)
   ----------------------------------------------------------------------------
   ETL ARCHITECTURE
       SOURCE  ->  [E] STAGING (STG_*)   raw, untyped, as-extracted
               ->  [T] VIEWS   (VW_*)    cleanse, cast, de-duplicate, derive
               ->  [L] PROCEDURES        surrogate keys, SCD logic, INSERT
               ->  WAREHOUSE (DIM / FACT)

   LOAD SEQUENCE (parents before children — enforced by PRC_RUN_INITIAL_LOAD)
       1. DATE_DIM            (generated, not sourced)
       2. PRODUCT_DIM         SCD 1
       3. BRANCH_DIM          SCD 1
       4. PROMOTION_DIM       SCD 1
       5. RETURN_REASON_DIM   SCD 1
       6. CUSTOMER_DIM        SCD 2  <-- full version history rebuilt
       7. SALES_FACT
       8. RETURNS_FACT

   CONTENTS
       1. ETL control & audit objects        6. Fact load procedures
       2. Staging tables                     7. Master load procedure
       3. Helper functions                   8. Sample staging data
       4. Transformation views               9. Execution
       5. Dimension load procedures         10. Verification SELECTs
   ============================================================================ */

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET DEFINE OFF;


/* ============================================================================
   0. CLEAN-UP
   NOTE: raises "object does not exist" on a first run — that is expected.
   ============================================================================ */
DROP VIEW VW_SALES_CLEAN;
DROP VIEW VW_RETURNS_CLEAN;
DROP VIEW VW_CUSTOMER_HISTORY;
DROP VIEW VW_PRODUCT_CLEAN;
DROP VIEW VW_BRANCH_CLEAN;
DROP VIEW VW_PROMOTION_CLEAN;
DROP VIEW VW_REASON_CLEAN;

DROP TABLE STG_SALES         PURGE;
DROP TABLE STG_RETURNS       PURGE;
DROP TABLE STG_CUSTOMER      PURGE;
DROP TABLE STG_PRODUCT       PURGE;
DROP TABLE STG_BRANCH        PURGE;
DROP TABLE STG_PROMOTION     PURGE;
DROP TABLE STG_RETURN_REASON PURGE;
DROP TABLE ETL_ERROR_LOG     PURGE;
DROP TABLE ETL_BATCH_CONTROL PURGE;
DROP TABLE REF_FESTIVE_DAY   PURGE;

DROP SEQUENCE SEQ_ETL_BATCH;
DROP SEQUENCE SEQ_ETL_ERROR;


/* ============================================================================
   1. ETL CONTROL & AUDIT OBJECTS
   Every warehouse row carries etl_batch_id / load_dt / dq_flag. These objects
   are what make those columns meaningful: a load can be traced, audited and
   (if necessary) reversed by batch.
   ============================================================================ */
CREATE SEQUENCE SEQ_ETL_BATCH START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_ETL_ERROR START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

CREATE TABLE ETL_BATCH_CONTROL (
    etl_batch_id    NUMBER(10)    NOT NULL,
    load_type       VARCHAR2(20)  NOT NULL,
    target_table    VARCHAR2(30)  NOT NULL,
    start_time      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    end_time        TIMESTAMP,
    rows_read       NUMBER(10)    DEFAULT 0,
    rows_inserted   NUMBER(10)    DEFAULT 0,
    rows_rejected   NUMBER(10)    DEFAULT 0,
    status          VARCHAR2(15)  DEFAULT 'RUNNING' NOT NULL,
    error_message   VARCHAR2(500),
    CONSTRAINT pk_etl_batch  PRIMARY KEY (etl_batch_id, target_table),
    CONSTRAINT ck_etl_type   CHECK (load_type IN ('INITIAL','INCREMENTAL')),
    CONSTRAINT ck_etl_status CHECK (status IN ('RUNNING','SUCCESS','FAILED'))
);

CREATE TABLE ETL_ERROR_LOG (
    error_id       NUMBER(10)     NOT NULL,
    etl_batch_id   NUMBER(10)     NOT NULL,
    source_table   VARCHAR2(30)   NOT NULL,
    source_key     VARCHAR2(100),
    error_type     VARCHAR2(30)   NOT NULL,
    error_detail   VARCHAR2(500),
    logged_at      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_etl_error PRIMARY KEY (error_id)
);

/* Reference table driving DATE_DIM.holiday_ind and festive_event */
CREATE TABLE REF_FESTIVE_DAY (
    cal_date       DATE          NOT NULL,
    festive_event  VARCHAR2(30)  NOT NULL,
    CONSTRAINT pk_ref_festive PRIMARY KEY (cal_date)
);


/* ============================================================================
   2. STAGING TABLES  [EXTRACT]
   Deliberately modelled on the SOURCE system, not the warehouse:
     - every column is VARCHAR2 (a flat-file / CSV extract has no data types)
     - no constraints, no keys — staging must accept dirty data, not reject it
     - a load_seq column preserves extract order for de-duplication
   Cleansing happens in the transformation VIEWS, never here.
   ============================================================================ */
CREATE TABLE STG_PRODUCT (
    load_seq            NUMBER(10),
    item_id             VARCHAR2(50),
    item_name           VARCHAR2(200),
    item_status         VARCHAR2(50),
    unit_price          VARCHAR2(50),
    category_name       VARCHAR2(100),
    supplier_name       VARCHAR2(200),
    supplier_contact_no VARCHAR2(50)
);

CREATE TABLE STG_BRANCH (
    load_seq    NUMBER(10),
    branch_id   VARCHAR2(50),
    branch_name VARCHAR2(200),
    city        VARCHAR2(100),
    state       VARCHAR2(100),
    contact_no  VARCHAR2(50)
);

CREATE TABLE STG_PROMOTION (
    load_seq       NUMBER(10),
    promotion_id   VARCHAR2(50),
    promo_name     VARCHAR2(200),
    discount_type  VARCHAR2(50),
    discount_value VARCHAR2(50),
    start_date     VARCHAR2(50),
    end_date       VARCHAR2(50),
    promo_status   VARCHAR2(50)
);

CREATE TABLE STG_RETURN_REASON (
    load_seq    NUMBER(10),
    reason_id   VARCHAR2(50),
    reason_name VARCHAR2(100)
);

/* SCD 2 source: ONE ROW PER CUSTOMER VERSION, carrying the date the version
   became effective in the source system. This is what makes a first-time
   HISTORICAL load possible — a snapshot extract could only ever load "today". */
CREATE TABLE STG_CUSTOMER (
    load_seq        NUMBER(10),
    customer_id     VARCHAR2(50),
    customer_name   VARCHAR2(200),
    ic_no           VARCHAR2(50),
    email           VARCHAR2(200),
    customer_status VARCHAR2(50),
    member_flag     VARCHAR2(10),
    membership_type VARCHAR2(50),
    membership_fee  VARCHAR2(50),
    change_date     VARCHAR2(50)   /* date this version became effective */
);

CREATE TABLE STG_SALES (
    load_seq     NUMBER(10),
    order_no     VARCHAR2(50),
    order_date   VARCHAR2(50),
    order_time   VARCHAR2(50),
    customer_id  VARCHAR2(50),
    branch_id    VARCHAR2(50),
    item_id      VARCHAR2(50),
    promotion_id VARCHAR2(50),
    order_type   VARCHAR2(50),
    quantity     VARCHAR2(50),
    unit_price   VARCHAR2(50),
    discount_amt VARCHAR2(50)
);

CREATE TABLE STG_RETURNS (
    load_seq      NUMBER(10),
    return_id     VARCHAR2(50),
    return_date   VARCHAR2(50),
    order_no      VARCHAR2(50),
    order_date    VARCHAR2(50),
    customer_id   VARCHAR2(50),
    branch_id     VARCHAR2(50),
    item_id       VARCHAR2(50),
    promotion_id  VARCHAR2(50),
    reason_id     VARCHAR2(50),
    return_status VARCHAR2(50),
    qty_returned  VARCHAR2(50),
    refund_amount VARCHAR2(50)
);


/* ============================================================================
   3. HELPER FUNCTIONS  [TRANSFORM support]
   Source data cannot be trusted to convert. A raw TO_NUMBER / TO_DATE on dirty
   staging data aborts the whole load; these functions convert safely and return
   a default instead, so one bad row never kills the batch.
   Declared DETERMINISTIC so they may be used inside views.
   ============================================================================ */
CREATE OR REPLACE FUNCTION FN_TO_NUM (
    p_str     IN VARCHAR2,
    p_default IN NUMBER DEFAULT NULL
) RETURN NUMBER DETERMINISTIC
IS
BEGIN
    RETURN TO_NUMBER(TRIM(REPLACE(REPLACE(p_str,','),'RM')));
EXCEPTION
    WHEN OTHERS THEN RETURN p_default;
END;
/

CREATE OR REPLACE FUNCTION FN_TO_DATE (
    p_str     IN VARCHAR2,
    p_default IN DATE DEFAULT NULL
) RETURN DATE DETERMINISTIC
IS
    v_str VARCHAR2(50) := TRIM(p_str);
BEGIN
    /* try the formats the source system is known to emit, in order */
    BEGIN RETURN TO_DATE(v_str,'YYYY-MM-DD');  EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN RETURN TO_DATE(v_str,'DD/MM/YYYY');  EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN RETURN TO_DATE(v_str,'DD-MON-YYYY','NLS_DATE_LANGUAGE=ENGLISH');
          EXCEPTION WHEN OTHERS THEN NULL; END;
    RETURN p_default;
EXCEPTION
    WHEN OTHERS THEN RETURN p_default;
END;
/

/* DATE -> smart integer surrogate key (YYYYMMDD); -1 when the date is unusable */
CREATE OR REPLACE FUNCTION FN_DATE_KEY (
    p_date IN DATE
) RETURN NUMBER DETERMINISTIC
IS
BEGIN
    IF p_date IS NULL THEN RETURN -1; END IF;
    RETURN TO_NUMBER(TO_CHAR(p_date,'YYYYMMDD'));
EXCEPTION
    WHEN OTHERS THEN RETURN -1;
END;
/


/* ============================================================================
   4. TRANSFORMATION VIEWS  [TRANSFORM]
   Each view is the single documented point where a source record is cleansed.
   Common transformations applied:
     - TRIM / UPPER / INITCAP standardisation
     - safe type casting via the helper functions
     - NVL defaulting of missing descriptive attributes to 'Unknown'
     - de-duplication: ROW_NUMBER() keeps the LAST extracted row per natural key
     - derived attributes (region, reason_category, gross/net amounts)
     - a dq_flag verdict: C = clean, S = suspect (a value was defaulted),
                          E = error (row must be rejected)
   ============================================================================ */

/* ---- 4.1 PRODUCT (SCD 1) ------------------------------------------------- */
CREATE OR REPLACE VIEW VW_PRODUCT_CLEAN AS
SELECT item_id,
       item_name,
       item_status,
       unit_price,
       category_name,
       supplier_name,
       supplier_contact_no,
       dq_flag
FROM (
    SELECT UPPER(TRIM(s.item_id))                                   AS item_id,
           INITCAP(TRIM(NVL(s.item_name,'Unknown Product')))        AS item_name,
           CASE UPPER(TRIM(s.item_status))
                WHEN 'A'            THEN 'Active'
                WHEN 'ACTIVE'       THEN 'Active'
                WHEN 'I'            THEN 'Inactive'
                WHEN 'INACTIVE'     THEN 'Inactive'
                WHEN 'D'            THEN 'Discontinued'
                WHEN 'DISCONTINUED' THEN 'Discontinued'
                ELSE 'Unknown'
           END                                                      AS item_status,
           NVL(FN_TO_NUM(s.unit_price), 0)                          AS unit_price,
           INITCAP(TRIM(NVL(s.category_name,'Unknown')))            AS category_name,
           INITCAP(TRIM(NVL(s.supplier_name,'Unknown')))            AS supplier_name,
           TRIM(s.supplier_contact_no)                              AS supplier_contact_no,
           CASE WHEN s.item_name IS NULL
                  OR FN_TO_NUM(s.unit_price) IS NULL
                  OR FN_TO_NUM(s.unit_price) < 0 THEN 'S'
                ELSE 'C'
           END                                                      AS dq_flag,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(s.item_id))
                              ORDER BY s.load_seq DESC)             AS rn
    FROM   STG_PRODUCT s
    WHERE  s.item_id IS NOT NULL
)
WHERE rn = 1;

/* ---- 4.2 BRANCH (SCD 1) — region is DERIVED from state ------------------- */
CREATE OR REPLACE VIEW VW_BRANCH_CLEAN AS
SELECT branch_id, branch_name, city, state, region, contact_no, dq_flag
FROM (
    SELECT UPPER(TRIM(s.branch_id))                           AS branch_id,
           INITCAP(TRIM(NVL(s.branch_name,'Unknown Branch'))) AS branch_name,
           INITCAP(TRIM(NVL(s.city,'Unknown')))               AS city,
           INITCAP(TRIM(NVL(s.state,'Unknown')))              AS state,
           CASE UPPER(TRIM(s.state))
                WHEN 'PERLIS'          THEN 'Northern'
                WHEN 'KEDAH'           THEN 'Northern'
                WHEN 'PENANG'          THEN 'Northern'
                WHEN 'PULAU PINANG'    THEN 'Northern'
                WHEN 'PERAK'           THEN 'Northern'
                WHEN 'SELANGOR'        THEN 'Central'
                WHEN 'KUALA LUMPUR'    THEN 'Central'
                WHEN 'PUTRAJAYA'       THEN 'Central'
                WHEN 'NEGERI SEMBILAN' THEN 'Southern'
                WHEN 'MELAKA'          THEN 'Southern'
                WHEN 'JOHOR'           THEN 'Southern'
                WHEN 'PAHANG'          THEN 'East Coast'
                WHEN 'TERENGGANU'      THEN 'East Coast'
                WHEN 'KELANTAN'        THEN 'East Coast'
                WHEN 'SABAH'           THEN 'East Malaysia'
                WHEN 'SARAWAK'         THEN 'East Malaysia'
                WHEN 'LABUAN'          THEN 'East Malaysia'
                ELSE 'Unknown'
           END                                                AS region,
           TRIM(s.contact_no)                                 AS contact_no,
           CASE WHEN s.state IS NULL THEN 'S' ELSE 'C' END    AS dq_flag,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(s.branch_id))
                              ORDER BY s.load_seq DESC)       AS rn
    FROM   STG_BRANCH s
    WHERE  s.branch_id IS NOT NULL
)
WHERE rn = 1;

/* ---- 4.3 PROMOTION (SCD 1) ---------------------------------------------- */
CREATE OR REPLACE VIEW VW_PROMOTION_CLEAN AS
SELECT promotion_id, promo_name, discount_type, discount_value,
       promo_start_date, promo_end_date, promo_status, dq_flag
FROM (
    SELECT UPPER(TRIM(s.promotion_id))                              AS promotion_id,
           INITCAP(TRIM(NVL(s.promo_name,'Unknown Promotion')))     AS promo_name,
           CASE UPPER(TRIM(s.discount_type))
                WHEN 'PCT'          THEN 'Percentage'
                WHEN 'PERCENT'      THEN 'Percentage'
                WHEN 'PERCENTAGE'   THEN 'Percentage'
                WHEN 'FIXED'        THEN 'Fixed Amount'
                WHEN 'FIXED AMOUNT' THEN 'Fixed Amount'
                WHEN 'AMT'          THEN 'Fixed Amount'
                WHEN 'BXGY'         THEN 'Buy X Get Y'
                WHEN 'NONE'         THEN 'None'
                ELSE 'Unknown'
           END                                                      AS discount_type,
           NVL(FN_TO_NUM(s.discount_value), 0)                      AS discount_value,
           FN_TO_DATE(s.start_date)                                 AS promo_start_date,
           FN_TO_DATE(s.end_date)                                   AS promo_end_date,
           CASE UPPER(TRIM(s.promo_status))
                WHEN 'A'       THEN 'Active'
                WHEN 'ACTIVE'  THEN 'Active'
                WHEN 'E'       THEN 'Expired'
                WHEN 'EXPIRED' THEN 'Expired'
                WHEN 'P'       THEN 'Planned'
                WHEN 'PLANNED' THEN 'Planned'
                ELSE 'Inactive'
           END                                                      AS promo_status,
           CASE WHEN FN_TO_DATE(s.start_date) IS NULL
                  OR FN_TO_DATE(s.end_date)   IS NULL THEN 'S'
                ELSE 'C'
           END                                                      AS dq_flag,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(s.promotion_id))
                              ORDER BY s.load_seq DESC)             AS rn
    FROM   STG_PROMOTION s
    WHERE  s.promotion_id IS NOT NULL
)
WHERE rn = 1;

/* ---- 4.4 RETURN REASON (SCD 1) — category is DERIVED from the reason ----- */
CREATE OR REPLACE VIEW VW_REASON_CLEAN AS
SELECT reason_id, reason_name, reason_category, dq_flag
FROM (
    SELECT UPPER(TRIM(s.reason_id))                             AS reason_id,
           INITCAP(TRIM(NVL(s.reason_name,'Unknown Reason')))   AS reason_name,
           CASE
                WHEN UPPER(s.reason_name) LIKE '%DAMAG%'    THEN 'Product Quality'
                WHEN UPPER(s.reason_name) LIKE '%DEFECT%'   THEN 'Product Quality'
                WHEN UPPER(s.reason_name) LIKE '%FAULT%'    THEN 'Product Quality'
                WHEN UPPER(s.reason_name) LIKE '%EXPIR%'    THEN 'Product Quality'
                WHEN UPPER(s.reason_name) LIKE '%SIZE%'     THEN 'Customer Preference'
                WHEN UPPER(s.reason_name) LIKE '%CHANGE%'   THEN 'Customer Preference'
                WHEN UPPER(s.reason_name) LIKE '%MIND%'     THEN 'Customer Preference'
                WHEN UPPER(s.reason_name) LIKE '%LATE%'     THEN 'Logistics'
                WHEN UPPER(s.reason_name) LIKE '%WRONG%'    THEN 'Logistics'
                WHEN UPPER(s.reason_name) LIKE '%DELIVER%'  THEN 'Logistics'
                WHEN UPPER(s.reason_name) LIKE '%PRICE%'    THEN 'Pricing'
                WHEN UPPER(s.reason_name) LIKE '%CHEAPER%'  THEN 'Pricing'
                ELSE 'Unknown'
           END                                                  AS reason_category,
           CASE WHEN s.reason_name IS NULL THEN 'S' ELSE 'C' END AS dq_flag,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(s.reason_id))
                              ORDER BY s.load_seq DESC)          AS rn
    FROM   STG_RETURN_REASON s
    WHERE  s.reason_id IS NOT NULL
)
WHERE rn = 1;

/* ---- 4.5 CUSTOMER — *** SCD TYPE 2 HISTORY RECONSTRUCTION *** ------------
   This is the heart of the historical load. For each customer the source rows
   are ordered by change_date, then:
       effective_start_date = this version's change_date
       effective_end_date   = (next version's change_date - 1), or 9999-12-31
                              for the most recent version   <-- LEAD()
       is_current_flag      = 'Y' only on the most recent version
       version_no           = ROW_NUMBER() within the customer
   The whole history is therefore rebuilt in a single pass, which an
   incremental (Task 2b) load could never do.
   ------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW VW_CUSTOMER_HISTORY AS
SELECT customer_id,
       customer_name,
       ic_no,
       email,
       customer_status,
       member_flag,
       membership_type,
       membership_fee,
       effective_start_date,
       NVL(LEAD(effective_start_date)
             OVER (PARTITION BY customer_id ORDER BY effective_start_date) - 1,
           DATE '9999-12-31')                              AS effective_end_date,
       CASE WHEN LEAD(effective_start_date)
                   OVER (PARTITION BY customer_id ORDER BY effective_start_date) IS NULL
            THEN 'Y' ELSE 'N'
       END                                                 AS is_current_flag,
       ROW_NUMBER() OVER (PARTITION BY customer_id
                          ORDER BY effective_start_date)   AS version_no,
       dq_flag
FROM (
    SELECT customer_id, customer_name, ic_no, email, customer_status,
           member_flag, membership_type, membership_fee,
           effective_start_date, dq_flag
    FROM (
        SELECT UPPER(TRIM(s.customer_id))                              AS customer_id,
               INITCAP(TRIM(NVL(s.customer_name,'Unknown Customer')))  AS customer_name,
               UPPER(TRIM(s.ic_no))                                    AS ic_no,
               LOWER(TRIM(s.email))                                    AS email,
               CASE UPPER(TRIM(s.customer_status))
                    WHEN 'A'        THEN 'Active'
                    WHEN 'ACTIVE'   THEN 'Active'
                    WHEN 'I'        THEN 'Inactive'
                    WHEN 'INACTIVE' THEN 'Inactive'
                    WHEN 'C'        THEN 'Closed'
                    WHEN 'CLOSED'   THEN 'Closed'
                    ELSE 'Unknown'
               END                                                     AS customer_status,
               CASE WHEN UPPER(TRIM(s.member_flag)) IN ('Y','YES','1','TRUE') THEN 'Y'
                    ELSE 'N'
               END                                                     AS member_flag,
               CASE UPPER(TRIM(s.membership_type))
                    WHEN 'BASIC'    THEN 'Basic'
                    WHEN 'SILVER'   THEN 'Silver'
                    WHEN 'GOLD'     THEN 'Gold'
                    WHEN 'PLATINUM' THEN 'Platinum'
                    WHEN 'NONE'     THEN 'None'
                    ELSE 'None'
               END                                                     AS membership_type,
               NVL(FN_TO_NUM(s.membership_fee), 0)                     AS membership_fee,
               NVL(FN_TO_DATE(s.change_date), DATE '1900-01-01')       AS effective_start_date,
               CASE WHEN FN_TO_DATE(s.change_date) IS NULL
                      OR s.customer_name IS NULL THEN 'S'
                    ELSE 'C'
               END                                                     AS dq_flag,
               /* one row per customer per effective date — keep the last extracted */
               ROW_NUMBER() OVER (
                   PARTITION BY UPPER(TRIM(s.customer_id)),
                                NVL(FN_TO_DATE(s.change_date), DATE '1900-01-01')
                   ORDER BY s.load_seq DESC)                           AS rn
        FROM   STG_CUSTOMER s
        WHERE  s.customer_id IS NOT NULL
    )
    WHERE rn = 1
);

/* ---- 4.6 SALES FACT --------------------------------------------------------
   Does three jobs beyond cleansing:
     (a) enforces the declared grain — duplicate item lines on the same order
         are aggregated with GROUP BY, so (order_no, product_key) stays unique
     (b) derives the measures gross_sales_amt and net_sales_amt
     (c) issues a load verdict in dq_flag; 'E' rows are rejected by the
         procedure into ETL_ERROR_LOG instead of being inserted
   ------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW VW_SALES_CLEAN AS
SELECT order_no,
       order_date,
       order_hour,
       customer_id,
       branch_id,
       item_id,
       promotion_id,
       order_type,
       quantity,
       unit_price,
       ROUND(quantity * unit_price, 2)                          AS gross_sales_amt,
       LEAST(discount_amt, ROUND(quantity * unit_price, 2))     AS discount_amt,
       ROUND(quantity * unit_price, 2)
         - LEAST(discount_amt, ROUND(quantity * unit_price, 2)) AS net_sales_amt,
       CASE WHEN order_no   IS NULL
              OR item_id    IS NULL
              OR order_date IS NULL
              OR quantity  <= 0
              OR unit_price < 0            THEN 'E'
            WHEN customer_id IS NULL
              OR branch_id   IS NULL
              OR raw_dq      = 'S'         THEN 'S'
            ELSE 'C'
       END                                                      AS dq_flag
FROM (
    SELECT UPPER(TRIM(s.order_no))                          AS order_no,
           FN_TO_DATE(s.order_date)                         AS order_date,
           NVL(FN_TO_NUM(SUBSTR(TRIM(s.order_time),1,2)),0) AS order_hour,
           UPPER(TRIM(s.customer_id))                       AS customer_id,
           UPPER(TRIM(s.branch_id))                         AS branch_id,
           UPPER(TRIM(s.item_id))                           AS item_id,
           UPPER(TRIM(s.promotion_id))                      AS promotion_id,
           CASE UPPER(TRIM(s.order_type))
                WHEN 'INSTORE'    THEN 'In-Store'
                WHEN 'IN-STORE'   THEN 'In-Store'
                WHEN 'STORE'      THEN 'In-Store'
                WHEN 'ONLINE'     THEN 'Online'
                WHEN 'WEB'        THEN 'Online'
                WHEN 'PHONE'      THEN 'Phone'
                WHEN 'APP'        THEN 'Mobile App'
                WHEN 'MOBILE APP' THEN 'Mobile App'
                ELSE 'Unknown'
           END                                              AS order_type,
           SUM(NVL(FN_TO_NUM(s.quantity), 0))               AS quantity,
           MAX(NVL(FN_TO_NUM(s.unit_price), 0))             AS unit_price,
           SUM(NVL(FN_TO_NUM(s.discount_amt), 0))           AS discount_amt,
           MAX(CASE WHEN FN_TO_NUM(s.quantity)   IS NULL
                      OR FN_TO_NUM(s.unit_price) IS NULL THEN 'S' ELSE 'C' END) AS raw_dq
    FROM   STG_SALES s
    GROUP  BY UPPER(TRIM(s.order_no)),
              FN_TO_DATE(s.order_date),
              NVL(FN_TO_NUM(SUBSTR(TRIM(s.order_time),1,2)),0),
              UPPER(TRIM(s.customer_id)),
              UPPER(TRIM(s.branch_id)),
              UPPER(TRIM(s.item_id)),
              UPPER(TRIM(s.promotion_id)),
              CASE UPPER(TRIM(s.order_type))
                   WHEN 'INSTORE'    THEN 'In-Store'
                   WHEN 'IN-STORE'   THEN 'In-Store'
                   WHEN 'STORE'      THEN 'In-Store'
                   WHEN 'ONLINE'     THEN 'Online'
                   WHEN 'WEB'        THEN 'Online'
                   WHEN 'PHONE'      THEN 'Phone'
                   WHEN 'APP'        THEN 'Mobile App'
                   WHEN 'MOBILE APP' THEN 'Mobile App'
                   ELSE 'Unknown'
              END
);

/* ---- 4.7 RETURNS FACT — days_to_return is DERIVED ------------------------ */
CREATE OR REPLACE VIEW VW_RETURNS_CLEAN AS
SELECT return_id, return_date, order_date, order_no, customer_id, branch_id,
       item_id, promotion_id, reason_id, return_status,
       qty_returned, refund_amount,
       CASE WHEN return_date IS NOT NULL AND order_date IS NOT NULL
                 AND return_date >= order_date
            THEN return_date - order_date ELSE 0
       END                                                   AS days_to_return,
       CASE WHEN return_id    IS NULL
              OR item_id      IS NULL
              OR return_date  IS NULL
              OR qty_returned <= 0
              OR refund_amount < 0                THEN 'E'
            WHEN order_date IS NULL
              OR return_date < order_date
              OR reason_id  IS NULL               THEN 'S'
            ELSE 'C'
       END                                                   AS dq_flag
FROM (
    SELECT UPPER(TRIM(s.return_id))                  AS return_id,
           FN_TO_DATE(s.return_date)                 AS return_date,
           FN_TO_DATE(s.order_date)                  AS order_date,
           UPPER(TRIM(s.order_no))                   AS order_no,
           UPPER(TRIM(s.customer_id))                AS customer_id,
           UPPER(TRIM(s.branch_id))                  AS branch_id,
           UPPER(TRIM(s.item_id))                    AS item_id,
           UPPER(TRIM(s.promotion_id))               AS promotion_id,
           UPPER(TRIM(s.reason_id))                  AS reason_id,
           CASE UPPER(TRIM(s.return_status))
                WHEN 'P'        THEN 'Pending'
                WHEN 'PENDING'  THEN 'Pending'
                WHEN 'A'        THEN 'Approved'
                WHEN 'APPROVED' THEN 'Approved'
                WHEN 'R'        THEN 'Rejected'
                WHEN 'REJECTED' THEN 'Rejected'
                WHEN 'REFUNDED' THEN 'Refunded'
                ELSE 'Pending'
           END                                       AS return_status,
           SUM(NVL(FN_TO_NUM(s.qty_returned), 0))    AS qty_returned,
           SUM(NVL(FN_TO_NUM(s.refund_amount), 0))   AS refund_amount
    FROM   STG_RETURNS s
    GROUP  BY UPPER(TRIM(s.return_id)),
              FN_TO_DATE(s.return_date),
              FN_TO_DATE(s.order_date),
              UPPER(TRIM(s.order_no)),
              UPPER(TRIM(s.customer_id)),
              UPPER(TRIM(s.branch_id)),
              UPPER(TRIM(s.item_id)),
              UPPER(TRIM(s.promotion_id)),
              UPPER(TRIM(s.reason_id)),
              CASE UPPER(TRIM(s.return_status))
                   WHEN 'P'        THEN 'Pending'
                   WHEN 'PENDING'  THEN 'Pending'
                   WHEN 'A'        THEN 'Approved'
                   WHEN 'APPROVED' THEN 'Approved'
                   WHEN 'R'        THEN 'Rejected'
                   WHEN 'REJECTED' THEN 'Rejected'
                   WHEN 'REFUNDED' THEN 'Refunded'
                   ELSE 'Pending'
              END
);


/* ============================================================================
   5. DIMENSION LOAD PROCEDURES  [LOAD]
   Every procedure follows the same contract:
       open an audit row -> INSERT from the transformation view
                         -> record counts -> close the audit row
                         -> on error, mark FAILED, roll back, re-raise
   ============================================================================ */

/* ---- shared audit helpers ------------------------------------------------ */
CREATE OR REPLACE PROCEDURE PRC_AUDIT_START (
    p_batch_id IN NUMBER,
    p_table    IN VARCHAR2
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;   /* audit survives a rollback of the load */
BEGIN
    INSERT INTO ETL_BATCH_CONTROL (etl_batch_id, load_type, target_table, status)
    VALUES (p_batch_id, 'INITIAL', p_table, 'RUNNING');
    COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE PRC_AUDIT_END (
    p_batch_id IN NUMBER,
    p_table    IN VARCHAR2,
    p_read     IN NUMBER,
    p_ins      IN NUMBER,
    p_rej      IN NUMBER,
    p_status   IN VARCHAR2,
    p_error    IN VARCHAR2 DEFAULT NULL
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    UPDATE ETL_BATCH_CONTROL
       SET end_time      = SYSTIMESTAMP,
           rows_read     = p_read,
           rows_inserted = p_ins,
           rows_rejected = p_rej,
           status        = p_status,
           error_message = SUBSTR(p_error,1,500)
     WHERE etl_batch_id = p_batch_id
       AND target_table = p_table;
    COMMIT;
END;
/

/* ---- 5.1 DATE_DIM — generated, not extracted -----------------------------
   A date dimension has no source system. It is generated for the full range
   the facts will ever need, so no fact row can arrive without a matching date.
   -------------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE PRC_LOAD_DATE_DIM (
    p_batch_id   IN NUMBER,
    p_start_date IN DATE,
    p_end_date   IN DATE
) IS
    v_ins NUMBER := 0;
    v_days NUMBER := p_end_date - p_start_date + 1;
BEGIN
    PRC_AUDIT_START(p_batch_id, 'DATE_DIM');

    INSERT INTO DATE_DIM (
        date_key, cal_date, full_desc, day_week, day_num_month, day_num_year,
        last_day_ind, cal_week_end_date, cal_week_year, cal_month_name,
        cal_month_year, cal_year_month, cal_quarter, cal_year_quarter,
        cal_year, holiday_ind, weekday_ind, festive_event)
    SELECT FN_DATE_KEY(d.cal_date),
           d.cal_date,
           TO_CHAR(d.cal_date,'DD Mon YYYY','NLS_DATE_LANGUAGE=ENGLISH'),
           TRIM(TO_CHAR(d.cal_date,'Day','NLS_DATE_LANGUAGE=ENGLISH')),
           TO_NUMBER(TO_CHAR(d.cal_date,'DD')),
           TO_NUMBER(TO_CHAR(d.cal_date,'DDD')),
           CASE WHEN d.cal_date = LAST_DAY(d.cal_date) THEN 'Y' ELSE 'N' END,
           TRUNC(d.cal_date,'IW') + 6,
           'W'||TO_CHAR(d.cal_date,'IW')||'-'||TO_CHAR(d.cal_date,'IYYY'),
           TRIM(TO_CHAR(d.cal_date,'Month','NLS_DATE_LANGUAGE=ENGLISH')),
           TO_CHAR(d.cal_date,'Mon YYYY','NLS_DATE_LANGUAGE=ENGLISH'),
           TO_CHAR(d.cal_date,'YYYY-MM'),
           'Q'||TO_CHAR(d.cal_date,'Q'),
           TO_CHAR(d.cal_date,'YYYY')||'-Q'||TO_CHAR(d.cal_date,'Q'),
           TO_NUMBER(TO_CHAR(d.cal_date,'YYYY')),
           CASE WHEN f.cal_date IS NOT NULL THEN 'Y' ELSE 'N' END,
           CASE WHEN TO_CHAR(d.cal_date,'DY','NLS_DATE_LANGUAGE=ENGLISH')
                     IN ('SAT','SUN') THEN 'N' ELSE 'Y' END,
           NVL(f.festive_event,'None')
    FROM   ( SELECT p_start_date + LEVEL - 1 AS cal_date
             FROM   DUAL
             CONNECT BY LEVEL <= v_days ) d
    LEFT   JOIN REF_FESTIVE_DAY f ON f.cal_date = d.cal_date;

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'DATE_DIM', v_days, v_ins, 0, 'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('DATE_DIM        loaded : '||v_ins||' rows');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'DATE_DIM',v_days,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/

/* ---- 5.2 PRODUCT_DIM (SCD 1) -------------------------------------------- */
CREATE OR REPLACE PROCEDURE PRC_LOAD_PRODUCT_DIM (p_batch_id IN NUMBER) IS
    v_read NUMBER; v_ins NUMBER := 0;
BEGIN
    PRC_AUDIT_START(p_batch_id,'PRODUCT_DIM');
    SELECT COUNT(*) INTO v_read FROM VW_PRODUCT_CLEAN;

    /* the sequence is applied in an OUTER select — NEXTVAL is not permitted in
       a query block that already uses analytic functions                     */
    INSERT INTO PRODUCT_DIM (
        product_key, item_id, item_name, item_status, current_unit_price,
        category_name, supplier_name, supplier_contact_no,
        etl_batch_id, load_dt, dq_flag)
    SELECT SEQ_PRODUCT_KEY.NEXTVAL, v.item_id, v.item_name, v.item_status,
           v.unit_price, v.category_name, v.supplier_name, v.supplier_contact_no,
           p_batch_id, SYSDATE, v.dq_flag
    FROM   ( SELECT * FROM VW_PRODUCT_CLEAN ORDER BY item_id ) v;

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'PRODUCT_DIM',v_read,v_ins,v_read-v_ins,'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('PRODUCT_DIM     loaded : '||v_ins||' rows');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'PRODUCT_DIM',v_read,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/

/* ---- 5.3 BRANCH_DIM (SCD 1) --------------------------------------------- */
CREATE OR REPLACE PROCEDURE PRC_LOAD_BRANCH_DIM (p_batch_id IN NUMBER) IS
    v_read NUMBER; v_ins NUMBER := 0;
BEGIN
    PRC_AUDIT_START(p_batch_id,'BRANCH_DIM');
    SELECT COUNT(*) INTO v_read FROM VW_BRANCH_CLEAN;

    INSERT INTO BRANCH_DIM (
        branch_key, branch_id, branch_name, city, state, region, contact_no,
        etl_batch_id, load_dt, dq_flag)
    SELECT SEQ_BRANCH_KEY.NEXTVAL, v.branch_id, v.branch_name, v.city,
           v.state, v.region, v.contact_no, p_batch_id, SYSDATE, v.dq_flag
    FROM   ( SELECT * FROM VW_BRANCH_CLEAN ORDER BY branch_id ) v;

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'BRANCH_DIM',v_read,v_ins,v_read-v_ins,'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('BRANCH_DIM      loaded : '||v_ins||' rows');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'BRANCH_DIM',v_read,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/

/* ---- 5.4 PROMOTION_DIM (SCD 1) ------------------------------------------ */
CREATE OR REPLACE PROCEDURE PRC_LOAD_PROMOTION_DIM (p_batch_id IN NUMBER) IS
    v_read NUMBER; v_ins NUMBER := 0;
BEGIN
    PRC_AUDIT_START(p_batch_id,'PROMOTION_DIM');
    SELECT COUNT(*) INTO v_read FROM VW_PROMOTION_CLEAN;

    /* promo_duration_days is a VIRTUAL column and is deliberately not listed */
    INSERT INTO PROMOTION_DIM (
        promo_key, promotion_id, promo_name, discount_type, discount_value,
        promo_start_date, promo_end_date, promo_status,
        etl_batch_id, load_dt, dq_flag)
    SELECT SEQ_PROMO_KEY.NEXTVAL, v.promotion_id, v.promo_name, v.discount_type,
           v.discount_value, v.promo_start_date, v.promo_end_date, v.promo_status,
           p_batch_id, SYSDATE, v.dq_flag
    FROM   ( SELECT * FROM VW_PROMOTION_CLEAN ORDER BY promotion_id ) v;

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'PROMOTION_DIM',v_read,v_ins,v_read-v_ins,'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('PROMOTION_DIM   loaded : '||v_ins||' rows');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'PROMOTION_DIM',v_read,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/

/* ---- 5.5 RETURN_REASON_DIM (SCD 1) -------------------------------------- */
CREATE OR REPLACE PROCEDURE PRC_LOAD_REASON_DIM (p_batch_id IN NUMBER) IS
    v_read NUMBER; v_ins NUMBER := 0;
BEGIN
    PRC_AUDIT_START(p_batch_id,'RETURN_REASON_DIM');
    SELECT COUNT(*) INTO v_read FROM VW_REASON_CLEAN;

    INSERT INTO RETURN_REASON_DIM (
        reason_key, reason_id, reason_name, reason_category,
        etl_batch_id, load_dt, dq_flag)
    SELECT SEQ_REASON_KEY.NEXTVAL, v.reason_id, v.reason_name,
           v.reason_category, p_batch_id, SYSDATE, v.dq_flag
    FROM   ( SELECT * FROM VW_REASON_CLEAN ORDER BY reason_id ) v;

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'RETURN_REASON_DIM',v_read,v_ins,v_read-v_ins,'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('RETURN_REASON   loaded : '||v_ins||' rows');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'RETURN_REASON_DIM',v_read,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/

/* ---- 5.6 CUSTOMER_DIM — *** SCD TYPE 2 HISTORICAL LOAD *** --------------
   Every version of every customer is inserted, each with its own surrogate
   key. Rows are ordered by (customer_id, effective_start_date) so that
   surrogate keys ascend in chronological order — not required, but it makes
   the dimension far easier to read when marking or debugging.
   -------------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE PRC_LOAD_CUSTOMER_DIM (p_batch_id IN NUMBER) IS
    v_read NUMBER; v_ins NUMBER := 0; v_cust NUMBER;
BEGIN
    PRC_AUDIT_START(p_batch_id,'CUSTOMER_DIM');
    SELECT COUNT(*), COUNT(DISTINCT customer_id)
      INTO v_read, v_cust
      FROM VW_CUSTOMER_HISTORY;

    INSERT INTO CUSTOMER_DIM (
        customer_key, customer_id, customer_name, ic_no, email,
        customer_status, member_flag, membership_type, membership_fee,
        effective_start_date, effective_end_date, is_current_flag, version_no,
        etl_batch_id, load_dt, dq_flag)
    SELECT SEQ_CUSTOMER_KEY.NEXTVAL, v.customer_id, v.customer_name, v.ic_no,
           v.email, v.customer_status, v.member_flag, v.membership_type,
           v.membership_fee, v.effective_start_date, v.effective_end_date,
           v.is_current_flag, v.version_no, p_batch_id, SYSDATE, v.dq_flag
    FROM   ( SELECT * FROM VW_CUSTOMER_HISTORY
             ORDER BY customer_id, effective_start_date ) v;

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'CUSTOMER_DIM',v_read,v_ins,v_read-v_ins,'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('CUSTOMER_DIM    loaded : '||v_ins||' version rows for '
                         ||v_cust||' distinct customers  (SCD Type 2)');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'CUSTOMER_DIM',v_read,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/


/* ============================================================================
   6. FACT LOAD PROCEDURES  [LOAD]
   Two techniques matter here:

   (a) SURROGATE KEY PIPELINE — the fact never stores a natural key. Each
       natural key is resolved to its surrogate by an OUTER JOIN to the
       dimension, and NVL(...,-1) redirects an unresolvable key to the seeded
       'Unknown' row rather than failing the FK. Promotions fall back to 0
       ('No Promotion') when the source simply had no promotion.

   (b) *** POINT-IN-TIME SCD 2 LOOKUP *** — CUSTOMER_DIM is joined on
           order_date BETWEEN effective_start_date AND effective_end_date
       so the fact is attached to the customer version that was in force ON
       THE TRANSACTION DATE, not the current one. Joining on is_current_flag
       instead would silently destroy all history and is the single most
       common error in an SCD 2 fact load.
   ============================================================================ */

CREATE OR REPLACE PROCEDURE PRC_LOAD_SALES_FACT (p_batch_id IN NUMBER) IS
    v_read NUMBER; v_ins NUMBER := 0; v_rej NUMBER := 0;
BEGIN
    PRC_AUDIT_START(p_batch_id,'SALES_FACT');
    SELECT COUNT(*) INTO v_read FROM VW_SALES_CLEAN;

    /* 6.1a  quarantine unusable rows -------------------------------------- */
    INSERT INTO ETL_ERROR_LOG (error_id, etl_batch_id, source_table,
                               source_key, error_type, error_detail)
    SELECT SEQ_ETL_ERROR.NEXTVAL, p_batch_id, 'STG_SALES',
           NVL(v.order_no,'(null)')||' / '||NVL(v.item_id,'(null)'),
           'REJECTED_ROW',
           'Failed mandatory validation: '
           || CASE WHEN v.order_no   IS NULL THEN 'missing order_no; '   END
           || CASE WHEN v.item_id    IS NULL THEN 'missing item_id; '    END
           || CASE WHEN v.order_date IS NULL THEN 'invalid order_date; ' END
           || CASE WHEN v.quantity  <= 0     THEN 'quantity <= 0; '      END
           || CASE WHEN v.unit_price < 0     THEN 'negative unit_price; ' END
    FROM   VW_SALES_CLEAN v
    WHERE  v.dq_flag = 'E';
    v_rej := SQL%ROWCOUNT;

    /* 6.1b  load the surviving rows ---------------------------------------- */
    INSERT INTO SALES_FACT (
        order_no, product_key, order_date_key, customer_key, branch_key,
        promo_key, order_type, order_hour, quantity, unit_price,
        gross_sales_amt, discount_amt, net_sales_amt,
        etl_batch_id, load_dt, dq_flag)
    SELECT v.order_no,
           NVL(p.product_key, -1),
           NVL(d.date_key,    -1),
           NVL(c.customer_key,-1),
           NVL(b.branch_key,  -1),
           NVL(pr.promo_key,   0),          /* no promotion -> key 0, not -1 */
           v.order_type,
           v.order_hour,
           v.quantity,
           v.unit_price,
           v.gross_sales_amt,
           v.discount_amt,
           v.net_sales_amt,
           p_batch_id, SYSDATE,
           CASE WHEN p.product_key IS NULL OR c.customer_key IS NULL
                  OR b.branch_key  IS NULL OR d.date_key     IS NULL
                THEN 'S' ELSE v.dq_flag
           END
    FROM       VW_SALES_CLEAN v
    LEFT  JOIN PRODUCT_DIM   p  ON p.item_id      = v.item_id
    LEFT  JOIN DATE_DIM      d  ON d.cal_date     = v.order_date
    LEFT  JOIN BRANCH_DIM    b  ON b.branch_id    = v.branch_id
    LEFT  JOIN PROMOTION_DIM pr ON pr.promotion_id = v.promotion_id
    /* point-in-time version lookup — the SCD 2 join */
    LEFT  JOIN CUSTOMER_DIM  c  ON c.customer_id  = v.customer_id
                               AND v.order_date BETWEEN c.effective_start_date
                                                    AND c.effective_end_date
    WHERE  v.dq_flag <> 'E';

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'SALES_FACT',v_read,v_ins,v_rej,'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('SALES_FACT      loaded : '||v_ins||' rows, '
                         ||v_rej||' rejected');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'SALES_FACT',v_read,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/

CREATE OR REPLACE PROCEDURE PRC_LOAD_RETURNS_FACT (p_batch_id IN NUMBER) IS
    v_read NUMBER; v_ins NUMBER := 0; v_rej NUMBER := 0;
BEGIN
    PRC_AUDIT_START(p_batch_id,'RETURNS_FACT');
    SELECT COUNT(*) INTO v_read FROM VW_RETURNS_CLEAN;

    INSERT INTO ETL_ERROR_LOG (error_id, etl_batch_id, source_table,
                               source_key, error_type, error_detail)
    SELECT SEQ_ETL_ERROR.NEXTVAL, p_batch_id, 'STG_RETURNS',
           NVL(v.return_id,'(null)')||' / '||NVL(v.item_id,'(null)'),
           'REJECTED_ROW',
           'Failed mandatory validation: '
           || CASE WHEN v.return_id     IS NULL THEN 'missing return_id; '    END
           || CASE WHEN v.item_id       IS NULL THEN 'missing item_id; '      END
           || CASE WHEN v.return_date   IS NULL THEN 'invalid return_date; '  END
           || CASE WHEN v.qty_returned <= 0     THEN 'qty_returned <= 0; '    END
           || CASE WHEN v.refund_amount < 0     THEN 'negative refund; '      END
    FROM   VW_RETURNS_CLEAN v
    WHERE  v.dq_flag = 'E';
    v_rej := SQL%ROWCOUNT;

    /* DATE_DIM is joined TWICE — the role-playing dimension in action */
    INSERT INTO RETURNS_FACT (
        return_id, product_key, return_date_key, order_date_key, customer_key,
        branch_key, reason_key, promo_key, order_no, return_status,
        quantity_returned, refund_amount, days_to_return,
        etl_batch_id, load_dt, dq_flag)
    SELECT v.return_id,
           NVL(p.product_key,  -1),
           NVL(dr.date_key,    -1),         /* role 1: return date */
           NVL(do_.date_key,   -1),         /* role 2: original order date */
           NVL(c.customer_key, -1),
           NVL(b.branch_key,   -1),
           NVL(r.reason_key,   -1),
           NVL(pr.promo_key,    0),
           NVL(v.order_no,'UNKNOWN'),
           v.return_status,
           v.qty_returned,
           v.refund_amount,
           v.days_to_return,
           p_batch_id, SYSDATE,
           CASE WHEN p.product_key IS NULL OR c.customer_key IS NULL
                  OR b.branch_key  IS NULL OR r.reason_key   IS NULL
                  OR dr.date_key   IS NULL
                THEN 'S' ELSE v.dq_flag
           END
    FROM       VW_RETURNS_CLEAN v
    LEFT  JOIN PRODUCT_DIM       p   ON p.item_id       = v.item_id
    LEFT  JOIN DATE_DIM          dr  ON dr.cal_date     = v.return_date
    LEFT  JOIN DATE_DIM          do_ ON do_.cal_date    = v.order_date
    LEFT  JOIN BRANCH_DIM        b   ON b.branch_id     = v.branch_id
    LEFT  JOIN RETURN_REASON_DIM r   ON r.reason_id     = v.reason_id
    LEFT  JOIN PROMOTION_DIM     pr  ON pr.promotion_id = v.promotion_id
    LEFT  JOIN CUSTOMER_DIM      c   ON c.customer_id   = v.customer_id
                                    AND NVL(v.order_date, v.return_date)
                                        BETWEEN c.effective_start_date
                                            AND c.effective_end_date
    WHERE  v.dq_flag <> 'E';

    v_ins := SQL%ROWCOUNT;
    COMMIT;
    PRC_AUDIT_END(p_batch_id,'RETURNS_FACT',v_read,v_ins,v_rej,'SUCCESS');
    DBMS_OUTPUT.PUT_LINE('RETURNS_FACT    loaded : '||v_ins||' rows, '
                         ||v_rej||' rejected');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PRC_AUDIT_END(p_batch_id,'RETURNS_FACT',v_read,0,0,'FAILED',SQLERRM);
        RAISE;
END;
/


/* ============================================================================
   7. MASTER LOAD PROCEDURE
   One callable entry point for the whole first-time historical load. It
   allocates the batch id, disables the fact FKs for a faster bulk insert,
   runs the loads in dependency order, then re-enables the constraints — an
   ORA-02298 at that point would prove an orphan key had slipped through.
   ============================================================================ */
CREATE OR REPLACE PROCEDURE PRC_RUN_INITIAL_LOAD (
    p_start_date IN DATE DEFAULT DATE '2024-01-01',
    p_end_date   IN DATE DEFAULT DATE '2026-12-31'
) IS
    v_batch_id NUMBER;
BEGIN
    v_batch_id := SEQ_ETL_BATCH.NEXTVAL;
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE(' INITIAL HISTORICAL LOAD — batch '||v_batch_id);
    DBMS_OUTPUT.PUT_LINE(' Started '||TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    /* speed up the bulk fact insert */
    EXECUTE IMMEDIATE 'ALTER TABLE SALES_FACT   DISABLE CONSTRAINT fk_sales_customer';
    EXECUTE IMMEDIATE 'ALTER TABLE RETURNS_FACT DISABLE CONSTRAINT fk_ret_customer';

    /* --- dimensions first (parents) --- */
    PRC_LOAD_DATE_DIM     (v_batch_id, p_start_date, p_end_date);
    PRC_LOAD_PRODUCT_DIM  (v_batch_id);
    PRC_LOAD_BRANCH_DIM   (v_batch_id);
    PRC_LOAD_PROMOTION_DIM(v_batch_id);
    PRC_LOAD_REASON_DIM   (v_batch_id);
    PRC_LOAD_CUSTOMER_DIM (v_batch_id);

    /* --- facts second (children) --- */
    PRC_LOAD_SALES_FACT   (v_batch_id);
    PRC_LOAD_RETURNS_FACT (v_batch_id);

    /* VALIDATE forces Oracle to re-check every existing row */
    EXECUTE IMMEDIATE 'ALTER TABLE SALES_FACT   ENABLE VALIDATE CONSTRAINT fk_sales_customer';
    EXECUTE IMMEDIATE 'ALTER TABLE RETURNS_FACT ENABLE VALIDATE CONSTRAINT fk_ret_customer';

    /* refresh optimiser statistics so the BI queries get star transformation */
    DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);

    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE(' INITIAL LOAD COMPLETED — batch '||v_batch_id);
    DBMS_OUTPUT.PUT_LINE('=====================================================');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('INITIAL LOAD FAILED: '||SQLERRM);
        RAISE;
END;
/


/* ============================================================================
   8. SAMPLE STAGING DATA
   A small, deliberately IMPERFECT extract, so the transformation logic can be
   demonstrated rather than merely described. Note what is wrong on purpose:
     - mixed date formats  'YYYY-MM-DD' vs 'DD/MM/YYYY'
     - inconsistent codes  'A' / 'Active', 'WEB' / 'Online'
     - untrimmed values and mixed case
     - a duplicate product row (later load_seq must win)
     - C003 has THREE versions -> SCD 2 history
     - one sales row with quantity 0 -> must be REJECTED to ETL_ERROR_LOG
     - one sales row referencing a product that does not exist -> key -1
   ============================================================================ */

/* -- festive calendar ------------------------------------------------------ */
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-01-29','Chinese New Year');
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-01-30','Chinese New Year');
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-03-31','Hari Raya Aidilfitri');
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-04-01','Hari Raya Aidilfitri');
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-05-01','Labour Day');
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-08-31','Merdeka Day');
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-10-20','Deepavali');
INSERT INTO REF_FESTIVE_DAY VALUES (DATE '2025-12-25','Christmas');

/* -- products (P002 appears twice — the later load_seq wins) --------------- */
INSERT INTO STG_PRODUCT VALUES (1,'P001','  wireless mouse  ','A','59.90','Accessories','TechSupply Sdn Bhd','03-77812345');
INSERT INTO STG_PRODUCT VALUES (2,'P002','mechanical keyboard','ACTIVE','249.00','Accessories','TechSupply Sdn Bhd','03-77812345');
INSERT INTO STG_PRODUCT VALUES (3,'P003','27in LED MONITOR','A','899.00','Displays','Visionary Trading','04-2298877');
INSERT INTO STG_PRODUCT VALUES (4,'P004','usb-c hub',NULL,'129.50','Accessories','Gadget House','05-2551234');
INSERT INTO STG_PRODUCT VALUES (5,'P005','laptop stand','D','89.00','Accessories',NULL,NULL);
INSERT INTO STG_PRODUCT VALUES (6,'P002','Mechanical Keyboard RGB','A','269.00','Accessories','TechSupply Sdn Bhd','03-77812345');

/* -- branches -------------------------------------------------------------- */
INSERT INTO STG_BRANCH VALUES (1,'B01','KLCC Outlet','Kuala Lumpur','Kuala Lumpur','03-21611111');
INSERT INTO STG_BRANCH VALUES (2,'B02','Penang Gurney','George Town','Penang','04-2229999');
INSERT INTO STG_BRANCH VALUES (3,'B03','Johor Bahru City','Johor Bahru','Johor','07-3334444');
INSERT INTO STG_BRANCH VALUES (4,'B04','Kuching Central','Kuching','Sarawak','082-556677');
INSERT INTO STG_BRANCH VALUES (5,'B05','Kuantan Mall','Kuantan',NULL,'09-5142233');

/* -- promotions ------------------------------------------------------------ */
INSERT INTO STG_PROMOTION VALUES (1,'PR01','CNY Mega Sale','PCT','15','2025-01-20','2025-02-05','E');
INSERT INTO STG_PROMOTION VALUES (2,'PR02','Raya Bonanza','PERCENTAGE','20','2025-03-20','2025-04-05','EXPIRED');
INSERT INTO STG_PROMOTION VALUES (3,'PR03','Merdeka Deal','FIXED','50','31/08/2025','07/09/2025','E');
INSERT INTO STG_PROMOTION VALUES (4,'PR04','Year End Clearance','PCT','30','2025-12-01','2025-12-31','A');

/* -- return reasons -------------------------------------------------------- */
INSERT INTO STG_RETURN_REASON VALUES (1,'R01','Damaged on arrival');
INSERT INTO STG_RETURN_REASON VALUES (2,'R02','Wrong item delivered');
INSERT INTO STG_RETURN_REASON VALUES (3,'R03','Changed mind');
INSERT INTO STG_RETURN_REASON VALUES (4,'R04','Found cheaper price elsewhere');
INSERT INTO STG_RETURN_REASON VALUES (5,'R05','Product defective');

/* -- customers: C003 has THREE versions (None -> Silver -> Gold) ----------- */
INSERT INTO STG_CUSTOMER VALUES (1,'C001','ahmad bin ali','850101-14-5566','AHMAD@MAIL.COM','A','Y','Silver','50','2024-01-15');
INSERT INTO STG_CUSTOMER VALUES (2,'C002','Siti Nurhaliza','900215-10-2233','siti@mail.com','ACTIVE','N','None','0','2024-02-20');
INSERT INTO STG_CUSTOMER VALUES (3,'C003','Lim Wei Ming','880730-07-8899','lim@mail.com','A','N','None','0','2024-03-01');
INSERT INTO STG_CUSTOMER VALUES (4,'C003','Lim Wei Ming','880730-07-8899','lim@mail.com','A','Y','Silver','50','2025-01-10');
INSERT INTO STG_CUSTOMER VALUES (5,'C003','Lim Wei Ming','880730-07-8899','lim.wm@mail.com','A','Y','Gold','150','2025-07-01');
INSERT INTO STG_CUSTOMER VALUES (6,'C004','Raj Kumar','920512-08-1122','raj@mail.com','I','Y','Gold','150','2024-05-05');
INSERT INTO STG_CUSTOMER VALUES (7,'C005','  Tan Mei Ling ','950818-12-3344',NULL,'A','N','None','0','2025-02-14');

/* -- sales ----------------------------------------------------------------- */
INSERT INTO STG_SALES VALUES (1,'SO1001','2025-01-25','14:30','C001','B01','P001','PR01','INSTORE','2','59.90','10.00');
INSERT INTO STG_SALES VALUES (2,'SO1001','2025-01-25','14:30','C001','B01','P003','PR01','INSTORE','1','899.00','134.85');
INSERT INTO STG_SALES VALUES (3,'SO1002','25/01/2025','19:05','C003','B02','P002','PR01','WEB','1','269.00','40.35');
INSERT INTO STG_SALES VALUES (4,'SO1003','2025-04-02','11:15','C002','B01','P004',NULL,'ONLINE','3','129.50','0');
INSERT INTO STG_SALES VALUES (5,'SO1004','2025-07-15','16:45','C003','B03','P003',NULL,'IN-STORE','1','899.00','0');
INSERT INTO STG_SALES VALUES (6,'SO1005','2025-09-02','10:20','C004','B04','P005',NULL,'APP','2','89.00','5.00');
INSERT INTO STG_SALES VALUES (7,'SO1006','2025-12-10','20:00','C005','B05','P002','PR04','WEB','1','269.00','80.70');
INSERT INTO STG_SALES VALUES (8,'SO1007','2025-12-11','13:00','C001','B01','P999',NULL,'INSTORE','1','45.00','0');  /* unknown product -> -1 */
INSERT INTO STG_SALES VALUES (9,'SO1008','2025-12-12','09:30','C002','B02','P001',NULL,'INSTORE','0','59.90','0');  /* qty 0 -> REJECTED */

/* -- returns --------------------------------------------------------------- */
INSERT INTO STG_RETURNS VALUES (1,'RT2001','2025-02-03','SO1001','2025-01-25','C001','B01','P003','PR01','R01','A','1','764.15');
INSERT INTO STG_RETURNS VALUES (2,'RT2002','2025-04-10','SO1003','2025-04-02','C002','B01','P004',NULL,'R03','APPROVED','1','129.50');
INSERT INTO STG_RETURNS VALUES (3,'RT2003','2025-12-20','SO1006','2025-12-10','C005','B05','P002','PR04','R04','P','1','188.30');
INSERT INTO STG_RETURNS VALUES (4,'RT2004','2025-09-08','SO1005','2025-09-02','C004','B04','P005',NULL,'R05','REFUNDED','1','84.00');

COMMIT;


/* ============================================================================
   9. EXECUTION
   ============================================================================ */
BEGIN
    PRC_RUN_INITIAL_LOAD(DATE '2024-01-01', DATE '2026-12-31');
END;
/


/* ============================================================================
   10. VERIFICATION SELECTs
   Proof for the report that the load did what it claims.
   ============================================================================ */

/* 10.1 batch audit trail — what ran, how many rows, did it succeed */
SELECT etl_batch_id, target_table, rows_read, rows_inserted, rows_rejected,
       status,
       ROUND(EXTRACT(SECOND FROM (end_time - start_time)),2) AS secs
FROM   ETL_BATCH_CONTROL
ORDER  BY etl_batch_id, start_time;

/* 10.2 rejected rows and why */
SELECT source_table, source_key, error_detail
FROM   ETL_ERROR_LOG
ORDER  BY error_id;

/* 10.3 warehouse row counts */
SELECT 'DATE_DIM'          AS table_name, COUNT(*) AS row_count FROM DATE_DIM
UNION ALL SELECT 'PRODUCT_DIM',       COUNT(*) FROM PRODUCT_DIM
UNION ALL SELECT 'CUSTOMER_DIM',      COUNT(*) FROM CUSTOMER_DIM
UNION ALL SELECT 'BRANCH_DIM',        COUNT(*) FROM BRANCH_DIM
UNION ALL SELECT 'PROMOTION_DIM',     COUNT(*) FROM PROMOTION_DIM
UNION ALL SELECT 'RETURN_REASON_DIM', COUNT(*) FROM RETURN_REASON_DIM
UNION ALL SELECT 'SALES_FACT',        COUNT(*) FROM SALES_FACT
UNION ALL SELECT 'RETURNS_FACT',      COUNT(*) FROM RETURNS_FACT;

/* 10.4 *** SCD TYPE 2 PROOF *** — C003 must show 3 chained versions,
        contiguous dates, exactly one row flagged current */
SELECT customer_key, customer_id, membership_type, version_no,
       TO_CHAR(effective_start_date,'DD-MON-YYYY') AS valid_from,
       TO_CHAR(effective_end_date  ,'DD-MON-YYYY') AS valid_to,
       is_current_flag
FROM   CUSTOMER_DIM
WHERE  customer_id = 'C003'
ORDER  BY version_no;

/* 10.5 *** POINT-IN-TIME PROOF *** — C003's Jan-2025 order must attach to the
        SILVER version and the Jul-2025 order to the GOLD version */
SELECT s.order_no, d.cal_date AS order_date, c.customer_id,
       c.membership_type AS tier_at_time_of_sale, c.version_no, s.net_sales_amt
FROM   SALES_FACT s
JOIN   DATE_DIM     d ON d.date_key     = s.order_date_key
JOIN   CUSTOMER_DIM c ON c.customer_key = s.customer_key
WHERE  c.customer_id = 'C003'
ORDER  BY d.cal_date;

/* 10.6 referential integrity — every count must be ZERO */
SELECT 'sales orphan product'  AS check_name, COUNT(*) AS bad_rows
FROM   SALES_FACT f WHERE NOT EXISTS
       (SELECT 1 FROM PRODUCT_DIM d WHERE d.product_key = f.product_key)
UNION ALL
SELECT 'sales orphan customer', COUNT(*)
FROM   SALES_FACT f WHERE NOT EXISTS
       (SELECT 1 FROM CUSTOMER_DIM d WHERE d.customer_key = f.customer_key)
UNION ALL
SELECT 'returns orphan reason', COUNT(*)
FROM   RETURNS_FACT f WHERE NOT EXISTS
       (SELECT 1 FROM RETURN_REASON_DIM d WHERE d.reason_key = f.reason_key)
UNION ALL
SELECT 'more than one current row per customer', COUNT(*)
FROM   (SELECT customer_id FROM CUSTOMER_DIM WHERE is_current_flag='Y'
        GROUP BY customer_id HAVING COUNT(*) > 1);

/* 10.7 data-quality profile of the load */
SELECT 'SALES_FACT' AS tbl, dq_flag, COUNT(*) AS rows_loaded
FROM   SALES_FACT   GROUP BY dq_flag
UNION ALL
SELECT 'RETURNS_FACT', dq_flag, COUNT(*)
FROM   RETURNS_FACT GROUP BY dq_flag
ORDER  BY 1, 2;

/* 10.8 the warehouse actually answering a business question — DRILL-ACROSS
        the two facts on the conformed BRANCH and DATE dimensions.
        Each fact is aggregated to the common grain FIRST and the results are
        then joined. Joining the two fact tables directly would create a fan
        trap and inflate net_sales whenever a line has more than one return. */
WITH sales_q AS (
    SELECT b.region, d.cal_year_quarter AS quarter,
           SUM(s.net_sales_amt) AS net_sales
    FROM   SALES_FACT s
    JOIN   DATE_DIM   d ON d.date_key   = s.order_date_key
    JOIN   BRANCH_DIM b ON b.branch_key = s.branch_key
    GROUP  BY b.region, d.cal_year_quarter
),
returns_q AS (
    SELECT b.region, d.cal_year_quarter AS quarter,
           SUM(r.refund_amount) AS refunds
    FROM   RETURNS_FACT r
    JOIN   DATE_DIM   d ON d.date_key   = r.order_date_key
    JOIN   BRANCH_DIM b ON b.branch_key = r.branch_key
    GROUP  BY b.region, d.cal_year_quarter
)
SELECT s.region,
       s.quarter,
       s.net_sales,
       NVL(r.refunds,0)                                     AS refunds,
       ROUND(NVL(r.refunds,0) / NULLIF(s.net_sales,0)*100,2) AS return_rate_pct
FROM       sales_q   s
LEFT  JOIN returns_q r ON r.region  = s.region
                      AND r.quarter = s.quarter
ORDER  BY s.region, s.quarter;

/* ======================== END OF TASK 2(a) SCRIPT ========================= */
