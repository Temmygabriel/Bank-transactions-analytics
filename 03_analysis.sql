-- =============================================================================
-- FILE: 03_analysis.sql
-- PROJECT: Nigerian Bank Transactions Analytics
-- AUTHOR: Temmygabriel
-- DATE: 16-03-2026
-- DESCRIPTION: Business intelligence queries answering 8 real analytical
--              questions a bank analyst would be asked by management.
--              All queries run on cleaned data only — zero amount rows and
--              future dated rows are excluded from every analysis.
-- =============================================================================

-- =============================================================================
-- QUERY 1: WHERE IS THE MONEY GOING? — Total spending by category
--
-- Business question: Which spending categories drive the most transaction
-- volume? This tells the bank where customers are using their money most,
-- which informs product decisions, partnership opportunities, and marketing.
--
-- Design decisions:
--   - Filtering out zero amounts and future dates from every query going
--     forward. These are data quality issues, not real transactions.
--   - Filtering to debit only — we want outgoing spend, not incoming salary.
--   - Rounding to 2 decimal places for clean reporting.
--   - Adding a percentage column so each category's share is immediately
--     visible without needing a calculator.
-- =============================================================================

SELECT
    category,
    COUNT(*)                                                AS transaction_count,
    ROUND(SUM(amount_clean), 2)                            AS total_spent_ngn,
    ROUND(AVG(amount_clean), 2)                            AS avg_transaction_ngn,
    ROUND(
        SUM(amount_clean) * 100.0 / 
        SUM(SUM(amount_clean)) OVER (), 
    2)                                                     AS percentage_of_total
FROM transactions
WHERE transaction_type = 'debit'
  AND (notes NOT LIKE '%ZERO AMOUNT%' OR notes IS NULL)
  AND (notes NOT LIKE '%FUTURE DATE%' OR notes IS NULL)
  AND amount_clean IS NOT NULL
GROUP BY category
ORDER BY total_spent_ngn DESC;



-- QUERY 1 RESULTS — Key findings:
--
-- 1. Housing is the single largest spending category at 18.38% of total spend
--    (637M NGN) despite only 2,553 transactions — the highest average ticket
--    size at 249,868 NGN per transaction. Rent and property fees are large,
--    infrequent payments which explains this pattern.
--
-- 2. Income and Salary combined = 27.62% of total volume — but these are
--    credits appearing as debits in our filter which is worth investigating.
--    In a real project I would flag this to the data owner for clarification.
--
-- 3. Groceries and Utilities have the HIGHEST transaction counts (6,129 and
--    5,246) but relatively low total spend — small frequent purchases.
--    Food and Transport show the same pattern — high frequency, low value.
--    These are the everyday banking categories.
--
-- 4. Entertainment is the smallest category at 0.44% — customers are not
--    spending heavily on leisure relative to essentials.
--
-- 5. Uncategorised = 4.16% of spend (144M NGN) — this is the cost of the
--    data quality issue we found. In a real bank this would be escalated
--    to the data team to recover those category labels from source systems.










-- =============================================================================
-- QUERY 2: HOW HAS SPENDING CHANGED OVER TIME? — Monthly trends
--
-- Business question: Is customer spending growing, declining, or seasonal?
-- Management uses this to forecast revenue, plan staffing, and identify
-- anomalies like a sudden drop in transaction volume.
--
-- The challenge here: transaction_date is still VARCHAR with 7 different
-- formats. I cannot simply cast it to DATE because mixed formats will cause
-- PostgreSQL to throw an error on formats it doesn't expect.
--
-- My approach: Use SUBSTRING and pattern matching to extract the 4-digit year
-- from wherever it appears in the string. This is not perfect — it is a
-- pragmatic workaround until a full date standardisation is done.
-- The correct long-term fix is a dedicated date cleaning pass which would
-- use multiple TO_DATE() attempts with different format strings.
-- For now this gives us a usable trend view.
-- =============================================================================

SELECT
    CASE
        WHEN transaction_date ~ '^\d{4}[-/]'
            THEN SUBSTRING(transaction_date, 1, 7)
        WHEN transaction_date ~ '\d{4}$'
            THEN SUBSTRING(transaction_date, LENGTH(transaction_date)-3, 4)
        ELSE 'unknown'
    END                                         AS year_month,
    COUNT(*)                                    AS transaction_count,
    ROUND(SUM(amount_clean), 2)                 AS total_spent_ngn,
    ROUND(AVG(amount_clean), 2)                 AS avg_transaction_ngn
