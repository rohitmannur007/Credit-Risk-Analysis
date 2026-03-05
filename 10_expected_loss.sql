-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 10_expected_loss.sql
-- Description: Expected Loss (EL) = PD × LGD × EAD
--
-- Expected Loss (EL) is the CORE output of credit risk models.
-- Banks use EL for:
--   1. Loan Loss Provisioning (reserves held against losses)
--   2. IFRS 9 Stage Classification (1 / 2 / 3)
--   3. Risk-Adjusted Return on Capital (RAROC)
--   4. Pricing of credit products
--   5. Capital adequacy (Basel III)
--
-- EL Formula:
--   EL = PD × LGD × EAD
--
-- Where:
--   PD  = Probability of Default (from 07_pd_calculation.sql)
--   LGD = Loss Given Default     (from 08_lgd_calculation.sql)
--   EAD = Exposure at Default    (from 09_ead_calculation.sql)
-- ============================================================

-- ============================================================
-- STEP 1: Pre-compute Portfolio-Level Parameters
-- ============================================================

-- Portfolio LGD (from writeoffs table)
WITH portfolio_lgd AS (
    SELECT ROUND(AVG(
        (writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)
    ), 4) AS lgd
    FROM writeoffs
),

-- ============================================================
-- STEP 2: Account-Level EL Calculation
-- ============================================================
account_risk AS (
    SELECT
        s.card_id,
        c.customer_id,
        c.product_type,
        cu.region,
        cu.income_band,
        s.credit_limit,
        AVG(s.statement_balance)                                                  AS avg_balance,
        -- EAD (latest month, 75% CCF)
        MAX(CASE WHEN s.period_month = (SELECT MAX(period_month) FROM statements)
            THEN s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance)
            END)                                                                  AS ead,
        -- PD Score (behavioral estimate, logistic approximation)
        ROUND(1.0 / (1.0 + EXP(-(
            -3.5
            + AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)) * 2.5
            + (AVG(s.days_past_due) / 30.0) * 1.8
            + SUM(CASE WHEN s.days_past_due >= 30 THEN 1 ELSE 0 END) * 0.4
            - AVG(s.paid_amount * 1.0 / NULLIF(s.statement_balance, 0)) * 1.5
        ))), 4)                                                                   AS pd_score,
        MAX(s.days_past_due)                                                      AS max_dpd
    FROM statements s
    JOIN cards c ON s.card_id = c.card_id
    JOIN customers cu ON c.customer_id = cu.customer_id
    GROUP BY s.card_id, c.customer_id, c.product_type, cu.region, cu.income_band, s.credit_limit
)
SELECT
    ar.card_id,
    ar.customer_id,
    ar.product_type,
    ar.region,
    ar.income_band,
    ar.credit_limit,
    ROUND(ar.avg_balance, 0)        AS avg_balance,
    ROUND(ar.ead, 0)                AS ead,
    ar.pd_score                     AS pd,
    pl.lgd                          AS lgd,
    -- Expected Loss = PD × LGD × EAD
    ROUND(ar.pd_score * pl.lgd * ar.ead, 2) AS expected_loss,
    -- EL as % of EAD (expected loss rate)
    ROUND(ar.pd_score * pl.lgd * 100.0, 4)  AS el_rate_pct,
    ar.max_dpd,
    -- IFRS 9 Stage assignment
    CASE
        WHEN ar.max_dpd >= 90    THEN 'Stage 3 (Credit-Impaired)'
        WHEN ar.pd_score >= 0.20 THEN 'Stage 2 (Significant Increase in CR)'
        ELSE                          'Stage 1 (Performing)'
    END AS ifrs9_stage
FROM account_risk ar
CROSS JOIN portfolio_lgd pl
ORDER BY expected_loss DESC;

-- ============================================================
-- EL 2: Portfolio-Level Expected Loss Summary
-- ============================================================
WITH portfolio_lgd AS (
    SELECT ROUND(AVG(
        (writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)
    ), 4) AS lgd FROM writeoffs
),
account_risk AS (
    SELECT
        s.card_id,
        MAX(CASE WHEN s.period_month = (SELECT MAX(p) FROM (SELECT MAX(period_month) AS p FROM statements) t)
            THEN s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance) END) AS ead,
        ROUND(1.0 / (1.0 + EXP(-(
            -3.5
            + AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)) * 2.5
            + (AVG(s.days_past_due) / 30.0) * 1.8
            + SUM(CASE WHEN s.days_past_due >= 30 THEN 1 ELSE 0 END) * 0.4
            - AVG(s.paid_amount * 1.0 / NULLIF(s.statement_balance, 0)) * 1.5
        ))), 4) AS pd_score,
        MAX(s.days_past_due) AS max_dpd
    FROM statements s
    GROUP BY s.card_id
)
SELECT
    SUM(ar.ead)                                          AS total_ead,
    pl.lgd                                               AS portfolio_lgd,
    ROUND(AVG(ar.pd_score), 4)                           AS avg_pd,
    ROUND(SUM(ar.pd_score * pl.lgd * ar.ead), 2)         AS total_expected_loss,
    ROUND(SUM(ar.pd_score * pl.lgd * ar.ead)
          * 100.0 / NULLIF(SUM(ar.ead), 0), 4)           AS el_rate_pct,
    COUNT(CASE WHEN ar.max_dpd >= 90    THEN 1 END)       AS stage_3_accounts,
    COUNT(CASE WHEN ar.pd_score >= 0.20
                AND ar.max_dpd < 90     THEN 1 END)       AS stage_2_accounts,
    COUNT(CASE WHEN ar.pd_score < 0.20  THEN 1 END)       AS stage_1_accounts
