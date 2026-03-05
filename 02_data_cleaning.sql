-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 02_data_cleaning.sql
-- Description: Full data quality validation suite
-- ============================================================

-- ============================================================
-- SECTION 1: NULL / MISSING VALUE CHECKS
-- ============================================================
SELECT 'customers - null check' AS check_name,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN region      IS NULL THEN 1 ELSE 0 END) AS null_region,
    SUM(CASE WHEN income_band IS NULL THEN 1 ELSE 0 END) AS null_income_band
FROM customers;

SELECT 'cards - null check' AS check_name,
    SUM(CASE WHEN card_id      IS NULL THEN 1 ELSE 0 END) AS null_card_id,
    SUM(CASE WHEN customer_id  IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN credit_limit IS NULL THEN 1 ELSE 0 END) AS null_credit_limit
FROM cards;

SELECT 'statements - null check' AS check_name,
    SUM(CASE WHEN statement_balance IS NULL THEN 1 ELSE 0 END) AS null_balance,
    SUM(CASE WHEN paid_amount       IS NULL THEN 1 ELSE 0 END) AS null_paid,
    SUM(CASE WHEN days_past_due     IS NULL THEN 1 ELSE 0 END) AS null_dpd,
    SUM(CASE WHEN credit_limit      IS NULL THEN 1 ELSE 0 END) AS null_limit
FROM statements;

-- ============================================================
-- SECTION 2: DUPLICATE CHECKS
-- ============================================================

-- Duplicate customer_ids
SELECT customer_id, COUNT(*) AS cnt
FROM customers GROUP BY customer_id HAVING COUNT(*) > 1;

-- Duplicate card_ids
SELECT card_id, COUNT(*) AS cnt
FROM cards GROUP BY card_id HAVING COUNT(*) > 1;

-- Duplicate (card_id, period_month) — must be unique
SELECT card_id, period_month, COUNT(*) AS cnt
FROM statements
GROUP BY card_id, period_month
HAVING COUNT(*) > 1;

-- ============================================================
-- SECTION 3: RANGE / BUSINESS LOGIC CHECKS
-- ============================================================

-- Negative statement balances
SELECT 'negative_balance' AS issue, COUNT(*) AS count
FROM statements WHERE statement_balance < 0;

-- Negative days_past_due
SELECT 'negative_dpd' AS issue, COUNT(*) AS count
FROM statements WHERE days_past_due < 0;

-- Paid amount exceeds balance (review — allowed for prepayments)
SELECT 'overpayment' AS issue, COUNT(*) AS count
FROM statements WHERE paid_amount > statement_balance;

-- Zero or negative credit limit
SELECT 'bad_credit_limit' AS issue, COUNT(*) AS count
FROM cards WHERE credit_limit <= 0;

-- Balance > credit limit  (over-limit accounts)
SELECT 'over_limit' AS issue, COUNT(*) AS count
FROM statements WHERE statement_balance > credit_limit;

-- DPD vs bucket inconsistency check
SELECT 'dpd_bucket_mismatch' AS issue, COUNT(*) AS count
FROM statements
WHERE
    (days_past_due = 0   AND dpd_bucket != '0')
 OR (days_past_due BETWEEN 1  AND 29 AND dpd_bucket != '1-29')
 OR (days_past_due BETWEEN 30 AND 59 AND dpd_bucket != '30-59')
 OR (days_past_due BETWEEN 60 AND 89 AND dpd_bucket != '60-89')
 OR (days_past_due >= 90              AND dpd_bucket != '90+');

-- ============================================================
-- SECTION 4: REFERENTIAL INTEGRITY
-- ============================================================

-- Cards with no matching customer
SELECT 'orphan_cards' AS issue, COUNT(*) AS count
FROM cards c LEFT JOIN customers cu ON c.customer_id = cu.customer_id
WHERE cu.customer_id IS NULL;

-- Statements with no matching card
SELECT 'orphan_statements' AS issue, COUNT(*) AS count
FROM statements s LEFT JOIN cards c ON s.card_id = c.card_id
WHERE c.card_id IS NULL;

-- Writeoffs with no matching card
SELECT 'orphan_writeoffs' AS issue, COUNT(*) AS count
FROM writeoffs w LEFT JOIN cards c ON w.card_id = c.card_id
WHERE c.card_id IS NULL;

-- ============================================================
-- SECTION 5: DISTRIBUTION PROFILES
-- ============================================================

-- Customer distribution
SELECT region, income_band, COUNT(*) AS customers,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM customers
GROUP BY region, income_band
ORDER BY customers DESC;

-- Product type distribution
SELECT product_type,
       COUNT(*) AS cards,
       ROUND(AVG(credit_limit), 0) AS avg_limit,
       MIN(credit_limit) AS min_limit,
       MAX(credit_limit) AS max_limit
FROM cards GROUP BY product_type ORDER BY cards DESC;

-- DPD bucket distribution (overall)
SELECT dpd_bucket,
       COUNT(*) AS account_months,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct,
       SUM(statement_balance) AS total_exposure
FROM statements GROUP BY dpd_bucket
ORDER BY CASE dpd_bucket
    WHEN '0' THEN 1 WHEN '1-29' THEN 2
    WHEN '30-59' THEN 3 WHEN '60-89' THEN 4 WHEN '90+' THEN 5 END;

-- Monthly data completeness — each month should have 50,000 statements
SELECT period_month,
       COUNT(*) AS statements,
       COUNT(DISTINCT card_id) AS unique_cards
FROM statements
GROUP BY period_month
ORDER BY period_month;

-- ============================================================
-- SECTION 6: WRITEOFF DATA VALIDATION
-- ============================================================

-- Negative writeoff amounts
SELECT 'negative_writeoff' AS issue, COUNT(*) AS count
FROM writeoffs WHERE writeoff_amount <= 0;

-- Recovery > writeoff (invalid)
SELECT 'recovery_exceeds_writeoff' AS issue, COUNT(*) AS count
FROM writeoffs WHERE recovery_amount > writeoff_amount;

-- LGD should be between 0 and 1
SELECT
    MIN((writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)) AS min_lgd,
    MAX((writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)) AS max_lgd,
    AVG((writeoff_amount - recovery_amount) * 1.0 / NULLIF(writeoff_amount, 0)) AS avg_lgd
FROM writeoffs;