FROM transactions
WHERE transaction_type = 'debit'
  AND (notes NOT LIKE '%ZERO AMOUNT%' OR notes IS NULL)
  AND (notes NOT LIKE '%FUTURE DATE%' OR notes IS NULL)
  AND amount_clean IS NOT NULL
GROUP BY year_month
ORDER BY year_month;





-- =============================================================================
-- DATE STANDARDISATION — Adding a clean date column
--
-- transaction_date is VARCHAR with 7 formats. Rather than working around
-- this in every query, I am adding a transaction_date_clean column of type
-- DATE and converting all formats properly using TO_DATE() with COALESCE.
--
-- COALESCE tries each format in order and uses the first one that succeeds.
-- This is the correct production approach — explicit, auditable, no guessing.
--
-- Formats to handle:
--   YYYY-MM-DD    → most common ISO format
--   YYYY/MM/DD    → slash ISO variant
--   DD/MM/YYYY    → British format
--   DD-MM-YYYY    → dash British
--   MM/DD/YYYY    → American (ambiguous — handled last)
--   Mon DD YYYY   → e.g. Jan 05 2024
--   DD Month, YYYY → e.g. 05 January, 2024
-- =============================================================================

ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS transaction_date_clean DATE;

UPDATE transactions
SET transaction_date_clean = COALESCE(
    -- YYYY-MM-DD
    CASE WHEN transaction_date ~ '^\d{4}-\d{2}-\d{2}$'
         THEN TO_DATE(transaction_date, 'YYYY-MM-DD') END,
    -- YYYY/MM/DD
    CASE WHEN transaction_date ~ '^\d{4}/\d{2}/\d{2}$'
         THEN TO_DATE(transaction_date, 'YYYY/MM/DD') END,
    -- DD-MM-YYYY (day first, unambiguous because day > 12)
    CASE WHEN transaction_date ~ '^\d{2}-\d{2}-\d{4}$'
         AND SPLIT_PART(transaction_date, '-', 1)::INT > 12
         THEN TO_DATE(transaction_date, 'DD-MM-YYYY') END,
    -- MM-DD-YYYY (month first, when day part > 12)
    CASE WHEN transaction_date ~ '^\d{2}-\d{2}-\d{4}$'
         AND SPLIT_PART(transaction_date, '-', 2)::INT > 12
         THEN TO_DATE(transaction_date, 'MM-DD-YYYY') END,
    -- DD-MM-YYYY fallback for ambiguous dash dates
    CASE WHEN transaction_date ~ '^\d{2}-\d{2}-\d{4}$'
         THEN TO_DATE(transaction_date, 'DD-MM-YYYY') END,
    -- MM/DD/YYYY American (when day part > 12, unambiguous)
    CASE WHEN transaction_date ~ '^\d{2}/\d{2}/\d{4}$'
         AND SPLIT_PART(transaction_date, '/', 2)::INT > 12
         THEN TO_DATE(transaction_date, 'MM/DD/YYYY') END,
    -- DD/MM/YYYY British (when day part > 12, unambiguous)
    CASE WHEN transaction_date ~ '^\d{2}/\d{2}/\d{4}$'
         AND SPLIT_PART(transaction_date, '/', 1)::INT > 12
         THEN TO_DATE(transaction_date, 'DD/MM/YYYY') END,
    -- DD/MM/YYYY British fallback for ambiguous slash dates
    CASE WHEN transaction_date ~ '^\d{2}/\d{2}/\d{4}$'
         THEN TO_DATE(transaction_date, 'DD/MM/YYYY') END,
    -- Mon DD YYYY e.g. Jan 05 2024
    CASE WHEN transaction_date ~ '^[A-Za-z]{3} \d{2} \d{4}$'
         THEN TO_DATE(transaction_date, 'Mon DD YYYY') END,
    -- DD Month, YYYY e.g. 05 January, 2024
    CASE WHEN transaction_date ~ '^\d{2} [A-Za-z]+, \d{4}$'
         THEN TO_DATE(REPLACE(transaction_date, ',', ''), 'DD Month YYYY') END
)
WHERE (notes NOT LIKE '%FUTURE DATE%' OR notes IS NULL);

