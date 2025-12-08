# LightRAG Cloud Run Deployment Guide with PostgreSQL

This guide will help you deploy LightRAG to Google Cloud Run with Cloud SQL PostgreSQL for persistent storage, eliminating the data loss issue caused by Cloud Run's ephemeral containers.

## 📋 Prerequisites

- Google Cloud Project with billing enabled
- `gcloud` CLI installed and authenticated
- Docker installed locally (for testing)
- Basic knowledge of Google Cloud Console

## 🎯 Problem Overview

**Issue**: Cloud Run containers are ephemeral (stateless). The default file-based storage is wiped when containers restart, scale down, or redeploy.

**Solution**: Configure LightRAG to use Cloud SQL PostgreSQL as a persistent storage backend.

---

## 🚀 Deployment Steps

### Step 1: Set Up Cloud SQL PostgreSQL Instance

#### 1.1 Create Cloud SQL Instance

```bash
# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export INSTANCE_NAME="lightrag-postgres"

# Create Cloud SQL PostgreSQL instance
gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region=$REGION \
    --network=default \
    --no-assign-ip \
    --enable-google-private-ip \
    --project=$PROJECT_ID
```

**Instance Tier Options**:
- `db-f1-micro`: ~$7/month (shared CPU, 0.6GB RAM) - Good for testing
- `db-g1-small`: ~$25/month (shared CPU, 1.7GB RAM) - Small production
- `db-custom-2-4096`: ~$80/month (2 vCPU, 4GB RAM) - Production workload

#### 1.2 Enable pgvector Extension

```bash
# Enable pgvector extension (REQUIRED for vector storage)
gcloud sql instances patch $INSTANCE_NAME \
    --database-flags=cloudsql.enable_pgvector=on \
    --project=$PROJECT_ID
```

**Note**: The instance will restart to apply this change (~2-3 minutes).

#### 1.3 Get Connection Information

```bash
# Get the connection name (format: PROJECT_ID:REGION:INSTANCE_NAME)
gcloud sql instances describe $INSTANCE_NAME \
    --format="value(connectionName)" \
    --project=$PROJECT_ID

# Get the private IP address
gcloud sql instances describe $INSTANCE_NAME \
    --format="value(ipAddresses[0].ipAddress)" \
    --project=$PROJECT_ID
```

**Save these values** - you'll need them for configuration.

---

### Step 2: Initialize the Database

#### 2.1 Connect to Cloud SQL

```bash
# Option A: Using Cloud SQL Proxy (recommended for local setup)
# Download proxy: https://cloud.google.com/sql/docs/postgres/connect-admin-proxy
./cloud-sql-proxy ${PROJECT_ID}:${REGION}:${INSTANCE_NAME} &

# Connect with psql
psql "host=127.0.0.1 port=5432 user=postgres dbname=postgres"
```

```bash
# Option B: Using gcloud (simpler, but requires gcloud auth)
gcloud sql connect $INSTANCE_NAME --user=postgres --project=$PROJECT_ID
```

#### 2.2 Run Initialization Script

Once connected to PostgreSQL, run the initialization script:

```sql
-- Create database
CREATE DATABASE lightrag
    WITH 
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;

-- Create user with a STRONG password
CREATE USER lightrag_user WITH PASSWORD 'YOUR_VERY_SECURE_PASSWORD_HERE';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE lightrag TO lightrag_user;

-- Connect to lightrag database
\c lightrag

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO lightrag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO lightrag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO lightrag_user;

-- Verify pgvector installation
SELECT * FROM pg_extension WHERE extname = 'vector';
```

**✅ Verification**: You should see the pgvector extension listed.

---

### Step 3: Store Secrets in Google Secret Manager

**Best Practice**: Never hardcode passwords in environment variables or code.

