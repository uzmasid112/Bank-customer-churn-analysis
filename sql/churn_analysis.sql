/* =====================================================================
   Bank Customer Churn Analysis (SQL Server / T-SQL)
   Author:  Uzma Siddiqui
   Data:    Kaggle "Churn Modelling" dataset, 10,000 customers
   Purpose: Find out who is leaving the bank, why, and which current
            customers the retention team should call first.

   Sections
     1. Set up the database and load the data
     2. Data quality checks
     3. Overall churn
     4. Churn by customer group
     5. How leavers differ from stayers
     6. Risk score (saved as a view)
     7. Deeper analysis with window functions
     8. Retention call list
   ===================================================================== */


/* ---------------------------------------------------------------------
   1. Set up the database and load the data
   --------------------------------------------------------------------- */

CREATE DATABASE BankChurn;
GO

USE BankChurn;
GO

CREATE TABLE dbo.customers (
    RowNumber       INT,
    CustomerId      INT PRIMARY KEY,
    Surname         NVARCHAR(50),
    CreditScore     INT,
    Geography       NVARCHAR(20),
    Gender          NVARCHAR(10),
    Age             INT,
    Tenure          INT,
    Balance         DECIMAL(12, 2),
    NumOfProducts   INT,
    HasCrCard       INT,
    IsActiveMember  INT,
    EstimatedSalary DECIMAL(12, 2),
    Exited          INT
);
GO

-- Update the path below to where data/Churn_Modelling.csv is saved on your computer
BULK INSERT dbo.customers
FROM 'C:\path\to\bank-customer-churn-analysis\data\Churn_Modelling.csv'
WITH (
    FORMAT          = 'CSV',
    FIRSTROW        = 2,      -- row 1 is the header
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0a'  -- line feed
);
GO


/* ---------------------------------------------------------------------
   2. Data quality checks
   Business question: are there gaps or mistakes that would make the
   answers wrong?
   --------------------------------------------------------------------- */

-- Row count (expect 10,000)
SELECT COUNT(*) AS total_customers
FROM dbo.customers;

-- Column names and data types
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'customers';

-- Preview the first 10 rows
SELECT TOP 10 *
FROM dbo.customers;

-- Missing values in key columns
SELECT
    COUNT(*) - COUNT(CreditScore) AS missing_credit,
    COUNT(*) - COUNT(Balance)     AS missing_balance,
    COUNT(*) - COUNT(Age)         AS missing_age
FROM dbo.customers;

-- Duplicate customers (IDs listed more than once)
-- WHERE filters rows before grouping; HAVING filters groups after grouping.
SELECT CustomerId, COUNT(*) AS times_listed
FROM dbo.customers
GROUP BY CustomerId
HAVING COUNT(*) > 1;

-- Customers with a zero balance
SELECT
    COUNT(*) AS zero_balance,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dbo.customers), 1) AS pct
FROM dbo.customers
WHERE Balance = 0;

-- Finding: no missing values and no duplicates. 3,617 customers (36.2%)
-- hold a zero balance. This is not an error; they likely hold only a
-- credit card and keep no savings with the bank.


/* ---------------------------------------------------------------------
   3. Overall churn
   Business question: what share of customers left the bank?
   --------------------------------------------------------------------- */

SELECT
    COUNT(*)                         AS customers,
    SUM(Exited)                      AS leavers,
    ROUND(AVG(Exited * 1.0) * 100, 2) AS churn_pct
FROM dbo.customers;

-- Finding: 10,000 customers, 2,037 leavers, 20.37% churn.
-- Exited is 0 or 1, so SUM counts leavers and AVG gives the churn rate.
-- Exited is an INT, so it is multiplied by 1.0 to avoid integer division.


/* ---------------------------------------------------------------------
   4. Churn by customer group
   --------------------------------------------------------------------- */

-- 4a. Country
-- Business question: is churn bank-wide, or concentrated in one market?
SELECT
    Geography,
    COUNT(*)                         AS customers,
    SUM(Exited)                      AS leavers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM dbo.customers
GROUP BY Geography
ORDER BY churn_pct DESC;

-- Finding: Germany loses about 1 in 3 customers (32.4%), double France
-- (16.2%) and Spain (16.7%).

-- 4b. Gender
-- Business question: do women or men leave more often?
SELECT
    Gender,
    COUNT(*)                         AS customers,
    SUM(Exited)                      AS leavers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM dbo.customers
GROUP BY Gender;

-- Finding: Female 25.1%, Male 16.5%.

-- 4c. Activity
-- Business question: do inactive customers leave more often?
-- CASE WHEN turns the 0/1 code into a readable label.
SELECT
    CASE WHEN IsActiveMember = 1 THEN 'Active' ELSE 'Inactive' END AS status,
    COUNT(*)                         AS customers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM dbo.customers
GROUP BY IsActiveMember;

-- Finding: Active 14.3%, Inactive 26.9%.

