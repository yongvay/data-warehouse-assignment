# 88 Speedmart Data Warehouse — How To Run It

**BMIT3003 Data Warehouse Technology — Assignment**

This is the run guide for the whole project, Task 1 through Task 3. If you follow
it top to bottom on a clean Oracle instance you will end up with a loaded
warehouse and reproducible Task 3 reports.

Read **[The one rule that saves you an hour](#the-one-rule-that-saves-you-an-hour)**
before you run anything.

---

## Contents

- [What you need first](#what-you-need-first)
- [The one rule that saves you an hour](#the-one-rule-that-saves-you-an-hour)
- [What lives where](#what-lives-where)
- [The run order](#the-run-order)
  - [Stage 0 — Build the operational source (as ADM)](#stage-0--build-the-operational-source-as-adm)
  - [Stage 1 — Expand the source to 2016–2026 (as ADM)](#stage-1--expand-the-source-to-20162026-as-adm)
  - [Stage 2 — Task 1: build the warehouse schema (as DW)](#stage-2--task-1-build-the-warehouse-schema-as-dw)
  - [Stage 3 — Task 2(a): initial historical load (as DW)](#stage-3--task-2a-initial-historical-load-as-dw)
  - [Stage 4 — Task 2(b): incremental load (ADM then DW)](#stage-4--task-2b-incremental-load-adm-then-dw)
  - [Stage 5 — Task 3: analytics reports and charts (as DW)](#stage-5--task-3-analytics-reports-and-charts-as-dw)
- [Quick reference card](#quick-reference-card)
- [Reloading without rebuilding](#reloading-without-rebuilding)
- [Troubleshooting](#troubleshooting)
- [Files you should NOT run](#files-you-should-not-run)

---

## What you need first

| Thing | Detail |
|---|---|
| Oracle | 12.2 or later. Oracle XE / Free 23ai is fine. Developed against service `FREEPDB1`. |
| Two database users | **`adm`** owns the operational (source) system. **`dw`** owns the warehouse. |
| Client | SQL\*Plus or SQL Developer. Every instruction below is written for SQL\*Plus. |
| Python (Task 3 charts only) | 3.9+, with `pip install oracledb matplotlib pandas numpy jupyter` |

Create the two users once, as a DBA:

```sql
CREATE USER adm IDENTIFIED BY <password>;
CREATE USER dw  IDENTIFIED BY <password>;
GRANT CONNECT, RESOURCE, UNLIMITED TABLESPACE TO adm;
GRANT CONNECT, RESOURCE, UNLIMITED TABLESPACE TO dw;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE SEQUENCE TO dw;
```

> ### ⚠ The operational user must be called `adm`
>
> The ETL reads the source with fully-qualified names — `SELECT ... FROM adm.Orders`
> — in **147 places across 17 files**. There are no synonyms and nothing reads the
> schema name from a variable. If your operational user has a different name, you
> must find-and-replace `adm.` across `Task 2/` before anything will compile.
> Naming the user `adm` is far less work.

---

## The one rule that saves you an hour

**Always start SQL\*Plus from the repository root.**

```powershell
cd "C:\path\to\data-warehouse-assignment"
sqlplus dw/<password>@localhost:1521/FREEPDB1
```

Every path in this guide, and every `@` call in every script, is written relative
to that folder. Start SQL\*Plus from anywhere else and you get `SP2-0310: unable to
open file`.

Two related notes:

- Paths with spaces **must** be quoted: `@"Task 2\Task 2a\compile_task2a.sql"`.
  Forward slashes work too.
- The compile scripts call their children with `@@` (double-at), which SQL\*Plus
  resolves relative to *the script's own folder*, not your working directory. That
  is why they keep working no matter where the repo is checked out. **Do not change
  `@@` back to absolute paths** — that is exactly the bug this guide exists to
  prevent.

---

## What lives where

| Folder | What it is | Who runs it |
|---|---|---|
| `adm/` | The **operational source** system — the OLTP database the warehouse is loaded *from*. Carried over from the previous assignment; the `Task2`/`Task3` in the filenames refer to *that* assignment, not this one. | ADM |
| `Data Expansion/` | Additive generator that stretches the source from 2.5 years to a decade (2016 → today), so Task 3 has real trend and seasonality. Has its own [RUN_ORDER.md](Data%20Expansion/RUN_ORDER.md). | ADM |
| `Task 1/` | Task 1(a) logical design (`.md`) and Task 1(b) physical design DDL, plus the cross-schema grants. | ADM + DW |
| `Task 2/Task 2a/` | **Initial historical load.** Views + `load_*` procedures + the driver + the gate check. | DW |
| `Task 2/Task 2b/` | **Incremental load.** `load_*_incr` procedures, SCD Type 2 maintenance, and the dirty-data injection. | ADM + DW |
| `Task 3/<name>/` | Per-student analytics: one `.sql` of reports and one charting notebook. | DW |
| `Task 3 output/<name>/` | Where the spooled report text and the chart PNGs land. | — |
| `utils/` | Diagnostics and housekeeping. Nothing here is a deliverable; all of it is safe to run except `delete_table.sql`, which empties the warehouse. | DW |
| `Star Schema/` | Star-schema diagrams (PNG/SVG) and the Word logical design. Not executable. | — |
| `docs/` | Assignment brief, marking rubric, sample reports, and the Task 3 report-idea catalogue. | — |

---

## The run order

Do these in order. Each stage assumes the one before it finished clean.

### Stage 0 — Build the operational source (as ADM)

Skip this if the source database already exists and you do not want to lose it —
`Task2_DDL.sql` opens with `DROP TABLE ... CASCADE CONSTRAINTS` on all 21 tables.

```sql
sqlplus adm/<password>@localhost:1521/FREEPDB1

SQL> @"adm\Task2_DDL.sql"           -- 21 tables, sequences, triggers
SQL> @"adm\Task3_Inserts_Data.sql"  -- base data, 2024-2026 (~16k lines, be patient)
```

Then grant the warehouse read access to the source. **Still connected as ADM:**

```sql
SQL> @"Task 1\Task1b_Grants_RunAsADM.sql"
```

That grants `SELECT` on the 18 source tables the ETL reads. The synonym block at
the bottom of that file is commented out and can stay that way — the ETL uses
`adm.`-qualified names, so synonyms are not needed.

**Check it worked** — connect as `dw` and run:

```sql
SQL> @"utils\check_status.sql"
```

Section 2 must list **18 tables** owned by `ADM`. Zero rows means the grants never ran.

---

### Stage 1 — Expand the source to 2016–2026 (as ADM)

Only the base data from Stage 0 is not enough for Task 3 — every year-on-year,
seasonality and channel-mix report needs a decade of history.

Follow **[Data Expansion/RUN_ORDER.md](Data%20Expansion/RUN_ORDER.md)** steps 1–4.
In short:

```sql
sqlplus adm/<password>@localhost:1521/FREEPDB1

SQL> @"Data Expansion\00_backup_adm.sql"        -- creates *_BAK copies. DO NOT SKIP.
SQL> @"Data Expansion\01_expand_promotions.sql"
SQL> @"Data Expansion\02_expand_orders.sql"     -- 1-3 minutes
SQL> @"Data Expansion\03_validate_source.sql"   -- every check must read PASS
```

Two things worth knowing:

- **`00_backup_adm.sql` is not optional.** `99_rollback.sql` restores from those
  `_BAK` tables and cannot work without them.
- **Run the generator once, then share that database.** It is seeded
  (`DBMS_RANDOM.SEED(42)`) so it is deterministic *for a given run date*, but row
  counts depend on `SYSDATE`. Two people generating on different days get different
  data, and then your Task 3 numbers will not match each other's.

If `03_validate_source.sql` reports anything other than PASS, stop and fix it here.
Finding the same problem later means reading an `ORA-02291` out of the middle of a
half-finished fact load.

---

### Stage 2 — Task 1: build the warehouse schema (as DW)

```sql
sqlplus dw/<password>@localhost:1521/FREEPDB1

SQL> @"Task 1\Task1b_Physical_Design.sql"     -- 8 dimensions + 4 facts
SQL> @"Task 2\Task 2a\CREATE_SEQUENCE.sql"    -- 7 surrogate-key sequences
```

`Task1b_Physical_Design.sql` drops and recreates all 12 warehouse tables, so it is
safe to re-run. `CREATE_SEQUENCE.sql` drops each sequence before creating it, so it
is safe to re-run too — and it **must** be re-run after `Task1b_Physical_Design.sql`,
because `DROP TABLE` does not remove sequences and a surviving sequence would start
your rebuilt warehouse's keys at 1002 instead of 1.

Task 1(a), the logical design, is documentation rather than code:
[Task 1/Task1a_Logical_Design.md](Task%201/Task1a_Logical_Design.md), with the star
diagrams in `Star Schema/`.

---

### Stage 3 — Task 2(a): initial historical load (as DW)

```sql
SQL> @"Task 2\Task 2a\compile_task2a.sql"
```

This compiles all 8 dimension scripts, all 4 fact scripts and the driver, in
dependency order, then prints three report blocks. **All three must be empty / zero
before you continue:**

1. *Missing or invalid objects* — must be 0 rows
2. *Compilation errors* — must be 0 rows
3. *Is the compiled logic actually current?* — every count must read 0

> ### Why this script exists — the trap that cost this project a day
>
> `DROP TABLE` does not drop procedures. Rebuilding the warehouse replaces the
> tables but leaves whatever `load_*` procedures were last compiled sitting in the
> schema. The "rebuild" then reloads happily using **months-old ETL logic**, with no
> error and no warning. That is how a stale `load_date_dim` kept building a 2020
> calendar long after the file on disk had been changed to 2016.
>
> **Run `compile_task2a.sql` after any edit to a Task 2(a) script, and always as
> part of a rebuild.** The third report block exists purely to catch this: it reads
> `user_source` and tells you what the database will *actually* execute, whatever the
> file on disk says.

Then load:

```sql
SQL> SET SERVEROUTPUT ON
SQL> EXEC run_task2a_initial_load
```

Phase 1 loads the 8 dimensions, phase 2 the 4 facts. Expect
`--- TASK 2A SUCCESSFULLY COMPLETED ---`.

Then verify:

```sql
SQL> @"Task 2\Task 2a\verify_task2a.sql"
```

Ten gates. **Every one must pass before you touch Task 2b.** The ones that catch
the most mistakes:

| Gate | Checks |
|---|---|
| 1 | Every procedure and view compiled |
| 4 | Every dimension has its `-1` "Unknown" row |
| 5 | Source ↔ warehouse row-count reconciliation |
| 7 | `date_dim` covers the window Task 2b will use — expect **5,479 days**, 2016-01-01 → 2030-12-31 |
| 10 | Saves the baseline snapshot that Task 2b's comparison needs |

Gate 10 matters even though it is not a pass/fail check: it stores the *before*
row counts. Skip `verify_task2a.sql` and `compare_after_2b.sql` in Stage 4 will
have nothing to compare against.

---

### Stage 4 — Task 2(b): incremental load (ADM then DW)

The shape of this task: the warehouse is already built, faulty records then turn up
in the source, and the incremental load has to cope with them.

**Order matters here more than anywhere else in the project.**

#### 4.1 — as ADM: inject the dirty data

```sql
sqlplus adm/<password>@localhost:1521/FREEPDB1
SQL> @"Task 2\Task 2b\insert_dirty_data.sql"
```

> ### This comes AFTER the Task 2(a) load, never before
>
> The dirty rows break the warehouse's own `CHECK` constraints deliberately. Test B
> lodges a return two days before its order was placed, which makes
> `days_to_return = -2` and **aborts Task 2a** on `chk_return_fact_days` with
> `ORA-02290`. The `GREATEST(...)` clamps that neutralise those rows live in the
> Task 2b *incremental* procedures — they are not in the initial load.
>
> If you loaded the dirty data too early: run `@"Data Expansion\04_remove_dirty_data.sql"`
> as ADM, redo Stages 2 and 3, then come back here.

The script is safe to re-run — every insert is guarded by `NOT EXISTS`.

#### 4.2 — as DW: compile and run the incremental load

```sql
sqlplus dw/<password>@localhost:1521/FREEPDB1

SQL> @"Task 2\Task 2b\compile_task2b.sql"   -- both report blocks must be empty
SQL> SET SERVEROUTPUT ON
SQL> EXEC run_task2b
SQL> @"utils\compare_after_2b.sql"
```

`run_task2b` extends the calendar, refreshes the Type 1 dimensions, applies Type 1
and Type 2 changes to `customer_dim`, then reloads the four facts with a 7-day
lookback window.

`compare_after_2b.sql` proves the incremental load actually did something, by
diffing against the baseline that `verify_task2a.sql` saved at gate 10.

#### 4.3 — final acceptance

```sql
SQL> @"utils\final_acceptance.sql"
```

One verdict table covering every deliverable from Task 1(a) to Task 2(b).
**Every row must read PASS.** Screenshot it for the report.

Optionally also run `@"utils\data_audit.sql"` — a *plausibility* audit rather than a
correctness one. Nothing there is a pass/fail gate; it flags things an examiner
might point at and ask "how can that be true?", graded `BLOCKER` / `REPORT` /
`COSMETIC`.

---

### Stage 5 — Task 3: analytics reports and charts (as DW)

Task 3 is **individual** — each student writes 3 reports on their own domain, so
no two people query the same fact/dimension combination. The catalogue of ideas is
in [docs/Task3-12-Report-Ideas.md](docs/Task3-12-Report-Ideas.md).

| Student | Domain | SQL | Output |
|---|---|---|---|
| Xing Szen | A — Sales & Product | `Task 3/Xing Szen/task3_xs_reports.sql` | `Task 3 output/Xing Szen/` |
| Yong Vay | C — Customer, Membership & Loyalty | `Task 3/Yong Vay/task3_yv_reports.sql` | `Task 3 output/Yong Vay/` |

#### Run the reports

```sql
sqlplus dw/<password>@localhost:1521/FREEPDB1

SQL> SPOOL "Task 3 output\Yong Vay\task3_output.txt"
SQL> @"Task 3\Yong Vay\task3_yv_reports.sql"
SQL> SPOOL OFF
```

To export one exhibit as CSV for charting (Oracle 12.2+):

```sql
SQL> SET MARKUP CSV ON
SQL> SET PAGESIZE 50000
SQL> SPOOL "Task 3 output\Yong Vay\csv\tier_value.csv"
    -- paste just the one query you want
SQL> SPOOL OFF
SQL> SET MARKUP CSV OFF
```

#### Run the charts

```powershell
cd "Task 3\Yong Vay"
jupyter notebook Task3_Analytics_Charts.ipynb
```

Run every cell top to bottom. The two notebooks work differently, so know which
one you are in:

- **Yong Vay's** queries the warehouse live via `oracledb` (thin mode — no Instant
  Client needed). Cell 2 prompts for the `dw` password. Re-run the ETL and the
  charts follow automatically. Set `USE_CSV = True` in cell 2 to read exported CSVs
  instead if you would rather not install the driver. Charts save to
  `Task 3 output/Yong Vay/`.
- **Xing Szen's** holds figures **transcribed** from `task3_xs_reports.sql`. If you
  reload the warehouse, the numbers in the notebook do **not** update themselves —
  re-run the SQL and update the lists in the data cell. It writes into a local
  `charts/` folder; the committed copies live in `Task 3 output/Xing Szen/`.

#### Four rules baked into every Task 3 report

These are already applied in the SQL and the charts. Do not "fix" them — and repeat
them in your write-up, because they are what makes the numbers defensible:

1. **2026 is a part year** (January–August). It is excluded from every year-on-year
   or growth calculation. Charted raw against 2025 it reads as a ~26% collapse that
   did not happen.
2. **`customer_dim` is Type 2.** A customer who upgraded Normal → VIP owns more than
   one `customer_key`. Revenue joins through `customer_key` (correct — each order is
   attributed to the tier in force that day), but every **headcount** uses
   `COUNT(DISTINCT customer_id)`, or upgraders get counted twice.
3. **Branch rollout confounds cross-branch comparison.** Four branches traded in
   2016; all twelve only from 2023. Any cross-branch or cross-state comparison is
   restricted to 2024 onward.
4. **Promotional coverage falls across the decade for an arithmetic reason** —
   campaign breadth held at ~25 SKUs while the range grew from 28 to 54. Compare
   promotion figures *within* a year, never across years.

---

## Quick reference card

Pin this. Everything is run from the repo root.

```sql
-- ===== AS ADM ==============================================================
@"adm\Task2_DDL.sql"                      -- source schema        (destructive)
@"adm\Task3_Inserts_Data.sql"             -- source base data
@"Task 1\Task1b_Grants_RunAsADM.sql"      -- GRANT SELECT TO dw
@"Data Expansion\00_backup_adm.sql"       -- backup first!
@"Data Expansion\01_expand_promotions.sql"
@"Data Expansion\02_expand_orders.sql"
@"Data Expansion\03_validate_source.sql"  -- all PASS
@"Task 2\Task 2b\insert_dirty_data.sql"   -- ONLY after Task 2a has loaded

-- ===== AS DW ===============================================================
@"Task 1\Task1b_Physical_Design.sql"      -- warehouse schema     (destructive)
@"Task 2\Task 2a\CREATE_SEQUENCE.sql"
@"Task 2\Task 2a\compile_task2a.sql"      -- 3 clean report blocks
SET SERVEROUTPUT ON
EXEC run_task2a_initial_load
@"Task 2\Task 2a\verify_task2a.sql"       -- 10 gates, all pass

-- ... dirty data goes in as ADM here ...

@"Task 2\Task 2b\compile_task2b.sql"      -- 2 clean report blocks
EXEC run_task2b
@"utils\compare_after_2b.sql"
@"utils\final_acceptance.sql"             -- every row PASS

-- ===== DIAGNOSTICS (safe any time) =========================================
@"utils\check_status.sql"                 -- who am I, can I see ADM, what is invalid
@"utils\data_audit.sql"                   -- is the data believable
```

---

## Reloading without rebuilding

If you only want to reload the data and keep the table definitions:

```sql
SQL> @"Task 2\Task 2a\compile_task2a.sql"   -- if you edited any ETL script
SQL> @"utils\delete_table.sql"              -- empties tables, resets sequences to 1
SQL> SET SERVEROUTPUT ON
SQL> EXEC run_task2a_initial_load
SQL> @"Task 2\Task 2a\verify_task2a.sql"
```

`delete_table.sql` empties all 12 warehouse tables in FK-safe order and resets the
7 surrogate-key sequences to 1. Use it instead of re-running
`Task1b_Physical_Design.sql` when the schema itself has not changed.

**Full rebuild from scratch** is Stage 2 → Stage 3 → Stage 4, in that order.

**Rolling back the source expansion:** `@"Data Expansion\99_rollback.sql"` as ADM
restores `adm` exactly as `00_backup_adm.sql` found it, then rebuild the warehouse
from Stage 2.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `SP2-0310: unable to open file` | SQL\*Plus was not started from the repo root. | `cd` to the repo root and reconnect. Quote paths containing spaces. |
| `ORA-00942: table or view does not exist` on an `adm.` table | The grants never ran, or the operational user is not called `adm`. | Run `Task1b_Grants_RunAsADM.sql` **as ADM**. Confirm with `utils\check_status.sql` — section 2 must show 18 tables. |
| `ORA-00955: name is already used` on a sequence | `Task1b_Physical_Design.sql` was re-run without `CREATE_SEQUENCE.sql`. | Run `@"Task 2\Task 2a\CREATE_SEQUENCE.sql"` — it drops before it creates. |
| Compile produces `PLS-00103` / statement ends unexpectedly | You ran a DIM/FACT script by hand without `SET SQLBLANKLINES ON`. Every ETL script has blank lines inside its PL/SQL block, and the SQL\*Plus default ends the statement at a blank line. | Use `compile_task2a.sql` / `compile_task2b.sql` — they set it for you. |
| Data reloads but the numbers are stale or wrong | Stale compiled procedures. `DROP TABLE` does not drop procedures. | `@"Task 2\Task 2a\compile_task2a.sql"` and read the *third* report block. |
| `ORA-02290: check constraint (CHK_RETURN_FACT_DAYS) violated` during Task 2a | The Task 2b dirty data was loaded before the initial load. | `@"Data Expansion\04_remove_dirty_data.sql"` as ADM, redo Stages 2–3, then inject the dirty data. |
| `ORA-02291: integrity constraint violated` mid fact-load | The source has a referential problem the validator would have caught. | `@"Data Expansion\03_validate_source.sql"` as ADM and fix what it reports. |
| Gate 7 reports the wrong number of calendar days | Stale `load_date_dim`. | Recompile, then check the *calendar range* block at the end of `compile_task2a.sql` — it must read 2016-01-01 to 2030-12-31. |
| `compare_after_2b.sql` has nothing to compare | `verify_task2a.sql` (gate 10) never ran, so no baseline was saved. | You have to redo the Task 2a load and run `verify_task2a.sql` before Task 2b. |
| Notebook: `ModuleNotFoundError: oracledb` | Driver not installed. | `pip install oracledb`, or set `USE_CSV = True` in cell 2 and feed it CSV exports. |
| A `PROMPT` line silently swallows the next line | The line ends in a hyphen — SQL\*Plus's line-continuation character. | Never end a `PROMPT` with `-`. |

---

## Files you should NOT run

| Path | Why |
|---|---|
| `Task 2/Task 2a/run_task2a_initial_load.sql`<br>`Task 2/Task 2b/run_task2b.sql` | These only **define** the driver procedures; they do not run anything. `compile_task2a.sql` / `compile_task2b.sql` already run them last, which is required — PL/SQL resolves called procedures at compile time, so the driver cannot compile before the procedures it calls. |
| Individual `DIM/*.sql` and `FACT/*.sql` | Run them through the compile scripts. By hand they need `SET SQLBLANKLINES ON` and the right dependency order. |
| `Task 2/Task 2b (Claude)/` | An **unused alternate** implementation of Task 2b — a separate 6-file version with its own write-up. It is gitignored and nothing references it. **`Task 2/Task 2b/` is the one that runs.** Kept on disk for reference only. |
| `utils/delete_table.sql` | Safe, but it empties every warehouse table. Only run it when you mean to reload. |
| `adm/Task2_DDL.sql` | Drops all 21 operational tables. Only run it when you mean to rebuild the source from nothing. |

---

## For teammates picking this up

The three things most likely to waste your afternoon, in order:

1. **Not starting SQL\*Plus from the repo root.** Everything is relative now.
2. **Editing an ETL script and not recompiling.** The database keeps running the old
   version and says nothing. `compile_task2a.sql`'s third report block is the only
   thing that will tell you.
3. **Injecting the dirty data before the Task 2a load.** It is designed to break
   Task 2a's constraints. It belongs at Stage 4.1, never earlier.
