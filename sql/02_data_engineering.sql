/*
================================================================================
HHS FRAUD DEMO - DATA ENGINEERING
================================================================================
Worksheet: 02_data_engineering.sql
Purpose: Transform raw data into analytics-ready views and tables for the
         fraud investigation workflow

Creates:
- Enriched beneficiary view with decoded values
- Unified claims view across claim types
- Fraud investigation dashboard view
- Aggregated metrics for Cortex Analyst
================================================================================
*/

-- ============================================================================
-- SETUP CONTEXT
-- ============================================================================
USE ROLE HHS_ADMIN;
USE WAREHOUSE HHS_DEMO_WH;
USE DATABASE HHS_SI_DEMO;

-- ============================================================================
-- SECTION 1: ENRICHED BENEFICIARY VIEW
-- ============================================================================
USE SCHEMA ANALYTICS;

CREATE OR REPLACE VIEW BENEFICIARY_ENRICHED AS
SELECT
    b.DESYNPUF_ID AS BENEFICIARY_ID,
    
    -- Demographics
    TRY_TO_DATE(b.BENE_BIRTH_DT, 'YYYYMMDD') AS BIRTH_DATE,
    DATEDIFF('year', TRY_TO_DATE(b.BENE_BIRTH_DT, 'YYYYMMDD'), CURRENT_DATE()) AS AGE,
    TRY_TO_DATE(b.BENE_DEATH_DT, 'YYYYMMDD') AS DEATH_DATE,
    CASE WHEN b.BENE_DEATH_DT IS NOT NULL THEN TRUE ELSE FALSE END AS IS_DECEASED,
    
    CASE b.BENE_SEX_IDENT_CD
        WHEN '1' THEN 'Male'
        WHEN '2' THEN 'Female'
        ELSE 'Unknown'
    END AS GENDER,
    
    CASE b.BENE_RACE_CD
        WHEN '1' THEN 'White'
        WHEN '2' THEN 'Black'
        WHEN '3' THEN 'Other'
        WHEN '5' THEN 'Hispanic'
        ELSE 'Unknown'
    END AS RACE,
    
    -- Location
    b.SP_STATE_CODE AS STATE_CODE,
    COALESCE(s.STATE_NAME, 'Unknown') AS STATE_NAME,
    b.BENE_COUNTY_CD AS COUNTY_CODE,
    
    -- Coverage
    CASE WHEN b.BENE_ESRD_IND IN ('Y', '1') THEN TRUE ELSE FALSE END AS HAS_ESRD,
    b.BENE_HI_CVRAGE_TOT_MONS AS PART_A_COVERAGE_MONTHS,
    b.BENE_SMI_CVRAGE_TOT_MONS AS PART_B_COVERAGE_MONTHS,
    b.BENE_HMO_CVRAGE_TOT_MONS AS HMO_COVERAGE_MONTHS,
    b.PLAN_CVRG_MOS_NUM AS PART_D_COVERAGE_MONTHS,
    
    -- Chronic Conditions (1 = Yes, 2 = No)
    CASE WHEN b.SP_ALZHDMTA = 1 THEN TRUE ELSE FALSE END AS HAS_ALZHEIMERS,
    CASE WHEN b.SP_CHF = 1 THEN TRUE ELSE FALSE END AS HAS_CHF,
    CASE WHEN b.SP_CHRNKIDN = 1 THEN TRUE ELSE FALSE END AS HAS_CHRONIC_KIDNEY,
    CASE WHEN b.SP_CNCR = 1 THEN TRUE ELSE FALSE END AS HAS_CANCER,
    CASE WHEN b.SP_COPD = 1 THEN TRUE ELSE FALSE END AS HAS_COPD,
    CASE WHEN b.SP_DEPRESSN = 1 THEN TRUE ELSE FALSE END AS HAS_DEPRESSION,
    CASE WHEN b.SP_DIABETES = 1 THEN TRUE ELSE FALSE END AS HAS_DIABETES,
    CASE WHEN b.SP_ISCHMCHT = 1 THEN TRUE ELSE FALSE END AS HAS_ISCHEMIC_HEART,
    CASE WHEN b.SP_OSTEOPRS = 1 THEN TRUE ELSE FALSE END AS HAS_OSTEOPOROSIS,
    CASE WHEN b.SP_RA_OA = 1 THEN TRUE ELSE FALSE END AS HAS_ARTHRITIS,
    CASE WHEN b.SP_STRKETIA = 1 THEN TRUE ELSE FALSE END AS HAS_STROKE,
    
    -- Chronic Condition Count
    (CASE WHEN b.SP_ALZHDMTA = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_CHF = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_CHRNKIDN = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_CNCR = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_COPD = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_DEPRESSN = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_DIABETES = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_ISCHMCHT = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_OSTEOPRS = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_RA_OA = 1 THEN 1 ELSE 0 END +
     CASE WHEN b.SP_STRKETIA = 1 THEN 1 ELSE 0 END) AS CHRONIC_CONDITION_COUNT,
    
    -- Reimbursement Summary
    COALESCE(b.MEDREIMB_IP, 0) AS INPATIENT_REIMBURSEMENT,
    COALESCE(b.MEDREIMB_OP, 0) AS OUTPATIENT_REIMBURSEMENT,
    COALESCE(b.MEDREIMB_CAR, 0) AS CARRIER_REIMBURSEMENT,
    COALESCE(b.MEDREIMB_IP, 0) + COALESCE(b.MEDREIMB_OP, 0) + COALESCE(b.MEDREIMB_CAR, 0) AS TOTAL_REIMBURSEMENT,
    
    -- Beneficiary Responsibility
    COALESCE(b.BENRES_IP, 0) + COALESCE(b.BENRES_OP, 0) + COALESCE(b.BENRES_CAR, 0) AS TOTAL_BENEFICIARY_RESPONSIBILITY
    
