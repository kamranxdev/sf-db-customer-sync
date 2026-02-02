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

### Detailed Test Explanations

#### 1. Happy Path Tests

##### Test: `db-to-sf-sync-test`
**Purpose**: Verify successful synchronization from Database to Salesforce

```
Given:
  DB returns: 2 customers (John Doe, Jane Smith) - no SF IDs
  SF returns: Empty list (no existing contacts)
  
When:
  1. fetchAllData loads both datasets
  2. syncDbToSalesforce processes DB customers
  
Then:
  ✅ vars.dbCustomers contains 2 records
  ✅ SF upsert creates 2 new contacts
  ✅ DB updated with new Salesforce IDs
  ✅ Payload is not null
```

##### Test: `sf-to-db-sync-test`
**Purpose**: Verify successful synchronization from Salesforce to Database

```
Given:
  DB returns: Empty list (no customers)
  SF returns: 2 contacts (Alice, Bob)
  
When:
  1. fetchAllData loads both datasets
  2. syncSalesforceToDb finds SF-only contacts
  
Then:
  ✅ vars.sfContacts contains 2 records
  ✅ vars.sfOnlyContacts contains 2 records
  ✅ Both contacts inserted to DB with SF IDs
```

##### Test: `db-to-sf-email-match-test`
**Purpose**: Verify email-based matching finds existing Salesforce contacts

```
Given:
  DB returns: John Doe (john.doe@test.com, sf_id: null)
  SF returns: John Doe (john.doe@test.com, Id: 003EXISTING)
  
When:
  1. fetchAllData creates email lookup map
  2. syncDbToSalesforce matches by email
  
Then:
  ✅ vars.sfLookup contains email mapping
  ✅ Existing SF contact found (UPDATE not CREATE)
  ✅ DB record linked to existing SF ID
```

##### Test: `bidirectional-full-sync-test`
**Purpose**: Verify complete bidirectional sync without duplicates

```
Given:
  DB returns: 1 customer (John)
  SF returns: 1 contact (Alice)
  
When:
  1. fetchAllData loads both
  2. syncDbToSalesforce syncs John → SF
  3. syncSalesforceToDb syncs Alice → DB
  
Then:
  ✅ vars.dbCustomers = 1
  ✅ vars.sfContacts = 1
  ✅ vars.sfOnlyContacts = 1 (Alice)
  ✅ No duplicates created
  ✅ Both systems have both records
```

#### 2. Edge Case Tests

##### Test: `empty-email-filtering-test`
**Purpose**: Verify records without emails are filtered out

```
Given:
  DB returns: 3 records
    - Record 1: email = "valid@test.com"
    - Record 2: email = ""
    - Record 3: email = null
  SF returns: Empty list
  
When:
  syncDbToSalesforce filters by email
  
Then:
  ✅ vars.mappedRecords contains only 1 record
  ✅ Empty and null emails excluded
  ✅ Only valid record sent to SF
```

##### Test: `null-sf-id-handling-test`
**Purpose**: Verify null Salesforce IDs don't cause DB update errors

```
Given:
  DB returns: 2 customers
  SF upsert returns: Mixed results
    - Record 1: {id: "003XXX", success: true}
    - Record 2: {id: null, success: false}
  
When:
  Preparing DB updates
  
Then:
  ✅ Filter removes null SF IDs
  ✅ Only successful record (003XXX) updates DB
  ✅ No constraint violations
```

##### Test: `case-insensitive-email-match-test`
**Purpose**: Verify email matching works regardless of case

```
Given:
  DB returns: john@test.com (lowercase)
  SF returns: JOHN@TEST.COM (uppercase)
  
When:
  Email lookup uses lower() function
  
Then:
  ✅ Match found despite case difference
  ✅ No duplicate creation
  ✅ Existing SF record updated
```

##### Test: `large-dataset-test`
**Purpose**: Verify performance with large number of records

```
Given:
  DB returns: 100 customers
  SF returns: Empty list
  
When:
  Processing all 100 records
  
Then:
  ✅ All 100 customers fetched
  ✅ All 100 mapped records created
  ✅ Performance acceptable
  ✅ No memory issues
```

##### Test: `sf-to-db-no-new-records-test`
**Purpose**: Verify no duplicates when all SF contacts exist in DB

```
Given:
  DB returns: Alice (alice@test.com, sf_id: 003AAA1)
  SF returns: Alice (alice@test.com, Id: 003AAA1)
  
When:
  syncSalesforceToDb checks for SF-only contacts
  
Then:
  ✅ vars.sfOnlyContacts is empty (size = 0)
  ✅ No insert operation performed
  ✅ No duplicates created
```

##### Test: `db-to-sf-empty-records-test`
**Purpose**: Verify graceful handling when no DB records exist

```
Given:
  DB returns: Empty list []
  SF returns: Empty list []
  
When:
  Running sync flows
  
Then:
  ✅ vars.dbCustomers size = 0
  ✅ No errors thrown
  ✅ "No DB records to sync" logged
```

