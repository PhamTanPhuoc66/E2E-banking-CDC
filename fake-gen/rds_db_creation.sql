CREATE DATABASE IF NOT EXISTS bankdb; -- Nhớ đổi tên DB cho khớp
USE bankdb;

GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO 'adminrds'@'%';
GRANT SELECT ON *.* TO 'adminrds'@'%';
FLUSH PRIVILEGES;


CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100) UNIQUE
);

CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    account_type VARCHAR(20),
    balance DECIMAL(12,2),
    currency VARCHAR(3)
);

CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(id),
    txn_type VARCHAR(20),
    amount DECIMAL(12,2),
    related_account_id INT REFERENCES accounts(id),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);
