/*
================================================================================
HHS FRAUD DEMO - CORTEX AI SQL SHOWCASE
================================================================================
Worksheet: 06_ai_sql_demo.sql

Demonstrating Snowflake Cortex AI functions for fraud investigation:
  - CLASSIFY_TEXT : Categorize text into custom labels
  - EXTRACT_ANSWER : Pull specific facts from text
  - SENTIMENT : Sentiment/urgency scoring
  - SUMMARIZE : Summarize text
  - COMPLETE : Generate analysis and insights
  - EMBED_TEXT_768 : Vector embeddings for similarity
  - TRANSLATE : Multi-language support

All functions run natively in SQL on your governed data!
================================================================================
*/

-- ============================================================================
-- SETUP
-- ============================================================================
USE ROLE HHS_ADMIN;
USE WAREHOUSE HHS_DEMO_WH;
USE DATABASE HHS_SI_DEMO;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- 🏷️ DEMO 1: CLASSIFY_TEXT - Categorize Investigation Notes
-- Classify free-text notes into YOUR custom action categories
-- ============================================================================

SELECT 
    cn.CASE_ID,
    cn.FRAUD_PATTERN,
    cn.RISK_TIER,
    
    -- Classify into custom action categories
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        cn.NOTE_TEXT,
        ['ESCALATION_NEEDED', 'DOCUMENT_REQUEST', 'AUDIT_REQUIRED', 'ROUTINE']
    )['label']::VARCHAR AS action_needed,
    
    ROUND(SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        cn.NOTE_TEXT,
        ['ESCALATION_NEEDED', 'DOCUMENT_REQUEST', 'AUDIT_REQUIRED', 'ROUTINE']
    )['score']::FLOAT, 2) AS confidence,
    
    LEFT(cn.NOTE_TEXT, 80) || '...' AS note_preview
    
FROM RAW.CASE_NOTES cn
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW'
  AND cn.RISK_TIER = 'CRITICAL'
LIMIT 5;

-- Classify by fraud severity
SELECT 
    cn.CASE_ID,
    cn.FRAUD_PATTERN,
    
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        cn.NOTE_TEXT,
        ['CRIMINAL_REFERRAL', 'ADMINISTRATIVE_ACTION', 'EDUCATION_NEEDED', 'FALSE_POSITIVE']
    )['label']::VARCHAR AS disposition_type,
    
    LEFT(cn.NOTE_TEXT, 100) || '...' AS note_preview
    
FROM RAW.CASE_NOTES cn
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW'
LIMIT 10;

-- ============================================================================
-- 📋 DEMO 2: EXTRACT_ANSWER - Pull Facts from Unstructured Text
-- Ask questions of your text data and get structured answers
-- ============================================================================

-- Extract key investigation details
SELECT 
    cn.CASE_ID,
    cn.FRAUD_PATTERN,
    
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        cn.NOTE_TEXT,
        'What is the dollar amount at risk?'
    )['answer']::VARCHAR AS extracted_amount,
    
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        cn.NOTE_TEXT,
        'What is the provider ID or provider number?'
    )['answer']::VARCHAR AS extracted_provider,
    
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        cn.NOTE_TEXT,
        'What action is recommended?'
    )['answer']::VARCHAR AS next_step,
    
    LEFT(cn.NOTE_TEXT, 60) || '...' AS note_preview
    
FROM RAW.CASE_NOTES cn
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW'
  AND cn.RISK_TIER IN ('CRITICAL', 'HIGH')
LIMIT 5;

-- Extract from flag reasons
SELECT 
    fc.CASE_ID,
    fc.FRAUD_PATTERN,
    fc.CLM_PMT_AMT,
    
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        fc.FLAG_REASON || '. Indicators: ' || fc.INDICATORS,
        'What is the primary fraud concern?'
    )['answer']::VARCHAR AS primary_concern,
    
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        fc.FLAG_REASON || '. Indicators: ' || fc.INDICATORS,
        'What evidence suggests fraud?'
    )['answer']::VARCHAR AS evidence
    
FROM RAW.FLAGGED_CLAIMS fc
WHERE fc.RISK_TIER = 'CRITICAL'
LIMIT 5;

-- ============================================================================
-- 🎭 DEMO 3: SENTIMENT - Detect Investigator Urgency
-- Negative sentiment often indicates higher concern/priority
-- ============================================================================

