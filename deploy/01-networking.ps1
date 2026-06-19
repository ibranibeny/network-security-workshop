<#
.SYNOPSIS
    Module 1 - Networking: hub + 2 spoke VNets, subnets, peering, public IPs.

.DESCRIPTION
    Constitution Principle VI (stage 1). Builds the hub-and-spoke backbone:
      Hub  (10.0.25.0/24): AzureFirewallSubnet, AGWAFSubnet, AzureBastionSubnet
      Spk1 (10.0.27.0/24): SPOKE1-SUBNET1 (Win11), SPOKE1-SUBNET2 (Kali)
      Spk2 (10.0.28.0/24): SPOKE2-SUBNET1 (Win Server)
    Peering: hub <-> spoke1, hub <-> spoke2 (spokes route to each other via the hub firewall).

.NOTES
    Prerequisite: 00-preflight.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
$rg = $Lab.ResourceGroup
$loc = $Lab.Location

# --- Hub VNet ----------------------------------------------------------------
Write-LabStep "Creating Hub VNet '$($Lab.HubVnet)'"
$hubSubnets = @(
    New-AzVirtualNetworkSubnetConfig -Name $Lab.FirewallSubnet -AddressPrefix $Lab.FirewallPrefix
    New-AzVirtualNetworkSubnetConfig -Name $Lab.AppGwSubnet    -AddressPrefix $Lab.AppGwPrefix
    New-AzVirtualNetworkSubnetConfig -Name $Lab.BastionSubnet  -AddressPrefix $Lab.BastionPrefix
)
$hub = New-AzVirtualNetwork -Name $Lab.HubVnet -ResourceGroupName $rg -Location $loc `
    -AddressPrefix $Lab.HubPrefix -Subnet $hubSubnets -Force

# --- Spoke1 VNet -------------------------------------------------------------
Write-LabStep "Creating Spoke1 VNet '$($Lab.Spoke1Vnet)'"
$spoke1Subnets = @(
    New-AzVirtualNetworkSubnetConfig -Name $Lab.Spoke1Subnet1 -AddressPrefix $Lab.Spoke1Subnet1Pfx
    New-AzVirtualNetworkSubnetConfig -Name $Lab.Spoke1Subnet2 -AddressPrefix $Lab.Spoke1Subnet2Pfx
)
$spoke1 = New-AzVirtualNetwork -Name $Lab.Spoke1Vnet -ResourceGroupName $rg -Location $loc `
    -AddressPrefix $Lab.Spoke1Prefix -Subnet $spoke1Subnets -Force

# --- Spoke2 VNet -------------------------------------------------------------
Write-LabStep "Creating Spoke2 VNet '$($Lab.Spoke2Vnet)'"
$spoke2Subnets = @(
    New-AzVirtualNetworkSubnetConfig -Name $Lab.Spoke2Subnet1 -AddressPrefix $Lab.Spoke2Subnet1Pfx
)
$spoke2 = New-AzVirtualNetwork -Name $Lab.Spoke2Vnet -ResourceGroupName $rg -Location $loc `
    -AddressPrefix $Lab.Spoke2Prefix -Subnet $spoke2Subnets -Force

# --- VNet peering (hub <-> spokes) -------------------------------------------
Write-LabStep "Peering hub <-> spokes"
function Set-LabPeering {
    param($LocalVnet, $RemoteVnet, $Name)
    if (-not (Get-AzVirtualNetworkPeering -VirtualNetworkName $LocalVnet.Name -ResourceGroupName $rg -Name $Name -ErrorAction SilentlyContinue)) {
        Add-AzVirtualNetworkPeering -Name $Name -VirtualNetwork $LocalVnet -RemoteVirtualNetworkId $RemoteVnet.Id `
            -AllowForwardedTraffic | Out-Null
    }
}
Set-LabPeering -LocalVnet $hub    -RemoteVnet $spoke1 -Name 'hub-to-spoke1'
Set-LabPeering -LocalVnet $spoke1 -RemoteVnet $hub    -Name 'spoke1-to-hub'
Set-LabPeering -LocalVnet $hub    -RemoteVnet $spoke2 -Name 'hub-to-spoke2'
Set-LabPeering -LocalVnet $spoke2 -RemoteVnet $hub    -Name 'spoke2-to-hub'

# --- Public IPs (Standard, static, zone-redundant) ---------------------------
Write-LabStep "Creating public IPs (Firewall, App Gateway, Bastion)"
function New-LabPip {
    param($Name)
    $existing = Get-AzPublicIpAddress -Name $Name -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if ($existing) { return $existing }
    New-AzPublicIpAddress -Name $Name -ResourceGroupName $rg -Location $loc `
        -AllocationMethod Static -Sku Standard
}
New-LabPip -Name $Lab.FirewallPip | Out-Null
New-LabPip -Name $Lab.BastionPip  | Out-Null
if ($Lab.DeployAppGateway) { New-LabPip -Name $Lab.AppGwPip | Out-Null }

# --- Checkpoint --------------------------------------------------------------
$vnets = Get-AzVirtualNetwork -ResourceGroupName $rg | Select-Object Name, @{n='Prefix';e={$_.AddressSpace.AddressPrefixes -join ','}}
$vnets | Format-Table -AutoSize
Write-LabCheckpoint "Networking ready: 3 VNets peered, public IPs created. Proceed to 02-security-core.ps1"
