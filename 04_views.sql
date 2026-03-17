-- =============================================================================
-- FILE: 04_views.sql
-- PROJECT: Nigerian Bank Transactions Analytics
-- AUTHOR: Temmygabriel
-- DATE: 16-03-2026
-- DESCRIPTION: Reusable views built on top of cleaned data.
--              These views abstract away all the cleaning logic so any
--              analyst can query clean, reliable data without needing to
--              know about the underlying messiness we fixed in Phase 3.
--              This is the standard pattern in production data warehouses —
--              raw tables stay untouched, views expose clean business-ready
--              data on top of them.
-- =============================================================================


-- =============================================================================
-- VIEW 1: vw_clean_transactions
--
-- The foundation view. Every other view builds on this one.
-- This is the single source of truth for clean transaction data.
-- It excludes zero amounts, future dates, NULL amounts, and joins
-- in the customer account type in one place so downstream views
-- don't have to repeat this logic.
--
-- Any analyst querying transactions should use this view, never
-- the raw transactions table directly.
-- ============================================================================


CREATE OR REPLACE VIEW vw_clean_transactions AS
SELECT
    t.transaction_id,
    t.customer_id,
    t.customer_name,
    t.transaction_date_clean                            AS transaction_date,
    t.amount_clean                                      AS amount,
    t.currency,
    t.transaction_type,
    t.merchant_name,
    t.category,
    t.status,
    t.location,
    t.notes,
    c.account_type,
    c.credit_score,
    c.city                                              AS customer_city
FROM transactions t
LEFT JOIN customers c ON t.customer_id = c.customer_id
WHERE t.transaction_date_clean IS NOT NULL
  AND t.amount_clean IS NOT NULL
  AND (t.notes NOT LIKE '%ZERO AMOUNT%' OR t.notes IS NULL)
  AND (t.notes NOT LIKE '%FUTURE DATE%' OR t.notes IS NULL);


-- =============================================================================
-- VIEW 2: vw_category_summary
--
-- Pre-aggregated spending by category.
-- Powers the "where is the money going" report.
-- A BI tool or dashboard can hit this view directly without running
-- a heavy aggregation query on 49,000 rows every time.
-- =============================================================================

CREATE OR REPLACE VIEW vw_category_summary AS
SELECT
    category,
    COUNT(*)                                            AS transaction_count,
    ROUND(SUM(amount), 2)                               AS total_spent_ngn,
    ROUND(AVG(amount), 2)                               AS avg_transaction_ngn,
    ROUND(
        SUM(amount) * 100.0 / SUM(SUM(amount)) OVER ()
    , 2)                                                AS pct_of_total
FROM vw_clean_transactions
WHERE transaction_type = 'debit'
GROUP BY category;


-- =============================================================================
-- VIEW 3: vw_monthly_summary
--
-- Monthly aggregation of transaction activity.
-- Powers trend charts and time series analysis.
-- Using transaction_date directly since vw_clean_transactions already
-- exposes the clean DATE column.
-- =============================================================================

CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT
    TO_CHAR(DATE_TRUNC('month', transaction_date), 'YYYY-MM')   AS year_month,
    DATE_TRUNC('month', transaction_date)                        AS month_start,
    COUNT(*)                                                      AS transaction_count,
    ROUND(SUM(CASE WHEN transaction_type = 'debit'
                   THEN amount ELSE 0 END), 2)                   AS total_debit_ngn,
    ROUND(SUM(CASE WHEN transaction_type = 'credit'
                   THEN amount ELSE 0 END), 2)                   AS total_credit_ngn,
    ROUND(AVG(amount), 2)                                        AS avg_transaction_ngn,
    COUNT(DISTINCT customer_id)                                  AS active_customers
FROM vw_clean_transactions
GROUP BY DATE_TRUNC('month', transaction_date);


-- =============================================================================
-- VIEW 4: vw_customer_summary
--
-- One row per customer with their full transaction profile.
-- Powers customer segmentation, top customer reports, and
-- relationship management dashboards.
-- =============================================================================

