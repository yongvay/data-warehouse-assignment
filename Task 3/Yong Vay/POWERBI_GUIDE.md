# Charting Task 3 in Power BI — Domain C (Yong Vay)

**BMIT3003 Data Warehouse Technology — Task 3, Customer / Membership / Loyalty**

This is the step-by-step guide for turning the eighteen exhibits in
[task3_yv_reports.sql](task3_yv_reports.sql) into a three-page Power BI report you
can paste into the written chapter.

---

## How the pieces fit together

```
 task3_yv_reports.sql ─────▶ task3_output.txt    the written chapter (numbers + prose)
                                    ▲
                                    │  these two must agree, exactly
                                    ▼
 task3_yv_csv_export.sql ──▶ 18 CSV files ──▶ Power BI ──▶ charts for the chapter
```

**The SQL is the single source of truth.** The export script runs the same
aggregations as the report, so the four standing rules — part-year 2026, Type 2
distinct headcounts, the all-branches era, and no decade-long redemption trend —
are enforced *before* the data ever reaches Power BI. Power BI is the visual layer
and nothing more. That is deliberate: those rules are easy to state in SQL and easy
to get subtly wrong in DAX.

Three files in this folder matter:

| File | What it is |
|---|---|
| [task3_yv_reports.sql](task3_yv_reports.sql) | The eighteen exhibits as spooled text. The chapter. |
| [task3_yv_csv_export.sql](task3_yv_csv_export.sql) | The same eighteen exhibits as CSV. Feeds Power BI. |
| [task3_yv_theme.json](task3_yv_theme.json) | Power BI theme carrying the shared Domain A/C palette. |

`Task3_Analytics_Charts.ipynb` is the older matplotlib route. It still works and is
left on disk, but you do not need it if you are using Power BI.

---

## Step 0 — Pre-flight: is the warehouse actually expanded?

**Do this first. It takes ten seconds and can save you rebuilding a whole report.**

Four of the eighteen exhibits — 1.3 (revenue by tier by year), 1.4 (year-on-year),
2.5 (points per ringgit by year) and 3.6 (acquisition cohorts) — are trend and
cohort views that need the full 2016–2026 history. Connect as `dw` and run:

```sql
SELECT MIN(d.cal_year) AS first_year,
       MAX(d.cal_year) AS last_year
FROM   sales_fact s
JOIN   date_dim   d ON d.date_key = s.order_date_key;
```

| Result | What it means |
|---|---|
| `2016 / 2026` | Good. The source expansion has run. Carry on. |
| `2024 / 2026` | The `Data Expansion/` generator has **not** been run on this machine. Those four charts will have three data points each, and the cohort chart will be meaningless. |

If you get `2024 / 2026`, stop and follow **Stage 1** of the
[main README](../../README.md) before going any further.

> ### Why this matters beyond your own chapter
>
> Your chapter and your teammates' chapters are compiled into one report. If two
> people chart off differently populated warehouses, the same company shows
> contradictory totals in the same document — the sort of thing a marker notices.
>
> Worse, the generator reads `SYSDATE` for the current year despite being seeded, so
> even after expanding, the 2026 figures only reconcile between two machines if the
> generator was run on the same day. Agree on one expanded database and share it.

---

## Step 1 — Install Power BI Desktop

Power BI Desktop is not installed on this machine yet. Pick one:

```powershell
winget install --id Microsoft.PowerBI -e
```

or the **Microsoft Store** (search "Power BI Desktop" — this version auto-updates),
or the MSI from <https://powerbi.microsoft.com/desktop/>.

It is free and needs 64-bit Windows 10 or 11.

> ### You do not need an account
>
> Building the report, applying a theme, and exporting to PDF all work fully offline
> with no sign-in. Power BI will nag you to sign in — dismiss it.
>
> Sign-in is only required for **Publish**, which uploads to the Power BI *Service*
> and requires a **work or school** account. A personal gmail address is rejected
> outright. Nothing in this assignment needs publishing, so this never comes up.

---

## Step 2 — Export the CSVs

