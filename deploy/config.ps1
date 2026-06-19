<#
.SYNOPSIS
    Shared configuration for the Azure Network Security Demo Lab workshop.

.DESCRIPTION
    Dot-sourced by every module (and Deploy-All.ps1). Defines the single source of
    truth for region, naming (prefix/suffix), address spaces, subnet layout, VM
    images, and SKUs. Per the project constitution:
      - Region is a SINGLE variable (Principle III) so the lab can be retargeted.
      - Names are deterministic (Principle IV) to avoid collisions.
      - NO secrets live here (Principle IV / VII) - the VM password is prompted at
        runtime in 03-compute.ps1 via Get-Credential.

    Edit the values in the "EDIT ME" block below for your environment, then run the
    modules in order (00 -> 05) or run Deploy-All.ps1.
#>

# ---------------------------------------------------------------------------
# EDIT ME - core settings
# ---------------------------------------------------------------------------
$Prefix   = 'NS'      # short resource name prefix (keep <= 4 chars)
$Suffix   = 'demo'    # short suffix to keep names unique within your subscription
$Location = 'westus'  # default region (Azure Network Security PoC Part 2 uses West US)

# Optional features (cost-bearing - see README cost note)
$EnableDdos = $false  # DDoS Network Protection plan (~$2,944/mo) - default OFF
$DeployFrontDoor = $true
$DeployAppGateway = $true
# App Service requires dedicated VM quota, which sponsored/MCAP subs cap at 0.
# We instead host OWASP Juice Shop on Azure Container Instances (ACI, separate quota
# pool) and point App Gateway at its public FQDN over HTTP:3000.
$DeployWebApp = $false
$WebAppBackendFqdn = 'ns-juice-demo-bibrani.westus.azurecontainer.io'  # ACI Juice Shop
$WebAppBackendPort = 3000
$WebAppBackendProtocol = 'Http'

# --- Docker Hub login (PREREQUISITE for the ACI backend) ---------------------
# Docker Hub rate-limits ANONYMOUS pulls, which makes `az container create` fail
# intermittently with RegistryErrorResponse. Supply a (free) Docker Hub account so
# the pull is authenticated. NO SECRET IS STORED HERE (Principle IV/VII): the values
# are read from environment variables, and the password is prompted securely if unset.
#   PowerShell:  $env:DOCKERHUB_USERNAME = 'youruser'; $env:DOCKERHUB_PASSWORD = '<token>'
# Prefer a Docker Hub *access token* (Account Settings -> Security) over your password.
$DockerHubUsername = $env:DOCKERHUB_USERNAME
$DockerHubPassword = $env:DOCKERHUB_PASSWORD   # leave unset to be prompted securely
$AciName           = 'ns-juice-aci'            # Azure Container Instance hosting Juice Shop

# VM sizing and images (validate currency per Principle I with Get-AzVMImageSku)
$VmSize = 'Standard_D2s_v3'

# Windows 11 client (Spoke1 / Subnet1)
$Win11Image = @{ Publisher = 'MicrosoftWindowsDesktop'; Offer = 'windows-11'; Sku = 'win11-24h2-pro'; Version = 'latest' }
# Kali Linux (Spoke1 / Subnet2) - marketplace image, terms accepted in 03-compute.ps1
$KaliImage  = @{ Publisher = 'kali-linux'; Offer = 'kali'; Sku = 'kali-2026-1'; Version = 'latest' }
# Windows Server (Spoke2 / Subnet1) - modernized from 2019 -> 2022 per Principle I
$WinSrvImage = @{ Publisher = 'MicrosoftWindowsServer'; Offer = 'WindowsServer'; Sku = '2022-datacenter-azure-edition'; Version = 'latest' }

# Demo web app container (OWASP Juice Shop - intentionally vulnerable, demo-only per Principle VII)
$WebAppContainerImage = 'bkimminich/juice-shop:latest'

# ---------------------------------------------------------------------------
# Derived names (deterministic) - usually no need to edit
# ---------------------------------------------------------------------------
$n = "$Prefix-{0}-$Suffix"   # name template helper

