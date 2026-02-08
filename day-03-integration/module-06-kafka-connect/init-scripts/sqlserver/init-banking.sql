-- ============================================
-- BHF Transaction Processing System - SQL Server Schema
-- ============================================

-- Create the banking database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'transaction_banking')
BEGIN
    CREATE DATABASE transaction_banking;
END
GO

USE transaction_banking;
GO

-- ============================================
-- Cards Table
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Cards]') AND type in (N'U'))
BEGIN
    CREATE TABLE Cards (
        CardId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        CardNumber VARCHAR(20) NOT NULL,
        CardholderName VARCHAR(200) NOT NULL,
        ExpiryMonth INT NOT NULL,
        ExpiryYear INT NOT NULL,
        CardType VARCHAR(20) NOT NULL CHECK (CardType IN ('DEBIT', 'CREDIT', 'PREPAID')),
        CardBrand VARCHAR(20) NOT NULL CHECK (CardBrand IN ('VISA', 'MASTERCARD', 'AMEX')),
        LinkedAccountNumber VARCHAR(30) NOT NULL,
        DailyLimit DECIMAL(18, 2) DEFAULT 2000.00,
        MonthlyLimit DECIMAL(18, 2) DEFAULT 10000.00,
        Status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (Status IN ('ACTIVE', 'BLOCKED', 'EXPIRED', 'CANCELLED')),
        Pin3DSecure BIT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE UNIQUE INDEX IX_Cards_CardNumber ON Cards(CardNumber);
END
GO

-- ============================================
-- CardTransactions Table
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CardTransactions]') AND type in (N'U'))
BEGIN
    CREATE TABLE CardTransactions (
        TransactionId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        TransactionReference VARCHAR(50) NOT NULL,
        CardId UNIQUEIDENTIFIER NOT NULL REFERENCES Cards(CardId),
        TransactionType VARCHAR(30) NOT NULL CHECK (TransactionType IN ('PURCHASE', 'WITHDRAWAL', 'REFUND', 'REVERSAL', 'AUTHORIZATION', 'CAPTURE')),
        Amount DECIMAL(18, 2) NOT NULL,
        Currency VARCHAR(3) DEFAULT 'EUR',
        MerchantName VARCHAR(200),
        MerchantCategory VARCHAR(10),
        MerchantCity VARCHAR(100),
        MerchantCountry VARCHAR(3),
        AuthorizationCode VARCHAR(20),
        ResponseCode VARCHAR(10),
        Status VARCHAR(20) DEFAULT 'PENDING' CHECK (Status IN ('PENDING', 'APPROVED', 'DECLINED', 'REVERSED', 'SETTLED')),
        Channel VARCHAR(20) DEFAULT 'POS' CHECK (Channel IN ('POS', 'ONLINE', 'ATM', 'CONTACTLESS', 'RECURRING')),
        Is3DSecure BIT DEFAULT 0,
        RiskScore INT,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE UNIQUE INDEX IX_CardTransactions_Reference ON CardTransactions(TransactionReference);
    CREATE INDEX IX_CardTransactions_CardId ON CardTransactions(CardId);
    CREATE INDEX IX_CardTransactions_CreatedAt ON CardTransactions(CreatedAt);
END
GO

-- ============================================
-- FraudAlerts Table
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[FraudAlerts]') AND type in (N'U'))
BEGIN
    CREATE TABLE FraudAlerts (
        AlertId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        TransactionId UNIQUEIDENTIFIER NOT NULL REFERENCES CardTransactions(TransactionId),
        CardId UNIQUEIDENTIFIER NOT NULL REFERENCES Cards(CardId),
        AlertType VARCHAR(50) NOT NULL CHECK (AlertType IN ('UNUSUAL_LOCATION', 'HIGH_AMOUNT', 'RAPID_TRANSACTIONS', 'SUSPICIOUS_MERCHANT', 'VELOCITY_CHECK')),
        RiskLevel VARCHAR(20) NOT NULL CHECK (RiskLevel IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
        Description VARCHAR(500),
        Status VARCHAR(20) DEFAULT 'OPEN' CHECK (Status IN ('OPEN', 'INVESTIGATING', 'CONFIRMED_FRAUD', 'FALSE_POSITIVE', 'CLOSED')),
        AssignedTo VARCHAR(100),
        ResolvedAt DATETIME2,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE INDEX IX_FraudAlerts_TransactionId ON FraudAlerts(TransactionId);
    CREATE INDEX IX_FraudAlerts_CardId ON FraudAlerts(CardId);
    CREATE INDEX IX_FraudAlerts_Status ON FraudAlerts(Status);
END
GO

-- ============================================
-- Merchants Table
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Merchants]') AND type in (N'U'))
BEGIN
    CREATE TABLE Merchants (
        MerchantId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        MerchantCode VARCHAR(20) NOT NULL,
        MerchantName VARCHAR(200) NOT NULL,
        CategoryCode VARCHAR(10) NOT NULL,
        CategoryDescription VARCHAR(100),
        City VARCHAR(100),
        Country VARCHAR(3) DEFAULT 'FRA',
        RiskCategory VARCHAR(20) DEFAULT 'STANDARD' CHECK (RiskCategory IN ('LOW', 'STANDARD', 'HIGH', 'BLOCKED')),
        IsOnline BIT DEFAULT 0,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE()
    );
    
    CREATE UNIQUE INDEX IX_Merchants_Code ON Merchants(MerchantCode);
END
GO

-- ============================================
-- Enable CDC on the database
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'transaction_banking' AND is_cdc_enabled = 1)
BEGIN
    EXEC sys.sp_cdc_enable_db;
END
GO

-- ============================================
-- Enable CDC on tables
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Cards' AND is_tracked_by_cdc = 1)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Cards',
        @role_name = NULL,
        @supports_net_changes = 1;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'CardTransactions' AND is_tracked_by_cdc = 1)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'CardTransactions',
        @role_name = NULL,
        @supports_net_changes = 1;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FraudAlerts' AND is_tracked_by_cdc = 1)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'FraudAlerts',
        @role_name = NULL,
        @supports_net_changes = 1;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Merchants' AND is_tracked_by_cdc = 1)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name = N'Merchants',
        @role_name = NULL,
        @supports_net_changes = 1;
