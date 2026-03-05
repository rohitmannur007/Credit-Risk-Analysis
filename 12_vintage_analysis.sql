-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 12_vintage_analysis.sql
-- Description: Vintage / Cohort Analysis
--
-- Vintage analysis tracks a COHORT of accounts originated
-- in the same time period and follows their performance
-- month-by-month as they age.
--
-- Why banks use vintage analysis:
--   1. Compare credit quality across origination vintages
--   2. Detect if newer book is riskier than older book
--   3. Calibrate underwriting criteria
--   4. Predict lifetime loss rates
--   5. IFRS 9 lifetime ECL modelling
--
-- Key axis:
--   X-axis = Months on Book (MOB) — age of account
--   Y-axis = Cumulative Default Rate
--
-- Reading: "Accounts from Jan-2022 vintage had 5% default
--           rate by MOB 12" means 5% had defaulted within
--           their first 12 months.
-- ============================================================

-- ============================================================
-- VINTAGE 1: Monthly Vintage Default Rates
-- Core vintage curve table — use this for Tableau chart
-- ============================================================
SELECT
    v.cohort_month,
    v.mob,
    COUNT(*)                                                              AS accounts,
    COUNT(CASE WHEN v.days_past_due >= 30 THEN 1 END)                     AS delinquent_30plus,
    COUNT(CASE WHEN v.days_past_due >= 90 THEN 1 END)                     AS defaulted,
    SUM(v.statement_balance)                                              AS outstanding_balance,
    ROUND(COUNT(CASE WHEN v.days_past_due >= 30 THEN 1 END) * 100.0
          / NULLIF(COUNT(*), 0), 4)                                       AS delinquency_rate_pct,
    ROUND(COUNT(CASE WHEN v.days_past_due >= 90 THEN 1 END) * 100.0
          / NULLIF(COUNT(*), 0), 4)                                       AS default_rate_pct
FROM vw_vintage_base v
GROUP BY v.cohort_month, v.mob
ORDER BY v.cohort_month, v.mob;

-- ============================================================
-- VINTAGE 2: Cumulative Default Rate by Vintage
-- Shows % of accounts that EVER defaulted by MOB X
-- ============================================================
WITH ever_defaulted AS (
    -- For each account, flag if it EVER went 90+ DPD up to MOB N
    SELECT
        v.card_id,
        v.cohort_month,
        v.mob,
        MAX(CASE WHEN v2.days_past_due >= 90 AND v2.mob <= v.mob THEN 1 ELSE 0 END) AS ever_defaulted_by_mob
    FROM vw_vintage_base v
    JOIN vw_vintage_base v2
        ON v.card_id = v2.card_id AND v2.mob <= v.mob
    GROUP BY v.card_id, v.cohort_month, v.mob
)
SELECT
    cohort_month,
    mob,
    COUNT(*)                                                              AS accounts_at_mob,
    SUM(ever_defaulted_by_mob)                                            AS cumulative_defaults,
    ROUND(SUM(ever_defaulted_by_mob) * 100.0 / COUNT(*), 4)              AS cumulative_default_rate_pct
FROM ever_defaulted
GROUP BY cohort_month, mob
ORDER BY cohort_month, mob;

-- ============================================================
-- VINTAGE 3: Vintage Comparison at Key MOBs (6/12/18/24)
-- Side-by-side comparison of vintages at fixed ages
-- ============================================================
SELECT
    cohort_month,
    MAX(CASE WHEN mob = 6  THEN ROUND(COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 4) END) AS default_rate_mob6,
    MAX(CASE WHEN mob = 12 THEN ROUND(COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 4) END) AS default_rate_mob12,
    MAX(CASE WHEN mob = 18 THEN ROUND(COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 4) END) AS default_rate_mob18,
    MAX(CASE WHEN mob = 24 THEN ROUND(COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 4) END) AS default_rate_mob24
FROM vw_vintage_base
GROUP BY cohort_month
ORDER BY cohort_month;

