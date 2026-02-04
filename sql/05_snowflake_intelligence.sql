/*
================================================================================
HHS FRAUD DEMO - SNOWFLAKE INTELLIGENCE AGENT SETUP
================================================================================
Worksheet: 05_snowflake_intelligence.sql
Purpose: Create Snowflake Intelligence agent with:
- Semantic Views for structured data analysis via Cortex Analyst
- Cortex Search services for unstructured data retrieval

The agent can answer natural language questions about:
- Fraud case details and patterns
- Beneficiary demographics and health profiles
- Provider risk analysis
- Investigation notes and guidelines

Reference: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage
================================================================================
*/

-- ============================================================================
-- SETUP
-- ============================================================================
USE ROLE ACCOUNTADMIN;  -- Need ACCOUNTADMIN to create agents
USE WAREHOUSE HHS_DEMO_WH;
USE DATABASE HHS_SI_DEMO;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- STEP 1: VERIFY PREREQUISITES
-- ============================================================================

-- Verify semantic views exist
SELECT 'Checking Semantic Views...' AS status;
SHOW SEMANTIC VIEWS IN SCHEMA HHS_SI_DEMO.ANALYTICS;

-- Verify Cortex Search services exist
SELECT 'Checking Cortex Search Services...' AS status;
SHOW CORTEX SEARCH SERVICES IN SCHEMA HHS_SI_DEMO.CORTEX;

-- Verify base views exist
SELECT 'Checking Base Views...' AS status;
SHOW VIEWS LIKE 'VW_%' IN SCHEMA HHS_SI_DEMO.ANALYTICS;

-- Verify data exists
SELECT 'Checking Data Counts...' AS status;
SELECT 
    (SELECT COUNT(*) FROM HHS_SI_DEMO.ANALYTICS.VW_FRAUD_CASES_BASE) AS fraud_cases,
    (SELECT COUNT(*) FROM HHS_SI_DEMO.ANALYTICS.VW_BENEFICIARIES_BASE) AS beneficiaries,
    (SELECT COUNT(*) FROM HHS_SI_DEMO.ANALYTICS.VW_PROVIDERS_BASE) AS providers,
    (SELECT COUNT(*) FROM HHS_SI_DEMO.CORTEX.CASE_NOTES_SEARCH) AS case_notes,
    (SELECT COUNT(*) FROM HHS_SI_DEMO.CORTEX.FRAUD_KNOWLEDGE_BASE) AS knowledge_docs;

-- ============================================================================
-- STEP 2: CREATE AGENT ROLE AND PERMISSIONS
-- ============================================================================

USE ROLE securityADMIN;

-- Create a role specifically for the Intelligence agent
CREATE ROLE IF NOT EXISTS HHS_INTELLIGENCE_ROLE
    COMMENT = 'Role for HHS Fraud Investigation Intelligence Agent';

-- Grant necessary privileges
GRANT USAGE ON DATABASE HHS_SI_DEMO TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT USAGE ON SCHEMA HHS_SI_DEMO.ANALYTICS TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT USAGE ON SCHEMA HHS_SI_DEMO.CORTEX TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT USAGE ON SCHEMA HHS_SI_DEMO.RAW TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT USAGE ON SCHEMA HHS_SI_DEMO.REFERENCE TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT USAGE ON WAREHOUSE HHS_DEMO_WH TO ROLE HHS_INTELLIGENCE_ROLE;

-- Grant access to semantic views (REFERENCES + SELECT needed for Cortex Analyst)
GRANT REFERENCES, SELECT ON ALL SEMANTIC VIEWS IN SCHEMA HHS_SI_DEMO.ANALYTICS TO ROLE HHS_INTELLIGENCE_ROLE;

-- Grant access to base views
GRANT SELECT ON ALL VIEWS IN SCHEMA HHS_SI_DEMO.ANALYTICS TO ROLE HHS_INTELLIGENCE_ROLE;

-- Grant access to Cortex Search services
GRANT USAGE ON ALL CORTEX SEARCH SERVICES IN SCHEMA HHS_SI_DEMO.CORTEX TO ROLE HHS_INTELLIGENCE_ROLE;

-- Grant SELECT on underlying tables
GRANT SELECT ON ALL TABLES IN SCHEMA HHS_SI_DEMO.RAW TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA HHS_SI_DEMO.CORTEX TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA HHS_SI_DEMO.REFERENCE TO ROLE HHS_INTELLIGENCE_ROLE;

