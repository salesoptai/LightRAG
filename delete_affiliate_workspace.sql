-- Delete all affiliate workspace tables
-- This will completely remove all data for the "affiliate" workspace

-- Drop all affiliate workspace tables
DROP TABLE IF EXISTS affiliate_documents CASCADE;
DROP TABLE IF EXISTS affiliate_text_chunks CASCADE;
DROP TABLE IF EXISTS affiliate_entities CASCADE;
DROP TABLE IF EXISTS affiliate_relationships CASCADE;
DROP TABLE IF EXISTS affiliate_entity_chunks CASCADE;
DROP TABLE IF EXISTS affiliate_relation_chunks CASCADE;
DROP TABLE IF EXISTS affiliate_full_docs CASCADE;
DROP TABLE IF EXISTS affiliate_full_entities CASCADE;
DROP TABLE IF EXISTS affiliate_full_relations CASCADE;
DROP TABLE IF EXISTS affiliate_llm_response_cache CASCADE;

-- Verify deletion - should return no rows
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name LIKE 'affiliate_%';
