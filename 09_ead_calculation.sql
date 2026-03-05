-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 09_ead_calculation.sql
-- Description: Exposure at Default (EAD) estimation
--
-- EAD = total exposure a bank faces at the time of default
--
-- For credit cards (revolving credit), EAD is NOT just the
-- current balance. The borrower may draw down more of their
-- available limit before defaulting.
--
-- Formula:
--   EAD = Current Balance + (CCF × Unused Limit)
--
-- Where:
--   CCF (Credit Conversion Factor) = 0.75
--   Unused Limit = Credit Limit - Current Balance
--
-- CCF of 75% means we assume the borrower will use 75% of
-- remaining available credit before defaulting.
-- (Basel III standard CCF for undrawn revolving credit = 0.75)
-- ============================================================

-- ============================================================
-- EAD 1: Account-Level EAD (Latest Month)
-- ============================================================
WITH latest AS (SELECT MAX(period_month) AS m FROM statements)
SELECT
    s.card_id,
    c.customer_id,
    c.product_type,
    s.credit_limit,
    s.statement_balance                                                    AS current_balance,
    (s.credit_limit - s.statement_balance)                                 AS unused_limit,
    ROUND(s.statement_balance * 1.0 / s.credit_limit, 4)                  AS current_utilization,
    -- EAD with 75% CCF (Basel III standard)
    s.statement_balance + ROUND(0.75 * (s.credit_limit - s.statement_balance), 0) AS ead_ccf_75,
    -- Conservative EAD with 100% CCF (worst case)
    s.credit_limit                                                          AS ead_ccf_100,
    -- Optimistic EAD with 50% CCF
    s.statement_balance + ROUND(0.50 * (s.credit_limit - s.statement_balance), 0) AS ead_ccf_50
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN latest   ON s.period_month = latest.m
ORDER BY ead_ccf_75 DESC;

-- ============================================================
-- EAD 2: Portfolio-Level EAD Summary
-- ============================================================
WITH latest AS (SELECT MAX(period_month) AS m FROM statements)
SELECT
    COUNT(DISTINCT s.card_id)                                              AS total_accounts,
    SUM(s.statement_balance)                                               AS total_current_balance,
    SUM(s.credit_limit - s.statement_balance)                              AS total_unused_limit,
    -- EAD at 75% CCF
    SUM(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance)) AS portfolio_ead_75,
    -- EAD at 100% CCF (maximum exposure)
    SUM(s.credit_limit)                                                    AS portfolio_ead_100,
    -- CCF uplift factor
    ROUND(
        SUM(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance))
        / NULLIF(SUM(s.statement_balance), 0), 4
    )                                                                      AS ead_uplift_factor
FROM statements s
JOIN latest ON s.period_month = latest.m;

-- ============================================================
-- EAD 3: EAD by Product Type
-- ============================================================
WITH latest AS (SELECT MAX(period_month) AS m FROM statements)
SELECT
    c.product_type,
    COUNT(DISTINCT s.card_id)                                              AS accounts,
    ROUND(AVG(s.credit_limit), 0)                                          AS avg_credit_limit,
    ROUND(AVG(s.statement_balance), 0)                                     AS avg_current_balance,
    ROUND(AVG(s.statement_balance * 1.0 / s.credit_limit), 4)             AS avg_utilization,
    -- Average EAD per account at 75% CCF
    ROUND(AVG(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance)), 0) AS avg_ead,
    -- Total portfolio EAD
    SUM(ROUND(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance), 0)) AS total_ead
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN latest ON s.period_month = latest.m
GROUP BY c.product_type
ORDER BY total_ead DESC;

-- ============================================================
-- EAD 4: EAD by Income Band
-- ============================================================
WITH latest AS (SELECT MAX(period_month) AS m FROM statements)
SELECT
    cu.income_band,
    COUNT(DISTINCT s.card_id)                                              AS accounts,
    ROUND(AVG(c.credit_limit), 0)                                          AS avg_limit,
    ROUND(AVG(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance)), 0) AS avg_ead,
    SUM(ROUND(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance), 0)) AS total_ead,
    -- Unused limit exposure (what borrowers could still draw)
    SUM(s.credit_limit - s.statement_balance)                              AS total_unused_limit,
    ROUND(SUM(s.credit_limit - s.statement_balance) * 100.0
          / NULLIF(SUM(s.credit_limit), 0), 2)                             AS unused_limit_pct
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
JOIN latest ON s.period_month = latest.m
GROUP BY cu.income_band ORDER BY total_ead DESC;

-- ============================================================
-- EAD 5: EAD by Region
-- ============================================================
WITH latest AS (SELECT MAX(period_month) AS m FROM statements)
SELECT
    cu.region,
    COUNT(DISTINCT s.card_id)                                              AS accounts,
    SUM(s.statement_balance)                                               AS current_exposure,
    SUM(ROUND(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance), 0)) AS total_ead,
    SUM(s.credit_limit)                                                    AS max_possible_ead,
    ROUND(
        SUM(ROUND(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance), 0))
        * 100.0 / NULLIF(SUM(s.credit_limit), 0), 2
    )                                                                      AS ead_as_pct_of_max
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
JOIN latest ON s.period_month = latest.m
GROUP BY cu.region ORDER BY total_ead DESC;

-- ============================================================
-- EAD 6: EAD Sensitivity — Impact of CCF Assumption Change
-- Shows how much EAD changes with different CCF assumptions
-- ============================================================
WITH latest AS (SELECT MAX(period_month) AS m FROM statements)
SELECT
    'CCF = 0%  (Balance Only)'   AS ccf_scenario,
    SUM(s.statement_balance)     AS portfolio_ead,
    0.00                         AS ccf_assumption
FROM statements s JOIN latest ON s.period_month = latest.m

UNION ALL

SELECT 'CCF = 25%',
    SUM(s.statement_balance + 0.25 * (s.credit_limit - s.statement_balance)), 0.25
FROM statements s JOIN latest ON s.period_month = latest.m

UNION ALL

SELECT 'CCF = 50%',
    SUM(s.statement_balance + 0.50 * (s.credit_limit - s.statement_balance)), 0.50
FROM statements s JOIN latest ON s.period_month = latest.m

UNION ALL

SELECT 'CCF = 75% (Basel III)',
    SUM(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance)), 0.75
FROM statements s JOIN latest ON s.period_month = latest.m

UNION ALL

SELECT 'CCF = 100% (Full Limit)',
    SUM(s.credit_limit), 1.00
FROM statements s JOIN latest ON s.period_month = latest.m

ORDER BY ccf_assumption;

-- ============================================================
-- EAD 7: Monthly EAD Trend (Portfolio)
-- Tracks how total exposure at default evolves over time
-- ============================================================
SELECT
    period_month,
    SUM(statement_balance)                                                  AS current_balance,
    SUM(credit_limit)                                                       AS total_credit_limit,
    SUM(statement_balance + 0.75 * (credit_limit - statement_balance))     AS ead_75_ccf,
    ROUND(
        SUM(statement_balance + 0.75 * (credit_limit - statement_balance))
        * 100.0 / NULLIF(SUM(credit_limit), 0), 2
    )                                                                       AS ead_utilization_pct
FROM statements
GROUP BY period_month ORDER BY period_month;
