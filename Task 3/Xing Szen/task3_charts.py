# =============================================================================
#  Task 3 - Analytics Charts        BMIT3003 Data Warehouse Technology
#  Section 4.3  Chan Xing Szen      Domain A: Sales & Product
#
#  Paste into Google Colab. Run top to bottom. The last cell zips every PNG
#  and downloads them.
#
#  TEN charts, one set per analytical report, all transcribed from the output
#  of Task 3/Xing Szen/task3_xs_reports.sql run for 2016-2025 with drill-downs
#  2025 / KleenHome Supplies / 2024 / 2025. Nothing is invented here.
#
#  RULES BAKED IN
#    1. The run covers 2016-2025 only. 2026 is a part year and was excluded at
#       the prompt, so no chart needs a part-year caveat.
#    2. Never a dual axis. Where two measures have different scales they are
#       indexed to a common base (chart 03) or split into two panels (chart 10).
#    3. Colours come from a CVD-validated categorical palette, assigned in
#       fixed slot order, never cycled. At most three series on one plot.
# =============================================================================

# %% ===========================  CELL 1 - SETUP  =============================
import matplotlib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.ticker import FuncFormatter
import os

os.makedirs("charts", exist_ok=True)

# --- Validated categorical palette (fixed slot order, never cycled) ----------
C1, C2, C3 = "#2a78d6", "#eb6834", "#1baf7a"      # blue, orange, aqua
RED, BLUE  = "#e34948", "#2a78d6"                  # diverging pair
INK        = "#1a1a19"
INK_SOFT   = "#52514e"
INK_MUTE   = "#8a8985"
GRID       = "#e6e5e1"
SURFACE    = "#ffffff"

plt.rcParams.update({
    "figure.dpi": 120,
    "savefig.dpi": 220,                 # print quality for a Word report
    "savefig.bbox": "tight",
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "font.family": ["DejaVu Sans"],
    "font.size": 10,
    "axes.edgecolor": GRID,
    "axes.linewidth": 0.8,
    "axes.labelcolor": INK_SOFT,
    "axes.titlesize": 12.5,
    "axes.titleweight": "bold",
    "axes.titlecolor": INK,
    "axes.titlepad": 14,
    "axes.grid": True,
    "axes.axisbelow": True,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "xtick.color": INK_SOFT,
    "ytick.color": INK_SOFT,
    "xtick.labelsize": 9.5,
    "ytick.labelsize": 9.5,
    "legend.frameon": False,
    "legend.fontsize": 9.5,
})

def clean(ax, xgrid=False, ygrid=True):
    """Recessive axes: drop the box, keep one grid direction."""
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.xaxis.grid(xgrid)
    ax.yaxis.grid(ygrid)
    ax.tick_params(length=0)

def subtitle(ax, text):
    """Call AFTER set_title. Re-pads the title so the two never collide."""
    ax.set_title(ax.get_title(), pad=30)
    ax.text(0, 1.012, text, transform=ax.transAxes, fontsize=9.5,
            color=INK_MUTE, ha="left", va="bottom")

rm  = FuncFormatter(lambda v, p: f"{v:,.0f}")
pct = FuncFormatter(lambda v, p: f"{v:.0f}%")

def save(fig, name):
    fig.savefig(f"charts/{name}.png", facecolor=SURFACE)
    print("saved charts/" + name + ".png")

print("Setup complete.")


# %% ===========================  CELL 2 - DATA  ==============================
# Every figure below is transcribed from task3_output.txt (run: 2016-2025).

# ---- Report 1, Section 1: Annual Trading Summary ---------------------------
annual = pd.DataFrame([
 (2016,  4, 103, 28,  250, 2.43,  14337.46, 57.35,  None),
 (2017,  6, 166, 32,  330, 1.99,  19154.95, 58.05,  33.6),
 (2018,  7, 233, 36,  430, 1.85,  26100.75, 60.70,  36.3),
 (2019,  9, 309, 39,  540, 1.75,  32144.30, 59.53,  23.2),
 (2020,  9, 236, 43,  330, 1.40,  19639.82, 59.51, -38.9),
 (2021, 10, 319, 47,  450, 1.41,  28212.97, 62.70,  43.7),
 (2022, 11, 451, 49,  680, 1.51,  47681.58, 70.12,  69.0),
 (2023, 12, 592, 54,  900, 1.52,  73698.64, 81.89,  54.6),
 (2024, 12, 645, 54, 1100, 1.71,  93022.81, 84.57,  26.2),
 (2025, 12, 742, 54, 1350, 1.82, 124890.61, 92.51,  34.3),
], columns=["year","branches","customers","items","orders",
            "orders_per_cust","revenue","basket","yoy_pct"])

