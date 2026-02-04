#!/usr/bin/env python3
"""
HHS Fraud Demo - Local Data Preparation Script
===============================================
This script prepares the CMS synthetic data for the Snowflake Intelligence demo:
1. Generates simulated fraud flags on claims
2. Creates synthetic investigation case notes
3. Generates reference lookup tables (ICD-9 codes, fraud indicators)

Run this script BEFORE uploading data to Snowflake internal stage.

Usage:
    python prepare_fraud_data.py
"""

import pandas as pd
import numpy as np
import random
import os
from datetime import datetime, timedelta
import hashlib

# Configuration
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data')
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data', 'prepared')
RANDOM_SEED = 42
NUM_FRAUD_CASES = 150  # Number of claims to flag as potentially fraudulent

# Fraud patterns we'll simulate
FRAUD_PATTERNS = {
    'UPCODING': {
        'description': 'Billing for more expensive services than actually provided',
        'risk_weight': 0.85,
        'indicators': ['High-cost procedure codes', 'Pattern of maximum-level E&M codes', 'Procedure complexity inconsistent with diagnosis']
    },
    'UNBUNDLING': {
        'description': 'Billing separately for services that should be bundled together',
        'risk_weight': 0.75,
        'indicators': ['Multiple related procedure codes on same date', 'Component billing instead of comprehensive codes', 'Sequential modifier abuse']
    },
    'PHANTOM_BILLING': {
        'description': 'Billing for services never rendered',
        'risk_weight': 0.95,
        'indicators': ['Services billed after beneficiary death', 'Impossible service combinations', 'Geographic impossibility']
    },
    'PROVIDER_HOPPING': {
        'description': 'Beneficiary visiting unusually high number of providers',
        'risk_weight': 0.70,
        'indicators': ['Multiple providers same specialty same period', 'Excessive unique provider count', 'Pattern suggests doctor shopping']
    },
    'DUPLICATE_BILLING': {
        'description': 'Same service billed multiple times',
        'risk_weight': 0.80,
        'indicators': ['Identical claims different dates', 'Same service multiple providers same day', 'Duplicate claim submissions']
    },
    'MEDICALLY_UNLIKELY': {
        'description': 'Services that are medically improbable given patient profile',
        'risk_weight': 0.65,
        'indicators': ['Age-inappropriate procedures', 'Gender-specific services mismatch', 'Chronic condition inconsistency']
    }
}

# Sample ICD-9 codes with descriptions (subset for demo)
ICD9_CODES = {
    '4019': 'Unspecified essential hypertension',
    '25000': 'Diabetes mellitus without complication',
    '4280': 'Congestive heart failure, unspecified',
    '42731': 'Atrial fibrillation',
    '2724': 'Other and unspecified hyperlipidemia',
    '7802': 'Syncope and collapse',
    '486': 'Pneumonia, organism unspecified',
    '5849': 'Acute kidney failure, unspecified',
    '78650': 'Chest pain, unspecified',
    '5990': 'Urinary tract infection, site not specified',
    '496': 'Chronic airway obstruction, not elsewhere classified',
    '311': 'Depressive disorder, not elsewhere classified',
    '7245': 'Backache, unspecified',
    '71590': 'Osteoarthrosis, unspecified',
    '7140': 'Rheumatoid arthritis',
    '43411': 'Cerebral embolism with cerebral infarction',
    '41401': 'Coronary atherosclerosis of native coronary artery',
    '5853': 'Chronic kidney disease, Stage III',
    '2768': 'Hypopotassemia',
    '2720': 'Pure hypercholesterolemia'
}