FROM RAW.BENEFICIARY_SUMMARY b
LEFT JOIN REFERENCE.REF_STATE_CODES s ON b.SP_STATE_CODE = s.STATE_CODE;

-- ============================================================================
-- SECTION 2: UNIFIED CLAIMS VIEW
-- ============================================================================

CREATE OR REPLACE VIEW CLAIMS_UNIFIED AS

-- Inpatient Claims
SELECT
    ic.CLM_ID AS CLAIM_ID,
    ic.DESYNPUF_ID AS BENEFICIARY_ID,
    'INPATIENT' AS CLAIM_TYPE,
    TRY_TO_DATE(ic.CLM_FROM_DT, 'YYYYMMDD') AS SERVICE_START_DATE,
    TRY_TO_DATE(ic.CLM_THRU_DT, 'YYYYMMDD') AS SERVICE_END_DATE,
    TRY_TO_DATE(ic.CLM_ADMSN_DT, 'YYYYMMDD') AS ADMISSION_DATE,
    TRY_TO_DATE(ic.NCH_BENE_DSCHRG_DT, 'YYYYMMDD') AS DISCHARGE_DATE,
    ic.CLM_UTLZTN_DAY_CNT AS LENGTH_OF_STAY,
    ic.PRVDR_NUM AS PROVIDER_ID,
    ic.AT_PHYSN_NPI AS ATTENDING_PHYSICIAN_NPI,
    ic.OP_PHYSN_NPI AS OPERATING_PHYSICIAN_NPI,
    ic.CLM_PMT_AMT AS CLAIM_PAYMENT_AMOUNT,
    ic.NCH_PRMRY_PYR_CLM_PD_AMT AS PRIMARY_PAYER_AMOUNT,
    ic.NCH_BENE_IP_DDCTBL_AMT AS DEDUCTIBLE_AMOUNT,
    ic.NCH_BENE_PTA_COINSRNC_LBLTY_AM AS COINSURANCE_AMOUNT,
    ic.CLM_DRG_CD AS DRG_CODE,
    ic.ADMTNG_ICD9_DGNS_CD AS ADMITTING_DIAGNOSIS,
    ic.ICD9_DGNS_CD_1 AS PRIMARY_DIAGNOSIS,
    ic.ICD9_DGNS_CD_2 AS SECONDARY_DIAGNOSIS,
    ic.ICD9_PRCDR_CD_1 AS PRIMARY_PROCEDURE,
    ic.HCPCS_CD_1 AS PRIMARY_HCPCS
FROM RAW.INPATIENT_CLAIMS ic

UNION ALL

