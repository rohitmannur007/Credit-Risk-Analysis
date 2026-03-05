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