-- Sentiment as urgency indicator
SELECT 
    cn.CASE_ID,
    cn.RISK_TIER,
    cn.FRAUD_PATTERN,
    
    ROUND(SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT), 3) AS sentiment_score,
    
    CASE 
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT) < -0.3 THEN '🔴 HIGH URGENCY'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT) < 0 THEN '🟡 MODERATE'
        ELSE '🟢 ROUTINE'
    END AS urgency_level,
    
    LEFT(cn.NOTE_TEXT, 100) || '...' AS note_preview
    
FROM RAW.CASE_NOTES cn
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW'
ORDER BY SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT) ASC
LIMIT 10;

-- Compare ML risk tier vs AI-detected urgency
SELECT 
    cn.RISK_TIER AS ml_tier,
    CASE 
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT) < -0.3 THEN 'HIGH_URGENCY'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT) < 0 THEN 'MODERATE'
        ELSE 'ROUTINE'
    END AS ai_urgency,
    COUNT(*) AS case_count,
    ROUND(AVG(SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT)), 3) AS avg_sentiment
FROM RAW.CASE_NOTES cn
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW'
GROUP BY 1, 2
ORDER BY 1, 2;

-- ============================================================================
-- 📝 DEMO 4: SUMMARIZE - Condense Long Text
-- Instant summaries for quick case review
-- ============================================================================

-- Summarize individual case notes
SELECT 
    cn.CASE_ID,
    cn.FRAUD_PATTERN,
    cn.RISK_TIER,
    
    SNOWFLAKE.CORTEX.SUMMARIZE(cn.NOTE_TEXT) AS quick_summary,
    
    cn.NOTE_TEXT AS original_note
    
FROM RAW.CASE_NOTES cn
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW'
  AND cn.RISK_TIER = 'CRITICAL'
LIMIT 5;

-- Summarize combined case timeline
WITH case_timeline AS (
    SELECT 
        CASE_ID,
        LISTAGG(
            CONCAT(NOTE_DATE::VARCHAR, ' - ', NOTE_TYPE, ': ', NOTE_TEXT),
            ' || '
        ) WITHIN GROUP (ORDER BY NOTE_DATE) AS full_history
    FROM RAW.CASE_NOTES
    WHERE CASE_ID = 'CASE-2010-00001'
    GROUP BY CASE_ID
)
SELECT 
    CASE_ID,
    SNOWFLAKE.CORTEX.SUMMARIZE(full_history) AS timeline_summary,
    full_history AS raw_timeline
FROM case_timeline;

-- ============================================================================
-- 🤖 DEMO 5: COMPLETE - Generate Investigation Analysis
-- LLM-powered analysis, recommendations, and insights
-- ============================================================================

-- Generate case briefings
SELECT 
    fc.CASE_ID,
    fc.FRAUD_PATTERN,
    fc.RISK_TIER,
    fc.CLM_PMT_AMT,
    
    SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        CONCAT(
            'You are a fraud investigator. Provide a 2-sentence assessment of this case:\n',
            'Fraud Pattern: ', fc.FRAUD_PATTERN, '\n',
            'Amount: $', fc.CLM_PMT_AMT::VARCHAR, '\n',
            'Risk Level: ', fc.RISK_TIER, '\n',
            'Flag Reason: ', fc.FLAG_REASON, '\n',
            'Indicators: ', fc.INDICATORS
        )
    ) AS ai_assessment
    
FROM RAW.FLAGGED_CLAIMS fc
WHERE fc.RISK_TIER = 'CRITICAL'
LIMIT 3;

-- Generate next steps
SELECT 
    fc.CASE_ID,
    fc.FRAUD_PATTERN,
    fc.CLM_PMT_AMT,
    
    SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        CONCAT(
            'List 3 specific next steps for investigating this ', fc.FRAUD_PATTERN, ' case:\n',
            'Amount at risk: $', fc.CLM_PMT_AMT::VARCHAR, '\n',
            'Provider: ', fc.PRVDR_NUM, '\n',
            'Status: ', fc.REVIEW_STATUS, '\n',
            'Be specific and actionable.'
        )
    ) AS investigation_steps
    
