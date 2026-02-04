/*
================================================================================
HHS FRAUD DEMO - ENVIRONMENT SETUP
================================================================================
Worksheet: 00_setup_environment.sql
Purpose: Create database, schemas, warehouse, and roles for the HHS Fraud Demo

Execute this worksheet FIRST before any other worksheets.
Requires: SYSADMIN and SECURITYADMIN roles (or ACCOUNTADMIN)
================================================================================
*/

-- ============================================================================
-- SECTION 1: ROLE SETUP
-- ============================================================================
USE ROLE SECURITYADMIN;

-- Create demo roles
CREATE ROLE IF NOT EXISTS HHS_ADMIN
    COMMENT = 'Administrator role for HHS Fraud Demo - full access';

CREATE ROLE IF NOT EXISTS HHS_ANALYST
    COMMENT = 'Analyst role for HHS Fraud Demo - read access for investigation';

-- Grant role hierarchy (both roll up to SYSADMIN)
GRANT ROLE HHS_ADMIN TO ROLE SYSADMIN;
GRANT ROLE HHS_ANALYST TO ROLE SYSADMIN;

-- Analysts inherit from Admin for demo simplicity (adjust for production)
GRANT ROLE HHS_ANALYST TO ROLE HHS_ADMIN;

-- Grant roles to current user (adjust username as needed)
GRANT ROLE HHS_ADMIN TO USER IDENTIFIER($CURRENT_USER);
GRANT ROLE HHS_ANALYST TO USER IDENTIFIER($CURRENT_USER);

-- ============================================================================
-- SECTION 2: WAREHOUSE SETUP
-- ============================================================================
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS HHS_DEMO_WH
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for HHS Fraud Demo workloads';

-- Grant warehouse usage to roles
GRANT USAGE ON WAREHOUSE HHS_DEMO_WH TO ROLE HHS_ADMIN;
GRANT USAGE ON WAREHOUSE HHS_DEMO_WH TO ROLE HHS_ANALYST;
GRANT OPERATE ON WAREHOUSE HHS_DEMO_WH TO ROLE HHS_ADMIN;

-- ============================================================================
-- SECTION 3: DATABASE SETUP
-- ============================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE HHS_DEMO_WH;

CREATE DATABASE IF NOT EXISTS HHS_SI_DEMO
    COMMENT = 'HHS Fraud Detection Demo with Snowflake Intelligence';

-- Grant database access to roles
GRANT USAGE ON DATABASE HHS_SI_DEMO TO ROLE HHS_ADMIN;
GRANT USAGE ON DATABASE HHS_SI_DEMO TO ROLE HHS_ANALYST;

GRANT CREATE SCHEMA ON DATABASE HHS_SI_DEMO TO ROLE HHS_ADMIN;

-- ============================================================================
-- SECTION 4: SCHEMA SETUP
-- ============================================================================
USE DATABASE HHS_SI_DEMO;

-- RAW schema: Staged data loaded directly from CSV files
CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Raw data loaded from CMS DE-SynPUF files and generated fraud data';

-- ANALYTICS schema: Transformed and enriched data for analysis
CREATE SCHEMA IF NOT EXISTS ANALYTICS
    COMMENT = 'Transformed data optimized for fraud investigation analysis';

-- CORTEX schema: Cortex services (Analyst semantic models, Search)
CREATE SCHEMA IF NOT EXISTS CORTEX
    COMMENT = 'Cortex Analyst and Cortex Search configurations';

-- REFERENCE schema: Lookup and reference tables
CREATE SCHEMA IF NOT EXISTS REFERENCE
    COMMENT = 'Reference tables (ICD codes, state codes, fraud patterns)';

-- Grant schema access to HHS_ADMIN
GRANT ALL ON SCHEMA RAW TO ROLE HHS_ADMIN;
GRANT ALL ON SCHEMA ANALYTICS TO ROLE HHS_ADMIN;
GRANT ALL ON SCHEMA CORTEX TO ROLE HHS_ADMIN;
GRANT ALL ON SCHEMA REFERENCE TO ROLE HHS_ADMIN;

-- Grant schema access to HHS_ANALYST (read-only on data schemas)
GRANT USAGE ON SCHEMA RAW TO ROLE HHS_ANALYST;
GRANT USAGE ON SCHEMA ANALYTICS TO ROLE HHS_ANALYST;
GRANT USAGE ON SCHEMA CORTEX TO ROLE HHS_ANALYST;
GRANT USAGE ON SCHEMA REFERENCE TO ROLE HHS_ANALYST;

-- Future grants for tables/views created in each schema
GRANT SELECT ON ALL TABLES IN SCHEMA RAW TO ROLE HHS_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA ANALYTICS TO ROLE HHS_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA REFERENCE TO ROLE HHS_ANALYST;

GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW TO ROLE HHS_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ANALYTICS TO ROLE HHS_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA REFERENCE TO ROLE HHS_ANALYST;

GRANT SELECT ON ALL VIEWS IN SCHEMA ANALYTICS TO ROLE HHS_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA ANALYTICS TO ROLE HHS_ANALYST;

-- ============================================================================
-- SECTION 5: VERIFICATION
-- ============================================================================

-- Switch to admin role to verify setup
USE ROLE HHS_ADMIN;
USE WAREHOUSE HHS_DEMO_WH;
USE DATABASE HHS_SI_DEMO;

-- Display created objects
SHOW SCHEMAS IN DATABASE HHS_SI_DEMO;

SELECT 
    'Environment setup complete!' AS STATUS,
    CURRENT_DATABASE() AS DATABASE_NAME,
    CURRENT_WAREHOUSE() AS WAREHOUSE_NAME,
    CURRENT_ROLE() AS CURRENT_ROLE;

/*
================================================================================
NEXT STEPS
================================================================================
1. Run the Python script to generate fraud simulation data:
   python scripts/prepare_fraud_data.py

2. Upload all CSV files to your local machine or cloud storage

3. Execute worksheet: 01_create_stage_load_data.sql
================================================================================
*/
