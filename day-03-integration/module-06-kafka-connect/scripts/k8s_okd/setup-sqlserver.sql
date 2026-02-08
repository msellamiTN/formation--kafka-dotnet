-- Créer la base de données transaction_banking
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'transaction_banking')
BEGIN
    CREATE DATABASE transaction_banking;
END
GO

USE transaction_banking;
GO

-- Créer les tables
CREATE TABLE Cards (
    CardId INT IDENTITY(1,1) PRIMARY KEY,
    CardNumber VARCHAR(20) UNIQUE NOT NULL,
    CardType VARCHAR(20) NOT NULL,
    CustomerId INT NOT NULL,
    Status VARCHAR(20) DEFAULT 'ACTIVE',
    CreditLimit DECIMAL(15,2) DEFAULT 0.00,
    Balance DECIMAL(15,2) DEFAULT 0.00,
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE CardTransactions (
    TransactionId BIGINT IDENTITY(1,1) PRIMARY KEY,
    CardId INT NOT NULL FOREIGN KEY REFERENCES Cards(CardId),
    TransactionType VARCHAR(20) NOT NULL,
    Amount DECIMAL(15,2) NOT NULL,
    MerchantId INT NOT NULL,
    TransactionDate DATETIME DEFAULT GETDATE(),
    Status VARCHAR(20) DEFAULT 'COMPLETED',
    ApprovalCode VARCHAR(10),
    Description VARCHAR(255)
);
GO

CREATE TABLE FraudAlerts (
    AlertId BIGINT IDENTITY(1,1) PRIMARY KEY,
    CardId INT NOT NULL FOREIGN KEY REFERENCES Cards(CardId),
    TransactionId BIGINT FOREIGN KEY REFERENCES CardTransactions(TransactionId),
    AlertType VARCHAR(50) NOT NULL,
    AlertDate DATETIME DEFAULT GETDATE(),
    Status VARCHAR(20) DEFAULT 'OPEN',
    RiskScore INT DEFAULT 0,
    Description VARCHAR(500)
);
GO

CREATE TABLE Merchants (
    MerchantId INT IDENTITY(1,1) PRIMARY KEY,
    MerchantName VARCHAR(100) NOT NULL,
    Category VARCHAR(50) NOT NULL,
    Country VARCHAR(50) NOT NULL,
    Status VARCHAR(20) DEFAULT 'ACTIVE',
    CreatedAt DATETIME DEFAULT GETDATE()
);
GO

-- Insérer des données de test
INSERT INTO Merchants (MerchantName, Category, Country) VALUES
('Amazon', 'E-commerce', 'US'),
('Carrefour', 'Supermarket', 'FR'),
('Shell', 'Gas Station', 'NL'),
('Apple Store', 'Technology', 'US'),
('Starbucks', 'Coffee Shop', 'US');
GO

INSERT INTO Cards (CardNumber, CardType, CustomerId, Status, CreditLimit, Balance) VALUES
('4532-1234-5678-9012', 'CREDIT', 1, 'ACTIVE', 10000.00, 2500.00),
('4532-1234-5678-9013', 'DEBIT', 2, 'ACTIVE', 5000.00, 1200.00),
('4532-1234-5678-9014', 'CREDIT', 3, 'ACTIVE', 20000.00, 8500.00);
GO

INSERT INTO CardTransactions (CardId, TransactionType, Amount, MerchantId, Description) VALUES
(1, 'PURCHASE', 150.50, 1, 'Amazon purchase'),
(1, 'PURCHASE', 85.25, 2, 'Carrefour groceries'),
(2, 'WITHDRAWAL', 200.00, 3, 'ATM withdrawal'),
(3, 'PURCHASE', 1299.99, 4, 'Apple iPhone'),
(1, 'PURCHASE', 5.75, 5, 'Starbucks coffee');
GO

-- Activer CDC sur les tables
EXEC sys.sp_cdc_enable_db;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name = 'Cards',
    @role_name = NULL,
    @supports_net_changes = 1;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name = 'CardTransactions',
    @role_name = NULL,
    @supports_net_changes = 1;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name = 'FraudAlerts',
    @role_name = NULL,
    @supports_net_changes = 1;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name = 'Merchants',
    @role_name = NULL,
    @supports_net_changes = 1;
GO

-- Vérifier que CDC est activé
SELECT name, is_cdc_enabled 
FROM sys.tables 
WHERE name IN ('Cards', 'CardTransactions', 'FraudAlerts', 'Merchants');
GO