$Lab = [ordered]@{
    Location          = $Location
    EnableDdos        = $EnableDdos
    DeployFrontDoor   = $DeployFrontDoor
    DeployAppGateway  = $DeployAppGateway
    DeployWebApp      = $DeployWebApp
    WebAppBackendFqdn = $WebAppBackendFqdn
    WebAppBackendPort = $WebAppBackendPort
    WebAppBackendProtocol = $WebAppBackendProtocol
    DockerHubUsername = $DockerHubUsername
    DockerHubPassword = $DockerHubPassword
    AciName           = $AciName
    VmSize            = $VmSize
    Win11Image        = $Win11Image
    KaliImage         = $KaliImage
    WinSrvImage       = $WinSrvImage
    WebAppContainerImage = $WebAppContainerImage

    ResourceGroup     = "rg-netsec-$Suffix"

    # Networking
    HubVnet           = ($n -f 'VN-HUB')
    Spoke1Vnet        = ($n -f 'VN-SPOKE1')
    Spoke2Vnet        = ($n -f 'VN-SPOKE2')

    # Subnet names (must match Azure reserved names exactly where required)
    FirewallSubnet    = 'AzureFirewallSubnet'   # reserved name, /26 minimum
    AppGwSubnet       = 'AGWAFSubnet'
    BastionSubnet     = 'AzureBastionSubnet'    # reserved name, /26 minimum
    Spoke1Subnet1     = 'SPOKE1-SUBNET1'
    Spoke1Subnet2     = 'SPOKE1-SUBNET2'
    Spoke2Subnet1     = 'SPOKE2-SUBNET1'

    # Address spaces (hub-and-spoke; see README diagram)
    HubPrefix         = '10.0.25.0/24'
    FirewallPrefix    = '10.0.25.0/26'
    AppGwPrefix       = '10.0.25.64/26'
    BastionPrefix     = '10.0.25.128/26'   # Bastion in HUB (documented deviation - reaches all spokes via peering)
    Spoke1Prefix      = '10.0.27.0/24'
    Spoke1Subnet1Pfx  = '10.0.27.0/26'
    Spoke1Subnet2Pfx  = '10.0.27.64/26'
    Spoke2Prefix      = '10.0.28.0/24'
    Spoke2Subnet1Pfx  = '10.0.28.0/26'

    # Static VM private IPs
    Win11Ip           = '10.0.27.4'
    KaliIp            = '10.0.27.68'
    WinSrvIp          = '10.0.28.4'

    # Security
    DdosPlan          = ($n -f 'DDOS-PLAN')
    FirewallName      = ($n -f 'FW')
    FirewallPolicy    = ($n -f 'FWPolicy')
    FirewallPip       = ($n -f 'FW-PIP')
    Nsg1              = ($n -f 'NSG1')   # spoke1
    Nsg2              = ($n -f 'NSG2')   # spoke2
    RouteTable        = ($n -f 'RT')

    # Compute
    Win11Vm           = ($n -f 'W11')
    KaliVm            = ($n -f 'KALI')
    WinSrvVm          = ($n -f 'W2022')
    Bastion           = ($n -f 'BASTION')
    BastionPip        = ($n -f 'BASTION-PIP')
    AdminUsername     = 'azureadmin'

    # App delivery
    AppServicePlan    = ($n -f 'ASP')
    WebApp            = ("$Prefix-juice-$Suffix").ToLower()
    AppGwName         = ($n -f 'AG-WAFv2')
    AppGwPip          = ($n -f 'AG-PIP')
    AppGwNsg          = ($n -f 'AG-NSG')
    AppGwWafPolicy    = ($n -f 'AGPolicy')
    FrontDoorProfile  = ($n -f 'FD')
    FrontDoorEndpoint = ("$Prefix-fd-$Suffix").ToLower()
    FrontDoorOriginGroup = ($n -f 'FD-OG')
    FrontDoorOrigin   = ($n -f 'FD-ORIGIN')
    FrontDoorRoute    = ($n -f 'FD-ROUTE')
    FrontDoorWaf      = ("$($Prefix)FDWAF$($Suffix)") -replace '[^a-zA-Z0-9]',''

    # Monitoring
    Workspace         = ($n -f 'LA')
}

# Make available to dot-sourcing scripts
$Global:Lab = $Lab

# Required Az sub-modules for the whole workshop
$Global:LabRequiredModules = @(
    'Az.Accounts', 'Az.Resources', 'Az.Network', 'Az.Compute',
    'Az.OperationalInsights', 'Az.Monitor', 'Az.Websites', 'Az.Cdn', 'Az.FrontDoor',
    'Az.MarketplaceOrdering'
)

function Write-LabStep {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-LabCheckpoint {
    param([string]$Message)
    Write-Host "[CHECKPOINT] $Message" -ForegroundColor Green
}

Write-Host "Loaded lab config: RG '$($Lab.ResourceGroup)' in '$($Lab.Location)'." -ForegroundColor DarkGray