-- Grant role to HHS_ADMIN and ACCOUNTADMIN
GRANT ROLE HHS_INTELLIGENCE_ROLE TO ROLE HHS_ADMIN;
GRANT ROLE HHS_INTELLIGENCE_ROLE TO ROLE ACCOUNTADMIN;

-- ============================================================================
-- STEP 3: TEST BASE VIEWS
-- ============================================================================

-- Test 1: Fraud cases data
SELECT 'Testing VW_FRAUD_CASES_BASE...' AS test;
SELECT 
    FRAUD_PATTERN_DISPLAY AS fraud_pattern,
    RISK_TIER,
    COUNT(*) AS case_count,
    ROUND(SUM(CLAIM_AMOUNT), 2) AS total_at_risk,
    ROUND(AVG(FRAUD_SCORE), 3) AS avg_score
FROM VW_FRAUD_CASES_BASE
GROUP BY FRAUD_PATTERN_DISPLAY, RISK_TIER
ORDER BY case_count DESC
LIMIT 15;

-- Test 2: Provider risk data
SELECT 'Testing VW_PROVIDERS_BASE...' AS test;
SELECT 
    PROVIDER_RISK_CATEGORY,
    COUNT(*) AS provider_count,
    SUM(FLAGGED_CLAIM_COUNT) AS total_flagged_claims,
    ROUND(SUM(TOTAL_FLAGGED_AMOUNT), 2) AS total_amount,
    ROUND(AVG(AVG_FRAUD_SCORE), 3) AS avg_score
FROM VW_PROVIDERS_BASE
GROUP BY PROVIDER_RISK_CATEGORY
ORDER BY avg_score DESC;

-- Test 3: Beneficiary data
SELECT 'Testing VW_BENEFICIARIES_BASE...' AS test;
SELECT 
    STATE_NAME,
    COUNT(*) AS beneficiary_count,
    ROUND(AVG(AGE), 1) AS avg_age,
    ROUND(AVG(CHRONIC_CONDITION_COUNT), 2) AS avg_conditions,
    ROUND(SUM(TOTAL_REIMBURSEMENT), 2) AS total_reimbursement
FROM VW_BENEFICIARIES_BASE
WHERE STATE_NAME IS NOT NULL
GROUP BY STATE_NAME
ORDER BY beneficiary_count DESC
LIMIT 10;

-- ============================================================================
-- STEP 4: VERIFY SEMANTIC VIEWS
-- ============================================================================

-- Describe each semantic view to verify structure
DESCRIBE SEMANTIC VIEW FRAUD_CASE_ANALYTICS;
DESCRIBE SEMANTIC VIEW BENEFICIARY_ANALYTICS;
DESCRIBE SEMANTIC VIEW PROVIDER_RISK_ANALYTICS;

-- ============================================================================
-- STEP 5: CREATE SNOWFLAKE INTELLIGENCE AGENT
-- ============================================================================

CREATE OR REPLACE AGENT HHS_SI_DEMO.ANALYTICS.FRAUD_INVESTIGATION_AGENT
    COMMENT = 'AI assistant for HHS Medicare/Medicaid fraud investigation'
    PROFILE = '{
        "display_name": "Fraud Investigation Assistant",
        "avatar": "🔍",
        "color": "#B91C1C"
    }'
    FROM SPECIFICATION
$$
models:
  orchestration: claude-4-sonnet

orchestration:
  budget:
    seconds: 60
    tokens: 32000

