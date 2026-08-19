-- ============================================================================
--  TASK 2(b) : DATE_DIM  -  calendar extension
-- ----------------------------------------------------------------------------
--  WHY THIS RUNS FIRST
--    Every fact table has a foreign key onto DATE_DIM.  Task 2(a) generated the
--    calendar for 2020-01-01 .. 2030-12-31 only.  If the operational system
--    ever produces a transaction outside that window - a back-dated correction
--    or a forward-dated pre-order - the fact insert fails with ORA-02291.
--
--    Rather than let the load break, this procedure widens the calendar to
--    cover the full span of dates actually present in the source, and also
--    fills any gap inside the existing range.  It is idempotent: re-running it
--    inserts nothing once the calendar is complete.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE extend_date_dim AS
    v_batch     NUMBER := etl_ctl.current_batch;
    v_src_min   DATE;
    v_src_max   DATE;
    v_dim_min   DATE;
    v_dim_max   DATE;
    v_start     DATE;
    v_end       DATE;
    v_ins       NUMBER := 0;
BEGIN
    ------------------------------------------------------------------
    -- 1. What date range does the source actually need?
    ------------------------------------------------------------------
    SELECT MIN(d), MAX(d)
      INTO v_src_min, v_src_max
      FROM (
            SELECT TRUNC(OrderDateTime) AS d FROM adm.Orders
             WHERE OrderDateTime IS NOT NULL
            UNION ALL
            SELECT TRUNC(ReturnDate)         FROM adm.Returns
             WHERE ReturnDate    IS NOT NULL
            UNION ALL
            SELECT TRUNC(DeliveryDate)       FROM adm.Delivery
             WHERE DeliveryDate  IS NOT NULL
            UNION ALL
            SELECT TRUNC(TransDate)          FROM adm.PointTransaction
             WHERE TransDate     IS NOT NULL
           );

    IF v_src_min IS NULL THEN
        etl_ctl.log_step('DATE_DIM', 0, 0, 0, 0);
        RETURN;
    END IF;

    ------------------------------------------------------------------
    -- 2. What does the calendar already cover?  (ignore the -1 seed)
    ------------------------------------------------------------------
    SELECT MIN(cal_date), MAX(cal_date)
      INTO v_dim_min, v_dim_max
      FROM date_dim
     WHERE date_key <> -1;

    v_start := LEAST   (NVL(v_dim_min, v_src_min), v_src_min);
    v_end   := GREATEST(NVL(v_dim_max, v_src_max), v_src_max);

    ------------------------------------------------------------------
    -- 3. Insert every calendar day in the range that is not there yet
    ------------------------------------------------------------------
    INSERT INTO date_dim
        (date_key, cal_date, full_desc, day_week, day_num_month, day_num_year,
         last_day_ind, cal_week_end_date, cal_week_year, cal_month_name,
         cal_month_year, cal_year_month, cal_quarter, cal_year_quarter, cal_year,
         holiday_ind, weekday_ind, festive_event, etl_batch_id, etl_load_dt, dq_flag)
    SELECT
        TO_NUMBER(TO_CHAR(g.d, 'YYYYMMDD')),
        g.d,
        TO_CHAR(g.d, 'fmMonth DD, YYYY'),
        TO_CHAR(g.d, 'fmDay'),
        EXTRACT(DAY FROM g.d),
        TO_NUMBER(TO_CHAR(g.d, 'DDD')),
        CASE WHEN g.d = LAST_DAY(g.d) THEN 'Y' ELSE 'N' END,
        g.d + (7 - TO_NUMBER(TO_CHAR(g.d, 'D'))),
        TO_NUMBER(TO_CHAR(g.d, 'WW')),
        TO_CHAR(g.d, 'fmMonth'),
        EXTRACT(MONTH FROM g.d),
        TO_CHAR(g.d, 'YYYY-MM'),
        'Q' || TO_CHAR(g.d, 'Q'),
        TO_CHAR(g.d, 'YYYY') || '-Q' || TO_CHAR(g.d, 'Q'),
        EXTRACT(YEAR FROM g.d),
        'N',
        CASE WHEN TO_CHAR(g.d, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT','SUN')
             THEN 'N' ELSE 'Y' END,
        'None',
        v_batch, SYSDATE, 'V'
    FROM (
        SELECT v_start + LEVEL - 1 AS d
          FROM dual
        CONNECT BY LEVEL <= (v_end - v_start) + 1
    ) g
    WHERE NOT EXISTS (SELECT 1 FROM date_dim dd
                       WHERE dd.date_key = TO_NUMBER(TO_CHAR(g.d, 'YYYYMMDD')));
    v_ins := SQL%ROWCOUNT;

    COMMIT;
    etl_ctl.log_step('DATE_DIM', v_ins, 0, 0, 0);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('DATE_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END extend_date_dim;
/
SHOW ERRORS
