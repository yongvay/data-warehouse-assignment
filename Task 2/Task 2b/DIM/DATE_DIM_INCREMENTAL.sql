CREATE OR REPLACE PROCEDURE load_date_dim_incr (p_end_year IN NUMBER DEFAULT NULL) AS
    v_max_date DATE;
    v_target_date DATE;
    v_count NUMBER := 0;
BEGIN
    SELECT NVL(MAX(cal_date), DATE '2020-01-01') INTO v_max_date FROM date_dim WHERE date_key <> -1;
    v_target_date := v_max_date + 365; -- Adds 1 year of dates
    
    IF p_end_year IS NOT NULL AND p_end_year > 0 THEN
        v_target_date := TO_DATE(p_end_year || '-12-31', 'YYYY-MM-DD');
    END IF;

    WHILE v_max_date < v_target_date LOOP
        v_max_date := v_max_date + 1;
        INSERT INTO date_dim (
            date_key, cal_date, full_desc, day_week, day_num_month, day_num_year, last_day_ind, 
            cal_week_end_date, cal_week_year, cal_month_name, cal_month_year, cal_year_month, 
            cal_quarter, cal_year_quarter, cal_year, holiday_ind, weekday_ind, festive_event, etl_batch_id, etl_load_dt, dq_flag
        ) VALUES (
            TO_NUMBER(TO_CHAR(v_max_date, 'YYYYMMDD')), v_max_date, TO_CHAR(v_max_date, 'fmMonth DD, YYYY'), 
            TO_CHAR(v_max_date, 'fmDay'), EXTRACT(DAY FROM v_max_date), TO_NUMBER(TO_CHAR(v_max_date, 'DDD')),
            CASE WHEN v_max_date = LAST_DAY(v_max_date) THEN 'Y' ELSE 'N' END,
            v_max_date + (7 - TO_NUMBER(TO_CHAR(v_max_date, 'D'))), TO_NUMBER(TO_CHAR(v_max_date, 'WW')), 
            TO_CHAR(v_max_date, 'fmMonth'), EXTRACT(MONTH FROM v_max_date), TO_CHAR(v_max_date, 'YYYY-MM'),
            'Q' || TO_CHAR(v_max_date, 'Q'), TO_CHAR(v_max_date, 'YYYY') || '-Q' || TO_CHAR(v_max_date, 'Q'),
            EXTRACT(YEAR FROM v_max_date), 'N', 
            CASE WHEN TO_CHAR(v_max_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN') THEN 'N' ELSE 'Y' END,
            'None', 2, SYSDATE, 'V'
        );
        v_count := v_count + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DATE_DIM incremental load: ' || v_count || ' days added.');
END;
/