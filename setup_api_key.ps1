# LightRAG API Key Setup Script

# 1. Configuration
$API_KEY = "bEFB-HgLYbKABMA9_gbBVJzaFwTp-e_SkT8e0iy-1-0"
$SECRET_NAME = "lightrag-api-key"
$SERVICE_NAME = "lightrag"
$REGION = "northamerica-northeast2"

Write-Host "Setting up LightRAG API Key..." -ForegroundColor Cyan
Write-Host "Generated Key: $API_KEY" -ForegroundColor Yellow

# 2. Check for gcloud authentication
Write-Host "`nChecking gcloud authentication..."
try {
    gcloud auth print-access-token | Out-Null
} catch {
    Write-Host "Error: You are not logged in to gcloud. Please run 'gcloud auth login' first." -ForegroundColor Red
    exit 1
}

# 3. Create the secret
Write-Host "`nCreating Secret '$SECRET_NAME'..."
try {
    $process = echo $API_KEY | gcloud secrets create $SECRET_NAME --data-file=- --replication-policy=automatic 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($process -match "already exists") {
            Write-Host "Secret already exists. Updating version..." -ForegroundColor Yellow
            echo $API_KEY | gcloud secrets versions add $SECRET_NAME --data-file=-
        } else {
            throw $process
        }
    } else {
        Write-Host "Secret created successfully." -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to create secret: $_" -ForegroundColor Red
    exit 1
}

# 4. Get Project Number (needed for service account)
$PROJECT_ID = gcloud config get-value project
$PROJECT_NUMBER = gcloud projects describe $PROJECT_ID --format="value(projectNumber)"
$SERVICE_ACCOUNT = "$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

# 5. Grant Access
Write-Host "`nGranting access to service account: $SERVICE_ACCOUNT..."
gcloud secrets add-iam-policy-binding $SECRET_NAME `
    --member="serviceAccount:$SERVICE_ACCOUNT" `
    --role="roles/secretmanager.secretAccessor"

# 6. Update Cloud Run Service
Write-Host "`nUpdating Cloud Run service '$SERVICE_NAME'..."
gcloud run services update $SERVICE_NAME `
    --update-secrets LIGHTRAG_API_KEY=${SECRET_NAME}:latest `
    --region=$REGION

Write-Host "`n✅ Setup Complete!" -ForegroundColor Green
Write-Host "Use this key in your agent headers:"
Write-Host "X-API-Key: $API_KEY" -ForegroundColor Cyan
