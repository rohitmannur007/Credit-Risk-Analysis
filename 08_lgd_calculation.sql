-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 08_lgd_calculation.sql
-- Description: Loss Given Default (LGD) estimation
--
-- LGD = percentage of exposure that is LOST after a default
-- LGD = (Writeoff Amount - Recovery Amount) / Writeoff Amount
--
-- Example:
--   Writeoff = ₹100,000
--   Recovery = ₹20,000
--   LGD      = (100,000 - 20,000) / 100,000 = 80%
--
-- Banks use LGD for:
--   - IFRS 9 Expected Credit Loss (ECL) models
--   - Basel III capital adequacy calculation
--   - Provisioning requirements
-- ============================================================

-- ============================================================
-- LGD 1: Portfolio-Level LGD
-- ============================================================
SELECT
    COUNT(*)                                                     AS total_writeoffs,
    SUM(writeoff_amount)                                         AS total_written_off,
    SUM(recovery_amount)                                         AS total_recovered,
    SUM(writeoff_amount - recovery_amount)                       AS total_net_loss,
    ROUND(AVG(
        (writeoff_amount - recovery_amount) * 1.0
        / NULLIF(writeoff_amount, 0)
    ), 4)                                                        AS avg_lgd,
    ROUND(
        SUM(writeoff_amount - recovery_amount) * 100.0
        / NULLIF(SUM(writeoff_amount), 0), 2
    )                                                            AS portfolio_lgd_pct,
    -- Recovery Rate = 1 - LGD
    ROUND(
        SUM(recovery_amount) * 100.0
        / NULLIF(SUM(writeoff_amount), 0), 2
    )                                                            AS recovery_rate_pct
FROM writeoffs;

-- ============================================================
-- LGD 2: LGD by Product Type
-- Premium / Platinum cards often have lower LGD (higher recovery)
-- ============================================================
SELECT
    c.product_type,
    COUNT(w.card_id)                                                AS writeoffs,
    SUM(w.writeoff_amount)                                          AS total_written_off,
    SUM(w.recovery_amount)                                          AS total_recovered,
    SUM(w.writeoff_amount - w.recovery_amount)                      AS net_loss,
    ROUND(AVG(
        (w.writeoff_amount - w.recovery_amount) * 1.0
        / NULLIF(w.writeoff_amount, 0)
    ), 4)                                                           AS avg_lgd,
    ROUND(
        SUM(w.recovery_amount) * 100.0
        / NULLIF(SUM(w.writeoff_amount), 0), 2
    )                                                               AS recovery_rate_pct
FROM writeoffs w
JOIN cards c ON w.card_id = c.card_id
GROUP BY c.product_type
ORDER BY avg_lgd DESC;

-- ============================================================
-- LGD 3: LGD by Income Band
-- ============================================================
SELECT
    cu.income_band,
    COUNT(w.card_id)                                                AS writeoffs,
    SUM(w.writeoff_amount)                                          AS total_written_off,
    SUM(w.recovery_amount)                                          AS total_recovered,
    ROUND(AVG(
        (w.writeoff_amount - w.recovery_amount) * 1.0
        / NULLIF(w.writeoff_amount, 0)
    ), 4)                                                           AS avg_lgd,
    ROUND(SUM(w.recovery_amount) * 100.0
          / NULLIF(SUM(w.writeoff_amount), 0), 2)                   AS recovery_rate_pct
FROM writeoffs w
JOIN cards c ON w.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.income_band ORDER BY avg_lgd DESC;

-- ============================================================
-- LGD 4: LGD by Region
-- ============================================================
SELECT
    cu.region,
    COUNT(w.card_id)                                                AS writeoffs,
    SUM(w.writeoff_amount)                                          AS total_written_off,
    SUM(w.recovery_amount)                                          AS total_recovered,
    ROUND(AVG(
        (w.writeoff_amount - w.recovery_amount) * 1.0
        / NULLIF(w.writeoff_amount, 0)
    ), 4)                                                           AS avg_lgd,
    ROUND(SUM(w.recovery_amount) * 100.0
          / NULLIF(SUM(w.writeoff_amount), 0), 2)                   AS recovery_rate_pct
