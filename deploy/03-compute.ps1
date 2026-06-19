<#
.SYNOPSIS
    Module 3 - Compute: 3 lab VMs (Win11, Kali, Win Server) + Azure Bastion.

.DESCRIPTION
    Constitution Principle VI (stage 3) and Principle VII (Bastion-only admin - NO
    public RDP/SSH; no public IPs on VMs). The VM admin password is collected at
    runtime via Get-Credential, so NO secret is ever written to source (Principle IV/VII).

    Bastion is deployed in the HUB and reaches all spoke VMs over peering (Standard SKU).

.NOTES
    Prerequisite: 02-security-core.ps1
#>
[CmdletBinding()]
param(
    # Pass a credential non-interactively for automation; otherwise you are prompted.
    [System.Management.Automation.PSCredential]$AdminCredential
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/config.ps1"
$rg = $Lab.ResourceGroup
$loc = $Lab.Location

# --- VM admin credential (NO secret in source) -------------------------------
if (-not $AdminCredential) {
    Write-LabStep "Enter the VM local admin password (username is '$($Lab.AdminUsername)')"
    $AdminCredential = Get-Credential -UserName $Lab.AdminUsername `
        -Message "Set a strong password for the lab VMs (12-123 chars, 3 of 4 complexity classes)."
}

$hub    = Get-AzVirtualNetwork -Name $Lab.HubVnet    -ResourceGroupName $rg
$spoke1 = Get-AzVirtualNetwork -Name $Lab.Spoke1Vnet -ResourceGroupName $rg
$spoke2 = Get-AzVirtualNetwork -Name $Lab.Spoke2Vnet -ResourceGroupName $rg

$spoke1Subnet1 = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke1 -Name $Lab.Spoke1Subnet1
$spoke1Subnet2 = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke1 -Name $Lab.Spoke1Subnet2
$spoke2Subnet1 = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $spoke2 -Name $Lab.Spoke2Subnet1

function New-LabNic {
    param($Name, $SubnetId, $PrivateIp)
    $existing = Get-AzNetworkInterface -Name $Name -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if ($existing) { return $existing }
    New-AzNetworkInterface -Name $Name -ResourceGroupName $rg -Location $loc `
        -SubnetId $SubnetId -PrivateIpAddress $PrivateIp   # NO -PublicIpAddress = no public exposure
}

function Test-LabVmExists {
    param($Name)
    [bool](Get-AzVM -Name $Name -ResourceGroupName $rg -ErrorAction SilentlyContinue)
}

# --- Accept Kali marketplace terms (required once per subscription) -----------
Write-LabStep "Accepting Kali Linux marketplace terms"
try {
    $terms = Get-AzMarketplaceTerms -Publisher $Lab.KaliImage.Publisher -Product $Lab.KaliImage.Offer -Name $Lab.KaliImage.Sku -ErrorAction Stop
    if (-not $terms.Accepted) {
        $terms | Set-AzMarketplaceTerms -Accept -ErrorAction Stop | Out-Null
        Write-Host "Kali terms accepted." -ForegroundColor DarkGray
    } else {
        Write-Host "Kali terms already accepted." -ForegroundColor DarkGray
    }
} catch {
    # Get-AzMarketplaceTerms throws when the agreement was never signed. Try a
    # direct accept, then fall back to the Azure CLI, which is the most reliable path.
    Write-Host "Marketplace cmdlet could not read terms ($($_.Exception.Message.Trim()))." -ForegroundColor DarkYellow
    Write-Host "Attempting direct acceptance via Azure CLI..." -ForegroundColor DarkYellow
    $azPath = (Get-Command az -ErrorAction SilentlyContinue)
    if ($azPath) {
        az vm image terms accept --publisher $Lab.KaliImage.Publisher --offer $Lab.KaliImage.Offer --plan $Lab.KaliImage.Sku 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Kali terms accepted via Azure CLI." -ForegroundColor DarkGray
        } else {
            throw "Could not accept Kali marketplace terms. Run manually: az vm image terms accept --publisher $($Lab.KaliImage.Publisher) --offer $($Lab.KaliImage.Offer) --plan $($Lab.KaliImage.Sku)"
        }
    } else {
        throw "Could not accept Kali marketplace terms and Azure CLI not found. Run: Get-AzMarketplaceTerms -Publisher $($Lab.KaliImage.Publisher) -Product $($Lab.KaliImage.Offer) -Name $($Lab.KaliImage.Sku) | Set-AzMarketplaceTerms -Accept"
    }
}

