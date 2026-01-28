# Salesforce - Database Customer Sync

## Overview
This MuleSoft application provides bidirectional synchronization of customer data between a local MySQL database and Salesforce CRM. The sync runs on a daily schedule.

## Features
- **DB to Salesforce Sync**: Fetches customer records from the local database and upserts them as Contacts in Salesforce
- **Salesforce to DB Sync**: Fetches Contact records from Salesforce and upserts them to the local database
- **Error Handling**: Comprehensive error handling for database, Salesforce, and transformation errors
- **MUnit Tests**: Complete test coverage for both sync flows

## Architecture

### Flows
1. **syncFromDatabaseToSalesforce** - Daily scheduled flow that:
   - Queries customers modified in the last 24 hours from the database
   - Transforms data to Salesforce Contact format
   - Upserts to Salesforce using `External_Customer_Id__c` as the external ID

2. **syncFromSalesforceToDatabase** - Daily scheduled flow that:
   - Queries Contacts modified in the last 24 hours from Salesforce
   - Transforms data to database format
   - Upserts to the customers table using `salesforce_id` as the unique key

### Configuration Files
- `global-config.xml` - Contains connector configurations (HTTP, Database, Salesforce)
- `sf-db-customer-sync.xml` - Main sync flows and sub-flows
- `error-handler.xml` - Global error handler definitions
- `config/config-dev.yaml` - Development environment properties

## Prerequisites

### Salesforce Setup
1. Create a custom field `External_Customer_Id__c` on the Contact object (Text, External ID)
2. Obtain Salesforce credentials (username, password, security token)

### Database Setup
Execute the `database-schema.sql` script to create the required `customers` table.

## Configuration
Update the `config-dev.yaml` file with your environment-specific values:
- Database connection parameters
- Salesforce credentials
- Scheduler frequency

## Running the Application
```bash
mvn clean package -DskipTests
mvn mule:run -Denv=dev
```

## Running Tests
```bash
mvn clean test -Denv=test
```

## Data Mapping

### DB to Salesforce
| Database Field | Salesforce Field |
|---------------|------------------|
| customer_id | External_Customer_Id__c |
| first_name | FirstName |
| last_name | LastName |
| email | Email |
| phone | Phone |
| street_address | MailingStreet |
| city | MailingCity |
| state | MailingState |
| postal_code | MailingPostalCode |
| country | MailingCountry |

### Salesforce to DB
| Salesforce Field | Database Field |
|------------------|---------------|
| Id | salesforce_id |
| FirstName | first_name |
| LastName | last_name |
| Email | email |
| Phone | phone |
| Account.Name | company_name |
| MailingStreet | street_address |
| MailingCity | city |
| MailingState | state |
| MailingPostalCode | postal_code |
| MailingCountry | country |

## Error Handling
The application handles the following error types:
- `DB:CONNECTIVITY` - Database connection failures
- `DB:QUERY_EXECUTION` - SQL query errors
- `SALESFORCE:CONNECTIVITY` - Salesforce connection failures
- `SALESFORCE:INVALID_INPUT` - Invalid data format errors
- `TRANSFORMATION` - DataWeave transformation errors
- `ANY` - Catch-all for unexpected errors
