<#
.SYNOPSIS
    Module 5 - Monitoring: Log Analytics workspace + diagnostic settings.

.DESCRIPTION
    Constitution Principle VI (stage 5). Centralizes platform logs into one Log
    Analytics workspace so learners can query firewall, WAF, and DDoS telemetry.
    NOTE: per the constitution scope, this lab deliberately does NOT deploy Microsoft
    Defender for Cloud or Microsoft Sentinel - only the Log Analytics workspace.

.NOTES
    Prerequisite: 04-app-delivery.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
$rg = $Lab.ResourceGroup
$loc = $Lab.Location

# --- Log Analytics workspace -------------------------------------------------
Write-LabStep "Creating Log Analytics workspace '$($Lab.Workspace)'"
$ws = Get-AzOperationalInsightsWorkspace -Name $Lab.Workspace -ResourceGroupName $rg -ErrorAction SilentlyContinue
if (-not $ws) {
    $ws = New-AzOperationalInsightsWorkspace -Name $Lab.Workspace -ResourceGroupName $rg -Location $loc `
        -Sku 'PerGB2018' -RetentionInDays 30
}
Write-Host "Workspace ID: $($ws.ResourceId)" -ForegroundColor DarkGray

# --- Helper: send all logs+metrics of a resource to the workspace ------------
function Set-LabDiagnostics {
    param([string]$ResourceId, [string]$Name)
    if (-not $ResourceId) { return }
    $existing = Get-AzDiagnosticSetting -ResourceId $ResourceId -Name $Name -ErrorAction SilentlyContinue
    if ($existing) { Write-Host "  diag '$Name' exists - skipping." -ForegroundColor DarkGray; return }

    # Use the 'allLogs' category group (not per-category enumeration). Get-AzDiagnosticSettingCategory
    # returns nothing for some resource types (e.g. Azure Firewall), which silently produced an empty
    # settings list and NO diagnostic setting at all. 'Dedicated' routes to resource-specific tables
    # (e.g. AZFWIdpsSignature) instead of the legacy AzureDiagnostics table.
    $logSetting = New-AzDiagnosticSettingLogSettingsObject -CategoryGroup 'allLogs' -Enabled $true
    New-AzDiagnosticSetting -ResourceId $ResourceId -Name $Name -WorkspaceId $ws.ResourceId `
        -Log $logSetting -LogAnalyticsDestinationType 'Dedicated' | Out-Null
    Write-Host "  diag '$Name' configured (allLogs -> Dedicated)." -ForegroundColor DarkGray
}

# --- Wire diagnostics for the key security resources -------------------------
Write-LabStep "Configuring diagnostic settings"

$fw = Get-AzFirewall -Name $Lab.FirewallName -ResourceGroupName $rg -ErrorAction SilentlyContinue
if ($fw) { Set-LabDiagnostics -ResourceId $fw.Id -Name 'diag-firewall' }

if ($Lab.DeployAppGateway) {
    $agw = Get-AzApplicationGateway -Name $Lab.AppGwName -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if ($agw) { Set-LabDiagnostics -ResourceId $agw.Id -Name 'diag-appgw' }
}

if ($Lab.DeployFrontDoor) {
    $fd = Get-AzFrontDoorCdnProfile -Name $Lab.FrontDoorProfile -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if ($fd) { Set-LabDiagnostics -ResourceId $fd.Id -Name 'diag-frontdoor' }
}

$fwPip = Get-AzPublicIpAddress -Name $Lab.FirewallPip -ResourceGroupName $rg -ErrorAction SilentlyContinue
if ($fwPip) { Set-LabDiagnostics -ResourceId $fwPip.Id -Name 'diag-fw-pip' }   # includes DDoS metrics/notifications

# --- Checkpoint --------------------------------------------------------------
Write-LabCheckpoint "Monitoring ready. Query logs in workspace '$($Lab.Workspace)'. Lab build complete - remember to run 99-teardown.ps1 when done."
