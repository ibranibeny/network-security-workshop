<#
.SYNOPSIS
    Module 0 - Pre-flight: sign in, validate region/SKU/quota, create the resource group.

.DESCRIPTION
    Constitution Principle III (Region-Aware Deployment) and Principle VI (stage 0).
    This module does the MANDATORY pre-flight availability gate BEFORE any resource
    is provisioned. It will stop the workshop early if West US cannot host the lab in
    your subscription, instead of failing halfway through.

.NOTES
    Run from the deploy/ folder:  ./00-preflight.ps1
#>
[CmdletBinding()]
param(
    # Pre-select a subscription (name or id) for unattended runs. When supplied,
    # the script selects it non-interactively and skips the typed confirmation.
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"

# --- 1. Verify required Az modules are installed -----------------------------
Write-LabStep "Checking required Az PowerShell modules"
$missing = @()
foreach ($m in $LabRequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) { $missing += $m }
}
if ($missing) {
    throw "Missing Az modules: $($missing -join ', '). Install with: Install-Module Az -Scope CurrentUser"
}
Write-Host "All required modules present." -ForegroundColor DarkGray

# --- 2. Sign in and select subscription --------------------------------------
Write-LabStep "Confirming Azure sign-in"
$ctx = Get-AzContext
if (-not $ctx) {
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext
}
if (-not $ctx) { throw "Azure sign-in failed - no active context. Run Connect-AzAccount and retry." }

# Detect all subscriptions this identity can access and confirm the target.
Write-LabStep "Selecting Azure subscription"
$subs = @(Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' } | Sort-Object Name)
if (-not $subs) { throw "No enabled subscriptions found for '$($ctx.Account.Id)'." }

if ($SubscriptionId) {
    # Non-interactive selection (unattended / orchestrated runs).
    $selected = $subs | Where-Object { $_.Id -eq $SubscriptionId -or $_.Name -eq $SubscriptionId } | Select-Object -First 1
    if (-not $selected) {
        throw "Requested subscription '$SubscriptionId' is not accessible to '$($ctx.Account.Id)'."
    }
    Write-Host "Using pre-selected subscription: $($selected.Name) ($($selected.Id))" -ForegroundColor DarkGray
} elseif ($subs.Count -eq 1) {
    $selected = $subs[0]
    Write-Host "Only one subscription available: $($selected.Name) ($($selected.Id))" -ForegroundColor DarkGray
} else {
    Write-Host "Subscriptions available to $($ctx.Account.Id):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $marker = if ($subs[$i].Id -eq $ctx.Subscription.Id) { '* (current)' } else { '' }
        Write-Host ("  [{0}] {1}  {2} {3}" -f $i, $subs[$i].Name, $subs[$i].Id, $marker)
    }
    $defaultIdx = [Math]::Max(0, [Array]::IndexOf(($subs | ForEach-Object Id), $ctx.Subscription.Id))
    $answer = Read-Host "Enter the number of the subscription to deploy into [default $defaultIdx]"
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $defaultIdx }
    if ($answer -notmatch '^\d+$' -or [int]$answer -lt 0 -or [int]$answer -ge $subs.Count) {
        throw "Invalid selection '$answer'. Re-run 00-preflight.ps1 and choose a listed number."
    }
    $selected = $subs[[int]$answer]
}

# Switch context if needed.
if ($ctx.Subscription.Id -ne $selected.Id) {
    Set-AzContext -Subscription $selected.Id | Out-Null
    $ctx = Get-AzContext
}

# Explicit confirmation gate before any resource is created.
Write-Host "About to deploy the NetSec demo lab into:" -ForegroundColor Yellow
Write-Host "  Subscription : $($selected.Name) ($($selected.Id))" -ForegroundColor Yellow
Write-Host "  Region       : $($Lab.Location)" -ForegroundColor Yellow
Write-Host "  Resource grp : $($Lab.ResourceGroup)" -ForegroundColor Yellow
Write-Host "  Note         : premium SKUs (Firewall/Front Door Premium, App Gateway WAFv2) incur cost." -ForegroundColor Yellow
if ($SubscriptionId) {
    Write-Host "Subscription pre-confirmed via -SubscriptionId; skipping interactive confirmation." -ForegroundColor DarkGray
} else {
    $confirm = Read-Host "Type 'yes' to confirm this subscription and continue"
    if ($confirm -ne 'yes') { throw "Subscription not confirmed. Aborting pre-flight." }
}
Write-Host "Subscription confirmed: $($selected.Name)" -ForegroundColor DarkGray

# --- 3. Region availability gate (Principle III) -----------------------------
Write-LabStep "Validating region '$($Lab.Location)' is available"
$region = Get-AzLocation | Where-Object Location -eq $Lab.Location
if (-not $region) { throw "Region '$($Lab.Location)' not found / not available to this subscription." }
Write-Host "Region OK: $($region.DisplayName)" -ForegroundColor DarkGray

# --- 4. VM SKU availability gate ---------------------------------------------
Write-LabStep "Validating VM size '$($Lab.VmSize)' in '$($Lab.Location)'"
$sku = Get-AzComputeResourceSku -Location $Lab.Location |
    Where-Object { $_.ResourceType -eq 'virtualMachines' -and $_.Name -eq $Lab.VmSize }
if (-not $sku) {
    throw "VM size '$($Lab.VmSize)' is not available in '$($Lab.Location)'. Pick another size in config.ps1."
}
$restricted = $sku.Restrictions | Where-Object { $_.ReasonCode }
if ($restricted) {
    Write-Warning "VM size '$($Lab.VmSize)' has restrictions in this region/subscription. Review before continuing."
}
Write-Host "VM size OK." -ForegroundColor DarkGray

# --- 5. vCPU quota gate -------------------------------------------------------
Write-LabStep "Checking compute quota (need >= 6 vCPUs for 3 lab VMs)"
$usage = Get-AzVMUsage -Location $Lab.Location |
    Where-Object { $_.Name.Value -eq 'cores' }
if ($usage) {
    $available = $usage.Limit - $usage.CurrentValue
    Write-Host "Regional cores: $($usage.CurrentValue)/$($usage.Limit) used, $available available." -ForegroundColor DarkGray
    if ($available -lt 6) {
        Write-Warning "Low core quota ($available). 3x $($Lab.VmSize) needs ~6 vCPUs. Request a quota increase if compute fails."
    }
}

# --- 6. Create the resource group (idempotent) -------------------------------
Write-LabStep "Creating resource group '$($Lab.ResourceGroup)'"
$rg = Get-AzResourceGroup -Name $Lab.ResourceGroup -ErrorAction SilentlyContinue
if (-not $rg) {
    $rg = New-AzResourceGroup -Name $Lab.ResourceGroup -Location $Lab.Location -Tag @{ workshop = 'netsec-demo' }
    Write-Host "Created." -ForegroundColor DarkGray
} else {
    Write-Host "Already exists - reusing." -ForegroundColor DarkGray
}

Write-LabCheckpoint "Pre-flight passed. RG '$($rg.ResourceGroupName)' ready in '$($rg.Location)'. Proceed to 01-networking.ps1"
