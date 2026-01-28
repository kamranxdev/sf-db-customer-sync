-- Database Schema for Customer Sync Application
-- Uses EMAIL as the primary business key for bidirectional sync

CREATE DATABASE IF NOT EXISTS customerdb;
USE customerdb;

DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    salesforce_id VARCHAR(18) UNIQUE,
    first_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,  -- Email is the business key for sync
    phone VARCHAR(50),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_salesforce_id (salesforce_id),
    INDEX idx_email (email),
    INDEX idx_last_modified (last_modified_date)
);

-- Sample data
INSERT INTO customers (first_name, last_name, email, phone)
VALUES 
    ('John', 'Doe', 'john.doe@example.com', '555-1234'),
    ('Jane', 'Smith', 'jane.smith@example.com', '555-5678');
