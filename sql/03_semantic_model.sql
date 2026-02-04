/*
================================================================================
HHS FRAUD DEMO - SEMANTIC VIEWS FOR CORTEX ANALYST
================================================================================
Worksheet: 03_semantic_model.sql
Purpose: Create Semantic Views for Cortex Analyst to enable natural language
         queries against fraud investigation data via Snowflake Intelligence

Reference: https://docs.snowflake.com/en/user-guide/views-semantic/sql
================================================================================
*/

-- ============================================================================
-- SETUP
-- ============================================================================
USE ROLE ACCOUNTADMIN;
USE DATABASE HHS_SI_DEMO;
USE WAREHOUSE HHS_DEMO_WH;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- STEP 1: CREATE BASE VIEWS WITH COMPUTED COLUMNS
-- ============================================================================

-- Base view for fraud investigation
CREATE OR REPLACE VIEW VW_FRAUD_CASES_BASE AS
SELECT
    CASE_ID,
    CLAIM_ID,
    BENEFICIARY_ID,
    FRAUD_PATTERN,
    FRAUD_PATTERN_DISPLAY,
    FRAUD_SCORE,
    RISK_TIER,
    REVIEW_STATUS,
    CLAIM_TYPE,
    FLAG_DATE,
    SERVICE_START_DATE,
    SERVICE_END_DATE,
    CLAIM_AMOUNT,
    PROVIDER_ID,
    PRIMARY_DIAGNOSIS,
    DIAGNOSIS_DESCRIPTION,
    PRIMARY_PROCEDURE,
    FLAG_REASON,
    FRAUD_INDICATORS,
    BENEFICIARY_AGE,
    BENEFICIARY_GENDER,
    BENEFICIARY_STATE,
    BENEFICIARY_DECEASED,
    CHRONIC_CONDITION_COUNT,
    CHRONIC_CONDITIONS,
    DAYS_SINCE_FLAGGED,
    RISK_PRIORITY_SCORE
FROM HHS_SI_DEMO.ANALYTICS.FRAUD_INVESTIGATION;

-- Base view for beneficiaries
CREATE OR REPLACE VIEW VW_BENEFICIARIES_BASE AS
SELECT
    BENEFICIARY_ID,
    BIRTH_DATE,
    AGE,
    GENDER,
    RACE,
    STATE_CODE,
    STATE_NAME,
    COUNTY_CODE,
    IS_DECEASED,
    DEATH_DATE,
    HAS_ESRD,
    PART_A_COVERAGE_MONTHS,
    PART_B_COVERAGE_MONTHS,
    HMO_COVERAGE_MONTHS,
    PART_D_COVERAGE_MONTHS,
    HAS_ALZHEIMERS,
    HAS_CHF,
    HAS_CHRONIC_KIDNEY,
    HAS_CANCER,
    HAS_COPD,
    HAS_DEPRESSION,
    HAS_DIABETES,
    HAS_ISCHEMIC_HEART,
    HAS_OSTEOPOROSIS,
    HAS_ARTHRITIS,
    HAS_STROKE,
    CHRONIC_CONDITION_COUNT,
    INPATIENT_REIMBURSEMENT,
    OUTPATIENT_REIMBURSEMENT,
    CARRIER_REIMBURSEMENT,
    TOTAL_REIMBURSEMENT,
    TOTAL_BENEFICIARY_RESPONSIBILITY
FROM HHS_SI_DEMO.ANALYTICS.BENEFICIARY_ENRICHED;

-- Base view for provider risk
CREATE OR REPLACE VIEW VW_PROVIDERS_BASE AS
SELECT
    PROVIDER_ID,
    FLAGGED_CLAIM_COUNT,
    CASE_COUNT,
    UNIQUE_BENEFICIARIES,
    TOTAL_FLAGGED_AMOUNT,
    AVG_FRAUD_SCORE,
    MAX_FRAUD_SCORE,
    PRIMARY_FRAUD_PATTERN,
    PROVIDER_RISK_CATEGORY,
    ALL_FRAUD_PATTERNS