TOTAL_REVENUE = 478883.89   # reported TOTAL, used as a reconciliation check
assert abs(annual["revenue"].sum() - TOTAL_REVENUE) < 0.05
assert annual["orders"].sum() == 6360

# ---- Report 1, Section 2: Growth Decomposition -----------------------------
decomp = pd.DataFrame([
 ("Active customers",   103.0,   742.0,  7.20),
 ("Orders per customer",  2.43,    1.82, 0.75),
 ("Average basket (RM)", 57.35,   92.51, 1.61),
], columns=["component","v2016","v2025","multiple"])
REV_MULT = 8.71
# the three multiples must reconcile to the revenue multiple
assert abs(decomp["multiple"].prod() - REV_MULT) < 0.03

# ---- Report 1, Section 3: Category Demand by Quarter, 2025 -----------------
catq = pd.DataFrame([
 ("Baby Products",      5864, 8271, 6882, 6602, 21.2),
 ("Pet Care",           5124, 3476, 6205, 4164, 27.0),
 ("Frozen Food",        2968, 3208, 2430, 2779, 26.1),
 ("Personal Care",      2390, 2166, 2568, 2543, 24.7),
 ("Dairy and Eggs",     2522, 2408, 2207, 2255, 26.9),
 ("Household Cleaning", 2320, 2219, 2536, 1828, 26.1),
 ("Rice and Noodles",   1898, 2404, 1891, 2532, 21.8),
 ("Cooking Essentials", 1559, 3247, 1427, 2222, 18.4),
 ("Canned Food",        1641, 1395, 2062, 1968, 23.2),
 ("Beverages",          1217, 1525, 1744, 1374, 20.8),
 ("Bakery",             1143, 1182, 1150, 1071, 25.2),
 ("Snacks",              845, 1184,  990, 1286, 19.6),
], columns=["category","q1","q2","q3","q4","q1_share"])
catq["total"] = catq[["q1","q2","q3","q4"]].sum(axis=1)
# store-wide Q1 share in 2025 - the reference line on chart 04
STORE_Q1_SHARE = 100 * catq["q1"].sum() / catq["total"].sum()

# ---- Report 2, Section 1: Supplier Pareto ---------------------------------
sup = pd.DataFrame([
 ("LittleStar Baby Products","Baby Products",      70733.54, 14.77,  14.77),
 ("Polar Frozen Foods",      "Frozen Food",        59851.56, 12.50,  27.27),
 ("Fresh Dairy Farm",        "Dairy and Eggs",     48769.07, 10.18,  37.45),
 ("Selera Cooking Products", "Cooking Essentials", 43976.04,  9.18,  46.64),
 ("PetJoy Trading",          "Pet Care",           40975.17,  8.56,  55.19),
 ("Padi Emas Rice Mills",    "Rice and Noodles",   37924.22,  7.92,  63.11),
 ("CarePlus Consumer Goods", "Personal Care",      37701.01,  7.87,  70.98),
 ("Sunshine Beverages",      "Beverages",          31256.78,  6.53,  77.51),
 ("Ocean Canned Food",       "Canned Food",        30194.03,  6.31,  83.82),
 ("KleenHome Supplies",      "Household Cleaning", 28397.96,  5.93,  89.75),
 ("Snacko Food Industries",  "Snacks",             26495.75,  5.53,  95.28),
 ("Gardenview Bakery",       "Bakery",             22608.76,  4.72, 100.00),
], columns=["supplier","category","revenue","pct","cum_pct"])
# Short axis labels - each first token is already unique across the twelve
sup["short"] = ["LittleStar","Polar","Fresh Dairy","Selera","PetJoy","Padi Emas",
                "CarePlus","Sunshine","Ocean","KleenHome","Snacko","Gardenview"]
assert sup["short"].is_unique
assert abs(sup["revenue"].sum() - TOTAL_REVENUE) < 0.05

