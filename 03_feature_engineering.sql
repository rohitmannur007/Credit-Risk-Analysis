-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 03_feature_engineering.sql
-- Description: Build all risk views & derived features
-- ============================================================

-- ============================================================
-- VIEW 1: vw_credit_utilization
-- Utilization ratio + band per account-month
-- ============================================================
CREATE OR REPLACE VIEW vw_credit_utilization AS
SELECT
    s.card_id,
    c.customer_id,
    s.period_month,
    s.statement_balance,
    s.credit_limit,
    ROUND(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0), 4) AS utilization_ratio,
    CASE
        WHEN s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0) >= 0.9 THEN 'Critical 90%+'
        WHEN s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0) >= 0.7 THEN 'High 70-89%'
        WHEN s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0) >= 0.4 THEN 'Medium 40-69%'
        ELSE                                                                     'Low <40%'
    END AS utilization_band
FROM statements s
JOIN cards c ON s.card_id = c.card_id;

-- ============================================================
-- VIEW 2: vw_payment_behavior
-- Payment classification per account-month
-- ============================================================
CREATE OR REPLACE VIEW vw_payment_behavior AS
SELECT
    card_id,
    period_month,
    statement_balance,
    min_due,
    paid_amount,
    days_past_due,
    dpd_bucket,
    ROUND(paid_amount * 1.0 / NULLIF(statement_balance, 0), 4) AS payment_ratio,
    CASE
        WHEN paid_amount >= statement_balance THEN 'Full Payment'
        WHEN paid_amount >= min_due           THEN 'Min Payment'
        WHEN paid_amount > 0                  THEN 'Partial Payment'
        ELSE                                       'No Payment'
    END AS payment_type,
    (statement_balance - paid_amount) AS revolving_balance
FROM statements;

-- ============================================================
-- VIEW 3: vw_customer_risk_profile
-- Per-customer aggregated risk profile across all months
-- ============================================================
CREATE OR REPLACE VIEW vw_customer_risk_profile AS
WITH agg AS (
    SELECT
        c.card_id,
        cu.customer_id,
        cu.region,
        cu.income_band,
        c.product_type,
        c.credit_limit,
        AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0))   AS avg_utilization,
        MAX(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0))   AS max_utilization,
        MAX(s.days_past_due)                                           AS max_dpd_ever,
        AVG(s.days_past_due)                                           AS avg_dpd,
        SUM(CASE WHEN s.days_past_due >= 30 THEN 1 ELSE 0 END)        AS months_delinquent,
        SUM(CASE WHEN s.days_past_due >= 90 THEN 1 ELSE 0 END)        AS months_default,
        AVG(s.paid_amount * 1.0 / NULLIF(s.statement_balance, 0))    AS avg_payment_ratio,
        AVG(s.statement_balance)                                       AS avg_balance,
        COUNT(DISTINCT s.period_month)                                 AS months_on_book,
        SUM(s.transaction_amount)                                      AS total_transactions
    FROM statements s
    JOIN cards     c  ON s.card_id     = c.card_id
    JOIN customers cu ON c.customer_id = cu.customer_id
    GROUP BY c.card_id, cu.customer_id, cu.region, cu.income_band,
             c.product_type, c.credit_limit
)
SELECT *,
    CASE
        WHEN avg_payment_ratio >= 0.95 THEN 'Transactor'
        WHEN avg_payment_ratio >= 0.50 THEN 'Revolving'
        ELSE                                'Distressed'
    END AS customer_segment,
    ROUND(
          LEAST(avg_utilization, 1.0)            * 40
        + LEAST(avg_dpd / 90.0, 1.0)             * 40
        + (1 - LEAST(avg_payment_ratio, 1.0))    * 20,
    2) AS risk_score
FROM agg;

-- ============================================================
-- VIEW 4: vw_roll_rate_base
-- Month-to-month bucket transition pairs
-- Foundation for roll rate analysis
-- ============================================================
CREATE OR REPLACE VIEW vw_roll_rate_base AS
SELECT
    s1.card_id,
    s1.period_month     AS current_month,
    s1.dpd_bucket       AS current_bucket,
    s2.period_month     AS next_month,
    s2.dpd_bucket       AS next_bucket,
    s1.statement_balance AS current_balance,
    s2.statement_balance AS next_balance
FROM statements s1
JOIN statements s2
    ON  s1.card_id     = s2.card_id
    AND s2.period_month = (
        SELECT MIN(s3.period_month) FROM statements s3
        WHERE s3.card_id = s1.card_id AND s3.period_month > s1.period_month
    );

-- ============================================================
-- VIEW 5: vw_vintage_base
-- Months-on-book tagging for vintage / cohort analysis
-- ============================================================
CREATE OR REPLACE VIEW vw_vintage_base AS
WITH first_seen AS (
    SELECT card_id, MIN(period_month) AS cohort_month
    FROM statements GROUP BY card_id
)
SELECT
    s.card_id,
    f.cohort_month,
    s.period_month,
    -- Months on book (MOB)
    (EXTRACT(YEAR  FROM AGE(s.period_month, f.cohort_month)) * 12 +
     EXTRACT(MONTH FROM AGE(s.period_month, f.cohort_month)))::INT AS mob,
    s.statement_balance,
    s.days_past_due,
    s.dpd_bucket,
    s.credit_limit
FROM statements s
JOIN first_seen f ON s.card_id = f.card_id;

-- ============================================================
-- VIEW 6: vw_early_warning_indicators
-- Flags accounts showing multi-month stress signals
-- ============================================================
CREATE OR REPLACE VIEW vw_early_warning_indicators AS
WITH lagged AS (
    SELECT
        card_id, period_month,
        statement_balance, days_past_due, paid_amount, dpd_bucket,
        LAG(statement_balance) OVER (PARTITION BY card_id ORDER BY period_month) AS prev_balance,
        LAG(days_past_due)     OVER (PARTITION BY card_id ORDER BY period_month) AS prev_dpd,
        LAG(paid_amount)       OVER (PARTITION BY card_id ORDER BY period_month) AS prev_paid,
        LAG(dpd_bucket)        OVER (PARTITION BY card_id ORDER BY period_month) AS prev_bucket
    FROM statements
)
SELECT *,
    CASE
        WHEN days_past_due > prev_dpd
             AND statement_balance > prev_balance
             AND paid_amount < prev_paid           THEN 'TRIPLE WARNING'
        WHEN days_past_due > prev_dpd
             AND statement_balance > prev_balance   THEN 'DOUBLE WARNING'
        WHEN days_past_due > 0 AND prev_dpd = 0     THEN 'NEWLY DELINQUENT'
        WHEN days_past_due = 0 AND prev_dpd > 0     THEN 'CURED'
        ELSE                                             'NORMAL'
    END AS ewi_flag
FROM lagged
WHERE prev_balance IS NOT NULL;
