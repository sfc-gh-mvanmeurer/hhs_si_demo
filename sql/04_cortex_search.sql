/*
================================================================================
HHS FRAUD DEMO - CORTEX SEARCH SETUP
================================================================================
Worksheet: 04_cortex_search.sql
Purpose: Create Cortex Search service for semantic search over investigation
         case notes and fraud documentation

Cortex Search enables:
- Natural language search over case notes
- Finding similar fraud patterns
- Retrieving investigation history
================================================================================
*/

-- ============================================================================
-- SETUP CONTEXT
-- ============================================================================
USE ROLE HHS_ADMIN;
USE WAREHOUSE HHS_DEMO_WH;
USE DATABASE HHS_SI_DEMO;
USE SCHEMA CORTEX;

-- ============================================================================
-- SECTION 1: PREPARE SEARCH DATA
-- ============================================================================

-- Create a materialized table for search (Cortex Search needs a table, not view)
CREATE OR REPLACE TABLE CASE_NOTES_SEARCH AS
SELECT
    NOTE_ID,
    CASE_ID,
    CLAIM_ID,
    NOTE_DATE,
    INVESTIGATOR,
    NOTE_TYPE,
    NOTE_TEXT,
    FRAUD_PATTERN,
    RISK_TIER,
    CLAIM_TYPE,
    CLAIM_AMOUNT,
    PROVIDER_ID,
    BENEFICIARY_ID,
    BENEFICIARY_STATE,
    DIAGNOSIS_DESCRIPTION,
    REVIEW_STATUS,
    
    -- Combined search text with rich context
    CONCAT(
        'Case ID: ', CASE_ID, '. ',
        'Claim ID: ', CLAIM_ID, '. ',
        'Fraud Pattern: ', REPLACE(FRAUD_PATTERN, '_', ' '), '. ',
        'Risk Level: ', RISK_TIER, '. ',
        'Claim Type: ', COALESCE(CLAIM_TYPE, 'Unknown'), '. ',
        'Provider: ', COALESCE(PROVIDER_ID, 'Unknown'), '. ',
        'State: ', COALESCE(BENEFICIARY_STATE, 'Unknown'), '. ',
        'Diagnosis: ', COALESCE(DIAGNOSIS_DESCRIPTION, 'Not specified'), '. ',
        'Status: ', COALESCE(REVIEW_STATUS, 'Unknown'), '. ',
        'Investigation Note: ', NOTE_TEXT
    ) AS SEARCH_CONTENT,
    
    -- Metadata for filtering
    CURRENT_TIMESTAMP() AS INDEXED_AT

FROM ANALYTICS.CASE_NOTES_ENRICHED;

-- Verify search data
SELECT COUNT(*) AS TOTAL_NOTES FROM CASE_NOTES_SEARCH;
SELECT * FROM CASE_NOTES_SEARCH LIMIT 5;

-- ============================================================================
-- SECTION 2: CREATE CORTEX SEARCH SERVICE
-- ============================================================================

/*
Cortex Search Service Configuration:
- SEARCH_COLUMN: The text column to search against
- COLUMNS: Additional columns to return in results
- TARGET_LAG: How often to refresh the search index
*/

CREATE OR REPLACE CORTEX SEARCH SERVICE FRAUD_CASE_SEARCH
    ON SEARCH_CONTENT
    ATTRIBUTES CASE_ID, CLAIM_ID, FRAUD_PATTERN, RISK_TIER, NOTE_TYPE, 
               PROVIDER_ID, BENEFICIARY_STATE, INVESTIGATOR, REVIEW_STATUS
    WAREHOUSE = HHS_DEMO_WH
    TARGET_LAG = '1 hour'
    AS (
        SELECT 
            NOTE_ID,
            CASE_ID,
            CLAIM_ID,
            NOTE_DATE,
            INVESTIGATOR,
            NOTE_TYPE,
            NOTE_TEXT,
            FRAUD_PATTERN,
            RISK_TIER,
            CLAIM_TYPE,
            CLAIM_AMOUNT,
            PROVIDER_ID,
            BENEFICIARY_ID,
            BENEFICIARY_STATE,
            DIAGNOSIS_DESCRIPTION,
            REVIEW_STATUS,
            SEARCH_CONTENT
        FROM CORTEX.CASE_NOTES_SEARCH
    );

-- ============================================================================
-- SECTION 3: CREATE FRAUD KNOWLEDGE BASE (Additional searchable content)
-- ============================================================================

-- Create table for fraud detection guidelines and policies
CREATE OR REPLACE TABLE FRAUD_KNOWLEDGE_BASE (
    DOC_ID VARCHAR(50),
    DOC_TYPE VARCHAR(50),
    DOC_TITLE VARCHAR(200),
    DOC_CONTENT VARCHAR(10000),
    FRAUD_PATTERN VARCHAR(50),
    CREATED_DATE DATE DEFAULT CURRENT_DATE(),
    SEARCH_TEXT VARCHAR(12000)
);

