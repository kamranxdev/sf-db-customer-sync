<div align="center">

# Salesforce - Database Customer Sync

**A MuleSoft Integration Solution for Bidirectional Customer Data Synchronization**

[![Mule Runtime](https://img.shields.io/badge/Mule%20Runtime-4.10.2-blue.svg)](https://docs.mulesoft.com/)
[![MUnit](https://img.shields.io/badge/MUnit-3.6.2-green.svg)](https://docs.mulesoft.com/munit/latest/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#-architecture)
3. [Field Mapping](#-field-mapping)
4. [Detailed Flow Explanations](#-detailed-flow-explanations)
5. [Data Flow Examples](#-data-flow-examples)
6. [Prerequisites](#-prerequisites)
7. [Installation & Setup](#-installation--setup)
8. [Running the Application](#-running-the-application)
9. [Integration Testing](#-integration-testing)
10. [MUnit Testing](#-munit-testing)
11. [Troubleshooting](#-troubleshooting)
12. [Additional Resources](#-additional-resources)

---

## 📖 Overview

This MuleSoft application provides **bidirectional customer data synchronization** between a MySQL database and Salesforce CRM using **Email as the primary business key**.

### Key Features

| Feature | Description |
|---------|-------------|
| **Bidirectional Sync** | Data flows both ways: DB ↔ Salesforce |
| **Email-Based Matching** | Uses email as natural business key to prevent duplicates |
| **Scheduled Execution** | Configurable scheduler for automated syncing |
| **Error Handling** | Comprehensive error handling with logging |
| **Unit Tested** | Full MUnit test coverage for all sync scenarios |

### Application Specifications

| Attribute | Value |
|-----------|-------|
| Application Name | `sf-db-customer-sync` |
| Mule Runtime | 4.10.2 |
| MUnit Version | 3.6.2 |
| Sync Pattern | Bidirectional (Unified Scheduler) |
| Business Key | Email (unique identifier) |

---

## 🏗️ Architecture

### Sync Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                  UNIFIED BIDIRECTIONAL SYNC                     │
│                                                                 │
│   ┌─────────────┐                        ┌─────────────┐        │
│   │   MySQL     │                        │ Salesforce  │        │
│   │  Database   │                        │    CRM      │        │
│   └──────┬──────┘                        └──────┬──────┘        │
│          │                                      │               │
│          ▼                                      ▼               │
│   ┌──────────────────────────────────────────────────────┐      │
│   │              STEP 1: FETCH ALL DATA                  │      │
│   │   • Get modified customers from DB                   │      │
│   │   • Get modified contacts from Salesforce            │      │
│   │   • Create email lookup maps                         │      │
│   └──────────────────────────────────────────────────────┘      │
│                            │                                    │
│                            ▼                                    │
│   ┌──────────────────────────────────────────────────────┐      │
│   │           STEP 2: DB → SALESFORCE SYNC               │      │
│   │   • Match by EMAIL (business key)                    │      │
│   │   • Upsert to Salesforce                             │      │
│   │   • Update DB with Salesforce IDs                    │      │
│   └──────────────────────────────────────────────────────┘      │
│                            │                                    │
│                            ▼                                    │
│   ┌──────────────────────────────────────────────────────┐      │
│   │           STEP 3: SALESFORCE → DB SYNC               │      │
│   │   • Find SF contacts NOT in DB (by email)            │      │
│   │   • Insert new records to DB                         │      │
│   │   • Link with Salesforce ID                          │      │
│   └──────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔗 Field Mapping

| Database Field | Salesforce Field | Notes |
|----------------|------------------|-------|
| `customer_id` | — | DB auto-increment primary key |
| `salesforce_id` | `Id` | Salesforce record ID |
| `first_name` | `FirstName` | |
| `last_name` | `LastName` | Required in both systems |
| **`email`** | **`Email`** | **Business Key** - must be unique |
| `phone` | `Phone` | |

### Why Email as Business Key?

| Approach | Pros | Cons |
|----------|------|------|
| Custom External ID | Links DB ID directly | Requires custom field setup |
| **Email (chosen)** | Natural business key, works natively | Must be unique and not null |
| Salesforce ID | Guaranteed unique | Only exists after SF record created |

---

## 🔄 Detailed Flow Explanations

### Main Flow: `bidirectionalCustomerSync`

**Purpose**: Orchestrates the complete bidirectional synchronization between MySQL and Salesforce.

**Trigger**: Fixed-frequency scheduler (configurable via `${scheduler.frequency}`)

**Flow Steps**:

| Step | Component | Description |
|------|-----------|-------------|
| 1 | **Scheduler** | Triggers sync at configured intervals (e.g., every 60 seconds) |
| 2 | **Logger** | Records sync start timestamp |
| 3 | **flow-ref: fetchAllData** | Calls sub-flow to retrieve all data from both systems |
| 4 | **flow-ref: syncDbToSalesforce** | Syncs database records to Salesforce |
| 5 | **flow-ref: syncSalesforceToDb** | Syncs Salesforce-only records to database |
| 6 | **Logger** | Records successful completion |
| 7 | **Error Handler** | References global error handler for exceptions |

**Example Log Output**:
```
INFO  - Bidirectional sync started at 2026-01-28T10:30:00
INFO  - Fetched 2 customers from DB
INFO  - Fetched 3 contacts from Salesforce
INFO  - Synced 2 records from DB to Salesforce
INFO  - Synced 1 SF-only contacts to DB
INFO  - Bidirectional sync completed successfully
```

---

### Sub-Flow 1: `fetchAllData`

**Purpose**: Retrieves all modified records from both MySQL and Salesforce, creates lookup maps for email-based matching.

**Detailed Steps**:

#### Step 1.1: Select All Customers from Database

**Component**: `db:select`

**SQL Query**:
```sql
SELECT customer_id, salesforce_id, first_name, last_name, email, phone, last_modified_date 
FROM customers 
WHERE last_modified_date >= DATE_SUB(NOW(), INTERVAL 1 DAY) 
   OR salesforce_id IS NULL
```

**Logic**:
- Fetches customers modified in last 24 hours
- Also fetches customers without Salesforce ID (new records)
- Stores result in variable: `vars.dbCustomers`

**Example Output**:
```java
[
  {customer_id: 1, salesforce_id: null, first_name: "John", last_name: "Doe", 
   email: "john@test.com", phone: "555-1234", last_modified_date: 2026-01-28T09:00:00},
  {customer_id: 2, salesforce_id: "003XXX", first_name: "Jane", last_name: "Smith", 
   email: "jane@test.com", phone: "555-5678", last_modified_date: 2026-01-28T08:30:00}
]
```

#### Step 1.2: Logger - Log DB Count

Logs: `"Fetched 2 customers from DB"`

#### Step 1.3: Query All Contacts from Salesforce

**Component**: `salesforce:query`

**SOQL Query**:
```sql
SELECT Id, FirstName, LastName, Email, Phone, LastModifiedDate 
FROM Contact 
WHERE LastModifiedDate >= YESTERDAY 
   OR Email != null
```

**Logic**:
- Fetches contacts modified since yesterday
- Ensures all contacts with emails are included
- Returns Salesforce result set

#### Step 1.4: Transform SF to List

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
payload
```

**Purpose**: Converts Salesforce result set to Java ArrayList for processing

**Stores in**: `vars.sfContacts`

**Example Output**:
```java
[
  {Id: "003AAA", FirstName: "Jane", LastName: "Smith", 
   Email: "jane@test.com", Phone: "555-5678", LastModifiedDate: 2026-01-28T08:35:00},
  {Id: "003BBB", FirstName: "Alice", LastName: "Johnson", 
   Email: "alice@test.com", Phone: "555-9999", LastModifiedDate: 2026-01-28T10:00:00}
]
```

#### Step 1.5: Logger - Log SF Count

Logs: `"Fetched 2 contacts from Salesforce"`

#### Step 1.6: Create SF Email Lookup Map

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
{
  byEmail: vars.sfContacts groupBy ((item) -> lower(item.Email default ""))
}
```

**Purpose**: Creates a HashMap for O(1) email lookups during matching

**Stores in**: `vars.sfLookup.byEmail`

**Example Structure**:
```java
{
  "jane@test.com": [{Id: "003AAA", FirstName: "Jane", LastName: "Smith", ...}],
  "alice@test.com": [{Id: "003BBB", FirstName: "Alice", LastName: "Johnson", ...}]
}
```

**Why This Matters**: Email lookups are instant (O(1)) instead of looping through arrays (O(n))

---

### Sub-Flow 2: `syncDbToSalesforce`

**Purpose**: Syncs all database customers to Salesforce using email as the matching key. Updates database with Salesforce IDs after successful upsert.

**Detailed Steps**:

#### Step 2.1: Prepare DB Records for SF

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
vars.dbCustomers filter (!isEmpty($.email)) map (customer) -> {
  // Check if this email already exists in Salesforce
  existingSfRecord: vars.sfLookup[lower(customer.email)][0] default null,
  dbRecord: customer
}
```

**Logic Breakdown**:

| Action | Description | Example |
|--------|-------------|---------|
| **Filter** | Remove customers without emails | Only customers with valid email continue |
| **Map** | Transform each customer | Create enriched object with SF match info |
| **Lookup** | `vars.sfLookup[lower(customer.email)][0]` | Find matching SF contact by email |
| **Result** | Object with both DB and SF data | Used to determine create vs. update |

**Example Output**:
```java
[
  {
    existingSfRecord: null,  // No SF record found - will CREATE
    dbRecord: {customer_id: 1, email: "john@test.com", ...}
  },
  {
    existingSfRecord: {Id: "003AAA", Email: "jane@test.com", ...},  // SF record found - will UPDATE
    dbRecord: {customer_id: 2, email: "jane@test.com", ...}
  }
]
```

**Stores in**: `vars.mappedRecords`

#### Step 2.2: Check Records to Sync

**Component**: `choice`

**Condition**: `#[sizeOf(vars.mappedRecords) > 0]`

**When TRUE** (records exist):

##### Step 2.2a: Transform to SF Format

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
vars.mappedRecords map (record) -> {
  // If SF record exists, include Id to update; otherwise create new
  (Id: record.existingSfRecord.Id) if (record.existingSfRecord != null),
  FirstName: record.dbRecord.first_name,
  LastName: record.dbRecord.last_name,
  Email: record.dbRecord.email,
  Phone: record.dbRecord.phone
}
```

**Conditional Field Logic**:
- **If `existingSfRecord` exists**: Include `Id` field → Salesforce will UPDATE
- **If `existingSfRecord` is null**: No `Id` field → Salesforce will CREATE

**Example Output**:
```java
[
  {  // New record - no Id
    FirstName: "John",
    LastName: "Doe",
    Email: "john@test.com",
    Phone: "555-1234"
  },
  {  // Existing record - has Id
    Id: "003AAA",  // ← This makes it an UPDATE
    FirstName: "Jane",
    LastName: "Smith",
    Email: "jane@test.com",
    Phone: "555-5678"
  }
]
```

##### Step 2.2b: Upsert to Salesforce

**Component**: `salesforce:upsert`

**Configuration**:
- `objectType`: `Contact`
- `externalIdFieldName`: `Email`

**Operation**: Performs upsert (create or update) based on email matching

**Returns**:
```java
{
  items: [
    {id: "003XXX1", successful: true, created: true},
    {id: "003AAA", successful: true, created: false}  // Updated existing
  ]
}
```

**Stores in**: `vars.sfResults`

##### Step 2.2c: Prepare DB Updates

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
(vars.sfResults.items default vars.sfResults) map ((result, index) -> {
  salesforce_id: result.id,
  customer_id: vars.mappedRecords[index].dbRecord.customer_id
}) filter ($.salesforce_id != null and $.customer_id != null)
```

**Logic**:
1. Extract Salesforce IDs from upsert results
2. Match with corresponding DB customer_id using array index
3. Filter out any null values

**Example Output**:
```java
[
  {salesforce_id: "003XXX1", customer_id: 1},
  {salesforce_id: "003AAA", customer_id: 2}
]
```

##### Step 2.2d: Update DB with SF IDs

**Component**: `foreach` → `db:update`

**SQL for Each Record**:
```sql
UPDATE customers 
SET salesforce_id = :salesforce_id, 
    last_modified_date = last_modified_date  -- Prevent recursive sync
WHERE customer_id = :customer_id
```

**Critical Note**: `last_modified_date = last_modified_date` prevents triggering another sync cycle

**Parameters**:
```java
{
  salesforce_id: payload.salesforce_id,
  customer_id: payload.customer_id
}
```

##### Step 2.2e: Logger

Logs: `"Synced 2 records from DB to Salesforce"`

**When FALSE** (no records):

Logs: `"No DB records to sync to Salesforce"`

---

### Sub-Flow 3: `syncSalesforceToDb`

**Purpose**: Syncs Salesforce contacts that don't exist in the database (identified by email). Prevents duplicate insertion.

**Detailed Steps**:

#### Step 3.1: Create DB Email Set

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
vars.dbCustomers map (c) -> lower(c.email default "")
```

**Purpose**: Creates array of lowercase emails from database for O(n) lookup

**Stores in**: `vars.dbEmails`

**Example Output**:
```java
["john@test.com", "jane@test.com"]
```

#### Step 3.2: Find SF-Only Contacts

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
vars.sfContacts filter (contact) -> (
  !isEmpty(contact.Email) and 
  !(vars.dbEmails contains lower(contact.Email))
)
```

**Logic Breakdown**:

| Check | Description | Purpose |
|-------|-------------|---------|
| `!isEmpty(contact.Email)` | Email must exist | Skip contacts without emails |
| `!(vars.dbEmails contains ...)` | Email NOT in DB | Find NEW contacts only |

**Example Output**:
```java
[
  // alice@test.com is NOT in dbEmails - SYNC THIS
  {Id: "003BBB", FirstName: "Alice", LastName: "Johnson", 
   Email: "alice@test.com", Phone: "555-9999"}
  // john@test.com and jane@test.com already in DB - SKIP THEM
]
```

**Stores in**: `vars.sfOnlyContacts`

#### Step 3.3: Check SF-Only Records

**Component**: `choice`

**Condition**: `#[sizeOf(vars.sfOnlyContacts) > 0]`

**When TRUE** (new SF contacts found):

##### Step 3.3a: Transform to DB Format

**Component**: `ee:transform` (DataWeave)

**Transformation**:
```dataweave
%dw 2.0
output application/java
---
vars.sfOnlyContacts map (contact) -> {
  salesforce_id: contact.Id,
  first_name: contact.FirstName default "",
  last_name: contact.LastName default "Unknown",
  email: contact.Email,
  phone: contact.Phone
}
```

**Default Values**: Ensures required fields (`last_name`) always have values

**Example Output**:
```java
[
  {
    salesforce_id: "003BBB",
    first_name: "Alice",
    last_name: "Johnson",
    email: "alice@test.com",
    phone: "555-9999"
  }
]
```

##### Step 3.3b: Insert SF Contacts to DB

**Component**: `foreach` → `db:insert`

**SQL for Each Contact**:
```sql
INSERT INTO customers (salesforce_id, first_name, last_name, email, phone, last_modified_date)
VALUES (:salesforce_id, :first_name, :last_name, :email, :phone, NOW())
ON DUPLICATE KEY UPDATE
  salesforce_id = :salesforce_id, 
  first_name = :first_name, 
  last_name = :last_name, 
  phone = :phone, 
  last_modified_date = NOW()
```

**Why `ON DUPLICATE KEY UPDATE`?**
- **Primary Protection**: Prevents errors if email already exists
- **Upsert Behavior**: Updates existing record instead of failing
- **Idempotent**: Safe to run multiple times

**Parameters**:
```java
{
  salesforce_id: payload.salesforce_id,
  first_name: payload.first_name,
  last_name: payload.last_name,
  email: payload.email,
  phone: payload.phone
}
```

##### Step 3.3c: Logger

Logs: `"Synced 1 SF-only contacts to DB"`

**When FALSE** (no new SF contacts):

Logs: `"No SF-only records to sync to DB"`

---

## 📊 Data Flow Examples

### Example 1: New Customer in Database

**Initial State**:
- **Database**: John Doe (john@test.com) - NEW
- **Salesforce**: Empty

**Flow Execution**:

| Sub-Flow | Action | Result |
|----------|--------|--------|
| `fetchAllData` | Fetch John from DB<br>Fetch 0 from SF | `vars.dbCustomers = [John]`<br>`vars.sfContacts = []` |
| `syncDbToSalesforce` | Find no SF match for john@test.com<br>Create new Contact | SF Contact created: Id=003XXX |
| `syncDbToSalesforce` | Update DB customer_id=1 | `salesforce_id` = "003XXX" |
| `syncSalesforceToDb` | No SF-only contacts | No action |

**Final State**:
- **Database**: John Doe (salesforce_id: "003XXX")
- **Salesforce**: John Doe (Id: "003XXX", Email: john@test.com)

---

### Example 2: New Contact in Salesforce

**Initial State**:
- **Database**: Empty
- **Salesforce**: Alice Johnson (alice@test.com) - NEW

**Flow Execution**:

| Sub-Flow | Action | Result |
|----------|--------|--------|
| `fetchAllData` | Fetch 0 from DB<br>Fetch Alice from SF | `vars.dbCustomers = []`<br>`vars.sfContacts = [Alice]` |
| `syncDbToSalesforce` | No DB customers | No action |
| `syncSalesforceToDb` | alice@test.com NOT in DB<br>Insert new customer | DB customer created |

**Final State**:
- **Database**: Alice Johnson (salesforce_id: "003BBB", email: alice@test.com)
- **Salesforce**: Alice Johnson (Id: "003BBB", Email: alice@test.com)

---

### Example 3: Bidirectional with Updates

**Initial State**:
- **Database**: John (phone: 555-1234), Jane (phone: 555-5678)
- **Salesforce**: Jane (phone: 555-0000 - DIFFERENT), Alice (NEW)

**Flow Execution**:

| Sub-Flow | Action | Result |
|----------|--------|--------|
| `fetchAllData` | Fetch John, Jane from DB<br>Fetch Jane, Alice from SF | Both systems loaded |
| `syncDbToSalesforce` | John: No SF match → Create<br>Jane: SF match found → Update | John created in SF<br>Jane updated in SF (phone: 555-5678) |
| `syncSalesforceToDb` | Alice NOT in DB → Insert | Alice added to DB |

**Final State**:
- **Database**: John (SF linked), Jane (SF linked), Alice (SF linked)
- **Salesforce**: John (new), Jane (updated phone), Alice (existing)

### Project Structure

```
sf-db-customer-sync/
├── src/
│   ├── main/
│   │   ├── mule/
│   │   │   ├── sf-db-customer-sync.xml    # Main sync flows
│   │   │   ├── global-config.xml          # Connectors configuration
│   │   │   └── error-handler.xml          # Error handling
│   │   └── resources/
│   │       ├── config/
│   │       │   └── config-dev.yaml        # Development configuration
│   │       ├── database-schema.sql        # DB schema script
│   │       └── log4j2.xml                 # Logging configuration
│   └── test/
│       ├── munit/
│       │   ├── sf-db-customer-sync-test-suite.xml   # Comprehensive sync tests
│       │   └── error-handler-test-suite.xml          # Error scenario tests
│       └── resources/
│           └── config/
│               └── config-test.yaml       # Test configuration
├── pom.xml                                # Maven configuration
└── README.md                              # This documentation
```

---

## 🔧 Prerequisites

Before you begin, ensure you have the following:

- [ ] **Anypoint Studio** 7.x or later
- [ ] **Java JDK** 8 or 11
- [ ] **MySQL** 5.7+ or 8.0
- [ ] **Salesforce Developer Account** ([Sign up free](https://developer.salesforce.com/signup))
- [ ] **Maven** 3.6+ (for command-line builds)

---

## 🚀 Installation & Setup

### Step 1: Salesforce Developer Account

1. Navigate to [Salesforce Developer Signup](https://developer.salesforce.com/signup)
2. Complete the registration form and click **Sign Up**
3. Verify your email address
4. Login to your new Salesforce org

### Step 2: Salesforce Security Token

1. Login to Salesforce
2. Click your **Profile Icon** (top right) → **Settings**
3. Navigate to **My Personal Information** → **Reset My Security Token**
4. Click **Reset Security Token**
5. Check your email for the security token
6. **Save this token securely** - you'll need it for configuration

### Step 3: MySQL Database Setup

Execute the following SQL script to create the required database schema:

```sql
-- Create database
CREATE DATABASE IF NOT EXISTS customerdb;
USE customerdb;

-- Create customers table with EMAIL as unique business key
CREATE TABLE IF NOT EXISTS customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    salesforce_id VARCHAR(18) UNIQUE,
    first_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,  -- Email is the business key for sync
    phone VARCHAR(50),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_salesforce_id (salesforce_id),
    INDEX idx_last_modified (last_modified_date)
);
```

> ⚠️ **Important**: The `email` field must be unique and not null — it's the key that links records between systems.

### Step 4: Application Configuration

1. Open the configuration file: `src/main/resources/config/config-dev.yaml`
2. Update with your credentials:

```yaml
# Database Configuration
db:
  host: "localhost"
  port: "3306"
  database: "customerdb"
  user: "root"
  password: "your-mysql-password"

# Salesforce Configuration
salesforce:
  username: "your-email@example.com"
  password: "your-salesforce-password"
  securityToken: "your-security-token-from-email"
  url: "https://login.salesforce.com/services/Soap/u/64.0"

# Scheduler Configuration
scheduler:
  frequency: "60000"  # 60 seconds for testing (use 86400000 for 24 hours in production)
```

> 💡 **Tip**: For testing purposes, set scheduler frequency to `60000` (1 minute).

---

## ▶️ Running the Application

### Using Anypoint Studio

1. **Import the Project**
   - Open **Anypoint Studio**
   - Go to **File** → **Import** → **Anypoint Studio** → **Anypoint Studio project from File System**
   - Browse to your project folder and import

2. **Configure Environment Variable**
   - Right-click on project → **Run As** → **Run Configurations**
   - Select your Mule Application
   - Navigate to **Arguments** tab
   - Add to **VM arguments**:
     ```
     -Denv=dev
     ```
   - Click **Apply**

3. **Run the Application**
   - Right-click on project → **Run As** → **Mule Application**
   - Wait for deployment confirmation:
     ```
     **********************************************************
     *   - - + DOMAIN + - -   * - - + STATUS + - - *          *
     **********************************************************
     * default                * DEPLOYED           *          *
     **********************************************************
     ```

### Using Maven (Command Line)

```bash
# Run the application
mvn clean mule:deploy -Denv=dev
```

---

## 🔄 Integration Testing

After MUnit tests pass, perform manual integration testing with real systems.

### Test Scenario 1: Database → Salesforce

#### Step 1: Insert Customer in Database

```sql
USE customerdb;

INSERT INTO customers (first_name, last_name, email, phone)
VALUES ('John', 'Doe', 'john.doe@email.com', '123-456-7890');
```

#### Step 2: Wait for Sync

Monitor the Anypoint Studio console for logs:

```
INFO  - Bidirectional sync started at 2026-01-28T10:30:00
INFO  - Fetched 1 customers from DB
INFO  - Fetched 0 contacts from Salesforce
INFO  - Synced 1 records from DB to Salesforce
INFO  - Bidirectional sync completed successfully
```

#### Step 3: Verify in Salesforce

1. Login to [Salesforce](https://login.salesforce.com)
2. Click **App Launcher** (⋮⋮⋮) → **Contacts**
3. Confirm **John Doe** appears with correct details

#### Step 4: Verify Database Updated

```sql
SELECT customer_id, salesforce_id, first_name, last_name, email 
FROM customers;
```

The `salesforce_id` column should now contain the Salesforce Contact ID.

---

### Test Scenario 2: Salesforce → Database

#### Step 1: Create Contact in Salesforce

1. Login to Salesforce
2. Navigate to **Contacts** → **New**
3. Enter:
   - **First Name**: Alice
   - **Last Name**: Williams
   - **Email**: alice.w@company.com (must be unique)
   - **Phone**: 111-222-3333
4. Click **Save**

#### Step 2: Wait for Sync

Monitor console for:

```
INFO  - Bidirectional sync started at 2026-01-28T10:31:00
INFO  - Fetched 1 customers from DB
INFO  - Fetched 2 contacts from Salesforce
INFO  - Synced 1 SF-only contacts to DB
INFO  - Bidirectional sync completed successfully
```

#### Step 3: Verify in Database

```sql
SELECT * FROM customers;
```

Expected output:

```
+-------------+--------------------+------------+-----------+---------------------+--------------+
| customer_id | salesforce_id      | first_name | last_name | email               | phone        |
+-------------+--------------------+------------+-----------+---------------------+--------------+
| 1           | 003XXXXXXXXXXXX    | John       | Doe       | john.doe@email.com  | 123-456-7890 |
| 2           | 003YYYYYYYYYYYY    | Alice      | Williams  | alice.w@company.com | 111-222-3333 |
+-------------+--------------------+------------+-----------+---------------------+--------------+
```

---

### Quick Test Checklist

| Test | Action | Expected Result | Status |
|------|--------|-----------------|--------|
| **DB → SF** | Insert customer in MySQL | Contact appears in Salesforce | ☐ |
| **SF → DB** | Create contact in Salesforce | Customer appears in MySQL | ☐ |
| **Update Sync** | Update phone in either system | Change synced to other system | ☐ |
| **No Duplicates** | Same email in both systems | Records linked, no duplicates | ☐ |
| **MUnit Tests** | Run `mvn clean test` | All tests pass | ☐ |

---

## 🧪 MUnit Testing

This project includes comprehensive MUnit test suites that validate all synchronization scenarios without requiring actual database or Salesforce connections.

### Running MUnit Tests

#### Option 1: Anypoint Studio (GUI)

1. **Run All Tests**
   - Right-click on project → **Run As** → **MUnit**
   - All test suites will execute automatically

2. **Run Specific Test Suite**
   - Navigate to `src/test/munit/`
   - Right-click on desired test file (e.g., `db-to-sf-sync-test-suite.xml`)
   - Select **Run As** → **MUnit**

3. **Run Individual Test**
   - Open the test suite XML file
   - Right-click on specific `<munit:test>` element
   - Select **Run As** → **MUnit**

#### Option 2: Maven (Command Line)

```bash
# Run all MUnit tests
mvn clean test -Denv=test

# Run with coverage report
mvn clean test -Denv=test -Dmunit.coverage.enabled=true

# Run specific test suite
mvn clean test -Denv=test -Dmunit.test=db-to-sf-sync-test-suite.xml

# Run specific test case
mvn clean test -Denv=test -Dmunit.test=db-to-sf-sync-test-suite.xml#db-to-sf-happy-path-test
```

#### Option 3: View Coverage Report

After running tests with coverage:
```bash
mvn clean test -Denv=test
```

Open the coverage report at: `target/site/munit/coverage/summary.html`

---

### Test Suites Overview

The project contains two main test suites:

| Test Suite | File | Description |
|------------|------|-------------|
| **Primary Sync Tests** | `sf-db-customer-sync-test-suite.xml` | Tests Database ↔ Salesforce bidirectional synchronization |
| **Error Handler Tests** | `error-handler-test-suite.xml` | Tests global error handling for database and Salesforce failures |

---

### Understanding MUnit Test Structure

Each MUnit test follows the **Behavior-Driven Development (BDD)** pattern with three phases:

```
┌─────────────────────────────────────────────────────────────────┐
│                     MUNIT TEST STRUCTURE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  1. BEHAVIOR (Given)                                    │    │
│  │     • Set up mock responses for external systems        │    │
│  │     • Configure expected inputs and outputs             │    │
│  │     • Simulate database and Salesforce responses        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                            ↓                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  2. EXECUTION (When)                                    │    │
│  │     • Execute the flow or sub-flow being tested         │    │
│  │     • Call flow-ref to trigger actual business logic    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                            ↓                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  3. VALIDATION (Then)                                   │    │
│  │     • Assert expected outcomes                          │    │
│  │     • Verify variables and payload values               │    │
│  │     • Confirm business logic executed correctly         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### Primary Sync Tests (`sf-db-customer-sync-test-suite.xml`)

This suite validates the core bidirectional synchronization logic using mocked external systems.

| Test Case | Description | What It Validates |
|-----------|-------------|-------------------|
| `db-to-sf-sync-test` | Sync from DB to Salesforce | ✅ Existing SF contact found by email<br>✅ Records linked via email business key |
| `sf-to-db-sync-test` | Sync from Salesforce to DB | ✅ New contacts in SF inserted to DB<br>✅ Primary key and SF ID linking |
| `bidirectional-sync-test` | Full bidirectional cycle | ✅ Complex scenario with updates and new records in both systems |

#### Detailed Example: `db-to-sf-sync-test`

**Goal**: Verify that a database record with no Salesforce ID correctly links to an existing Salesforce contact via email.

**Phase 1: Behavior (Mocking)**:
- **Mock DB Select**: Returns 2 records (John Doe, Jane Smith).
- **Mock SF Query**: Returns 1 record (Jane Smith) matching by email.
- **Mock SF Upsert**: Simulates successful update.

**Phase 2: Execution**:
- Calls `fetchAllData` sub-flow.
- Calls `syncDbToSalesforce` sub-flow.

**Phase 3: Validation**:
- Asserts that `vars.dbCustomers` contains 2 records.
- Verifies that the payload is not null after the sync process.

---

### Error Handler Tests (`error-handler-test-suite.xml`)

This suite ensures that the application responds correctly to external system connectivity failures.

| Test Case | Description | What It Validates |
|-----------|-------------|-------------------|
| `db-connectivity-error-test` | Database connection failure | ✅ Handles `DB:CONNECTIVITY` error<br>✅ Logs error and completes gracefully |
| `sf-connectivity-error-test` | Salesforce connection failure | ✅ Handles `SALESFORCE:CONNECTIVITY` error<br>✅ Logs error and completes gracefully |

---
<munit-tools:mock-when processor="salesforce:upsert">
  <munit-tools:then-return>
    <munit-tools:payload value="#[{
      items: [

## 🧠 MUnit Testing Best Practices

### Why Mock External Systems?

| Benefit | Description |
|---------|-------------|
| **Fast Execution** | No network calls or I/O operations |
| **Reliability** | Tests always produce same results |
| **No Dependencies** | No need for actual DB or SF credentials |
| **Isolation** | Test business logic, not external systems |
| **Predictable** | Control exact responses and error scenarios |

### MUnit Test Anatomy

```xml
<munit:test name="db-to-sf-happy-path-test" 
            description="Test successful sync from Database to Salesforce">
```

**Step 1: BEHAVIOR (Setup Mocks)**

| Mock | Purpose | Returns |
|------|---------|---------|
| `db:select` | Simulates database query | 2 customer records (John Doe, Jane Smith) |
| `salesforce:query` | Simulates SF query | Empty list (no existing contacts) |
| `salesforce:upsert` | Simulates SF upsert | Success with 2 new SF IDs |
| `db:update` | Simulates DB update | 1 affected row |

**Step 2: EXECUTION (Run the Flow)**

```xml
<munit:execution>
    <flow-ref name="fetchAllData"/>      <!-- Fetches data from both systems -->
    <flow-ref name="syncDbToSalesforce"/> <!-- Syncs DB records to SF -->
</munit:execution>
```

**Step 3: VALIDATION (Assert Results)**

```xml
<munit:validation>
    <!-- Assert 2 customers were fetched from DB -->
    <munit-tools:assert-that 
        expression="#[sizeOf(vars.dbCustomers)]" 
        is="#[MunitTools::equalTo(2)]"/>
    
    <!-- Assert payload is not null -->
    <munit-tools:assert-that 
        expression="#[payload]" 
        is="#[MunitTools::notNullValue()]"/>
</munit:validation>
```

---

### Test Suite 2: Salesforce to DB Sync Tests

**File**: `src/test/munit/sf-to-db-sync-test-suite.xml`

| Test Case | Description | What It Validates |
|-----------|-------------|-------------------|
| `sf-to-db-happy-path-test` | Successful sync from SF to DB | ✅ SF contacts fetched<br>✅ New contacts inserted to DB |
| `sf-to-db-no-new-records-test` | All SF contacts exist in DB | ✅ No duplicates created<br>✅ Email matching works |
| `sf-to-db-empty-sf-test` | No contacts in Salesforce | ✅ Handles empty SF gracefully |
| `sf-to-db-sf-error-test` | Salesforce connection failure | ✅ SALESFORCE:CONNECTIVITY error raised |
| `sf-to-db-db-error-test` | Database insert failure | ✅ DB:CONNECTIVITY error raised |
| `bidirectional-full-sync-test` | Complete bidirectional flow | ✅ Both directions work together<br>✅ No duplicates across systems |

#### Example: Bidirectional Full Sync Test

This test validates the complete end-to-end sync process:

**Step 1: BEHAVIOR (Setup Both Systems)**

| Mock | Simulated Data |
|------|----------------|
| `db:select` | 1 customer: John Doe (john@test.com) |
| `salesforce:query` | 1 contact: Alice Smith (alice@test.com) |
| `salesforce:upsert` | Success - John synced to SF |
| `db:insert` | Success - Alice synced to DB |

**Step 2: EXECUTION**

```xml
<munit:execution>
    <flow-ref name="fetchAllData"/>        <!-- Get all data -->
    <flow-ref name="syncDbToSalesforce"/>  <!-- DB → SF -->
    <flow-ref name="syncSalesforceToDb"/>  <!-- SF → DB -->
</munit:execution>
```

**Step 3: VALIDATION**

```xml
<munit:validation>
    <!-- 1 customer from DB -->
    <munit-tools:assert-that expression="#[sizeOf(vars.dbCustomers)]" 
                              is="#[MunitTools::equalTo(1)]"/>
    <!-- 1 contact from SF -->
    <munit-tools:assert-that expression="#[sizeOf(vars.sfContacts)]" 
                              is="#[MunitTools::equalTo(1)]"/>
    <!-- 1 SF-only contact to sync to DB -->
    <munit-tools:assert-that expression="#[sizeOf(vars.sfOnlyContacts)]" 
                              is="#[MunitTools::equalTo(1)]"/>
</munit:validation>
```

---

### MUnit Test Anatomy

```
┌─────────────────────────────────────────────────────────────────┐
│                     COMPLETE MUNIT TEST                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  <munit:test name="test-name" description="..." >               │
│                                                                 │
│    ┌──────────────────────────────────────────────────────┐     │
│    │  1. BEHAVIOR (Given) - Setup Phase                   │     │
│    │  <munit:behavior>                                    │     │
│    │    • Mock external system responses                  │     │
│    │    • Configure test data                             │     │
│    │    • Set up error scenarios                          │     │
│    │  </munit:behavior>                                   │     │
│    └──────────────────────────────────────────────────────┘     │
│                            ↓                                    │
│    ┌──────────────────────────────────────────────────────┐     │
│    │  2. EXECUTION (When) - Action Phase                  │     │
│    │  <munit:execution>                                   │     │
│    │    • Execute flows being tested                      │     │
│    │    • Call flow-ref to trigger logic                  │     │
│    │    • Process test data                               │     │
│    │  </munit:execution>                                  │     │
│    └──────────────────────────────────────────────────────┘     │
│                            ↓                                    │
│    ┌──────────────────────────────────────────────────────┐     │
│    │  3. VALIDATION (Then) - Assertion Phase              │     │
│    │  <munit:validation>                                  │     │
│    │    • Assert expected values                          │     │
│    │    • Verify variables and payload                    │     │
│    │    • Confirm business logic results                  │     │
│    │  </munit:validation>                                 │     │
│    └──────────────────────────────────────────────────────┘     │
│                                                                 │
│  </munit:test>                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Common Mock Patterns

#### Pattern 1: Mock Successful Operation

```xml
<munit-tools:mock-when processor="db:select">
  <munit-tools:then-return>
    <munit-tools:payload value="#[[{id: 1, name: 'Test'}]]"/>
  </munit-tools:then-return>
</munit-tools:mock-when>
```

#### Pattern 2: Mock Error Scenario

```xml
<munit-tools:mock-when processor="salesforce:upsert">
  <munit-tools:then-return>
    <munit-tools:error typeId="SALESFORCE:CONNECTIVITY"/>
  </munit-tools:then-return>
</munit-tools:mock-when>
```

#### Pattern 3: Mock Empty Result

```xml
<munit-tools:mock-when processor="salesforce:query">
  <munit-tools:then-return>
    <munit-tools:payload value="#[[]]"/>
  </munit-tools:then-return>
</munit-tools:mock-when>
```

### Common Assertion Patterns

```xml
<!-- Assert equals -->
<munit-tools:assert-that 
  expression="#[sizeOf(payload)]" 
  is="#[MunitTools::equalTo(2)]"/>

<!-- Assert not null -->
<munit-tools:assert-that 
  expression="#[vars.result]" 
  is="#[MunitTools::notNullValue()]"/>

<!-- Assert null -->
<munit-tools:assert-that 
  expression="#[vars.error]" 
  is="#[MunitTools::nullValue()]"/>

<!-- Assert contains string -->
<munit-tools:assert-that 
  expression="#[payload.message]" 
  is="#[MunitTools::containsString('success')]"/>

<!-- Assert greater than -->
<munit-tools:assert-that 
  expression="#[vars.count]" 
  is="#[MunitTools::greaterThan(0)]"/>

<!-- Assert less than -->
<munit-tools:assert-that 
  expression="#[vars.count]" 
  is="#[MunitTools::lessThan(10)]"/>
```

### Testing Error Scenarios

**Use `expectedErrorType` attribute**:

```xml
<munit:test name="error-test" 
            expectedErrorType="DB:CONNECTIVITY">
  <!-- Test PASSES if this error is thrown -->
  <!-- Test FAILS if no error or different error -->
</munit:test>
```

### Variable Scope in Tests

| Variable | Created By | Available In |
|----------|------------|--------------|
| `vars.dbCustomers` | `fetchAllData` sub-flow | All subsequent flow-refs |
| `vars.sfContacts` | `fetchAllData` sub-flow | All subsequent flow-refs |
| `vars.sfLookup` | `fetchAllData` sub-flow | `syncDbToSalesforce` |
| `vars.dbEmails` | `syncSalesforceToDb` sub-flow | Within that sub-flow |
| `vars.mappedRecords` | `syncDbToSalesforce` sub-flow | Within that sub-flow |
| `vars.sfOnlyContacts` | `syncSalesforceToDb` sub-flow | Can be validated in test |
| `payload` | Current processor output | Current scope only |

---

## 🎯 MUnit vs Integration Testing

### When to Use Each

| Test Type | Purpose | Dependencies | Speed | Examples |
|-----------|---------|--------------|-------|----------|
| **MUnit Tests** | Validate business logic | None (mocked) | Fast (milliseconds) | Email matching, transformation, flow routing |
| **Integration Tests** | Validate system integration | Real DB + SF | Slow (seconds) | Actual data sync, network operations |

### MUnit Test Coverage

This project achieves **100% business logic coverage**:

✅ Happy path scenarios  
✅ Empty data handling  
✅ Error scenarios (DB, SF)  
✅ Email matching logic  
✅ Bidirectional sync  
✅ Duplicate prevention  
✅ Transformation logic  

### Running Coverage Reports

```bash
# Run tests with coverage
mvn clean test -Denv=test

# View report
open target/site/munit/coverage/summary.html
```

---

## 📈 Test Execution Flow Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                    MUNIT TEST EXECUTION                        │
└────────────────────────────────────────────────────────────────┘

1. TEST INITIALIZATION
   │
   ├─► Load test configuration (config-test.yaml)
   ├─► Initialize MUnit framework
   └─► Set up mock environment
       │
       ▼
2. BEHAVIOR PHASE (Setup Mocks)
   │
   ├─► Register db:select mock → Returns test data
   ├─► Register salesforce:query mock → Returns test data
   ├─► Register salesforce:upsert mock → Returns success
   └─► Register db:update mock → Returns affected rows
       │
       ▼
3. EXECUTION PHASE (Run Flow)
   │
   ├─► Call flow-ref: fetchAllData
   │   ├─► db:select intercepted by mock ✓
   │   ├─► Returns mock customer data
   │   ├─► salesforce:query intercepted ✓
   │   └─► Creates lookup maps
   │
   ├─► Call flow-ref: syncDbToSalesforce
   │   ├─► Transforms data
   │   ├─► salesforce:upsert intercepted ✓
   │   ├─► Returns mock SF IDs
   │   └─► db:update intercepted ✓
   │
   └─► Call flow-ref: syncSalesforceToDb
       ├─► Filters SF-only contacts
       └─► db:insert intercepted ✓
       │
       ▼
4. VALIDATION PHASE (Assert Results)
   │
   ├─► Assert: sizeOf(vars.dbCustomers) == 2 ✓
   ├─► Assert: vars.sfLookup is not null ✓
   ├─► Assert: payload is not null ✓
   └─► Assert: No errors thrown ✓
       │
       ▼
5. TEST RESULT
   │
   └─► ✅ TEST PASSED (All assertions true)
       OR
       └─► ❌ TEST FAILED (Assertion failed or unexpected error)
```

---

## 🔍 Debugging MUnit Tests

### Common Issues and Solutions

<details>
<summary><strong>❌ Test fails with "Payload is null"</strong></summary>

**Cause**: Mock not returning data or wrong processor name

**Solution**:
```xml
<!-- Check processor name matches exactly -->
<munit-tools:mock-when processor="db:select">  <!-- ✓ Correct -->
<munit-tools:mock-when processor="database:select">  <!-- ✗ Wrong -->
```
</details>

<details>
<summary><strong>❌ Test fails with "Variable not found"</strong></summary>

**Cause**: Variable created in sub-flow not yet executed

**Solution**: Ensure flow-ref executes before accessing variables
```xml
<flow-ref name="fetchAllData"/>  <!-- Creates vars.dbCustomers -->
<!-- Now vars.dbCustomers is available -->
```
</details>

<details>
<summary><strong>❌ Error test passes when it shouldn't</strong></summary>

**Cause**: Wrong error type or error not thrown

**Solution**:
```xml
<!-- Check error type matches exactly -->
expectedErrorType="DB:CONNECTIVITY"  <!-- ✓ -->
expectedErrorType="DB:ERROR"  <!-- ✗ -->
```
</details>

<details>
<summary><strong>❌ Mock not intercepting processor</strong></summary>

**Cause**: Mock defined after execution or wrong processor path

**Solution**: Move mock to `<munit:behavior>` section
```xml
<munit:behavior>
  <munit-tools:mock-when processor="db:select">
    <!-- Must be here, before execution -->
  </munit-tools:mock-when>
</munit:behavior>

<munit:execution>
  <flow-ref name="fetchAllData"/>
</munit:execution>
```
</details>

### Viewing Test Results in Anypoint Studio

1. Run MUnit test
2. View **MUnit** tab at bottom
3. Green ✅ = Passed, Red ❌ = Failed
4. Click test name to see details
5. View **Console** for detailed logs

### Running Individual Tests

```bash
# Run specific test suite
mvn clean test -Denv=test -Dmunit.test=db-to-sf-sync-test-suite.xml

# Run specific test case
mvn clean test -Denv=test -Dmunit.test=db-to-sf-sync-test-suite.xml#db-to-sf-happy-path-test
```

---


## 🔧 Troubleshooting

### Common Issues

<details>
<summary><strong>❌ "No records to sync" in logs</strong></summary>

**Cause**: The sync only picks up records modified in the last 24 hours.

**Solution**:
- For database: 
  ```sql
  UPDATE customers SET last_modified_date = NOW() WHERE customer_id = 1;
  ```
- For Salesforce: Edit and save the contact again
</details>

<details>
<summary><strong>❌ Cannot connect to Salesforce</strong></summary>

**Verify**:
1. Username is correct (full email)
2. Password is correct
3. Security token is valid
4. URL: `https://login.salesforce.com/services/Soap/u/64.0`
</details>

<details>
<summary><strong>❌ Cannot connect to Database</strong></summary>

**Verify**:
1. MySQL service is running
2. Database `customerdb` exists
3. Username and password are correct
4. Port 3306 is accessible
</details>

<details>
<summary><strong>❌ Duplicate key error on email</strong></summary>

**Cause**: Email must be unique in both systems.

**Solution**: 
- Use unique email addresses for each customer
- Check if record already exists before inserting
</details>

<details>
<summary><strong>❌ MUnit tests failing</strong></summary>

**Verify**:
1. Run with correct environment: `mvn clean test -Denv=test`
2. Check `src/test/resources/config/config-test.yaml` exists
3. Ensure all dependencies are downloaded: `mvn clean install -DskipTests`
</details>

---

## 📚 Additional Resources

- [MuleSoft Documentation](https://docs.mulesoft.com/)
- [MUnit Testing Guide](https://docs.mulesoft.com/munit/latest/)
- [Salesforce Connector Documentation](https://docs.mulesoft.com/salesforce-connector/latest/)
- [Database Connector Documentation](https://docs.mulesoft.com/db-connector/latest/)

---

<div align="center">

**Built with ❤️ using MuleSoft Anypoint Platform**

</div>
