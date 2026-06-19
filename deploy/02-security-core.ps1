<#
.SYNOPSIS
    Module 2 - Security core: Azure Firewall Premium (+ IDPS), NSGs, UDR, optional DDoS.

.DESCRIPTION
    Constitution Principle VI (stage 2) and Principle VII (secure-by-default).
      - Firewall Policy Premium with IDPS (Intrusion Detection) in Alert mode.
      - Azure Firewall Premium in the hub AzureFirewallSubnet.
      - Network/application rules: allow east-west admin between spokes + curated FQDNs.
      - NSGs on spoke subnets: deny inbound from Internet; allow only Bastion RDP/SSH.
      - UDR forcing 0.0.0.0/0 from spoke subnets through the firewall.
      - Optional DDoS Network Protection plan (config: $EnableDdos).

    COST NOTE: Azure Firewall Premium (~$1.75/hr + data) and DDoS plan (~$2,944/mo)
    are the expensive resources. DDoS defaults OFF.

.NOTES
    Prerequisite: 01-networking.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
$rg = $Lab.ResourceGroup
$loc = $Lab.Location

$hub    = Get-AzVirtualNetwork -Name $Lab.HubVnet    -ResourceGroupName $rg
$spoke1 = Get-AzVirtualNetwork -Name $Lab.Spoke1Vnet -ResourceGroupName $rg
$spoke2 = Get-AzVirtualNetwork -Name $Lab.Spoke2Vnet -ResourceGroupName $rg

# --- Optional: DDoS Network Protection plan ----------------------------------
if ($Lab.EnableDdos) {
    Write-LabStep "Creating DDoS Network Protection plan '$($Lab.DdosPlan)' (COST: ~`$2,944/mo)"
    $ddos = Get-AzDdosProtectionPlan -Name $Lab.DdosPlan -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if (-not $ddos) { $ddos = New-AzDdosProtectionPlan -Name $Lab.DdosPlan -ResourceGroupName $rg -Location $loc }
    $hub.DdosProtectionPlan = New-Object Microsoft.Azure.Commands.Network.Models.PSResourceId
    $hub.DdosProtectionPlan.Id = $ddos.Id
    $hub.EnableDdosProtection = $true
    $hub = Set-AzVirtualNetwork -VirtualNetwork $hub
    Write-Host "DDoS enabled on hub VNet." -ForegroundColor DarkGray
} else {
    Write-Host "DDoS plan skipped (set `$EnableDdos = `$true in config.ps1 to enable)." -ForegroundColor DarkGray
}

# --- Firewall Policy Premium + IDPS ------------------------------------------
Write-LabStep "Creating Firewall Policy Premium '$($Lab.FirewallPolicy)' with IDPS (Alert mode)"
$policy = Get-AzFirewallPolicy -Name $Lab.FirewallPolicy -ResourceGroupName $rg -ErrorAction SilentlyContinue
if (-not $policy) {
    $idps = New-AzFirewallPolicyIntrusionDetection -Mode 'Alert'
    $policy = New-AzFirewallPolicy -Name $Lab.FirewallPolicy -ResourceGroupName $rg -Location $loc `
        -SkuTier 'Premium' -IntrusionDetection $idps
}

# Rule collection group + rules (east-west admin + outbound FQDNs)
Write-LabStep "Adding firewall rules (network: spoke<->spoke admin; application: curated FQDNs)"
$netRule = New-AzFirewallPolicyNetworkRule -Name 'Allow-Spoke-Admin' `
    -SourceAddress $Lab.Spoke1Prefix, $Lab.Spoke2Prefix `
    -DestinationAddress $Lab.Spoke1Prefix, $Lab.Spoke2Prefix `
    -DestinationPort 3389, 22, 445 -Protocol TCP
$netCollection = New-AzFirewallPolicyFilterRuleCollection -Name 'NetworkRules' -Priority 200 `
    -ActionType 'Allow' -Rule $netRule

$appRule = New-AzFirewallPolicyApplicationRule -Name 'Allow-Web' `
    -SourceAddress $Lab.Spoke1Prefix, $Lab.Spoke2Prefix `
    -TargetFqdn 'www.bing.com', '*.google.com', '*.microsoft.com', '*.ubuntu.com', '*.kali.org' `
    -Protocol 'http:80', 'https:443'
$appCollection = New-AzFirewallPolicyFilterRuleCollection -Name 'ApplicationRules' -Priority 300 `
    -ActionType 'Allow' -Rule $appRule

if (-not (Get-AzFirewallPolicyRuleCollectionGroup -Name 'LabRuleCollectionGroup' -AzureFirewallPolicyName $Lab.FirewallPolicy -ResourceGroupName $rg -ErrorAction SilentlyContinue)) {
    New-AzFirewallPolicyRuleCollectionGroup -Name 'LabRuleCollectionGroup' -Priority 200 `
        -RuleCollection $netCollection, $appCollection `
        -FirewallPolicyObject $policy | Out-Null
}

# --- Azure Firewall Premium --------------------------------------------------
Write-LabStep "Creating Azure Firewall Premium '$($Lab.FirewallName)' (this can take ~10 min)"
$fw = Get-AzFirewall -Name $Lab.FirewallName -ResourceGroupName $rg -ErrorAction SilentlyContinue
if (-not $fw) {
    $fw = New-AzFirewall -Name $Lab.FirewallName -ResourceGroupName $rg -Location $loc `
        -SkuName 'AZFW_VNet' -SkuTier 'Premium' `
        -VirtualNetworkName $Lab.HubVnet -PublicIpName $Lab.FirewallPip `
        -FirewallPolicyId $policy.Id
}
$fwPrivateIp = $fw.IpConfigurations[0].PrivateIPAddress
Write-Host "Firewall private IP: $fwPrivateIp" -ForegroundColor DarkGray