# Investigation note templates
INVESTIGATION_TEMPLATES = {
    'UPCODING': [
        "Initial review flagged claim {claim_id} for potential upcoding. Provider {provider} billed {procedure} (high-complexity) but diagnosis codes ({diagnoses}) suggest routine visit would be appropriate. Recommend chart review to verify service level.",
        "ML model detected billing pattern anomaly for claim {claim_id}. This provider shows consistent pattern of billing highest E&M codes. Claim amount ${amount:.2f} exceeds expected range for diagnosis {diagnoses}. Flagged for auditor review.",
        "Claim {claim_id} triggered upcoding alert. Beneficiary {beneficiary} received {procedure} but historical claims suggest lower acuity visits typical. Provider {provider} has elevated upcoding risk score. Documentation review required."
    ],
    'UNBUNDLING': [
        "Claim {claim_id} flagged for unbundling review. Multiple procedure codes billed separately that typically should be bundled. Services on {service_date} for beneficiary {beneficiary}. Total claim ${amount:.2f}. Cross-reference with CCI edits.",
        "Potential unbundling detected on claim {claim_id}. Provider {provider} billed component codes rather than comprehensive code. Pattern appears across multiple claims. Estimated overpayment if confirmed: ${amount:.2f}.",
        "ML model identified unbundling pattern for claim {claim_id}. Services provided on {service_date} include procedures commonly billed together. Recommend comparison with similar provider billing patterns."
    ],
    'PHANTOM_BILLING': [
        "CRITICAL: Claim {claim_id} billed for services dated {service_date}, but beneficiary {beneficiary} death date recorded as prior to service date. Immediate review required. Provider {provider}. Amount: ${amount:.2f}.",
        "High-priority fraud alert for claim {claim_id}. Geographic analysis indicates beneficiary {beneficiary} could not have been at service location on {service_date}. Provider {provider} flagged for pattern review.",
        "Claim {claim_id} flagged for phantom billing. Service combination ({procedure}) is medically impossible to perform simultaneously. Provider {provider}. Recommend SIU escalation."
    ],
    'PROVIDER_HOPPING': [
        "Beneficiary {beneficiary} associated with claim {claim_id} shows pattern of visiting {provider_count} unique providers for similar services within 90 days. Potential controlled substance seeking behavior or coordinated fraud scheme.",
        "Provider hopping alert for claim {claim_id}. Beneficiary {beneficiary} received overlapping services from multiple providers. Total charges across providers: ${amount:.2f}. Pattern suggests possible prescription fraud.",
        "Claim {claim_id} linked to beneficiary with excessive provider utilization. {provider_count} different providers billed for related diagnoses ({diagnoses}) in short timeframe. Coordination of benefits review recommended."
    ],
    'DUPLICATE_BILLING': [
        "Duplicate billing detected for claim {claim_id}. Identical service ({procedure}) billed by provider {provider} on {service_date}. Previous claim for same service exists. Potential duplicate submission.",
        "Claim {claim_id} matches pattern of prior paid claim. Same beneficiary {beneficiary}, same procedure, different claim ID. System flagged as potential duplicate. Amount at risk: ${amount:.2f}.",
        "ML model identified claim {claim_id} as likely duplicate. Service details match claim paid on previous date. Provider {provider} showing elevated duplicate billing rate. Audit trail review needed."
    ],
    'MEDICALLY_UNLIKELY': [
        "Claim {claim_id} flagged for medically unlikely services. Procedure {procedure} atypical for beneficiary age/gender profile. Beneficiary {beneficiary}. Provider {provider}. Clinical review recommended.",
        "Medical necessity alert for claim {claim_id}. Diagnosis codes ({diagnoses}) do not support procedure billed ({procedure}). Provider {provider} has pattern of questionable medical necessity. Amount: ${amount:.2f}.",
        "Claim {claim_id} triggered improbability alert. Services billed inconsistent with beneficiary's documented chronic conditions. Beneficiary {beneficiary} profile does not match treatment pattern. Review with medical director."
    ]
}


def set_seed():
    """Set random seeds for reproducibility"""
    random.seed(RANDOM_SEED)
    np.random.seed(RANDOM_SEED)


