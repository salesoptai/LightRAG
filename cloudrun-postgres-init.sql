-- LightRAG PostgreSQL Database Initialization Script
-- This script sets up the database, user, and required extensions for LightRAG

-- ============================================================================
-- STEP 1: Create database and user (run as postgres superuser)
-- ============================================================================

-- Create the database
CREATE DATABASE lightrag
    WITH 
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;

-- Create the user
CREATE USER lightrag_user WITH PASSWORD 'YOUR_SECURE_PASSWORD_HERE';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE lightrag TO lightrag_user;

-- ============================================================================
-- STEP 2: Enable extensions (connect to lightrag database first: \c lightrag)
-- ============================================================================

-- Connect to the lightrag database
\c lightrag

-- Enable pgvector extension (REQUIRED for vector storage)
-- This must be installed on your Cloud SQL instance first
CREATE EXTENSION IF NOT EXISTS vector;

-- Optional: Enable other useful extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For text search optimizations

-- Grant schema permissions to the user
GRANT ALL ON SCHEMA public TO lightrag_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lightrag_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lightrag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO lightrag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO lightrag_user;

-- ============================================================================
-- STEP 3: Verify installation
-- ============================================================================

-- Verify pgvector extension
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Test vector operations
SELECT '[1,2,3]'::vector;

-- Show database size (should be minimal at this point)
SELECT pg_size_pretty(pg_database_size('lightrag')) AS database_size;

-- ============================================================================
-- NOTES:
-- ============================================================================
-- 
-- 1. Cloud SQL PostgreSQL Setup:
--    - Ensure you have PostgreSQL 11+ (14 or 15 recommended)
--    - Install pgvector extension via Cloud SQL flags or Google Cloud Console
--    - For Cloud SQL, you may need to enable the pgvector extension via:
--      gcloud sql instances patch INSTANCE_NAME --database-flags=cloudsql.enable_pgvector=on
--
-- 2. Table Creation:
--    - LightRAG will automatically create all required tables on first run
--    - Tables created: entities, relationships, chunks, documents, and internal metadata
--    - No manual table creation is needed
--
-- 3. Security:
--    - Replace 'YOUR_SECURE_PASSWORD_HERE' with a strong password
--    - Store the password in Google Secret Manager, not in code
--    - Use SSL connections in production (configure POSTGRES_SSL_MODE=require)
--
-- 4. Performance:
--    - Default HNSW vector index settings are optimized for most use cases
--    - Adjust POSTGRES_HNSW_M and POSTGRES_HNSW_EF in .env if needed
--    - Monitor query performance and adjust Cloud SQL tier accordingly
--
-- 5. Backup:
--    - Enable automated backups in Cloud SQL
--    - Set backup window during low-traffic periods
--    - Test restore procedures regularly
--
-- ============================================================================
-- CLOUD SQL SPECIFIC COMMANDS:
-- ============================================================================
--
-- To run this script on Cloud SQL, you have several options:
--
-- Option 1: Using Cloud SQL Studio (Web Interface)
--   1. Go to Cloud SQL instance in Google Cloud Console
--   2. Click "Cloud SQL Studio" button
--   3. Copy and paste this script
--   4. Execute line by line or in sections
--
-- Option 2: Using gcloud and psql
--   gcloud sql connect INSTANCE_NAME --user=postgres --database=postgres
--   \i /path/to/cloudrun-postgres-init.sql
--
-- Option 3: Using Cloud SQL Proxy
--   ./cloud-sql-proxy PROJECT:REGION:INSTANCE &
--   psql "host=127.0.0.1 port=5432 user=postgres dbname=postgres"
--   \i cloudrun-postgres-init.sql
--
-- ============================================================================
