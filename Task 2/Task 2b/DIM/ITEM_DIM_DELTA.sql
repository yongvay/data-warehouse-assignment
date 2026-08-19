-- ============================================================================
--  TASK 2(b) : ITEM_DIM  -  incremental Type 1 load
-- ----------------------------------------------------------------------------
--  NOTE ON THE TYPE 1 CHOICE
--    item_unit_price is overwritten rather than versioned because SALES_FACT
--    already stores the price that was actually charged on each line.  The
--    dimension therefore only needs the CURRENT list price, and no history is
--    lost by overwriting it.
-- ============================================================================
SET DEFINE OFF

CREATE OR REPLACE PROCEDURE load_item_dim_delta AS
    v_batch NUMBER := etl_ctl.current_batch;
    v_ins   NUMBER := 0;
    v_upd   NUMBER := 0;
    v_rej   NUMBER := 0;
    v_scr   NUMBER := 0;
BEGIN
    -- 1. UPDATE changed items
    UPDATE item_dim d
       SET (item_name, item_unit_price, item_status, category_id, category_name,
            supplier_id, supplier_name, supplier_contact_no,
            etl_update_dt, etl_batch_id, dq_flag) =
           (SELECT s.item_name, s.item_unit_price, s.item_status,
                   s.category_id, s.category_name, s.supplier_id,
                   s.supplier_name, s.supplier_contact_no,
                   SYSDATE, v_batch, s.dq_flag
              FROM vw_stg_item s
             WHERE s.item_id = d.item_id)
     WHERE d.item_key <> -1
       AND EXISTS (SELECT 1
                     FROM vw_stg_item s
                    WHERE s.item_id = d.item_id
                      AND s.dq_flag <> 'D'
                      AND (   s.item_name           <> d.item_name
                           OR s.item_unit_price     <> d.item_unit_price
                           OR s.item_status         <> d.item_status
                           OR s.category_id         <> d.category_id
                           OR s.category_name       <> d.category_name
                           OR s.supplier_id         <> d.supplier_id
                           OR s.supplier_name       <> d.supplier_name
                           OR s.supplier_contact_no <> d.supplier_contact_no));
    v_upd := SQL%ROWCOUNT;

    -- 2. INSERT new items
    INSERT INTO item_dim
        (item_key, item_id, item_name, item_unit_price, item_status,
         category_id, category_name, supplier_id, supplier_name,
         supplier_contact_no, etl_batch_id, dq_flag)
    SELECT seq_dw_item.NEXTVAL, s.item_id, s.item_name, s.item_unit_price,
           s.item_status, s.category_id, s.category_name, s.supplier_id,
           s.supplier_name, s.supplier_contact_no, v_batch, s.dq_flag
      FROM vw_stg_item s
     WHERE s.dq_flag <> 'D'
       AND NOT EXISTS (SELECT 1 FROM item_dim d WHERE d.item_id = s.item_id);
    v_ins := SQL%ROWCOUNT;

    -- 3. AUDIT
    FOR r IN (SELECT item_id, raw_price, raw_status, dq_flag, dq_note
                FROM vw_stg_item
               WHERE dq_flag IN ('S','D'))
    LOOP
        etl_ctl.log_reject('ADM.ITEM', r.item_id, 'ITEM_DIM',
                           'UNITPRICE/STATUS',
                           TO_CHAR(r.raw_price) || ' / ' || r.raw_status,
                           NVL(SUBSTR(r.dq_note, 1, 4), 'R000'),
                           NVL(r.dq_note, 'value standardised by scrubbing rules'),
                           CASE WHEN r.dq_flag = 'D' THEN 'REJECTED'
                                ELSE 'SCRUBBED' END);
        IF r.dq_flag = 'D' THEN v_rej := v_rej + 1;
        ELSE                    v_scr := v_scr + 1;
        END IF;
    END LOOP;

    COMMIT;
    etl_ctl.log_step('ITEM_DIM', v_ins, v_upd, v_rej, v_scr);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        etl_ctl.log_step('ITEM_DIM', 0, 0, 0, 0, 'FAILED');
        RAISE;
END load_item_dim_delta;
/
SHOW ERRORS