FROM RAW.FLAGGED_CLAIMS fc
WHERE fc.RISK_TIER = 'CRITICAL'
  AND fc.REVIEW_STATUS = 'PENDING_REVIEW'
LIMIT 2;

-- ============================================================================
-- 🔗 DEMO 6: EMBED_TEXT + VECTOR_SIMILARITY - Semantic Search
-- Find similar cases using AI embeddings
-- ============================================================================

-- Create embeddings for case notes
CREATE OR REPLACE TEMPORARY TABLE case_embeddings AS
SELECT 
    cn.CASE_ID,
    cn.FRAUD_PATTERN,
    cn.RISK_TIER,
    fc.CLM_PMT_AMT,
    cn.NOTE_TEXT,
    SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', cn.NOTE_TEXT) AS embedding
FROM RAW.CASE_NOTES cn
JOIN RAW.FLAGGED_CLAIMS fc ON cn.CASE_ID = fc.CASE_ID
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW';

-- Find cases similar to a specific case
WITH target AS (
    SELECT embedding, CASE_ID, NOTE_TEXT
    FROM case_embeddings 
    WHERE CASE_ID = 'CASE-2010-00003'
)
SELECT 
    ce.CASE_ID,
    ce.FRAUD_PATTERN,
    ce.RISK_TIER,
    ce.CLM_PMT_AMT AS amount,
    ROUND(VECTOR_COSINE_SIMILARITY(ce.embedding, t.embedding), 3) AS similarity,
    LEFT(ce.NOTE_TEXT, 100) || '...' AS note_preview
FROM case_embeddings ce
CROSS JOIN target t
WHERE ce.CASE_ID != t.CASE_ID
ORDER BY VECTOR_COSINE_SIMILARITY(ce.embedding, t.embedding) DESC
LIMIT 5;

-- Semantic search: find cases by concept
SELECT 
    ce.CASE_ID,
    ce.FRAUD_PATTERN,
    ce.RISK_TIER,
    ce.CLM_PMT_AMT,
    ROUND(VECTOR_COSINE_SIMILARITY(
        ce.embedding, 
        SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', 'billing for services after patient death')
    ), 3) AS relevance,
    LEFT(ce.NOTE_TEXT, 100) || '...' AS note_preview
FROM case_embeddings ce
ORDER BY relevance DESC
LIMIT 5;

-- Search by natural language query
SELECT 
    ce.CASE_ID,
    ce.FRAUD_PATTERN,
    ce.CLM_PMT_AMT,
    ROUND(VECTOR_COSINE_SIMILARITY(
        ce.embedding, 
        SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', 'provider billing patterns exceed peer average')
    ), 3) AS relevance,
    LEFT(ce.NOTE_TEXT, 80) || '...' AS note_preview
FROM case_embeddings ce
ORDER BY relevance DESC
LIMIT 5;

-- ============================================================================
-- 🌐 DEMO 7: TRANSLATE - Multi-Language Support
-- Support diverse investigation teams
-- ============================================================================

-- Translate case summary to Spanish
SELECT 
    cn.CASE_ID,
    cn.RISK_TIER,
    
    SNOWFLAKE.CORTEX.SUMMARIZE(cn.NOTE_TEXT) AS english_summary,
    
    SNOWFLAKE.CORTEX.TRANSLATE(
        SNOWFLAKE.CORTEX.SUMMARIZE(cn.NOTE_TEXT),
        'en',
        'es'
    ) AS spanish_summary
    
FROM RAW.CASE_NOTES cn
WHERE cn.CASE_ID = 'CASE-2010-00003'
  AND cn.NOTE_TYPE = 'INITIAL_REVIEW';

-- Translate to French
SELECT 
    cn.CASE_ID,
    
    SNOWFLAKE.CORTEX.SUMMARIZE(cn.NOTE_TEXT) AS english_summary,
    
    SNOWFLAKE.CORTEX.TRANSLATE(
        SNOWFLAKE.CORTEX.SUMMARIZE(cn.NOTE_TEXT),
        'en',
        'fr'
    ) AS french_summary
    
FROM RAW.CASE_NOTES cn
WHERE cn.RISK_TIER = 'CRITICAL'
  AND cn.NOTE_TYPE = 'INITIAL_REVIEW'
LIMIT 2;

