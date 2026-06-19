<#
.SYNOPSIS
    Module 99 - Teardown: delete the entire lab resource group.

.DESCRIPTION
    Constitution Principle VI mandates a single, reliable teardown. Because every lab
    resource lives in ONE resource group, removing that group removes everything and
    stops all billing. Requires explicit confirmation.

.NOTES
    Run last:  ./99-teardown.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force   # skip the interactive confirmation prompt
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
$rg = $Lab.ResourceGroup

$group = Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue
if (-not $group) {
    Write-Host "Resource group '$rg' not found - nothing to remove." -ForegroundColor Yellow
    return
}

Write-Host "About to DELETE resource group '$rg' and ALL resources in it:" -ForegroundColor Red
Get-AzResource -ResourceGroupName $rg | Select-Object Name, ResourceType | Format-Table -AutoSize

if (-not $Force) {
    $answer = Read-Host "Type the resource group name '$rg' to confirm deletion"
    if ($answer -ne $rg) {
        Write-Host "Confirmation did not match - aborting." -ForegroundColor Yellow
        return
    }
}

if ($PSCmdlet.ShouldProcess($rg, 'Remove-AzResourceGroup')) {
    Write-LabStep "Deleting resource group '$rg' (runs in background)"
    Remove-AzResourceGroup -Name $rg -Force -AsJob | Out-Null
    Write-LabCheckpoint "Teardown started. Track with: Get-Job | Wait-Job. Billing stops as resources delete."
}
