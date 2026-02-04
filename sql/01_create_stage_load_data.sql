/*
================================================================================
HHS FRAUD DEMO - STAGE AND DATA LOADING
================================================================================
Worksheet: 01_create_stage_load_data.sql
Purpose: Create internal stage, define tables, and load data from CSV files

Prerequisites:
- Execute 00_setup_environment.sql first
- Run prepare_fraud_data.py to generate fraud simulation data
- Run sample_large_files.py to create sampled versions of large files
- Have all CSV files ready for upload (each file must be <250MB)

Data Files Expected (organized by source folder):
  data/
    ├── DE1_0_2008_Beneficiary_Summary*.csv (14MB) ✓
    ├── DE1_0_2009_Beneficiary_Summary*.csv (14MB) ✓
    ├── DE1_0_2010_Beneficiary_Summary*.csv (13MB) ✓
    ├── DE1_0_2008_to_2010_Inpatient_Claims*.csv (16MB) ✓
    └── DE1_0_2008_to_2010_Outpatient_Claims*.csv (154MB) ✓
  data/sampled/
    ├── Carrier_Claims_Sample_1A_sampled.csv (~177MB) ✓
    ├── Carrier_Claims_Sample_1B_sampled.csv (~177MB) ✓
    └── Prescription_Drug_Events_sampled.csv (~180MB) ✓
  data/prepared/
    ├── flagged_claims.csv
    ├── case_notes.csv
    └── ref_*.csv
================================================================================
*/

-- ============================================================================
-- SETUP CONTEXT
-- ============================================================================
USE ROLE HHS_ADMIN;
USE WAREHOUSE HHS_DEMO_WH;
USE DATABASE HHS_SI_DEMO;
USE SCHEMA RAW;

-- ============================================================================
-- SECTION 1: CREATE INTERNAL STAGE
-- ============================================================================

CREATE OR REPLACE STAGE HHS_DATA_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Internal stage for HHS Fraud Demo CSV files';

-- Create file format for CSV files
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    NULL_IF = ('', 'NULL', 'null');

/*
================================================================================
MANUAL STEP: UPLOAD FILES TO STAGE (Max 250MB per file)
================================================================================
Upload files in 3 batches to stay under 250MB limit:

BATCH 1: Small CMS files → @HHS_DATA_STAGE/cms/
  - DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv
  - DE1_0_2009_Beneficiary_Summary_File_Sample_1.csv
  - DE1_0_2010_Beneficiary_Summary_File_Sample_1.csv
  - DE1_0_2008_to_2010_Inpatient_Claims_Sample_1.csv
  - DE1_0_2008_to_2010_Outpatient_Claims_Sample_1.csv

BATCH 2: Sampled large files → @HHS_DATA_STAGE/cms/
  - Carrier_Claims_Sample_1A_sampled.csv (from data/sampled/)
  - Carrier_Claims_Sample_1B_sampled.csv (from data/sampled/)
  - Prescription_Drug_Events_sampled.csv (from data/sampled/)

BATCH 3: Fraud simulation files → @HHS_DATA_STAGE/prepared/
  - flagged_claims.csv
  - case_notes.csv
  - ref_icd9_codes.csv
  - ref_fraud_patterns.csv
  - ref_state_codes.csv

Using Snowsight UI:
1. Navigate to: Data > Databases > HHS_SI_DEMO > RAW > Stages > HHS_DATA_STAGE
2. Create folder "cms", upload Batch 1 + 2 files
3. Create folder "prepared", upload Batch 3 files

After upload, verify with:
LIST @HHS_DATA_STAGE;
================================================================================
*/