-- ============================================================================
-- 🎯 DEMO 8: COMBINED PIPELINE - Multi-Function Analysis
-- Chain AI functions for sophisticated case triage
-- ============================================================================

SELECT 
    cn.CASE_ID,
    cn.FRAUD_PATTERN,
    fc.CLM_PMT_AMT AS amount_at_risk,
    
    -- Classification
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        cn.NOTE_TEXT,
        ['ESCALATE', 'INVESTIGATE', 'MONITOR', 'CLOSE']
    )['label']::VARCHAR AS action,
    
    -- Sentiment/Urgency
    ROUND(SNOWFLAKE.CORTEX.SENTIMENT(cn.NOTE_TEXT), 2) AS urgency,
    
    -- Key extraction
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        cn.NOTE_TEXT,
        'What is the provider ID?'
    )['answer']::VARCHAR AS provider,
    
    -- Quick summary
    SNOWFLAKE.CORTEX.SUMMARIZE(cn.NOTE_TEXT) AS summary

FROM RAW.CASE_NOTES cn
JOIN RAW.FLAGGED_CLAIMS fc ON cn.CASE_ID = fc.CASE_ID
WHERE cn.NOTE_TYPE = 'INITIAL_REVIEW'
  AND cn.RISK_TIER = 'CRITICAL'
ORDER BY fc.CLM_PMT_AMT DESC
LIMIT 5;

-- ============================================================================
-- 📊 DEMO 9: EXECUTIVE SUMMARY GENERATION
-- Generate portfolio-level insights
-- ============================================================================

-- Portfolio overview with AI insights
WITH portfolio_stats AS (
    SELECT 
        COUNT(*) AS total_cases,
        SUM(CASE WHEN RISK_TIER = 'CRITICAL' THEN 1 ELSE 0 END) AS critical,
        SUM(CASE WHEN RISK_TIER = 'HIGH' THEN 1 ELSE 0 END) AS high,
        ROUND(SUM(CLM_PMT_AMT), 0) AS total_at_risk,
        COUNT(DISTINCT FRAUD_PATTERN) AS pattern_types
    FROM RAW.FLAGGED_CLAIMS
)
SELECT 
    SNOWFLAKE.CORTEX.COMPLETE(
        'claude-3-5-sonnet',
        CONCAT(
            'Generate a 3-sentence executive summary for this fraud portfolio:\n',
            'Total Cases: ', total_cases, '\n',
            'Critical Cases: ', critical, '\n',
            'High Risk Cases: ', high, '\n',
            'Total Amount at Risk: $', total_at_risk, '\n',
            'Fraud Pattern Types: ', pattern_types, '\n',
            'Write for a compliance executive. Focus on priorities.'
        )
    ) AS executive_summary
FROM portfolio_stats;

-- ============================================================================
-- ✅ DEMO COMPLETE
-- ============================================================================

SELECT 
    '✅ AI SQL Demo Complete!' AS status,
    'CLASSIFY_TEXT, EXTRACT_ANSWER, SENTIMENT, SUMMARIZE, COMPLETE, EMBED_TEXT_768, TRANSLATE' AS functions_demonstrated,
    'All running natively in SQL, on governed data!' AS key_benefit;

/*
================================================================================
DEMO TALKING POINTS
================================================================================

🏷️ CLASSIFY_TEXT - Your custom labels, no training required
   → Classify notes: ESCALATE vs ROUTINE vs DOCUMENT_REQUEST
   → Works out of the box on any text

📋 EXTRACT_ANSWER - Q&A over your data
   → "What is the dollar amount?" → "$15,000"
   → "What provider?" → "2600PG"
   → Structured extraction from unstructured text

🎭 SENTIMENT - Urgency detection
   → Negative sentiment = investigator concern
   → Complements ML risk scores

📝 SUMMARIZE - Instant condensation
   → Turn paragraphs into bullet points
   → Perfect for case dashboards

🤖 COMPLETE - Full LLM power
   → Generate briefings, recommendations, explanations
   → Chain with other functions

🔗 EMBED + VECTOR_SIMILARITY - Semantic search
   → "Find cases similar to this one"
   → Natural language search over cases

🌐 TRANSLATE - Global teams
   → Spanish, French, German, etc.
   → Same data, multiple languages

All running in YOUR warehouse, on YOUR data, with YOUR governance!
================================================================================
*/