FROM HHS_SI_DEMO.ANALYTICS.PROVIDER_RISK_PROFILE;

-- Verify base views created
SELECT 'Base views created. Verifying data...' AS status;
SELECT COUNT(*) AS fraud_cases FROM VW_FRAUD_CASES_BASE;
SELECT COUNT(*) AS beneficiaries FROM VW_BENEFICIARIES_BASE;
SELECT COUNT(*) AS providers FROM VW_PROVIDERS_BASE;

-- ============================================================================
-- STEP 2: CREATE SEMANTIC VIEWS
-- ============================================================================

-- Semantic View 1: Fraud Case Analytics
CREATE OR REPLACE SEMANTIC VIEW FRAUD_CASE_ANALYTICS

  TABLES (
    fraud_cases AS HHS_SI_DEMO.ANALYTICS.VW_FRAUD_CASES_BASE
      PRIMARY KEY (CASE_ID)
      COMMENT = 'Fraud cases flagged by ML model for investigation'
  )

  FACTS (
    fraud_cases.claim_dollars AS CLAIM_AMOUNT
      COMMENT = 'Payment amount for the claim in dollars',
    fraud_cases.ml_score AS FRAUD_SCORE
      COMMENT = 'ML model confidence score 0 to 1',
    fraud_cases.patient_age AS BENEFICIARY_AGE
      COMMENT = 'Age of the beneficiary in years',
    fraud_cases.conditions_count AS CHRONIC_CONDITION_COUNT
      COMMENT = 'Number of chronic conditions',
    fraud_cases.days_open AS DAYS_SINCE_FLAGGED
      COMMENT = 'Days since case was flagged'
  )

  DIMENSIONS (
    fraud_cases.case_id AS CASE_ID
      COMMENT = 'Unique fraud investigation case identifier',
    fraud_cases.claim_id AS CLAIM_ID
      COMMENT = 'Unique claim identifier',
    fraud_cases.beneficiary_id AS BENEFICIARY_ID
      COMMENT = 'Patient or beneficiary identifier',
    fraud_cases.fraud_type AS FRAUD_PATTERN
      COMMENT = 'Type of fraud pattern code',
    fraud_cases.fraud_type_display AS FRAUD_PATTERN_DISPLAY
      COMMENT = 'Human readable fraud pattern name',
    fraud_cases.risk_level AS RISK_TIER
      COMMENT = 'Risk classification CRITICAL HIGH MEDIUM or LOW',
    fraud_cases.status AS REVIEW_STATUS
      COMMENT = 'Investigation status',
    fraud_cases.claim_type AS CLAIM_TYPE
      COMMENT = 'Type of claim INPATIENT or OUTPATIENT',
    fraud_cases.flagged_date AS FLAG_DATE
      COMMENT = 'Date when claim was flagged by ML model',
    fraud_cases.service_date AS SERVICE_START_DATE
      COMMENT = 'Date service was provided',
    fraud_cases.provider AS PROVIDER_ID
      COMMENT = 'Healthcare provider identifier',
    fraud_cases.diagnosis_code AS PRIMARY_DIAGNOSIS
      COMMENT = 'ICD9 diagnosis code',
    fraud_cases.diagnosis AS DIAGNOSIS_DESCRIPTION
      COMMENT = 'Description of primary diagnosis',
    fraud_cases.gender AS BENEFICIARY_GENDER
      COMMENT = 'Gender of beneficiary',
    fraud_cases.state AS BENEFICIARY_STATE
      COMMENT = 'State where beneficiary resides',
    fraud_cases.flag_reason AS FLAG_REASON
      COMMENT = 'Explanation of why claim was flagged',
    fraud_cases.chronic_conditions AS CHRONIC_CONDITIONS
      COMMENT = 'List of beneficiary chronic conditions'
  )

  METRICS (
    fraud_cases.total_cases AS COUNT(CASE_ID)
      COMMENT = 'Total number of fraud cases',
    fraud_cases.total_amount_at_risk AS SUM(CLAIM_AMOUNT)
      COMMENT = 'Total dollar amount at risk',
    fraud_cases.average_claim_amount AS AVG(CLAIM_AMOUNT)
      COMMENT = 'Average claim amount',
    fraud_cases.average_fraud_score AS AVG(FRAUD_SCORE)
      COMMENT = 'Average ML fraud score',
    fraud_cases.critical_cases AS COUNT_IF(RISK_TIER = 'CRITICAL')
      COMMENT = 'Number of critical risk cases',
    fraud_cases.high_risk_cases AS COUNT_IF(RISK_TIER = 'HIGH')
      COMMENT = 'Number of high risk cases',
    fraud_cases.pending_review_cases AS COUNT_IF(REVIEW_STATUS = 'PENDING_REVIEW')
      COMMENT = 'Cases pending initial review',
    fraud_cases.unique_providers AS COUNT(DISTINCT PROVIDER_ID)
      COMMENT = 'Number of unique providers with flagged claims',
    fraud_cases.unique_beneficiaries AS COUNT(DISTINCT BENEFICIARY_ID)
      COMMENT = 'Number of unique beneficiaries with flagged claims'
  )

  COMMENT = 'Fraud case analytics for ML-flagged Medicare and Medicaid claims';

