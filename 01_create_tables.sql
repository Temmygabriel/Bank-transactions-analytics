-- =============================================================================
-- FILE: 01_create_tables.sql
-- PROJECT: Nigerian Bank Transactions Analytics
-- AUTHOR: [Temmygabriel]
-- DATE: 16-03-2026
-- DESCRIPTION: Initial schema creation for raw data ingestion
-- =============================================================================

-- -----------------------------------------------------------------------------
-- WHY ARE SOME COLUMNS VARCHAR INSTEAD OF THEIR "CORRECT" TYPE?
--
-- Before I even opened this dataset I knew it would be messy — it came from
-- a banking system where multiple people entered records over 3 years with
-- no enforced validation. My first instinct was to define amount as NUMERIC
-- and transaction_date as DATE, but that would cause the entire import to
-- FAIL the moment PostgreSQL hit a single "N/A" in the amount column or a
-- "Jan 5 2024" where it expected "2024-01-05".
--
-- The safer and more professional approach is a two-stage load:
--   Stage 1 (this file)  → ingest everything as VARCHAR, nothing gets rejected
--   Stage 2 (03_clean)   → validate, cast, and fix inside the database
--
-- This mirrors how real ETL pipelines work in production. You never trust
-- source data enough to cast it on arrival. You land it raw, inspect it,
-- then transform it with full control and visibility over what breaks.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS customers (
    customer_id     VARCHAR(12)  PRIMARY KEY,
    full_name       VARCHAR(100),           -- nullable: some records have no name on file
    email           VARCHAR(100),           -- nullable: not all customers provided email
    phone           VARCHAR(15),
    city            VARCHAR(50),
    account_type    VARCHAR(20),
    account_number  VARCHAR(20),            -- nullable: a few records are missing this
    join_date       VARCHAR(15),            -- stored as text: will cast to DATE in cleaning
    credit_score    INTEGER                 -- nullable: NULL means not yet assessed
);

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id    VARCHAR(20),
    customer_id       VARCHAR(12),
    customer_name     VARCHAR(100),         -- nullable + messy: inconsistent casing, extra spaces
    account_number    VARCHAR(20),          -- nullable: some transactions lack this
    transaction_date  VARCHAR(30),          -- VARCHAR not DATE: 7 different formats in source data
    amount            VARCHAR(20),          -- VARCHAR not NUMERIC: source contains "N/A" values
    currency          VARCHAR(10),          -- VARCHAR: mixed casing (NGN, ngn, ₦, "NGN ")
    transaction_type  VARCHAR(20),          -- VARCHAR: mixed casing (debit, DEBIT, Debit)
    merchant_name     VARCHAR(100),         -- messy: same merchant has 5+ spelling variants
    category          VARCHAR(50),          -- nullable: ~4% of rows have no category
    status            VARCHAR(20),          -- nullable + messy: NULL, uppercase variants exist
    location          VARCHAR(50),          -- nullable: ~3% of rows missing location
    notes             VARCHAR(100)          -- used to flag suspected duplicates on import
);