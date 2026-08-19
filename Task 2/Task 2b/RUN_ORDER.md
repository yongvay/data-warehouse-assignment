# Task 2(b) — Subsequent (Incremental) ETL Loading

88 Speedmart Grocery Data Warehouse · BMIT3003
Run everything as the **DW schema owner**, not as `adm`.

---

## 1. What to type in SQL*Plus right now

```sql
sqlplus dw/<password>@<service>

SQL> SET SERVEROUTPUT ON SIZE UNLIMITED
SQL> HOST cd "C:\Users\USER\Desktop\DWT\Task 2\Task 2b"
SQL> @RUN_ALL_TASK2B.sql
```

`RUN_ALL_TASK2B.sql` compiles all 17 objects in dependency order, checks that
nothing is INVALID, runs the load, and prints the three verification reports.

If you would rather install piece by piece, this is the order — it matters,
because each file depends on the one above it:

| # | File | Creates |
|---|------|---------|
| 0 | `00_ETL_CONTROL_DDL.sql` | `etl_batch_control`, `etl_step_log`, `etl_reject_log`, 3 sequences, package `etl_ctl` |
| 1 | `01_SCRUB_FUNCTIONS.sql` | package `etl_scrub` — 22 cleansing functions |
| 2 | `02_STAGING_VIEWS.sql` | 12 `vw_stg_*` views (Extract + Transform) |
| 3 | `DIM/DATE_DIM_EXTEND.sql` | `extend_date_dim` |
| 4 | `DIM/RETURN_REASON_DIM_DELTA.sql` | `load_return_reason_dim_delta` |
| 5 | `DIM/DELIVERY_COMPANY_DIM_DELTA.sql` | `load_delivery_company_dim_delta` |
| 6 | `DIM/BRANCH_DIM_DELTA.sql` | `load_branch_dim_delta` |
| 7 | `DIM/ADDRESS_DIM_DELTA.sql` | `load_address_dim_delta` |
| 8 | `DIM/PROMOTION_DIM_DELTA.sql` | `load_promotion_dim_delta` |
| 9 | `DIM/ITEM_DIM_DELTA.sql` | `load_item_dim_delta` |
| 10 | `DIM/CUSTOMER_DIM_SCD2.sql` | `load_customer_dim_scd2` ← the Type 2 procedure |
| 11 | `FACT/SALES_FACT_DELTA.sql` | `load_sales_fact_delta` |
| 12 | `FACT/RETURN_FACT_DELTA.sql` | `load_return_fact_delta` |
| 13 | `FACT/DELIVERY_FACT_DELTA.sql` | `load_delivery_fact_delta` |
| 14 | `FACT/POINT_FACT_DELTA.sql` | `load_point_fact_delta` |
| 15 | `03_RECON_VIEWS.sql` | 7 verification views |
| 16 | `99_run_task2b_subsequent_load.sql` | `run_task2b_subsequent_load` — the driver |

Then:

```sql
SQL> EXEC run_task2b_subsequent_load
```

---

## 2. Before you run: three things must already be true

```sql
-- (a) Task 1b tables exist and Task 2a populated them
SELECT COUNT(*) FROM customer_dim;    -- should be > 1
SELECT COUNT(*) FROM sales_fact;      -- should be > 0

-- (b) You can read the operational schema
SELECT COUNT(*) FROM adm.Orders;      -- ORA-00942 => re-run Task1b_Grants_RunAsADM.sql as adm

-- (c) The Task 2a sequences exist (2b reuses them, it does not recreate them)
SELECT sequence_name FROM user_sequences ORDER BY 1;
--   expect seq_dw_address, seq_dw_branch, seq_dw_company, seq_dw_cust,
--          seq_dw_item, seq_dw_promo, seq_dw_reason
```

---

## 3. Verifying the run (these are your report screenshots)

