# Fix API Key Secret (Remove Newline)

$API_KEY = "bEFB-HgLYbKABMA9_gbBVJzaFwTp-e_SkT8e0iy-1-0"
$SECRET_NAME = "lightrag-api-key"
$SERVICE_NAME = "lightrag"
$REGION = "northamerica-northeast2"
$TEMP_FILE = "temp_key_clean.txt"

Write-Host "Fixing Secret (Removing Trailing Newline)..." -ForegroundColor Cyan

# 1. Write key to file with NO newline
# System.IO.File::WriteAllText does not add a newline
[System.IO.File]::WriteAllText($TEMP_FILE, $API_KEY)

# 2. Upload new version
Write-Host "Uploading clean version to Secret Manager..."
try {
    gcloud secrets versions add $SECRET_NAME --data-file=$TEMP_FILE
    Write-Host "Secret updated successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to update secret: $_" -ForegroundColor Red
    Remove-Item $TEMP_FILE
    exit 1
}

# 3. Cleanup
Remove-Item $TEMP_FILE

# 4. Redeploy Cloud Run to pick up new secret version
Write-Host "Refreshing Cloud Run service..."
gcloud run services update $SERVICE_NAME `
    --update-secrets LIGHTRAG_API_KEY=${SECRET_NAME}:latest `
    --region=$REGION

Write-Host "✅ Fix Complete. Please ask the developer to try again." -ForegroundColor Green