def load_claims_data():
    """Load inpatient and outpatient claims (smaller files for demo)"""
    print("Loading claims data...")
    
    # Load inpatient claims
    inpatient_path = os.path.join(DATA_DIR, 'DE1_0_2008_to_2010_Inpatient_Claims_Sample_1.csv')
    inpatient_df = pd.read_csv(inpatient_path, dtype=str)
    inpatient_df['CLAIM_TYPE'] = 'INPATIENT'
    print(f"  Loaded {len(inpatient_df):,} inpatient claims")
    
    # Load outpatient claims (sample for performance)
    outpatient_path = os.path.join(DATA_DIR, 'DE1_0_2008_to_2010_Outpatient_Claims_Sample_1.csv')
    outpatient_df = pd.read_csv(outpatient_path, dtype=str, nrows=100000)  # Sample first 100K
    outpatient_df['CLAIM_TYPE'] = 'OUTPATIENT'
    print(f"  Loaded {len(outpatient_df):,} outpatient claims (sampled)")
    
    return inpatient_df, outpatient_df


def load_beneficiary_data():
    """Load beneficiary summary data"""
    print("Loading beneficiary data...")
    
    # Use 2010 as primary, supplement with 2009/2008 for history
    bene_2010 = pd.read_csv(os.path.join(DATA_DIR, 'DE1_0_2010_Beneficiary_Summary_File_Sample_1.csv'), dtype=str)
    bene_2010['BENE_YEAR'] = '2010'
    print(f"  Loaded {len(bene_2010):,} beneficiary records (2010)")
    
    return bene_2010


