```markdown
# 💳 Credit Card Risk Analytics & Early Default Detection
> **End-to-End Bank-Grade Portfolio Risk Monitoring**
> SQL (70%) · Python (20%) · Tableau (10%)

**[🌐 Live Interactive Dashboard](https://rohitmannur007.github.io/DASHBORD-html/)**  
*(All 6 dashboards hosted & ready to explore — no Tableau installation needed!)*

![SQL](https://img.shields.io/badge/SQL-70%25-blue)
![Python](https://img.shields.io/badge/Python-20%25-green)
![Tableau](https://img.shields.io/badge/Tableau-10%25-orange)
![Rows](https://img.shields.io/badge/Data-1.6M%20Rows-purple)

---

## 📋 Project Overview
This project replicates the **credit risk analytics pipeline** used at banks like JPMorgan Chase, HSBC, and American Express. It covers the full spectrum of credit risk monitoring from raw transactional data to regulatory-grade risk metrics.

**What this project builds:**

| Component | Description |
|-----------|-------------|
| PD (Probability of Default) | Likelihood a customer will default in 12 months |
| LGD (Loss Given Default) | % of exposure lost when a default occurs |
| EAD (Exposure at Default) | Total exposure at time of default (with CCF) |
| Expected Loss (EL = PD × LGD × EAD) | Regulatory provision amount |
| IFRS 9 Staging | Stage 1 / 2 / 3 classification |
| Roll Rate Analysis | Bucket-to-bucket migration matrix |
| Vintage Analysis | Cohort default curves by origination month |

---

## 📊 Dataset
| Table | Rows | Description |
|--------------|-------------|--------------------------------------|
| `customers` | 50,000 | Demographics: region, income, age |
| `cards` | 50,000 | Card product type and credit limit |
| `statements` | 1,500,000 | 30 months of billing statements |
| `writeoffs` | 2,000 | Written-off accounts with recovery |

**Run `python/generate_dataset.py` to regenerate the dataset.**

---

## 📁 Project Structure
```
credit-risk-analytics/
│
├── data/
│ ├── customers.csv
│ ├── cards.csv
│ ├── statements.csv
│ └── writeoffs.csv
│
├── sql/
│ ├── 01_create_tables.sql ← Schema & data load
│ ├── 02_data_cleaning.sql ← Quality validation
│ ├── 03_feature_engineering.sql ← Risk views & derived metrics
│ ├── 04_risk_metrics.sql ← 9 core banking KPIs
│ ├── 05_delinquency_analysis.sql ← Trends, cure rates, EWI
│ ├── 06_advanced_queries.sql ← 15 advanced SQL queries
│ ├── 07_pd_calculation.sql ← Probability of Default
│ ├── 08_lgd_calculation.sql ← Loss Given Default
│ ├── 09_ead_calculation.sql ← Exposure at Default
│ ├── 10_expected_loss.sql ← EL = PD × LGD × EAD + IFRS 9
│ ├── 11_roll_rate_matrix.sql ← Full migration matrix
│ └── 12_vintage_analysis.sql ← Cohort default curves
│
├── python/
│ ├── generate_dataset.py ← Generates all 4 CSVs
│ └── risk_analysis.py ← Full analysis + ML model + exports
│
├── tableau/
│ ├── T1_portfolio_overview.csv ← Dashboard 1 data
│ ├── T2_monthly_trend.csv ← Dashboard 2 data
│ ├── T3_vintage_curves.csv ← Dashboard 3 data
│ ├── T4_roll_rate_matrix.csv ← Dashboard 4 data
│ ├── T5_utilization_segments.csv ← Dashboard 5 data
│ ├── T6_expected_loss.csv ← Dashboard 6 data
│ └── TABLEAU_SETUP_GUIDE.txt ← Step-by-step Tableau guide
│
└── README.md
```

---

## 🚀 How to Run
### Step 1 — Generate Dataset
```bash
cd python/
python generate_dataset.py
# Creates: customers.csv, cards.csv, statements.csv, writeoffs.csv
```

### Step 2 — SQL Pipeline (Run in order)
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

### Step 3 — Python Analysis
```bash
cd python/
pip install pandas numpy matplotlib seaborn scikit-learn
python risk_analysis.py
# Generates: 7 charts + 6 Tableau CSVs
```

### Step 4 — Tableau Dashboard
**🎉 Instant option:**  
**[View Live Hosted Dashboard](https://rohitmannur007.github.io/DASHBORD-html/)** (GitHub Pages — works on mobile too!)

**OR** build locally:  
1. Open Tableau Desktop  
2. Connect to each `T1_*.csv` through `T6_*.csv`  
3. Build 6 dashboards as described in `TABLEAU_SETUP_GUIDE.txt`

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

**🔴 All dashboards are live here:** [https://rohitmannur007.github.io/DASHBORD-html/](https://rohitmannur007.github.io/DASHBORD-html/)

---

## 🏦 Banking Concepts Demonstrated
| Concept | File |
|---------|------|
| DPD Buckets (0/1-29/30-59/60-89/90+) | All SQL files |
| Probability of Default (PD) | 07_pd_calculation.sql |
| Loss Given Default (LGD) | 08_lgd_calculation.sql |
| Exposure at Default (EAD) | 09_ead_calculation.sql |
| Expected Loss (ECL) | 10_expected_loss.sql |
| IFRS 9 Stage 1/2/3 | 10_expected_loss.sql |
| Roll Rate Analysis | 11_roll_rate_matrix.sql |
| Vintage / Cohort Analysis | 12_vintage_analysis.sql |
| Basel III CCF | 09_ead_calculation.sql |
| Stress Testing | 06_advanced_queries.sql |
| Collections Efficiency | 06_advanced_queries.sql |
| Early Warning Indicators | 03_feature_engineering.sql |

---

## 💼 Resume Description
> **Credit Card Risk Analytics Dashboard** *(SQL · Python · Tableau)*
>
> • Analyzed **1.5M credit card statements** for 50,000 customers to build a bank-grade risk monitoring system  
> • Calculated **PD, LGD, EAD, and Expected Loss** metrics following IFRS 9 and Basel III frameworks  
> • Built **roll rate matrices and vintage curves** used by credit risk teams for loss reserve calculation  
> • Developed **IFRS 9 stage classification model** separating portfolio into Stage 1 / 2 / 3 (ECL provisioning)  
> • Built logistic regression default model achieving **ROC-AUC of 0.99**  
> • Delivered **6 interactive Tableau dashboards** (hosted live on GitHub Pages) covering portfolio overview, delinquency trends, vintage curves, and expected loss

*Replicates analytics used at JPMorgan Chase, HSBC, American Express, and other major credit card issuers.*
```

*