##### Test: `sf-to-db-empty-sf-test`
**Purpose**: Verify graceful handling when no SF contacts exist

```
Given:
  DB returns: 1 customer (John)
  SF returns: Empty list []
  
When:
  syncSalesforceToDb looks for SF-only contacts
  
Then:
  ✅ vars.sfContacts size = 0
  ✅ vars.sfOnlyContacts size = 0
  ✅ No insert operations
  ✅ No errors thrown
```

##### Test: `sf-query-missing-fields-test`
**Purpose**: Verify handling of SF contacts with null/missing fields

```
Given:
  SF returns: Contact with null FirstName and null Phone
    {Id: "003AAA", FirstName: null, LastName: "Doe", 
     Email: "john@test.com", Phone: null}
  
When:
  Transforming to DB format with defaults
  
Then:
  ✅ first_name defaults to ""
  ✅ last_name uses actual value
  ✅ phone defaults to null
  ✅ No transformation errors
```

#### 3. Error Handling Tests

##### Test: `db-to-sf-db-error-test`
**Purpose**: Verify database connectivity error handling

```
Given:
  db:select is mocked to throw DB:CONNECTIVITY error
  
When:
  fetchAllData attempts to query database
  
Then:
  ✅ DB:CONNECTIVITY error is raised
  ✅ Global error handler catches it
  ✅ Error logged with details
  ✅ Test expects error type: DB:CONNECTIVITY
```

**Error Response**:
```json
{
  "errorType": "DATABASE_CONNECTION_ERROR",
  "message": "Failed to connect to the database",
  "details": "Connection refused: localhost:3306"
}
```

##### Test: `db-query-execution-error-test`
**Purpose**: Verify database query execution error handling

```
Given:
  db:select throws DB:QUERY_EXECUTION error
  (simulates invalid SQL, constraint violations, etc.)
  
When:
  fetchAllData executes query
  
Then:
  ✅ DB:QUERY_EXECUTION error raised
  ✅ Error handler processes it
  ✅ Appropriate error message logged
```

**Use Cases**:
- Invalid SQL syntax
- Table/column not found
- Database constraint violations
- Permission denied errors

##### Test: `db-update-error-test`
**Purpose**: Verify database update operation error handling

```
Given:
  db:select returns 1 customer
  sf:query returns empty
  sf:upsert succeeds with ID
  db:update throws DB:QUERY_EXECUTION error
  
When:
  syncDbToSalesforce tries to update DB with SF ID
  
Then:
  ✅ DB:QUERY_EXECUTION error raised
  ✅ Error occurs after successful SF upsert
  ✅ Partial success scenario handled
```

##### Test: `db-to-sf-sf-error-test`
**Purpose**: Verify Salesforce connectivity error during upsert

```
Given:
  db:select returns 1 customer
  sf:query returns empty
  sf:upsert throws SALESFORCE:CONNECTIVITY error
  
When:
  syncDbToSalesforce attempts upsert
  
Then:
  ✅ SALESFORCE:CONNECTIVITY error raised
  ✅ DB query succeeded but SF failed
  ✅ Error propagated correctly
```

**Error Response**:
```json
{
  "errorType": "SALESFORCE_CONNECTION_ERROR",
  "message": "Failed to connect to Salesforce. Check credentials and security token.",
  "details": "Authentication failure"
}
```

##### Test: `sf-to-db-sf-error-test`
**Purpose**: Verify Salesforce connectivity error during query

```
Given:
  db:select returns customers
  sf:query throws SALESFORCE:CONNECTIVITY error
  
When:
  fetchAllData attempts to query Salesforce
  
Then:
  ✅ SALESFORCE:CONNECTIVITY error raised
  ✅ Occurs during data fetch phase
  ✅ Error handler invoked
```

##### Test: `sf-invalid-input-error-test`
**Purpose**: Verify Salesforce validation error handling

```
Given:
  db:select returns customer with invalid data
  sf:upsert throws SALESFORCE:INVALID_INPUT error
  (missing required fields, invalid format, etc.)
  
When:
  syncDbToSalesforce attempts upsert
  
Then:
  ✅ SALESFORCE:INVALID_INPUT error raised
  ✅ Validation error details captured
  ✅ User-friendly error message returned
```

**Error Response**:
```json
{
  "errorType": "SALESFORCE_VALIDATION_ERROR",
  "message": "Invalid data for Salesforce. Check required fields.",
  "details": "Required field missing: LastName"
}
```

##### Test: `transformation-error-test`
**Purpose**: Verify DataWeave transformation error handling

```
Given:
  db:select returns malformed data structure
  DataWeave transformation fails with invalid expression
  
When:
  Attempting to transform data
  
Then:
  ✅ MULE:EXPRESSION error raised
  ✅ Transformation error caught
  ✅ Error details include expression info
```