# ---- Report 2, Section 2: Return Rate With the Noise Band -----------------
zsc = pd.DataFrame([
 ("KleenHome Supplies",       3740, 138, 3.69, 109.6,  2.71),
 ("PetJoy Trading",           2191,  78, 3.56,  64.2,  1.72),
 ("Polar Frozen Foods",       6000, 197, 3.28, 175.9,  1.59),
 ("Ocean Canned Food",        5095, 164, 3.22, 149.3,  1.20),
 ("LittleStar Baby Products", 2493,  74, 2.97,  73.1,  0.11),
 ("Fresh Dairy Farm",         4743, 138, 2.91, 139.0, -0.09),
 ("Padi Emas Rice Mills",     4753, 137, 2.88, 139.3, -0.20),
 ("Gardenview Bakery",        5838, 168, 2.88, 171.1, -0.24),
 ("Selera Cooking Products",  5314, 140, 2.63, 155.8, -1.26),
 ("CarePlus Consumer Goods",  3309,  86, 2.60,  97.0, -1.12),
 ("Sunshine Beverages",       5889, 150, 2.55, 172.6, -1.72),
 ("Snacko Food Industries",   5190, 129, 2.49, 152.1, -1.87),
], columns=["supplier","units_sold","returned","return_pct","expected","z"])
# expected totals must equal actual totals - the test is internally consistent
assert abs(zsc["expected"].sum() - zsc["returned"].sum()) < 1.0

# A return line takes back 1-3 units, so returns arrive in clusters. The plain
# Poisson SD assumes single units and understates true variance by about 1.5x.
CLUSTER_ADJ = 1.53
zsc["z_adj"] = zsc["z"] / CLUSTER_ADJ
BONFERRONI = 2.87   # +/-2 corrected for 12 simultaneous comparisons

# ---- Report 2, Section 3: Concentration Across Two Periods ----------------
period = pd.DataFrame([
 ("2016-2020", 111377.28, 10, "Polar Frozen Foods",       19.9, 61.1),
 ("2021-2025", 367506.61, 12, "LittleStar Baby Products", 19.2, 49.5),
], columns=["period","revenue","sole_sources","largest","largest_pct","top4_pct"])
assert abs(period["revenue"].sum() - TOTAL_REVENUE) < 0.05

# ---- Report 2, Section 4: Return Reasons, KleenHome Supplies --------------
reasons = pd.DataFrame([
 ("Fulfilment",      "Wrong Item", 18, 38, 314.70, 5.8),
 ("Fulfilment",      "Missing",    13, 28, 208.30, 7.2),
 ("Product Quality", "Expired",    22, 44, 295.40, 5.3),
 ("Product Quality", "Broken",     15, 28, 214.90, 6.5),
], columns=["group","reason","lines","units","refund","avg_days"])
# must reconcile with KleenHome's total in the z-score table
assert reasons["units"].sum() == 138

# ---- Report 3, Section 1: Channel Mix by Year -----------------------------
chan = pd.DataFrame([
 (2016,  44, 17.60, 59.90,  206, 56.81),
 (2017,  68, 20.61, 60.37,  262, 57.44),
 (2018, 120, 27.91, 57.83,  310, 61.81),
 (2019, 164, 30.37, 61.40,  376, 58.71),
 (2020, 114, 34.55, 58.58,  216, 60.01),
 (2021, 167, 37.11, 63.46,  283, 62.24),
 (2022, 290, 42.65, 70.66,  390, 69.72),
 (2023, 384, 42.67, 76.55,  516, 85.86),
 (2024, 471, 42.82, 84.35,  629, 84.73),
 (2025, 606, 44.89, 92.02,  744, 92.91),
], columns=["year","online_orders","online_pct","online_basket",
            "walkin_orders","walkin_basket"])
assert (chan["online_orders"] + chan["walkin_orders"]).tolist() == annual["orders"].tolist()

# ---- Report 3, Section 2: Channel by Region, 2024-2025 --------------------
region = pd.DataFrame([
 ("Northern",      3, 633, 47.6, 91.88),
 ("Central",       5, 994, 43.5, 89.07),
 ("East Malaysia", 1, 196, 43.4, 87.92),
 ("Southern",      2, 416, 42.5, 84.60),
 ("East Coast",    1, 211, 38.9, 89.05),
], columns=["region","branches","orders","online_pct","basket"])
assert region["orders"].sum() == 2450   # = 2024 + 2025 orders

