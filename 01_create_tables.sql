-- ============================================================
-- Credit Card Risk Analytics Project
-- File: 01_create_tables.sql
-- Description: Create schema for all 4 tables
-- ============================================================

-- ============================================================
-- TABLE 1: customers  (50,000 rows)
-- ============================================================
DROP TABLE IF EXISTS customers CASCADE;

CREATE TABLE customers (
    customer_id   INT           PRIMARY KEY,
    region        VARCHAR(20)   NOT NULL,
    income_band   VARCHAR(20)   NOT NULL,
    age           INT,
    tenure_years  INT
);

-- ============================================================
-- TABLE 2: cards  (50,000 rows)
-- ============================================================
DROP TABLE IF EXISTS cards CASCADE;

CREATE TABLE cards (
    card_id        INT          PRIMARY KEY,
    customer_id    INT          NOT NULL,
    product_type   VARCHAR(20)  NOT NULL,
    credit_limit   INT          NOT NULL,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- ============================================================
-- TABLE 3: statements  (1,500,000 rows)
-- ============================================================
DROP TABLE IF EXISTS statements CASCADE;

CREATE TABLE statements (
    card_id              INT          NOT NULL,
    period_month         DATE         NOT NULL,
    statement_balance    INT          NOT NULL DEFAULT 0,
    min_due              INT          NOT NULL DEFAULT 0,
    paid_amount          INT          NOT NULL DEFAULT 0,
    days_past_due        INT          NOT NULL DEFAULT 0,
    dpd_bucket           VARCHAR(10)  NOT NULL,
    credit_limit         INT          NOT NULL,
    transaction_amount   INT          NOT NULL DEFAULT 0,
    CONSTRAINT fk_card FOREIGN KEY (card_id) REFERENCES cards(card_id)
);

-- Recommended indexes for performance
CREATE INDEX idx_stmts_card_id      ON statements(card_id);
CREATE INDEX idx_stmts_period       ON statements(period_month);
CREATE INDEX idx_stmts_dpd          ON statements(days_past_due);
CREATE INDEX idx_stmts_dpd_bucket   ON statements(dpd_bucket);

-- ============================================================
-- TABLE 4: writeoffs  (2,000 rows)
-- Used for LGD calculation
-- ============================================================
DROP TABLE IF EXISTS writeoffs CASCADE;

CREATE TABLE writeoffs (
    card_id           INT     NOT NULL,
    writeoff_amount   INT     NOT NULL,
    recovery_amount   INT     NOT NULL DEFAULT 0,
    writeoff_date     DATE    NOT NULL,
    CONSTRAINT fk_writeoff_card FOREIGN KEY (card_id) REFERENCES cards(card_id)
);

CREATE INDEX idx_writeoffs_card ON writeoffs(card_id);
CREATE INDEX idx_writeoffs_date ON writeoffs(writeoff_date);

-- ============================================================
-- LOAD DATA  (PostgreSQL COPY syntax)
-- ============================================================
-- COPY customers  FROM '/path/to/customers.csv'  CSV HEADER;
-- COPY cards      FROM '/path/to/cards.csv'      CSV HEADER;
-- COPY statements FROM '/path/to/statements.csv' CSV HEADER;
-- COPY writeoffs  FROM '/path/to/writeoffs.csv'  CSV HEADER;

-- MySQL alternative:
-- LOAD DATA INFILE '/path/customers.csv'
-- INTO TABLE customers FIELDS TERMINATED BY ',' IGNORE 1 ROWS;

-- ============================================================
-- VERIFY ROW COUNTS
-- ============================================================
SELECT 'customers'  AS tbl, COUNT(*) AS rows FROM customers
UNION ALL
SELECT 'cards',               COUNT(*)        FROM cards
UNION ALL
SELECT 'statements',          COUNT(*)        FROM statements
UNION ALL
SELECT 'writeoffs',           COUNT(*)        FROM writeoffs;

-- Expected:
-- customers  → 50,000
-- cards      → 50,000
-- statements → 1,500,000
-- writeoffs  → 2,000