FROM writeoffs w
JOIN cards c ON w.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.region ORDER BY avg_lgd DESC;

-- ============================================================
-- LGD 5: Monthly LGD Trend
-- Track if recovery rate is improving or declining
-- ============================================================
SELECT
    DATE_TRUNC('month', writeoff_date)                             AS writeoff_month,
    COUNT(*)                                                       AS writeoffs,
    SUM(writeoff_amount)                                           AS total_written_off,
    SUM(recovery_amount)                                           AS total_recovered,
    ROUND(AVG(
        (writeoff_amount - recovery_amount) * 1.0
        / NULLIF(writeoff_amount, 0)
    ), 4)                                                          AS avg_lgd,
    ROUND(SUM(recovery_amount) * 100.0
          / NULLIF(SUM(writeoff_amount), 0), 2)                    AS recovery_rate_pct
FROM writeoffs
GROUP BY 1 ORDER BY 1;

-- ============================================================
-- LGD 6: LGD Distribution (Histogram Buckets)
-- ============================================================
SELECT
    CASE
        WHEN (writeoff_amount - recovery_amount) * 1.0 / writeoff_amount < 0.20 THEN '0-20% (Low Loss)'
        WHEN (writeoff_amount - recovery_amount) * 1.0 / writeoff_amount < 0.40 THEN '20-40%'
        WHEN (writeoff_amount - recovery_amount) * 1.0 / writeoff_amount < 0.60 THEN '40-60%'
        WHEN (writeoff_amount - recovery_amount) * 1.0 / writeoff_amount < 0.80 THEN '60-80%'
        ELSE                                                                          '80-100% (High Loss)'
    END AS lgd_band,
    COUNT(*)                                                      AS writeoffs,
    SUM(writeoff_amount)                                          AS total_exposure,
    SUM(writeoff_amount - recovery_amount)                        AS net_loss,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)            AS pct_of_writeoffs
FROM writeoffs
GROUP BY 1 ORDER BY 1;

-- ============================================================
-- LGD 7: Account-Level LGD with Full Detail
-- ============================================================
SELECT
    w.card_id,
    c.product_type,
    cu.region,
    cu.income_band,
    c.credit_limit,
    w.writeoff_amount,
    w.recovery_amount,
    (w.writeoff_amount - w.recovery_amount)                         AS net_loss,
    ROUND(
        (w.writeoff_amount - w.recovery_amount) * 1.0
        / NULLIF(w.writeoff_amount, 0), 4
    )                                                               AS lgd,
    ROUND(w.recovery_amount * 1.0 / NULLIF(w.writeoff_amount, 0), 4) AS recovery_rate,
    w.writeoff_date
FROM writeoffs w
JOIN cards c ON w.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
ORDER BY lgd DESC, net_loss DESC;

-- ============================================================
-- LGD 8: Comparing LGD to Credit Limit (Collateral proxy)
-- Higher limits may have better recovery (more creditworthy)
-- ============================================================
SELECT
    CASE
        WHEN c.credit_limit < 50000   THEN 'Low (<50K)'
        WHEN c.credit_limit < 150000  THEN 'Medium (50K-150K)'
        WHEN c.credit_limit < 400000  THEN 'High (150K-400K)'
        ELSE                               'Premium (400K+)'
    END AS limit_band,
    COUNT(w.card_id)               AS writeoffs,
    ROUND(AVG(c.credit_limit), 0)  AS avg_limit,
    ROUND(AVG(w.writeoff_amount), 0) AS avg_writeoff,
    ROUND(AVG(
        (w.writeoff_amount - w.recovery_amount) * 1.0
        / NULLIF(w.writeoff_amount, 0)
    ), 4)                          AS avg_lgd
FROM writeoffs w
JOIN cards c ON w.card_id = c.card_id
GROUP BY 1 ORDER BY avg_lgd DESC;