-- Insert fraud detection guidelines
INSERT INTO FRAUD_KNOWLEDGE_BASE (DOC_ID, DOC_TYPE, DOC_TITLE, DOC_CONTENT, FRAUD_PATTERN, SEARCH_TEXT)
VALUES
('GUIDE-001', 'INVESTIGATION_GUIDE', 'Upcoding Detection Guidelines',
'Upcoding occurs when providers bill for more expensive services than actually rendered. Key indicators include:

1. BILLING PATTERNS
- Consistent use of highest-level E&M codes (99215, 99223, 99233)
- Procedure complexity inconsistent with documented diagnosis
- Higher billing codes than peer providers for similar patients

2. DOCUMENTATION REVIEW
- Request medical records for high-value claims
- Compare documented services to billed codes
- Verify time-based codes match documentation

3. INVESTIGATION STEPS
- Pull 12-month billing history for provider
- Compare to specialty benchmarks
- Interview provider if pattern persists
- Calculate potential overpayment

4. RED FLAGS
- E&M code distribution skewed to higher levels
- Modifier abuse (especially modifier 25)
- Same high-level code for all patient types',
'UPCODING',
'Upcoding Detection Guidelines. Upcoding occurs when providers bill for more expensive services than actually rendered. Key indicators include billing patterns with consistent use of highest-level E&M codes, procedure complexity inconsistent with documented diagnosis. Documentation review steps and red flags for upcoding fraud investigation.'),

('GUIDE-002', 'INVESTIGATION_GUIDE', 'Unbundling Detection Guidelines',
'Unbundling is the practice of billing separately for services that should be billed as a single comprehensive code. 

1. COMMON UNBUNDLING SCENARIOS
- Laboratory panel components billed individually
- Surgical procedures with included services billed separately
- Global surgical packages with separately billed follow-up visits

2. DETECTION METHODS
- Apply CCI (Correct Coding Initiative) edits
- Compare against NCCI bundling rules
- Look for patterns of component code billing

3. INVESTIGATION APPROACH
- Identify claims with multiple related CPT codes same date
- Cross-reference with bundling databases
- Calculate difference between bundled and unbundled pricing

4. PROVIDER EDUCATION
- Many unbundling cases result from coding errors
- Provide education before pursuing fraud determination
- Document repeated violations after education',
'UNBUNDLING',
'Unbundling Detection Guidelines. Unbundling is billing separately for services that should be bundled. Common scenarios include laboratory panels billed individually, surgical procedures with included services. Detection methods using CCI edits and NCCI bundling rules. Investigation approach for unbundling fraud.'),

('GUIDE-003', 'INVESTIGATION_GUIDE', 'Phantom Billing Investigation Protocol',
'Phantom billing is one of the most serious forms of healthcare fraud, involving billing for services never rendered.

1. CRITICAL INDICATORS
- Services billed after beneficiary death date
- Geographic impossibilities (services in multiple distant locations same day)
- Medically impossible service combinations
- Services during documented hospitalizations elsewhere

2. IMMEDIATE ACTIONS
- Flag for SIU (Special Investigations Unit) review
- Preserve all claim documentation
- Cross-reference with other payer data if available

3. EVIDENCE GATHERING
- Beneficiary interviews or family contact
- Medical record requests with specific date verification
- Provider site visits if warranted
- Cross-reference with pharmacy and other claim types

4. LEGAL CONSIDERATIONS
- Phantom billing often rises to criminal fraud level
- Coordinate with OIG and law enforcement as appropriate
- Maintain chain of custody for evidence',
'PHANTOM_BILLING',
'Phantom Billing Investigation Protocol. Phantom billing is billing for services never rendered. Critical indicators include services after death date, geographic impossibilities, medically impossible combinations. Immediate actions for SIU review, evidence gathering procedures, legal considerations for criminal fraud.'),

('GUIDE-004', 'INVESTIGATION_GUIDE', 'Provider Hopping Pattern Analysis',
'Provider hopping or doctor shopping indicates potential prescription fraud or coordinated billing schemes.

1. PATTERN IDENTIFICATION
- Beneficiary visits 5+ providers for similar complaints in 90 days
- Multiple prescriptions for controlled substances
- Overlapping appointments with different specialists

2. ANALYSIS TECHNIQUES
- Map beneficiary travel patterns
- Identify prescription overlaps
- Calculate total controlled substance quantities

3. COORDINATED FRAUD INDICATORS
- Multiple beneficiaries showing same pattern with same providers
- Unusually high percentage of cash-pay patients
- Providers in different networks with same billing patterns

4. INTERVENTION OPTIONS
- Beneficiary lock-in programs
- Provider monitoring and audits
- Law enforcement referral for drug trafficking',
'PROVIDER_HOPPING',
'Provider Hopping Pattern Analysis. Provider hopping indicates potential prescription fraud or coordinated billing schemes. Pattern identification for multiple provider visits, controlled substance prescriptions. Analysis techniques for travel patterns, prescription overlaps. Coordinated fraud indicators and intervention options.'),

