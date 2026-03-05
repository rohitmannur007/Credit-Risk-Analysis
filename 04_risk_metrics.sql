-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 04_risk_metrics.sql
-- Description: Core portfolio KPIs used in bank reporting
-- ============================================================

-- ============================================================
-- KPI 1: Overall Portfolio Summary Dashboard Card
-- ============================================================
SELECT
    COUNT(DISTINCT c.customer_id)                                                AS total_customers,
    COUNT(DISTINCT s.card_id)                                                    AS total_accounts,
    SUM(s.statement_balance)                                                     AS total_exposure,
    ROUND(AVG(s.statement_balance), 2)                                           AS avg_balance,
    ROUND(AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)), 4)        AS avg_utilization,
    COUNT(CASE WHEN s.days_past_due >= 30 THEN 1 END)                            AS delinquent_accounts,
    COUNT(CASE WHEN s.days_past_due >= 90 THEN 1 END)                            AS default_accounts,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 2)  AS delinquency_rate_pct,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 2)  AS default_rate_pct
FROM statements s
JOIN cards c ON s.card_id = c.card_id;

-- ============================================================
-- KPI 2: Delinquency by DPD Bucket
-- ============================================================
SELECT
    dpd_bucket,
    COUNT(*)                                                        AS account_months,
    COUNT(DISTINCT card_id)                                         AS unique_accounts,
    SUM(statement_balance)                                          AS total_exposure,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)              AS pct_of_portfolio
FROM statements
GROUP BY dpd_bucket
ORDER BY CASE dpd_bucket
    WHEN '0' THEN 1 WHEN '1-29' THEN 2 WHEN '30-59' THEN 3
    WHEN '60-89' THEN 4 WHEN '90+' THEN 5 END;

-- ============================================================
-- KPI 3: Credit Utilization Segmentation
-- ============================================================
SELECT
    CASE
        WHEN statement_balance * 1.0 / NULLIF(s.credit_limit, 0) >= 0.9 THEN 'Critical 90%+'
        WHEN statement_balance * 1.0 / NULLIF(s.credit_limit, 0) >= 0.7 THEN 'High 70-89%'
        WHEN statement_balance * 1.0 / NULLIF(s.credit_limit, 0) >= 0.4 THEN 'Medium 40-69%'
        ELSE                                                                   'Low <40%'
    END AS util_band,
    COUNT(*)                                         AS account_months,
    COUNT(DISTINCT s.card_id)                        AS unique_accounts,
    SUM(s.statement_balance)                         AS exposure,
    ROUND(AVG(s.days_past_due), 2)                   AS avg_dpd
FROM statements s
GROUP BY 1 ORDER BY 1;

-- ============================================================
-- KPI 4: Payment Behavior Distribution
-- ============================================================
SELECT
    CASE
        WHEN paid_amount >= statement_balance THEN 'Full Payment'
        WHEN paid_amount >= min_due           THEN 'Min Payment'
        WHEN paid_amount > 0                  THEN 'Partial Payment'
        ELSE                                       'No Payment'
    END AS payment_type,
    COUNT(*)                                                  AS occurrences,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)        AS pct,
    SUM(statement_balance - paid_amount)                      AS revolving_balance,
    ROUND(AVG(days_past_due), 2)                              AS avg_dpd
FROM statements
GROUP BY 1 ORDER BY occurrences DESC;

-- ============================================================
-- KPI 5: Risk by Region
-- ============================================================
SELECT
    cu.region,
    COUNT(DISTINCT s.card_id)                                                    AS accounts,
    SUM(s.statement_balance)                                                     AS total_exposure,
    ROUND(AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)), 4)        AS avg_utilization,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 2) AS del_rate_pct,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 2) AS default_rate_pct,
    ROUND(AVG(s.paid_amount * 1.0 / NULLIF(s.statement_balance, 0)), 4)         AS avg_payment_ratio
FROM statements s
JOIN cards     c  ON s.card_id     = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.region ORDER BY del_rate_pct DESC;

-- ============================================================
-- KPI 6: Risk by Income Band
-- ============================================================
SELECT
    cu.income_band,
    COUNT(DISTINCT s.card_id)                                                    AS accounts,
    ROUND(AVG(c.credit_limit), 0)                                                AS avg_limit,
    ROUND(AVG(s.statement_balance), 0)                                           AS avg_balance,
    ROUND(AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)), 4)        AS avg_utilization,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 2) AS del_rate_pct,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 2) AS default_rate_pct
FROM statements s
JOIN cards     c  ON s.card_id     = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.income_band ORDER BY del_rate_pct DESC;

-- ============================================================
-- KPI 7: Risk by Product Type
-- ============================================================
SELECT
    c.product_type,
    COUNT(DISTINCT s.card_id)                                                    AS accounts,
    ROUND(AVG(c.credit_limit), 0)                                                AS avg_limit,
    SUM(s.statement_balance)                                                     AS total_exposure,
    ROUND(AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)), 4)        AS avg_utilization,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 2) AS del_rate_pct,
    ROUND(COUNT(CASE WHEN s.days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 2) AS default_rate_pct
FROM statements s
JOIN cards c ON s.card_id = c.card_id
GROUP BY c.product_type ORDER BY del_rate_pct DESC;

-- ============================================================
-- KPI 8: Monthly Delinquency Trend
-- ============================================================
SELECT
    period_month,
    COUNT(*)                                                                        AS total_accounts,
    COUNT(CASE WHEN days_past_due >= 30 THEN 1 END)                                 AS dpd_30plus,
    COUNT(CASE WHEN days_past_due >= 60 THEN 1 END)                                 AS dpd_60plus,
    COUNT(CASE WHEN days_past_due >= 90 THEN 1 END)                                 AS dpd_90plus,
    SUM(statement_balance)                                                           AS total_exposure,
    SUM(CASE WHEN days_past_due >= 30 THEN statement_balance ELSE 0 END)             AS at_risk_exposure,
    ROUND(COUNT(CASE WHEN days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 2)    AS del_rate_pct
FROM statements
GROUP BY period_month ORDER BY period_month;

-- ============================================================
-- KPI 9: Top 50 High-Risk Accounts (Latest Month)
-- ============================================================
WITH latest AS (SELECT MAX(period_month) AS m FROM statements)
SELECT
    s.card_id,
    cu.region,
    cu.income_band,
    c.product_type,
    c.credit_limit,
    s.statement_balance,
    ROUND(s.statement_balance * 1.0 / s.credit_limit, 4)            AS utilization,
    s.days_past_due,
    s.dpd_bucket,
    ROUND(s.paid_amount * 1.0 / NULLIF(s.statement_balance, 0), 4)  AS payment_ratio
FROM statements s
JOIN cards     c  ON s.card_id     = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
JOIN latest       ON s.period_month = latest.m
ORDER BY s.days_past_due DESC, s.statement_balance DESC
LIMIT 50;