# --- VM 1: Windows 11 (Spoke1 / Subnet1) -------------------------------------
if (-not (Test-LabVmExists $Lab.Win11Vm)) {
    Write-LabStep "Creating Windows 11 VM '$($Lab.Win11Vm)'"
    $nic = New-LabNic -Name "$($Lab.Win11Vm)-nic" -SubnetId $spoke1Subnet1.Id -PrivateIp $Lab.Win11Ip
    $cfg = New-AzVMConfig -VMName $Lab.Win11Vm -VMSize $Lab.VmSize
    $cfg = Set-AzVMOperatingSystem -VM $cfg -Windows -ComputerName 'win11' -Credential $AdminCredential
    $cfg = Set-AzVMSourceImage -VM $cfg -PublisherName $Lab.Win11Image.Publisher -Offer $Lab.Win11Image.Offer -Skus $Lab.Win11Image.Sku -Version $Lab.Win11Image.Version
    $cfg = Add-AzVMNetworkInterface -VM $cfg -Id $nic.Id
    $cfg = Set-AzVMBootDiagnostic -VM $cfg -Disable
    New-AzVM -ResourceGroupName $rg -Location $loc -VM $cfg | Out-Null
} else { Write-Host "Win11 VM exists - skipping." -ForegroundColor DarkGray }

# --- VM 2: Kali Linux (Spoke1 / Subnet2) -------------------------------------
if (-not (Test-LabVmExists $Lab.KaliVm)) {
    Write-LabStep "Creating Kali Linux VM '$($Lab.KaliVm)'"
    $nic = New-LabNic -Name "$($Lab.KaliVm)-nic" -SubnetId $spoke1Subnet2.Id -PrivateIp $Lab.KaliIp
    # Kali is not a Trusted Launch-capable image; force Standard security type
    # (newer New-AzVM defaults to TrustedLaunch, which this image rejects).
    $cfg = New-AzVMConfig -VMName $Lab.KaliVm -VMSize $Lab.VmSize -SecurityType 'Standard'
    $cfg = Set-AzVMOperatingSystem -VM $cfg -Linux -ComputerName 'kali' -Credential $AdminCredential
    $cfg = Set-AzVMSourceImage -VM $cfg -PublisherName $Lab.KaliImage.Publisher -Offer $Lab.KaliImage.Offer -Skus $Lab.KaliImage.Sku -Version $Lab.KaliImage.Version
    $cfg = Set-AzVMPlan -VM $cfg -Name $Lab.KaliImage.Sku -Publisher $Lab.KaliImage.Publisher -Product $Lab.KaliImage.Offer
    $cfg = Add-AzVMNetworkInterface -VM $cfg -Id $nic.Id
    $cfg = Set-AzVMBootDiagnostic -VM $cfg -Disable
    New-AzVM -ResourceGroupName $rg -Location $loc -VM $cfg | Out-Null
} else { Write-Host "Kali VM exists - skipping." -ForegroundColor DarkGray }

# --- VM 3: Windows Server (Spoke2 / Subnet1) ---------------------------------
if (-not (Test-LabVmExists $Lab.WinSrvVm)) {
    Write-LabStep "Creating Windows Server VM '$($Lab.WinSrvVm)'"
    $nic = New-LabNic -Name "$($Lab.WinSrvVm)-nic" -SubnetId $spoke2Subnet1.Id -PrivateIp $Lab.WinSrvIp
    $cfg = New-AzVMConfig -VMName $Lab.WinSrvVm -VMSize $Lab.VmSize
    $cfg = Set-AzVMOperatingSystem -VM $cfg -Windows -ComputerName 'winsrv' -Credential $AdminCredential
    $cfg = Set-AzVMSourceImage -VM $cfg -PublisherName $Lab.WinSrvImage.Publisher -Offer $Lab.WinSrvImage.Offer -Skus $Lab.WinSrvImage.Sku -Version $Lab.WinSrvImage.Version
    $cfg = Add-AzVMNetworkInterface -VM $cfg -Id $nic.Id
    $cfg = Set-AzVMBootDiagnostic -VM $cfg -Disable
    New-AzVM -ResourceGroupName $rg -Location $loc -VM $cfg | Out-Null
} else { Write-Host "Win Server VM exists - skipping." -ForegroundColor DarkGray }

# --- Azure Bastion (hub) -----------------------------------------------------
Write-LabStep "Creating Azure Bastion '$($Lab.Bastion)' (Standard SKU - connects across peering)"
$bastion = Get-AzBastion -Name $Lab.Bastion -ResourceGroupName $rg -ErrorAction SilentlyContinue
if (-not $bastion) {
    $bastionPip = Get-AzPublicIpAddress -Name $Lab.BastionPip -ResourceGroupName $rg
    New-AzBastion -Name $Lab.Bastion -ResourceGroupName $rg `
        -PublicIpAddressId $bastionPip.Id -VirtualNetworkId $hub.Id -Sku 'Standard' | Out-Null
} else { Write-Host "Bastion exists - skipping." -ForegroundColor DarkGray }

# --- Checkpoint --------------------------------------------------------------
Get-AzVM -ResourceGroupName $rg | Select-Object Name, @{n='Size';e={$_.HardwareProfile.VmSize}} | Format-Table -AutoSize
Write-LabCheckpoint "Compute ready. Connect to VMs via Bastion (portal -> VM -> Connect -> Bastion). Proceed to 04-app-delivery.ps1"