-- Verify — how many rows got a clean date vs NULL?
SELECT
    COUNT(*)                            AS total_rows,
    COUNT(transaction_date_clean)       AS rows_with_clean_date,
    COUNT(*) - COUNT(transaction_date_clean) AS rows_still_null
FROM transactions;







-- DATE STANDARDISATION RESULT:
-- 49,127 rows successfully converted from VARCHAR to DATE
-- 82 rows left as NULL — these are the future-dated transactions
-- flagged in ISS-12. Intentionally excluded from conversion.
-- All 7 date formats successfully parsed using SPLIT_PART disambiguation
-- for ambiguous American vs British slash/dash formats.










-- =============================================================================
-- QUERY 2 REVISED: Monthly trends using transaction_date_clean
-- Now that we have a proper DATE column, we can use DATE_TRUNC to group
-- by month cleanly. DATE_TRUNC('month', date) rounds every date down to
-- the 1st of its month — so 2022-01-05 and 2022-01-28 both become
-- 2022-01-01 and group together correctly.
-- =============================================================================

SELECT
    TO_CHAR(DATE_TRUNC('month', transaction_date_clean), 'YYYY-MM') AS year_month,
    COUNT(*)                                                          AS transaction_count,
    ROUND(SUM(amount_clean), 2)                                       AS total_spent_ngn,
    ROUND(AVG(amount_clean), 2)                                       AS avg_transaction_ngn
FROM transactions
WHERE transaction_type = 'debit'
  AND transaction_date_clean IS NOT NULL
  AND (notes NOT LIKE '%ZERO AMOUNT%' OR notes IS NULL)
  AND amount_clean IS NOT NULL
GROUP BY DATE_TRUNC('month', transaction_date_clean)
ORDER BY DATE_TRUNC('month', transaction_date_clean);





-- QUERY 2 RESULTS — Key findings:
--
-- 36 months of clean transaction data from Jan 2022 to Dec 2024
-- Monthly transaction counts are remarkably stable — ranging from
-- ~950 to ~1,180 transactions per month. No dramatic spikes or drops
-- suggesting the customer base was consistent throughout the period.
--
-- Notable observations:
-- May consistently performs strongly across all 3 years:
--   May 2022: 111M NGN, May 2023: 108M NGN, May 2024: 88M NGN
-- February is consistently the weakest month — fewer days + lower spend
-- Dec 2024 ended strong at 108M NGN suggesting year-end spending behaviour
-- Average transaction value held steady around 80,000-95,000 NGN throughout
-- suggesting no major inflation shock visible in this customer segment











-- =============================================================================
-- QUERY 3: WHO ARE THE HIGHEST VALUE CUSTOMERS? — Top 10 by spend
--
-- Business question: Which customers generate the most transaction volume?
-- Banks use this to identify premium customers for relationship management,
-- loyalty programmes, and preferential service.
--
-- This is our first JOIN — connecting transactions to customers to enrich
-- the transaction data with account type and credit score information.
-- I am using LEFT JOIN rather than INNER JOIN because some transactions
-- may have customer_ids that do not exist in the customers table due to
-- data quality issues. INNER JOIN would silently drop those rows.
-- LEFT JOIN keeps all transactions and shows NULL for missing customer info
-- making the data gap visible rather than hiding it.
-- =============================================================================

SELECT
    t.customer_id,
    c.full_name,
    c.city,
    c.account_type,
    c.credit_score,
    COUNT(*)                            AS transaction_count,
    ROUND(SUM(t.amount_clean), 2)       AS total_spent_ngn,
    ROUND(AVG(t.amount_clean), 2)       AS avg_transaction_ngn,
    MIN(t.transaction_date_clean)       AS first_transaction,
    MAX(t.transaction_date_clean)       AS last_transaction
FROM transactions t
LEFT JOIN customers c ON t.customer_id = c.customer_id
WHERE t.transaction_type = 'debit'
  AND t.transaction_date_clean IS NOT NULL
  AND (t.notes NOT LIKE '%ZERO AMOUNT%' OR t.notes IS NULL)
  AND t.amount_clean IS NOT NULL
