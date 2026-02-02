<div align="center">

# Salesforce - Database Customer Sync

**A MuleSoft Integration Solution for Bidirectional Customer Data Synchronization**

[![Mule Runtime](https://img.shields.io/badge/Mule%20Runtime-4.10.2-blue.svg)](https://docs.mulesoft.com/)
[![MUnit](https://img.shields.io/badge/MUnit-3.6.2-green.svg)](https://docs.mulesoft.com/munit/latest/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## 📋 Table of Contents

1. [Overview](#-overview)
2. [Architecture](#-architecture)
3. [Prerequisites](#-prerequisites)
4. [Installation & Setup](#-installation--setup)
5. [Running the Application](#-running-the-application)
6. [Testing](#-testing)
7. [Troubleshooting](#-troubleshooting)

---

## 📖 Overview

This MuleSoft application provides **bidirectional customer data synchronization** between MySQL database and Salesforce CRM using **Email as the primary business key**.

### Key Features

- **Bidirectional Sync**: Data flows both ways (DB ↔ Salesforce)
- **Email-Based Matching**: Uses email as natural business key to prevent duplicates
- **Scheduled Execution**: Configurable scheduler for automated syncing
- **Comprehensive Error Handling**: 6 error types with consistent JSON responses
- **100% Test Coverage**: 24 MUnit tests covering all scenarios

### Technical Specifications

| Component | Value |
|-----------|-------|
| Mule Runtime | 4.10.2 |
| MUnit Version | 3.6.2 |
| Sync Pattern | Bidirectional |
| Business Key | Email (case-insensitive) |

---

## 🏗️ Architecture

### Bidirectional Sync Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                  UNIFIED BIDIRECTIONAL SYNC                     │
│                                                                 │
│   ┌─────────────┐                        ┌─────────────┐        │
│   │   MySQL     │                        │ Salesforce  │        │
│   │  Database   │◄──────────────────────►│    CRM      │        │
│   └──────┬──────┘    Email Matching     └──────┬──────┘        │
│          │                                      │               │
│          ▼                                      ▼               │
│   ┌──────────────────────────────────────────────────────┐      │
│   │         STEP 1: fetchAllData (Sub-Flow)              │      │
│   │   • SELECT customers from DB (last 24h + no SF ID)   │      │
│   │   • QUERY contacts from Salesforce (recent changes)  │      │
│   │   • Create email → SF record HashMap (O(1) lookup)   │      │
│   └──────────────────────────────────────────────────────┘      │
│                            │                                    │
│                            ▼                                    │
│   ┌──────────────────────────────────────────────────────┐      │
│   │      STEP 2: syncDbToSalesforce (Sub-Flow)           │      │
│   │   • Match DB customers by EMAIL (case-insensitive)   │      │
│   │   • If match found → UPDATE SF contact               │      │
│   │   • If no match → CREATE new SF contact              │      │
│   │   • UPDATE DB with returned Salesforce IDs           │      │
│   └──────────────────────────────────────────────────────┘      │
│                            │                                    │
│                            ▼                                    │
│   ┌──────────────────────────────────────────────────────┐      │
│   │      STEP 3: syncSalesforceToDb (Sub-Flow)           │      │
│   │   • Find SF contacts NOT in DB (email comparison)    │      │
│   │   • INSERT new customers to DB                       │      │
│   │   • Link with Salesforce ID for future syncs         │      │
│   └──────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Main Flow: `bidirectionalCustomerSync`

**Trigger**: Scheduler (configurable frequency, default 60 seconds)

```xml
<flow name="bidirectionalCustomerSync">
    <scheduler/> ──► <flow-ref: fetchAllData/> 
                 ──► <flow-ref: syncDbToSalesforce/> 
                 ──► <flow-ref: syncSalesforceToDb/>
                 ──► <error-handler: globalErrorHandler/>
</flow>
```

### Sub-Flow 1: `fetchAllData`

**Purpose**: Load all data from both systems and create lookup maps

```
┌───────────────────────────────────────────────────────────┐
│  DB Query                    SF Query                     │
│  └─► SELECT customers        └─► SELECT contacts          │
│      WHERE modified >= -24h       WHERE modified >= -24h  │
│      OR salesforce_id IS NULL     OR email != null        │
│                                                            │
│  Result:                     Result:                      │
│  vars.dbCustomers (Array)    vars.sfContacts (Array)      │
│                                                            │
│  ┌────────────────────────────────────────────┐           │
│  │  Create Email Lookup Map                   │           │
│  │  vars.sfLookup = {                         │           │
│  │    "john@test.com": [SF Contact Object],   │           │
│  │    "jane@test.com": [SF Contact Object]    │           │
│  │  }                                          │           │
│  └────────────────────────────────────────────┘           │
└───────────────────────────────────────────────────────────┘
```

**Key Operations**:
- Fetches records modified in last 24 hours
- Creates HashMap for O(1) email lookups (performance optimization)
- Uses lowercase emails for case-insensitive matching

### Sub-Flow 2: `syncDbToSalesforce`

**Purpose**: Sync database customers to Salesforce using email matching

```
┌─────────────────────────────────────────────────────────────┐
│  For each DB customer:                                      │
│                                                             │
│  1. Filter out customers without email                     │
│     vars.dbCustomers.filter(!isEmpty(email))               │
│                                                             │
│  2. Check if email exists in SF                            │
│     existingSfRecord = vars.sfLookup[lower(email)]         │
│                                                             │
│  3. Prepare SF payload                                     │
│     ┌──────────────────────────────────┐                   │
│     │ If existing:                     │                   │
│     │   {Id: "003XXX", ...}  → UPDATE  │                   │
│     │ If new:                          │                   │
│     │   {Email: "...", ...}  → CREATE  │                   │
│     └──────────────────────────────────┘                   │
│                                                             │
│  4. Salesforce Upsert (Email as external ID)               │
│     Result: [{id: "003XXX", success: true}, ...]           │
│                                                             │
│  5. Update DB with Salesforce IDs                          │
│     UPDATE customers                                       │
│     SET salesforce_id = :id,                               │
│         last_modified_date = last_modified_date  ← No loop │
│     WHERE customer_id = :id                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Anti-Pattern Prevention**:
- `last_modified_date = last_modified_date` prevents infinite sync loops
- Parameterized queries prevent SQL injection
- `ON DUPLICATE KEY UPDATE` ensures idempotency

### Sub-Flow 3: `syncSalesforceToDb`

**Purpose**: Sync Salesforce-only contacts to database

```
┌─────────────────────────────────────────────────────────────┐
│  1. Create DB email list                                    │
│     dbEmails = ["john@test.com", "jane@test.com"]          │
│                                                             │
│  2. Find SF contacts NOT in DB                             │
│     vars.sfOnlyContacts = sfContacts.filter(               │
│       !isEmpty(email) &&                                   │
│       !(dbEmails contains lower(email))                    │
│     )                                                       │
│                                                             │
│  3. Transform to DB format                                 │
│     [{                                                      │
│       salesforce_id: "003AAA",                             │
│       first_name: "Alice",                                 │
│       last_name: "Johnson",                                │
│       email: "alice@test.com",                             │
│       phone: "555-1234"                                    │
│     }]                                                      │
│                                                             │
│  4. Insert to Database (with upsert safety)               │
│     INSERT INTO customers (...)                            │
│     VALUES (...)                                           │
│     ON DUPLICATE KEY UPDATE ← Prevents duplicates          │
│       salesforce_id = :id,                                 │
│       first_name = :first_name,                            │
│       ...                                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Field Mapping

| Database Field | Salesforce Field | Notes |
|----------------|------------------|-------|
| `customer_id` | — | Auto-increment primary key |
| `salesforce_id` | `Id` | Links to SF record (VARCHAR 18) |
| `first_name` | `FirstName` | Optional in both |
| `last_name` | `LastName` | ✅ Required in both |
| **`email`** | **`Email`** | **🔑 Business Key (Unique)** |
| `phone` | `Phone` | Optional in both |
| `last_modified_date` | `LastModifiedDate` | Auto-updated timestamp |

### Data Flow Example

**Scenario**: New customer in DB, existing contact in SF

```
Initial State:
├─ DB:  John (email: john@test.com, sf_id: NULL)
└─ SF:  Alice (email: alice@test.com, Id: 003AAA)

Step 1 - fetchAllData:
├─ vars.dbCustomers = [John]
├─ vars.sfContacts = [Alice]
└─ vars.sfLookup = {"alice@test.com": [Alice]}

Step 2 - syncDbToSalesforce:
├─ John's email NOT in sfLookup
├─ CREATE new SF contact for John
├─ SF returns Id: 003XXX
└─ UPDATE DB: SET salesforce_id = '003XXX' WHERE email = 'john@test.com'

Step 3 - syncSalesforceToDb:
├─ Alice's email NOT in DB
├─ INSERT Alice to DB with salesforce_id = '003AAA'
└─ Both systems now in sync

Final State:
├─ DB:  John (sf_id: 003XXX), Alice (sf_id: 003AAA)
└─ SF:  John (Id: 003XXX), Alice (Id: 003AAA)
```

---

## 🔧 Prerequisites

- **Anypoint Studio** 7.x or later
- **Java JDK** 8 or 11
- **MySQL** 5.7+ or 8.0
- **Salesforce Developer Account** ([Sign up free](https://developer.salesforce.com/signup))
- **Maven** 3.6+

---

## 🚀 Installation & Setup

### Step 1: Clone Repository

```bash
git clone https://github.com/kamranxdev/sf-db-customer-sync.git
cd sf-db-customer-sync
```

### Step 2: Configure Database

```sql
-- Create database
CREATE DATABASE customerdb;
USE customerdb;

-- Create customers table
CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    salesforce_id VARCHAR(18) UNIQUE,
    first_name VARCHAR(50),
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20),
    last_modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_last_modified (last_modified_date)
);
```

### Step 3: Get Salesforce Security Token

1. Log in to Salesforce
2. Go to **Settings** → **Reset My Security Token**
3. Check your email for the token

### Step 4: Configure Properties

Edit `src/main/resources/config/config-dev.yaml`:

```yaml
# Database Configuration
db:
  host: "localhost"
  port: "3306"
  database: "customerdb"
  user: "root"
  password: "your_password"

# Salesforce Configuration
salesforce:
  username: "your_salesforce_email@example.com"
  password: "your_password"
  securityToken: "your_security_token"
  url: "https://login.salesforce.com/services/Soap/u/64.0"

# Scheduler Configuration
scheduler:
  frequency: "60000"  # 60 seconds
```

### Step 5: Build Project

```bash
mvn clean install
```

---

## ▶️ Running the Application

### Run in Anypoint Studio

1. Right-click on project → **Run As** → **Mule Application**
2. Check console for "Application deployed successfully"
3. Sync runs automatically based on scheduler frequency

### Run via Maven

```bash
mvn clean install
mvn mule:deploy
```

### Verify Sync

Check logs for:
```
INFO  - Bidirectional sync started at 2026-02-02T10:30:00
INFO  - Fetched 2 customers from DB
INFO  - Fetched 3 contacts from Salesforce
INFO  - Synced 2 records from DB to Salesforce
INFO  - Synced 1 SF-only contacts to DB
INFO  - Bidirectional sync completed successfully
```

---

## 🧪 Testing

### Test Architecture

```
┌────────────────────────────────────────────────────────────┐
│                  MUnit Test Suite (24 Tests)               │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  Happy Path  │  │  Edge Cases  │  │ Error Handling  │  │
│  │   (4 tests)  │  │  (8 tests)   │  │   (12 tests)    │  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
│         │                 │                    │           │
│         ▼                 ▼                    ▼           │
│  • DB to SF sync   • Empty datasets    • DB:CONNECTIVITY  │
│  • SF to DB sync   • Null emails       • SF:CONNECTIVITY  │
│  • Email matching  • Large datasets    • DB:QUERY_EXEC    │
│  • Full bidir sync • Case sensitivity  • SF:INVALID_INPUT │
│                    • No new records    • MULE:EXPRESSION  │
│                    • Null SF IDs       • Response checks  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Run All Tests

```bash
mvn clean test
```

### Test Coverage Summary

| Category | Tests | Description |
|----------|-------|-------------|
| **Happy Path** | 4 | Core sync functionality |
| **Edge Cases** | 8 | Empty data, nulls, large datasets |
| **Error Handling** | 6 | DB/SF connectivity, validation errors |
| **Error Responses** | 6 | Response structure validation |
| **Total** | **24** | **100% Coverage** |

### MUnit Test Anatomy

Each test follows the **Given-When-Then** pattern:

```
┌─────────────────────────────────────────────────────────┐
│  <munit:test name="db-to-sf-sync-test">                │
│                                                         │
│    1. BEHAVIOR (Given) - Setup                         │
│       ┌─────────────────────────────────┐              │
│       │ Mock external systems:          │              │
│       │ • db:select → Return 2 records  │              │
│       │ • sf:query → Return empty []    │              │
│       │ • sf:upsert → Return success    │              │
│       │ • db:update → Return affected:1 │              │
│       └─────────────────────────────────┘              │
│                                                         │
│    2. EXECUTION (When) - Action                        │
│       ┌─────────────────────────────────┐              │
│       │ <flow-ref name="fetchAllData"/> │              │
│       │ <flow-ref name="syncDbToSF"/>   │              │
│       └─────────────────────────────────┘              │
│                                                         │
│    3. VALIDATION (Then) - Assert                       │
│       ┌─────────────────────────────────┐              │
│       │ Assert:                         │              │
│       │ • vars.dbCustomers size = 2     │              │
│       │ • payload is not null           │              │
│       └─────────────────────────────────┘              │
│                                                         │
│  </munit:test>                                         │
└─────────────────────────────────────────────────────────┘
```

### Key Test Cases

#### 1. Happy Path Tests

| Test | Validates |
|------|-----------|
| `db-to-sf-sync-test` | ✅ DB customers fetched<br>✅ SF upsert succeeds<br>✅ DB updated with SF IDs |
| `sf-to-db-sync-test` | ✅ SF contacts fetched<br>✅ New customers inserted to DB<br>✅ SF IDs linked |
| `db-to-sf-email-match-test` | ✅ Existing SF contact found by email<br>✅ UPDATE instead of CREATE |
| `bidirectional-full-sync-test` | ✅ Both directions work<br>✅ No duplicates created |

#### 2. Edge Case Tests

| Test | Validates |
|------|-----------|
| `empty-email-filtering-test` | ✅ Records without emails filtered out |
| `null-sf-id-handling-test` | ✅ Null SF IDs handled gracefully |
| `case-insensitive-email-match-test` | ✅ Email matching works regardless of case |
| `large-dataset-test` | ✅ Performance with 100 records |
| `sf-to-db-no-new-records-test` | ✅ No duplicates when all records exist |
| `db-to-sf-empty-records-test` | ✅ Handles empty DB gracefully |
| `sf-to-db-empty-sf-test` | ✅ Handles empty SF gracefully |
| `sf-query-missing-fields-test` | ✅ Handles null fields with defaults |

#### 3. Error Handling Tests

**Integration Tests** (6 tests):

```
┌─────────────────────────────────────────────────────┐
│  Test Flow → Trigger Error → Catch Error           │
├─────────────────────────────────────────────────────┤
│  db-to-sf-db-error-test                            │
│  └─► Mock db:select throw DB:CONNECTIVITY          │
│      └─► Expect: DB:CONNECTIVITY error raised      │
│                                                     │
│  db-query-execution-error-test                     │
│  └─► Mock db:select throw DB:QUERY_EXECUTION       │
│      └─► Expect: DB:QUERY_EXECUTION error raised   │
│                                                     │
│  sf-invalid-input-error-test                       │
│  └─► Mock sf:upsert throw SF:INVALID_INPUT         │
│      └─► Expect: SF:INVALID_INPUT error raised     │
│                                                     │
│  transformation-error-test                         │
│  └─► Mock with malformed data                      │
│      └─► Expect: MULE:EXPRESSION error raised      │
│                                                     │
│  sf-upsert-partial-failure-test                    │
│  └─► Mock sf:upsert with mixed success/failure     │
│      └─► Expect: Only successful records processed │
│                                                     │
│  bidirectional-flow-error-test                     │
│  └─► Mock main flow error                          │
│      └─► Expect: Global error handler invoked      │
└─────────────────────────────────────────────────────┘
```

**Error Response Validation Tests** (6 tests):

These tests validate the JSON structure returned by error handlers:

```xml
<!-- Test triggers error and validates response -->
<try>
  <flow-ref name="fetchAllData"/>  <!-- Triggers mocked error -->
  <error-handler>
    <on-error-continue type="DB:CONNECTIVITY">
      <!-- Validate error response structure -->
      <assert payload.errorType = "DATABASE_CONNECTION_ERROR"/>
      <assert payload.message exists/>
      <assert payload.timestamp exists/>
      <assert payload.flowName exists/>
    </on-error-continue>
  </error-handler>
</try>
```

### Error Handler Coverage

All 6 error types tested with consistent JSON responses:

```json
{
  "errorType": "DATABASE_CONNECTION_ERROR",
  "message": "Failed to connect to the database",
  "details": "Connection refused: localhost:3306",
  "timestamp": "2026-02-02T10:30:00",
  "flowName": "bidirectionalCustomerSync"
}
```

| Error Type | Handler | Integration Tests | Response Tests |
|------------|---------|------------------|----------------|
| `DB:CONNECTIVITY` | Database Connection Error | ✅ 3 | ✅ 1 |
| `DB:QUERY_EXECUTION` | Database Query Error | ✅ 3 | ✅ 1 |
| `SALESFORCE:CONNECTIVITY` | Salesforce Connection Error | ✅ 2 | ✅ 1 |
| `SALESFORCE:INVALID_INPUT` | Salesforce Validation Error | ✅ 1 | ✅ 1 |
| `MULE:EXPRESSION` | Transformation Error | ✅ 1 | ✅ 1 |
| `ANY` | Generic Error | ✅ 1 | ✅ 1 |

### Mock Pattern Examples

**Mock Successful Operation**:
```xml
<munit-tools:mock-when processor="db:select">
  <munit-tools:then-return>
    <munit-tools:payload value="#[[
      {customer_id: 1, email: 'john@test.com', ...}
    ]]"/>
  </munit-tools:then-return>
</munit-tools:mock-when>
```

**Mock Error Scenario**:
```xml
<munit-tools:mock-when processor="salesforce:upsert">
  <munit-tools:then-return>
    <munit-tools:error typeId="SALESFORCE:CONNECTIVITY"/>
  </munit-tools:then-return>
</munit-tools:mock-when>
```

### Run Tests in Anypoint Studio

1. Right-click on test suite → **Run As** → **MUnit Test**
2. View results in **MUnit** tab
3. Green ✅ = Pass, Red ❌ = Fail
4. Click test name for detailed logs

---

## 🔧 Troubleshooting

### Common Issues

<details>
<summary><strong>❌ "No records to sync" in logs</strong></summary>

**Cause**: Sync only picks up records modified in the last 24 hours.

**Solution**:
```sql
UPDATE customers SET last_modified_date = NOW() WHERE customer_id = 1;
```
</details>

<details>
<summary><strong>❌ Cannot connect to Salesforce</strong></summary>

**Verify**:
- Username is correct (full email)
- Password is correct
- Security token is valid (reset if needed)
- URL: `https://login.salesforce.com/services/Soap/u/64.0`
</details>

<details>
<summary><strong>❌ Cannot connect to Database</strong></summary>

**Verify**:
- MySQL service is running
- Database `customerdb` exists
- Credentials are correct in config file
- Port 3306 is accessible
</details>

<details>
<summary><strong>❌ Duplicate key error on email</strong></summary>

**Cause**: Email must be unique in both systems.

**Solution**: Use unique email addresses for each customer.
</details>

<details>
<summary><strong>❌ MUnit tests failing</strong></summary>

**Solution**:
```bash
# Clean and reinstall dependencies
mvn clean install -DskipTests

# Run tests with correct environment
mvn clean test -Denv=test
```
</details>

---

## 📊 Project Structure

```
sf-db-customer-sync/
├── src/
│   ├── main/
│   │   ├── mule/
│   │   │   ├── sf-db-customer-sync.xml    # Main sync flows
│   │   │   ├── global-config.xml          # DB & SF configurations
│   │   │   └── error-handler.xml          # Error handling (6 types)
│   │   └── resources/
│   │       ├── config/
│   │       │   └── config-dev.yaml        # Configuration properties
│   │       ├── database-schema.sql        # DB schema
│   │       └── log4j2.xml                 # Logging config
│   └── test/
│       ├── munit/
│       │   └── sf-db-customer-sync-test-suite.xml   # 24 tests
│       └── resources/
│           └── config/
│               └── config-test.yaml       # Test configuration
├── pom.xml                                # Maven dependencies
└── README.md
```

---

## 🎯 Key Design Decisions

### Why Email as Business Key?

| Approach | Pros | Cons |
|----------|------|------|
| Custom External ID | Direct DB ID linking | Requires custom SF field |
| **Email (chosen)** | ✅ Natural key, works natively | Must be unique |
| Salesforce ID only | Guaranteed unique | Only exists after SF creation |

### Best Practices Implemented

✅ **Case-insensitive email matching** - Uses `lower()` function  
✅ **Idempotent operations** - `ON DUPLICATE KEY UPDATE`  
✅ **Anti-sync loop protection** - `last_modified_date = last_modified_date`  
✅ **SQL injection prevention** - Parameterized queries  
✅ **O(1) lookups** - HashMap for email matching  
✅ **Null-safe operations** - Default values throughout  
✅ **Comprehensive error handling** - 6 specific error types  
✅ **100% test coverage** - All flows and errors tested  

---

## 📚 Additional Resources

- [MuleSoft Documentation](https://docs.mulesoft.com/)
- [MUnit Testing Guide](https://docs.mulesoft.com/munit/latest/)
- [Salesforce Connector](https://docs.mulesoft.com/salesforce-connector/latest/)
- [Database Connector](https://docs.mulesoft.com/db-connector/latest/)

---

<div align="center">

**Built with ❤️ using MuleSoft Anypoint Platform**

</div>