def generate_fraud_flags(inpatient_df, outpatient_df, beneficiary_df):
    """Generate simulated fraud flags for subset of claims"""
    print(f"\nGenerating {NUM_FRAUD_CASES} simulated fraud flags...")
    
    # Combine claims for selection
    all_claims = []
    
    # Select from inpatient (higher value, more fraud-prone)
    inpatient_sample = inpatient_df.sample(n=min(80, len(inpatient_df)), random_state=RANDOM_SEED)
    for _, row in inpatient_sample.iterrows():
        all_claims.append({
            'CLM_ID': row['CLM_ID'],
            'DESYNPUF_ID': row['DESYNPUF_ID'],
            'CLAIM_TYPE': 'INPATIENT',
            'CLM_FROM_DT': row.get('CLM_FROM_DT', ''),
            'CLM_THRU_DT': row.get('CLM_THRU_DT', ''),
            'CLM_PMT_AMT': row.get('CLM_PMT_AMT', '0'),
            'PRVDR_NUM': row.get('PRVDR_NUM', ''),
            'ICD9_DGNS_CD_1': row.get('ICD9_DGNS_CD_1', ''),
            'HCPCS_CD_1': row.get('HCPCS_CD_1', '')
        })
    
    # Select from outpatient
    outpatient_sample = outpatient_df.sample(n=min(70, len(outpatient_df)), random_state=RANDOM_SEED)
    for _, row in outpatient_sample.iterrows():
        all_claims.append({
            'CLM_ID': row['CLM_ID'],
            'DESYNPUF_ID': row['DESYNPUF_ID'],
            'CLAIM_TYPE': 'OUTPATIENT',
            'CLM_FROM_DT': row.get('CLM_FROM_DT', ''),
            'CLM_THRU_DT': row.get('CLM_THRU_DT', ''),
            'CLM_PMT_AMT': row.get('CLM_PMT_AMT', '0'),
            'PRVDR_NUM': row.get('PRVDR_NUM', ''),
            'ICD9_DGNS_CD_1': row.get('ICD9_DGNS_CD_1', ''),
            'HCPCS_CD_1': row.get('HCPCS_CD_1', '')
        })
    
    # Assign fraud patterns
    fraud_types = list(FRAUD_PATTERNS.keys())
    flagged_claims = []
    
    for i, claim in enumerate(all_claims[:NUM_FRAUD_CASES]):
        fraud_type = fraud_types[i % len(fraud_types)]
        pattern = FRAUD_PATTERNS[fraud_type]
        
        # Generate fraud score (biased toward higher scores for demo impact)
        base_score = pattern['risk_weight']
        fraud_score = min(0.99, base_score + random.uniform(-0.15, 0.15))
        
        # Generate flag date (recent dates for demo relevance)
        flag_date = datetime(2010, 1, 1) + timedelta(days=random.randint(0, 364))
        
        # Assign risk tier
        if fraud_score >= 0.85:
            risk_tier = 'CRITICAL'
        elif fraud_score >= 0.70:
            risk_tier = 'HIGH'
        elif fraud_score >= 0.55:
            risk_tier = 'MEDIUM'
        else:
            risk_tier = 'LOW'
        
        # Assign review status
        statuses = ['PENDING_REVIEW', 'UNDER_INVESTIGATION', 'ESCALATED', 'PENDING_DOCUMENTATION']
        status_weights = [0.4, 0.3, 0.15, 0.15]
        review_status = random.choices(statuses, weights=status_weights)[0]
        
        # Create unique case ID
        case_id = f"CASE-{flag_date.year}-{str(i+1).zfill(5)}"
        
        flagged_claims.append({
            'CASE_ID': case_id,
            'CLM_ID': claim['CLM_ID'],
            'DESYNPUF_ID': claim['DESYNPUF_ID'],
            'CLAIM_TYPE': claim['CLAIM_TYPE'],
            'FRAUD_PATTERN': fraud_type,
            'FRAUD_SCORE': round(fraud_score, 4),
            'RISK_TIER': risk_tier,
            'FLAG_DATE': flag_date.strftime('%Y-%m-%d'),
            'FLAG_REASON': pattern['description'],
            'REVIEW_STATUS': review_status,
            'INDICATORS': '|'.join(pattern['indicators']),
            'CLM_FROM_DT': claim['CLM_FROM_DT'],
            'CLM_THRU_DT': claim['CLM_THRU_DT'],
            'CLM_PMT_AMT': claim['CLM_PMT_AMT'],
            'PRVDR_NUM': claim['PRVDR_NUM'],
            'PRIMARY_DIAGNOSIS': claim['ICD9_DGNS_CD_1'],
            'PRIMARY_PROCEDURE': claim['HCPCS_CD_1']
        })
    
    fraud_df = pd.DataFrame(flagged_claims)
    print(f"  Generated {len(fraud_df)} fraud flags")
    print(f"  Distribution by pattern: {fraud_df['FRAUD_PATTERN'].value_counts().to_dict()}")
    print(f"  Distribution by risk tier: {fraud_df['RISK_TIER'].value_counts().to_dict()}")
    
    return fraud_df


