"""
=============================================================
 Credit Card Risk Analytics Project
 File: generate_dataset.py
 Purpose: Generate realistic bank-scale dataset
=============================================================
 Tables generated:
   customers  → 50,000 rows
   cards      → 50,000 rows
   statements → 1,500,000 rows
   writeoffs  → 2,000 rows
=============================================================
"""

import pandas as pd
import numpy as np
import os

np.random.seed(42)

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────
N_CUSTOMERS  = 50_000
N_CARDS      = 50_000
N_MONTHS     = 30           # 30 months of statements
N_WRITEOFFS  = 2_000
OUT_DIR      = "../data"
os.makedirs(OUT_DIR, exist_ok=True)

# ─────────────────────────────────────────────────────────────
# TABLE 1: CUSTOMERS  (50,000 rows)
# ─────────────────────────────────────────────────────────────
print("Generating customers...")

regions     = ["North", "South", "East", "West", "Central"]
income_band = ["low", "medium", "high"]

customers = pd.DataFrame({
    "customer_id": range(1, N_CUSTOMERS + 1),
    "region":      np.random.choice(regions,     N_CUSTOMERS,
                                    p=[0.20, 0.25, 0.20, 0.20, 0.15]),
    "income_band": np.random.choice(income_band, N_CUSTOMERS,
                                    p=[0.35, 0.45, 0.20]),
    "age":         np.random.randint(22, 65, N_CUSTOMERS),
    "tenure_years":np.random.randint(1,  15, N_CUSTOMERS),
})

customers.to_csv(f"{OUT_DIR}/customers.csv", index=False)
print(f"  ✓ customers.csv  → {len(customers):,} rows")

# ─────────────────────────────────────────────────────────────
# TABLE 2: CARDS  (50,000 rows)
# ─────────────────────────────────────────────────────────────
print("Generating cards...")

product_types   = ["classic", "premium", "platinum", "business"]
product_weights = [0.40, 0.35, 0.15, 0.10]

# Credit limits depend on income band via customer lookup
income_limit_map = {
    "low":    (10_000,  80_000),
    "medium": (50_000, 250_000),
    "high":  (150_000, 800_000),
}

cust_income = dict(zip(customers["customer_id"], customers["income_band"]))

