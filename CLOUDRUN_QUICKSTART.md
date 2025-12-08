# LightRAG Cloud Run + PostgreSQL Quick Start

## 🎯 Problem Solved

**Your Issue**: Data was disappearing after Cloud Run container restarts because the default file-based storage is ephemeral.

**The Solution**: Configure LightRAG to use Cloud SQL PostgreSQL for persistent storage.

---

## 📁 Files Created for You

This quick start guide references the following files that have been created:

1. **`.env.cloudrun.postgres`** - Production environment configuration template
2. **`cloudrun-postgres-init.sql`** - Database initialization script
3. **`CLOUDRUN_DEPLOYMENT_GUIDE.md`** - Complete step-by-step deployment guide
4. **`CLOUDRUN_VERIFICATION_CHECKLIST.md`** - Testing and verification checklist

---

## 🚀 Quick Setup (15 minutes)

### Step 1: Set Up Cloud SQL (5 minutes)

```bash
# Set your variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export INSTANCE_NAME="lightrag-postgres"

# Create Cloud SQL instance
gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region=$REGION \
    --enable-google-private-ip \
    --no-assign-ip \
    --project=$PROJECT_ID

# Enable pgvector extension (REQUIRED)
gcloud sql instances patch $INSTANCE_NAME \
    --database-flags=cloudsql.enable_pgvector=on \
    --project=$PROJECT_ID
```

### Step 2: Initialize Database (3 minutes)

```bash
# Connect to Cloud SQL
gcloud sql connect $INSTANCE_NAME --user=postgres --project=$PROJECT_ID

# Run the initialization script from cloudrun-postgres-init.sql
# Or copy/paste these commands:
```

```sql
CREATE DATABASE lightrag;
CREATE USER lightrag_user WITH PASSWORD 'YOUR_SECURE_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE lightrag TO lightrag_user;

\c lightrag

CREATE EXTENSION IF NOT EXISTS vector;
GRANT ALL ON SCHEMA public TO lightrag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO lightrag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO lightrag_user;
```

### Step 3: Store Secrets (2 minutes)

```bash
# Store PostgreSQL password
echo -n "YOUR_SECURE_PASSWORD" | \
gcloud secrets create lightrag-postgres-password \
    --data-file=- \
    --replication-policy=automatic \
    --project=$PROJECT_ID

# Store API keys
echo -n "your-openai-api-key" | \
gcloud secrets create lightrag-openai-api-key \
    --data-file=- \
    --replication-policy=automatic \
    --project=$PROJECT_ID
```

### Step 4: Deploy to Cloud Run (5 minutes)

```bash
# Get Cloud SQL info
export SQL_CONNECTION_NAME=$(gcloud sql instances describe $INSTANCE_NAME \
    --format="value(connectionName)" --project=$PROJECT_ID)

export SQL_PRIVATE_IP=$(gcloud sql instances describe $INSTANCE_NAME \
    --format="value(ipAddresses[0].ipAddress)" --project=$PROJECT_ID)

# Build and deploy (or use pre-built image)
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/lightrag-repo/lightrag:latest

# Deploy to Cloud Run with PostgreSQL storage
gcloud run deploy lightrag \
    --image=${REGION}-docker.pkg.dev/${PROJECT_ID}/lightrag-repo/lightrag:latest \
    --region=$REGION \
    --allow-unauthenticated \
    --port=9621 \
    --memory=2Gi \
    --cpu=2 \
    --timeout=300 \
    --add-cloudsql-instances=$SQL_CONNECTION_NAME \
    --set-env-vars="LIGHTRAG_KV_STORAGE=PGKVStorage,\
LIGHTRAG_DOC_STATUS_STORAGE=PGDocStatusStorage,\
LIGHTRAG_GRAPH_STORAGE=PGGraphStorage,\
LIGHTRAG_VECTOR_STORAGE=PGVectorStorage,\
POSTGRES_HOST=$SQL_PRIVATE_IP,\
POSTGRES_PORT=5432,\
POSTGRES_USER=lightrag_user,\
POSTGRES_DATABASE=lightrag,\
WORKSPACE=production" \
    --set-secrets="POSTGRES_PASSWORD=lightrag-postgres-password:latest,\
LLM_BINDING_API_KEY=lightrag-openai-api-key:latest,\
EMBEDDING_BINDING_API_KEY=lightrag-openai-api-key:latest" \
    --project=$PROJECT_ID
```

