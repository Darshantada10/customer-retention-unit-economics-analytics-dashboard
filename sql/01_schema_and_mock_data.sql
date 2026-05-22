/* ============================================================================
   Script Name: 01_schema_and_mock_data.sql
   Description: Optimized High-Volume DDL & Set-Based Synthetic Data Generation
   Author: Darshan
   Date: May 2026
   Target RDBMS: MS SQL Server
   Scale: 100,000+ Rows across tables (Production Simulation)
============================================================================ */

-- 0. Create and Use Database
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'EcommerceLifecycleDB')
BEGIN
    CREATE DATABASE EcommerceLifecycleDB;
END;
GO

USE EcommerceLifecycleDB;
GO

-- 1. Drop existing tables for clean execution (Order matters for Foreign Keys)
IF OBJECT_ID('dbo.orders', 'U') IS NOT NULL DROP TABLE dbo.orders;
IF OBJECT_ID('dbo.clickstream_events', 'U') IS NOT NULL DROP TABLE dbo.clickstream_events;
IF OBJECT_ID('dbo.users', 'U') IS NOT NULL DROP TABLE dbo.users;
IF OBJECT_ID('dbo.marketing_spend', 'U') IS NOT NULL DROP TABLE dbo.marketing_spend;

-- 2. Create Schema
CREATE TABLE dbo.users (
    user_id INT IDENTITY(1,1) PRIMARY KEY,
    signup_date DATE NOT NULL,
    acquisition_channel VARCHAR(50) NOT NULL,
    device_type VARCHAR(50) NOT NULL
);

CREATE TABLE dbo.clickstream_events (
    event_id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT NOT NULL FOREIGN KEY REFERENCES dbo.users(user_id),
    session_id VARCHAR(50) NOT NULL,
    event_timestamp DATETIME NOT NULL,
    event_name VARCHAR(50) NOT NULL
);

CREATE TABLE dbo.orders (
    order_id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT NOT NULL FOREIGN KEY REFERENCES dbo.users(user_id),
    order_date DATE NOT NULL,
    revenue DECIMAL(10,2) NOT NULL
);

CREATE TABLE dbo.marketing_spend (
    spend_id INT IDENTITY(1,1) PRIMARY KEY,
    spend_date DATE NOT NULL,
    channel VARCHAR(50) NOT NULL,
    daily_spend DECIMAL(10,2) NOT NULL
);

SET NOCOUNT ON;

-- 3. High-Performance Set-Based Data Generation
-- Generate a base tally/numbers view of 10,000 numbers using cross joins
WITH N1 (n) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1), -- 10
     N2 (n) AS (SELECT 1 FROM N1 a CROSS JOIN N1 b), -- 100
     N3 (n) AS (SELECT 1 FROM N2 a CROSS JOIN N2 b), -- 10,000
     Tally (t_id) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM N3)

-- A. Populate 10,000 Users instantly
INSERT INTO dbo.users (signup_date, acquisition_channel, device_type)
SELECT 
    DATEADD(DAY, ABS(CHECKSUM(SHA1(CAST(t_id AS VARCHAR)))) % 90, '2026-01-01') AS signup_date,
    CASE 
        WHEN t_id % 3 = 0 THEN 'Google Ads'
        WHEN t_id % 3 = 1 THEN 'Facebook Ads'
        ELSE 'Organic Search'
    END AS acquisition_channel,
    CASE 
        WHEN ABS(CHECKSUM(SHA1(CAST(t_id * 2 AS VARCHAR)))) % 10 < 6 THEN 'Mobile'
        ELSE 'Desktop'
    END AS device_type
FROM Tally;

-- B. Populate Marketing Spend (Daily entries for Q1 2026)
DECLARE @StartDate DATE = '2026-01-01';
DECLARE @EndDate DATE = '2026-03-31';
DECLARE @CurrentDate DATE = @StartDate;