-- Grant access
GRANT REFERENCES, SELECT ON SEMANTIC VIEW FRAUD_CASE_ANALYTICS TO ROLE HHS_ADMIN;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW FRAUD_CASE_ANALYTICS TO ROLE HHS_ANALYST;
GRANT SELECT ON VW_FRAUD_CASES_BASE TO ROLE HHS_ADMIN;
GRANT SELECT ON VW_FRAUD_CASES_BASE TO ROLE HHS_ANALYST;


-- Semantic View 2: Beneficiary Analytics
CREATE OR REPLACE SEMANTIC VIEW BENEFICIARY_ANALYTICS

  TABLES (
    beneficiaries AS HHS_SI_DEMO.ANALYTICS.VW_BENEFICIARIES_BASE
      PRIMARY KEY (BENEFICIARY_ID)
      COMMENT = 'Medicare and Medicaid beneficiary demographics and health'
  )

  FACTS (
    beneficiaries.patient_age AS AGE
      COMMENT = 'Beneficiary age in years',
    beneficiaries.conditions AS CHRONIC_CONDITION_COUNT
      COMMENT = 'Number of chronic conditions',
    beneficiaries.inpatient_paid AS INPATIENT_REIMBURSEMENT
      COMMENT = 'Inpatient reimbursement amount',
    beneficiaries.outpatient_paid AS OUTPATIENT_REIMBURSEMENT
      COMMENT = 'Outpatient reimbursement amount',
    beneficiaries.carrier_paid AS CARRIER_REIMBURSEMENT
      COMMENT = 'Carrier reimbursement amount'
  )

  DIMENSIONS (
    beneficiaries.beneficiary_id AS BENEFICIARY_ID
      COMMENT = 'Unique beneficiary identifier',
    beneficiaries.gender AS GENDER
      COMMENT = 'Beneficiary gender Male or Female',
    beneficiaries.race AS RACE
      COMMENT = 'Beneficiary race or ethnicity',
    beneficiaries.state AS STATE_NAME
      COMMENT = 'State of residence',
    beneficiaries.deceased AS IS_DECEASED
      COMMENT = 'Whether beneficiary is deceased',
    beneficiaries.has_esrd AS HAS_ESRD
      COMMENT = 'Has End Stage Renal Disease',
    beneficiaries.has_diabetes AS HAS_DIABETES
      COMMENT = 'Has diabetes diagnosis',
    beneficiaries.has_chf AS HAS_CHF
      COMMENT = 'Has congestive heart failure',
    beneficiaries.has_copd AS HAS_COPD
      COMMENT = 'Has COPD diagnosis',
    beneficiaries.has_cancer AS HAS_CANCER
      COMMENT = 'Has cancer diagnosis',
    beneficiaries.has_alzheimers AS HAS_ALZHEIMERS
      COMMENT = 'Has Alzheimers diagnosis',
    beneficiaries.has_kidney AS HAS_CHRONIC_KIDNEY
      COMMENT = 'Has chronic kidney disease',
    beneficiaries.has_depression AS HAS_DEPRESSION
      COMMENT = 'Has depression diagnosis'
  )

  METRICS (
    beneficiaries.total_beneficiaries AS COUNT(BENEFICIARY_ID)
      COMMENT = 'Total number of beneficiaries',
    beneficiaries.average_age AS AVG(AGE)
      COMMENT = 'Average age of beneficiaries',
    beneficiaries.average_conditions AS AVG(CHRONIC_CONDITION_COUNT)
      COMMENT = 'Average number of chronic conditions',
    beneficiaries.total_inpatient AS SUM(INPATIENT_REIMBURSEMENT)
      COMMENT = 'Total inpatient reimbursement',
    beneficiaries.total_outpatient AS SUM(OUTPATIENT_REIMBURSEMENT)
      COMMENT = 'Total outpatient reimbursement',
    beneficiaries.total_carrier AS SUM(CARRIER_REIMBURSEMENT)
      COMMENT = 'Total carrier reimbursement',
    beneficiaries.deceased_count AS COUNT_IF(IS_DECEASED = TRUE)
      COMMENT = 'Number of deceased beneficiaries',
    beneficiaries.diabetic_count AS COUNT_IF(HAS_DIABETES = TRUE)
      COMMENT = 'Number of beneficiaries with diabetes'
  )

  COMMENT = 'Beneficiary demographics and health analytics for Medicare Medicaid';