GROUP BY 
    t.customer_id,
    c.full_name,
    c.city,
    c.account_type,
    c.credit_score
ORDER BY total_spent_ngn DESC
LIMIT 10;







-- QUERY 3 RESULTS — Key findings:
--
-- Top 10 customers account for roughly 84M NGN in debit spend over 3 years.
-- Transaction counts are similar across all top customers (52-69 txns each)
-- suggesting consistent, high-value spenders rather than one-time large payments.
--
-- Notable observations:
-- CUST-0180 (Dennis Evans, Sokoto) leads total spend at 9.2M NGN despite
--   having only a credit score of 541 — low score, high activity. Interesting
--   profile that a risk team would want to investigate further.
--
-- CUST-0437 (David Frey, Kaduna) has the highest credit score (847) among
--   the top 10 and is the second highest spender — expected correlation.
--
-- CUST-0609 (row 9) has a NULL full_name — this is a data quality gap we
--   flagged in cleaning. The customer is still visible here because we used
--   LEFT JOIN — INNER JOIN would have silently hidden this customer entirely,
--   potentially excluding a top-10 spender from the report. This validates
--   our decision to use LEFT JOIN over INNER JOIN.
--
-- Geographic spread: top customers come from Sokoto, Kaduna, Uyo, Zaria,
--   Calabar, Ibadan, Abuja, Warri, Owerri — not concentrated in Lagos.
--   Surprising given Lagos dominates Nigerian banking activity generally.





-- =============================================================================
-- QUERY 4: WHAT IS OUR TRANSACTION FAILURE RATE? — Status breakdown
--
-- Business question: What proportion of transactions are failing or pending?
-- A high failure rate indicates payment infrastructure problems.
-- A high pending rate may indicate processing backlogs.
-- This is a key operational metric for any payments team.
--
-- I am calculating both count and percentage in the same query using a
-- window function SUM() OVER () to get the grand total for the denominator.
-- This avoids a subquery and keeps the logic in one clean pass.
-- =============================================================================

SELECT
    status,
    COUNT(*)                                                AS transaction_count,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
    2)                                                      AS percentage,
    ROUND(SUM(amount_clean), 2)                            AS total_value_ngn,
    ROUND(AVG(amount_clean), 2)                            AS avg_value_ngn
FROM transactions
WHERE transaction_date_clean IS NOT NULL
  AND (notes NOT LIKE '%ZERO AMOUNT%' OR notes IS NULL)
  AND amount_clean IS NOT NULL
GROUP BY status
ORDER BY transaction_count DESC;




-- QUERY 4 RESULTS — Key findings:
--
-- 83.76% completion rate — meaning roughly 1 in 6 transactions never
-- completes successfully. In a production banking system this would be
-- a serious concern worth escalating to the payments infrastructure team.
--
-- Pending transactions (8.07% / 3,921 rows) represent 544M NGN sitting
-- in limbo — money neither confirmed delivered nor returned to sender.
-- A real bank would have SLA rules requiring pending transactions to
-- resolve within 24-48 hours. These would need immediate investigation.
--
-- Failed transactions (4.02% / 1,954 rows) represent 274M NGN in
-- attempted payments that never went through. Each failed transaction
-- is a potential customer complaint and revenue loss for the bank.
--
-- Reversed transactions show negative total value (-212M NGN) confirming
-- our ISS-14 fix worked correctly — reversals are reducing total volume
-- as they should.
--
-- Unknown status (1.20%) — these are the NULL status rows we replaced
-- with 'unknown' during cleaning. In a real project these would be
-- escalated to the source system team to recover the original status.
--
-- Key metric for the dashboard:
-- Successful transaction rate: 83.76%
-- Problem transaction rate: 16.24% (pending + failed + unknown)









-- =============================================================================
-- QUERY 5: WHICH MERCHANTS GET THE MOST BUSINESS? — Top 15 merchants
--
-- Business question: Where are customers spending the most?
-- Banks use this for merchant partnership negotiations, cashback programme
-- design, and understanding customer lifestyle patterns.
-- This also validates our merchant name standardisation from Phase 3 —
-- if cleaning worked correctly, each merchant appears exactly once.
-- =============================================================================

