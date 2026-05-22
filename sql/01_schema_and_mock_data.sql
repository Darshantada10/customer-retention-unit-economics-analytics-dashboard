/* ============================================================================
   Script Name: 01_schema_and_mock_data.sql
   Description: DDL for Customer Lifecycle Analytics and Synthetic Data Generation
   Author: Darshan
   Date: May 2026
   Target RDBMS: MS SQL Server

   Architecture:
   1. users (Dimension) - Core user attributes and acquisition channels.
   2. clickstream_events (Fact) - Sequential website journey logs.
   3. orders (Fact) - Transactional revenue data.
   4. marketing_spend (Fact) - Daily ad spend for CAC calculation.
============================================================================ */

-- 1. Drop existing tables for clean execution
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
    event_name VARCHAR(50) NOT NULL -- 'page_view_home', 'page_view_product', 'add_to_cart', 'checkout_start', 'purchase'
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

-- 3. Synthetic Data Generation (Simulating 3 months of data)
SET NOCOUNT ON;

-- A. Generate Marketing Spend
DECLARE @StartDate DATE = '2026-01-01';
DECLARE @EndDate DATE = '2026-03-31';
DECLARE @CurrentDate DATE = @StartDate;

WHILE @CurrentDate <= @EndDate
BEGIN
    INSERT INTO dbo.marketing_spend (spend_date, channel, daily_spend)
    VALUES 
        (@CurrentDate, 'Google Ads', ROUND(RAND() * 500 + 500, 2)),
        (@CurrentDate, 'Facebook Ads', ROUND(RAND() * 400 + 600, 2)),
        (@CurrentDate, 'Organic Search', 0.00); -- SEO has 0 direct daily ad spend

    SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
END;

-- B. Generate Users & Orders (Engineered with specific business logic)
DECLARE @UserCounter INT = 1;
DECLARE @TotalUsers INT = 1500;
DECLARE @SignupDate DATE;
DECLARE @Channel VARCHAR(50);
DECLARE @Device VARCHAR(50);
DECLARE @RandVal FLOAT;

WHILE @UserCounter <= @TotalUsers
BEGIN
    -- Random Signup Date between Jan 1 and Mar 31
    SET @SignupDate = DATEADD(DAY, ABS(CHECKSUM(NEWID()) % 90), '2026-01-01');
    
    -- Assign Channel
    SET @RandVal = RAND();
    IF @RandVal < 0.4 SET @Channel = 'Google Ads';
    ELSE IF @RandVal < 0.8 SET @Channel = 'Facebook Ads';
    ELSE SET @Channel = 'Organic Search';

    -- Assign Device
    IF RAND() < 0.6 SET @Device = 'Mobile';
    ELSE SET @Device = 'Desktop';

    INSERT INTO dbo.users (signup_date, acquisition_channel, device_type)
    VALUES (@SignupDate, @Channel, @Device);

    -- Simulate Orders (Organic Search gets higher LTV / more repeat purchases)
    DECLARE @NumOrders INT = 0;
    IF @Channel = 'Organic Search' AND RAND() < 0.7 SET @NumOrders = CEILING(RAND() * 4); -- 1 to 4 orders
    ELSE IF RAND() < 0.4 SET @NumOrders = CEILING(RAND() * 2); -- 1 to 2 orders

    DECLARE @OrderCounter INT = 1;
    WHILE @OrderCounter <= @NumOrders
    BEGIN
        INSERT INTO dbo.orders (user_id, order_date, revenue)
        VALUES (
            @UserCounter, 
            DATEADD(DAY, ABS(CHECKSUM(NEWID()) % 30), @SignupDate), -- Order within 30 days of signup
            ROUND(RAND() * 150 + 50, 2) -- Revenue between 50 and 200
        );
        SET @OrderCounter = @OrderCounter + 1;
    END;

    SET @UserCounter = @UserCounter + 1;
END;

-- C. Generate Clickstream Funnel Data
-- (Logic built in: High mobile drop-off at checkout)
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT 
    u.user_id,
    CONCAT('SES-', u.user_id, '-', ABS(CHECKSUM(NEWID()) % 1000)),
    DATEADD(MINUTE, 1, CAST(u.signup_date AS DATETIME)),
    'page_view_home'
FROM dbo.users u;

-- 80% proceed to product page
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT user_id, session_id, DATEADD(MINUTE, 3, event_timestamp), 'page_view_product'
FROM dbo.clickstream_events WHERE event_name = 'page_view_home' AND RAND(CAST(NEWID() AS VARBINARY)) < 0.8;

-- 50% of those add to cart
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT user_id, session_id, DATEADD(MINUTE, 5, event_timestamp), 'add_to_cart'
FROM dbo.clickstream_events WHERE event_name = 'page_view_product' AND RAND(CAST(NEWID() AS VARBINARY)) < 0.5;

-- 70% of those start checkout
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT user_id, session_id, DATEADD(MINUTE, 7, event_timestamp), 'checkout_start'
FROM dbo.clickstream_events WHERE event_name = 'add_to_cart' AND RAND(CAST(NEWID() AS VARBINARY)) < 0.7;

-- Simulate Mobile Drop-off: Desktop converts at 80%, Mobile converts at only 30%
INSERT INTO dbo.clickstream_events (user_id, session_id, event_timestamp, event_name)
SELECT e.user_id, e.session_id, DATEADD(MINUTE, 10, e.event_timestamp), 'purchase'
FROM dbo.clickstream_events e
JOIN dbo.users u ON e.user_id = u.user_id
WHERE e.event_name = 'checkout_start' 
  AND ((u.device_type = 'Desktop' AND RAND(CAST(NEWID() AS VARBINARY)) < 0.8)
       OR (u.device_type = 'Mobile' AND RAND(CAST(NEWID() AS VARBINARY)) < 0.3));

PRINT 'Schema created and synthetic data successfully generated.';