-- ============================================================
-- VINTAGE 4: Vintage Loss Rate (Balance-Weighted)
-- How much of original balance was written off by each vintage
-- ============================================================
WITH cohort_original_balance AS (
    SELECT cohort_month, SUM(statement_balance) AS original_balance
    FROM vw_vintage_base WHERE mob = 1
    GROUP BY cohort_month
),
cohort_writeoffs AS (
    SELECT
        f.cohort_month,
        SUM(w.writeoff_amount)   AS written_off,
        SUM(w.recovery_amount)   AS recovered,
        SUM(w.writeoff_amount - w.recovery_amount) AS net_loss
    FROM writeoffs w
    JOIN (SELECT card_id, cohort_month FROM vw_vintage_base GROUP BY card_id, cohort_month) f
        ON w.card_id = f.card_id
    GROUP BY f.cohort_month
)
SELECT
    ob.cohort_month,
    ob.original_balance,
    COALESCE(cw.written_off, 0)  AS written_off,
    COALESCE(cw.recovered, 0)    AS recovered,
    COALESCE(cw.net_loss, 0)     AS net_loss,
    ROUND(COALESCE(cw.net_loss, 0) * 100.0 / NULLIF(ob.original_balance, 0), 4) AS net_loss_rate_pct
FROM cohort_original_balance ob
LEFT JOIN cohort_writeoffs cw ON ob.cohort_month = cw.cohort_month
ORDER BY ob.cohort_month;

-- ============================================================
-- VINTAGE 5: Vintage Delinquency Curves (by Income Band)
-- Shows if credit quality differs by income segment
-- ============================================================
SELECT
    cu.income_band,
    v.cohort_month,
    v.mob,
    COUNT(*) AS accounts,
    ROUND(COUNT(CASE WHEN v.days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 4) AS del_rate_pct,
    ROUND(COUNT(CASE WHEN v.days_past_due >= 90 THEN 1 END) * 100.0 / COUNT(*), 4) AS default_rate_pct
FROM vw_vintage_base v
JOIN cards c ON v.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.income_band, v.cohort_month, v.mob
ORDER BY cu.income_band, v.cohort_month, v.mob;

-- ============================================================
-- VINTAGE 6: Vintage Performance Scorecard (Annual Summary)
-- For management / board reporting
-- ============================================================
SELECT
    DATE_TRUNC('year', cohort_month)::DATE   AS vintage_year,
    COUNT(DISTINCT card_id)                   AS total_accounts,
    COUNT(DISTINCT cohort_month)              AS months_in_vintage,
    ROUND(AVG(statement_balance), 0)          AS avg_balance,
    ROUND(AVG(CASE WHEN days_past_due >= 30 THEN 1.0 ELSE 0 END) * 100, 4) AS avg_del_rate_pct,
    ROUND(AVG(CASE WHEN days_past_due >= 90 THEN 1.0 ELSE 0 END) * 100, 4) AS avg_default_rate_pct,
    MAX(days_past_due)                        AS peak_dpd_observed
FROM vw_vintage_base
GROUP BY DATE_TRUNC('year', cohort_month)
ORDER BY vintage_year;

-- ============================================================
-- VINTAGE 7: Early Life Delinquency (First 6 MOBs)
-- Strong predictor of lifetime portfolio performance
-- Underwriting quality indicator
-- ============================================================
WITH early_life AS (
    SELECT
        cohort_month,
        card_id,
        MAX(CASE WHEN mob <= 6 THEN days_past_due ELSE 0 END) AS max_early_dpd,
        SUM(CASE WHEN mob <= 6 AND days_past_due >= 30 THEN 1 ELSE 0 END) AS early_del_months
    FROM vw_vintage_base
    GROUP BY cohort_month, card_id
)
SELECT
    cohort_month,
    COUNT(*) AS total_accounts,
    COUNT(CASE WHEN max_early_dpd >= 30 THEN 1 END) AS early_delinquent,
    COUNT(CASE WHEN max_early_dpd >= 90 THEN 1 END) AS early_default,
    ROUND(COUNT(CASE WHEN max_early_dpd >= 30 THEN 1 END) * 100.0 / COUNT(*), 4) AS early_del_rate_pct,
    ROUND(COUNT(CASE WHEN max_early_dpd >= 90 THEN 1 END) * 100.0 / COUNT(*), 4) AS early_default_rate_pct
FROM early_life
GROUP BY cohort_month
ORDER BY cohort_month;
