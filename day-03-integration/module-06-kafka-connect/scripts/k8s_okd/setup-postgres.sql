-- Créer l'utilisateur banking s'il n'existe pas
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'banking') THEN
      CREATE ROLE banking LOGIN PASSWORD 'banking123';
   END IF;
END
$$;

-- Donner les permissions
GRANT ALL PRIVILEGES ON DATABASE core_banking TO banking;
GRANT ALL ON SCHEMA public TO banking;

-- Créer les tables
CREATE TABLE IF NOT EXISTS customers (
    customer_number SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    customer_type VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS accounts (
    account_number SERIAL PRIMARY KEY,
    customer_number INTEGER NOT NULL REFERENCES customers(customer_number),
    account_type VARCHAR(20) NOT NULL,
    balance DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(3) NOT NULL DEFAULT 'EUR',
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id SERIAL PRIMARY KEY,
    account_number INTEGER NOT NULL REFERENCES accounts(account_number),
    transaction_type VARCHAR(20) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    description TEXT,
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    balance_after DECIMAL(15,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS transfers (
    transfer_id SERIAL PRIMARY KEY,
    from_account_number INTEGER NOT NULL REFERENCES accounts(account_number),
    to_account_number INTEGER NOT NULL REFERENCES accounts(account_number),
    amount DECIMAL(15,2) NOT NULL,
    transfer_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
);

-- Insérer des données de test
INSERT INTO customers (first_name, last_name, email, phone, customer_type) VALUES
('Jean', 'Dupont', 'jean.dupont@email.com', '+33-1-23456789', 'INDIVIDUAL'),
('Marie', 'Martin', 'marie.martin@email.com', '+33-1-23456788', 'INDIVIDUAL'),
('Entreprise', 'TechCorp', 'contact@techcorp.com', '+33-1-23456787', 'BUSINESS')
ON CONFLICT (email) DO NOTHING;

INSERT INTO accounts (customer_number, account_type, balance, currency, status) VALUES
(1, 'CHECKING', 5000.00, 'EUR', 'ACTIVE'),
(2, 'SAVINGS', 10000.00, 'EUR', 'ACTIVE'),
(3, 'BUSINESS', 50000.00, 'EUR', 'ACTIVE')
ON CONFLICT DO NOTHING;