```bash
# Create secret for PostgreSQL password
echo -n "YOUR_VERY_SECURE_PASSWORD_HERE" | \
gcloud secrets create lightrag-postgres-password \
    --data-file=- \
    --replication-policy=automatic \
    --project=$PROJECT_ID

# Create secret for API key
echo -n "your-openai-api-key" | \
gcloud secrets create lightrag-openai-api-key \
    --data-file=- \
    --replication-policy=automatic \
    --project=$PROJECT_ID

# Create secret for embedding API key (if different)
echo -n "your-embedding-api-key" | \
gcloud secrets create lightrag-embedding-api-key \
    --data-file=- \
    --replication-policy=automatic \
    --project=$PROJECT_ID
```

---

### Step 4: Configure Environment Variables

Create a `.env.cloudrun` file based on `.env.cloudrun.postgres`:

```bash
# Copy the template
cp .env.cloudrun.postgres .env.cloudrun

# Edit with your actual values
nano .env.cloudrun  # or use your preferred editor
```

**Critical values to update**:
```env
# PostgreSQL Configuration
POSTGRES_HOST=10.x.x.x  # Your Cloud SQL private IP
POSTGRES_PASSWORD=YOUR_VERY_SECURE_PASSWORD_HERE
POSTGRES_USER=lightrag_user
POSTGRES_DATABASE=lightrag

# LLM Configuration
LLM_BINDING_API_KEY=your-openai-api-key
EMBEDDING_BINDING_API_KEY=your-openai-api-key

# Security
TOKEN_SECRET=generate-a-random-secret-key-here
LIGHTRAG_API_KEY=generate-another-random-api-key
```

**Generate secure random keys**:
```bash
# On Linux/Mac
openssl rand -base64 32

# On Windows PowerShell
[Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }))
```

---

### Step 5: Build and Push Docker Image

#### 5.1 Enable Required APIs

```bash
# Enable Cloud Build and Artifact Registry
gcloud services enable cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    --project=$PROJECT_ID
```

#### 5.2 Create Artifact Registry Repository

```bash
# Create repository for Docker images
gcloud artifacts repositories create lightrag-repo \
    --repository-format=docker \
    --location=$REGION \
    --description="LightRAG Docker images" \
    --project=$PROJECT_ID

# Configure Docker to authenticate with Artifact Registry
gcloud auth configure-docker ${REGION}-docker.pkg.dev --project=$PROJECT_ID
```

#### 5.3 Build and Push Image

```bash
# Build the image
docker build -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/lightrag-repo/lightrag:latest .

# Push to Artifact Registry
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/lightrag-repo/lightrag:latest
```

**Alternative**: Use Cloud Build (builds in Google Cloud, no local Docker needed):
```bash
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/lightrag-repo/lightrag:latest \
    --project=$PROJECT_ID
```

---

### Step 6: Deploy to Cloud Run

#### 6.1 Create Cloud Run Service

```bash
# Get your Cloud SQL connection name
export SQL_CONNECTION_NAME=$(gcloud sql instances describe $INSTANCE_NAME \
    --format="value(connectionName)" --project=$PROJECT_ID)

# Get the private IP
export SQL_PRIVATE_IP=$(gcloud sql instances describe $INSTANCE_NAME \
    --format="value(ipAddresses[0].ipAddress)" --project=$PROJECT_ID)

# Deploy Cloud Run service
gcloud run deploy lightrag \
    --image=${REGION}-docker.pkg.dev/${PROJECT_ID}/lightrag-repo/lightrag:latest \
    --region=$REGION \
    --platform=managed \
    --allow-unauthenticated \
    --port=9621 \
    --memory=2Gi \
    --cpu=2 \
    --timeout=300 \
    --max-instances=10 \
    --min-instances=0 \
    --add-cloudsql-instances=$SQL_CONNECTION_NAME \
    --set-env-vars="LIGHTRAG_KV_STORAGE=PGKVStorage,\
LIGHTRAG_DOC_STATUS_STORAGE=PGDocStatusStorage,\
LIGHTRAG_GRAPH_STORAGE=PGGraphStorage,\
LIGHTRAG_VECTOR_STORAGE=PGVectorStorage,\
POSTGRES_HOST=$SQL_PRIVATE_IP,\
POSTGRES_PORT=5432,\
POSTGRES_USER=lightrag_user,\
POSTGRES_DATABASE=lightrag,\
POSTGRES_MAX_CONNECTIONS=12,\
POSTGRES_VECTOR_INDEX_TYPE=HNSW,\
POSTGRES_CONNECTION_RETRIES=5,\
WORKSPACE=production,\
LLM_BINDING=openai,\
LLM_MODEL=gpt-4o-mini,\
LLM_BINDING_HOST=https://api.openai.com/v1,\
EMBEDDING_BINDING=openai,\
EMBEDDING_MODEL=text-embedding-3-large,\
EMBEDDING_DIM=3072,\
EMBEDDING_BINDING_HOST=https://api.openai.com/v1" \
    --set-secrets="POSTGRES_PASSWORD=lightrag-postgres-password:latest,\
LLM_BINDING_API_KEY=lightrag-openai-api-key:latest,\
EMBEDDING_BINDING_API_KEY=lightrag-openai-api-key:latest" \
    --project=$PROJECT_ID
```

