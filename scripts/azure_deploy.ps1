#!/usr/bin/env pwsh
<#
.SYNOPSIS
    One-shot Azure deployment script for Customer Intelligence Platform.
    Run this AFTER logging in with: az login

.USAGE
    .\scripts\azure_deploy.ps1 -GeminiApiKey "YOUR_GEMINI_API_KEY"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$GeminiApiKey,

    [string]$ResourceGroup  = "cip-rg",
    [string]$Location       = "eastus",
    [string]$AcrName        = "cipregistry",        # must be globally unique, lowercase
    [string]$AppName        = "cip-backend",         # must be globally unique
    [string]$StorageAccount = "cipstorageacct",      # must be globally unique, lowercase, 3-24 chars
    [string]$BlobContainer  = "cip-artifacts",
    [string]$AppServicePlan = "cip-plan",
    [string]$ImageTag       = "latest"
)

$ErrorActionPreference = "Stop"
$Image = "$AcrName.azurecr.io/cip-backend:$ImageTag"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CIP Azure Deployment Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── 1. Resource Group ─────────────────────────────────────────────────────────
Write-Host "[1/9] Creating Resource Group: $ResourceGroup..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location | Out-Null
Write-Host "      OK" -ForegroundColor Green

# ── 2. Azure Container Registry ───────────────────────────────────────────────
Write-Host "[2/9] Creating Container Registry: $AcrName..." -ForegroundColor Yellow
az acr create --resource-group $ResourceGroup --name $AcrName --sku Basic --admin-enabled true | Out-Null
Write-Host "      OK" -ForegroundColor Green

# ── 3. Storage Account + Blob Container ───────────────────────────────────────
Write-Host "[3/9] Creating Storage Account: $StorageAccount..." -ForegroundColor Yellow
az storage account create `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2 | Out-Null

$ConnectionString = az storage account show-connection-string `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --query connectionString -o tsv

az storage container create --name $BlobContainer --connection-string $ConnectionString | Out-Null
Write-Host "      OK" -ForegroundColor Green

# ── 4. Upload ML Artifacts ────────────────────────────────────────────────────
Write-Host "[4/9] Uploading ML artifacts to Blob Storage..." -ForegroundColor Yellow
$env:AZURE_STORAGE_CONNECTION_STRING = $ConnectionString
$env:AZURE_BLOB_CONTAINER = $BlobContainer
python scripts/upload_artifacts.py
Write-Host "      OK" -ForegroundColor Green

# ── 5. Build Docker Image ─────────────────────────────────────────────────────
Write-Host "[5/9] Building Docker image..." -ForegroundColor Yellow
docker build -t $Image .
Write-Host "      OK" -ForegroundColor Green

# ── 6. Push Image to ACR ──────────────────────────────────────────────────────
Write-Host "[6/9] Pushing image to ACR..." -ForegroundColor Yellow
az acr login --name $AcrName
docker push $Image
Write-Host "      OK" -ForegroundColor Green

# ── 7. App Service Plan ───────────────────────────────────────────────────────
Write-Host "[7/9] Creating App Service Plan (B1)..." -ForegroundColor Yellow
az appservice plan create `
    --name $AppServicePlan `
    --resource-group $ResourceGroup `
    --is-linux `
    --sku B1 | Out-Null
Write-Host "      OK" -ForegroundColor Green

# ── 8. Web App (Container) ────────────────────────────────────────────────────
Write-Host "[8/9] Creating Web App: $AppName..." -ForegroundColor Yellow
$AcrPassword = az acr credential show --name $AcrName --query "passwords[0].value" -o tsv

az webapp create `
    --resource-group $ResourceGroup `
    --plan $AppServicePlan `
    --name $AppName `
    --deployment-container-image-name $Image | Out-Null

# Configure container registry credentials
az webapp config container set `
    --name $AppName `
    --resource-group $ResourceGroup `
    --container-image-name $Image `
    --container-registry-url "https://$AcrName.azurecr.io" `
    --container-registry-user $AcrName `
    --container-registry-password $AcrPassword | Out-Null

# Set environment variables
az webapp config appsettings set `
    --name $AppName `
    --resource-group $ResourceGroup `
    --settings `
        GEMINI_API_KEY=$GeminiApiKey `
        AZURE_STORAGE_CONNECTION_STRING=$ConnectionString `
        AZURE_BLOB_CONTAINER=$BlobContainer `
        MLFLOW_TRACKING_URI="sqlite:///mlflow.db" `
        WEBSITES_PORT=8000 | Out-Null

# Enable logging
az webapp log config `
    --name $AppName `
    --resource-group $ResourceGroup `
    --docker-container-logging filesystem | Out-Null

Write-Host "      OK" -ForegroundColor Green

# ── 9. Summary ────────────────────────────────────────────────────────────────
$BackendUrl = "https://$AppName.azurewebsites.net"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Backend API :  $BackendUrl" -ForegroundColor Cyan
Write-Host "  Health Check:  $BackendUrl/health" -ForegroundColor Cyan
Write-Host "  API Docs    :  $BackendUrl/docs" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Storage Conn:  (saved in App Service settings)" -ForegroundColor Gray
Write-Host "  ACR Image   :  $Image" -ForegroundColor Gray
Write-Host ""
Write-Host "  Next step: Deploy frontend to Azure Static Web Apps" -ForegroundColor Yellow
Write-Host "  Run: az staticwebapp create --name cip-frontend --resource-group $ResourceGroup --source https://github.com/Himkar001/Customer-Intelligence-Platform --branch main --app-location /ui --login-with-github" -ForegroundColor Yellow
Write-Host ""
