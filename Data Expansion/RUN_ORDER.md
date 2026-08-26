# Data Expansion — run order

Extends the operational source from 2.5 years (2024–2026) to a full decade
(2016 → today), so Task 3 has trend, seasonality and channel-mix material.

**Additive only.** No existing row is updated or deleted. The 2,000 orders
already in `adm` keep their dates, their keys and their children.

---

## Step 1 — as ADM: back up

```sql
SQL> connect adm
SQL> @"C:\Users\PC\Desktop\DW\Data Expansion\00_backup_adm.sql"
```

Creates `*_BAK` copies of all 21 tables plus a row-count baseline.
**Do not skip this.** `99_rollback.sql` needs it.

## Step 2 — as ADM: extend promotions and build the existence-year tables

```sql
SQL> @"C:\Users\PC\Desktop\DW\Data Expansion\01_expand_promotions.sql"
```

Adds 32 promotions (4/year, 2016–2023) anchored to real CNY, Hari Raya,
Merdeka and year-end windows. Without these, every pre-2024 order line would
resolve to `promo_key = 0`.

Also builds `gen_customer_cohort`, `gen_item_launch` and `gen_branch_open` —
the "existence year" tables that stop a 2016 order referencing a customer,
item or branch that did not exist yet.

## Step 3 — as ADM: generate the history

```sql
SQL> @"C:\Users\PC\Desktop\DW\Data Expansion\02_expand_orders.sql"
```

Expect **1–3 minutes** — every insert fires the source's own triggers.
Adds roughly 5,400 orders and 15,000 order lines, plus their payments,
deliveries, returns and point transactions.

## Step 4 — as ADM: validate the source

```sql
SQL> @"C:\Users\PC\Desktop\DW\Data Expansion\03_validate_source.sql"
```

**Every check must read PASS before you go any further.** Validating here
costs one query; discovering the same problem inside a fact load means
reading an ORA-02291 out of a half-finished procedure.

## Step 5 — as DW: rebuild the warehouse

```sql
SQL> connect dw
SQL> @"C:\Users\PC\Desktop\DW\Task 1\Task1b_Physical_Design.sql"
SQL> @"C:\Users\PC\Desktop\DW\Task 2\Task 2a\CREATE_SEQUENCE.sql"
```

then every DIM script, every FACT script, the 2a driver, and:

```sql
SQL> SET SERVEROUTPUT ON
SQL> EXEC run_task2a_initial_load
```

## Step 6 — as DW: verify

```sql
SQL> @"C:\Users\PC\Desktop\DW\utils\verify_task2a.sql"
```

Gate 7 must now report **5,479 contiguous calendar days** (2016-01-01 →
2030-12-31). Gate 5 reconciles against the new source counts.

## Step 7 — as ADM: the dirty data for Task 2b

```sql
SQL> connect adm
SQL> @"C:\Users\PC\Desktop\DW\Task 2\Task 2b\insert_dirty_data.sql"
```

**This comes AFTER the initial load, never before.** The dirty rows break the
warehouse's own CHECK constraints deliberately — Test B lodges a return two
days before its order was placed, which makes `days_to_return = -2` and aborts
Task 2a on `chk_return_fact_days` with `ORA-02290`. The `GREATEST(...)` clamps
that neutralise those rows live in the Task 2b **incremental** procedures, not
in the initial load. That is the whole shape of Task 2b: the warehouse is
already built, faulty records then turn up in the source, and the incremental
load has to cope.

If you loaded the dirty data too early, run
`Data Expansion\04_remove_dirty_data.sql` as ADM, redo steps 5 and 6, then
come back here.

`ORD02001`, `ORD02002`, `DLV00642`, `DLV00643`, `RET00135` and `RET00136` are
reserved — step 3 winds the sequences past them, so nothing collides.

## Step 8 — as DW: Task 2b

```sql
SQL> connect dw
SQL> SET SERVEROUTPUT ON
SQL> EXEC run_task2b
SQL> @"C:\Users\PC\Desktop\DW\utils\compare_after_2b.sql"
```

---

## If it goes wrong

```sql
SQL> connect adm
SQL> @"C:\Users\PC\Desktop\DW\Data Expansion\99_rollback.sql"
```

Restores `adm` exactly as step 1 found it and resets the sequences. Then
rebuild the warehouse from step 6.

---

## Design decisions worth putting in the report

**Existence encoded by absence, not by new columns.** The source has no
`JoinDate`, no item launch date and no branch opening date. Rather than alter
the schema, a customer acquired in 2019 simply places no orders before 2019.
The acquisition curve, product rollout and branch expansion all emerge from
which rows exist, not from a new field.

**Derived values left to the source's triggers.** The generator never supplies
`OrderDetails.UnitPrice` or `Subtotal`, `Orders.TotalAmount`, `Payment.Amount`,
`ReturnDetails.RefundAmount`, `Returns.TotalRefundAmount`, Earn
`PointTransaction.Point`, or `Member.PointsBalance`. Generated rows are
therefore structurally identical to the hand-written ones. The cost is that
order lines are priced at the item's current list price — there is no
historical price drift, because introducing one would mean disabling
`trg_orderdetails_price`, which also derives the `Subtotal` that
`chk_orderdetails_subtotal` depends on.

**Deterministic for a given run date.** `DBMS_RANDOM.SEED(42)` fixes the random
stream, so two people running the generator on the same day get identical
data. The row counts still depend on `SYSDATE` — the current year is only
partly elapsed — so run it once and have the group work from that database
rather than each regenerating.

**All or nothing.** The generator holds one transaction and commits once at
the end. If anything raises, it rolls back to a completely clean source and
you fix and re-run. There is no half-generated state to clean up.

**Patterns designed, then generated, then discovered.**

| Pattern | How it shows up |
|---|---|
| Growth | 250 orders in 2016 rising to ~1,350 by 2025 |
| Pandemic shock | Deliberate 2020–21 dip, then recovery |
| Seasonality | CNY (Jan/Feb) and year-end (Nov/Dec) peaks, Jul/Aug lull |
| Channel mix | Online share climbing from 18% to ~55% |
| Branch rollout | 4 branches trading in 2016, all 12 by 2023 |
| Customer acquisition | 120 active customers in 2016, 1,000 by 2023 |
| Product range | 30 items listed in 2016, all 60 by 2023 |
| Weekly cycle | Weekends run about 1.5× weekdays |
| Hour of day | Evening peak 17:00–21:00 |
