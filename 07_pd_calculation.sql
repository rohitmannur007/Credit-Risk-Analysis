-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 07_pd_calculation.sql
-- Description: Probability of Default (PD) estimation
--
-- PD is one of the three core components of Expected Credit
-- Loss (ECL) under IFRS 9 / Basel III frameworks.
--
-- Definition:
--   PD = Probability that a borrower will default within
--        a 12-month forward-looking window.
--   Default trigger = DPD >= 90
-- ============================================================

-- ============================================================
-- PD 1: Portfolio-Level PD (Overall)
-- ============================================================
SELECT
    COUNT(DISTINCT CASE WHEN days_past_due >= 90 THEN card_id END)   AS defaulted_accounts,
    COUNT(DISTINCT card_id)                                           AS total_accounts,
    ROUND(
        COUNT(DISTINCT CASE WHEN days_past_due >= 90 THEN card_id END) * 100.0
        / COUNT(DISTINCT card_id), 4
    )                                                                 AS pd_pct
FROM statements;

-- ============================================================
-- PD 2: Monthly PD Trend
-- Tracks how PD evolves each month — key for IFRS 9 staging
-- ============================================================
SELECT
    period_month,
    COUNT(*)                                                           AS total_accounts,
    COUNT(CASE WHEN days_past_due >= 90 THEN 1 END)                    AS defaults,
    ROUND(
        COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*),
    4)                                                                 AS pd_pct,
    -- 3-month moving average PD
    ROUND(AVG(
        COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*)
    ) OVER (ORDER BY period_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 4) AS pd_3mo_avg
FROM statements
GROUP BY period_month
ORDER BY period_month;

-- ============================================================
-- PD 3: PD by Region
-- Regional PD differences reflect economic conditions
-- ============================================================
SELECT
    cu.region,
    COUNT(DISTINCT s.card_id)                                                    AS accounts,
    COUNT(DISTINCT CASE WHEN s.days_past_due >= 90 THEN s.card_id END)           AS defaults,
    ROUND(
        COUNT(DISTINCT CASE WHEN s.days_past_due >= 90 THEN s.card_id END) * 100.0
        / COUNT(DISTINCT s.card_id), 4
    )                                                                             AS pd_pct
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.region
ORDER BY pd_pct DESC;

-- ============================================================
-- PD 4: PD by Income Band
-- Lower income bands typically show higher PD
-- ============================================================
SELECT
    cu.income_band,
    COUNT(DISTINCT s.card_id)                                                    AS accounts,
    COUNT(DISTINCT CASE WHEN s.days_past_due >= 90 THEN s.card_id END)           AS defaults,
    ROUND(
        COUNT(DISTINCT CASE WHEN s.days_past_due >= 90 THEN s.card_id END) * 100.0
        / COUNT(DISTINCT s.card_id), 4
    )                                                                             AS pd_pct,
    ROUND(AVG(c.credit_limit), 0)                                                AS avg_limit
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.income_band
ORDER BY pd_pct DESC;

-- ============================================================
-- PD 5: PD by Product Type
-- ============================================================
SELECT
    c.product_type,
    COUNT(DISTINCT s.card_id)                                                    AS accounts,
    COUNT(DISTINCT CASE WHEN s.days_past_due >= 90 THEN s.card_id END)           AS defaults,
    ROUND(
        COUNT(DISTINCT CASE WHEN s.days_past_due >= 90 THEN s.card_id END) * 100.0
        / COUNT(DISTINCT s.card_id), 4
    )                                                                             AS pd_pct
FROM statements s
JOIN cards c ON s.card_id = c.card_id
GROUP BY c.product_type
ORDER BY pd_pct DESC;

-- ============================================================
-- PD 6: PD by Utilization Band
-- High utilization is a strong predictor of default
-- ============================================================
SELECT
    CASE
        WHEN statement_balance * 1.0 / NULLIF(credit_limit, 0) >= 0.9 THEN 'Critical 90%+'
        WHEN statement_balance * 1.0 / NULLIF(credit_limit, 0) >= 0.7 THEN 'High 70-89%'
        WHEN statement_balance * 1.0 / NULLIF(credit_limit, 0) >= 0.4 THEN 'Medium 40-69%'
        ELSE                                                                  'Low <40%'
    END AS utilization_band,
    COUNT(*)                                                                AS account_months,
    COUNT(CASE WHEN days_past_due >= 90 THEN 1 END)                         AS defaults,
    ROUND(
        COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*),
    4)                                                                      AS pd_pct
FROM statements
GROUP BY 1 ORDER BY pd_pct DESC;

-- ============================================================
-- PD 7: PD by Months on Book (MOB) — Lifetime PD Curve
-- Shows at which point in the account lifecycle default peaks
-- ============================================================
WITH mob_tagged AS (
    SELECT
        s.card_id, s.period_month, s.days_past_due,
        ROW_NUMBER() OVER (PARTITION BY s.card_id ORDER BY s.period_month) AS mob
    FROM statements s
)
SELECT
    mob,
    COUNT(*) AS accounts,
    COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) AS defaults,
    ROUND(
        COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*),
    4)                                               AS pd_pct
FROM mob_tagged
GROUP BY mob
ORDER BY mob;

-- ============================================================
-- PD 8: Account-Level 12-Month Forward PD Score
-- Assigns each account a point-in-time PD estimate
-- based on behavioral signals
-- ============================================================
WITH account_features AS (
    SELECT
        card_id,
        credit_limit,
        ROUND(AVG(statement_balance * 1.0 / NULLIF(credit_limit, 0)), 4)   AS avg_util,
        ROUND(AVG(days_past_due), 4)                                         AS avg_dpd,
        MAX(days_past_due)                                                   AS max_dpd,
        SUM(CASE WHEN days_past_due >= 30 THEN 1 ELSE 0 END)                 AS del_months,
        ROUND(AVG(paid_amount * 1.0 / NULLIF(statement_balance, 0)), 4)     AS avg_pay_ratio,
        COUNT(DISTINCT period_month)                                         AS months_on_book
    FROM statements
    GROUP BY card_id, credit_limit
)
SELECT
    card_id,
    avg_util,
    avg_dpd,
    max_dpd,
    del_months,
    avg_pay_ratio,
    months_on_book,
    -- PD score: logistic-like transformation of risk factors
    -- Higher = more likely to default in next 12 months
    ROUND(
        1.0 / (1.0 + EXP(-(
            -3.5                               -- intercept
            + avg_util          * 2.5          -- utilization driver
            + (avg_dpd / 30.0)  * 1.8          -- DPD driver
            + del_months        * 0.4          -- frequency driver
            - avg_pay_ratio     * 1.5          -- payment driver (negative = lower risk)
        ))), 4
    ) AS pd_score_12m,
    CASE
        WHEN ROUND(1.0 / (1.0 + EXP(-(
            -3.5 + avg_util*2.5 + (avg_dpd/30.0)*1.8 + del_months*0.4 - avg_pay_ratio*1.5
        ))), 4) >= 0.60 THEN 'Stage 3 (Default)'
        WHEN ROUND(1.0 / (1.0 + EXP(-(
            -3.5 + avg_util*2.5 + (avg_dpd/30.0)*1.8 + del_months*0.4 - avg_pay_ratio*1.5
        ))), 4) >= 0.20 THEN 'Stage 2 (Significant Increase)'
        ELSE                 'Stage 1 (Performing)'
    END AS ifrs9_stage
FROM account_features
ORDER BY pd_score_12m DESC;