card_rows = []
for card_id in range(1, N_CARDS + 1):
    cust_id  = card_id                          # 1-to-1 mapping
    inc      = cust_income[cust_id]
    lo, hi   = income_limit_map[inc]
    limit    = int(np.random.randint(lo // 1000, hi // 1000) * 1000)
    product  = np.random.choice(product_types, p=product_weights)
    card_rows.append((card_id, cust_id, product, limit))

cards = pd.DataFrame(card_rows,
                     columns=["card_id","customer_id","product_type","credit_limit"])
cards.to_csv(f"{OUT_DIR}/cards.csv", index=False)
print(f"  ✓ cards.csv      → {len(cards):,} rows")

# ─────────────────────────────────────────────────────────────
# TABLE 3: STATEMENTS  (1,500,000 rows)
# ─────────────────────────────────────────────────────────────
print("Generating statements (1.5M rows — this takes ~60s)...")

import pandas as pd
from datetime import date

start_month = pd.Timestamp("2022-01-01")
months      = pd.date_range(start_month, periods=N_MONTHS, freq="MS")

card_limit   = dict(zip(cards["card_id"], cards["credit_limit"]))
card_product = dict(zip(cards["card_id"], cards["product_type"]))

# Risk profiles — each card gets a base risk level
# Higher risk → higher utilization & more DPD
risk_profile = np.random.choice(
    ["low","medium","high","distressed"],
    N_CARDS,
    p=[0.45, 0.30, 0.17, 0.08]
)
card_risk = dict(zip(range(1, N_CARDS + 1), risk_profile))

dpd_bucket_map = {
    0:  "0",
    1:  "1-29",
    2:  "30-59",
    3:  "60-89",
    4:  "90+",
}

all_stmts = []

CHUNK = 5000
for chunk_start in range(1, N_CARDS + 1, CHUNK):
    chunk_end  = min(chunk_start + CHUNK, N_CARDS + 1)
    chunk_ids  = range(chunk_start, chunk_end)
    n          = len(range(chunk_start, chunk_end))

    for month_idx, month in enumerate(months):
        limits  = np.array([card_limit[c] for c in chunk_ids])
        risks   = [card_risk[c] for c in chunk_ids]

        # Utilization based on risk
        util_base = np.where(
            np.array(risks) == "distressed", np.random.uniform(0.70, 1.10, n),
            np.where(
                np.array(risks) == "high",       np.random.uniform(0.50, 0.95, n),
                np.where(
                    np.array(risks) == "medium", np.random.uniform(0.25, 0.70, n),
                                                 np.random.uniform(0.05, 0.45, n)
                )
            )
        ).clip(0, 1)

        balances = (util_base * limits).astype(int)

        # Min due = 3% of balance
        min_dues = (balances * 0.03).astype(int)

        # Payment behavior
        pay_ratio = np.where(
            np.array(risks) == "distressed", np.random.uniform(0.00, 0.25, n),
            np.where(
                np.array(risks) == "high",       np.random.uniform(0.05, 0.60, n),
                np.where(
                    np.array(risks) == "medium", np.random.uniform(0.30, 0.90, n),
                                                 np.random.uniform(0.70, 1.10, n)
                )
            )
        ).clip(0, 1)

        paid = (balances * pay_ratio).astype(int)

        # DPD based on risk
        dpd_raw = np.where(
            np.array(risks) == "distressed",
            np.random.choice([0,15,30,45,60,75,90,120], n,
                             p=[0.10,0.10,0.20,0.20,0.15,0.10,0.10,0.05]),
            np.where(
                np.array(risks) == "high",
                np.random.choice([0,10,30,45,60,75,90], n,
                                 p=[0.35,0.20,0.20,0.10,0.08,0.04,0.03]),
                np.where(
                    np.array(risks) == "medium",
                    np.random.choice([0,10,30,45,60], n,
                                     p=[0.60,0.20,0.12,0.05,0.03]),
                    np.random.choice([0,5,10,30], n,
                                     p=[0.85,0.08,0.05,0.02])
                )
            )
        )

        dpd_buckets = np.where(
            dpd_raw == 0,  "0",
            np.where(dpd_raw <= 29, "1-29",
            np.where(dpd_raw <= 59, "30-59",
            np.where(dpd_raw <= 89, "60-89", "90+")))
        )

        # Transaction amount
        tx_amount = (balances * np.random.uniform(0.05, 0.25, n)).astype(int)

        chunk_df = pd.DataFrame({
            "card_id":           list(chunk_ids),
            "period_month":      month.strftime("%Y-%m-%d"),
            "statement_balance": balances,
            "min_due":           min_dues,
            "paid_amount":       paid,
            "days_past_due":     dpd_raw,
            "dpd_bucket":        dpd_buckets,
            "credit_limit":      limits,
            "transaction_amount": tx_amount,
        })
        all_stmts.append(chunk_df)

    if chunk_start % 10000 == 1:
        print(f"    → Processed cards {chunk_start:,}–{chunk_end-1:,}")

statements = pd.concat(all_stmts, ignore_index=True)
statements.to_csv(f"{OUT_DIR}/statements.csv", index=False)
print(f"  ✓ statements.csv → {len(statements):,} rows")

# ─────────────────────────────────────────────────────────────
# TABLE 4: WRITEOFFS  (2,000 rows)
# ─────────────────────────────────────────────────────────────
print("Generating writeoffs...")

# Pick 2000 cards that had 90+ DPD
defaulted_cards = (statements[statements["days_past_due"] >= 90]
                   ["card_id"].unique())
writeoff_cards  = np.random.choice(defaulted_cards,
                                   size=min(N_WRITEOFFS, len(defaulted_cards)),
                                   replace=False)

# Get their max balance
max_bal = (statements[statements["card_id"].isin(writeoff_cards)]
           .groupby("card_id")["statement_balance"].max()
           .reset_index()
           .rename(columns={"statement_balance":"writeoff_amount"}))

max_bal = max_bal[max_bal["card_id"].isin(writeoff_cards)].copy()

# Recovery rate: 0–40% of writeoff
max_bal["recovery_amount"] = (
    max_bal["writeoff_amount"] * np.random.uniform(0, 0.40, len(max_bal))
).astype(int)

# Writeoff dates spread over 2 years
wo_dates = pd.date_range("2023-01-01", "2024-12-31", periods=len(max_bal))
max_bal["writeoff_date"] = np.random.choice(
    [d.strftime("%Y-%m-%d") for d in wo_dates], len(max_bal), replace=False
)

writeoffs = max_bal[["card_id","writeoff_amount","recovery_amount","writeoff_date"]]
writeoffs.to_csv(f"{OUT_DIR}/writeoffs.csv", index=False)
print(f"  ✓ writeoffs.csv  → {len(writeoffs):,} rows")

# ─────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 50)
print("  DATASET GENERATION COMPLETE")
print("=" * 50)
print(f"  customers.csv  : {len(customers):>10,} rows")
print(f"  cards.csv      : {len(cards):>10,} rows")
print(f"  statements.csv : {len(statements):>10,} rows")
print(f"  writeoffs.csv  : {len(writeoffs):>10,} rows")
print("=" * 50)
