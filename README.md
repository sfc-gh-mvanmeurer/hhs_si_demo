# HHS Fraud Investigation Demo

Snowflake Intelligence demo for Medicare/Medicaid fraud investigation using Cortex Analyst and Cortex Search.

## Overview

ML-flagged claims are triaged and investigated through a conversational AI interface that combines:
- **Cortex Analyst** - Natural language queries over structured data
- **Cortex Search** - Search over investigation notes and guidelines
- **Snowflake Intelligence** - Unified "Fraud Investigation Assistant" agent

## Quick Start

### 1. Prepare Data

```bash
python scripts/prepare_fraud_data.py      # Generate fraud simulation data
python scripts/sample_large_files.py      # Sample large files (<250MB)
```

### 2. Execute SQL (in order)

```sql
@sql/00_setup_environment.sql         -- Database, schemas, warehouse
@sql/01_create_stage_load_data.sql    -- Stage and load data
@sql/02_data_engineering.sql          -- Analytics views
@sql/03_semantic_model.sql            -- Cortex Analyst model
@sql/04_cortex_search.sql             -- Search services
@sql/05_snowflake_intelligence.sql    -- SI agent
```

### 3. Upload Files

Upload to `@HHS_DATA_STAGE/cms/`:
- Beneficiary files (3), Inpatient, Outpatient from `data/`
- Sampled Carrier/Prescription files from `data/sampled/`

Upload to `@HHS_DATA_STAGE/prepared/`:
- Fraud simulation files from `data/prepared/`

## Project Structure

```
hhs_si_demo/
├── data/              # CMS DE-SynPUF data + sampled/prepared subfolders
├── scripts/           # Data preparation scripts
├── sql/               # SQL setup scripts (00-05)
└── docs/              # Architecture documentation
```

## Sample Questions

```
"Show me all critical risk cases that need immediate review"
"Tell me everything about case CASE-2010-00015"
"Which providers have the most flagged claims?"
```

## Data Source

CMS DE-SynPUF (Synthetic Public Use Files) - 100% synthetic, no real patient data.