instructions:
  system: |
    You are the Fraud Investigation Assistant for HHS Medicare and Medicaid claims review.
    
    IMPORTANT DEMO CONTEXT:
    This is a demonstration environment using CMS synthetic data from 2008-2010. 
    When discussing dates and timeframes:
    - Treat the current date as December 2010 for the purpose of this demo
    - Claims and services are from 2008-2010
    - Cases were flagged by the ML model throughout 2010
    - Do NOT reference the actual current date - stay in the 2010 timeframe
    - When asked about "recent" cases, interpret this as late 2010
    - "Days since flagged" should be interpreted relative to late 2010
    
    You help fraud investigators quickly understand and triage potentially fraudulent claims
    that have been flagged by an ML detection model.
    
    You can analyze:
    - Fraud cases by pattern, risk tier, and review status
    - Beneficiary demographics and health profiles  
    - Provider risk patterns and flagged claim histories
    - Investigation notes and fraud detection guidelines
    
    Always prioritize CRITICAL and HIGH risk cases. Be specific with case IDs and dollar amounts.

  orchestration: |
    Tool Selection Guidelines:
    
    1. For STRUCTURED DATA queries (counts, averages, comparisons, filtering):
       - Use FraudCaseAnalyst for fraud cases, patterns, risk tiers, claim amounts
       - Use BeneficiaryAnalyst for beneficiary demographics, health conditions, reimbursements
       - Use ProviderAnalyst for provider risk profiles, flagged claim counts
    
    2. For SEARCH queries (find specific notes, guidelines, documentation):
       - Use CaseNotesSearch for finding investigation notes by case, pattern, or investigator
       - Use KnowledgeSearch for fraud investigation guidelines and procedures
    
    3. For VISUALIZATION requests:
       - Use data_to_chart to generate charts from query results
    
    Multi-tool coordination:
    - For case details: query FraudCaseAnalyst first, then CaseNotesSearch for notes
    - For investigation guidance: use KnowledgeSearch, supplement with similar cases
    - For provider analysis: use ProviderAnalyst, then FraudCaseAnalyst for their cases

  response: |
    Response Guidelines:
    - Lead with the direct answer - don't make investigators dig
    - Include specific case IDs, dollar amounts, and fraud scores
    - Prioritize by risk tier: CRITICAL > HIGH > MEDIUM > LOW
    - For case lookups, include: fraud pattern, amount, provider, beneficiary context
    - Recommend specific next steps when appropriate
    - Acknowledge limitations if data is incomplete
    
    Risk Tiers:
    - CRITICAL: Immediate review required (fraud score 0.85+)
    - HIGH: Priority review (fraud score 0.70-0.84)
    - MEDIUM: Standard review (fraud score 0.55-0.69)
    - LOW: Monitor only (fraud score <0.55)
    
    Fraud Patterns:
    - UPCODING: Billing for more expensive services than provided
    - UNBUNDLING: Billing separately for services that should be bundled
    - PHANTOM_BILLING: Billing for services never rendered
    - PROVIDER_HOPPING: Suspicious multi-provider utilization
    - DUPLICATE_BILLING: Same service billed multiple times
    - MEDICALLY_UNLIKELY: Services inappropriate for patient profile

  sample_questions:
    - question: "Show me all critical risk cases pending review"
      answer: "I'll query fraud cases filtered by CRITICAL risk tier and PENDING_REVIEW status, ordered by fraud score."
    - question: "What fraud patterns are most common?"
      answer: "I'll analyze fraud cases grouped by pattern type with counts and total amounts at risk."
    - question: "Tell me about case CASE-2010-00015"
      answer: "I'll retrieve the case details and search for any related investigation notes."
    - question: "Which providers have the highest fraud risk?"
      answer: "I'll query the provider risk data ordered by average fraud score and flagged claim count."
    - question: "How do I investigate a phantom billing case?"
      answer: "I'll search the knowledge base for phantom billing investigation guidelines."

tools:
  # Cortex Analyst tools for structured data
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: FraudCaseAnalyst
      description: "Analyzes fraud cases including patterns, risk tiers, claim amounts, review status, and beneficiary/provider details. Use for questions about case counts, amounts at risk, fraud scores, and case filtering."
  
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: BeneficiaryAnalyst
      description: "Analyzes Medicare/Medicaid beneficiary demographics, health conditions, and reimbursement data. Use for questions about patient profiles, chronic conditions, and healthcare utilization."
  
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: ProviderAnalyst
      description: "Analyzes provider-level fraud risk including flagged claim counts, fraud scores, and risk categories. Use for questions about high-risk providers and billing patterns."

  # Cortex Search tools for unstructured search
  - tool_spec:
      type: cortex_search
      name: CaseNotesSearch
      description: "Search investigation case notes by case ID, fraud pattern, investigator, or keywords. Use when user wants to find investigation history or similar past cases."
  
  - tool_spec:
      type: cortex_search
      name: KnowledgeSearch
      description: "Search fraud investigation guidelines, procedures, and best practices. Use when user asks how to investigate specific fraud types or wants policy guidance."

  # Visualization tool
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Generate visualizations from data. Use when query results would benefit from a chart or graph."