# ---- Report 3, Section 3: Membership Tier x Channel, 2025 ----------------
tier = pd.DataFrame([
 ("Non-Member", 105, 28.23, 85.06, 267, 91.25),
 ("Normal",     267, 49.72, 92.95, 270, 99.44),
 ("VIP",        234, 53.06, 94.09, 207, 86.53),
], columns=["tier","online_orders","online_pct","online_basket",
            "walkin_orders","walkin_basket"])
tier["orders"] = tier["online_orders"] + tier["walkin_orders"]
assert tier["orders"].sum() == 1350     # = 2025 orders

print("Data loaded and all 8 reconciliation checks passed.")


# %% =============  CELL 3 - REPORT 1: RANGE EXPANSION & DEMAND  =============
# Charts 01-04, used in section 4.3.1.

# --- Chart 01: the shape of the decade, and the one year it broke -----------
fig, ax = plt.subplots(figsize=(9, 4.4))
cols = [RED if y == 2020 else BLUE for y in annual["year"]]
ax.bar(annual["year"], annual["revenue"], width=0.66, color=cols, zorder=3)
ax.set_title("Revenue grew 8.7x, with one interruption")
subtitle(ax, "Net revenue by year, RM. 2026 excluded at the prompt as a part year.")
ax.yaxis.set_major_formatter(rm); ax.set_ylabel("Net revenue (RM)")
ax.set_xticks(annual["year"]); clean(ax)
ax.annotate("2020: -38.9%,\nthe only contraction",
            xy=(2020, 19639), xytext=(2016.6, 62000), fontsize=9, color=INK_SOFT,
            arrowprops=dict(arrowstyle="->", color=INK_MUTE, lw=1))
for y, v in [(2016, 14337.46), (2025, 124890.61)]:
    ax.text(y, v + 3000, f"RM {v:,.0f}", ha="center", fontsize=9,
            weight="bold", color=INK)
save(fig, "01_annual_revenue"); plt.show()


# --- Chart 02: which driver actually did the work ---------------------------
fig, ax = plt.subplots(figsize=(7.6, 3.8))
d = decomp.iloc[::-1]
cols = [BLUE if m >= 1 else RED for m in d["multiple"]]
ax.barh(d["component"], d["multiple"], height=0.6, color=cols, zorder=3)
ax.axvline(1.0, color=INK_SOFT, lw=1.2, zorder=4)
# label sits in the empty gap between two bars, never in the subtitle band
ax.text(1.10, 1.52, "no change", fontsize=8.5, color=INK_SOFT,
        va="center", ha="left")
for i, m in enumerate(d["multiple"]):
    ax.text(m + 0.16, i, f"x{m:.2f}", va="center", fontsize=10.5,
            weight="bold", color=INK)
ax.set_title("Revenue grew 8.71x - acquisition did the work")
subtitle(ax, "x7.20 x x0.75 x x1.61 = x8.71. Anything left of 1.0 worked against growth.")
ax.set_xlabel("Growth multiple, 2016 to 2025"); ax.set_xlim(0, 8.6)
clean(ax, xgrid=True, ygrid=False)
save(fig, "02_growth_decomposition"); plt.show()


# --- Chart 03: the same three drivers, year by year -------------------------
# Indexed to 2016 = 100 so three different scales share one axis honestly.
idx = pd.DataFrame({
    "year": annual["year"],
    "Customers":           100 * annual["customers"]       / annual["customers"].iloc[0],
    "Orders per customer": 100 * annual["orders_per_cust"] / annual["orders_per_cust"].iloc[0],
    "Basket value":        100 * annual["basket"]          / annual["basket"].iloc[0],
})
fig, ax = plt.subplots(figsize=(9, 4.4))
for name, c in zip(["Customers", "Orders per customer", "Basket value"], [C1, C2, C3]):
    ax.plot(idx["year"], idx[name], color=c, lw=2.4, marker="o", ms=6,
            mfc=SURFACE, mew=2.2, label=name, zorder=4)
    ax.text(2025.12, idx[name].iloc[-1], f" {idx[name].iloc[-1]:.0f}",
            va="center", fontsize=9.5, weight="bold", color=c)