```sql
SET LINESIZE 200
SET PAGESIZE 100

-- What every batch did
SELECT * FROM vw_etl_batch_summary;

-- What each table did in the latest batch
SELECT * FROM vw_etl_step_summary
 WHERE batch_id = (SELECT MAX(batch_id) FROM etl_batch_control);

-- Which cleansing rules fired, and how often
SELECT * FROM vw_etl_reject_summary
 WHERE batch_id = (SELECT MAX(batch_id) FROM etl_batch_control);

-- Row-level evidence for a single rule
SELECT source_key, column_name, raw_value, rule_desc, action_taken
  FROM etl_reject_log
 WHERE rule_code = 'R803';

-- Current cleanliness of the whole warehouse
SELECT * FROM vw_dw_dq_dashboard ORDER BY table_name, dq_flag;

-- Source vs warehouse row counts
SELECT * FROM vw_dw_reconciliation;

-- Type 2 history, and the defect check that MUST be empty
SELECT * FROM vw_scd2_customer_history;
SELECT * FROM vw_scd2_integrity_check;
```

**Idempotency proof.** Run `EXEC run_task2b_subsequent_load` twice with no
source change in between. The second batch must show `ins=0 upd=0` on every
line of `vw_etl_step_summary`. Put both batches in the report side by side —
it is the cleanest single piece of evidence that the load is genuinely
incremental and not a reload.

---

## 4. How the incremental logic works (for the write-up)

**Delta detection is an anti-join on the declared grain, not a date
high-water mark.** `adm` has no `last_modified` column, and even if it had,
a high-water mark on `OrderDateTime` would silently miss a back-dated order
inserted after the previous run. Each load therefore asks "is this business
key already in the target, and if so have its attributes changed?" The
high-water marks are still recorded in `etl_batch_control` (`hwm_order_dt`
and friends) as audit metadata.

**Changed facts are deleted and re-inserted, not updated.** `order_date_key`,
`customer_key`, `item_key`, `branch_key` and `promo_key` are all inside
`sales_fact_pk`, so a restated line cannot be `UPDATE`d in place. The delete
and the insert share one transaction, so the fact is never observably missing.

**Late-arriving dimensions never drop a fact.** Every dimension lookup is a
`LEFT JOIN` wrapped in `NVL(..., -1)` — or `NVL(..., 0)` for `promo_key`,
whose "No Promotion" seed is key 0.

**Type 2 customer resolution is point-in-time.** Facts join the customer
version that was effective on the transaction date (half-open interval
`[effective_start_date, effective_end_date)`, so exactly one version can
match), falling back to the current version for transactions that pre-date
the first version row created by the initial load.

---

## 5. Data-scrubbing rules implemented

Every rule has a code that appears in `etl_reject_log.rule_code`.

