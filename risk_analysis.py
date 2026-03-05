"""
=============================================================
 Credit Card Risk Analytics Project — Full Python Analysis
 File: risk_analysis.py
=============================================================
 Dataset : 50K customers | 50K cards | 1.5M statements | 2K writeoffs
 Sections:
   1.  Load & Validate Data
   2.  Feature Engineering
   3.  Portfolio KPIs
   4.  PD Estimation
   5.  LGD Calculation
   6.  EAD Calculation
   7.  Expected Loss (EL = PD × LGD × EAD)
   8.  IFRS 9 Stage Classification
   9.  Roll Rate Analysis
   10. Vintage Analysis
   11. Logistic Regression Default Model
   12. Export for Tableau (6 dashboards)
=============================================================
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
import warnings, os
warnings.filterwarnings("ignore")

os.makedirs("../tableau", exist_ok=True)

# ── Plot Style ────────────────────────────────────────────────
plt.rcParams.update({
    "figure.figsize"    : (13, 5),
    "axes.spines.top"   : False,
    "axes.spines.right" : False,
    "axes.titlesize"    : 13,
    "axes.titleweight"  : "bold",
})
COLORS = {"green":"#2ecc71","orange":"#f39c12","red":"#e74c3c",
          "blue":"#3498db","purple":"#8e44ad","gray":"#95a5a6"}

# ─────────────────────────────────────────────────────────────
# SECTION 1: LOAD & VALIDATE
# ─────────────────────────────────────────────────────────────
print("=" * 65)
print("  SECTION 1: LOADING DATA")
print("=" * 65)

customers = pd.read_csv("../data/customers.csv")
cards     = pd.read_csv("../data/cards.csv")
stmts     = pd.read_csv("../data/statements.csv",
                         parse_dates=["period_month"])
writeoffs = pd.read_csv("../data/writeoffs.csv",
                         parse_dates=["writeoff_date"])

print(f"  customers  : {len(customers):>10,} rows")
print(f"  cards      : {len(cards):>10,} rows")
print(f"  statements : {len(stmts):>10,} rows")
print(f"  writeoffs  : {len(writeoffs):>10,} rows")
print(f"  Date range : {stmts.period_month.min().date()} → {stmts.period_month.max().date()}")

# Null checks
for name, df in [("customers",customers),("cards",cards),("stmts",stmts),("writeoffs",writeoffs)]:
    n = df.isnull().sum().sum()
    print(f"  {name} nulls: {n}")

# ─────────────────────────────────────────────────────────────
# SECTION 2: FEATURE ENGINEERING
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 2: FEATURE ENGINEERING")
print("=" * 65)

# Master table — drop duplicate credit_limit from cards (already in statements)
master = (stmts
          .merge(cards.drop(columns=["credit_limit"]), on="card_id", how="left")
          .merge(customers, on="customer_id", how="left"))

# Core features
master["utilization"]       = (master["statement_balance"] /
                                master["credit_limit"].replace(0, np.nan)).round(4)
master["payment_ratio"]     = (master["paid_amount"] /
                                master["statement_balance"].replace(0, np.nan)
                               ).fillna(0).clip(0, 1).round(4)
master["revolving_balance"] = (master["statement_balance"] - master["paid_amount"]).clip(0)
master["is_delinquent"]     = (master["days_past_due"] >= 30).astype(int)
master["is_default"]        = (master["days_past_due"] >= 90).astype(int)

def payment_type(row):
    if row["paid_amount"] >= row["statement_balance"]: return "Full Payment"
    if row["paid_amount"] >= row["min_due"]:           return "Min Payment"
    if row["paid_amount"] > 0:                         return "Partial Payment"
    return "No Payment"

master["payment_type"] = master.apply(payment_type, axis=1)

bins   = [-0.001, 0.4, 0.7, 0.9, float("inf")]
labels = ["Low <40%","Medium 40-69%","High 70-89%","Critical 90%+"]
master["util_band"] = pd.cut(master["utilization"], bins=bins, labels=labels)

print(f"  Master shape   : {master.shape}")
print(f"  Features added : utilization, payment_ratio, revolving_balance,")
print(f"                   is_delinquent, is_default, payment_type, util_band")

# ─────────────────────────────────────────────────────────────
# SECTION 3: PORTFOLIO KPIs
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 3: PORTFOLIO KPIs")
print("=" * 65)

print(f"  Total Exposure         : {master['statement_balance'].sum():>15,.0f}")
print(f"  Avg Utilization        : {master['utilization'].mean():>14.1%}")
print(f"  Delinquency Rate (30+) : {master['is_delinquent'].mean():>14.1%}")
print(f"  Default Rate (90+)     : {master['is_default'].mean():>14.1%}")
print(f"  No Payment Months      : {(master['payment_type']=='No Payment').mean():>14.1%}")

# ─────────────────────────────────────────────────────────────
# SECTION 4: PD ESTIMATION
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 4: PROBABILITY OF DEFAULT (PD)")
print("=" * 65)

# Per-card features for PD
card_feats = (master.groupby("card_id")
              .agg(avg_util       =("utilization",       "mean"),
                   max_util       =("utilization",       "max"),
                   avg_dpd        =("days_past_due",     "mean"),
                   max_dpd        =("days_past_due",     "max"),
                   del_months     =("is_delinquent",     "sum"),
                   avg_pay_ratio  =("payment_ratio",     "mean"),
                   avg_rev_bal    =("revolving_balance", "mean"),
                   default_flag   =("is_default",        "max"),
                   months_on_book =("period_month",      "nunique"))
              .reset_index())

# Logistic PD score
card_feats["pd_score"] = (
    1 / (1 + np.exp(-(
        -3.5
        + card_feats["avg_util"].clip(0,1)                   * 2.5
        + (card_feats["avg_dpd"] / 30.0)                     * 1.8
        + card_feats["del_months"]                            * 0.4
        - card_feats["avg_pay_ratio"].clip(0,1)              * 1.5
    )))
).round(4)

portfolio_pd = card_feats["default_flag"].mean()
print(f"  Portfolio PD (90+ DPD) : {portfolio_pd:.2%}")
print(f"  Avg PD Score           : {card_feats['pd_score'].mean():.4f}")

# PD by region
pd_region = (master.groupby("region")
             .agg(pd=("is_default","mean"))
             .round(4).reset_index())
print(f"\n  PD by Region:\n{pd_region.to_string(index=False)}")

# ─────────────────────────────────────────────────────────────
# SECTION 5: LGD CALCULATION
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 5: LOSS GIVEN DEFAULT (LGD)")
print("=" * 65)

writeoffs["lgd"] = (
    (writeoffs["writeoff_amount"] - writeoffs["recovery_amount"])
    / writeoffs["writeoff_amount"].replace(0, np.nan)
).round(4)

portfolio_lgd     = writeoffs["lgd"].mean()
portfolio_rr      = 1 - portfolio_lgd
total_written_off = writeoffs["writeoff_amount"].sum()
total_recovered   = writeoffs["recovery_amount"].sum()
net_loss          = total_written_off - total_recovered

print(f"  Total Write-offs       : {total_written_off:>15,.0f}")
print(f"  Total Recovered        : {total_recovered:>15,.0f}")
print(f"  Net Loss               : {net_loss:>15,.0f}")
print(f"  Portfolio LGD          : {portfolio_lgd:.2%}")
print(f"  Recovery Rate (1-LGD)  : {portfolio_rr:.2%}")

lgd_product = (writeoffs
               .merge(cards[["card_id","product_type"]], on="card_id")
               .groupby("product_type")["lgd"]
               .mean().round(4).reset_index())
print(f"\n  LGD by Product:\n{lgd_product.to_string(index=False)}")

# ─────────────────────────────────────────────────────────────
# SECTION 6: EAD CALCULATION
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 6: EXPOSURE AT DEFAULT (EAD)")
print("=" * 65)

CCF = 0.75    # Basel III standard Credit Conversion Factor

latest_month = stmts["period_month"].max()
latest_stmts = stmts[stmts["period_month"] == latest_month].copy()

latest_stmts["unused_limit"] = latest_stmts["credit_limit"] - latest_stmts["statement_balance"]
latest_stmts["ead"]          = (latest_stmts["statement_balance"] +
                                 CCF * latest_stmts["unused_limit"]).round(0)

portfolio_ead          = latest_stmts["ead"].sum()
portfolio_balance      = latest_stmts["statement_balance"].sum()
portfolio_max_exposure = latest_stmts["credit_limit"].sum()

print(f"  CCF Assumption         : {CCF:.0%}")
print(f"  Current Balance        : {portfolio_balance:>15,.0f}")
print(f"  Portfolio EAD (75% CCF): {portfolio_ead:>15,.0f}")
print(f"  Max Possible (100% CCF): {portfolio_max_exposure:>15,.0f}")
print(f"  EAD Uplift Factor      : {portfolio_ead / portfolio_balance:.4f}x")

# ─────────────────────────────────────────────────────────────
# SECTION 7: EXPECTED LOSS  EL = PD × LGD × EAD
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 7: EXPECTED LOSS (EL = PD × LGD × EAD)")
print("=" * 65)

el_df = (card_feats[["card_id","pd_score","max_dpd"]]
         .merge(latest_stmts[["card_id","ead"]], on="card_id", how="left"))

el_df["lgd"]             = portfolio_lgd
el_df["expected_loss"]   = (el_df["pd_score"] * el_df["lgd"] * el_df["ead"]).round(2)
el_df["el_rate_pct"]     = (el_df["pd_score"] * el_df["lgd"] * 100).round(4)

# IFRS 9 Stage
el_df["ifrs9_stage"] = np.where(
    el_df["max_dpd"] >= 90, "Stage 3",
    np.where(el_df["pd_score"] >= 0.20, "Stage 2", "Stage 1")
)

total_el = el_df["expected_loss"].sum()
total_ead_model = el_df["ead"].sum()

print(f"  Total Expected Loss    : {total_el:>15,.0f}")
print(f"  EL Rate (EL/EAD)       : {total_el / total_ead_model:.2%}")
print(f"\n  IFRS 9 Stage Breakdown:")
stage_summary = (el_df.groupby("ifrs9_stage")
                 .agg(accounts=("card_id","count"),
                      total_ead=("ead","sum"),
                      total_el =("expected_loss","sum"))
                 .reset_index())
stage_summary["el_rate"] = (stage_summary["total_el"] / stage_summary["total_ead"]).round(4)
print(stage_summary.to_string(index=False))

# ─────────────────────────────────────────────────────────────
# SECTION 8: ROLL RATE ANALYSIS
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 8: ROLL RATE ANALYSIS")
print("=" * 65)

# Build transitions
stmts_sorted = stmts.sort_values(["card_id","period_month"])
stmts_sorted["next_bucket"] = stmts_sorted.groupby("card_id")["dpd_bucket"].shift(-1)
transitions  = stmts_sorted.dropna(subset=["next_bucket"])

# Roll rate matrix
roll_matrix = (transitions
               .groupby(["dpd_bucket","next_bucket"])
               .size()
               .reset_index(name="count"))
roll_matrix["total"] = roll_matrix.groupby("dpd_bucket")["count"].transform("sum")
roll_matrix["roll_rate"] = (roll_matrix["count"] / roll_matrix["total"] * 100).round(2)

bucket_order = ["0","1-29","30-59","60-89","90+"]
pivot = (roll_matrix
         .pivot(index="dpd_bucket", columns="next_bucket", values="roll_rate")
         .reindex(index=bucket_order, columns=bucket_order)
         .fillna(0))

print("\n  Roll Rate Matrix (%):\n")
print(pivot.to_string())

# ─────────────────────────────────────────────────────────────
# SECTION 9: VINTAGE ANALYSIS
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 9: VINTAGE ANALYSIS")
print("=" * 65)

# MOB (months on book)
first_month = stmts.groupby("card_id")["period_month"].min().reset_index()
first_month.columns = ["card_id","cohort_month"]

vintage = stmts.merge(first_month, on="card_id")
vintage["mob"] = (
    ((vintage["period_month"].dt.year  - vintage["cohort_month"].dt.year) * 12 +
     (vintage["period_month"].dt.month - vintage["cohort_month"].dt.month))
).astype(int)

vintage_curves = (vintage
                  .groupby(["cohort_month","mob"])
                  .agg(accounts   =("card_id","count"),
                       defaulted  =("days_past_due", lambda x: (x >= 90).sum()),
                       delinquent =("days_past_due", lambda x: (x >= 30).sum()))
                  .reset_index())
vintage_curves["default_rate"]    = (vintage_curves["defaulted"]  / vintage_curves["accounts"] * 100).round(4)
vintage_curves["delinquency_rate"]= (vintage_curves["delinquent"] / vintage_curves["accounts"] * 100).round(4)

print(f"  Vintage curves built for {vintage_curves['cohort_month'].nunique()} cohorts")
print(f"  MOB range: {vintage_curves['mob'].min()} → {vintage_curves['mob'].max()}")

# ─────────────────────────────────────────────────────────────
# SECTION 10: ML DEFAULT PREDICTION MODEL
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 10: LOGISTIC REGRESSION DEFAULT MODEL")
print("=" * 65)

from sklearn.linear_model    import LogisticRegression
from sklearn.model_selection  import train_test_split
from sklearn.preprocessing    import StandardScaler
from sklearn.metrics          import (classification_report,
                                      roc_auc_score,
                                      confusion_matrix,
                                      RocCurveDisplay)

FEATURES = ["avg_util","max_util","avg_pay_ratio",
            "avg_dpd","del_months","avg_rev_bal"]

X = card_feats[FEATURES]
y = card_feats["default_flag"]

print(f"  Class balance: {y.value_counts().to_dict()}")

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y)

scaler    = StandardScaler()
Xtr_s     = scaler.fit_transform(X_train)
Xte_s     = scaler.transform(X_test)

model     = LogisticRegression(max_iter=1000, random_state=42)
model.fit(Xtr_s, y_train)

y_pred = model.predict(Xte_s)
y_prob = model.predict_proba(Xte_s)[:, 1]

auc = roc_auc_score(y_test, y_prob)
print(f"\n  ROC-AUC Score  : {auc:.4f}")
print("\n  Classification Report:")
print(classification_report(y_test, y_pred))

# ─────────────────────────────────────────────────────────────
# SECTION 11: CHARTS  (7 charts saved for Tableau)
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 11: GENERATING CHARTS")
print("=" * 65)

# ── CHART 1: Portfolio Overview (DPD + Util dist) ────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
fig.suptitle("Dashboard 1 — Portfolio Overview", fontsize=14, fontweight="bold")

dpd_dist = master["dpd_bucket"].value_counts().reindex(bucket_order).fillna(0)
c_map    = ["#2ecc71","#f39c12","#e67e22","#e74c3c","#8e44ad"]
dpd_dist.plot(kind="bar", ax=axes[0], color=c_map, edgecolor="white")
axes[0].set_title("DPD Bucket Distribution"); axes[0].tick_params(axis="x", rotation=0)
axes[0].set_xlabel("DPD Bucket"); axes[0].set_ylabel("Account-Months")
for bar in axes[0].patches:
    axes[0].text(bar.get_x()+bar.get_width()/2, bar.get_height()+1000,
                 f"{bar.get_height()/1000:.0f}K", ha="center", fontsize=8)

util_dist = master["util_band"].value_counts()
axes[1].pie(util_dist, labels=util_dist.index, autopct="%1.1f%%",
            colors=["#2ecc71","#f39c12","#e67e22","#e74c3c"],
            startangle=90, wedgeprops={"edgecolor":"white","linewidth":2})
axes[1].set_title("Credit Utilization Bands"); axes[1].set_ylabel("")

plt.tight_layout()
plt.savefig("../tableau/chart1_portfolio_overview.png", dpi=150, bbox_inches="tight")
plt.close(); print("  ✓ chart1_portfolio_overview.png")

# ── CHART 2: Monthly Delinquency Trend ───────────────────────
monthly = (master.groupby("period_month")
           .agg(total=("card_id","count"),
                del30=("is_delinquent","sum"),
                def90=("is_default","sum"),
                exposure=("statement_balance","sum"))
           .reset_index())
monthly["del_rate"] = monthly["del30"] / monthly["total"] * 100
monthly["def_rate"] = monthly["def90"] / monthly["total"] * 100

fig, ax1 = plt.subplots(figsize=(14, 5))
fig.suptitle("Dashboard 2 — Monthly Delinquency Trend", fontsize=14, fontweight="bold")
ax2 = ax1.twinx()
ax1.bar(monthly["period_month"], monthly["exposure"], width=25,
        color="#3498db", alpha=0.25, label="Exposure")
ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x,_: f"{x/1e9:.1f}B"))
ax1.set_ylabel("Portfolio Exposure", color="#3498db")
ax2.plot(monthly["period_month"], monthly["del_rate"],
         color="#e74c3c", lw=2.5, marker="o", markersize=4, label="Del Rate 30+")
ax2.plot(monthly["period_month"], monthly["def_rate"],
         color="#8e44ad", lw=2, marker="s", markersize=3,
         linestyle="--", label="Default Rate 90+")
ax2.set_ylabel("Rate (%)", color="#e74c3c"); ax2.set_ylim(0, 40)
lines = ax1.get_legend_handles_labels()[0] + ax2.get_legend_handles_labels()[0]
lbls  = ax1.get_legend_handles_labels()[1] + ax2.get_legend_handles_labels()[1]
ax1.legend(lines, lbls, loc="upper left")
plt.tight_layout()
plt.savefig("../tableau/chart2_monthly_trend.png", dpi=150, bbox_inches="tight")
plt.close(); print("  ✓ chart2_monthly_trend.png")

# ── CHART 3: Roll Rate Heatmap ────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 6))
fig.suptitle("Dashboard 4 — Roll Rate Heatmap", fontsize=14, fontweight="bold")
sns.heatmap(pivot, annot=True, fmt=".1f", cmap="YlOrRd",
            linewidths=0.5, cbar_kws={"label":"Roll Rate (%)"},
            ax=ax, vmin=0, vmax=100)
ax.set_xlabel("Next Month Bucket"); ax.set_ylabel("Current Month Bucket")
plt.tight_layout()
plt.savefig("../tableau/chart3_roll_rate_heatmap.png", dpi=150, bbox_inches="tight")
plt.close(); print("  ✓ chart3_roll_rate_heatmap.png")

# ── CHART 4: Vintage Curves ───────────────────────────────────
fig, ax = plt.subplots(figsize=(14, 6))
fig.suptitle("Dashboard 3 — Vintage Default Rate Curves", fontsize=14, fontweight="bold")

sampled_cohorts = vintage_curves["cohort_month"].unique()[::3]  # every 3rd cohort
cmap_v = plt.cm.get_cmap("tab20", len(sampled_cohorts))

for i, cohort in enumerate(sampled_cohorts):
    vc = vintage_curves[vintage_curves["cohort_month"] == cohort]
    ax.plot(vc["mob"], vc["default_rate"],
            color=cmap_v(i), linewidth=1.5, alpha=0.8,
            label=str(cohort.date()) if hasattr(cohort, "date") else str(cohort))

ax.set_xlabel("Months on Book (MOB)")
ax.set_ylabel("Default Rate (%)")
ax.set_title("Vintage Default Curves by Cohort Month")
ax.legend(loc="upper left", fontsize=7, ncol=3, framealpha=0.7)
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig("../tableau/chart4_vintage_curves.png", dpi=150, bbox_inches="tight")
plt.close(); print("  ✓ chart4_vintage_curves.png")

# ── CHART 5: Expected Loss Breakdown ─────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(16, 5))
fig.suptitle("Dashboard 6 — Expected Loss Breakdown", fontsize=14, fontweight="bold")

# IFRS9 Stage
stage_colors = {"Stage 1":"#2ecc71","Stage 2":"#f39c12","Stage 3":"#e74c3c"}
sc = el_df["ifrs9_stage"].value_counts()
axes[0].pie(sc, labels=sc.index, autopct="%1.1f%%",
            colors=[stage_colors.get(l,"gray") for l in sc.index],
            startangle=90, wedgeprops={"edgecolor":"white","linewidth":2})
axes[0].set_title("IFRS 9 Stage Distribution")

# EL by Stage
stage_el = el_df.groupby("ifrs9_stage")["expected_loss"].sum()
stage_el.plot(kind="bar", ax=axes[1],
              color=[stage_colors.get(l,"gray") for l in stage_el.index],
              edgecolor="white")
axes[1].set_title("Expected Loss by IFRS 9 Stage")
axes[1].set_ylabel("Expected Loss")
axes[1].yaxis.set_major_formatter(mticker.FuncFormatter(lambda x,_: f"{x/1e6:.0f}M"))
axes[1].tick_params(axis="x", rotation=0)

# PD Score Distribution
axes[2].hist(el_df["pd_score"], bins=40, color="#3498db", edgecolor="white", alpha=0.8)
axes[2].axvline(0.20, color="#f39c12", lw=2, linestyle="--", label="Stage 2 threshold")
axes[2].axvline(0.60, color="#e74c3c", lw=2, linestyle="--", label="Stage 3 threshold")
axes[2].set_title("PD Score Distribution")
axes[2].set_xlabel("PD Score"); axes[2].set_ylabel("Accounts")
axes[2].legend()

plt.tight_layout()
plt.savefig("../tableau/chart5_expected_loss.png", dpi=150, bbox_inches="tight")
plt.close(); print("  ✓ chart5_expected_loss.png")

# ── CHART 6: Model Performance ────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
fig.suptitle("Logistic Regression — Default Prediction Model", fontsize=14, fontweight="bold")

cm = confusion_matrix(y_test, y_pred)
sns.heatmap(cm, annot=True, fmt="d", cmap="Blues", ax=axes[0],
            xticklabels=["No Default","Default"],
            yticklabels=["No Default","Default"])
axes[0].set_title(f"Confusion Matrix"); axes[0].set_xlabel("Predicted"); axes[0].set_ylabel("Actual")

RocCurveDisplay.from_predictions(y_test, y_prob, ax=axes[1],
    name=f"Logistic (AUC = {auc:.3f})")
axes[1].plot([0,1],[0,1],"k--",lw=1)
axes[1].set_title("ROC Curve")

plt.tight_layout()
plt.savefig("../tableau/chart6_model_performance.png", dpi=150, bbox_inches="tight")
plt.close(); print("  ✓ chart6_model_performance.png")

# ── CHART 7: Utilization Segments ────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
fig.suptitle("Dashboard 5 — Utilization Segments", fontsize=14, fontweight="bold")

region_util = (master.groupby("region")
               .agg(avg_util=("utilization","mean"),
                    del_rate=("is_delinquent","mean"))
               .reset_index()
               .sort_values("del_rate", ascending=False))

axes[0].barh(region_util["region"], region_util["del_rate"]*100,
             color="#e74c3c", edgecolor="white")
axes[0].set_title("Delinquency Rate by Region")
axes[0].set_xlabel("Delinquency Rate (%)")
for i, (v, r) in enumerate(zip(region_util["del_rate"]*100, region_util["region"])):
    axes[0].text(v + 0.1, i, f"{v:.1f}%", va="center")

income_util = (master.groupby("income_band")
               .agg(avg_util=("utilization","mean"),
                    del_rate=("is_delinquent","mean"))
               .reset_index()
               .sort_values("del_rate", ascending=False))

x = range(len(income_util))
axes[1].bar([i-0.2 for i in x], income_util["avg_util"]*100,
            width=0.4, color="#3498db", label="Avg Utilization", edgecolor="white")
axes[1].bar([i+0.2 for i in x], income_util["del_rate"]*100,
            width=0.4, color="#e74c3c", label="Delinquency Rate", edgecolor="white")
axes[1].set_xticks(list(x)); axes[1].set_xticklabels(income_util["income_band"])
axes[1].set_title("Utilization & Delinquency by Income Band")
axes[1].set_ylabel("Rate (%)"); axes[1].legend()

plt.tight_layout()
plt.savefig("../tableau/chart7_utilization_segments.png", dpi=150, bbox_inches="tight")
plt.close(); print("  ✓ chart7_utilization_segments.png")

# ─────────────────────────────────────────────────────────────
# SECTION 12: EXPORT FOR TABLEAU  (6 dashboard CSVs)
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  SECTION 12: EXPORTING TABLEAU DATASETS")
print("=" * 65)

# 1. Portfolio Overview
master_sample = master.sample(min(200_000, len(master)), random_state=42)
master_sample.to_csv("../tableau/T1_portfolio_overview.csv", index=False)
print(f"  ✓ T1_portfolio_overview.csv  → {len(master_sample):,} rows")

# 2. Monthly Delinquency Trend
monthly.to_csv("../tableau/T2_monthly_trend.csv", index=False)
print(f"  ✓ T2_monthly_trend.csv       → {len(monthly):,} rows")

# 3. Vintage Curves
vintage_curves.to_csv("../tableau/T3_vintage_curves.csv", index=False)
print(f"  ✓ T3_vintage_curves.csv      → {len(vintage_curves):,} rows")

# 4. Roll Rate Matrix
roll_matrix.to_csv("../tableau/T4_roll_rate_matrix.csv", index=False)
print(f"  ✓ T4_roll_rate_matrix.csv    → {len(roll_matrix):,} rows")

# 5. Utilization Segments
seg_export = (master.groupby(["region","income_band","product_type","util_band"])
              .agg(accounts=("card_id","nunique"),
                   avg_util=("utilization","mean"),
                   del_rate=("is_delinquent","mean"),
                   def_rate=("is_default","mean"),
                   exposure=("statement_balance","sum"))
              .reset_index())
seg_export.to_csv("../tableau/T5_utilization_segments.csv", index=False)
print(f"  ✓ T5_utilization_segments.csv → {len(seg_export):,} rows")

# 6. Expected Loss Breakdown
el_export = (el_df
             .merge(cards[["card_id","customer_id","product_type","credit_limit"]], on="card_id")
             .merge(customers, on="customer_id"))
el_export.to_csv("../tableau/T6_expected_loss.csv", index=False)
print(f"  ✓ T6_expected_loss.csv       → {len(el_export):,} rows")

# ─────────────────────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("  FINAL PROJECT SUMMARY")
print("=" * 65)
print(f"  Customers              : {len(customers):>10,}")
print(f"  Cards                  : {len(cards):>10,}")
print(f"  Statements             : {len(stmts):>10,}")
print(f"  Write-offs             : {len(writeoffs):>10,}")
print(f"  Date Range             : {stmts.period_month.min().date()} → {stmts.period_month.max().date()}")
print()
print(f"  Portfolio PD (90+)     : {portfolio_pd:.2%}")
print(f"  Portfolio LGD          : {portfolio_lgd:.2%}")
print(f"  Portfolio EAD          : {portfolio_ead:>15,.0f}")
print(f"  Expected Loss          : {total_el:>15,.0f}")
print(f"  EL Rate (EL/EAD)       : {total_el/total_ead_model:.2%}")
print()
s1 = (el_df["ifrs9_stage"]=="Stage 1").sum()
s2 = (el_df["ifrs9_stage"]=="Stage 2").sum()
s3 = (el_df["ifrs9_stage"]=="Stage 3").sum()
print(f"  IFRS9 Stage 1          : {s1:>10,} accounts")
print(f"  IFRS9 Stage 2          : {s2:>10,} accounts")
print(f"  IFRS9 Stage 3          : {s3:>10,} accounts")
print()
print(f"  ML Model ROC-AUC       : {auc:.4f}")
print()
print(f"  Charts saved           : 7 PNG files")
print(f"  Tableau CSVs saved     : 6 CSV files (T1–T6)")
print("=" * 65)