ax.axhline(100, color=INK_MUTE, lw=1, ls=":", zorder=2)
ax.set_title("Customer growth outran both other drivers")
subtitle(ax, "Each driver indexed to its own 2016 value. Order frequency never recovered.")
ax.set_ylabel("Index (2016 = 100)"); ax.set_xticks(annual["year"])
ax.set_xlim(2015.7, 2026.1); clean(ax)
ax.legend(loc="upper left")
save(fig, "03_driver_index"); plt.show()


# --- Chart 04: two questions, two panels ------------------------------------
# Left  = how big each category is in 2025 (full year, all four quarters).
# Right = whether the year has a season at all. Keeping these apart matters:
#         the bar length is RM for the whole year, not Q1.
c = catq.sort_values("total")
qshare = [100 * catq[q].sum() / catq["total"].sum() for q in ["q1","q2","q3","q4"]]

fig, axes = plt.subplots(1, 2, figsize=(12, 4.8),
                         gridspec_kw={"width_ratios": [1.75, 1]})

ax = axes[0]
top2 = set(catq.nlargest(2, "total")["category"])
ax.barh(c["category"], c["total"], height=0.68, zorder=3,
        color=[C2 if k in top2 else C1 for k in c["category"]])
for i, t in enumerate(c["total"]):
    ax.text(t + 450, i, f"{t:,.0f}", va="center", fontsize=9, color=INK_SOFT)
ax.set_title("Two categories take over a third of the year", fontsize=11.5)
ax.xaxis.set_major_formatter(rm)
ax.set_xlabel("Net revenue, full year 2025 (RM)")
ax.set_xlim(0, 32500); clean(ax, xgrid=True, ygrid=False)
share2 = 100 * catq.nlargest(2, "total")["total"].sum() / catq["total"].sum()
ax.text(0.97, 0.06, f"Baby Products + Pet Care = {share2:.1f}%\nof all 2025 revenue",
        transform=ax.transAxes, ha="right", va="bottom", fontsize=9.5,
        color=INK_SOFT)

ax = axes[1]
ax.bar(["Q1","Q2","Q3","Q4"], qshare, width=0.6, color=C1, zorder=3)
ax.axhline(25, color=INK_SOFT, lw=1.2, ls="--", zorder=4)
ax.text(-0.44, 25.4, "even split", ha="left", va="bottom",
        fontsize=8.5, color=INK_SOFT)
for i, v in enumerate(qshare):
    ax.text(i, v + 0.35, f"{v:.1f}%", ha="center", fontsize=10,
            weight="bold", color=INK)
ax.set_title("...but the year has no season", fontsize=11.5)
ax.set_ylim(0, 30); ax.yaxis.set_major_formatter(pct)
ax.set_ylabel("Share of 2025 revenue"); clean(ax)

fig.tight_layout()
fig.suptitle("2025: concentrated by category, flat across the calendar",
             fontsize=12.5, weight="bold", color=INK, y=1.09)
fig.text(0.5, 1.03, "Left: full-year revenue, all four quarters. "
                    "Right: how that year splits by quarter.",
         fontsize=9.5, color=INK_MUTE, ha="center", va="bottom")
save(fig, "04_category_2025"); plt.show()


# %% =============  CELL 4 - REPORT 2: SUPPLIER CONCENTRATION  ===============
# Charts 05-07, used in section 4.3.2.

# --- Chart 05: Pareto. Both series are percentages, so one axis serves both --
fig, ax = plt.subplots(figsize=(9.6, 4.8))
x = np.arange(len(sup))
ax.bar(x, sup["pct"], width=0.62, color=C1, zorder=3, label="Share of revenue")
ax.plot(x, sup["cum_pct"], color=C2, lw=2.4, marker="o", ms=6, mfc=SURFACE,
        mew=2.2, zorder=4, label="Cumulative share")
ax.axhline(80, color=INK_MUTE, lw=1, ls=":", zorder=2)
ax.text(11.4, 82, "80%", fontsize=8.5, color=INK_MUTE, ha="right")
ax.set_title("Every supplier is the sole source of exactly one category")
subtitle(ax, "Share of 2016-2025 net revenue. No category has a second supplier.")
ax.set_xticks(x)
ax.set_xticklabels(sup["short"], fontsize=9, rotation=30, ha="right")
ax.yaxis.set_major_formatter(pct); ax.set_ylabel("Share of net revenue")
ax.set_ylim(0, 108); clean(ax)
ax.legend(loc="center right")
save(fig, "05_supplier_pareto"); plt.show()


