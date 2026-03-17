-- =============================================================================
-- FILE: 02_data_cleaning.sql
-- PROJECT: Nigerian Bank Transactions Analytics
-- AUTHOR: [Your Name]
-- DATE: 2024
-- DESCRIPTION: Cleaning all 18 data quality issues in the raw transactions data
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ISS-01: DUPLICATE TRANSACTIONS
-- Approach: Before deleting anything, I first want to SEE the duplicates.
-- A professional never runs a DELETE without inspecting what will be removed.
-- I'm looking for rows where the same transaction_id appears more than once.
-- -----------------------------------------------------------------------------

-- 1a. How many duplicate transaction_ids exist?
SELECT 
    transaction_id,
    COUNT(*) AS occurrences
FROM transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;

-- 1b. How many total rows are duplicates?
-- This tells me the exact number I expect to disappear after the DELETE
SELECT 
    COUNT(*) AS total_duplicate_rows
FROM transactions
WHERE transaction_id IN (
    SELECT transaction_id
    FROM transactions
    GROUP BY transaction_id
    HAVING COUNT(*) > 1
);



-- 1c. See the duplicates side by side before touching anything
SELECT 
    transaction_id,
    customer_id,
    amount,
    transaction_date,
    merchant_name,
    notes
FROM transactions
WHERE transaction_id IN (
    SELECT transaction_id
    FROM transactions
    GROUP BY transaction_id
    HAVING COUNT(*) > 1
)
ORDER BY transaction_id
LIMIT 20;


-- 1d. See exactly how many times each duplicate ID appears
-- This explains why we got 1,582 instead of ~246
SELECT 
    transaction_id,
    COUNT(*) AS occurrences
FROM transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 10;


-- 1e. DELETE duplicates — keep only the first occurrence of each transaction_id
-- 
-- HOW THIS WORKS:
-- PostgreSQL gives every row a hidden physical address called "ctid".
-- For each transaction_id, I keep the row with the MINIMUM ctid (the one
-- that arrived first) and delete every other copy.
-- This is the standard PostgreSQL approach — clean, precise, no accidental deletions.

DELETE FROM transactions
WHERE ctid NOT IN (
    SELECT MIN(ctid)
    FROM transactions
    GROUP BY transaction_id
);



-- 1f. Confirm duplicates are gone
SELECT 
    COUNT(*) AS total_transactions_remaining
FROM transactions;

-- Should return exactly: 50000 minus 1582 = 48,418 rows

-- Double check — this should now return zero rows
SELECT 
    transaction_id,
    COUNT(*) AS occurrences
FROM transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1;



-- -----------------------------------------------------------------------------
-- ISS-02: NULL customer_name
-- Rather than guessing a name, I flag it as 'Unknown' so it's visible in reports
-- A NULL would silently disappear from GROUP BY results — 'Unknown' stays visible
-- -----------------------------------------------------------------------------
UPDATE transactions
SET customer_name = 'Unknown'
WHERE customer_name IS NULL;

-- Verify
SELECT COUNT(*) AS remaining_null_names 
FROM transactions 
WHERE customer_name IS NULL;

-- -----------------------------------------------------------------------------
-- ISS-03: NULL category
-- Same logic — 'Uncategorised' is better than NULL for reporting
-- -----------------------------------------------------------------------------
UPDATE transactions
SET category = 'Uncategorised'
WHERE category IS NULL;

-- Verify
SELECT COUNT(*) AS remaining_null_categories
FROM transactions 
WHERE category IS NULL;

-- -----------------------------------------------------------------------------
-- ISS-04: NULL status
-- -----------------------------------------------------------------------------
UPDATE transactions
SET status = 'unknown'
WHERE status IS NULL;

-- Verify
SELECT COUNT(*) AS remaining_null_status
FROM transactions 
WHERE status IS NULL;

-- -----------------------------------------------------------------------------
-- ISS-05: NULL location
-- -----------------------------------------------------------------------------
UPDATE transactions
SET location = 'Unknown'
WHERE location IS NULL;

-- -----------------------------------------------------------------------------
-- ISS-06: Standardise currency — trim spaces, force uppercase
-- 'ngn', 'NGN ', '₦' all become 'NGN'
-- This is critical — a GROUP BY currency right now would return 4 different groups
-- instead of one, silently splitting your totals
-- -----------------------------------------------------------------------------
UPDATE transactions
SET currency = TRIM(UPPER(currency));

-- Handle the ₦ symbol variant
UPDATE transactions
SET currency = 'NGN'
WHERE currency = '₦';

-- Verify — should show only 'NGN'
SELECT DISTINCT currency FROM transactions;

