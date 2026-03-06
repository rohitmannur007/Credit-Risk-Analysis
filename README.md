

# 💳 Credit Card Risk Analytics & Early Default Detection
> **End-to-End Bank-Grade Portfolio Risk Monitoring**  
> SQL (70%) · Python (20%) · Tableau (10%)

**[🌐 Live Interactive Dashboard](https://rohitmannur007.github.io/DASHBORD-html/)**  


![SQL](https://img.shields.io/badge/SQL-70%25-blue) ![Python](https://img.shields.io/badge/Python-20%25-green) ![Tableau](https://img.shields.io/badge/Tableau-10%25-orange) ![Rows](https://img.shields.io/badge/Data-1.6M%20Rows-purple)

---

## 📋 Project Overview

This project replicates a **credit risk analytics pipeline used in large banks** such as JPMorgan Chase, HSBC, and American Express. It demonstrates the **complete credit portfolio risk monitoring workflow**, starting from raw transactional data and progressing to regulatory-grade risk metrics.

### What This Project Builds

| Component | Description |
|-----------|-------------|
| **PD (Probability of Default)** | Likelihood that a customer will default within 12 months |
| **LGD (Loss Given Default)** | Percentage of exposure lost when a default occurs |
| **EAD (Exposure at Default)** | Total exposure at the time of default (including CCF adjustments) |
| **Expected Loss (EL = PD × LGD × EAD)** | Regulatory provision amount required for credit losses |
| **IFRS 9 Staging** | Classification of accounts into Stage 1 / Stage 2 / Stage 3 |
| **Roll Rate Analysis** | Migration of accounts between delinquency buckets |
| **Vintage Analysis** | Cohort-based default analysis by origination month |

---

## 📊 Dataset

| Table | Rows | Description |
|-------|------|-------------|
| `customers` | 50,000 | Customer demographics (region, income, age) |
| `cards` | 50,000 | Credit card product type and credit limit |
| `statements` | 1,500,000 | 30 months of billing statement data |
| `writeoffs` | 2,000 | Written-off accounts and recovery information |

To regenerate the dataset:

```bash
python python/generate_dataset.py
```

---

## 📁 Project Structure

```
credit-risk-analytics/
│
├── data/
│   ├── customers.csv
│   ├── cards.csv
│   ├── statements.csv
│   └── writeoffs.csv
│
├── sql/
│   ├── 01_create_tables.sql        ← Schema creation & data loading
│   ├── 02_data_cleaning.sql        ← Data quality validation
│   ├── 03_feature_engineering.sql  ← Risk features & derived metrics
│   ├── 04_risk_metrics.sql         ← Core banking KPIs
│   ├── 05_delinquency_analysis.sql ← Delinquency trends & cure rates
│   ├── 06_advanced_queries.sql     ← Advanced portfolio analytics
│   ├── 07_pd_calculation.sql       ← Probability of Default
│   ├── 08_lgd_calculation.sql      ← Loss Given Default
│   ├── 09_ead_calculation.sql      ← Exposure at Default
│   ├── 10_expected_loss.sql        ← Expected Loss + IFRS 9 staging
│   ├── 11_roll_rate_matrix.sql     ← Delinquency migration matrix
│   └── 12_vintage_analysis.sql     ← Cohort-based default analysis
│
├── python/
│   ├── generate_dataset.py         ← Generates all dataset tables
│   └── risk_analysis.py            ← Risk analysis, ML model, exports
│
├── tableau/
│   ├── T1_portfolio_overview.csv
│   ├── T2_monthly_trend.csv
│   ├── T3_vintage_curves.csv
│   ├── T4_roll_rate_matrix.csv
│   ├── T5_utilization_segments.csv
│   ├── T6_expected_loss.csv
│   └── TABLEAU_SETUP_GUIDE.txt
│
└── README.md
```

---

## 🚀 How to Run

### Step 1 — Generate Dataset

```bash
cd python/
python generate_dataset.py
```

This will generate: `customers.csv`, `cards.csv`, `statements.csv`, `writeoffs.csv`

---

### Step 2 — SQL Pipeline (Run in Order)

```sql
-- PostgreSQL
psql -U postgres -d credit_risk_project

\i sql/01_create_tables.sql
\i sql/02_data_cleaning.sql
\i sql/03_feature_engineering.sql
\i sql/04_risk_metrics.sql
\i sql/05_delinquency_analysis.sql
\i sql/06_advanced_queries.sql
\i sql/07_pd_calculation.sql
\i sql/08_lgd_calculation.sql
\i sql/09_ead_calculation.sql
\i sql/10_expected_loss.sql
\i sql/11_roll_rate_matrix.sql
\i sql/12_vintage_analysis.sql
```

---

### Step 3 — Python Analysis

```bash
cd python/
pip install pandas numpy matplotlib seaborn scikit-learn
python risk_analysis.py
```

This generates risk analysis charts and 6 Tableau-ready data files.

---

### Step 4 — Tableau Dashboard

**Instant Option (No Installation Required)**

View the live hosted dashboard:  
🌐 [https://rohitmannur007.github.io/DASHBORD-html/](https://rohitmannur007.github.io/DASHBORD-html/)

---

**Local Build Option**

1. Open Tableau Desktop
2. Connect to each CSV file:
   - `T1_portfolio_overview.csv`
   - `T2_monthly_trend.csv`
   - `T3_vintage_curves.csv`
   - `T4_roll_rate_matrix.csv`
   - `T5_utilization_segments.csv`
   - `T6_expected_loss.csv`
3. Follow instructions in `TABLEAU_SETUP_GUIDE.txt`

---

## 📈 Tableau — 6 Dashboards

| # | Dashboard | Data Source |
|---|-----------|-------------|
| 1 | Portfolio Overview | T1_portfolio_overview.csv |
| 2 | Delinquency Trend | T2_monthly_trend.csv |
| 3 | Vintage Curves | T3_vintage_curves.csv |
| 4 | Roll Rate Heatmap | T4_roll_rate_matrix.csv |
| 5 | Utilization Segments | T5_utilization_segments.csv |
| 6 | Expected Loss Breakdown | T6_expected_loss.csv |

🌐 **Live Dashboard:** [https://rohitmannur007.github.io/DASHBORD-html/](https://rohitmannur007.github.io/DASHBORD-html/)

---

## 🏦 Banking Concepts Demonstrated

| Concept | File |
|---------|------|
| DPD Buckets (0 / 1–29 / 30–59 / 60–89 / 90+) | Multiple SQL scripts |
| Probability of Default (PD) | `07_pd_calculation.sql` |
| Loss Given Default (LGD) | `08_lgd_calculation.sql` |
| Exposure at Default (EAD) | `09_ead_calculation.sql` |
| Expected Credit Loss (ECL) | `10_expected_loss.sql` |
| IFRS 9 Stage Classification | `10_expected_loss.sql` |
| Roll Rate Analysis | `11_roll_rate_matrix.sql` |
| Vintage / Cohort Analysis | `12_vintage_analysis.sql` |
| Basel III Credit Conversion Factor | `09_ead_calculation.sql` |
| Stress Testing | `06_advanced_queries.sql` |
| Collections Efficiency | `06_advanced_queries.sql` |
| Early Warning Indicators | `03_feature_engineering.sql` |

---

## 💼 Resume Description

**Credit Card Risk Analytics Dashboard** *(SQL · Python · Tableau)*

- Analyzed 1.5M credit card statements for 50,000 customers to build a portfolio risk monitoring system
- Calculated PD, LGD, EAD, and Expected Loss following IFRS 9 and Basel III frameworks
- Built roll rate matrices and vintage curves used for credit loss forecasting
- Developed an IFRS 9 staging model classifying accounts into Stage 1 / Stage 2 / Stage 3
- Built a logistic regression default prediction model achieving ROC-AUC of 0.99
- Delivered 6 interactive Tableau dashboards hosted on GitHub Pages covering portfolio risk, delinquency trends, and expected losses