# --- Chart 06: is any supplier a real outlier? ------------------------------
s = zsc.sort_values("z")
fig, ax = plt.subplots(figsize=(9, 5.0))
y = np.arange(len(s))
ax.axvspan(-BONFERRONI, BONFERRONI, color=C1, alpha=0.07, zorder=1)
ax.axvspan(-2, 2, color=C1, alpha=0.07, zorder=1)
for v in (-BONFERRONI, -2, 2, BONFERRONI):
    ax.axvline(v, color=INK_MUTE, lw=1, ls="--", zorder=2)
ax.axvline(0, color=INK_SOFT, lw=1.2, zorder=3)
ax.scatter(s["z"], y, s=70, color=C2, zorder=5, label="Raw z (Poisson)")
ax.scatter(s["z_adj"], y, s=70, color=C1, zorder=5,
           label="Adjusted for return clustering")
ax.set_yticks(y); ax.set_yticklabels(s["supplier"], fontsize=9)
ax.set_title("No supplier's return rate is a real outlier")
subtitle(ax, "Deviation from expected returns, in SD. Bands: +/-2 and +/-2.87 "
             "(Bonferroni, 12 tests).")
ax.set_xlabel("z-score (standard deviations)"); ax.set_xlim(-4.2, 4.2)
clean(ax, xgrid=True, ygrid=False)
ax.legend(loc="lower right")
fig.text(0.5, -0.02,
         "KleenHome is the only supplier past +2 on the raw score. Adjusted for "
         "clustering it falls to 1.77 - inside every band.",
         fontsize=9, color=INK_SOFT, ha="center", va="top")
save(fig, "06_return_zscore"); plt.show()


# --- Chart 07: did the exposure ease, or just move? -------------------------
fig, ax = plt.subplots(figsize=(8.4, 4.6))
x = np.arange(len(period)); w = 0.32
ax.bar(x - w/2, period["top4_pct"], w, color=C1, zorder=3,
       label="Top-four suppliers' share")
ax.bar(x + w/2, period["largest_pct"], w, color=C2, zorder=3,
       label="Largest single supplier's share")
for i, r in period.iterrows():
    ax.text(i - w/2, r.top4_pct + 1.4, f"{r.top4_pct}%", ha="center",
            fontsize=10, weight="bold", color=INK)
    ax.text(i + w/2, r.largest_pct + 1.4, f"{r.largest_pct}%", ha="center",
            fontsize=10, weight="bold", color=INK)
    ax.text(i + w/2, r.largest_pct - 3.2, r.largest.split()[0], ha="center",
            fontsize=8.5, color=SURFACE, weight="bold")
    ax.text(i, -6.6, f"{r.sole_sources} sole-source suppliers", ha="center",
            fontsize=9.5, weight="bold" if r.sole_sources == 12 else "normal",
            color=RED if r.sole_sources == 12 else INK_SOFT)
ax.set_title("Revenue spread out - single points of failure rose")
subtitle(ax, "Two five-year periods, split automatically at the range midpoint.")
ax.set_xticks(x); ax.set_xticklabels(period["period"], fontsize=10.5)
ax.set_ylim(0, 78); ax.yaxis.set_major_formatter(pct)
ax.set_ylabel("Share of period revenue"); clean(ax)
ax.legend(loc="upper right")
ax.annotate("", xy=(1 - w/2, 53.6), xytext=(0 - w/2, 65.0),
            arrowprops=dict(arrowstyle="->", color=INK_MUTE, lw=1.4, ls="--"))
ax.text(0.5, 60.6, "-11.6 pts", ha="center", fontsize=9.5, color=INK_SOFT,
        bbox=dict(fc=SURFACE, ec="none", pad=1.5))
save(fig, "07_concentration_period"); plt.show()


# %% =============  CELL 5 - REPORT 3: CHANNEL MIGRATION  ====================
# Charts 08-10, used in section 4.3.3.

# --- Chart 08: the migration itself -----------------------------------------
fig, ax = plt.subplots(figsize=(9, 4.2))
ax.plot(chan["year"], chan["online_pct"], color=C1, lw=2.6, marker="o", ms=7,
        mfc=SURFACE, mew=2.2, zorder=4)
