-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 11_roll_rate_matrix.sql
-- Description: Full Roll Rate & Bucket Migration Analysis
--
-- Roll Rate = % of accounts that MIGRATE from one DPD bucket
-- to another bucket in the next month.
--
-- Why banks use roll rates:
--   1. Predict future default volume
--   2. Size collections teams
--   3. Calculate loss reserves (IFRS 9 ECL)
--   4. Detect deterioration early
--
-- DPD Buckets:
--   0     = Current (no missed payment)
--   1-29  = Watch List (< 1 month overdue)
--   30-59 = Substandard (1-2 months overdue)
--   60-89 = Doubtful (2-3 months overdue)
--   90+   = Default / Write-off candidate
-- ============================================================

-- ============================================================
-- ROLL RATE 1: Full Migration Matrix (Count-Based)
-- Reads like: "Of all accounts in bucket X, Y% moved to bucket Z"
-- ============================================================
SELECT
    r.current_bucket,
    COUNT(*)                                                                 AS total_accounts,
    SUM(CASE WHEN r.next_bucket = '0'     THEN 1 ELSE 0 END)                AS roll_to_current,
    SUM(CASE WHEN r.next_bucket = '1-29'  THEN 1 ELSE 0 END)                AS roll_to_1_29,
    SUM(CASE WHEN r.next_bucket = '30-59' THEN 1 ELSE 0 END)                AS roll_to_30_59,
    SUM(CASE WHEN r.next_bucket = '60-89' THEN 1 ELSE 0 END)                AS roll_to_60_89,
    SUM(CASE WHEN r.next_bucket = '90+'   THEN 1 ELSE 0 END)                AS roll_to_90_plus,
    -- Roll rates as percentages
    ROUND(SUM(CASE WHEN r.next_bucket = '0'     THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_to_current,
    ROUND(SUM(CASE WHEN r.next_bucket = '1-29'  THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_to_1_29,
    ROUND(SUM(CASE WHEN r.next_bucket = '30-59' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_to_30_59,
    ROUND(SUM(CASE WHEN r.next_bucket = '60-89' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_to_60_89,
    ROUND(SUM(CASE WHEN r.next_bucket = '90+'   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_to_90_plus
FROM vw_roll_rate_base r
GROUP BY r.current_bucket
ORDER BY CASE r.current_bucket
    WHEN '0' THEN 1 WHEN '1-29' THEN 2 WHEN '30-59' THEN 3
    WHEN '60-89' THEN 4 WHEN '90+' THEN 5 END;

-- ============================================================
-- ROLL RATE 2: Balance-Weighted Migration Matrix
-- Uses balance (not count) — more relevant for loss reserves
-- ============================================================
SELECT
    r.current_bucket,
    SUM(r.current_balance)                                                   AS total_balance,
    SUM(CASE WHEN r.next_bucket = '0'     THEN r.current_balance ELSE 0 END) AS bal_to_current,
    SUM(CASE WHEN r.next_bucket = '1-29'  THEN r.current_balance ELSE 0 END) AS bal_to_1_29,
    SUM(CASE WHEN r.next_bucket = '30-59' THEN r.current_balance ELSE 0 END) AS bal_to_30_59,
    SUM(CASE WHEN r.next_bucket = '60-89' THEN r.current_balance ELSE 0 END) AS bal_to_60_89,
    SUM(CASE WHEN r.next_bucket = '90+'   THEN r.current_balance ELSE 0 END) AS bal_to_90_plus,
    -- Balance roll rates as percentages
    ROUND(SUM(CASE WHEN r.next_bucket = '30-59' THEN r.current_balance ELSE 0 END)
          * 100.0 / NULLIF(SUM(r.current_balance), 0), 2)                    AS bal_roll_to_30_59_pct,
    ROUND(SUM(CASE WHEN r.next_bucket = '60-89' THEN r.current_balance ELSE 0 END)
          * 100.0 / NULLIF(SUM(r.current_balance), 0), 2)                    AS bal_roll_to_60_89_pct,
    ROUND(SUM(CASE WHEN r.next_bucket = '90+'   THEN r.current_balance ELSE 0 END)
          * 100.0 / NULLIF(SUM(r.current_balance), 0), 2)                    AS bal_roll_to_90_plus_pct
FROM vw_roll_rate_base r
GROUP BY r.current_bucket
ORDER BY CASE r.current_bucket
    WHEN '0' THEN 1 WHEN '1-29' THEN 2 WHEN '30-59' THEN 3
    WHEN '60-89' THEN 4 WHEN '90+' THEN 5 END;

-- ============================================================
-- ROLL RATE 3: Monthly Roll Rate Trend
-- Track if accounts are rolling forward (worsening) over time
-- ============================================================
SELECT
    r.current_month,
    r.current_bucket,
    COUNT(*)                                                                 AS accounts,
    ROUND(
        COUNT(CASE WHEN r.next_bucket > r.current_bucket THEN 1 END) * 100.0 / COUNT(*),
    2)                                                                       AS forward_roll_rate_pct,
    ROUND(
        COUNT(CASE WHEN r.next_bucket < r.current_bucket THEN 1 END) * 100.0 / COUNT(*),
    2)                                                                       AS cure_rate_pct,
    ROUND(
        COUNT(CASE WHEN r.next_bucket = r.current_bucket THEN 1 END) * 100.0 / COUNT(*),
    2)                                                                       AS stable_rate_pct
FROM vw_roll_rate_base r
WHERE r.current_bucket != '0'           -- Focus on delinquent buckets
GROUP BY r.current_month, r.current_bucket
ORDER BY r.current_month,
    CASE r.current_bucket
        WHEN '1-29' THEN 1 WHEN '30-59' THEN 2
        WHEN '60-89' THEN 3 WHEN '90+' THEN 4 END;

-- ============================================================
-- ROLL RATE 4: Net Roll Rate (Inflows vs Outflows)
-- Net roll rate = new inflows to a bucket - outflows (cures)
-- Positive net roll = portfolio deteriorating
-- ============================================================
WITH transitions AS (
    SELECT
        next_month AS month,
        next_bucket AS bucket,
        COUNT(*) AS inflows,
        SUM(next_balance) AS inflow_balance
    FROM vw_roll_rate_base
    WHERE next_bucket NOT IN ('0')
    GROUP BY next_month, next_bucket

    UNION ALL

    SELECT
        current_month,
        current_bucket,
        -COUNT(*),                   -- outflows (cures/payoffs)
        -SUM(current_balance)
    FROM vw_roll_rate_base
    WHERE current_bucket NOT IN ('0')
      AND next_bucket = '0'
    GROUP BY current_month, current_bucket
)
SELECT
    month,
    bucket,
    SUM(inflows) AS net_account_flow,
    SUM(inflow_balance) AS net_balance_flow
FROM transitions
GROUP BY month, bucket
ORDER BY month,
    CASE bucket
        WHEN '1-29' THEN 1 WHEN '30-59' THEN 2
        WHEN '60-89' THEN 3 WHEN '90+' THEN 4 END;

-- ============================================================
-- ROLL RATE 5: Forward Roll Rate by Region
-- Identify which regions have worst deterioration
-- ============================================================
SELECT
    cu.region,
    r.current_bucket,
    COUNT(*) AS accounts,
    ROUND(
        COUNT(CASE WHEN r.next_bucket IN ('30-59','60-89','90+')
                    AND r.current_bucket IN ('0','1-29') THEN 1 END) * 100.0 / COUNT(*),
    2) AS new_delinquency_rate_pct,
    ROUND(
        COUNT(CASE WHEN r.next_bucket = '90+'
                    AND r.current_bucket != '90+' THEN 1 END) * 100.0 / COUNT(*),
    2) AS charge_off_flow_pct
FROM vw_roll_rate_base r
JOIN cards c ON r.card_id = c.card_id
JOIN customers cu ON c.customer_id = cu.customer_id
GROUP BY cu.region, r.current_bucket
ORDER BY cu.region,
    CASE r.current_bucket
        WHEN '0' THEN 1 WHEN '1-29' THEN 2 WHEN '30-59' THEN 3
        WHEN '60-89' THEN 4 WHEN '90+' THEN 5 END;

-- ============================================================
-- ROLL RATE 6: 3-Month Forward Loss Projection
-- Uses roll rates to project next 3 months of defaults
-- ============================================================
WITH latest_buckets AS (
    SELECT dpd_bucket, COUNT(*) AS accounts, SUM(statement_balance) AS balance
    FROM statements
    WHERE period_month = (SELECT MAX(period_month) FROM statements)
    GROUP BY dpd_bucket
),
roll_rates AS (
    SELECT
        current_bucket,
        ROUND(SUM(CASE WHEN next_bucket = '90+' THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS roll_to_default
    FROM vw_roll_rate_base
    GROUP BY current_bucket
)
SELECT
    lb.dpd_bucket,
    lb.accounts,
    lb.balance,
    COALESCE(rr.roll_to_default, 0) AS projected_default_rate,
    ROUND(lb.balance * COALESCE(rr.roll_to_default, 0), 0) AS projected_default_balance
FROM latest_buckets lb
LEFT JOIN roll_rates rr ON lb.dpd_bucket = rr.current_bucket
ORDER BY CASE lb.dpd_bucket
    WHEN '0' THEN 1 WHEN '1-29' THEN 2 WHEN '30-59' THEN 3
    WHEN '60-89' THEN 4 WHEN '90+' THEN 5 END;