-- 4d. Age group
-- Business question: which age groups are most likely to leave?
-- The age group is built in a CTE first, so it can be grouped on.
WITH labelled AS (
    SELECT
        CASE
            WHEN Age <= 30 THEN '18-30'
            WHEN Age <= 45 THEN '31-45'
            WHEN Age <= 60 THEN '46-60'
            ELSE '61+'
        END AS age_group,
        Exited
    FROM dbo.customers
)
SELECT
    age_group,
    COUNT(*)                         AS customers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM labelled
GROUP BY age_group
ORDER BY age_group;

-- Finding: customers aged 46-60 leave at 51.1%, about 7 times the rate
-- of customers aged 18-30 (7.5%).

-- 4e. Number of products
-- Business question: the bank assumes more products = more loyalty. Is that true?
SELECT
    NumOfProducts,
    COUNT(*)                         AS customers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM dbo.customers
GROUP BY NumOfProducts
ORDER BY NumOfProducts;

-- Finding: 2 products is the sweet spot (7.6% churn). Customers with
-- 3 products (82.7%) or 4 products (100%) almost all leave, but this is
-- a small group of 326 customers.


/* ---------------------------------------------------------------------
   5. How leavers differ from stayers
   Business question: are we losing our wealthiest customers? Do credit
   score or salary explain who leaves?
   --------------------------------------------------------------------- */

SELECT
    CASE WHEN Exited = 1 THEN 'Left' ELSE 'Stayed' END AS status,
    COUNT(*)                         AS customers,
    ROUND(AVG(Age * 1.0), 1)         AS avg_age,
    ROUND(AVG(Balance), 0)           AS avg_balance,
    ROUND(AVG(EstimatedSalary), 0)   AS avg_salary,
    ROUND(AVG(CreditScore * 1.0), 1) AS avg_credit
FROM dbo.customers
GROUP BY Exited
ORDER BY Exited;

-- Finding: leavers are about 7 years older and hold about 18,000 more
-- in their accounts. Salary and credit score are almost the same in both
-- groups, so they do not explain churn.


/* ---------------------------------------------------------------------
   6. Risk score
   Business question: can we score every customer's risk of leaving?
   One point for each warning sign found above:
     +1 aged 46-60   +1 holds 3+ products   +1 inactive   +1 Germany
   Saved as a view so later queries (and Power BI) can use RiskPoints
   like a normal column.
   --------------------------------------------------------------------- */

DROP VIEW IF EXISTS dbo.customers_scored;
GO

CREATE VIEW dbo.customers_scored AS
SELECT
    *,
    (  CASE WHEN Age BETWEEN 46 AND 60   THEN 1 ELSE 0 END
     + CASE WHEN NumOfProducts >= 3      THEN 1 ELSE 0 END
     + CASE WHEN IsActiveMember = 0      THEN 1 ELSE 0 END
     + CASE WHEN Geography = 'Germany'   THEN 1 ELSE 0 END
    ) AS RiskPoints
FROM dbo.customers;
GO

-- Test the score: churn rate by number of risk points
SELECT
    RiskPoints,
    COUNT(*)                         AS customers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM dbo.customers_scored
GROUP BY RiskPoints
ORDER BY RiskPoints;

-- Group the points into Low / Medium / High
WITH levels AS (
    SELECT
        CASE
            WHEN RiskPoints <= 1 THEN 'Low'
            WHEN RiskPoints = 2  THEN 'Medium'
            ELSE 'High'
        END AS risk_level,
        Exited
    FROM dbo.customers_scored
)
SELECT
    risk_level,
    COUNT(*)                         AS customers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM levels
GROUP BY risk_level
ORDER BY churn_pct;

-- Finding: Low 12.2%, Medium 43.0%, High 84.6%. A simple 4-point rule
-- separates customers who stay from customers who leave.


/* ---------------------------------------------------------------------
   7. Deeper analysis with window functions
   A window function calculates across a group of rows but keeps every
   row:  FUNCTION() OVER (PARTITION BY ... ORDER BY ...)
   --------------------------------------------------------------------- */

-- 7a. Each country compared with the bank average
-- Business question: how far above or below average is each country, and
-- does each country cause its fair share of the losses?
WITH country AS (
    SELECT
        Geography,
        COUNT(*)    AS customers,
        SUM(Exited) AS leavers
    FROM dbo.customers
    GROUP BY Geography
)
SELECT
    Geography,
    customers,
    leavers,
    ROUND(100.0 * leavers / customers, 1)                                 AS churn_pct,
    ROUND(100.0 * SUM(leavers) OVER () / SUM(customers) OVER (), 1)       AS overall_pct,
    ROUND(100.0 * leavers / customers
          - 100.0 * SUM(leavers) OVER () / SUM(customers) OVER (), 1)     AS gap_vs_overall,
    ROUND(100.0 * customers / SUM(customers) OVER (), 1)                  AS pct_of_customers,
    ROUND(100.0 * leavers / SUM(leavers) OVER (), 1)                      AS pct_of_leavers
FROM country
ORDER BY churn_pct DESC;