-- ============================================================================
-- SECTION 2: CREATE RAW TABLES
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 2.1 BENEFICIARY SUMMARY TABLES
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE BENEFICIARY_SUMMARY (
    DESYNPUF_ID VARCHAR(16) NOT NULL,
    BENE_BIRTH_DT VARCHAR(8),
    BENE_DEATH_DT VARCHAR(8),
    BENE_SEX_IDENT_CD VARCHAR(1),
    BENE_RACE_CD VARCHAR(1),
    BENE_ESRD_IND VARCHAR(1),
    SP_STATE_CODE VARCHAR(2),
    BENE_COUNTY_CD VARCHAR(3),
    BENE_HI_CVRAGE_TOT_MONS NUMBER(2),
    BENE_SMI_CVRAGE_TOT_MONS NUMBER(2),
    BENE_HMO_CVRAGE_TOT_MONS NUMBER(2),
    PLAN_CVRG_MOS_NUM NUMBER(2),
    SP_ALZHDMTA NUMBER(1),
    SP_CHF NUMBER(1),
    SP_CHRNKIDN NUMBER(1),
    SP_CNCR NUMBER(1),
    SP_COPD NUMBER(1),
    SP_DEPRESSN NUMBER(1),
    SP_DIABETES NUMBER(1),
    SP_ISCHMCHT NUMBER(1),
    SP_OSTEOPRS NUMBER(1),
    SP_RA_OA NUMBER(1),
    SP_STRKETIA NUMBER(1),
    MEDREIMB_IP NUMBER(12,2),
    BENRES_IP NUMBER(12,2),
    PPPYMT_IP NUMBER(12,2),
    MEDREIMB_OP NUMBER(12,2),
    BENRES_OP NUMBER(12,2),
    PPPYMT_OP NUMBER(12,2),
    MEDREIMB_CAR NUMBER(12,2),
    BENRES_CAR NUMBER(12,2),
    PPPYMT_CAR NUMBER(12,2),
    BENE_YEAR VARCHAR(4),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CMS DE-SynPUF Beneficiary Summary data';

-- ---------------------------------------------------------------------------
-- 2.2 INPATIENT CLAIMS TABLE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE INPATIENT_CLAIMS (
    DESYNPUF_ID VARCHAR(16) NOT NULL,
    CLM_ID VARCHAR(20) NOT NULL,
    SEGMENT NUMBER(1),
    CLM_FROM_DT VARCHAR(8),
    CLM_THRU_DT VARCHAR(8),
    PRVDR_NUM VARCHAR(10),
    CLM_PMT_AMT NUMBER(12,2),
    NCH_PRMRY_PYR_CLM_PD_AMT NUMBER(12,2),
    AT_PHYSN_NPI VARCHAR(10),
    OP_PHYSN_NPI VARCHAR(10),
    OT_PHYSN_NPI VARCHAR(10),
    CLM_ADMSN_DT VARCHAR(8),
    ADMTNG_ICD9_DGNS_CD VARCHAR(10),
    CLM_PASS_THRU_PER_DIEM_AMT NUMBER(12,2),
    NCH_BENE_IP_DDCTBL_AMT NUMBER(12,2),
    NCH_BENE_PTA_COINSRNC_LBLTY_AM NUMBER(12,2),
    NCH_BENE_BLOOD_DDCTBL_LBLTY_AM NUMBER(12,2),
    CLM_UTLZTN_DAY_CNT NUMBER(5),
    NCH_BENE_DSCHRG_DT VARCHAR(8),
    CLM_DRG_CD VARCHAR(5),
    ICD9_DGNS_CD_1 VARCHAR(10),
    ICD9_DGNS_CD_2 VARCHAR(10),
    ICD9_DGNS_CD_3 VARCHAR(10),
    ICD9_DGNS_CD_4 VARCHAR(10),
    ICD9_DGNS_CD_5 VARCHAR(10),
    ICD9_DGNS_CD_6 VARCHAR(10),
    ICD9_DGNS_CD_7 VARCHAR(10),
    ICD9_DGNS_CD_8 VARCHAR(10),
    ICD9_DGNS_CD_9 VARCHAR(10),
    ICD9_DGNS_CD_10 VARCHAR(10),
    ICD9_PRCDR_CD_1 VARCHAR(10),
    ICD9_PRCDR_CD_2 VARCHAR(10),
    ICD9_PRCDR_CD_3 VARCHAR(10),
    ICD9_PRCDR_CD_4 VARCHAR(10),
    ICD9_PRCDR_CD_5 VARCHAR(10),
    ICD9_PRCDR_CD_6 VARCHAR(10),
    HCPCS_CD_1 VARCHAR(10),
    HCPCS_CD_2 VARCHAR(10),
    HCPCS_CD_3 VARCHAR(10),
    HCPCS_CD_4 VARCHAR(10),
    HCPCS_CD_5 VARCHAR(10),
    HCPCS_CD_6 VARCHAR(10),
    HCPCS_CD_7 VARCHAR(10),
    HCPCS_CD_8 VARCHAR(10),
    HCPCS_CD_9 VARCHAR(10),
    HCPCS_CD_10 VARCHAR(10),
    HCPCS_CD_11 VARCHAR(10),
    HCPCS_CD_12 VARCHAR(10),
    HCPCS_CD_13 VARCHAR(10),
    HCPCS_CD_14 VARCHAR(10),
    HCPCS_CD_15 VARCHAR(10),
    HCPCS_CD_16 VARCHAR(10),
    HCPCS_CD_17 VARCHAR(10),
    HCPCS_CD_18 VARCHAR(10),
    HCPCS_CD_19 VARCHAR(10),
    HCPCS_CD_20 VARCHAR(10),
    HCPCS_CD_21 VARCHAR(10),
    HCPCS_CD_22 VARCHAR(10),
    HCPCS_CD_23 VARCHAR(10),
    HCPCS_CD_24 VARCHAR(10),
    HCPCS_CD_25 VARCHAR(10),
    HCPCS_CD_26 VARCHAR(10),
    HCPCS_CD_27 VARCHAR(10),
    HCPCS_CD_28 VARCHAR(10),
    HCPCS_CD_29 VARCHAR(10),
    HCPCS_CD_30 VARCHAR(10),
    HCPCS_CD_31 VARCHAR(10),
    HCPCS_CD_32 VARCHAR(10),
    HCPCS_CD_33 VARCHAR(10),
    HCPCS_CD_34 VARCHAR(10),
    HCPCS_CD_35 VARCHAR(10),
    HCPCS_CD_36 VARCHAR(10),
    HCPCS_CD_37 VARCHAR(10),
    HCPCS_CD_38 VARCHAR(10),
    HCPCS_CD_39 VARCHAR(10),
    HCPCS_CD_40 VARCHAR(10),
    HCPCS_CD_41 VARCHAR(10),
    HCPCS_CD_42 VARCHAR(10),
    HCPCS_CD_43 VARCHAR(10),
    HCPCS_CD_44 VARCHAR(10),
    HCPCS_CD_45 VARCHAR(10),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CMS DE-SynPUF Inpatient Claims data';

-- ---------------------------------------------------------------------------
-- 2.3 OUTPATIENT CLAIMS TABLE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE OUTPATIENT_CLAIMS (
    DESYNPUF_ID VARCHAR(16) NOT NULL,
    CLM_ID VARCHAR(20) NOT NULL,
    SEGMENT NUMBER(1),
    CLM_FROM_DT VARCHAR(8),
    CLM_THRU_DT VARCHAR(8),
    PRVDR_NUM VARCHAR(10),
    CLM_PMT_AMT NUMBER(12,2),
    NCH_PRMRY_PYR_CLM_PD_AMT NUMBER(12,2),
    AT_PHYSN_NPI VARCHAR(10),
    OP_PHYSN_NPI VARCHAR(10),
    OT_PHYSN_NPI VARCHAR(10),
    NCH_BENE_BLOOD_DDCTBL_LBLTY_AM NUMBER(12,2),
    ICD9_DGNS_CD_1 VARCHAR(10),
    ICD9_DGNS_CD_2 VARCHAR(10),
    ICD9_DGNS_CD_3 VARCHAR(10),
    ICD9_DGNS_CD_4 VARCHAR(10),
    ICD9_DGNS_CD_5 VARCHAR(10),
    ICD9_DGNS_CD_6 VARCHAR(10),
    ICD9_DGNS_CD_7 VARCHAR(10),
    ICD9_DGNS_CD_8 VARCHAR(10),
    ICD9_DGNS_CD_9 VARCHAR(10),
    ICD9_DGNS_CD_10 VARCHAR(10),
    ICD9_PRCDR_CD_1 VARCHAR(10),
    ICD9_PRCDR_CD_2 VARCHAR(10),
    ICD9_PRCDR_CD_3 VARCHAR(10),
    ICD9_PRCDR_CD_4 VARCHAR(10),
    ICD9_PRCDR_CD_5 VARCHAR(10),
    ICD9_PRCDR_CD_6 VARCHAR(10),
    NCH_BENE_PTB_DDCTBL_AMT NUMBER(12,2),
    NCH_BENE_PTB_COINSRNC_AMT NUMBER(12,2),
    ADMTNG_ICD9_DGNS_CD VARCHAR(10),
    HCPCS_CD_1 VARCHAR(10),
    HCPCS_CD_2 VARCHAR(10),
    HCPCS_CD_3 VARCHAR(10),
    HCPCS_CD_4 VARCHAR(10),
    HCPCS_CD_5 VARCHAR(10),
    HCPCS_CD_6 VARCHAR(10),
    HCPCS_CD_7 VARCHAR(10),
    HCPCS_CD_8 VARCHAR(10),
    HCPCS_CD_9 VARCHAR(10),
    HCPCS_CD_10 VARCHAR(10),
    HCPCS_CD_11 VARCHAR(10),
    HCPCS_CD_12 VARCHAR(10),
    HCPCS_CD_13 VARCHAR(10),
    HCPCS_CD_14 VARCHAR(10),
    HCPCS_CD_15 VARCHAR(10),
    HCPCS_CD_16 VARCHAR(10),
    HCPCS_CD_17 VARCHAR(10),
    HCPCS_CD_18 VARCHAR(10),
    HCPCS_CD_19 VARCHAR(10),
    HCPCS_CD_20 VARCHAR(10),
    HCPCS_CD_21 VARCHAR(10),
    HCPCS_CD_22 VARCHAR(10),
    HCPCS_CD_23 VARCHAR(10),
    HCPCS_CD_24 VARCHAR(10),
    HCPCS_CD_25 VARCHAR(10),
    HCPCS_CD_26 VARCHAR(10),
    HCPCS_CD_27 VARCHAR(10),
    HCPCS_CD_28 VARCHAR(10),
    HCPCS_CD_29 VARCHAR(10),
    HCPCS_CD_30 VARCHAR(10),
    HCPCS_CD_31 VARCHAR(10),
    HCPCS_CD_32 VARCHAR(10),
    HCPCS_CD_33 VARCHAR(10),
    HCPCS_CD_34 VARCHAR(10),
    HCPCS_CD_35 VARCHAR(10),
    HCPCS_CD_36 VARCHAR(10),
    HCPCS_CD_37 VARCHAR(10),
    HCPCS_CD_38 VARCHAR(10),
    HCPCS_CD_39 VARCHAR(10),
    HCPCS_CD_40 VARCHAR(10),
    HCPCS_CD_41 VARCHAR(10),
    HCPCS_CD_42 VARCHAR(10),
    HCPCS_CD_43 VARCHAR(10),
    HCPCS_CD_44 VARCHAR(10),
    HCPCS_CD_45 VARCHAR(10),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CMS DE-SynPUF Outpatient Claims data';

-- ---------------------------------------------------------------------------
-- 2.4 PRESCRIPTION DRUG EVENTS TABLE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE PRESCRIPTION_DRUG_EVENTS (
    DESYNPUF_ID VARCHAR(16) NOT NULL,
    PDE_ID VARCHAR(20) NOT NULL,
    SRVC_DT VARCHAR(8),
    PROD_SRVC_ID VARCHAR(20),
    QTY_DSPNSD_NUM NUMBER(10,3),
    DAYS_SUPLY_NUM NUMBER(5),
    PTNT_PAY_AMT NUMBER(12,2),
    TOT_RX_CST_AMT NUMBER(12,2),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CMS DE-SynPUF Prescription Drug Events data';

-- ---------------------------------------------------------------------------
-- 2.5 CARRIER CLAIMS TABLE (for larger dataset if needed)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE CARRIER_CLAIMS (
    DESYNPUF_ID VARCHAR(16) NOT NULL,
    CLM_ID VARCHAR(20) NOT NULL,
    CLM_FROM_DT VARCHAR(8),
    CLM_THRU_DT VARCHAR(8),
    ICD9_DGNS_CD_1 VARCHAR(10),
    ICD9_DGNS_CD_2 VARCHAR(10),
    ICD9_DGNS_CD_3 VARCHAR(10),
    ICD9_DGNS_CD_4 VARCHAR(10),
    ICD9_DGNS_CD_5 VARCHAR(10),
    ICD9_DGNS_CD_6 VARCHAR(10),
    ICD9_DGNS_CD_7 VARCHAR(10),
    ICD9_DGNS_CD_8 VARCHAR(10),
    PRF_PHYSN_NPI_1 VARCHAR(10),
    TAX_NUM_1 VARCHAR(10),
    HCPCS_CD_1 VARCHAR(10),
    LINE_NCH_PMT_AMT_1 NUMBER(12,2),
    LINE_BENE_PTB_DDCTBL_AMT_1 NUMBER(12,2),
    LINE_BENE_PRMRY_PYR_PD_AMT_1 NUMBER(12,2),
    LINE_COINSRNC_AMT_1 NUMBER(12,2),
    LINE_ALOWD_CHRG_AMT_1 NUMBER(12,2),
    LINE_PRCSG_IND_CD_1 VARCHAR(2),
    LINE_ICD9_DGNS_CD_1 VARCHAR(10),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'CMS DE-SynPUF Carrier Claims data (simplified schema)';

-- ---------------------------------------------------------------------------
-- 2.6 FRAUD FLAGGED CLAIMS TABLE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE FLAGGED_CLAIMS (
    CASE_ID VARCHAR(20) NOT NULL,
    CLM_ID VARCHAR(20) NOT NULL,
    DESYNPUF_ID VARCHAR(16) NOT NULL,
    CLAIM_TYPE VARCHAR(20),
    FRAUD_PATTERN VARCHAR(30),
    FRAUD_SCORE NUMBER(6,4),
    RISK_TIER VARCHAR(10),
    FLAG_DATE DATE,
    FLAG_REASON VARCHAR(500),
    REVIEW_STATUS VARCHAR(30),
    INDICATORS VARCHAR(1000),
    CLM_FROM_DT VARCHAR(8),
    CLM_THRU_DT VARCHAR(8),
    CLM_PMT_AMT NUMBER(12,2),
    PRVDR_NUM VARCHAR(10),
    PRIMARY_DIAGNOSIS VARCHAR(10),
    PRIMARY_PROCEDURE VARCHAR(10),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'ML-flagged potentially fraudulent claims';

-- ---------------------------------------------------------------------------
-- 2.7 CASE NOTES TABLE (for Cortex Search)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE CASE_NOTES (
    NOTE_ID VARCHAR(30) NOT NULL,
    CASE_ID VARCHAR(20) NOT NULL,
    CLM_ID VARCHAR(20) NOT NULL,
    NOTE_DATE DATE,
    INVESTIGATOR VARCHAR(50),
    NOTE_TYPE VARCHAR(30),
    NOTE_TEXT VARCHAR(2000),
    FRAUD_PATTERN VARCHAR(30),
    RISK_TIER VARCHAR(10),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Investigation case notes for Cortex Search';

-- ============================================================================
-- SECTION 3: CREATE REFERENCE TABLES
-- ============================================================================
USE SCHEMA REFERENCE;

CREATE OR REPLACE TABLE REF_ICD9_CODES (
    ICD9_CODE VARCHAR(10) NOT NULL,
    DESCRIPTION VARCHAR(500),
    CODE_TYPE VARCHAR(20),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'ICD-9 diagnosis and procedure code reference';

CREATE OR REPLACE TABLE REF_FRAUD_PATTERNS (
    PATTERN_CODE VARCHAR(30) NOT NULL,
    PATTERN_NAME VARCHAR(100),
    DESCRIPTION VARCHAR(500),
    BASE_RISK_WEIGHT NUMBER(4,2),
    KEY_INDICATORS VARCHAR(1000),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Fraud pattern definitions and indicators';

CREATE OR REPLACE TABLE REF_STATE_CODES (
    STATE_CODE VARCHAR(2) NOT NULL,
    STATE_NAME VARCHAR(50),
    LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'US State code reference';

-- ============================================================================
-- SECTION 4: LOAD DATA FROM STAGE
-- ============================================================================
/*
IMPORTANT: Run these COPY commands AFTER uploading files to the stage.

Adjust file paths based on your stage organization:
- @HHS_DATA_STAGE/cms/ for original CMS files
- @HHS_DATA_STAGE/prepared/ for generated fraud files
*/

USE SCHEMA RAW;

-- Load Beneficiary data (all years)
COPY INTO BENEFICIARY_SUMMARY (
    DESYNPUF_ID, BENE_BIRTH_DT, BENE_DEATH_DT, BENE_SEX_IDENT_CD, BENE_RACE_CD,
    BENE_ESRD_IND, SP_STATE_CODE, BENE_COUNTY_CD, BENE_HI_CVRAGE_TOT_MONS,
    BENE_SMI_CVRAGE_TOT_MONS, BENE_HMO_CVRAGE_TOT_MONS, PLAN_CVRG_MOS_NUM,
    SP_ALZHDMTA, SP_CHF, SP_CHRNKIDN, SP_CNCR, SP_COPD, SP_DEPRESSN,
    SP_DIABETES, SP_ISCHMCHT, SP_OSTEOPRS, SP_RA_OA, SP_STRKETIA,
    MEDREIMB_IP, BENRES_IP, PPPYMT_IP, MEDREIMB_OP, BENRES_OP, PPPYMT_OP,
    MEDREIMB_CAR, BENRES_CAR, PPPYMT_CAR
)
FROM (
    SELECT 
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
        $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28,
        $29, $30, $31, $32
    FROM @HHS_DATA_STAGE
)
FILE_FORMAT = CSV_FORMAT
PATTERN = '.*Beneficiary.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- Load Inpatient Claims
COPY INTO INPATIENT_CLAIMS
FROM @HHS_DATA_STAGE
FILE_FORMAT = CSV_FORMAT
PATTERN = '.*Inpatient.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- Load Outpatient Claims
COPY INTO OUTPATIENT_CLAIMS
FROM @HHS_DATA_STAGE
FILE_FORMAT = CSV_FORMAT
PATTERN = '.*Outpatient.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- Load Prescription Drug Events (sampled file ~180MB)
COPY INTO PRESCRIPTION_DRUG_EVENTS (
    DESYNPUF_ID, PDE_ID, SRVC_DT, PROD_SRVC_ID, QTY_DSPNSD_NUM,
    DAYS_SUPLY_NUM, PTNT_PAY_AMT, TOT_RX_CST_AMT
)
FROM @HHS_DATA_STAGE
FILE_FORMAT = CSV_FORMAT
PATTERN = '.*Prescription.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- Load Carrier Claims (sampled files ~177MB each)
-- Note: Using simplified schema - only loading key fields
COPY INTO CARRIER_CLAIMS (
    DESYNPUF_ID, CLM_ID, CLM_FROM_DT, CLM_THRU_DT,
    ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
    ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
    PRF_PHYSN_NPI_1, TAX_NUM_1, HCPCS_CD_1,
    LINE_NCH_PMT_AMT_1, LINE_BENE_PTB_DDCTBL_AMT_1, LINE_BENE_PRMRY_PYR_PD_AMT_1,
    LINE_COINSRNC_AMT_1, LINE_ALOWD_CHRG_AMT_1, LINE_PRCSG_IND_CD_1, LINE_ICD9_DGNS_CD_1
)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $25, $38,
           $52, $65, $78, $91, $104, $117, $130
    FROM @HHS_DATA_STAGE
)
FILE_FORMAT = CSV_FORMAT
PATTERN = '.*Carrier.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- Load Flagged Claims (generated data)
COPY INTO FLAGGED_CLAIMS (
    CASE_ID, CLM_ID, DESYNPUF_ID, CLAIM_TYPE, FRAUD_PATTERN, FRAUD_SCORE,
    RISK_TIER, FLAG_DATE, FLAG_REASON, REVIEW_STATUS, INDICATORS,
    CLM_FROM_DT, CLM_THRU_DT, CLM_PMT_AMT, PRVDR_NUM, PRIMARY_DIAGNOSIS,
    PRIMARY_PROCEDURE
)
FROM @HHS_DATA_STAGE
FILE_FORMAT = CSV_FORMAT
PATTERN = '.*flagged_claims.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- Load Case Notes (generated data)
COPY INTO CASE_NOTES (
    NOTE_ID, CASE_ID, CLM_ID, NOTE_DATE, INVESTIGATOR, NOTE_TYPE,
    NOTE_TEXT, FRAUD_PATTERN, RISK_TIER
)
FROM @HHS_DATA_STAGE
FILE_FORMAT = CSV_FORMAT
PATTERN = '.*case_notes.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- Load Reference Tables
USE SCHEMA REFERENCE;

COPY INTO REF_ICD9_CODES (ICD9_CODE, DESCRIPTION, CODE_TYPE)
FROM @RAW.HHS_DATA_STAGE
FILE_FORMAT = RAW.CSV_FORMAT
PATTERN = '.*ref_icd9.*\.csv.*'
ON_ERROR = 'CONTINUE';

COPY INTO REF_FRAUD_PATTERNS (PATTERN_CODE, PATTERN_NAME, DESCRIPTION, BASE_RISK_WEIGHT, KEY_INDICATORS)
FROM @RAW.HHS_DATA_STAGE
FILE_FORMAT = RAW.CSV_FORMAT
PATTERN = '.*ref_fraud_patterns.*\.csv.*'
ON_ERROR = 'CONTINUE';

COPY INTO REF_STATE_CODES (STATE_CODE, STATE_NAME)
FROM @RAW.HHS_DATA_STAGE
FILE_FORMAT = RAW.CSV_FORMAT
PATTERN = '.*ref_state.*\.csv.*'
ON_ERROR = 'CONTINUE';

-- ============================================================================
-- SECTION 5: VERIFY DATA LOADS
-- ============================================================================
USE SCHEMA RAW;

SELECT 'BENEFICIARY_SUMMARY' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM BENEFICIARY_SUMMARY
UNION ALL
SELECT 'INPATIENT_CLAIMS', COUNT(*) FROM INPATIENT_CLAIMS
UNION ALL
SELECT 'OUTPATIENT_CLAIMS', COUNT(*) FROM OUTPATIENT_CLAIMS
UNION ALL
SELECT 'PRESCRIPTION_DRUG_EVENTS', COUNT(*) FROM PRESCRIPTION_DRUG_EVENTS
UNION ALL
SELECT 'FLAGGED_CLAIMS', COUNT(*) FROM FLAGGED_CLAIMS
UNION ALL
SELECT 'CASE_NOTES', COUNT(*) FROM CASE_NOTES
UNION ALL
SELECT 'REF_ICD9_CODES', COUNT(*) FROM REFERENCE.REF_ICD9_CODES
UNION ALL
SELECT 'REF_FRAUD_PATTERNS', COUNT(*) FROM REFERENCE.REF_FRAUD_PATTERNS
UNION ALL
SELECT 'REF_STATE_CODES', COUNT(*) FROM REFERENCE.REF_STATE_CODES;

-- Preview flagged claims
SELECT * FROM FLAGGED_CLAIMS LIMIT 10;

/*
================================================================================
NEXT STEPS
================================================================================
1. Verify row counts match expected values
2. Execute worksheet: 02_data_engineering.sql
================================================================================
*/