**Causes**:
- Malformed data structure
- Invalid DataWeave expression
- Type mismatch errors
- Null pointer in transformation

##### Test: `sf-upsert-partial-failure-test`
**Purpose**: Verify handling of partial Salesforce upsert failures

```
Given:
  db:select returns 3 customers
  sf:upsert returns mixed results:
    - Record 1: {id: "003AAA", success: true}
    - Record 2: {id: "003BBB", success: true}
    - Record 3: {id: null, success: false, error: "Validation"}
  
When:
  Processing upsert results and updating DB
  
Then:
  ✅ Successful records (003AAA, 003BBB) processed
  ✅ Failed record (null) filtered out
  ✅ Only 2 DB updates performed
  ✅ No errors thrown
```

**Real-World Scenario**:
```
Batch of 100 records:
├─ 95 succeed → Update DB with SF IDs
├─ 5 fail → Log errors, skip DB update
└─ Overall process continues successfully
```

##### Test: `db-insert-constraint-error-test`
**Purpose**: Verify database constraint violation during SF-to-DB sync

```
Given:
  DB has existing customer: john@test.com
  SF returns contact: john@test.com (duplicate email)
  db:insert throws DB:QUERY_EXECUTION (unique constraint)
  
When:
  syncSalesforceToDb attempts to insert
  
Then:
  ✅ DB:QUERY_EXECUTION error raised
  ✅ Constraint violation detected
  ✅ ON DUPLICATE KEY UPDATE would prevent this in reality
```

##### Test: `bidirectional-flow-error-test`
**Purpose**: Verify main flow error handling via global error handler

```
Given:
  Main flow: bidirectionalCustomerSync
  db:select throws DB:CONNECTIVITY error
  
When:
  Flow execution begins
  
Then:
  ✅ DB:CONNECTIVITY error raised
  ✅ Global error handler catches it
  ✅ Error logged at flow level
  ✅ Graceful failure (no crash)
```

#### 4. Error Response Validation Tests

These tests verify the **structure** of error responses returned by error handlers.

##### Test: `error-handler-db-connectivity-response-test`
**Purpose**: Validate DB connectivity error response structure

```
Test Pattern:
  <try>
    <flow-ref name="fetchAllData"/>  ← Triggers DB:CONNECTIVITY
    <error-handler>
      <on-error-continue type="DB:CONNECTIVITY">
        <!-- Capture error response -->
        <set-variable name="errorResponse" value="#[payload]"/>
      </on-error-continue>
    </error-handler>
  </try>
  
Assertions:
  ✅ payload.errorType = "DATABASE_CONNECTION_ERROR"
  ✅ payload.message exists and is not empty
  ✅ payload.details contains error description
  ✅ payload.timestamp is valid date format
  ✅ payload.flowName = "bidirectionalCustomerSync"
```

##### Test: `error-handler-db-query-response-test`
**Purpose**: Validate DB query execution error response structure

```
Validates:
  ✅ errorType = "DATABASE_QUERY_ERROR"
  ✅ message = "Database query execution failed"
  ✅ details includes SQL error information
  ✅ timestamp in ISO format
  ✅ flowName correctly populated
```

##### Test: `error-handler-sf-connectivity-response-test`
**Purpose**: Validate Salesforce connectivity error response structure

```
Validates:
  ✅ errorType = "SALESFORCE_CONNECTION_ERROR"
  ✅ message = "Failed to connect to Salesforce..."
  ✅ details includes authentication/network error
  ✅ timestamp and flowName present
```

##### Test: `error-handler-sf-validation-response-test`
**Purpose**: Validate Salesforce validation error response structure

```
Validates:
  ✅ errorType = "SALESFORCE_VALIDATION_ERROR"
  ✅ message = "Invalid data for Salesforce..."
  ✅ details includes field-level validation errors
  ✅ Response helps identify what to fix
```

##### Test: `error-handler-transformation-response-test`
**Purpose**: Validate transformation error response structure

```
Validates:
  ✅ errorType = "TRANSFORMATION_ERROR"
  ✅ message = "Data transformation failed"
  ✅ details includes DataWeave expression error
  ✅ Helps debug transformation issues
```

##### Test: `error-handler-any-response-test`
**Purpose**: Validate generic ANY error handler response structure

```
Validates:
  ✅ errorType = actual error type identifier
  ✅ message = "An unexpected error occurred"
  ✅ details includes raw error information
  ✅ Catch-all for unhandled error types
```

**Why Response Validation Matters**:
```
┌─────────────────────────────────────────────────┐
│  Error Response Consistency = Better UX         │
├─────────────────────────────────────────────────┤
│  ✅ Frontend can parse responses reliably       │
│  ✅ Monitoring systems can categorize errors    │
│  ✅ Debugging is easier with structured data    │
│  ✅ API consumers get actionable information    │
└─────────────────────────────────────────────────┘
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