-- -----------------------------------------------------------------------------
-- ISS-07: Standardise transaction_type — force lowercase
-- 'DEBIT', 'Debit', 'debit' all become 'debit'
-- -----------------------------------------------------------------------------
UPDATE transactions
SET transaction_type = LOWER(TRIM(transaction_type));

-- Verify — should show only 'debit' and 'credit'
SELECT DISTINCT transaction_type FROM transactions;

-- -----------------------------------------------------------------------------
-- ISS-08: Standardise status casing
-- -----------------------------------------------------------------------------
UPDATE transactions
SET status = LOWER(TRIM(status));

-- Verify
SELECT DISTINCT status FROM transactions;



-- -----------------------------------------------------------------------------
-- ISS-09: Fix leading/trailing whitespace in customer_name
-- 'Fatima  Aliyu' and '  Adewale' become clean names
-- REGEXP_REPLACE collapses multiple internal spaces into one
-- -----------------------------------------------------------------------------
UPDATE transactions
SET customer_name = TRIM(REGEXP_REPLACE(customer_name, '\s+', ' ', 'g'));

UPDATE customers
SET full_name = TRIM(REGEXP_REPLACE(full_name, '\s+', ' ', 'g'))
WHERE full_name IS NOT NULL;



-- we need to confirm if what we have done is working, or we messed it up.




SELECT DISTINCT currency FROM transactions;


SELECT DISTINCT transaction_type FROM transactions;

SELECT DISTINCT status FROM transactions;


SELECT DISTINCT category FROM transactions ORDER BY category;



-- After running our NULL fixes and casing standardisation, I ran these four
-- DISTINCT checks as a sanity test. A good engineer never assumes an UPDATE
-- worked — you always verify with eyes on the actual data.




-- ISSUE DISCOVERED: Empty strings hiding in status and category
--
-- When I ran the DISTINCT checks above, I noticed row 1 in both status and
-- category was showing as blank — visually empty in DBeaver.
--
-- My first thought was it might just be a display bug. So I added LENGTH()
-- to measure the actual character count of each distinct value.
-- If it was 'unknown' sitting there invisibly, LENGTH() would return 7.
-- If it was truly empty, LENGTH() would return 0.
--
-- Result: LENGTH = 0 — confirmed empty string, not a display issue.
--
-- WHY THIS IS A REAL PROBLEM:
-- In SQL, NULL and '' (empty string) are completely different things.
--   - NULL means "no value was ever recorded"
--   - ''  means "someone recorded nothing — a blank was entered"
-- Our earlier UPDATE used WHERE IS NULL — which correctly caught NULLs
-- but silently skipped the empty strings entirely.
-- This matters because:
--   1. GROUP BY would create a separate nameless group for '' rows,
--      splitting your totals invisibly in any report or dashboard
--   2. WHERE status = 'completed' would exclude '' rows from counts
--   3. A chart built on this data would have an unlabelled segment
--      that is impossible to explain to a stakeholder
-- In a real company this kind of silent data corruption causes wrong
-- business decisions — reports that look fine but are quietly wrong.


SELECT DISTINCT status, LENGTH(status) AS char_length 
FROM transactions 
ORDER BY status;

SELECT DISTINCT category, LENGTH(category ) AS char_length 
FROM transactions 
ORDER BY category ;



-- FIX: Catch both NULL and empty string in one UPDATE
--
-- TRIM(status) = '' handles empty strings and strings that are only spaces
-- IS NULL handles genuine NULLs
-- Using OR means neither can slip through




-- Fix empty strings in status
UPDATE transactions
SET status = 'unknown'
WHERE TRIM(status) = '' OR status IS NULL;

-- Fix empty strings in category  
UPDATE transactions
SET category = 'Uncategorised'
WHERE TRIM(category) = '' OR category IS NULL;



-- FINAL VERIFICATION: Confirm the fix worked
-- Expected result: zero rows with LENGTH = 0 in either column
-- If this comes back clean, these two columns are fully standardised

-- Verify both are clean now
SELECT DISTINCT status, LENGTH(status) AS char_length 
FROM transactions 
ORDER BY status;

SELECT DISTINCT category, LENGTH(category) AS char_length 
FROM transactions 
ORDER BY category;







-- -----------------------------------------------------------------------------
-- ISS-10: MERCHANT NAME STANDARDISATION
-- Before fixing anything, I want to see every unique merchant name in the data.
-- This tells me the full scope of the typo problem across all 49,209 rows.
-- -----------------------------------------------------------------------------

-- How many unique merchant name variants exist right now?
SELECT 
    merchant_name,
    COUNT(*) AS transaction_count
FROM transactions
GROUP BY merchant_name
ORDER BY merchant_name;







