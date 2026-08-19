CREATE OR REPLACE PROCEDURE load_date_dim AS
    v_batch_id NUMBER := 1;
    v_curr_date DATE := TO_DATE('2020-01-01', 'YYYY-MM-DD'); -- Starts in 2020
    v_end_date  DATE := TO_DATE('2030-12-31', 'YYYY-MM-DD'); -- Ends in 2030
BEGIN
    -- 1. Insert Seeded Unknown Row (Key -1)
    INSERT INTO date_dim (
        date_key, cal_date, full_desc, day_week, day_num_month, day_num_year,
        last_day_ind, cal_week_end_date, cal_week_year, cal_month_name,
        cal_month_year, cal_year_month, cal_quarter, cal_year_quarter, cal_year,
        holiday_ind, weekday_ind, festive_event, etl_batch_id, etl_load_dt, dq_flag
    ) VALUES (
        -1, DATE '1900-01-01', 'Unknown', 'Unknown', 0, 0,
        'N', DATE '1900-01-01', 0, 'Unknown',
        0, 'Unk-Unk', 'Q1', 'Unk-Q1', 0,
        'N', 'Y', 'None', v_batch_id, SYSDATE, 'V'
    );

    -- 2. Procedurally Generate Calendar Dates
    WHILE v_curr_date <= v_end_date LOOP
        INSERT INTO date_dim (
            date_key, cal_date, full_desc, day_week, day_num_month, day_num_year,
            last_day_ind, cal_week_end_date, cal_week_year, cal_month_name,
            cal_month_year, cal_year_month, cal_quarter, cal_year_quarter, cal_year,
            holiday_ind, weekday_ind, festive_event, etl_batch_id, etl_load_dt, dq_flag
        ) VALUES (
            TO_NUMBER(TO_CHAR(v_curr_date, 'YYYYMMDD')), 
            v_curr_date, TO_CHAR(v_curr_date, 'fmMonth DD, YYYY'), TO_CHAR(v_curr_date, 'fmDay'),
            EXTRACT(DAY FROM v_curr_date), TO_NUMBER(TO_CHAR(v_curr_date, 'DDD')),
            CASE WHEN v_curr_date = LAST_DAY(v_curr_date) THEN 'Y' ELSE 'N' END,
            v_curr_date + (7 - TO_NUMBER(TO_CHAR(v_curr_date, 'D'))), 
            TO_NUMBER(TO_CHAR(v_curr_date, 'WW')), TO_CHAR(v_curr_date, 'fmMonth'),
            EXTRACT(MONTH FROM v_curr_date), TO_CHAR(v_curr_date, 'YYYY-MM'),
            'Q' || TO_CHAR(v_curr_date, 'Q'), TO_CHAR(v_curr_date, 'YYYY') || '-Q' || TO_CHAR(v_curr_date, 'Q'),
            EXTRACT(YEAR FROM v_curr_date), 'N', 
            CASE WHEN TO_CHAR(v_curr_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN') THEN 'N' ELSE 'Y' END,
            'None', v_batch_id, SYSDATE, 'V'
        );
        v_curr_date := v_curr_date + 1;
    END LOOP;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DATE_DIM expanded load complete.');
END;
/