-- Outpatient Claims
SELECT
    oc.CLM_ID AS CLAIM_ID,
    oc.DESYNPUF_ID AS BENEFICIARY_ID,
    'OUTPATIENT' AS CLAIM_TYPE,
    TRY_TO_DATE(oc.CLM_FROM_DT, 'YYYYMMDD') AS SERVICE_START_DATE,
    TRY_TO_DATE(oc.CLM_THRU_DT, 'YYYYMMDD') AS SERVICE_END_DATE,
    NULL AS ADMISSION_DATE,
    NULL AS DISCHARGE_DATE,
    DATEDIFF('day', TRY_TO_DATE(oc.CLM_FROM_DT, 'YYYYMMDD'), TRY_TO_DATE(oc.CLM_THRU_DT, 'YYYYMMDD')) + 1 AS LENGTH_OF_STAY,
    oc.PRVDR_NUM AS PROVIDER_ID,
    oc.AT_PHYSN_NPI AS ATTENDING_PHYSICIAN_NPI,
    oc.OP_PHYSN_NPI AS OPERATING_PHYSICIAN_NPI,
    oc.CLM_PMT_AMT AS CLAIM_PAYMENT_AMOUNT,
    oc.NCH_PRMRY_PYR_CLM_PD_AMT AS PRIMARY_PAYER_AMOUNT,
    oc.NCH_BENE_PTB_DDCTBL_AMT AS DEDUCTIBLE_AMOUNT,
    oc.NCH_BENE_PTB_COINSRNC_AMT AS COINSURANCE_AMOUNT,
    NULL AS DRG_CODE,
    oc.ADMTNG_ICD9_DGNS_CD AS ADMITTING_DIAGNOSIS,
    oc.ICD9_DGNS_CD_1 AS PRIMARY_DIAGNOSIS,
    oc.ICD9_DGNS_CD_2 AS SECONDARY_DIAGNOSIS,
    oc.ICD9_PRCDR_CD_1 AS PRIMARY_PROCEDURE,
    oc.HCPCS_CD_1 AS PRIMARY_HCPCS
FROM RAW.OUTPATIENT_CLAIMS oc;

-- ============================================================================
-- SECTION 3: FRAUD INVESTIGATION VIEW (Primary view for SI)
-- ============================================================================

CREATE OR REPLACE VIEW FRAUD_INVESTIGATION AS
SELECT
    -- Case Information
    fc.CASE_ID,
    fc.CLM_ID AS CLAIM_ID,
    fc.FRAUD_PATTERN,
    REPLACE(fc.FRAUD_PATTERN, '_', ' ') AS FRAUD_PATTERN_DISPLAY,
    fc.FRAUD_SCORE,
    fc.RISK_TIER,
    fc.FLAG_DATE,
    fc.FLAG_REASON,
    fc.REVIEW_STATUS,
    fc.INDICATORS AS FRAUD_INDICATORS,
    
    -- Claim Details
    fc.CLAIM_TYPE,
    TRY_TO_DATE(fc.CLM_FROM_DT, 'YYYYMMDD') AS SERVICE_START_DATE,
    TRY_TO_DATE(fc.CLM_THRU_DT, 'YYYYMMDD') AS SERVICE_END_DATE,
    fc.CLM_PMT_AMT AS CLAIM_AMOUNT,
    fc.PRVDR_NUM AS PROVIDER_ID,
    fc.PRIMARY_DIAGNOSIS,
    COALESCE(icd.DESCRIPTION, 'Unknown diagnosis') AS DIAGNOSIS_DESCRIPTION,
    fc.PRIMARY_PROCEDURE,
    
    -- Beneficiary Information
    fc.DESYNPUF_ID AS BENEFICIARY_ID,
    be.AGE AS BENEFICIARY_AGE,
    be.GENDER AS BENEFICIARY_GENDER,
    be.STATE_NAME AS BENEFICIARY_STATE,
    be.IS_DECEASED AS BENEFICIARY_DECEASED,
    be.DEATH_DATE AS BENEFICIARY_DEATH_DATE,
    be.CHRONIC_CONDITION_COUNT,
    be.TOTAL_REIMBURSEMENT AS BENEFICIARY_TOTAL_REIMBURSEMENT,
    
    -- Chronic Conditions as comma-separated list
    CONCAT_WS(', ',
        CASE WHEN be.HAS_DIABETES THEN 'Diabetes' END,
        CASE WHEN be.HAS_CHF THEN 'Heart Failure' END,
        CASE WHEN be.HAS_CHRONIC_KIDNEY THEN 'Chronic Kidney Disease' END,
        CASE WHEN be.HAS_COPD THEN 'COPD' END,
        CASE WHEN be.HAS_CANCER THEN 'Cancer' END,
        CASE WHEN be.HAS_ALZHEIMERS THEN 'Alzheimer''s' END,
        CASE WHEN be.HAS_DEPRESSION THEN 'Depression' END,
        CASE WHEN be.HAS_ISCHEMIC_HEART THEN 'Ischemic Heart Disease' END,
        CASE WHEN be.HAS_STROKE THEN 'Stroke/TIA' END,
        CASE WHEN be.HAS_ARTHRITIS THEN 'Arthritis' END,
        CASE WHEN be.HAS_OSTEOPOROSIS THEN 'Osteoporosis' END
    ) AS CHRONIC_CONDITIONS,
    
    -- Risk Assessment
    CASE 
        WHEN fc.RISK_TIER = 'CRITICAL' THEN 4
        WHEN fc.RISK_TIER = 'HIGH' THEN 3
        WHEN fc.RISK_TIER = 'MEDIUM' THEN 2
        ELSE 1
    END AS RISK_PRIORITY_SCORE,
    
    -- Days since flagged
    DATEDIFF('day', fc.FLAG_DATE, CURRENT_DATE()) AS DAYS_SINCE_FLAGGED