| Code | Defect | Action |
|------|--------|--------|
| R101 | Customer business key missing | REJECT row |
| R102 | Name blank, or punctuation/digits only | → `'Unknown'` |
| R103 | Email fails RFC-shaped regex | → `'Unknown'` |
| R104 | NRIC not 12 digits | → `'Unknown'` |
| R105 | Status outside `Active/Inactive` | → `'Unknown'` |
| R106 | Negative annual fee or earn rate | clamp to 0 |
| R201 | ItemID missing | REJECT row |
| R202/R203 | Orphan CategoryID / SupplierID | → `'UNKN'` seed |
| R204 | Null or negative unit price | → 0 |
| R205 | Item status outside domain | → `'Unknown'` |
| R301 | BranchID missing | REJECT row |
| R302/R303 | State unrecognised / non-canonical spelling | canonicalise, else `'Unknown'` |
| R304 | Contact number not 9–15 digits | → `'Unknown'` |
| R401–R404 | Address key, blank line, bad state, bad postcode | default / `'00000'` |
| R501/R502 | PromotionID missing, or reuses reserved `NONE`/`UNKN` | REJECT row |
| R503 | Promo end date before start date | end reset to start |
| R504 | Null promo dates | 1900-01-01 / 9999-12-31 |
| R505/R506 | Negative discount, percentage above 100 | clamp to 0 / 100 |
| R601/R602 | Reason key missing / text outside domain | REJECT / `'Unknown'` |
| R701–R703 | Courier key, name, phone | REJECT / `'Unknown'` |
| R801/R802 | OrderNo, ItemID, customer or branch missing | REJECT row |
| R803 | Quantity null or ≤ 0 | REJECT row (`chk_sales_fact_qty`) |
| R804 | Unit price null or negative | fall back to `Item.UnitPrice` |
| R805 | Null order date | `date_key = -1` |
| R806 | Order type not `Online`/`Walk-in` | canonicalise |
| R807 | Discount exceeds gross sales | cap so `net_sales_amt >= 0` |
| R901/R902 | Return key missing / quantity ≤ 0 | REJECT row |
| R903 | Return dated before its order | `days_to_return` floored at 0 |
| R904 | Negative refund | clamp to 0 |
| R905/R906 | Null return date / missing reason | `-1` seeded keys |
| RA01 | DeliveryID missing | REJECT row |
| RA02 | Not yet despatched | `delivery_date_key = -1` |
| RA03 | Delivered before ordered | lead days floored at 0 |
| RA04/RA05 | Negative charge or order total | clamp to 0 |
| RA06 | Delivery status outside domain | canonicalise |
| RA07 | Missing address | `address_key = -1` |
| RB01/RB02 | PointTransID missing / TransType unresolvable | REJECT row |
| RB03 | `Earn` with no OrderNo | REJECT row (`chk_point_fact_order`) |
| RB04 | `Redeem` carrying an OrderNo | strip the OrderNo |
| RB05 | Null or negative point value | absolute value |
| RB06 | Null transaction date | `date_key = -1` |

Plus one rule with no code, applied by every view: **duplicate source rows on
the declared grain are collapsed to one** by `ROW_NUMBER() ... WHERE rn = 1`.
Duplicates are the most common cause of an incremental load dying on
`ORA-00001`, so the grain is enforced in the view rather than discovered by
the database.

---

## 6. Two gaps in Task 2(a) worth fixing before submission

Both are cheap, and both are things the rubric names explicitly.

1. **Task 2a has no `VIEW`s.** The mark scheme for 2a reads *"Robust creation of
   SQL **views**, select blocks, and stored procedures"*. The 2a procedures go
   straight from `adm.*` to `INSERT`. The easiest fix that costs nothing: point
   the 2a procedures at the `vw_stg_*` views this task creates, so both halves
   of Task 2 share one Extract+Transform layer. Mention that in the report as a
   design decision rather than a patch.

2. **`v_batch_id NUMBER := 1;` is hard-coded in all twelve 2a procedures.**
   Replace with `etl_ctl.current_batch` and have 2a call
   `etl_ctl.start_batch('INITIAL')` first. `00_ETL_CONTROL_DDL.sql` already
   back-fills batch 1 as the historical load, so existing rows stay consistent
   either way.

Optional but useful for screenshots: `test/DEMO_dirty_and_scd2.sql` injects one
example of each defect class into `adm` (run it as the `adm` owner) so the next
load visibly produces a Type 2 version, a Type 1 overwrite, a scrubbed value, a
rejected row and a pending→delivered transition.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ORA-00942` on a `vw_stg_*` view | missing `SELECT` grant on an `adm` table | re-run `Task 1/Task1b_Grants_RunAsADM.sql` as `adm` |
| `ORA-20001 No ETL batch is open` | a load procedure was called directly | call `EXEC run_task2b_subsequent_load`, or `etl_ctl.start_batch` first |
| Package compiles `INVALID` | an `adm` table or column name differs from what the views assume | `SHOW ERRORS PACKAGE BODY etl_scrub` / `SELECT * FROM user_errors` |
| `ORA-02291` on a fact insert | a date outside the calendar | `extend_date_dim` runs first in the driver; check it did not fail |
| `ORA-00001` on `*_grain_uq` | duplicates in the source beyond the assumed grain | widen the `PARTITION BY` in the relevant `vw_stg_*` view |
| Second run still shows inserts | attribute comparison missing a column | add the column to the `EXISTS (... OR ...)` list in that procedure |