def generate_case_notes(fraud_df):
    """Generate synthetic investigation case notes for each flagged claim"""
    print("\nGenerating investigation case notes...")
    
    case_notes = []
    investigators = ['J. Martinez', 'S. Thompson', 'R. Chen', 'M. Williams', 'A. Patel', 'K. Johnson']
    
    for _, row in fraud_df.iterrows():
        fraud_type = row['FRAUD_PATTERN']
        templates = INVESTIGATION_TEMPLATES[fraud_type]
        template = random.choice(templates)
        
        # Parse amount safely
        try:
            amount = float(row['CLM_PMT_AMT']) if row['CLM_PMT_AMT'] else 0.0
        except:
            amount = 0.0
        
        # Format the note
        note_text = template.format(
            claim_id=row['CLM_ID'],
            beneficiary=row['DESYNPUF_ID'][:8] + '...',  # Truncate for privacy appearance
            provider=row['PRVDR_NUM'] or 'UNKNOWN',
            procedure=row['PRIMARY_PROCEDURE'] or 'N/A',
            diagnoses=row['PRIMARY_DIAGNOSIS'] or 'N/A',
            service_date=row['CLM_FROM_DT'] or 'N/A',
            amount=amount,
            provider_count=random.randint(5, 15)
        )
        
        # Generate note metadata
        note_date = datetime.strptime(row['FLAG_DATE'], '%Y-%m-%d') + timedelta(days=random.randint(1, 14))
        investigator = random.choice(investigators)
        
        # Create note ID
        note_id = f"NOTE-{row['CASE_ID']}-{str(random.randint(1000, 9999))}"
        
        case_notes.append({
            'NOTE_ID': note_id,
            'CASE_ID': row['CASE_ID'],
            'CLM_ID': row['CLM_ID'],
            'NOTE_DATE': note_date.strftime('%Y-%m-%d'),
            'INVESTIGATOR': investigator,
            'NOTE_TYPE': 'INITIAL_REVIEW',
            'NOTE_TEXT': note_text,
            'FRAUD_PATTERN': fraud_type,
            'RISK_TIER': row['RISK_TIER']
        })
        
        # Add follow-up notes for some cases
        if row['REVIEW_STATUS'] in ['UNDER_INVESTIGATION', 'ESCALATED']:
            followup_date = note_date + timedelta(days=random.randint(3, 21))
            followup_templates = [
                f"Follow-up on {row['CASE_ID']}: Requested medical records from provider. Awaiting response. Escalation deadline: {(followup_date + timedelta(days=30)).strftime('%Y-%m-%d')}.",
                f"Case {row['CASE_ID']} update: Spoke with provider billing department. They are gathering documentation to support medical necessity. Will review upon receipt.",
                f"Investigation progress on {row['CASE_ID']}: Compared billing patterns with peer providers. This provider's {fraud_type.lower().replace('_', ' ')} rate is 2.3x higher than regional average. Recommend continued monitoring.",
                f"Case {row['CASE_ID']}: Cross-referenced beneficiary claims history. Found {random.randint(2, 7)} additional claims with similar patterns. Expanding investigation scope."
            ]
            
            case_notes.append({
                'NOTE_ID': f"NOTE-{row['CASE_ID']}-{str(random.randint(1000, 9999))}",
                'CASE_ID': row['CASE_ID'],
                'CLM_ID': row['CLM_ID'],
                'NOTE_DATE': followup_date.strftime('%Y-%m-%d'),
                'INVESTIGATOR': investigator,
                'NOTE_TYPE': 'FOLLOW_UP',
                'NOTE_TEXT': random.choice(followup_templates),
                'FRAUD_PATTERN': fraud_type,
                'RISK_TIER': row['RISK_TIER']
            })
    
    notes_df = pd.DataFrame(case_notes)
    print(f"  Generated {len(notes_df)} case notes")
    
    return notes_df