('GUIDE-005', 'INVESTIGATION_GUIDE', 'Duplicate Billing Detection',
'Duplicate billing occurs when the same service is billed multiple times.

1. TYPES OF DUPLICATES
- Exact duplicates: Same claim submitted twice
- Near duplicates: Same service, different claim numbers
- Cross-provider duplicates: Same service billed by multiple providers

2. SYSTEM DETECTION
- Exact match on key fields (beneficiary, date, procedure, provider)
- Fuzzy matching for near duplicates
- Cross-provider matching for coordination issues

3. ROOT CAUSE ANALYSIS
- System errors vs intentional duplicate submission
- Billing system configuration issues
- Lack of coordination of benefits

4. RECOVERY ACTIONS
- Automated recoupment for exact duplicates
- Manual review for complex cases
- Provider system audits for repeat offenders',
'DUPLICATE_BILLING',
'Duplicate Billing Detection. Duplicate billing occurs when same service is billed multiple times. Types include exact duplicates, near duplicates, cross-provider duplicates. System detection methods, root cause analysis, and recovery actions for duplicate billing fraud.'),

('GUIDE-006', 'INVESTIGATION_GUIDE', 'Medically Unlikely Services Review',
'Medically unlikely services are those that are improbable given the patient profile or clinical context.

1. MEDICAL NECESSITY INDICATORS
- Age-inappropriate procedures (pediatric services for elderly)
- Gender-specific service mismatches
- Services inconsistent with documented chronic conditions
- Excessive units of service

2. CLINICAL REVIEW PROCESS
- Medical director review for complex cases
- Specialty consultant input as needed
- Evidence-based guideline comparison

3. MUE (Medically Unlikely Edits) APPLICATION
- CMS MUE tables for unit limits
- Specialty-specific service limits
- Anatomically-based restrictions

4. PROVIDER COMMUNICATION
- Request additional documentation
- Medical necessity questionnaires
- Appeals process for legitimate exceptions',
'MEDICALLY_UNLIKELY',
'Medically Unlikely Services Review. Medically unlikely services are improbable given patient profile. Medical necessity indicators include age-inappropriate procedures, gender mismatches, condition inconsistencies. Clinical review process with medical director. MUE application and provider communication.');

-- Update search text column
UPDATE FRAUD_KNOWLEDGE_BASE 
SET SEARCH_TEXT = CONCAT(DOC_TITLE, '. ', DOC_CONTENT);

-- Create search service for knowledge base
CREATE OR REPLACE CORTEX SEARCH SERVICE FRAUD_KNOWLEDGE_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES DOC_ID, DOC_TYPE, DOC_TITLE, FRAUD_PATTERN
    WAREHOUSE = HHS_DEMO_WH
    TARGET_LAG = '1 day'
    AS (
        SELECT 
            DOC_ID,
            DOC_TYPE,
            DOC_TITLE,
            DOC_CONTENT,
            FRAUD_PATTERN,
            CREATED_DATE,
            SEARCH_TEXT
        FROM CORTEX.FRAUD_KNOWLEDGE_BASE
    );

-- ============================================================================
-- SECTION 4: TEST SEARCH QUERIES
-- ============================================================================

-- Test case notes search
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'FRAUD_CASE_SEARCH',
    '{
        "query": "upcoding high risk claims",
        "columns": ["CASE_ID", "CLAIM_ID", "NOTE_TEXT", "RISK_TIER", "FRAUD_PATTERN"],
        "limit": 5
    }'
);

-- Test knowledge base search
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'FRAUD_KNOWLEDGE_SEARCH',
    '{
        "query": "how to investigate phantom billing",
        "columns": ["DOC_TITLE", "DOC_CONTENT", "FRAUD_PATTERN"],
        "limit": 3
    }'
);

-- ============================================================================
-- SECTION 5: GRANT PERMISSIONS
-- ============================================================================

-- Grant search service access to analyst role
GRANT USAGE ON CORTEX SEARCH SERVICE FRAUD_CASE_SEARCH TO ROLE HHS_ANALYST;
GRANT USAGE ON CORTEX SEARCH SERVICE FRAUD_KNOWLEDGE_SEARCH TO ROLE HHS_ANALYST;

-- Grant table access
GRANT SELECT ON TABLE CASE_NOTES_SEARCH TO ROLE HHS_ANALYST;
GRANT SELECT ON TABLE FRAUD_KNOWLEDGE_BASE TO ROLE HHS_ANALYST;

-- ============================================================================
-- SECTION 6: VERIFICATION
-- ============================================================================

-- Show search services
SHOW CORTEX SEARCH SERVICES IN SCHEMA CORTEX;

-- Describe services
DESCRIBE CORTEX SEARCH SERVICE FRAUD_CASE_SEARCH;
DESCRIBE CORTEX SEARCH SERVICE FRAUD_KNOWLEDGE_SEARCH;

SELECT 
    'Cortex Search Setup Complete' AS STATUS,
    (SELECT COUNT(*) FROM CASE_NOTES_SEARCH) AS CASE_NOTES_INDEXED,
    (SELECT COUNT(*) FROM FRAUD_KNOWLEDGE_BASE) AS KNOWLEDGE_DOCS_INDEXED;

/*
================================================================================
NEXT STEPS
================================================================================
1. Verify search services are active
2. Test search queries return relevant results
3. Execute worksheet: 05_snowflake_intelligence.sql
================================================================================
*/