#### 6.2 Grant Secret Access to Cloud Run Service

```bash
# Get Cloud Run service account
export SERVICE_ACCOUNT=$(gcloud run services describe lightrag \
    --region=$REGION \
    --format="value(spec.template.spec.serviceAccountName)" \
    --project=$PROJECT_ID)

# If no custom service account, get the default one
if [ -z "$SERVICE_ACCOUNT" ]; then
    export SERVICE_ACCOUNT="${PROJECT_ID}-compute@developer.gserviceaccount.com"
fi

# Grant access to secrets
gcloud secrets add-iam-policy-binding lightrag-postgres-password \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor" \
    --project=$PROJECT_ID

gcloud secrets add-iam-policy-binding lightrag-openai-api-key \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor" \
    --project=$PROJECT_ID
```

---

### Step 7: Verify Deployment

#### 7.1 Get Cloud Run URL

```bash
export CLOUD_RUN_URL=$(gcloud run services describe lightrag \
    --region=$REGION \
    --format="value(status.url)" \
    --project=$PROJECT_ID)

echo "LightRAG is deployed at: $CLOUD_RUN_URL"
```

#### 7.2 Test the Deployment

```bash
# Test health endpoint
curl ${CLOUD_RUN_URL}/health

# Expected response: {"status": "healthy"}
```

#### 7.3 Access Web UI

Open your browser to: `${CLOUD_RUN_URL}`

You should see the LightRAG web interface.

#### 7.4 Verify PostgreSQL Connection

```bash
# Check Cloud Run logs for database connection
gcloud run services logs read lightrag \
    --region=$REGION \
    --limit=50 \
    --project=$PROJECT_ID | grep -i postgres
```

Look for messages like:
- `Connected to PostgreSQL`
- `Initialized PGKVStorage`
- `Initialized PGGraphStorage`
- `Initialized PGVectorStorage`

---

## 🧪 Testing Data Persistence

### Test 1: Upload a Document

1. Go to your Cloud Run URL in a browser
2. Upload a test document (e.g., a small text file)
3. Wait for processing to complete

### Test 2: Verify in Database

```bash
# Connect to database
gcloud sql connect $INSTANCE_NAME --user=lightrag_user --database=lightrag --project=$PROJECT_ID

# Check tables were created
\dt

# Count documents
SELECT COUNT(*) FROM production_documents;

# Sample entities
SELECT id, entity_name FROM production_entities LIMIT 5;
```

### Test 3: Restart Cloud Run Service

```bash
# Force restart by deploying again
gcloud run services update lightrag \
    --region=$REGION \
    --update-env-vars="RESTART=$(date +%s)" \
    --project=$PROJECT_ID
```

### Test 4: Verify Data Still Exists

1. Refresh the web UI
2. Your uploaded documents should still be there
3. Try querying the data - it should work!

**✅ SUCCESS**: If data persists after restart, your persistent storage is working correctly!

---

## 🔧 Troubleshooting

