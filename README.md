# Nigerian Bank Transactions Analytics

An end-to-end data analytics project simulating a real-world banking data pipeline — from raw messy data to a live cloud database, cleaned with SQL and visualised in Power BI.

---

## Project Overview

This project replicates the kind of work a junior data analyst or data engineer would encounter on their first day at a Nigerian bank or fintech company. The dataset is intentionally messy — duplicates, inconsistent formats, NULL values, typos, wrong data types — because that is what real data looks like.

The project covers the full analytics lifecycle:

- **Ingest** raw messy data into a cloud PostgreSQL database
- **Clean** 18 documented data quality issues using SQL
- **Analyse** the cleaned data to answer real business questions
- **Visualise** key insights in a Power BI dashboard

---

## Tech Stack

| Tool | Purpose |
|---|---|
| PostgreSQL 17 (Aiven) | Cloud-hosted relational database |
| DBeaver | SQL client for query development |
| Power BI Desktop | Dashboard and visualisation |
| Python + Faker | Synthetic data generation |

---

## Dataset

- **50,000 transactions** spanning 3 years (2022–2024)
- **800 customers** across 18 Nigerian cities
- **14 spending categories** and 69 unique merchants
- Synthetically generated to mirror realistic Nigerian banking data

### Data quality issues deliberately embedded

| Issue | Description |
|---|---|
| Duplicate transactions | ~800 duplicate rows scattered throughout |
| Inconsistent date formats | 7 different formats in one column |
| Merchant name typos | GTBank / GT Bank / GT-Bank / G.T Bank |
| NULL values | Names, categories, status, location |
| Empty strings | '' treated differently from NULL |
| Wrong data types | Amount stored as VARCHAR containing 'N/A' |
| Casing inconsistencies | ngn / NGN / ₦, debit / DEBIT / Debit |
| Future dates | Data entry errors beyond today's date |
| Wrong-sign amounts | Reversed transactions with positive values |
| Zero amounts | Incomplete or failed transaction records |

---

## Project Structure

```
bank-transactions-analytics/
│
├── sql/
│   ├── 01_create_tables.sql       # Schema with documented design decisions
│   ├── 02_data_cleaning.sql       # 18 data quality fixes with full comments
│   ├── 03_analysis.sql            # 8 business intelligence queries
│   └── 04_views.sql               # 6 reusable views for reporting
│
├── bank_transactions_dashboard.pbix   # Power BI dashboard
└── README.md
```

---

## SQL Scripts

### 01 — Create tables
Defines the raw ingestion schema. Intentionally uses VARCHAR for columns like `amount` and `transaction_date` because the source data contains values like 'N/A' and mixed date formats that would cause a typed import to fail. This mirrors the two-stage ETL pattern used in production pipelines — land raw, clean in place.

### 02 — Data cleaning
Systematically fixes all 18 data quality issues. Every fix is documented with a comment explaining what the problem is, why it matters, and what approach was chosen. Key techniques used:

- `DELETE` with `ctid` for duplicate removal
- `TRIM()` and `REGEXP_REPLACE()` for whitespace cleaning
- `NULLIF()` and `CAST` for type conversion
- `CASE WHEN` for merchant name standardisation
- `COALESCE` with multiple `TO_DATE()` patterns for date standardisation
- `ALTER TABLE ... ADD COLUMN` for clean typed columns alongside raw originals

### 03 — Analysis
Eight business intelligence queries answering real management questions:

| Query | Business question | Key technique |
|---|---|---|
| 1 | Where is the money going? | GROUP BY, window % |
| 2 | How has spending changed over time? | DATE_TRUNC, monthly trends |
| 3 | Who are the highest value customers? | JOIN, aggregation |
| 4 | What is our failure rate? | Status analysis, percentages |
| 5 | Which merchants get the most business? | COUNT DISTINCT, TOP N |
| 6 | Do account types spend differently? | LEFT JOIN, COALESCE |
| 7 | Running total per customer | PARTITION BY, OVER, ROWS |
| 8 | Which transactions look suspicious? | CTE, STDDEV, 3-sigma rule |

### 04 — Views
Six reusable views that abstract the cleaning logic away from the analysis layer. Any analyst or BI tool can query clean, reliable data without knowing about the underlying messiness.

| View | Purpose |
|---|---|
| `vw_clean_transactions` | Foundation view — single source of truth |
| `vw_category_summary` | Pre-aggregated spend by category |
| `vw_monthly_summary` | Monthly debit and credit totals |
| `vw_customer_summary` | Full transaction profile per customer |
| `vw_merchant_summary` | Spend and reach metrics per merchant |
| `vw_flagged_transactions` | Data quality flags and fraud anomalies |

---

## Power BI Dashboard

The dashboard connects live to the Aiven PostgreSQL database and visualises:

- **KPI cards** — total transactions, total spend, avg transaction value, flagged count
- **Spending by category** — horizontal bar chart ranked by total NGN volume
- **Monthly trend** — line chart showing 36 months of debit activity
- **Transaction status breakdown** — donut chart showing completion rate
- **Top 10 customers** — ranked by total debit spend with city and account type
- **Top merchants treemap** — showing merchant dominance by transaction volume

---

## Key Findings

- **Housing** is the largest spending category at 18.38% of total volume (637M NGN) driven by rent, estate fees and property agency payments averaging 250,000 NGN per transaction
- **83.76% of transactions completed** successfully — meaning 1 in 6 transactions encounters a problem, representing 544M NGN sitting in pending or failed states
- **Monthly spend is remarkably stable** at 80M–120M NGN throughout 2022–2024 with May consistently performing strongest across all three years
- **Business accounts** lead total spend at 911M NGN despite identical transaction counts to other account types
- **20+ transactions** flagged by the 3-sigma fraud detection model with sigma scores above 5.5, all warranting manual review

---

## How to Run This Project

### Prerequisites
- PostgreSQL database (Aiven free tier or any PostgreSQL 14+)
- DBeaver or any PostgreSQL-compatible SQL client
- Power BI Desktop (for the dashboard)

### Steps
1. Clone this repository
2. Run `01_create_tables.sql` to create the schema
3. Load your data into the `transactions` and `customers` tables
4. Run `02_data_cleaning.sql` to clean the data
5. Run `03_analysis.sql` to reproduce the analysis queries
6. Run `04_views.sql` to create the reporting views
7. Open `bank_transactions_dashboard.pbix` and update the data source connection to your own PostgreSQL instance

---

## Lessons Learned

- **NULL and empty string are not the same thing** in SQL. `WHERE column IS NULL` will silently miss empty string `''` values, causing incorrect aggregations in reports.
- **Never cast on arrival.** Landing data as VARCHAR and cleaning in place is safer than defining strict types upfront on messy source data.
- **LEFT JOIN over INNER JOIN** for analytical queries — INNER JOIN silently drops unmatched rows which can exclude important data from reports without any error or warning.
- **Date format inconsistency is one of the most common real-world data problems.** The `COALESCE` + `TO_DATE()` pattern with regex matching is the reliable production approach.
- **The 3-sigma rule** for anomaly detection is a simple but effective starting point for fraud flagging that requires no machine learning — just standard SQL window functions.

---

## Author

**Temmygabriel**
[github.com/Temmygabriel](https://github.com/Temmygabriel)