CREATE OR REPLACE VIEW vw_customer_summary AS
SELECT
    t.customer_id,
    MAX(c.full_name)                                    AS full_name,
    MAX(c.city)                                         AS city,
    MAX(c.account_type)                                 AS account_type,
    MAX(c.credit_score)                                 AS credit_score,
    MAX(c.join_date)                                    AS join_date,
    COUNT(*)                                            AS total_transactions,
    ROUND(SUM(CASE WHEN transaction_type = 'debit'
                   THEN amount ELSE 0 END), 2)          AS total_debit_ngn,
    ROUND(SUM(CASE WHEN transaction_type = 'credit'
                   THEN amount ELSE 0 END), 2)          AS total_credit_ngn,
    ROUND(AVG(CASE WHEN transaction_type = 'debit'
                   THEN amount END), 2)                 AS avg_debit_ngn,
    MIN(transaction_date)                               AS first_transaction,
    MAX(transaction_date)                               AS last_transaction,
    COUNT(DISTINCT category)                            AS categories_used,
    COUNT(DISTINCT merchant_name)                       AS merchants_used
FROM vw_clean_transactions t
LEFT JOIN customers c ON t.customer_id = c.customer_id
GROUP BY t.customer_id;


-- =============================================================================
-- VIEW 5: vw_merchant_summary
--
-- One row per merchant with spend and reach metrics.
-- Powers merchant partnership analysis and cashback programme design.
-- unique_customers tells you merchant reach — how many different
-- customers used this merchant, not just total transaction volume.
-- =============================================================================

CREATE OR REPLACE VIEW vw_merchant_summary AS
SELECT
    merchant_name,
    category,
    COUNT(*)                                            AS transaction_count,
    ROUND(SUM(amount), 2)                               AS total_spent_ngn,
    ROUND(AVG(amount), 2)                               AS avg_transaction_ngn,
    COUNT(DISTINCT customer_id)                         AS unique_customers,
    MIN(transaction_date)                               AS first_seen,
    MAX(transaction_date)                               AS last_seen
FROM vw_clean_transactions
WHERE transaction_type = 'debit'
GROUP BY merchant_name, category;


-- =============================================================================
-- VIEW 6: vw_flagged_transactions
--
-- Surfaces all transactions that were flagged during cleaning or
-- during fraud analysis. Single place to monitor data quality issues
-- and suspicious activity.
-- =============================================================================

CREATE OR REPLACE VIEW vw_flagged_transactions AS
SELECT
    t.transaction_id,
    t.customer_id,
    t.customer_name,
    t.transaction_date,
    t.amount,
    t.merchant_name,
    t.category,
    t.status,
    t.notes                                             AS flag_reason,
    ROUND(
        (t.amount - cs.avg_spend) /
        NULLIF(cs.stddev_spend, 0)
    , 2)                                                AS sigma_score
FROM vw_clean_transactions t
LEFT JOIN (
    SELECT
        customer_id,
        AVG(amount)     AS avg_spend,
        STDDEV(amount)  AS stddev_spend
    FROM vw_clean_transactions
    WHERE transaction_type = 'debit'
    GROUP BY customer_id
    HAVING COUNT(*) >= 10
) cs ON t.customer_id = cs.customer_id
WHERE
    (t.notes IS NOT NULL)
    OR
    (
        t.transaction_type = 'debit'
        AND (t.amount - cs.avg_spend) / NULLIF(cs.stddev_spend, 0) > 3
    );


-- =============================================================================
-- VERIFY: Confirm all 6 views were created successfully
-- =============================================================================

SELECT 
    table_name      AS view_name,
    table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'VIEW'
ORDER BY table_name;




-- Quick test on 3 key views
SELECT COUNT(*) AS clean_transactions FROM vw_clean_transactions;

SELECT * FROM vw_category_summary ORDER BY total_spent_ngn DESC LIMIT 5;

SELECT * FROM vw_monthly_summary ORDER BY month_start DESC LIMIT 3;



SELECT COUNT(*) FROM vw_flagged_transactions;