def generate_reference_tables():
    """Generate reference lookup tables"""
    print("\nGenerating reference tables...")
    
    # ICD-9 codes reference
    icd9_df = pd.DataFrame([
        {'ICD9_CODE': code, 'DESCRIPTION': desc, 'CODE_TYPE': 'DIAGNOSIS'}
        for code, desc in ICD9_CODES.items()
    ])
    print(f"  Generated {len(icd9_df)} ICD-9 code references")
    
    # Fraud pattern reference
    fraud_ref_df = pd.DataFrame([
        {
            'PATTERN_CODE': code,
            'PATTERN_NAME': code.replace('_', ' ').title(),
            'DESCRIPTION': pattern['description'],
            'BASE_RISK_WEIGHT': pattern['risk_weight'],
            'KEY_INDICATORS': '|'.join(pattern['indicators'])
        }
        for code, pattern in FRAUD_PATTERNS.items()
    ])
    print(f"  Generated {len(fraud_ref_df)} fraud pattern references")
    
    # State codes reference (subset)
    state_codes = {
        '01': 'Alabama', '02': 'Alaska', '04': 'Arizona', '05': 'Arkansas',
        '06': 'California', '08': 'Colorado', '09': 'Connecticut', '10': 'Delaware',
        '11': 'District of Columbia', '12': 'Florida', '13': 'Georgia', '15': 'Hawaii',
        '16': 'Idaho', '17': 'Illinois', '18': 'Indiana', '19': 'Iowa',
        '20': 'Kansas', '21': 'Kentucky', '22': 'Louisiana', '23': 'Maine',
        '24': 'Maryland', '25': 'Massachusetts', '26': 'Michigan', '27': 'Minnesota',
        '28': 'Mississippi', '29': 'Missouri', '30': 'Montana', '31': 'Nebraska',
        '32': 'Nevada', '33': 'New Hampshire', '34': 'New Jersey', '35': 'New Mexico',
        '36': 'New York', '37': 'North Carolina', '38': 'North Dakota', '39': 'Ohio',
        '40': 'Oklahoma', '41': 'Oregon', '42': 'Pennsylvania', '44': 'Rhode Island',
        '45': 'South Carolina', '46': 'South Dakota', '47': 'Tennessee', '48': 'Texas',
        '49': 'Utah', '50': 'Vermont', '51': 'Virginia', '53': 'Washington',
        '54': 'West Virginia', '55': 'Wisconsin', '56': 'Wyoming', '52': 'Puerto Rico'
    }
    state_df = pd.DataFrame([
        {'STATE_CODE': code, 'STATE_NAME': name}
        for code, name in state_codes.items()
    ])
    print(f"  Generated {len(state_df)} state code references")
    
    return icd9_df, fraud_ref_df, state_df


def save_outputs(fraud_df, notes_df, icd9_df, fraud_ref_df, state_df):
    """Save all prepared data to CSV files"""
    print(f"\nSaving outputs to {OUTPUT_DIR}...")
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Save fraud flags
    fraud_path = os.path.join(OUTPUT_DIR, 'flagged_claims.csv')
    fraud_df.to_csv(fraud_path, index=False)
    print(f"  Saved: flagged_claims.csv ({len(fraud_df)} rows)")
    
    # Save case notes
    notes_path = os.path.join(OUTPUT_DIR, 'case_notes.csv')
    notes_df.to_csv(notes_path, index=False)
    print(f"  Saved: case_notes.csv ({len(notes_df)} rows)")
    
    # Save reference tables
    icd9_path = os.path.join(OUTPUT_DIR, 'ref_icd9_codes.csv')
    icd9_df.to_csv(icd9_path, index=False)
    print(f"  Saved: ref_icd9_codes.csv ({len(icd9_df)} rows)")
    
    fraud_ref_path = os.path.join(OUTPUT_DIR, 'ref_fraud_patterns.csv')
    fraud_ref_df.to_csv(fraud_ref_path, index=False)
    print(f"  Saved: ref_fraud_patterns.csv ({len(fraud_ref_df)} rows)")
    
    state_path = os.path.join(OUTPUT_DIR, 'ref_state_codes.csv')
    state_df.to_csv(state_path, index=False)
    print(f"  Saved: ref_state_codes.csv ({len(state_df)} rows)")


def main():
    """Main execution"""
    print("=" * 60)
    print("HHS Fraud Demo - Data Preparation")
    print("=" * 60)
    
    set_seed()
    
    # Load source data
    inpatient_df, outpatient_df = load_claims_data()
    beneficiary_df = load_beneficiary_data()
    
    # Generate fraud simulation data
    fraud_df = generate_fraud_flags(inpatient_df, outpatient_df, beneficiary_df)
    notes_df = generate_case_notes(fraud_df)
    
    # Generate reference tables
    icd9_df, fraud_ref_df, state_df = generate_reference_tables()
    
    # Save all outputs
    save_outputs(fraud_df, notes_df, icd9_df, fraud_ref_df, state_df)
    
    print("\n" + "=" * 60)
    print("Data preparation complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Review generated files in data/prepared/")
    print("2. Upload all CSV files to Snowflake internal stage")
    print("3. Execute SQL worksheets in sequence (00 through 05)")


if __name__ == "__main__":
    main()