GRANT REFERENCES, SELECT ON SEMANTIC VIEW BENEFICIARY_ANALYTICS TO ROLE HHS_ADMIN;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW BENEFICIARY_ANALYTICS TO ROLE HHS_ANALYST;
GRANT SELECT ON VW_BENEFICIARIES_BASE TO ROLE HHS_ADMIN;
GRANT SELECT ON VW_BENEFICIARIES_BASE TO ROLE HHS_ANALYST;


-- Semantic View 3: Provider Risk Analytics
-- Note: This is a pre-aggregated view, so we use DIMENSIONS for the aggregate values
CREATE OR REPLACE SEMANTIC VIEW PROVIDER_RISK_ANALYTICS

  TABLES (
    providers AS HHS_SI_DEMO.ANALYTICS.VW_PROVIDERS_BASE
      PRIMARY KEY (PROVIDER_ID)
      COMMENT = 'Provider level fraud risk aggregations'
  )

  DIMENSIONS (
    providers.provider_id AS PROVIDER_ID
      COMMENT = 'Healthcare provider identifier',
    providers.risk_category AS PROVIDER_RISK_CATEGORY
      COMMENT = 'Risk category Very High Risk High Risk Moderate Risk Lower Risk',
    providers.primary_pattern AS PRIMARY_FRAUD_PATTERN
      COMMENT = 'Most common fraud pattern for this provider',
    providers.all_patterns AS ALL_FRAUD_PATTERNS
      COMMENT = 'All fraud patterns associated with provider',
    providers.flagged_claims AS FLAGGED_CLAIM_COUNT
      COMMENT = 'Number of flagged claims for this provider',
    providers.case_count AS CASE_COUNT
      COMMENT = 'Number of fraud cases',
    providers.patients AS UNIQUE_BENEFICIARIES
      COMMENT = 'Number of unique beneficiaries',
    providers.flagged_amount AS TOTAL_FLAGGED_AMOUNT
      COMMENT = 'Total dollar amount of flagged claims',
    providers.avg_score AS AVG_FRAUD_SCORE
      COMMENT = 'Average fraud score for provider',
    providers.max_score AS MAX_FRAUD_SCORE
      COMMENT = 'Maximum fraud score for provider'
  )

  METRICS (
    providers.total_providers AS COUNT(PROVIDER_ID)
      COMMENT = 'Total number of providers',
    providers.high_risk_providers AS COUNT_IF(PROVIDER_RISK_CATEGORY = 'Very High Risk' OR PROVIDER_RISK_CATEGORY = 'High Risk')
      COMMENT = 'Number of high risk providers',
    providers.very_high_risk_count AS COUNT_IF(PROVIDER_RISK_CATEGORY = 'Very High Risk')
      COMMENT = 'Number of very high risk providers'
  )

  COMMENT = 'Provider fraud risk analytics for investigation prioritization';