-- 7b. Rank the riskiest segments (age group x country)
-- Business question: if the retention team can focus on only a few
-- segments, which come first?
WITH labelled AS (
    SELECT
        CASE
            WHEN Age <= 30 THEN '18-30'
            WHEN Age <= 45 THEN '31-45'
            WHEN Age <= 60 THEN '46-60'
            ELSE '61+'
        END AS age_group,
        Geography,
        Exited
    FROM dbo.customers
),
segments AS (
    SELECT
        age_group,
        Geography,
        COUNT(*)                         AS customers,
        ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
    FROM labelled
    GROUP BY age_group, Geography
)
SELECT TOP 5
    age_group,
    Geography,
    customers,
    churn_pct,
    RANK() OVER (ORDER BY churn_pct DESC) AS risk_rank
FROM segments
ORDER BY risk_rank;

-- Finding: Germans aged 46-60 leave at 67%, two out of three. The age
-- risk and the Germany risk add together.

-- 7c. Top 3 customers to call in each country
-- Business question: give each country's retention team a top-3 list of
-- at-risk customers who have not left yet and hold the most money.
WITH at_risk AS (
    SELECT
        CustomerId, Surname, Geography, Age, Balance, RiskPoints,
        ROW_NUMBER() OVER (
            PARTITION BY Geography     -- restart numbering for each country
            ORDER BY Balance DESC      -- biggest balance gets number 1
        ) AS rank_in_country
    FROM dbo.customers_scored
    WHERE Exited = 0
      AND RiskPoints >= 2
      AND Balance > 100000
)
SELECT *
FROM at_risk
WHERE rank_in_country <= 3
ORDER BY Geography, rank_in_country;

-- 7d. Running total of balance on the call list
-- Business question: if we call the biggest accounts first, how many calls
-- until we have covered half of the money at risk?
WITH call_list AS (
    SELECT CustomerId, Geography, Balance
    FROM dbo.customers_scored
    WHERE Exited = 0 AND RiskPoints >= 2 AND Balance > 100000
)
SELECT
    CustomerId,
    Geography,
    Balance,
    ROW_NUMBER() OVER (ORDER BY Balance DESC) AS call_order,
    SUM(Balance) OVER (ORDER BY Balance DESC
                       ROWS UNBOUNDED PRECEDING) AS running_total,
    ROUND(100.0 * SUM(Balance) OVER (ORDER BY Balance DESC
                                     ROWS UNBOUNDED PRECEDING)
          / SUM(Balance) OVER (), 1)             AS running_pct
FROM call_list
ORDER BY call_order;

-- Finding: calling the 309 biggest at-risk accounts covers half of the
-- 94.8M at risk. This turns the list into a staffing plan.

-- 7e. Churn by balance quarter (customers with a balance only)
-- Business question: leavers hold more money on average. Where exactly?
WITH with_quarter AS (
    SELECT
        Balance,
        Exited,
        NTILE(4) OVER (ORDER BY Balance) AS balance_quarter
    FROM dbo.customers
    WHERE Balance > 0              -- leave out the 3,617 zero balances
)
SELECT
    balance_quarter,
    COUNT(*)                         AS customers,
    MIN(Balance)                     AS from_balance,
    MAX(Balance)                     AS to_balance,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM with_quarter
GROUP BY balance_quarter
ORDER BY balance_quarter;

-- Finding: churn peaks among customers holding about 100K to 140K,
-- the middle of the range, not the very richest.

-- 7f. Zero balance vs. has a balance
WITH grouped AS (
    SELECT
        CASE WHEN Balance = 0 THEN 'Zero balance' ELSE 'Has balance' END AS grp,
        Exited
    FROM dbo.customers
)
SELECT
    grp,
    COUNT(*)                         AS customers,
    ROUND(AVG(Exited * 1.0) * 100, 1) AS churn_pct
FROM grouped
GROUP BY grp;

-- Finding: Has balance 24.1%, Zero balance 13.8%. Customers with money
-- in the bank leave more often than those without.


/* ---------------------------------------------------------------------
   8. Retention call list
   Business question: how many current customers should we call, and how
   much money are we protecting?
   Rule: still a customer, 2+ warning signs, balance over 100,000.
   --------------------------------------------------------------------- */

-- Size of the call list
SELECT
    COUNT(*)     AS customers_to_call,
    SUM(Balance) AS money_at_risk
FROM dbo.customers_scored
WHERE Exited = 0
  AND RiskPoints >= 2
  AND Balance > 100000;

-- Finding: 713 customers holding 94.8M.

-- Split by country
SELECT
    Geography,
    COUNT(*)     AS customers_to_call,
    SUM(Balance) AS money_at_risk
FROM dbo.customers_scored
WHERE Exited = 0 AND RiskPoints >= 2 AND Balance > 100000
GROUP BY Geography
ORDER BY money_at_risk DESC;

-- Full call list, biggest balances first (feeds the Power BI Action Plan page)
SELECT
    CustomerId, Surname, Geography, Gender, Age, Balance,
    NumOfProducts, IsActiveMember, RiskPoints
FROM dbo.customers_scored
WHERE Exited = 0 AND RiskPoints >= 2 AND Balance > 100000
ORDER BY Balance DESC;
