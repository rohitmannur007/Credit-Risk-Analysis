-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 05_delinquency_analysis.sql
-- Description: Delinquency trends, cure rates, EWI signals
-- ============================================================

-- ============================================================
-- ANALYSIS 1: Monthly Delinquency Trend with MoM Change
-- ============================================================
WITH monthly AS (
    SELECT
        period_month,
        COUNT(*) AS total,
        COUNT(CASE WHEN days_past_due >= 30 THEN 1 END) AS delinquent,
        COUNT(CASE WHEN days_past_due >= 60 THEN 1 END) AS dpd_60,
        COUNT(CASE WHEN days_past_due >= 90 THEN 1 END) AS dpd_90,
        SUM(statement_balance)                           AS exposure
    FROM statements GROUP BY period_month
)
SELECT
    period_month,
    total,
    delinquent,
    exposure,
    ROUND(delinquent * 100.0 / total, 2) AS del_rate_pct,
    ROUND(dpd_60     * 100.0 / total, 2) AS dpd60_rate_pct,
    ROUND(dpd_90     * 100.0 / total, 2) AS dpd90_rate_pct,
    ROUND(delinquent * 100.0 / total, 2)
        - LAG(ROUND(delinquent * 100.0 / total, 2))
          OVER (ORDER BY period_month)   AS mom_change_pct
FROM monthly
ORDER BY period_month;

-- ============================================================
-- ANALYSIS 2: Cure Rate by DPD Bucket
-- Cure = account moves from delinquent back to bucket "0"
-- ============================================================
SELECT
    current_bucket,
    COUNT(*)                                                                AS total_transitions,
    COUNT(CASE WHEN next_bucket = '0' THEN 1 END)                           AS cured,
    ROUND(COUNT(CASE WHEN next_bucket = '0' THEN 1 END) * 100.0 / COUNT(*), 2) AS cure_rate_pct,
    ROUND(COUNT(CASE WHEN next_bucket > current_bucket THEN 1 END) * 100.0
          / COUNT(*), 2)                                                    AS worsening_rate_pct
FROM vw_roll_rate_base
WHERE current_bucket IN ('1-29','30-59','60-89','90+')
GROUP BY current_bucket
ORDER BY CASE current_bucket
    WHEN '1-29' THEN 1 WHEN '30-59' THEN 2
    WHEN '60-89' THEN 3 WHEN '90+' THEN 4 END;

-- ============================================================
-- ANALYSIS 3: Early Warning Indicator Summary
-- ============================================================
SELECT
    ewi_flag,
    COUNT(*)                                                   AS occurrences,
    COUNT(DISTINCT card_id)                                    AS unique_accounts,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)         AS pct,
    ROUND(AVG(days_past_due), 2)                               AS avg_current_dpd
FROM vw_early_warning_indicators
GROUP BY ewi_flag
ORDER BY occurrences DESC;

-- ============================================================
-- ANALYSIS 4: Consecutive Delinquency Detection
-- ============================================================
WITH flags AS (
    SELECT card_id, period_month,
           CASE WHEN days_past_due >= 30 THEN 1 ELSE 0 END AS is_del
    FROM statements
),
grps AS (
    SELECT card_id, period_month, is_del,
           ROW_NUMBER() OVER (PARTITION BY card_id ORDER BY period_month)
           - ROW_NUMBER() OVER (PARTITION BY card_id, is_del ORDER BY period_month) AS grp
    FROM flags
),
streaks AS (
    SELECT card_id, grp, SUM(is_del) AS streak
    FROM grps WHERE is_del = 1
    GROUP BY card_id, grp
)
SELECT card_id, MAX(streak) AS max_consecutive_delinquent_months
FROM streaks
GROUP BY card_id
HAVING MAX(streak) >= 3
ORDER BY max_consecutive_delinquent_months DESC
LIMIT 100;

-- ============================================================
-- ANALYSIS 5: Balance Migration (Month-over-Month Exposure)
-- ============================================================
WITH buckets AS (
    SELECT
        period_month,
        SUM(CASE WHEN dpd_bucket = '0'     THEN statement_balance ELSE 0 END) AS current_bal,
        SUM(CASE WHEN dpd_bucket = '1-29'  THEN statement_balance ELSE 0 END) AS b_1_29,
        SUM(CASE WHEN dpd_bucket = '30-59' THEN statement_balance ELSE 0 END) AS b_30_59,
        SUM(CASE WHEN dpd_bucket = '60-89' THEN statement_balance ELSE 0 END) AS b_60_89,
        SUM(CASE WHEN dpd_bucket = '90+'   THEN statement_balance ELSE 0 END) AS b_90_plus
    FROM statements GROUP BY period_month
)
SELECT
    period_month,
    current_bal,
    b_1_29,
    b_30_59,
    b_60_89,
    b_90_plus,
    (b_30_59 + b_60_89 + b_90_plus) AS total_delinquent_bal,
    ROUND((b_30_59 + b_60_89 + b_90_plus) * 100.0
          / NULLIF(current_bal + b_1_29 + b_30_59 + b_60_89 + b_90_plus, 0), 2) AS delinquent_bal_pct
FROM buckets ORDER BY period_month;

-- ============================================================
-- ANALYSIS 6: First-Payment Default (FPD) Detection
-- Very high-risk signal used in origination scoring
-- ============================================================
WITH mob_tagged AS (
    SELECT card_id, period_month, days_past_due,
           ROW_NUMBER() OVER (PARTITION BY card_id ORDER BY period_month) AS mob
    FROM statements
)
SELECT
    card_id,
    MAX(CASE WHEN mob <= 3 THEN days_past_due ELSE 0 END) AS max_early_dpd,
    SUM(CASE WHEN mob <= 3 AND days_past_due >= 30 THEN 1 ELSE 0 END) AS early_delinquent_months
FROM mob_tagged
GROUP BY card_id
HAVING SUM(CASE WHEN mob <= 3 AND days_past_due >= 30 THEN 1 ELSE 0 END) > 0
ORDER BY max_early_dpd DESC
LIMIT 200;
