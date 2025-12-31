# LightRAG Staging & Production CI/CD Setup Guide

This guide details how to set up the automated CI/CD pipeline using Google Cloud Build.
This setup enables the following flow:
1.  Push to `staging` branch → Deploys to `lightrag-staging` service.
2.  Push to `main` branch → Deploys to `lightrag` (production) service.

## Configuration Details
*   **Project ID**: `gen-lang-client-0743417261`
*   **Region**: `northamerica-northeast2`
*   **Repository**: `cloud-run-source-deploy`
*   **Staging Database**: `lightrag_staging`
*   **Production Database**: `lightrag`

---

## Phase 1: Database Setup

### 1. Download Cloud SQL Proxy
If you haven't downloaded the proxy yet, run this command:

*PowerShell:*
```powershell
curl -o cloud-sql-proxy.exe https://dl.google.com/cloudsql/cloud_sql_proxy_x64.exe
```

*Bash:*
```bash
curl -o cloud-sql-proxy.exe https://dl.google.com/cloudsql/cloud_sql_proxy_x64.exe
```

### 2. Initialize Staging Database
Run the `staging-db-init.sql` script against your existing Cloud SQL instance.

**Option A: Using Cloud SQL Proxy (Recommended)**

*Bash (Open a separate terminal for the proxy):*
```bash
./cloud-sql-proxy.exe -instances=gen-lang-client-0743417261:northamerica-northeast2:lightrag-postgres=tcp:5432
```

*PowerShell (Open a separate terminal for the proxy):*
```powershell
.\cloud-sql-proxy.exe -instances=gen-lang-client-0743417261:northamerica-northeast2:lightrag-postgres=tcp:5432
```

**Wait for the message: "Ready for new connections"**

Then, in your original terminal, run:

*Bash/PowerShell:*
```bash
psql "host=127.0.0.1 port=5432 user=postgres dbname=postgres" -f staging-db-init.sql
```

**Option B: Using gcloud**
```bash
gcloud sql connect lightrag-postgres --user=postgres --project=gen-lang-client-0743417261
# Then copy-paste the content of staging-db-init.sql
```

### 2. Create Staging Secret
Store the staging database password in Secret Manager.

*Bash:*
```bash
echo -n "YOUR_STAGING_PASSWORD_HERE" | \
gcloud secrets create lightrag-staging-postgres-password \
    --data-file=- \
    --replication-policy=automatic \
    --project=gen-lang-client-0743417261
```

*PowerShell:*
```powershell
echo "YOUR_STAGING_PASSWORD_HERE" | gcloud secrets create lightrag-staging-postgres-password --data-file=- --replication-policy=automatic --project=gen-lang-client-0743417261
```

---

## Phase 2: Create Staging Cloud Run Service

We need to create the service once so Cloud Build has a target to deploy to.

*Bash:*
```bash
export SQL_CONNECTION_NAME="gen-lang-client-0743417261:northamerica-northeast2:lightrag-postgres"

gcloud run deploy lightrag-staging \
    --image=northamerica-northeast2-docker.pkg.dev/gen-lang-client-0743417261/cloud-run-source-deploy/lightrag/lightrag:latest \
    --region=northamerica-northeast2 \
    --platform=managed \
    --allow-unauthenticated \
    --port=9621 \
    --memory=2Gi \
    --cpu=2 \
    --timeout=300 \
    --add-cloudsql-instances=$SQL_CONNECTION_NAME \
    --set-env-vars="POSTGRES_DATABASE=lightrag_staging,\
POSTGRES_USER=lightrag_staging_user,\
WORKSPACE=staging,\
LIGHTRAG_KV_STORAGE=PGKVStorage,\
LIGHTRAG_DOC_STATUS_STORAGE=PGDocStatusStorage,\
LIGHTRAG_GRAPH_STORAGE=PGGraphStorage,\
LIGHTRAG_VECTOR_STORAGE=PGVectorStorage" \
    --set-secrets="POSTGRES_PASSWORD=lightrag-staging-postgres-password:latest,\
LLM_BINDING_API_KEY=lightrag-openai-api-key:latest,\
EMBEDDING_BINDING_API_KEY=lightrag-openai-api-key:latest" \
    --project=gen-lang-client-0743417261
```