---

## ✅ Verify It Works

### Test Data Persistence

```bash
# 1. Get your Cloud Run URL
export CLOUD_RUN_URL=$(gcloud run services describe lightrag \
    --region=$REGION \
    --format="value(status.url)" \
    --project=$PROJECT_ID)

echo "Your LightRAG URL: $CLOUD_RUN_URL"

# 2. Open in browser and upload a document

# 3. Restart the service
gcloud run services update lightrag \
    --region=$REGION \
    --update-env-vars="RESTART=$(date +%s)" \
    --project=$PROJECT_ID

# 4. Refresh browser - your data should still be there!
```

**✅ SUCCESS**: If your uploaded documents persist after restart, you're done!

---

## 📚 Need More Details?

For complete instructions, see:

- **`CLOUDRUN_DEPLOYMENT_GUIDE.md`** - Full deployment guide with all options
- **`CLOUDRUN_VERIFICATION_CHECKLIST.md`** - Complete testing checklist
- **`.env.cloudrun.postgres`** - All configuration options explained

---

## 🔑 Key Configuration Changes

The critical environment variables that fix the data loss issue:

```env
# OLD (file-based, ephemeral):
LIGHTRAG_KV_STORAGE=JsonKVStorage
LIGHTRAG_DOC_STATUS_STORAGE=JsonDocStatusStorage
LIGHTRAG_GRAPH_STORAGE=NetworkXStorage
LIGHTRAG_VECTOR_STORAGE=NanoVectorDBStorage

# NEW (PostgreSQL, persistent):
LIGHTRAG_KV_STORAGE=PGKVStorage
LIGHTRAG_DOC_STATUS_STORAGE=PGDocStatusStorage
LIGHTRAG_GRAPH_STORAGE=PGGraphStorage
LIGHTRAG_VECTOR_STORAGE=PGVectorStorage
```

Plus PostgreSQL connection settings:
```env
POSTGRES_HOST=<Cloud_SQL_Private_IP>
POSTGRES_PORT=5432
POSTGRES_USER=lightrag_user
POSTGRES_PASSWORD=<from_secret_manager>
POSTGRES_DATABASE=lightrag
```

---

## 💰 Cost Estimate

**Small production deployment**:
- Cloud SQL (db-f1-micro): ~$7/month
- Cloud Run (scales to zero): ~$5-20/month
- **Total**: ~$15-30/month

**Your data is safe and costs are minimal!**

---

## 🆘 Common Issues

### "Connection refused" to PostgreSQL
- Check Cloud SQL connection is attached: `--add-cloudsql-instances`
- Verify private IP connectivity

### "pgvector extension not found"
```bash
gcloud sql instances patch $INSTANCE_NAME \
    --database-flags=cloudsql.enable_pgvector=on \
    --project=$PROJECT_ID
```

### "Permission denied" for secrets
```bash
# Grant access to service account
gcloud secrets add-iam-policy-binding lightrag-postgres-password \
    --member="serviceAccount:YOUR-SERVICE-ACCOUNT" \
    --role="roles/secretmanager.secretAccessor" \
    --project=$PROJECT_ID
```

---

## 🎉 What You Get

With this setup, your LightRAG deployment now has:

✅ **Persistent storage** - Data survives container restarts  
✅ **Production ready** - PostgreSQL is battle-tested  
✅ **Scalable** - Cloud Run scales automatically  
✅ **Cost effective** - Scales to zero when idle  
✅ **Secure** - Private networking, secret management  
✅ **Reliable** - Automatic backups, high availability  

**No more data loss!** 🚀