# --- NSGs (deny inbound from Internet; allow Bastion RDP/SSH) -----------------
Write-LabStep "Creating NSGs for spoke subnets"
function New-LabNsg {
    param($Name)
    $existing = Get-AzNetworkSecurityGroup -Name $Name -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if ($existing) { return $existing }
    $allowBastion = New-AzNetworkSecurityRuleConfig -Name 'Allow-Bastion-RDP-SSH' -Access Allow -Protocol Tcp `
        -Direction Inbound -Priority 100 -SourceAddressPrefix $Lab.BastionPrefix -SourcePortRange * `
        -DestinationAddressPrefix * -DestinationPortRange 3389, 22
    $allowVnet = New-AzNetworkSecurityRuleConfig -Name 'Allow-VNet-Inbound' -Access Allow -Protocol * `
        -Direction Inbound -Priority 200 -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
        -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *
    $denyInternet = New-AzNetworkSecurityRuleConfig -Name 'Deny-Internet-Inbound' -Access Deny -Protocol * `
        -Direction Inbound -Priority 4096 -SourceAddressPrefix Internet -SourcePortRange * `
        -DestinationAddressPrefix * -DestinationPortRange *
    New-AzNetworkSecurityGroup -Name $Name -ResourceGroupName $rg -Location $loc `
        -SecurityRules $allowBastion, $allowVnet, $denyInternet
}
$nsg1 = New-LabNsg -Name $Lab.Nsg1
$nsg2 = New-LabNsg -Name $Lab.Nsg2

# --- Route table: 0.0.0.0/0 -> firewall --------------------------------------
Write-LabStep "Creating route table forcing egress through the firewall"
$rt = Get-AzRouteTable -Name $Lab.RouteTable -ResourceGroupName $rg -ErrorAction SilentlyContinue
if (-not $rt) {
    $rt = New-AzRouteTable -Name $Lab.RouteTable -ResourceGroupName $rg -Location $loc
}
$rt | Add-AzRouteConfig -Name 'default-to-firewall' -AddressPrefix '0.0.0.0/0' `
    -NextHopType VirtualAppliance -NextHopIpAddress $fwPrivateIp -ErrorAction SilentlyContinue | Out-Null
$rt = Set-AzRouteTable -RouteTable $rt

# --- Associate NSGs + route table to spoke subnets ---------------------------
Write-LabStep "Associating NSGs and route table to spoke subnets"
$spoke1 = Get-AzVirtualNetwork -Name $Lab.Spoke1Vnet -ResourceGroupName $rg
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke1 -Name $Lab.Spoke1Subnet1 `
    -AddressPrefix $Lab.Spoke1Subnet1Pfx -NetworkSecurityGroup $nsg1 -RouteTable $rt | Out-Null
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke1 -Name $Lab.Spoke1Subnet2 `
    -AddressPrefix $Lab.Spoke1Subnet2Pfx -NetworkSecurityGroup $nsg1 -RouteTable $rt | Out-Null
$spoke1 | Set-AzVirtualNetwork | Out-Null

$spoke2 = Get-AzVirtualNetwork -Name $Lab.Spoke2Vnet -ResourceGroupName $rg
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke2 -Name $Lab.Spoke2Subnet1 `
    -AddressPrefix $Lab.Spoke2Subnet1Pfx -NetworkSecurityGroup $nsg2 -RouteTable $rt | Out-Null
$spoke2 | Set-AzVirtualNetwork | Out-Null

# --- Checkpoint --------------------------------------------------------------
Write-LabCheckpoint "Security core ready. Firewall Premium '$($Lab.FirewallName)' private IP $fwPrivateIp; spokes locked down. Proceed to 03-compute.ps1"