*PowerShell:*
```powershell
$env:SQL_CONNECTION_NAME="gen-lang-client-0743417261:northamerica-northeast2:lightrag-postgres"

gcloud run deploy lightrag-staging `
    --image=northamerica-northeast2-docker.pkg.dev/gen-lang-client-0743417261/cloud-run-source-deploy/lightrag/lightrag:latest `
    --region=northamerica-northeast2 `
    --platform=managed `
    --allow-unauthenticated `
    --port=9621 `
    --memory=2Gi `
    --cpu=2 `
    --timeout=300 `
    --add-cloudsql-instances=$env:SQL_CONNECTION_NAME `
    --set-env-vars="POSTGRES_DATABASE=lightrag_staging,POSTGRES_USER=lightrag_staging_user,WORKSPACE=staging,LIGHTRAG_KV_STORAGE=PGKVStorage,LIGHTRAG_DOC_STATUS_STORAGE=PGDocStatusStorage,LIGHTRAG_GRAPH_STORAGE=PGGraphStorage,LIGHTRAG_VECTOR_STORAGE=PGVectorStorage" `
    --set-secrets="POSTGRES_PASSWORD=lightrag-staging-postgres-password:latest,LLM_BINDING_API_KEY=lightrag-openai-api-key:latest,EMBEDDING_BINDING_API_KEY=lightrag-openai-api-key:latest" `
    --project=gen-lang-client-0743417261
```

**Note**: We are reusing the OpenAI keys from production. If you want separate keys for staging, create new secrets and update the `--set-secrets` flag above.

---

## Phase 3: Configure Cloud Build Triggers

We will create two triggers: one for Staging and one for Production.

### Trigger 1: Staging (Branch: `staging`)

*Bash:*
```bash
gcloud builds triggers create github \
    --name="lightrag-staging-deploy" \
    --repo-owner="salesoptai" \
    --repo-name="LightRAG" \
    --branch-pattern="^staging$" \
    --build-config="cloudbuild.yaml" \
    --substitutions="_SERVICE_NAME=lightrag-staging,_DB_NAME=lightrag_staging" \
    --region=northamerica-northeast2 \
    --project=gen-lang-client-0743417261
```

*PowerShell:*
```powershell
gcloud builds triggers create github `
    --name="lightrag-staging-deploy" `
    --repo-owner="salesoptai" `
    --repo-name="LightRAG" `
    --branch-pattern="^staging$" `
    --build-config="cloudbuild.yaml" `
    --substitutions="_SERVICE_NAME=lightrag-staging,_DB_NAME=lightrag_staging" `
    --region=northamerica-northeast2 `
    --project=gen-lang-client-0743417261
```

### Trigger 2: Production (Branch: `main`)

*Bash:*
```bash
gcloud builds triggers create github \
    --name="lightrag-prod-deploy" \
    --repo-owner="salesoptai" \
    --repo-name="LightRAG" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml" \
    --substitutions="_SERVICE_NAME=lightrag,_DB_NAME=lightrag" \
    --region=northamerica-northeast2 \
    --project=gen-lang-client-0743417261
```

*PowerShell:*
```powershell
gcloud builds triggers create github `
    --name="lightrag-prod-deploy" `
    --repo-owner="salesoptai" `
    --repo-name="LightRAG" `
    --branch-pattern="^main$" `
    --build-config="cloudbuild.yaml" `
    --substitutions="_SERVICE_NAME=lightrag,_DB_NAME=lightrag" `
    --region=northamerica-northeast2 `
    --project=gen-lang-client-0743417261
```

**Important**: If you have not connected your GitHub repository to Cloud Build in this project yet, you must do so first in the Google Cloud Console (Cloud Build > Triggers > Connect Repository).

---

## Phase 4: Grant Permissions

Ensure the Cloud Build service account has permission to deploy to Cloud Run.

*Bash:*
```bash
# Get Cloud Build Service Account
PROJECT_NUMBER=$(gcloud projects describe gen-lang-client-0743417261 --format='value(projectNumber)')
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# Grant Run Admin
gcloud projects add-iam-policy-binding gen-lang-client-0743417261 \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/run.admin"

# Grant Service Account User (to act as the runtime service account)
gcloud projects add-iam-policy-binding gen-lang-client-0743417261 \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser"
```

*PowerShell:*
```powershell
# Get Cloud Build Service Account
$PROJECT_NUMBER = gcloud projects describe gen-lang-client-0743417261 --format='value(projectNumber)'
$CLOUD_BUILD_SA = "$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"

# Grant Run Admin
gcloud projects add-iam-policy-binding gen-lang-client-0743417261 `
    --member="serviceAccount:$CLOUD_BUILD_SA" `
    --role="roles/run.admin"

# Grant Service Account User
gcloud projects add-iam-policy-binding gen-lang-client-0743417261 `
    --member="serviceAccount:$CLOUD_BUILD_SA" `
    --role="roles/iam.serviceAccountUser"
```

## Verification

1.  **Push to Staging**:
    *   Create/checkout `staging` branch: `git checkout -b staging`
    *   Push: `git push origin staging`
    *   Check Cloud Build history to see the build start.
    *   Verify `lightrag-staging` service is updated.

2.  **Push to Production**:
    *   Merge staging to main.
    *   Push main.
    *   Verify `lightrag` service is updated.