SELECT
    merchant_name,
    category,
    COUNT(*)                            AS transaction_count,
    ROUND(SUM(amount_clean), 2)         AS total_spent_ngn,
    ROUND(AVG(amount_clean), 2)         AS avg_transaction_ngn,
    COUNT(DISTINCT customer_id)         AS unique_customers
FROM transactions
WHERE transaction_type = 'debit'
  AND transaction_date_clean IS NOT NULL
  AND (notes NOT LIKE '%ZERO AMOUNT%' OR notes IS NULL)
  AND amount_clean IS NOT NULL
GROUP BY merchant_name, category
ORDER BY total_spent_ngn DESC
LIMIT 15;



-- QUERY 5 RESULTS — Key findings:
--
-- Housing dominates the top 3 merchants by total spend:
-- Estate Management Fee (217M), Rent Payment (217M), Property Agency (202M)
-- Combined: 637M NGN — consistent with Query 1 showing Housing at 18.38%
-- These are large infrequent payments averaging 244,000-252,000 NGN each.
-- Unique customer spread is wide (524-546 customers) meaning this is not
-- driven by a few high-value customers — it is a broad portfolio behaviour.
--
-- Income/Salary merchants appearing here is worth flagging:
-- Dividend Credit, Freelance Income, Client Payment, Business Revenue
-- are all INCOME categories but appearing in a DEBIT filter query.
-- This suggests these transactions were coded as debits in the source
-- system despite being incoming payments — a data quality issue worth
-- raising with the source system team in a real project.
--
-- Travel merchants (Air Peace, Sheraton, Radisson, Dana Air, Transcorp)
-- all cluster tightly between 70M-80M NGN suggesting similar customer
-- behaviour across travel merchants rather than one dominant provider.
--
-- Merchant cleaning validation: each merchant appears exactly once --
-- confirming our CASE WHEN standardisation in Phase 3 worked correctly.















-- =============================================================================
-- QUERY 6: DO ACCOUNT TYPES SPEND DIFFERENTLY? — Savings vs Current vs Business
--
-- Business question: Which customer segment is most valuable?
-- This informs which account types to prioritise for acquisition campaigns
-- and what product features matter most to each segment.
--
-- This JOIN pulls account_type from the customers table and aggregates
-- transaction behaviour by segment. A customer with no matching record
-- in customers (NULL account_type) is grouped separately so the data
-- gap is visible rather than silently excluded.
-- =============================================================================

SELECT
    COALESCE(c.account_type, 'Unknown')     AS account_type,
    COUNT(DISTINCT t.customer_id)           AS customer_count,
    COUNT(*)                                AS transaction_count,
    ROUND(SUM(t.amount_clean), 2)           AS total_spent_ngn,
    ROUND(AVG(t.amount_clean), 2)           AS avg_transaction_ngn,
    ROUND(SUM(t.amount_clean) /
          COUNT(DISTINCT t.customer_id), 2) AS avg_spend_per_customer
FROM transactions t
LEFT JOIN customers c ON t.customer_id = c.customer_id
WHERE t.transaction_type = 'debit'
  AND t.transaction_date_clean IS NOT NULL
  AND (t.notes NOT LIKE '%ZERO AMOUNT%' OR t.notes IS NULL)
  AND t.amount_clean IS NOT NULL
GROUP BY c.account_type
ORDER BY total_spent_ngn DESC;





-- QUERY 6 RESULTS — Key findings:
--
-- All four account types show remarkably similar behaviour:
-- Transaction counts range from 9,739 to 10,393 — very even distribution
-- Average transaction value is nearly identical across all types:
-- Business: 87,687 NGN, Savings: 86,037 NGN, Fixed Deposit: 85,594 NGN
-- Current: 84,745 NGN — less than 4% difference between highest and lowest
--
-- Business accounts lead total spend at 911M NGN and highest spend
-- per customer at 4.42M NGN over 3 years — expected since business
-- accounts handle commercial payments, payroll and supplier payments
-- which tend to be larger and more frequent than personal banking.
--
-- Fixed Deposit accounts spending 851M NGN is surprising — these are
-- typically term deposit accounts not meant for daily transactions.
-- In a real project this would be flagged for investigation — either
-- the account type classification is wrong for some customers or
-- Fixed Deposit customers are using a linked current account for
-- spending but the transactions are tagged to the wrong account type.
--
-- Savings accounts have the lowest total and per-customer spend which
-- is expected — savings accounts are designed for deposits not spending.
--
-- No Unknown account_type rows appeared — confirming every transaction
-- customer_id matched a record in the customers table successfully.