-- -----------------------------------------------------------------------------
-- ISS-10: MERCHANT NAME STANDARDISATION — THE FIX
--
-- When I ran the initial DISTINCT check, I found 107 unique merchant name
-- variants in the data. I then ran a frequency analysis grouping by category
-- and merchant_name ordered by COUNT DESC. This showed me a clear pattern:
-- some merchant names appeared thousands of times while others appeared only
-- a handful of times with slightly different spellings.
--
-- The high-frequency version of each name is almost certainly the correct one.
-- The low-frequency variants are typos, casing errors, or formatting differences
-- introduced by different staff entering the same merchant inconsistently.
--
-- I manually reviewed the variants and mapped them to canonical names below.
-- After this fix I will re-run the DISTINCT count to see how many unique
-- merchant names remain — whatever that number is, it should be significantly
-- lower than 107 and every name should look intentional and clean.
--
-- I used CASE WHEN instead of fuzzy matching because:
--   - Every mapping is explicit and auditable
--   - No risk of accidentally merging two different merchants
--   - Any future engineer can read exactly what was changed and why
-- -----------------------------------------------------------------------------

UPDATE transactions
SET merchant_name = CASE

    -- GTBank variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'gt bank transfer', 'gt-bank transfer', 'gtbank transfer',
        'gtbank', 'g.t bank', 'gt bank', 'gt-bank'
    ) THEN 'GTBank Transfer'

    -- Shoprite variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'shoprite', 'shop rite', 'shoprite ng'
    ) THEN 'Shoprite'

    -- Chicken Republic variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'chicken republic', 'chicken-republic', 'chickenrepublic'
    ) THEN 'Chicken Republic'

    -- KFC variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'kfc nigeria', 'kfc', 'kfc nig', 'k.f.c nigeria'
    ) THEN 'KFC Nigeria'

    -- Bolt variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'bolt nigeria', 'bolt', 'bolt ng'
    ) THEN 'Bolt Nigeria'

    -- MTN variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'mtn airtime', 'mtn', 'mtn nigeria'
    ) THEN 'MTN Airtime'

    -- Jumia variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'jumia nigeria', 'jumia', 'jumia ng'
    ) THEN 'Jumia Nigeria'

    -- DSTV variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'dstv', 'dstv nigeria', 'd.s.t.v'
    ) THEN 'DSTV'

    -- Zenith Bank variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'zenith bank transfer', 'zenith transfer',
        'zenith bank', 'zenith-bank'
    ) THEN 'Zenith Bank Transfer'

    -- Netflix variants
    WHEN LOWER(TRIM(merchant_name)) IN (
        'netflix', 'netflix ng'
    ) THEN 'Netflix'

    ELSE merchant_name

END;

-- -----------------------------------------------------------------------------
-- VERIFY: Re-run the distinct count after the fix
-- Before cleaning: 107 variants
-- After cleaning: should be significantly lower — exact number TBD
-- Any remaining variants that look like typos will need a second pass
-- -----------------------------------------------------------------------------
SELECT 
    merchant_name,
    COUNT(*) AS transaction_count
FROM transactions
GROUP BY merchant_name
ORDER BY merchant_name;



-- What merchant names are still suspicious?
-- Low frequency = likely a typo of something more common
SELECT 
    merchant_name,
    COUNT(*) AS times_appeared
FROM transactions
GROUP BY merchant_name
ORDER BY times_appeared ASC;




-- MERCHANT CLEANING RESULT:
-- Before: 107 distinct merchant name variants
-- After first CASE WHEN pass: 69 distinct merchant names
-- 
-- On inspection, all 69 remaining names are legitimate distinct merchants
-- with reasonable transaction frequencies. No further typo variants detected.
-- The 38 variants we collapsed were purely formatting and casing differences
-- introduced by inconsistent data entry — not different businesses.
-- Merchant standardisation is complete.






-- -----------------------------------------------------------------------------
-- ISS-11: ZERO AMOUNT TRANSACTIONS
--
-- Some transactions have amount = '0.00' — these are incomplete or failed
-- records where a transaction was initiated but no value was processed.
-- I am not deleting these — I am flagging them in the notes column so they
-- are visible and excluded from financial analysis without losing the audit trail.
-- Deleting financial records entirely is bad practice — you always want to
-- know a transaction was attempted even if it failed.
-- -----------------------------------------------------------------------------

UPDATE transactions
SET notes = 'ZERO AMOUNT — EXCLUDE FROM ANALYSIS'
WHERE TRIM(amount) = '0.00' OR TRIM(amount) = '0';

-- Verify — how many zero amount transactions exist?
SELECT COUNT(*) AS zero_amount_count
FROM transactions
WHERE TRIM(amount) = '0.00' OR TRIM(amount) = '0';


-- Result: 422 zero amount transactions flagged with 'ZERO AMOUNT — EXCLUDE FROM ANALYSIS'





