# Manual Workspace Cleanup Instructions

## Option 1: Use Google Cloud Console (Easiest)

1. Go to https://console.cloud.google.com/sql/instances
2. Click on `lightrag-postgres`
3. Click "Open Cloud Shell" button (terminal icon in top right)
4. Run this command:
```bash
gcloud sql connect lightrag-postgres --user=lightrag_user --database=lightrag
```
5. When prompted for password, enter your lightrag_user password
6. Copy and paste these SQL commands:

```sql
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

-- Verify (should return no rows)
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name LIKE 'affiliate_%';
```

7. Type `\q` to exit psql

## Option 2: Use Cloud SQL Proxy Locally

If you have PostgreSQL client tools installed:

1. Start Cloud SQL Proxy:
```powershell
.\cloud-sql-proxy.exe gen-lang-client-0743417261:northamerica-northeast2:lightrag-postgres
```

2. In a new terminal, connect with psql:
```bash
psql -h 127.0.0.1 -p 5432 -U lightrag_user -d lightrag -f delete_affiliate_workspace.sql
```

3. Stop the proxy when done (Ctrl+C)

## What This Does

- Completely removes ALL data from the "affiliate" workspace
- Includes documents, entities, relationships, chunks, and cached LLM responses
- The workspace will start fresh when you next access it

## After Cleanup

The code fix has been applied to prevent this issue from recurring. Future document deletions will properly clean up LLM cache.
