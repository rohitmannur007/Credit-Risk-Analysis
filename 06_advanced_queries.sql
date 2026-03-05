-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 06_advanced_queries.sql
-- Description: 15 advanced bank-level SQL queries
-- ============================================================

-- QUERY 1: Running Total Portfolio Exposure
SELECT period_month,
       SUM(statement_balance) AS monthly_exposure,
       SUM(SUM(statement_balance)) OVER (ORDER BY period_month) AS cumulative_exposure
FROM statements GROUP BY period_month ORDER BY period_month;

-- ─────────────────────────────────────────────────────────────
-- QUERY 2: MoM Delinquency Change in Basis Points
WITH m AS (
    SELECT period_month,
           ROUND(COUNT(CASE WHEN days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 4) AS del_rate
    FROM statements GROUP BY period_month
)
SELECT period_month, del_rate,
       LAG(del_rate) OVER (ORDER BY period_month) AS prev_rate,
       ROUND((del_rate - LAG(del_rate) OVER (ORDER BY period_month)) * 100, 2) AS change_bps
FROM m ORDER BY period_month;

-- ─────────────────────────────────────────────────────────────
-- QUERY 3: 3-Month Rolling Average Utilization per Account
SELECT card_id, period_month,
       ROUND(statement_balance * 1.0 / NULLIF(credit_limit, 0), 4) AS utilization,
       ROUND(AVG(statement_balance * 1.0 / NULLIF(credit_limit, 0))
             OVER (PARTITION BY card_id ORDER BY period_month
                   ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 4) AS util_3mo_avg
FROM statements ORDER BY card_id, period_month;

-- ─────────────────────────────────────────────────────────────
-- QUERY 4: RFM Risk Scoring (Recency-Frequency-Monetary)
WITH rfm AS (
    SELECT card_id,
           MAX(CASE WHEN days_past_due >= 30 THEN period_month END) AS last_delinquent_month,
           COUNT(CASE WHEN days_past_due >= 30 THEN 1 END)          AS frequency,
           AVG(statement_balance - paid_amount)                      AS avg_revolving_bal
    FROM statements GROUP BY card_id
)
SELECT card_id, last_delinquent_month, frequency,
       ROUND(avg_revolving_bal, 2) AS avg_revolving_bal,
       NTILE(5) OVER (ORDER BY frequency DESC)        AS freq_quintile,
       NTILE(5) OVER (ORDER BY avg_revolving_bal DESC) AS monetary_quintile
FROM rfm ORDER BY frequency DESC, avg_revolving_bal DESC;

-- ─────────────────────────────────────────────────────────────
-- QUERY 5: Payment Gap Analysis (Below Min Due)
SELECT cu.region, cu.income_band,
       COUNT(*) AS statements,
       ROUND(AVG(GREATEST(min_due - paid_amount, 0)), 2) AS avg_payment_gap,
       COUNT(CASE WHEN paid_amount < min_due THEN 1 END) AS below_min_count,
       ROUND(COUNT(CASE WHEN paid_amount < min_due THEN 1 END) * 100.0 / COUNT(*), 2) AS below_min_pct
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.region, cu.income_band ORDER BY below_min_pct DESC;

-- ─────────────────────────────────────────────────────────────
-- QUERY 6: Stress Test — 25% Balance Spike Scenario
SELECT period_month,
       SUM(statement_balance)           AS current_exposure,
       SUM(statement_balance * 1.25)    AS stressed_exposure_25pct,
       ROUND(COUNT(CASE WHEN days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*), 2) AS current_del_rate,
       ROUND(COUNT(CASE WHEN days_past_due >= 30 THEN 1 END) * 100.0 / COUNT(*) * 1.30, 2) AS stressed_del_rate
FROM statements GROUP BY period_month ORDER BY period_month;

-- ─────────────────────────────────────────────────────────────
-- QUERY 7: Portfolio Concentration Risk (Top 100 Accounts)
SELECT cu.customer_id, cu.region, c.product_type,
       SUM(s.statement_balance) AS total_balance,
       MAX(s.days_past_due)     AS max_dpd,
       ROUND(SUM(s.statement_balance) * 100.0
             / (SELECT SUM(statement_balance) FROM statements), 6) AS pct_of_portfolio
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.customer_id, cu.region, c.product_type
ORDER BY total_balance DESC LIMIT 100;

-- ─────────────────────────────────────────────────────────────
-- QUERY 8: Cohort Retention Rate
WITH cohort AS (
    SELECT card_id, MIN(period_month) AS cohort_month FROM statements GROUP BY card_id
),
activity AS (
    SELECT c.cohort_month, s.period_month, COUNT(DISTINCT s.card_id) AS active
    FROM statements s JOIN cohort c ON s.card_id = c.card_id
    GROUP BY c.cohort_month, s.period_month
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS initial_size FROM cohort GROUP BY cohort_month
)
SELECT a.cohort_month, a.period_month, sz.initial_size, a.active,
       ROUND(a.active * 100.0 / sz.initial_size, 2) AS retention_pct
FROM activity a JOIN sizes sz ON a.cohort_month = sz.cohort_month
ORDER BY a.cohort_month, a.period_month;

-- ─────────────────────────────────────────────────────────────
-- QUERY 9: Collections Efficiency (Recovery Rate Month-After)
WITH delinquent_base AS (
    SELECT s1.card_id, s1.period_month, s1.statement_balance,
           s1.days_past_due, s2.paid_amount AS recovery_next_month
    FROM statements s1
    LEFT JOIN statements s2
        ON s1.card_id = s2.card_id
        AND s2.period_month = (
            SELECT MIN(s3.period_month) FROM statements s3
            WHERE s3.card_id = s1.card_id AND s3.period_month > s1.period_month
        )
    WHERE s1.days_past_due >= 30
)
SELECT period_month,
       COUNT(*) AS delinquent_accounts,
       SUM(statement_balance) AS at_risk_balance,
       SUM(recovery_next_month) AS recovered,
       ROUND(SUM(recovery_next_month) * 100.0 / NULLIF(SUM(statement_balance),0), 2) AS recovery_rate_pct
FROM delinquent_base
GROUP BY period_month ORDER BY period_month;

-- ─────────────────────────────────────────────────────────────
-- QUERY 10: Account-Level Risk Decile Ranking
SELECT card_id, credit_limit,
       ROUND(AVG(statement_balance * 1.0 / credit_limit), 4)              AS avg_util,
       ROUND(AVG(days_past_due), 2)                                         AS avg_dpd,
       ROUND(AVG(paid_amount * 1.0 / NULLIF(statement_balance, 0)), 4)    AS avg_pay_ratio,
       ROUND(AVG(statement_balance * 1.0 / credit_limit) * 40
             + (AVG(days_past_due) / 90.0) * 40
             + (1 - AVG(LEAST(paid_amount * 1.0 / NULLIF(statement_balance,0),1))) * 20, 2) AS risk_score,
       NTILE(10) OVER (
           ORDER BY AVG(statement_balance * 1.0 / credit_limit) * 40
                  + (AVG(days_past_due) / 90.0) * 40
                  + (1 - AVG(LEAST(paid_amount * 1.0 / NULLIF(statement_balance,0),1))) * 20 DESC
       ) AS risk_decile
FROM statements
GROUP BY card_id, credit_limit
ORDER BY risk_score DESC;

-- ─────────────────────────────────────────────────────────────
-- QUERY 11: Segment-Level LGD Proxy
SELECT c.product_type, cu.income_band,
       COUNT(DISTINCT s.card_id) AS accounts,
       SUM(s.statement_balance)  AS total_exposure,
       SUM(CASE WHEN s.days_past_due >= 60 THEN s.statement_balance ELSE 0 END) AS at_risk_exposure,
       ROUND(SUM(CASE WHEN s.days_past_due >= 60 THEN s.statement_balance ELSE 0 END)
             * 100.0 / NULLIF(SUM(s.statement_balance), 0), 2) AS lgd_proxy_pct
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY c.product_type, cu.income_band ORDER BY lgd_proxy_pct DESC;

-- ─────────────────────────────────────────────────────────────
-- QUERY 12: Writeoff Analysis by Product & Region
SELECT c.product_type, cu.region,
       COUNT(*) AS writeoffs,
       SUM(w.writeoff_amount) AS total_written_off,
       SUM(w.recovery_amount) AS total_recovered,
       ROUND(AVG((w.writeoff_amount - w.recovery_amount) * 1.0 / w.writeoff_amount), 4) AS avg_lgd,
       SUM(w.writeoff_amount - w.recovery_amount) AS net_loss
FROM writeoffs w
JOIN cards c ON w.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY c.product_type, cu.region ORDER BY net_loss DESC;

-- ─────────────────────────────────────────────────────────────
-- QUERY 13: Credit Limit Utilization Adequacy by Segment
SELECT cu.income_band, c.product_type,
       ROUND(AVG(c.credit_limit), 0) AS avg_limit,
       ROUND(AVG(s.statement_balance), 0) AS avg_balance,
       ROUND(AVG(s.statement_balance * 1.0 / NULLIF(s.credit_limit, 0)), 4) AS avg_util,
       COUNT(CASE WHEN s.statement_balance * 1.0 / s.credit_limit > 0.9 THEN 1 END) AS maxed_accounts,
       ROUND(COUNT(CASE WHEN s.statement_balance * 1.0 / s.credit_limit > 0.9 THEN 1 END)
             * 100.0 / COUNT(*), 2) AS pct_maxed
FROM statements s
JOIN cards c ON s.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.income_band, c.product_type ORDER BY avg_util DESC;

-- ─────────────────────────────────────────────────────────────
-- QUERY 14: Bucket Migration Pivot (Full Roll Rate Matrix)
SELECT current_bucket,
       SUM(CASE WHEN next_bucket = '0'     THEN 1 ELSE 0 END) AS to_current,
       SUM(CASE WHEN next_bucket = '1-29'  THEN 1 ELSE 0 END) AS to_1_29,
       SUM(CASE WHEN next_bucket = '30-59' THEN 1 ELSE 0 END) AS to_30_59,
       SUM(CASE WHEN next_bucket = '60-89' THEN 1 ELSE 0 END) AS to_60_89,
       SUM(CASE WHEN next_bucket = '90+'   THEN 1 ELSE 0 END) AS to_90_plus,
       COUNT(*) AS total
FROM vw_roll_rate_base
GROUP BY current_bucket
ORDER BY CASE current_bucket
    WHEN '0' THEN 1 WHEN '1-29' THEN 2 WHEN '30-59' THEN 3
    WHEN '60-89' THEN 4 WHEN '90+' THEN 5 END;

-- ─────────────────────────────────────────────────────────────
-- QUERY 15: Transaction Activity vs Delinquency Correlation
SELECT
    CASE
        WHEN days_past_due = 0   THEN 'Current'
        WHEN days_past_due <= 29 THEN '1-29 DPD'
        WHEN days_past_due <= 59 THEN '30-59 DPD'
        WHEN days_past_due <= 89 THEN '60-89 DPD'
        ELSE '90+ DPD'
    END AS dpd_group,
    COUNT(*) AS account_months,
    ROUND(AVG(transaction_amount), 2) AS avg_transaction,
    ROUND(AVG(statement_balance), 2)  AS avg_balance,
    ROUND(AVG(transaction_amount * 1.0 / NULLIF(statement_balance, 0)), 4) AS tx_to_balance_ratio
FROM statements
GROUP BY 1
ORDER BY CASE
    WHEN days_past_due = 0 THEN 1 WHEN days_past_due <= 29 THEN 2
    WHEN days_past_due <= 59 THEN 3 WHEN days_past_due <= 89 THEN 4 ELSE 5 END;
