-- LightRAG Staging Database Initialization Script
-- This script sets up the STAGING database, user, and required extensions.
-- It mirrors the production setup but uses distinct names to ensure isolation.

-- ============================================================================
-- STEP 1: Create Staging Database and User
-- ============================================================================

-- Create the staging database
CREATE DATABASE lightrag_staging
    WITH 
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;

-- Create the staging user
-- IMPORTANT: Replace 'YOUR_STAGING_PASSWORD_HERE' with a unique secure password
CREATE USER lightrag_staging_user WITH PASSWORD 'YOUR_STAGING_PASSWORD_HERE';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE lightrag_staging TO lightrag_staging_user;

-- ============================================================================
-- STEP 2: Enable Extensions (Connect to staging database first)
-- ============================================================================

-- Connect to the staging database
\c lightrag_staging

-- Enable pgvector extension (REQUIRED for vector storage)
CREATE EXTENSION IF NOT EXISTS vector;

-- Optional extensions matching production
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO lightrag_staging_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lightrag_staging_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lightrag_staging_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO lightrag_staging_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO lightrag_staging_user;

-- ============================================================================
-- STEP 3: Verify
-- ============================================================================

-- Verify current database is staging
SELECT current_database();

-- Verify pgvector
SELECT * FROM pg_extension WHERE extname = 'vector';