FROM account_risk ar
CROSS JOIN portfolio_lgd pl;

-- ============================================================
-- EL 3: Expected Loss by IFRS 9 Stage
-- ============================================================
WITH portfolio_lgd AS (
    SELECT ROUND(AVG(
        (writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)
    ), 4) AS lgd FROM writeoffs
),
account_risk AS (
    SELECT
        s.card_id,
        MAX(CASE WHEN s.period_month = (SELECT MAX(period_month) FROM statements)
            THEN s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance) END) AS ead,
        ROUND(1.0 / (1.0 + EXP(-(
            -3.5
            + AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)) * 2.5
            + (AVG(s.days_past_due) / 30.0) * 1.8
            + SUM(CASE WHEN s.days_past_due >= 30 THEN 1 ELSE 0 END) * 0.4
            - AVG(s.paid_amount * 1.0 / NULLIF(s.statement_balance, 0)) * 1.5
        ))), 4) AS pd_score,
        MAX(s.days_past_due) AS max_dpd
    FROM statements s GROUP BY s.card_id
)
SELECT
    CASE
        WHEN ar.max_dpd >= 90    THEN 'Stage 3'
        WHEN ar.pd_score >= 0.20 THEN 'Stage 2'
        ELSE                          'Stage 1'
    END AS ifrs9_stage,
    COUNT(ar.card_id)                                     AS accounts,
    ROUND(AVG(ar.pd_score), 4)                            AS avg_pd,
    pl.lgd                                                AS lgd,
    ROUND(SUM(ar.ead), 0)                                 AS total_ead,
    ROUND(SUM(ar.pd_score * pl.lgd * ar.ead), 2)          AS total_expected_loss,
    ROUND(SUM(ar.pd_score * pl.lgd * ar.ead)
          * 100.0 / NULLIF(SUM(ar.ead), 0), 4)            AS el_rate_pct
FROM account_risk ar
CROSS JOIN portfolio_lgd pl
GROUP BY 1, pl.lgd ORDER BY 1;

-- ============================================================
-- EL 4: Expected Loss by Product Type
-- ============================================================
WITH portfolio_lgd AS (
    SELECT ROUND(AVG(
        (writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)
    ), 4) AS lgd FROM writeoffs
),
account_risk AS (
    SELECT
        s.card_id,
        c.product_type,
        MAX(CASE WHEN s.period_month = (SELECT MAX(period_month) FROM statements)
            THEN s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance) END) AS ead,
        ROUND(1.0 / (1.0 + EXP(-(
            -3.5
            + AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)) * 2.5
            + (AVG(s.days_past_due) / 30.0) * 1.8
            + SUM(CASE WHEN s.days_past_due >= 30 THEN 1 ELSE 0 END) * 0.4
            - AVG(s.paid_amount * 1.0 / NULLIF(s.statement_balance, 0)) * 1.5
        ))), 4) AS pd_score
    FROM statements s JOIN cards c ON s.card_id = c.card_id
    GROUP BY s.card_id, c.product_type
)
SELECT
    ar.product_type,
    COUNT(ar.card_id)                                     AS accounts,
    ROUND(AVG(ar.pd_score), 4)                            AS avg_pd,
    pl.lgd                                                AS lgd,
    ROUND(SUM(ar.ead), 0)                                 AS total_ead,
    ROUND(SUM(ar.pd_score * pl.lgd * ar.ead), 2)          AS total_expected_loss,
    ROUND(AVG(ar.pd_score * pl.lgd), 4)                   AS avg_el_rate
FROM account_risk ar
CROSS JOIN portfolio_lgd pl
GROUP BY ar.product_type, pl.lgd
ORDER BY total_expected_loss DESC;

-- ============================================================
-- EL 5: Monthly ECL Reserve Requirement
-- How much provision to set aside each month
-- ============================================================
WITH portfolio_lgd AS (
    SELECT ROUND(AVG(
        (writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)
    ), 4) AS lgd FROM writeoffs
),
monthly_ead AS (
    SELECT
        s.period_month,
        SUM(s.statement_balance + 0.75 * (s.credit_limit - s.statement_balance)) AS total_ead,
        ROUND(COUNT(CASE WHEN s.days_past_due >= 90 THEN 1 END) * 1.0 / COUNT(*), 4) AS period_pd
    FROM statements s GROUP BY s.period_month
)
SELECT
    m.period_month,
    ROUND(m.total_ead, 0)                                               AS total_ead,
    m.period_pd                                                         AS pd,
    pl.lgd                                                              AS lgd,
    ROUND(m.period_pd * pl.lgd * m.total_ead, 2)                        AS ecl_provision,
    ROUND(m.period_pd * pl.lgd * 100.0, 4)                              AS provision_rate_pct
FROM monthly_ead m
CROSS JOIN portfolio_lgd pl
ORDER BY m.period_month;
