-- ============================================
-- BHF Core Banking System - PostgreSQL Schema
-- ============================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- Customers Table
-- ============================================
CREATE TABLE IF NOT EXISTS customers (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_number VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(3) DEFAULT 'FRA',
    customer_type VARCHAR(20) DEFAULT 'RETAIL' CHECK (customer_type IN ('RETAIL', 'CORPORATE', 'VIP')),
    kyc_status VARCHAR(20) DEFAULT 'PENDING' CHECK (kyc_status IN ('PENDING', 'VERIFIED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Accounts Table
-- ============================================
CREATE TABLE IF NOT EXISTS accounts (
    account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_number VARCHAR(30) UNIQUE NOT NULL,
    customer_id UUID NOT NULL REFERENCES customers(customer_id),
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('CHECKING', 'SAVINGS', 'BUSINESS', 'INVESTMENT')),
    currency VARCHAR(3) DEFAULT 'EUR',
    balance DECIMAL(18, 2) DEFAULT 0.00,
    available_balance DECIMAL(18, 2) DEFAULT 0.00,
    overdraft_limit DECIMAL(18, 2) DEFAULT 0.00,
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED', 'DORMANT')),
    interest_rate DECIMAL(5, 4) DEFAULT 0.0000,
    opened_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Transactions Table
-- ============================================
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_reference VARCHAR(50) UNIQUE NOT NULL,
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT', 'FEE', 'INTEREST', 'PAYMENT')),
    amount DECIMAL(18, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'EUR',
    balance_after DECIMAL(18, 2) NOT NULL,
    description VARCHAR(500),
    counterparty_account VARCHAR(30),
    counterparty_name VARCHAR(200),
    status VARCHAR(20) DEFAULT 'COMPLETED' CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED', 'REVERSED')),
    channel VARCHAR(20) DEFAULT 'ONLINE' CHECK (channel IN ('ONLINE', 'MOBILE', 'BRANCH', 'ATM', 'API')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Transfers Table (for inter-account transfers)
-- ============================================
CREATE TABLE IF NOT EXISTS transfers (
    transfer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transfer_reference VARCHAR(50) UNIQUE NOT NULL,
    from_account_id UUID NOT NULL REFERENCES accounts(account_id),
    to_account_id UUID NOT NULL REFERENCES accounts(account_id),
    amount DECIMAL(18, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'EUR',
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    description VARCHAR(500),
    scheduled_at TIMESTAMP WITH TIME ZONE,
    executed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Audit Log Table
-- ============================================
CREATE TABLE IF NOT EXISTS audit_log (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    action VARCHAR(20) NOT NULL CHECK (action IN ('CREATE', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    user_id VARCHAR(100),
    ip_address VARCHAR(45),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Indexes for performance
-- ============================================
CREATE INDEX idx_accounts_customer ON accounts(customer_id);
CREATE INDEX idx_transactions_account ON transactions(account_id);
CREATE INDEX idx_transactions_created ON transactions(created_at);
CREATE INDEX idx_transfers_from_account ON transfers(from_account_id);
CREATE INDEX idx_transfers_to_account ON transfers(to_account_id);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);

-- ============================================
-- Publication for Debezium CDC
-- ============================================
CREATE PUBLICATION dbz_publication FOR TABLE customers, accounts, transactions, transfers;

-- ============================================
-- Sample Data - Customers
-- ============================================
INSERT INTO customers (customer_number, first_name, last_name, email, phone, date_of_birth, city, country, customer_type, kyc_status) VALUES
('CUST-001', 'Jean', 'Dupont', 'jean.dupont@email.fr', '+33612345678', '1985-03-15', 'Paris', 'FRA', 'RETAIL', 'VERIFIED'),
('CUST-002', 'Marie', 'Martin', 'marie.martin@email.fr', '+33623456789', '1990-07-22', 'Lyon', 'FRA', 'RETAIL', 'VERIFIED'),
('CUST-003', 'Pierre', 'Bernard', 'pierre.bernard@corp.fr', '+33634567890', '1978-11-30', 'Marseille', 'FRA', 'CORPORATE', 'VERIFIED'),
('CUST-004', 'Sophie', 'Dubois', 'sophie.dubois@email.fr', '+33645678901', '1995-05-08', 'Toulouse', 'FRA', 'VIP', 'VERIFIED'),
('CUST-005', 'Antoine', 'Moreau', 'antoine.moreau@email.fr', '+33656789012', '1982-09-18', 'Nice', 'FRA', 'RETAIL', 'PENDING');

-- ============================================
-- Sample Data - Accounts
-- ============================================
INSERT INTO accounts (account_number, customer_id, account_type, balance, available_balance, overdraft_limit, status) VALUES
('FR7612345000010001234567890', (SELECT customer_id FROM customers WHERE customer_number = 'CUST-001'), 'CHECKING', 5250.00, 5250.00, 500.00, 'ACTIVE'),
('FR7612345000010001234567891', (SELECT customer_id FROM customers WHERE customer_number = 'CUST-001'), 'SAVINGS', 15000.00, 15000.00, 0.00, 'ACTIVE'),
('FR7612345000010001234567892', (SELECT customer_id FROM customers WHERE customer_number = 'CUST-002'), 'CHECKING', 3200.50, 3200.50, 300.00, 'ACTIVE'),
('FR7612345000010001234567893', (SELECT customer_id FROM customers WHERE customer_number = 'CUST-003'), 'BUSINESS', 125000.00, 125000.00, 10000.00, 'ACTIVE'),
('FR7612345000010001234567894', (SELECT customer_id FROM customers WHERE customer_number = 'CUST-004'), 'INVESTMENT', 500000.00, 500000.00, 0.00, 'ACTIVE'),
('FR7612345000010001234567895', (SELECT customer_id FROM customers WHERE customer_number = 'CUST-005'), 'CHECKING', 850.25, 850.25, 200.00, 'ACTIVE');

-- ============================================
-- Sample Data - Initial Transactions
-- ============================================
INSERT INTO transactions (transaction_reference, account_id, transaction_type, amount, balance_after, description, channel) VALUES
('TXN-PG-001', (SELECT account_id FROM accounts WHERE account_number = 'FR7612345000010001234567890'), 'DEPOSIT', 5000.00, 5000.00, 'Initial deposit', 'BRANCH'),
('TXN-PG-002', (SELECT account_id FROM accounts WHERE account_number = 'FR7612345000010001234567890'), 'DEPOSIT', 250.00, 5250.00, 'Salary credit', 'API'),
('TXN-PG-003', (SELECT account_id FROM accounts WHERE account_number = 'FR7612345000010001234567892'), 'DEPOSIT', 3200.50, 3200.50, 'Initial deposit', 'ONLINE'),
('TXN-PG-004', (SELECT account_id FROM accounts WHERE account_number = 'FR7612345000010001234567893'), 'DEPOSIT', 125000.00, 125000.00, 'Business capital', 'BRANCH');

-- ============================================
-- Function to update timestamps
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_transfers_updated_at BEFORE UPDATE ON transfers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO banking;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO banking;

-- Log completion
DO $$
BEGIN
    RAISE NOTICE 'BHF Core Banking PostgreSQL schema initialized successfully!';
END $$;
