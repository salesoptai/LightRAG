# PowerShell script to delete affiliate workspace using Cloud SQL Proxy
# This script will:
# 1. Start Cloud SQL Proxy
# 2. Execute SQL deletion script
# 3. Clean up

Write-Host "Starting Cloud SQL Proxy..." -ForegroundColor Cyan

# Start Cloud SQL Proxy in background
$proxyProcess = Start-Process -FilePath ".\cloud-sql-proxy.exe" `
    -ArgumentList "gen-lang-client-0743417261:northamerica-northeast2:lightrag-postgres" `
    -WindowStyle Hidden `
    -PassThru

# Wait for proxy to be ready
Write-Host "Waiting for proxy to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

try {
    Write-Host "Executing SQL deletion script..." -ForegroundColor Cyan
    
    # Set PostgreSQL password environment variable
    $env:PGPASSWORD = Read-Host "Enter PostgreSQL password for lightrag_user" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($env:PGPASSWORD)
    $env:PGPASSWORD = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    # Execute SQL script via psql (if available) or provide manual instructions
    if (Get-Command psql -ErrorAction SilentlyContinue) {
        psql -h 127.0.0.1 -p 5432 -U lightrag_user -d lightrag -f delete_affiliate_workspace.sql
        Write-Host "Workspace deletion completed!" -ForegroundColor Green
    } else {
        Write-Host "`npsql not found. Please install PostgreSQL client tools, or run these commands manually:" -ForegroundColor Yellow
        Write-Host "psql -h 127.0.0.1 -p 5432 -U lightrag_user -d lightrag -f delete_affiliate_workspace.sql" -ForegroundColor White
    }
    
} finally {
    # Stop Cloud SQL Proxy
    Write-Host "`nStopping Cloud SQL Proxy..." -ForegroundColor Cyan
    Stop-Process -Id $proxyProcess.Id -Force
    Write-Host "Done!" -ForegroundColor Green
}