-- -----------------------------------------------------------------------------
-- ISS-12: FUTURE TRANSACTION DATES
--
-- Some transaction_date values are beyond today's date — clearly a data entry
-- error. I cannot cast these to dates yet since the column is still VARCHAR
-- with mixed formats. Instead I flag them in the notes column for exclusion.
-- I will handle the full date casting in the next step.
-- -----------------------------------------------------------------------------

UPDATE transactions
SET notes = COALESCE(notes || ' | ', '') || 'FUTURE DATE — VERIFY'
WHERE transaction_date LIKE '202[6-9]%'
   OR transaction_date LIKE '20[3-9]%';

-- Verify
SELECT 
    transaction_id,
    transaction_date,
    notes
FROM transactions
WHERE notes LIKE '%FUTURE DATE%'
LIMIT 10;



-- -----------------------------------------------------------------------------
-- ISS-12- continue_001: FUTURE TRANSACTION DATES — revised approach
--
-- My first attempt used LIKE '202[6-9]%' which only catches dates where the
-- year appears at the START of the string — i.e. YYYY-MM-DD format.
-- But our date column has 7 different formats, some starting with the day
-- or month instead. So I need to search for the year appearing ANYWHERE
-- in the string instead.
-- -----------------------------------------------------------------------------

-- First let's see what future-looking dates actually exist
SELECT 
    transaction_date,
    COUNT(*) AS count
FROM transactions
WHERE transaction_date LIKE '%2025%'
   OR transaction_date LIKE '%2026%'
   OR transaction_date LIKE '%2027%'
GROUP BY transaction_date
ORDER BY transaction_date;



-- -----------------------------------------------------------------------------
-- ISS-12- continued_002: FUTURE TRANSACTION DATES — final fix
--
-- Found 79 future-dated transactions spread across all 7 date formats.
-- The year appears in different positions depending on the format, so
-- searching with LIKE '%YEAR%' is the only reliable way to catch all of them
-- regardless of where the year sits in the string.
--
-- Today's date is 2026-03-16. Anything in 2025 that hasn't passed yet,
-- and anything in 2026 or beyond is a future date error.
-- I am flagging rather than deleting — financial records should never be
-- silently removed without investigation.
-- -----------------------------------------------------------------------------

UPDATE transactions
SET notes = COALESCE(notes || ' | ', '') || 'FUTURE DATE — VERIFY'
WHERE transaction_date LIKE '%2025%'
   OR transaction_date LIKE '%2026%'
   OR transaction_date LIKE '%2027%';

-- Verify count
SELECT COUNT(*) AS future_dated_rows
FROM transactions
WHERE notes LIKE '%FUTURE DATE%';


-- Result: 82 rows flagged with 'FUTURE DATE — VERIFY'
-- Note: SELECT preview showed 80 rows but UPDATE caught 82 — 2 additional
-- rows had future years embedded in slightly different string formats.
-- All future-dated records are now flagged for exclusion from analysis.



ALTER TABLE transactions 
ADD COLUMN IF NOT EXISTS amount_clean NUMERIC(15,2);



UPDATE transactions
SET amount_clean = NULLIF(TRIM(amount), 'N/A')::NUMERIC(15,2)
WHERE notes NOT LIKE '%ZERO AMOUNT%';


UPDATE transactions
SET amount_clean = 0.00
WHERE notes LIKE '%ZERO AMOUNT%';



SELECT 
    COUNT(*)                            AS total_rows,
    COUNT(amount_clean)                 AS rows_with_clean_amount,
    COUNT(*) - COUNT(amount_clean)      AS rows_with_null_amount,
    ROUND(AVG(amount_clean), 2)         AS average_transaction,
    MIN(amount_clean)                   AS minimum_amount,
    MAX(amount_clean)                   AS maximum_amount
FROM transactions;




-- ISS-13 RESULT:
-- 49,063 rows successfully cast from VARCHAR to NUMERIC(15,2)
-- 146 rows correctly stored as NULL (were 'N/A' in source data)
-- Average transaction: 139,759 NGN — realistic
-- Range: -993,863 to 999,339 NGN — negative values are reversed transactions













UPDATE transactions
SET amount_clean = -ABS(amount_clean)
WHERE status = 'reversed' 
AND amount_clean > 0;

-- Verify
SELECT 
    status,
    COUNT(*)                    AS count,
    ROUND(SUM(amount_clean), 2) AS total_amount
FROM transactions
WHERE status = 'reversed'
GROUP BY status;



-- ISS-14 RESULT:
-- 1,449 reversed transactions corrected to negative amounts
-- Total reversed value: -213,089,086 NGN
-- All reversals now correctly reduce transaction volume in any sum calculation
