tool_resources:
  FraudCaseAnalyst:
    semantic_view: HHS_SI_DEMO.ANALYTICS.FRAUD_CASE_ANALYTICS
  
  BeneficiaryAnalyst:
    semantic_view: HHS_SI_DEMO.ANALYTICS.BENEFICIARY_ANALYTICS
  
  ProviderAnalyst:
    semantic_view: HHS_SI_DEMO.ANALYTICS.PROVIDER_RISK_ANALYTICS
  
  CaseNotesSearch:
    name: HHS_SI_DEMO.CORTEX.FRAUD_CASE_SEARCH
    max_results: 10
    title_column: CASE_ID
    id_column: NOTE_ID
  
  KnowledgeSearch:
    name: HHS_SI_DEMO.CORTEX.FRAUD_KNOWLEDGE_SEARCH
    max_results: 5
    title_column: DOC_TITLE
    id_column: DOC_ID
$$;

-- Grant usage on the agent to appropriate roles
GRANT USAGE ON AGENT HHS_SI_DEMO.ANALYTICS.FRAUD_INVESTIGATION_AGENT TO ROLE HHS_INTELLIGENCE_ROLE;
GRANT USAGE ON AGENT HHS_SI_DEMO.ANALYTICS.FRAUD_INVESTIGATION_AGENT TO ROLE HHS_ADMIN;
GRANT USAGE ON AGENT HHS_SI_DEMO.ANALYTICS.FRAUD_INVESTIGATION_AGENT TO ROLE HHS_ANALYST;

-- ============================================================================
-- STEP 6: VERIFY AGENT CREATION
-- ============================================================================

-- Verify the agent was created
SHOW AGENTS IN SCHEMA HHS_SI_DEMO.ANALYTICS;
DESCRIBE AGENT HHS_SI_DEMO.ANALYTICS.FRAUD_INVESTIGATION_AGENT;

-- ============================================================================
-- STEP 7: VERIFICATION SUMMARY
-- ============================================================================

SELECT 'Setup Verification Summary' AS status;

-- Count semantic views (use SHOW command, not INFORMATION_SCHEMA)
SHOW SEMANTIC VIEWS IN SCHEMA HHS_SI_DEMO.ANALYTICS;

-- Count base views  
SELECT 'Base Views Created' AS check_item,
       COUNT(*) AS count
FROM INFORMATION_SCHEMA.VIEWS 
WHERE TABLE_SCHEMA = 'ANALYTICS' 
  AND TABLE_NAME LIKE 'VW_%';

-- Verify role exists
SHOW ROLES LIKE 'HHS_INTELLIGENCE_ROLE';

SELECT '✅ Fraud Investigation Agent setup complete!' AS status;
SELECT 'Access via: Snowsight > AI & ML > Agents' AS next_step;

/*
================================================================================
DEMO SCRIPT - QUESTIONS TO ASK THE AGENT
================================================================================

TRIAGE & PRIORITIZATION:
1. "Show me all critical risk cases that need immediate review"
2. "How many cases are in each review status?"
3. "Which cases have been flagged the longest without resolution?"

PATTERN ANALYSIS:
4. "Break down fraud cases by pattern type - what's most common?"
5. "Show me upcoding cases with fraud scores above 0.8"
6. "What's the total dollar amount at risk across all flagged claims?"

CASE INVESTIGATION:
7. "Tell me everything about case CASE-2010-00001"
8. "Find investigation notes related to phantom billing"
9. "Show me cases for provider 2600PG"

PROVIDER FOCUS:
10. "Which providers have the highest fraud risk scores?"
11. "Show providers with more than 3 flagged claims"
12. "What fraud patterns is provider 3900MB associated with?"

BENEFICIARY ANALYSIS:
13. "What's the average age of beneficiaries in flagged claims?"
14. "Show beneficiaries with multiple flagged claims"
15. "Which states have the most flagged cases?"

INVESTIGATION GUIDANCE:
16. "How do I investigate a phantom billing case?"
17. "What are the red flags for unbundling fraud?"
18. "What evidence should I gather for an upcoding investigation?"

================================================================================
*/