END
GO

-- ============================================
-- Sample Data - Merchants
-- ============================================
INSERT INTO Merchants (MerchantCode, MerchantName, CategoryCode, CategoryDescription, City, Country, RiskCategory, IsOnline) VALUES
('MCH-001', 'Carrefour Paris', '5411', 'Grocery Stores', 'Paris', 'FRA', 'LOW', 0),
('MCH-002', 'Amazon France', '5999', 'E-commerce', 'Paris', 'FRA', 'STANDARD', 1),
('MCH-003', 'SNCF Voyages', '4112', 'Railway Services', 'Paris', 'FRA', 'LOW', 1),
('MCH-004', 'Restaurant Le Gourmet', '5812', 'Restaurants', 'Lyon', 'FRA', 'STANDARD', 0),
('MCH-005', 'Casino Online', '7995', 'Gambling', 'Malta', 'MLT', 'HIGH', 1);
GO

-- ============================================
-- Sample Data - Cards
-- ============================================
INSERT INTO Cards (CardNumber, CardholderName, ExpiryMonth, ExpiryYear, CardType, CardBrand, LinkedAccountNumber, DailyLimit, MonthlyLimit, Status) VALUES
('4532XXXXXXXX1234', 'JEAN DUPONT', 12, 2026, 'DEBIT', 'VISA', 'FR7612345000010001234567890', 2000.00, 10000.00, 'ACTIVE'),
('5412XXXXXXXX5678', 'MARIE MARTIN', 6, 2027, 'CREDIT', 'MASTERCARD', 'FR7612345000010001234567892', 5000.00, 25000.00, 'ACTIVE'),
('4916XXXXXXXX9012', 'PIERRE BERNARD', 3, 2025, 'DEBIT', 'VISA', 'FR7612345000010001234567893', 10000.00, 50000.00, 'ACTIVE'),
('3782XXXXXXXX3456', 'SOPHIE DUBOIS', 9, 2026, 'CREDIT', 'AMEX', 'FR7612345000010001234567894', 20000.00, 100000.00, 'ACTIVE');
GO

-- ============================================
-- Sample Data - Card Transactions
-- ============================================
DECLARE @Card1 UNIQUEIDENTIFIER = (SELECT CardId FROM Cards WHERE CardNumber = '4532XXXXXXXX1234');
DECLARE @Card2 UNIQUEIDENTIFIER = (SELECT CardId FROM Cards WHERE CardNumber = '5412XXXXXXXX5678');
DECLARE @Card3 UNIQUEIDENTIFIER = (SELECT CardId FROM Cards WHERE CardNumber = '4916XXXXXXXX9012');

INSERT INTO CardTransactions (TransactionReference, CardId, TransactionType, Amount, MerchantName, MerchantCategory, MerchantCity, MerchantCountry, AuthorizationCode, ResponseCode, Status, Channel) VALUES
('TXN-SQL-001', @Card1, 'PURCHASE', 45.50, 'Carrefour Paris', '5411', 'Paris', 'FRA', 'AUTH001', '00', 'SETTLED', 'CONTACTLESS'),
('TXN-SQL-002', @Card1, 'WITHDRAWAL', 100.00, 'ATM BNP Paribas', '6011', 'Paris', 'FRA', 'AUTH002', '00', 'SETTLED', 'ATM'),
('TXN-SQL-003', @Card2, 'PURCHASE', 299.99, 'Amazon France', '5999', 'Paris', 'FRA', 'AUTH003', '00', 'SETTLED', 'ONLINE'),
('TXN-SQL-004', @Card3, 'PURCHASE', 1500.00, 'SNCF Voyages', '4112', 'Paris', 'FRA', 'AUTH004', '00', 'SETTLED', 'ONLINE');
GO

PRINT 'BHF Transaction Processing SQL Server schema initialized successfully!';
GO
