<#
.SYNOPSIS
    Create the OWASP Juice Shop backend on Azure Container Instances (ACI) via a
    private Azure Container Registry (ACR). Run AFTER 03-compute.ps1 and BEFORE
    04-app-delivery.ps1.

.DESCRIPTION
    Pulling the Juice Shop image directly from Docker Hub (docker.io) is unreliable:
      - Anonymous pulls are rate-limited        -> RegistryErrorResponse ("retry later")
      - Basic auth is rejected with 2FA enabled  -> InaccessibleImage
    The reliable method this script implements:
      1. Create a private ACR (Basic, admin enabled).
      2. `az acr import` the image ONCE from Docker Hub (server-side copy - no local
         Docker, no Docker Hub login required on the client).
      3. Create the ACI pulling from ACR using ACR admin credentials.

    Idempotent: re-running only creates what is missing. Names come from config.ps1
    ($Lab.AcrName, $Lab.AcrImage, $Lab.SourceContainerImage, $Lab.AciName,
    $Lab.WebAppBackendFqdn -> the ACI DNS label).

.NOTES
    Requires the Azure CLI (`az`) signed in to the same subscription as the lab.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
$rg  = $Lab.ResourceGroup
$loc = $Lab.Location

# The ACI DNS label is the first segment of the configured backend FQDN
# (e.g. 'ns-juice-demo-bibrani' from 'ns-juice-demo-bibrani.westus.azurecontainer.io').
$dnsLabel = ($Lab.WebAppBackendFqdn -split '\.')[0]
$port     = $Lab.WebAppBackendPort

# --- 1. ACR -----------------------------------------------------------------
Write-LabStep "Ensuring Azure Container Registry '$($Lab.AcrName)' exists"
$acrExists = az acr show -n $Lab.AcrName -g $rg --query 'name' -o tsv 2>$null
if (-not $acrExists) {
    az acr create -g $rg -n $Lab.AcrName --sku Basic --admin-enabled true -o table
} else {
    Write-Host "ACR already exists - skipping create." -ForegroundColor DarkGray
}

# --- 2. Import the image (server-side, avoids Docker Hub client rate-limit) --
Write-LabStep "Importing '$($Lab.SourceContainerImage)' into ACR as '$($Lab.AcrImage)'"
$imgExists = az acr repository show -n $Lab.AcrName --image $Lab.AcrImage --query 'name' -o tsv 2>$null
if (-not $imgExists) {
    # Retry import a few times - Docker Hub may briefly rate-limit even server-side.
    # (Native `az` failures set $LASTEXITCODE rather than throwing, so check it.)
    $maxTries = 4
    for ($i = 1; $i -le $maxTries; $i++) {
        az acr import -n $Lab.AcrName --source $Lab.SourceContainerImage --image $Lab.AcrImage
        if ($LASTEXITCODE -eq 0) { break }
        if ($i -eq $maxTries) { throw "az acr import failed after $maxTries attempts." }
        Write-Host "Import attempt $i failed (likely Docker Hub rate-limit). Retrying in 30s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
    }
} else {
    Write-Host "Image already imported - skipping import." -ForegroundColor DarkGray
}

# --- 3. ACI from ACR --------------------------------------------------------
$acrLoginServer = az acr show -n $Lab.AcrName -g $rg --query 'loginServer' -o tsv
$acrUser        = az acr credential show -n $Lab.AcrName --query 'username' -o tsv
$acrPass        = az acr credential show -n $Lab.AcrName --query 'passwords[0].value' -o tsv

Write-LabStep "Creating Azure Container Instance '$($Lab.AciName)' (pulls from ACR)"
$aciExists = az container show -g $rg -n $Lab.AciName --query 'name' -o tsv 2>$null
if (-not $aciExists) {
    az container create `
        --resource-group $rg `
        --name $Lab.AciName `
        --image "$acrLoginServer/$($Lab.AcrImage)" `
        --os-type Linux --cpu 1 --memory 1.5 `
        --ports $port --ip-address Public `
        --dns-name-label $dnsLabel `
        --registry-login-server $acrLoginServer `
        --registry-username $acrUser `
        --registry-password $acrPass `
        -o table
} else {
    Write-Host "ACI already exists - skipping create." -ForegroundColor DarkGray
}

# --- Verify -----------------------------------------------------------------
$state = az container show -g $rg -n $Lab.AciName --query 'instanceView.state' -o tsv
$fqdn  = az container show -g $rg -n $Lab.AciName --query 'ipAddress.fqdn' -o tsv
Write-LabCheckpoint "ACI '$($Lab.AciName)' state=$state  FQDN=$fqdn (port $port). Proceed to 04-app-delivery.ps1"
Write-Host "Smoke test: curl.exe http://$fqdn`:$port" -ForegroundColor DarkGray