FROM RAW.FLAGGED_CLAIMS fc
LEFT JOIN ANALYTICS.BENEFICIARY_ENRICHED be ON fc.DESYNPUF_ID = be.BENEFICIARY_ID
LEFT JOIN REFERENCE.REF_ICD9_CODES icd ON fc.PRIMARY_DIAGNOSIS = icd.ICD9_CODE;

-- ============================================================================
-- SECTION 4: AGGREGATE METRICS TABLE (for Cortex Analyst)
-- ============================================================================

CREATE OR REPLACE TABLE FRAUD_METRICS_SUMMARY AS
SELECT
    -- Dimensions
    fc.FRAUD_PATTERN,
    fc.RISK_TIER,
    fc.CLAIM_TYPE,
    fc.REVIEW_STATUS,
    DATE_TRUNC('month', fc.FLAG_DATE) AS FLAG_MONTH,
    
    -- Metrics
    COUNT(*) AS CASE_COUNT,
    SUM(fc.CLM_PMT_AMT) AS TOTAL_CLAIM_AMOUNT,
    AVG(fc.CLM_PMT_AMT) AS AVG_CLAIM_AMOUNT,
    AVG(fc.FRAUD_SCORE) AS AVG_FRAUD_SCORE,
    COUNT(DISTINCT fc.DESYNPUF_ID) AS UNIQUE_BENEFICIARIES,
    COUNT(DISTINCT fc.PRVDR_NUM) AS UNIQUE_PROVIDERS
    
FROM RAW.FLAGGED_CLAIMS fc
GROUP BY 1, 2, 3, 4, 5;

-- ============================================================================
-- SECTION 5: PROVIDER RISK PROFILE
-- ============================================================================

CREATE OR REPLACE VIEW PROVIDER_RISK_PROFILE AS
SELECT
    fc.PRVDR_NUM AS PROVIDER_ID,
    COUNT(*) AS FLAGGED_CLAIM_COUNT,
    COUNT(DISTINCT fc.CASE_ID) AS CASE_COUNT,
    COUNT(DISTINCT fc.DESYNPUF_ID) AS UNIQUE_BENEFICIARIES,
    SUM(fc.CLM_PMT_AMT) AS TOTAL_FLAGGED_AMOUNT,
    AVG(fc.FRAUD_SCORE) AS AVG_FRAUD_SCORE,
    MAX(fc.FRAUD_SCORE) AS MAX_FRAUD_SCORE,
    
    -- Most common fraud pattern for this provider
    MODE(fc.FRAUD_PATTERN) AS PRIMARY_FRAUD_PATTERN,
    
    -- Risk categorization
    CASE 
        WHEN AVG(fc.FRAUD_SCORE) >= 0.85 THEN 'Very High Risk'
        WHEN AVG(fc.FRAUD_SCORE) >= 0.70 THEN 'High Risk'
        WHEN AVG(fc.FRAUD_SCORE) >= 0.55 THEN 'Moderate Risk'
        ELSE 'Lower Risk'
    END AS PROVIDER_RISK_CATEGORY,
    
    LISTAGG(DISTINCT fc.FRAUD_PATTERN, ', ') WITHIN GROUP (ORDER BY fc.FRAUD_PATTERN) AS ALL_FRAUD_PATTERNS

FROM RAW.FLAGGED_CLAIMS fc
WHERE fc.PRVDR_NUM IS NOT NULL
GROUP BY fc.PRVDR_NUM
ORDER BY AVG_FRAUD_SCORE DESC;

-- ============================================================================
-- SECTION 6: BENEFICIARY CLAIMS HISTORY (for context in investigations)
-- ============================================================================