WHILE @CurrentDate <= @EndDate
BEGIN
    INSERT INTO dbo.marketing_spend (spend_date, channel, daily_spend)
    VALUES 
        (@CurrentDate, 'Google Ads', ROUND(500 + (ABS(CHECKSUM(NEWID())) % 300), 2)),
        (@CurrentDate, 'Facebook Ads', ROUND(600 + (ABS(CHECKSUM(NEWID())) % 400), 2)),
        (@CurrentDate, 'Organic Search', 0.00);

    SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
END;

-- C. Populate 15,000+ Orders (Set-based, with intentional higher retention trends for Organic Search)
INSERT INTO dbo.orders (user_id, order_date, revenue)
SELECT 
    u.user_id,
    DATEADD(DAY, v.day_offset, u.signup_date) AS order_date,
    ROUND(45.00 + (ABS(CHECKSUM(SHA1(CAST(u.user_id * v.day_offset AS VARCHAR)))) % 150), 2) AS revenue
FROM dbo.users u
CROSS APPLY (
    -- Initial purchase for everyone
    SELECT 0 AS day_offset
    UNION ALL
    -- Second purchase for 60% of Organic Search, but only 25% of Paid Ads
    SELECT ABS(CHECKSUM(SHA1(CAST(u.user_id AS VARCHAR)))) % 25 + 5
    WHERE (u.acquisition_channel = 'Organic Search' AND ABS(CHECKSUM(SHA1(CAST(u.user_id AS VARCHAR)))) % 10 < 6)
       OR (u.acquisition_channel != 'Organic Search' AND ABS(CHECKSUM(SHA1(CAST(u.user_id AS VARCHAR)))) % 10 < 3)
    UNION ALL
    -- Third purchase for highly retained organic users
    SELECT ABS(CHECKSUM(SHA1(CAST(u.user_id * 2 AS VARCHAR)))) % 25 + 35
    WHERE u.acquisition_channel = 'Organic Search' AND ABS(CHECKSUM(SHA1(CAST(u.user_id * 3 AS VARCHAR)))) % 10 < 3
) v;

-- D. Populate 85,000+ Clickstream Events (The Web Funnel Logs)
-- Step 1: All 10,000 users hit Home Page
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT 
    user_id,
    CONCAT('SES-', user_id, '-1'),
    CAST(signup_date AS DATETIME) AS event_timestamp,
    'page_view_home'
FROM dbo.users;

-- Step 2: 85% view a product (8,500 rows)
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT user_id, session_id, DATEADD(SECOND, 45, event_timestamp), 'page_view_product'
FROM dbo.clickstream_events 
WHERE event_name = 'page_view_home' AND user_id % 20 < 17;

-- Step 3: 50% add to cart (4,250 rows)
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT user_id, session_id, DATEADD(SECOND, 120, event_timestamp), 'add_to_cart'
FROM dbo.clickstream_events 
WHERE event_name = 'page_view_product' AND user_id % 2 = 0;

-- Step 4: 80% start checkout (3,400 rows)
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT user_id, session_id, DATEADD(SECOND, 90, event_timestamp), 'checkout_start'
FROM dbo.clickstream_events 
WHERE event_name = 'add_to_cart' AND user_id % 5 < 4;

-- Step 5: Purchase Phase (Engineered Mobile Drop-off)
-- Desktop converts at 85%, Mobile drops off severely and converts at only 35%
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT e.user_id, e.session_id, DATEADD(SECOND, 180, e.event_timestamp), 'purchase'
FROM dbo.clickstream_events e
JOIN dbo.users u ON e.user_id = u.user_id
WHERE e.event_name = 'checkout_start'
  AND (
      (u.device_type = 'Desktop' AND e.user_id % 100 < 85) OR
      (u.device_type = 'Mobile' AND e.user_id % 100 < 35)
  );

-- Repeat visitor sessions to simulate realistic lookups
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT 
    user_id,
    CONCAT('SES-', user_id, '-2'),
    DATEADD(DAY, 14, CAST(signup_date AS DATETIME)),
    'page_view_home'
FROM dbo.users
WHERE user_id % 3 = 0;

PRINT 'Production-scale schema created. 100,000+ data rows successfully populated in EcommerceLifecycleDB.';