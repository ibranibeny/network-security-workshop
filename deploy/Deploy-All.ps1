<#
.SYNOPSIS
    Orchestrator - runs the NetSec Demo Lab modules 00 -> 05 in order with checkpoints.

.DESCRIPTION
    Constitution Principle VI (Sequential, Checkpoint-Gated Deployment). Runs each
    module in dependency order and stops on the first failure. By default it pauses
    after each stage so a workshop facilitator can validate the checkpoint before
    continuing; use -NoPause for an unattended run.

.EXAMPLE
    ./Deploy-All.ps1
    Interactive, paused run (recommended for the live workshop).

.EXAMPLE
    $cred = Get-Credential azureadmin
    ./Deploy-All.ps1 -AdminCredential $cred -SubscriptionId '<name-or-id>' -NoPause
    Unattended end-to-end build into a specific subscription.
#>
[CmdletBinding()]
param(
    [System.Management.Automation.PSCredential]$AdminCredential,
    # Pre-select a subscription (name or id). Required for a fully unattended -NoPause run;
    # if omitted, 00-preflight.ps1 prompts interactively to choose and confirm.
    [string]$SubscriptionId,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"

$modules = @(
    '00-preflight.ps1'
    '01-networking.ps1'
    '02-security-core.ps1'
    '03-compute.ps1'
    '04-app-delivery.ps1'
    '05-monitoring.ps1'
)

$start = Get-Date
foreach ($m in $modules) {
    Write-Host "`n############################################################" -ForegroundColor Magenta
    Write-Host "# Stage: $m" -ForegroundColor Magenta
    Write-Host "############################################################" -ForegroundColor Magenta

    $path = Join-Path $PSScriptRoot $m
    if ($m -eq '00-preflight.ps1' -and $SubscriptionId) {
        & $path -SubscriptionId $SubscriptionId
    } elseif ($m -eq '03-compute.ps1' -and $AdminCredential) {
        & $path -AdminCredential $AdminCredential
    } else {
        & $path
    }

    if (-not $NoPause -and $m -ne $modules[-1]) {
        Read-Host "`nCheckpoint reached for $m. Press Enter to continue to the next stage (Ctrl+C to stop)"
    }
}

$elapsed = (Get-Date) - $start
Write-Host "`nAll stages complete in $([math]::Round($elapsed.TotalMinutes,1)) min." -ForegroundColor Green

Write-Host "`nNext: run the demonstration scenarios to prove the controls work." -ForegroundColor Cyan
Write-Host "  S1  WAF blocks a web attack (HTTP 403)"                       -ForegroundColor Cyan
Write-Host "  S2  Firewall FQDN filtering - allowed vs blocked"             -ForegroundColor Cyan
Write-Host "  S3  Default-deny segmentation (east-west)"                    -ForegroundColor Cyan
Write-Host "  S4  Forced-tunnel egress through the firewall"               -ForegroundColor Cyan
Write-Host "  S5  Firewall IDPS - outbound intrusion detection"            -ForegroundColor Cyan
Write-Host "  S6  Firewall IDPS - inbound via DNAT (optional)"             -ForegroundColor Cyan
Write-Host "  S7  Application Gateway custom WAF rule (optional)"          -ForegroundColor Cyan
Write-Host "  S8  Application Gateway WAF geo-blocking (optional)"          -ForegroundColor Cyan
Write-Host "  S9  Read the telemetry in Log Analytics (KQL or portal)"     -ForegroundColor Cyan
Write-Host "  Step-by-step commands: docs/WORKSHOP-WALKTHROUGH.md"          -ForegroundColor Cyan

Write-Host "`nRun ./99-teardown.ps1 when you are finished to delete everything and stop billing." -ForegroundColor Yellow