From the **repository root** (see the README's "one rule that saves you an hour"):

```powershell
cd "C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment"
sqlplus dw/<password>@localhost:1521/FREEPDB1
```

```sql
SQL> @"Task 3\Yong Vay\task3_yv_csv_export.sql"
```

It runs unattended — unlike the report script it uses `DEFINE` rather than `ACCEPT`,
so there are no prompts to answer. It finishes in a few seconds and prints
`Done. Eighteen CSV files written to: Task 3 output\Yong Vay\csv`.

### Verify before you import

Importing a broken CSV and discovering it three charts later is miserable. Three
checks, in PowerShell:

```powershell
cd "C:\Users\Lenovo\Desktop\Database Warehouse\data-warehouse-assignment"

# 1. Eighteen files, none of them empty
Get-ChildItem "Task 3 output\Yong Vay\csv\*.csv" | Select-Object Name, Length

# 2. No COMPUTE subtotals, no feedback trailer, no Oracle errors
Select-String -Path "Task 3 output\Yong Vay\csv\*.csv" -Pattern "State total|rows selected|ORA-|SP2-"

# 3. Eyeball the reshaped one
Get-Content "Task 3 output\Yong Vay\csv\c2_1_standing_position.csv"
```

Check 2 must return **nothing**. Check 3 must show two lines — a header and one row
of bare numbers, with no thousands separators and no ` %` suffix.

---

## Step 3 — Import into Power BI

Open Power BI Desktop, choose **Blank report**.

**Home → Get data → Text/CSV**, pick one file, click **Load**. Repeat for all
eighteen. It is more clicks than the alternative, but it is the route that cannot go
wrong.

> ### The trap: do not use Get data → Folder → Combine
>
> **Folder** looks like the obvious shortcut, and Power BI will offer
> **Combine & Load**. That option *appends* every file into one table — it is
> designed for a folder of files that all share a schema, like monthly sales
> extracts. Your eighteen files have eighteen different schemas. Combining them
> produces one table with sixty-odd mostly-null columns and rows that mean nothing.
>
> If you want the Folder connector's speed, choose **Transform Data** instead of
> Combine, then expand each file into its own query by hand. Only do that once you
> are comfortable — Text/CSV eighteen times is the safe default.

### Check the column types

After loading, open **Transform data** (Power Query) and look at the icon in each
column header: `123` whole number, `1.2` decimal, `ABC` text, calendar icon for date.

Every `Pct`, `Net Sales`, `Avg`, `Spend`, `Balance` and `Points` column must be a
number. If one shows `ABC`, something in Step 2's verification was missed.

Two things that occasionally need a nudge:

| Symptom | Fix |
|---|---|
| A decimal column loads as text | Right-click the column → **Change Type → Using Locale** → Decimal Number, Locale **English (United States)**. The export writes `1234.56` with a dot. |
| State or city names show `Ã` or `?` | In the query's **Source** step, change **File Origin** to `65001: Unicode (UTF-8)` or `1252: Western European (Windows)`. |

**Close & Apply** when the types look right.

### Set a sort key on the two monthly tables

`c2_4_monthly_points` and `c3_3_active_by_month` have a `Month` column of the form
`2024-01`. That happens to sort correctly as text, but do not rely on it — the
moment the date dimension's format changes, every month chart scrambles
alphabetically.

Make it explicit. Both tables already carry `Year` and `Month No`. `Month No` alone
is not unique across years, so build a combined key first:

**Transform data → Add Column → Custom Column**

```
= [Year] * 100 + [Month No]
```

Name it `Month Sort`, set its type to Whole Number, then **Close & Apply**.

Now tell Power BI to use it. After Close & Apply you are back in the main window;
look at the **far-left edge**, where a narrow vertical strip holds three view icons:

| Icon | View |
|---|---|
| Bar chart | **Report** — where you build visuals |
| Grid / table | **Table view** (called **Data view** in older versions) |
| Boxes joined by lines | **Model** |

1. Click the **middle (grid) icon**. Your data appears as a spreadsheet.
2. In the **Data pane on the right**, click the table `c2_4_monthly_points`. Its
   rows fill the grid.
3. Click the **`Month` column header** in the grid — one click on the header itself,
   which selects the whole column. (Clicking the field name `Month` in the Data pane
   does the same thing.)
4. A **`Column tools`** tab now appears in the ribbon. *It only exists while a column
   is selected* — this is the step people miss. Click it.
5. Click **Sort by column** and pick **`Month Sort`**.
6. **Nothing visible happens.** That is correct — it sets a property, it does not
   reorder the grid. You see the effect only on a chart.
7. Repeat steps 2–5 for `c3_3_active_by_month`.

If `Column tools` never appears, or **Sort by column** is greyed out, you have
selected the *table* rather than a *column*.

> ### Setting the sort column is not enough on its own
>
> **Power BI defaults a chart's axis to sorting by its first measure, descending.**
> Left alone, your monthly line chart comes out ordered by whichever month had the
> largest value — not chronologically. The sort column does not override this.
>
> On each monthly visual (#9 and #14), click the **`...`** in its top-right corner →
> **Sort axis** → choose **`Month`**. Then open **`...` → Sort axis** again and
> choose **Sort ascending**.
>
> That is the step that actually makes the line read left-to-right in time order.

**If you get stuck, skip the sort column.** `cal_year_month` is `CHAR(7)` holding
`2024-01`, which already sorts correctly as plain text, so the "Sort axis →
ascending" step above is sufficient on its own. The sort column exists only to
protect you if someone later changes the date dimension's format.

---

## Step 4 — Apply the theme

**View → Themes → Browse for themes**, then pick
[task3_yv_theme.json](task3_yv_theme.json).

This carries the same validated, colour-vision-safe palette the Domain A charts use
— blue `#2a78d6`, orange `#eb6834`, aqua `#1baf7a` — so your chapter and your
teammates' chapters read as one document rather than three.

### Lock the tier colours by hand

A theme sets the *order* colours are handed out, not which category gets which. VIP
can end up blue on one chart and orange on the next, purely because the sort order
differed. On a report whose whole argument is a comparison between tiers, that is
actively misleading.

For **every** visual with `Tier` in the legend, open the format pane and set:

| Tier | Colour |
|---|---|
| VIP | `#2a78d6` (blue) |
| Normal | `#eb6834` (orange) |
| Non-Member | `#8a8985` (grey) |

Format pane → **Columns / Bars / Lines → Colors**, setting each category
individually. Five minutes now, and every chart in the chapter agrees.

---

## Step 5 — Build the three pages

One page per report. Rename the page tabs at the bottom: `C1 Tier Economics`,
`C2 Loyalty Points`, `C3 Retention`.

Throughout, use the `WHAT` / `WHY IT MATTERS` / `SO WHAT` lines already written
above each exhibit in [task3_yv_reports.sql](task3_yv_reports.sql) as your visual
titles and subtitles. They are already the argument the chart is making — do not
write new ones and risk the chart and the prose saying different things.

### How to build any visual — the four-step recipe

Step 3 left you in **Table view**. Click the **top icon** (bar chart) on the
far-left strip to return to the report canvas.

Two panes sit on the right: **Visualizations** (a grid of chart-type icons) and
**Data** (your eighteen tables — click the arrow beside a table to expand its
columns).

1. **Click an empty spot on the canvas** so nothing is selected.
2. **Click a chart-type icon** in the Visualizations pane. An empty placeholder
   appears on the canvas. Hover an icon to see its name.
3. **Look directly below the chart icons** — the field wells (`X-axis`, `Y-axis`,
   `Legend`, …) appear there. They are only visible while a visual is selected.
4. **Drag** columns from the Data pane into the wells.

> **Drag, do not tick.** Ticking a column's checkbox lets Power BI choose the well
> for you, and it guesses wrong constantly. Dragging onto the named well is the only
> reliable way.

To rename an axis or legend label, double-click the field once it is in the well.
To change chart type afterwards, select the visual and click a different icon —
field assignments carry over where they can.

**Worked example, Visual 1.** Click empty canvas → **Clustered column chart** icon →
expand `c1_1_tier_value` → drag `Tier` to **X-axis** → drag `Spend per Customer` to
**Y-axis** → drag `Avg Order Value` into that **same Y-axis well**, below the first.
Two fields stacked in one value well is what produces the side-by-side pair of
columns per tier.

> ### Two gotchas, both specific to these CSVs
>
> **1. Numbers are auto-summed.** Drop a numeric column in and the well reads
> `Sum of Spend per Customer`. On Page 1 that is harmless — each table holds one row
> per tier and `Tier` is on the axis, so summing one row returns that row. But these
> CSVs are **already aggregated**. Build a visual without `Tier` on the axis and Sum
> will silently add pre-averaged figures together and produce a meaningless number.
> Where a measure is a rate or an average, set **Don't summarize** if the visual
> allows it, and never trust a total row.
>
> **2. `Year` is a number, so Power BI treats it as a measure.** It carries a Σ in
> the Data pane. Before building any year-axis visual, select the column and set
> **Column tools → Summarization → Don't summarize**. Do the same for `Cohort Year`,
> `Month No`, `Month Sort` and `Value Rank`. Otherwise the axis collapses to a single
> column labelled something like "20,213" instead of showing eleven years.

---

### Page 1 — C1 Membership tier economics

*The question: VIP costs the member RM12 a year and costs the company a doubled
point-earn rate. Does the extra spend a VIP brings cover what the tier gives away?*

| # | Visual type | Table | Field wells |
|---|---|---|---|
| 1 | **Clustered column** | `c1_1_tier_value` | X-axis `Tier`; Y-axis `Spend per Customer`, `Avg Order Value` |
| 2 | **Stacked column** | `c1_3_revenue_by_tier_year` | X-axis `Year`; Legend `Tier`; Y-axis `Net Sales` |
| 3 | **Line** | `c1_4_tier_yoy` | X-axis `Year`; Legend `Tier`; Y-axis `Share of Year Pct` |
| 4 | **Bar** | `c1_5_tier_movement` | Y-axis `Movement`; X-axis `Customers` |
| 5 | **Table** | `c1_2_tier_cost_vs_income` | all columns |
| 6 | **Line and clustered column** | `c1_6_basket_by_tier` | X-axis `Tier`; Column `Avg Basket`; Line `Discount Take Pct` |

**Visual 1 is the headline.** Two bars per tier because they answer different
questions: average order value is how big a visit is, spend per customer folds in
how *often* they come back. Turn data labels on here — the gap between the two bars
is the finding.

> **Read this chart before you title it.** Report 1 asks a genuine question, and in
> this warehouse the answer comes back **negative**: Normal members outspend VIPs per
> head (roughly RM610 against RM580) while average order value is flat across all
> three tiers. VIPs therefore shop slightly *less* often than Normal members, while
> costing double the point-earn rate and returning only a few thousand ringgit in
> fees against a six-figure point liability.
>
> That is a good, defensible finding — "the tier does not earn its keep" is an
> answer, not a failure. Do not force the opposite narrative onto it, and do not
> reuse the older matplotlib title *"A VIP is worth more per visit and comes back
> more often"* (still hardcoded in `Task3_Analytics_Charts.ipynb`), because it
> contradicts the data.

**Visual 5 stays a table on purpose.** Annual fee revenue is in ringgit and points
accrued are in points, and there is no reward catalogue table in the schema to
convert between them. Forcing both onto one axis would invent an exchange rate the
warehouse does not record. A table is the honest presentation.

**Visual 3 plots share, not absolute sales.** A tier whose *share* is rising is
winning the mix even when every tier is growing. Note that `c1_4` has no 2026 rows
at all — the export excludes the part year rather than trusting a caption, because a
caption does not survive somebody later dragging the measure onto a new visual.

**Visual 4 is your SCD Type 2 evidence.** It is the clearest single demonstration
that the Type 2 requirement from Task 1b actually works: a customer with more than
one version row has changed tier, and `version_no` plus the effective dates record
exactly when. Worth a sentence in the chapter.

> **Check the shape before committing to a bar chart.** After a standard Task 2b run
> only *one* customer (C0187) carries a second version, and that was a status change
> rather than a tier change — so the chart is roughly 1,000 "Never changed tier"
> against a single "Other tier change", and the second bar is invisible.
>
> The number is correct; the bar chart is not the way to show it. Use a **Table** or
> a **Card** instead ("1 customer holds 2 versions"), and make the argument in prose
> with the two version rows from section 2 of `utils/compare_after_2b.sql` beside it.

---

### Page 2 — C2 Loyalty points

*This is a **liability and participation** report, not a trend report.*

**Top row — six Card visuals**, all from the single row in
`c2_1_standing_position`. Insert a Card, drop one field in, repeat:

`Points Issued` · `Points Redeemed` · `Outstanding Balance` · `Redemption Pct` ·
`Members Holding Points` · `Members Ever Redeemed`

(A seventh, `Participation Pct`, is exported too if you want it on a card rather
than reading it off visual 7.)

| # | Visual type | Table | Field wells |
|---|---|---|---|
| 7 | **Bar** | `c2_2_participation` | Y-axis `Tier`; X-axis `Participation Pct` |
| 8 | **Clustered bar** | `c2_3_liability_by_tier` | Y-axis `Tier`; X-axis `Member Share Pct`, `Liability Share Pct` |
| 9 | **Line and clustered column** | `c2_4_monthly_points` | X-axis `Month`; Column `Points Earned`, `Points Redeemed`; Line `Cumulative Balance` |
| 10 | **Line** | `c2_5_points_per_rm` | X-axis `Year`; Y-axis `Points per RM` |
| 11 | **Clustered bar** | `c2_6_balance_bands` | Y-axis `Balance Band`; X-axis `Pct of Members`, `Pct of Liability` |

**Visual 7 is the key exhibit.** A redemption *rate* measured in points can be
dragged around by a handful of large redemptions. Participation — the share of
point-holding members who have ever redeemed even once — cannot. If participation is
low while balances rise, the reward catalogue is the problem, not the earn rate.

**Visual 8 turns Report 1's repricing question into a number.** VIP earns at 2.00
points per ringgit against Normal's 1.00, so VIP should hold a share of the
liability well above its share of the membership. The *gap between the two bars* is
that overhang, quantified.

**Visual 9 carries the only time axis in this report, and it starts at 2024.** In
this source a member holds at most one redemption, dated at their most recent earn,
so redemptions bunch toward the end of each member's life instead of spreading
across the decade. Charted from 2016 the series shows a data-generator artefact, not
a business trend. **Read the cumulative balance line, not the redeem columns** — say
so in the caption.

**Visual 11 answers whether a campaign is worth running.** An expiry policy or a
voucher sweep only pays for itself if the liability is concentrated. If `Pct of
Members` and `Pct of Liability` track each other, the liability is diffuse and a
blanket campaign wastes most of its budget. The two bars diverging is the finding.

> **On point valuation.** The schema records points, not the ringgit value of a
> point — there is no reward catalogue table. Quantify the liability in **points**
> and state the earn rates (Normal 1.00/RM, VIP 2.00/RM). Do not invent a
> conversion for the chart axis.

---

### Page 3 — C3 Retention and dormancy

*Two definitions this report commits to, both choices rather than facts: a
customer's state is the state of the branch they **last shopped at**, and the as-at
date is the **latest order date in the warehouse**, not `SYSDATE`.* State both in
the chapter — they are defensible, but only if you say them out loud.

| # | Visual type | Table | Field wells |
|---|---|---|---|
| 12 | **Line and clustered column** | `c3_1_state_retention` | X-axis `State`; Column `Dormancy Pct`; **Line `National Dormancy Pct`** |
| 13 | **Matrix** | `c3_2_city_dormancy` | Rows `State` then `City`; Values `Base Customers`, `Dormant`, `Dormancy Pct` |
| 14 | **Line** | `c3_3_active_by_month` | X-axis `Month`; Y-axis `Active Customers` |
| 15 | **Bar** | `c3_4_retention_by_tier` | Y-axis `Tier`; X-axis `Retention Pct` |
| 16 | **Column** | `c3_5_recency_bands` | X-axis `Recency Band`; Y-axis `Customers` |
| 17 | **Line and clustered column** | `c3_6_cohorts` | X-axis `Cohort Year`; Column `Customers Acquired`; Line `Still Active Pct` |

> ### Visual 12 — do NOT use the Analytics pane's "Average line"
>
> This is a correctness issue, not a styling preference.
>
> Power BI's **Analytics → Average line** looks exactly like the reference line
> Exhibit 3.1 asks for. It is not. It averages the *plotted state percentages* — an
> unweighted mean in which a state with 40 customers pulls as hard as one with 400.
> That is not the national dormancy rate, and a state can end up on the wrong side
> of it.
>
> The export computes the true national figure over exactly the population the
> states are drawn from, and carries it on every row as `National Dormancy Pct`. Put
> that column in the **Line** well of a line-and-clustered-column chart. It plots
> flat, which is what a reference line should be, and it is the number your chapter
> is entitled to quote.
>
> `National Retention Pct` is exported alongside it, for the same reason.

**Visual 13 is where drill-down earns its keep.** Put `State` then `City` in the
Rows well and use the matrix's expand arrows. A state-level dormancy figure is not
actionable; a branch city is. Unlike the text report, this data carries **no
`COMPUTE SUM` subtotal rows** — the matrix computes its own state subtotals from the
city rows. Had subtotals been exported, every state would be counted twice.

**Visual 15 closes the loop with Page 1.** Report 1 asks whether VIP *spends* more.
This asks whether VIP *stays*. A tier that spends more but churns at the same rate
is buying revenue, not loyalty, and the RM12 fee cannot be defended on retention
grounds. Put both pages' findings in the same paragraph of the chapter.

**Visual 16 prices the win-back budget.** A customer three months quiet needs a
nudge; one two years quiet needs a reacquisition offer or writing off. The bands are
what make that a costed decision rather than a blanket campaign.

---

## Step 6 — Format for a printed report

A chart that looks fine on screen often falls apart at 8cm wide in Word.

- **Page size.** Format pane with nothing selected → **Canvas settings → Type →
  Letter** (or Custom, 1600 × 1000 px) so the export has print proportions.
- **Titles.** Left-aligned, 13pt, `#1a1a19` — the theme does this. Write the title
  as the *finding*, not the field list: "Normal members outspend VIPs per head"
  beats "Spend per Customer by Tier". Read your own chart first — state what the
  data says, not what you expected it to say.
- **Kill the "Sum of" prefixes.** Every field arrives as `Sum of Spend per Customer`.
  Double-click the field in its well and rename it. A report full of "Sum of" reads
  as unfinished.
- **Subtitles.** Power BI has no native subtitle. Use a **Text box** placed directly
  under the title, 10pt, `#8a8985`, holding the measurement definition — "Lifetime
  net sales per customer against average order value, by tier".
- **Data labels** on for the small-category charts (tiers, movements, bands), off
  for the monthly series where they collide.
- **Gridlines** horizontal only, `#e6e5e1`. The theme sets this; do not add vertical
  gridlines back.
- **Turn off the visual header** so the "..." and focus icons stay out of an
  exported image: Format pane → **General → Header icons → off**, per visual.

### Flagging the part year

The matplotlib notebook hatched the 2026 bar to mark it as January–August only.
Power BI cannot hatch a column. Two things instead, and you need both:

1. **Keep 2026 out of every growth visual.** The export already does this — `c1_4`
   has no 2026 rows.
2. **Caption the level charts.** `c1_3`, `c2_5` and `c3_3` do show 2026, correctly.
   Each carries a `Year Type` column reading `Part year, Jan-Aug`. Put a text box
   under those charts: *"2026 covers January–August only. Read the ratio, not the
   volume."*

---

## Step 7 — Getting the charts into the Word chapter

**One visual at a time** — what you want most of the time:

> Hover the visual → **Copy icon** (or right-click → **Copy → Copy visual as
> image**) → paste into Word.

Power BI offers to include a caption with the visual title and a "data as of" stamp.
Take it, then delete Word's own caption so you do not caption twice.

**Whole pages:** **File → Export → Export to PDF**. Every page goes into one PDF at
canvas proportions. Good for an appendix.

There is **no native per-visual PNG export**. Copy-as-image is the route; do not go
looking for a Save As Image button.

---

## Step 8 — Refreshing after an ETL reload

1. Re-run `@"Task 3\Yong Vay\task3_yv_csv_export.sql"` as `dw`.
2. In Power BI: **Home → Refresh**.

Every visual re-reads its CSV. Nothing else to update.

> ### The one real downside of the CSV route, stated honestly
>
> **Nothing tells you the CSVs are stale.** Rebuild the warehouse, forget to
> re-export, and Power BI will happily refresh from month-old files and report a
> confident, wrong number. This is the same class of trap as the stale compiled
> procedures the README warns about in Stage 3.
>
> Make it a habit: any time you run `run_task2a_initial_load` or `run_task2b`, run
> the export script straight afterwards — and re-spool `task3_output.txt` too, so
> the text and the charts move together.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `SP2-0606: Cannot create SPOOL file` | The `csv` folder does not exist. SQL\*Plus will not create one. | The script's `HOST mkdir` should handle it. If not, create `Task 3 output\Yong Vay\csv` by hand, or set `csv_dir` to an absolute path. |
| `SP2-0310: unable to open file` | SQL\*Plus was not started from the repository root. | `cd` to the repo root and reconnect. Quote paths with spaces. |
| A CSV contains `ORA-` or `SP2-` text | An error occurred, but `SET TERMOUT OFF` hid it from the screen so it went into the spool file instead. | Comment out the `SET TERMOUT OFF` line near the top of the export script and re-run to see the error on screen. |
| The header row repeats every 30-odd lines | `PAGESIZE` too small. | The script sets `PAGESIZE 50000`. Something reset it — run the whole script rather than one pasted query. |
| A trailing `N rows selected` line in a CSV | `SET FEEDBACK` was on. | Same fix — run the whole script, not a fragment. |
| A `State total` row inside `c3_2` | `BREAK`/`COMPUTE` leaked in from the report script running earlier in the same session. | Run `CLEAR BREAKS` and `CLEAR COMPUTES`, then re-run the export. |
| Numbers arrive in Power BI as text | Either a `TO_CHAR` mask (thousands separators or a `%` suffix), or a locale mismatch. | The export uses no masks. Use **Change Type → Using Locale**, English (US). |
| Months sort `2024-01, 2024-10, 2024-11, 2024-02…` | No sort key set. | Add the `Month Sort` custom column and sort `Month` by it — Step 3. |
| The month axis is in no order at all — big months first | The visual is sorting by its **measure**, descending. This is Power BI's default and the sort column does not override it. | On the visual: **`...` → Sort axis → `Month`**, then **`...` → Sort axis → Sort ascending**. |
| `Column tools` tab is missing, or **Sort by column** is greyed out | A table is selected rather than a column. | In Table view, click the **column header** in the grid, not the table name. |
| "There can't be more than one value in `Month Sort` for the same value in `Month`" | The sort column is not 1:1 with the column being sorted. | `Year * 100 + [Month No]` is 1:1 with `YYYY-MM`. If you see this, the custom column formula was mistyped — check it in Power Query. |
| One combined table with dozens of null columns | **Get data → Folder → Combine & Load**. | Delete the query and import the files individually with **Text/CSV**. |
| The year axis is one giant column labelled `20,213` | `Year` is numeric, so Power BI summed it instead of using it as a category. | Select the column → **Column tools → Summarization → Don't summarize**. Same for `Cohort Year`, `Month No`, `Month Sort`, `Value Rank`. |
| No field wells visible under the chart icons | No visual is selected. | Click the visual on the canvas first. The wells only exist while one is selected. |
| A field landed in the wrong well | The checkbox was ticked instead of dragging. | Drag the field out of the well and drop it onto the correct one. |
| Every year in a stacked column is the same height, axis reads 0–100% | You picked **Stacked column chart (100%)** instead of **Stacked column chart**. | Select the visual and click the plain stacked column icon. The 100% variant hides growth and duplicates the share-of-year line chart. |
| A table's total row shows a nonsense figure like `Sum of Earn Rate per RM = 3` | Power BI sums every numeric column in the total, including rates and ratios, which cannot be added. | **Format pane → Totals → Off**. |
| A line on a secondary axis swings dramatically for a tiny real spread | The secondary axis auto-scales to the data range, not to zero. | Format pane → **Y-axis (secondary) → Range → Start = 0**, or say in the chapter that the spread is negligible. |
| Only some years label on a numeric X-axis | Power BI is treating the years as a continuous scale. | Format pane → **X-axis → Type → Categorical**. |
| Power BI rejects the sign-in | Publish needs a work or school account; a gmail address will not work. | You do not need to sign in. Dismiss the prompt and keep working offline. |
| Four charts look nearly empty | The warehouse holds only 2024–2026. | Step 0. Run the `Data Expansion/` generator — README Stage 1. |

---

## Checklist before you submit

- [ ] Step 0 returns `2016 / 2026`
- [ ] All eighteen CSVs exist, none empty, none containing `State total` or `rows selected`
- [ ] Exhibit 1.1's spend per customer in `task3_output.txt` matches `c1_1_tier_value.csv` exactly
- [ ] Exhibit 2.1's outstanding balance matches `c2_1_standing_position.csv` exactly
- [ ] Theme applied; VIP is blue and Normal is orange on **every** chart
- [ ] Visual 12 uses the exported `National Dormancy Pct` line, not an Analytics average line
- [ ] `c1_4` contains no 2026 rows; `c1_3`, `c2_5` and `c3_3` carry a part-year caption
- [ ] Both monthly charts sort chronologically
- [ ] Every visual title states a finding, and matches the prose in the chapter