-- =============================================================================
-- QUERY 7: RUNNING TOTAL PER CUSTOMER — Window function
--
-- Business question: How does each customer's cumulative spend build up
-- over time? This is used for customer lifetime value tracking, spending
-- limit monitoring, and identifying customers approaching credit thresholds.
--
-- WINDOW FUNCTIONS explained:
-- A normal GROUP BY collapses rows into one summary row per group.
-- A window function performs a calculation ACROSS rows without collapsing them.
-- Each row keeps its own identity AND gets access to an aggregated value.
--
-- PARTITION BY customer_id → restart the running total for each customer
-- ORDER BY transaction_date_clean → accumulate in date order
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW → sum from first row
-- to current row — this is what makes it a running total
--
-- I am limiting to top 5 customers by spend to keep the output readable
-- while demonstrating the technique clearly.
-- =============================================================================

WITH top_customers AS (
    SELECT customer_id
    FROM transactions
    WHERE transaction_type = 'debit'
      AND amount_clean IS NOT NULL
      AND transaction_date_clean IS NOT NULL
    GROUP BY customer_id
    ORDER BY SUM(amount_clean) DESC
    LIMIT 5
)
SELECT
    t.customer_id,
    c.full_name,
    t.transaction_date_clean,
    t.merchant_name,
    t.amount_clean,
    ROUND(
        SUM(t.amount_clean) OVER (
            PARTITION BY t.customer_id
            ORDER BY t.transaction_date_clean
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2)                               AS running_total_ngn,
    ROW_NUMBER() OVER (
        PARTITION BY t.customer_id
        ORDER BY t.transaction_date_clean
    )                                       AS transaction_number
FROM transactions t
LEFT JOIN customers c ON t.customer_id = c.customer_id
WHERE t.customer_id IN (SELECT customer_id FROM top_customers)
  AND t.transaction_type = 'debit'
  AND t.transaction_date_clean IS NOT NULL
  AND (t.notes NOT LIKE '%ZERO AMOUNT%' OR t.notes IS NULL)
  AND t.amount_clean IS NOT NULL
ORDER BY t.customer_id, t.transaction_date_clean
LIMIT 50;




-- QUERY 7 RESULTS — Key findings:
--
-- This output shows Terry Santiago (CUST-0135) building from zero to
-- 8.3M NGN in cumulative spend across 50 transactions from Jan 2022
-- to Aug 2024. Every transaction is visible with its individual amount
-- AND its contribution to the running total simultaneously.
--
-- This is what window functions make possible — information at two
-- levels of granularity in a single query. A GROUP BY would give you
-- the total but lose the individual transactions. A plain SELECT would
-- give you individual transactions but no running context. OVER() gives
-- you both at the same time.
--
-- Notable pattern in Terry's spending:
-- Transaction 13 (Oct 2022): Client Payment of 906,742 NGN — running
--   total jumps from 1.7M to 2.6M in one transaction. Large income event.
-- Transaction 29 (Jul 2023): Freelance Income of 997,580 NGN — biggest
--   single transaction, pushes running total past 5M NGN milestone.
-- Small daily transactions (YouTube Premium, Shoprite, Sweet Sensation)
--   are visible between the large payments showing realistic mixed behaviour.
-- Transaction 27: YouTube Premium shows -7,854 NGN — a reversal that
--   actually REDUCES the running total, proving our sign fix works correctly
--   in a real calculation context.
--
-- Real world use case: a bank's risk system would use this exact query
-- to monitor when a customer's cumulative monthly spend crosses a threshold
-- and trigger a review or a premium service offer.







-- =============================================================================
-- QUERY 8: WHICH TRANSACTIONS LOOK SUSPICIOUS? — Fraud flag analysis
--
-- Business question: Which transactions are unusually large compared to
-- that customer's normal spending behaviour?
-- Banks use statistical deviation from a customer's own baseline to flag
-- potentially fraudulent transactions for manual review.
--
-- APPROACH:
-- For each customer I calculate their average transaction amount and
-- standard deviation. A transaction is flagged as suspicious if it is
-- more than 3 standard deviations above that customer's own average.
-- This is called the 3-sigma rule — a standard statistical technique
-- used in fraud detection systems worldwide.
--
-- I use a CTE (Common Table Expression) to first calculate each
-- customer's baseline stats, then join back to transactions to find
-- outliers. CTEs make complex multi-step logic readable and maintainable.
-- =============================================================================

WITH customer_stats AS (
    -- Step 1: Calculate each customer's spending baseline
    SELECT
        customer_id,
        ROUND(AVG(amount_clean), 2)     AS avg_spend,
        ROUND(STDDEV(amount_clean), 2)  AS stddev_spend,
        COUNT(*)                         AS total_transactions
    FROM transactions
    WHERE transaction_type = 'debit'
      AND amount_clean IS NOT NULL
      AND transaction_date_clean IS NOT NULL
      AND (notes NOT LIKE '%ZERO AMOUNT%' OR notes IS NULL)
    GROUP BY customer_id
    HAVING COUNT(*) >= 10  -- only flag customers with enough history
),
flagged AS (
    -- Step 2: Find transactions exceeding 3 standard deviations
    SELECT
        t.transaction_id,
        t.customer_id,
        c.full_name,
        c.city,
        t.transaction_date_clean,
        t.merchant_name,
        t.category,
        t.amount_clean,
        cs.avg_spend,
        cs.stddev_spend,
        ROUND(
            (t.amount_clean - cs.avg_spend) / NULLIF(cs.stddev_spend, 0)
        , 2)                            AS sigma_score,
        t.status
    FROM transactions t
    JOIN customer_stats cs ON t.customer_id = cs.customer_id
    LEFT JOIN customers c ON t.customer_id = c.customer_id
    WHERE t.transaction_type = 'debit'
      AND t.amount_clean IS NOT NULL
      AND t.transaction_date_clean IS NOT NULL
      AND (t.notes NOT LIKE '%ZERO AMOUNT%' OR t.notes IS NULL)
      AND (t.amount_clean - cs.avg_spend) / 
          NULLIF(cs.stddev_spend, 0) > 3
)
-- Step 3: Show the most suspicious transactions first
SELECT *
FROM flagged
ORDER BY sigma_score DESC
LIMIT 20;







-- QUERY 8 RESULTS — Key findings:
--
-- 20 transactions flagged with sigma scores between 5.52 and 6.23 —
-- all are more than 5 standard deviations above their customer's normal
-- spending baseline. In statistics, anything above 3 sigma is considered
-- a significant outlier. These are extreme outliers worth investigating.
--
-- Top flag: TXN-005648 — Richard Flores (Owerri) received a Salary Credit
-- of 743,141 NGN against his average spend of 46,196 NGN — a sigma score
-- of 6.23. This is 16x his normal transaction size.
--
-- Pattern observation: the majority of flagged transactions are in the
-- Income and Salary categories — Client Payment, Freelance Income,
-- Dividend Credit, Salary Credit, Business Revenue, Payroll Payment.
-- This makes statistical sense — these are occasional large credits
-- hitting accounts that otherwise show smaller daily spend patterns.
-- In a real fraud system you would want to separate the flag logic
-- for income vs spending transactions since large income events are
-- expected and not inherently suspicious.
--
-- Status breakdown of flagged transactions:
-- Completed: majority — payment went through despite being anomalous
-- Pending: TXN-031948, TXN-003686, TXN-037756 — these are the most
--   interesting. Large anomalous amounts that have not yet settled.
--   A real fraud team would prioritise reviewing pending high-sigma
--   transactions before they complete.
-- Failed: TXN-013545 — Amy Chen, 737K NGN Salary Credit that failed.
--   Could indicate the system's own fraud detection blocked it.
--
-- This query is the foundation of a real fraud detection pipeline.
-- In production it would run automatically every hour, feed into a
-- case management system, and trigger analyst review workflows.