CREATE OR REPLACE VIEW BENEFICIARY_CLAIMS_HISTORY AS
SELECT
    cu.BENEFICIARY_ID,
    cu.CLAIM_ID,
    cu.CLAIM_TYPE,
    cu.SERVICE_START_DATE,
    cu.SERVICE_END_DATE,
    cu.CLAIM_PAYMENT_AMOUNT,
    cu.PROVIDER_ID,
    cu.PRIMARY_DIAGNOSIS,
    COALESCE(icd.DESCRIPTION, 'Unknown') AS DIAGNOSIS_DESCRIPTION,
    cu.PRIMARY_PROCEDURE,
    
    -- Flag if this claim is in the fraud investigation list
    CASE WHEN fc.CLM_ID IS NOT NULL THEN TRUE ELSE FALSE END AS IS_FLAGGED,
    fc.FRAUD_PATTERN AS FLAGGED_PATTERN,
    fc.FRAUD_SCORE AS FLAGGED_SCORE
    
FROM ANALYTICS.CLAIMS_UNIFIED cu
LEFT JOIN RAW.FLAGGED_CLAIMS fc ON cu.CLAIM_ID = fc.CLM_ID
LEFT JOIN REFERENCE.REF_ICD9_CODES icd ON cu.PRIMARY_DIAGNOSIS = icd.ICD9_CODE
ORDER BY cu.BENEFICIARY_ID, cu.SERVICE_START_DATE;

-- ============================================================================
-- SECTION 7: CASE NOTES ENRICHED (for Cortex Search)
-- ============================================================================

CREATE OR REPLACE VIEW CASE_NOTES_ENRICHED AS
SELECT
    cn.NOTE_ID,
    cn.CASE_ID,
    cn.CLM_ID AS CLAIM_ID,
    cn.NOTE_DATE,
    cn.INVESTIGATOR,
    cn.NOTE_TYPE,
    cn.NOTE_TEXT,
    cn.FRAUD_PATTERN,
    cn.RISK_TIER,
    
    -- Additional context for search
    fi.CLAIM_TYPE,
    fi.CLAIM_AMOUNT,
    fi.PROVIDER_ID,
    fi.BENEFICIARY_ID,
    fi.BENEFICIARY_STATE,
    fi.DIAGNOSIS_DESCRIPTION,
    fi.REVIEW_STATUS,
    
    -- Combine text for better search
    CONCAT(
        'Case: ', cn.CASE_ID, '. ',
        'Fraud Pattern: ', REPLACE(cn.FRAUD_PATTERN, '_', ' '), '. ',
        'Risk: ', cn.RISK_TIER, '. ',
        cn.NOTE_TEXT
    ) AS SEARCH_TEXT

FROM RAW.CASE_NOTES cn
LEFT JOIN ANALYTICS.FRAUD_INVESTIGATION fi ON cn.CASE_ID = fi.CASE_ID;

-- ============================================================================
-- SECTION 8: VERIFICATION QUERIES
-- ============================================================================

-- Check fraud investigation view
SELECT 
    FRAUD_PATTERN,
    RISK_TIER,
    COUNT(*) AS CASE_COUNT,
    ROUND(AVG(CLAIM_AMOUNT), 2) AS AVG_CLAIM_AMOUNT,
    ROUND(AVG(FRAUD_SCORE), 3) AS AVG_SCORE
FROM ANALYTICS.FRAUD_INVESTIGATION
GROUP BY 1, 2
ORDER BY 1, 2;

-- Check beneficiary enrichment
SELECT 
    STATE_NAME,
    COUNT(*) AS BENEFICIARY_COUNT,
    ROUND(AVG(AGE), 1) AS AVG_AGE,
    ROUND(AVG(CHRONIC_CONDITION_COUNT), 2) AS AVG_CONDITIONS
FROM ANALYTICS.BENEFICIARY_ENRICHED
WHERE STATE_NAME IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

-- Summary stats
SELECT
    (SELECT COUNT(*) FROM ANALYTICS.FRAUD_INVESTIGATION) AS FRAUD_CASES,
    (SELECT COUNT(*) FROM ANALYTICS.CLAIMS_UNIFIED) AS TOTAL_CLAIMS,
    (SELECT COUNT(*) FROM ANALYTICS.BENEFICIARY_ENRICHED) AS BENEFICIARIES,
    (SELECT COUNT(*) FROM ANALYTICS.CASE_NOTES_ENRICHED) AS CASE_NOTES;

/*
================================================================================
NEXT STEPS
================================================================================
1. Verify view outputs look correct
2. Execute worksheet: 03_semantic_model.sql
================================================================================
*/