### Issue: "Connection refused" to PostgreSQL

**Solution**: Check VPC connector and Cloud SQL connection:
```bash
# Verify Cloud SQL connection is attached
gcloud run services describe lightrag \
    --region=$REGION \
    --format="value(spec.template.metadata.annotations['run.googleapis.com/cloudsql-instances'])" \
    --project=$PROJECT_ID
```

### Issue: "pgvector extension not found"

**Solution**: Enable pgvector extension:
```bash
gcloud sql instances patch $INSTANCE_NAME \
    --database-flags=cloudsql.enable_pgvector=on \
    --project=$PROJECT_ID
```

### Issue: "Permission denied" for secrets

**Solution**: Grant Secret Manager access:
```bash
gcloud secrets add-iam-policy-binding SECRET_NAME \
    --member="serviceAccount:YOUR_SERVICE_ACCOUNT" \
    --role="roles/secretmanager.secretAccessor" \
    --project=$PROJECT_ID
```

### Issue: Cloud Run timeout during document processing

**Solution**: Increase timeout and memory:
```bash
gcloud run services update lightrag \
    --timeout=600 \
    --memory=4Gi \
    --region=$REGION \
    --project=$PROJECT_ID
```

### Issue: High database connections

**Solution**: Adjust connection pool size:
```bash
gcloud run services update lightrag \
    --update-env-vars="POSTGRES_MAX_CONNECTIONS=8" \
    --region=$REGION \
    --project=$PROJECT_ID
```

---

## 💰 Cost Estimation

**Monthly costs for small production deployment**:

- **Cloud SQL** (db-f1-micro): ~$7/month
- **Cloud Run**: ~$5-20/month (depends on usage, scales to zero when idle)
- **Cloud SQL backup storage**: ~$2-5/month (automatic backups)
- **Network egress**: Usually negligible for internal traffic

**Total**: ~$15-35/month for a small deployment

**For larger deployments**:
- Cloud SQL (db-custom-2-4096): ~$80/month
- Cloud Run with min-instances=1: ~$20-50/month
- Total: ~$100-150/month

---

## 🔒 Security Best Practices

1. **Use Secret Manager**: Never hardcode passwords
2. **Enable SSL**: Set `POSTGRES_SSL_MODE=require`
3. **Private IP only**: No public IP for Cloud SQL
4. **IAM authentication**: Consider using Cloud SQL IAM authentication
5. **Regular backups**: Enable automated backups in Cloud SQL
6. **Monitor access**: Set up Cloud Logging alerts
7. **Update regularly**: Keep LightRAG and PostgreSQL updated

---

## 📊 Monitoring and Maintenance

### Set Up Monitoring

```bash
# View Cloud Run metrics
gcloud run services describe lightrag \
    --region=$REGION \
    --project=$PROJECT_ID

# View Cloud SQL metrics
gcloud sql operations list \
    --instance=$INSTANCE_NAME \
    --project=$PROJECT_ID
```

### Enable Alerts

1. Go to Google Cloud Console → Monitoring
2. Create alert policies for:
   - Cloud Run high error rate
   - Cloud SQL high CPU usage
   - Cloud SQL high connection count
   - High memory usage

### Regular Maintenance

- **Weekly**: Review logs for errors
- **Monthly**: Check database size and optimize indexes
- **Quarterly**: Review and optimize costs
- **Yearly**: Test backup restoration

---

## 🎉 Success!

You now have a fully persistent LightRAG deployment on Cloud Run with PostgreSQL!

Your data will survive:
- ✅ Container restarts
- ✅ Service redeployments
- ✅ Scale-to-zero events
- ✅ Cloud Run updates

**Next Steps**:
1. Upload your documents
2. Build your knowledge graph
3. Query your data with confidence
4. Scale as needed!

---

## 📚 Additional Resources

- [LightRAG Documentation](https://github.com/HKUDS/LightRAG)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud SQL PostgreSQL](https://cloud.google.com/sql/docs/postgres)
- [pgvector Extension](https://github.com/pgvector/pgvector)
