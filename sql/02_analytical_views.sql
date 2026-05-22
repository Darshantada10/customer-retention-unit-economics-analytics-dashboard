/* ============================================================================
   Script Name: 02_analytical_views.sql
   Description: Advanced Semantic Layer for Power BI 
   Author: Darshan
   Date: May 2026
   Target RDBMS: MS SQL Server 2022

   Views Included:
   1. vw_user_journey (Funnel Tracking with LAG/LEAD)
   2. vw_cohort_retention (Month-over-Month Cohort Heatmap Logic)
   3. vw_unit_economics (CAC vs LTV by Channel)
============================================================================ */

USE EcommerceLifecycleDB;
GO

-- ============================================================================
-- 1. CLICKSTREAM FUNNEL VIEW (Using Window Functions)
-- Proves you can track sequential user behavior, finding exact drop-off points.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_user_journey AS
SELECT 
    u.user_id,
    u.device_type,
    u.acquisition_channel,
    ce.session_id,
    ce.event_name AS current_step,
    ce.event_timestamp,
    -- LEAD tracks the immediate next step the user took in the same session
    LEAD(ce.event_name) OVER (
        PARTITION BY ce.session_id 
        ORDER BY ce.event_timestamp
    ) AS next_step,
    -- Calculate the time spent on the current step before moving forward
    DATEDIFF(SECOND, ce.event_timestamp, LEAD(ce.event_timestamp) OVER (
        PARTITION BY ce.session_id 
        ORDER BY ce.event_timestamp
    )) AS seconds_to_next_step
FROM dbo.clickstream_events ce
JOIN dbo.users u ON ce.user_id = u.user_id;
GO

-- ============================================================================
-- 2. COHORT RETENTION VIEW
-- Maps users to their signup month, then calculates how many months later 
-- they made subsequent purchases. Perfect for a Power BI Matrix heatmap.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_cohort_retention AS
WITH CohortBase AS (
    SELECT 
        user_id,
        -- Lock users to the first day of their signup month
        DATEFROMPARTS(YEAR(signup_date), MONTH(signup_date), 1) AS cohort_month 
    FROM dbo.users
),
UserActivity AS (
    SELECT 
        o.user_id,
        DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS activity_month
    FROM dbo.orders o
)
SELECT 
    cb.cohort_month,
    -- Month 0 = Signup month, Month 1 = Following month, etc.
    DATEDIFF(MONTH, cb.cohort_month, ua.activity_month) AS month_number,
    COUNT(DISTINCT cb.user_id) AS retained_users
FROM CohortBase cb
LEFT JOIN UserActivity ua ON cb.user_id = ua.user_id
GROUP BY 
    cb.cohort_month, 
    DATEDIFF(MONTH, cb.cohort_month, ua.activity_month);
GO

-- We also need the original cohort sizes to calculate the retention percentage
CREATE OR ALTER VIEW dbo.vw_cohort_sizes AS
SELECT 
    DATEFROMPARTS(YEAR(signup_date), MONTH(signup_date), 1) AS cohort_month,
    COUNT(DISTINCT user_id) AS total_users_in_cohort
FROM dbo.users
GROUP BY DATEFROMPARTS(YEAR(signup_date), MONTH(signup_date), 1);
GO

-- ============================================================================
-- 3. UNIT ECONOMICS VIEW (CAC vs LTV)
-- Aggregates marketing spend and total revenue by channel to prove profitability.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_unit_economics AS
WITH Acquisition AS (
    SELECT 
        acquisition_channel,
        COUNT(user_id) AS total_users_acquired
    FROM dbo.users
    GROUP BY acquisition_channel
),
Spend AS (
    SELECT 
        channel,
        SUM(daily_spend) AS total_spend
    FROM dbo.marketing_spend
    GROUP BY channel
),
Revenue AS (
    SELECT 
        u.acquisition_channel,
        SUM(o.revenue) AS total_revenue
    FROM dbo.orders o
    JOIN dbo.users u ON o.user_id = u.user_id
    GROUP BY u.acquisition_channel
)
SELECT 
    a.acquisition_channel,
    ISNULL(s.total_spend, 0) AS total_spend,
    a.total_users_acquired,
    ISNULL(r.total_revenue, 0) AS total_revenue,
    -- Customer Acquisition Cost (CAC)
    CAST(ISNULL(s.total_spend, 0) / NULLIF(a.total_users_acquired, 0) AS DECIMAL(10,2)) AS CAC,
    -- Customer Lifetime Value (LTV)
    CAST(ISNULL(r.total_revenue, 0) / NULLIF(a.total_users_acquired, 0) AS DECIMAL(10,2)) AS LTV,
    -- LTV:CAC Ratio (The ultimate executive metric)
    CAST((ISNULL(r.total_revenue, 0) / NULLIF(a.total_users_acquired, 0)) / 
         NULLIF((ISNULL(s.total_spend, 0) / NULLIF(a.total_users_acquired, 0)), 0) AS DECIMAL(10,2)) AS ltv_to_cac_ratio
FROM Acquisition a
LEFT JOIN Spend s ON a.acquisition_channel = s.channel
LEFT JOIN Revenue r ON a.acquisition_channel = r.acquisition_channel;
GO

PRINT 'Phase 2 complete. Analytical Views successfully created.';