ax.axhline(50, color=INK_MUTE, lw=1, ls=":", zorder=2)
ax.text(2016, 51, "half of all orders", fontsize=8.5, color=INK_MUTE)
ax.set_title("Online share rose every year, but has not yet crossed half")
subtitle(ax, "Online share of orders, 2016-2025. No year in the series falls.")
ax.yaxis.set_major_formatter(pct); ax.set_ylabel("Online share of orders")
ax.set_xticks(chan["year"]); ax.set_ylim(10, 58); clean(ax)
for yr, v in [(2016, 17.60), (2025, 44.89)]:
    ax.annotate(f"{v}%", xy=(yr, v), xytext=(0, 13), textcoords="offset points",
                ha="center", fontsize=9.5, weight="bold", color=INK)
save(fig, "08_online_share"); plt.show()


# --- Chart 09: does moving a customer online grow the basket? ---------------
fig, ax = plt.subplots(figsize=(9, 4.2))
ax.plot(chan["year"], chan["online_basket"], color=C1, lw=2.4, marker="o",
        ms=7, mfc=SURFACE, mew=2.2, label="Online", zorder=4)
ax.plot(chan["year"], chan["walkin_basket"], color=C2, lw=2.4, marker="s",
        ms=7, mfc=SURFACE, mew=2.2, label="Walk-in", zorder=4)
ax.set_title("The migration substitutes, it does not grow the basket")
subtitle(ax, "Average basket by channel, RM. The gap never exceeds RM 9 and is "
             "under RM 1 in 2024-25.")
ax.set_ylabel("Average basket (RM)"); ax.set_xticks(chan["year"]); clean(ax)
ax.legend(loc="upper left")
save(fig, "09_basket_by_channel"); plt.show()


# --- Chart 10: WHERE and WHO. Two panels, because two different cuts --------
fig, axes = plt.subplots(1, 2, figsize=(11, 4.2))

r = region.sort_values("online_pct")
axes[0].barh(r["region"], r["online_pct"], height=0.62, color=C1, zorder=3)
for i, (v, b) in enumerate(zip(r["online_pct"], r["branches"])):
    axes[0].text(v + 0.6, i, f"{v}%", va="center", fontsize=9.5,
                 weight="bold", color=INK)
    axes[0].text(0.6, i, f"{b} br", va="center", fontsize=8.5, color=SURFACE)
axes[0].set_title("Where: by region", fontsize=11.5)
axes[0].set_xlim(0, 56); axes[0].xaxis.set_major_formatter(pct)
axes[0].set_xlabel("Online share of orders, 2024-2025")
clean(axes[0], xgrid=True, ygrid=False)

t = tier.sort_values("online_pct")
axes[1].barh(t["tier"], t["online_pct"], height=0.62, zorder=3,
             color=[C2 if x == "Non-Member" else C1 for x in t["tier"]])
for i, v in enumerate(t["online_pct"]):
    axes[1].text(v + 0.8, i, f"{v:.1f}%", va="center", fontsize=9.5,
                 weight="bold", color=INK)
axes[1].set_title("Who: by membership tier", fontsize=11.5)
axes[1].set_xlim(0, 62); axes[1].xaxis.set_major_formatter(pct)
axes[1].set_xlabel("Online share of orders, 2025")
clean(axes[1], xgrid=True, ygrid=False)

fig.tight_layout()
fig.suptitle("Non-members cannot take delivery - the gap is structural",
             fontsize=12.5, weight="bold", color=INK, y=1.17)
fig.text(0.5, 1.055, "Left: like-for-like window, every branch trading. "
                     "Right: 2025 only.", fontsize=9.5, color=INK_MUTE,
         ha="center", va="bottom")
save(fig, "10_where_and_who"); plt.show()


# %% ===================  CELL 6 - DOWNLOAD EVERYTHING  =======================
import shutil
shutil.make_archive("task3_charts", "zip", "charts")
print("\nCharts written:")
for f in sorted(os.listdir("charts")):
    print("  ", f)

try:
    from google.colab import files
    files.download("task3_charts.zip")
except Exception as e:
    print("\nNot running in Colab - the PNGs are in ./charts/  (", e, ")")