GRANT REFERENCES, SELECT ON SEMANTIC VIEW PROVIDER_RISK_ANALYTICS TO ROLE HHS_ADMIN;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW PROVIDER_RISK_ANALYTICS TO ROLE HHS_ANALYST;
GRANT SELECT ON VW_PROVIDERS_BASE TO ROLE HHS_ADMIN;
GRANT SELECT ON VW_PROVIDERS_BASE TO ROLE HHS_ANALYST;


-- ============================================================================
-- STEP 3: VERIFY SEMANTIC VIEWS
-- ============================================================================

-- Show all created views
SHOW VIEWS IN SCHEMA HHS_SI_DEMO.ANALYTICS;

-- Show all created semantic views
SHOW SEMANTIC VIEWS IN SCHEMA HHS_SI_DEMO.ANALYTICS;

-- Describe semantic views
DESCRIBE SEMANTIC VIEW FRAUD_CASE_ANALYTICS;
DESCRIBE SEMANTIC VIEW BENEFICIARY_ANALYTICS;
DESCRIBE SEMANTIC VIEW PROVIDER_RISK_ANALYTICS;

-- ============================================================================
-- STEP 4: TEST BASE VIEWS
-- ============================================================================

SELECT 'Testing fraud case data...' AS test;
SELECT 
    FRAUD_PATTERN_DISPLAY AS fraud_pattern,
    RISK_TIER,
    COUNT(*) AS case_count,
    ROUND(SUM(CLAIM_AMOUNT), 2) AS total_amount,
    ROUND(AVG(FRAUD_SCORE), 3) AS avg_score
FROM VW_FRAUD_CASES_BASE
GROUP BY FRAUD_PATTERN_DISPLAY, RISK_TIER
ORDER BY case_count DESC;

SELECT 'Testing beneficiary data...' AS test;
SELECT 
    STATE_NAME,
    COUNT(*) AS beneficiary_count,
    ROUND(AVG(AGE), 1) AS avg_age,
    ROUND(AVG(CHRONIC_CONDITION_COUNT), 2) AS avg_conditions
FROM VW_BENEFICIARIES_BASE
WHERE STATE_NAME IS NOT NULL
GROUP BY STATE_NAME
ORDER BY beneficiary_count DESC
LIMIT 10;

SELECT 'Testing provider data...' AS test;
SELECT 
    PROVIDER_RISK_CATEGORY,
    COUNT(*) AS provider_count,
    SUM(FLAGGED_CLAIM_COUNT) AS total_flagged_claims,
    ROUND(AVG(AVG_FRAUD_SCORE), 3) AS avg_score
FROM VW_PROVIDERS_BASE
GROUP BY PROVIDER_RISK_CATEGORY
ORDER BY avg_score DESC;

SELECT '✅ Semantic views created successfully!' AS status;

/*
================================================================================
NEXT STEPS
================================================================================
1. Verify semantic views appear in SHOW SEMANTIC VIEWS output
2. Execute worksheet: 04_cortex_search.sql
3. Execute worksheet: 05_snowflake_intelligence.sql
================================================================================
*/
