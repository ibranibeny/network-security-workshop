# Quickstart: Azure Network Security Demo Lab Workshop

**Date**: 2026-06-18 | **Plan**: [plan.md](plan.md)

The fastest path from zero to a running lab. For the full guided experience (talking points + demo
scenarios), use the [workshop walkthrough in the README](../../README.md#workshop-walkthrough).

## Prerequisites

- PowerShell 7+ and the `Az` module: `Install-Module Az -Scope CurrentUser`
- An Azure subscription with quota for **≥ 6 vCPUs** of `Standard_D2s_v3` in `westus`
- Rights to create the lab resources

## 1. Configure

Open [`deploy/config.ps1`](../../deploy/config.ps1) and edit the **EDIT ME** block:

```powershell
$Prefix   = 'NS'      # resource name prefix
$Suffix   = 'demo'    # uniqueness suffix
$Location = 'westus'  # default region (single source of truth)
$EnableDdos = $false  # keep OFF unless you intend the ~$2,944/mo charge
```

## 2. Deploy (guided, recommended)

```powershell
cd deploy
./Deploy-All.ps1            # pauses at each checkpoint
```

…or run one stage at a time:

```powershell
cd deploy
./00-preflight.ps1     # sign in + region/SKU/quota gate + resource group
./01-networking.ps1    # hub + 2 spokes, peering, public IPs
./02-security-core.ps1 # Firewall Premium + IDPS, NSGs, UDR, (optional DDoS)
./03-compute.ps1       # 3 VMs (prompts for VM password) + Bastion
./04-app-delivery.ps1  # Web App + App Gateway WAFv2 + Front Door Premium
./05-monitoring.ps1    # Log Analytics + diagnostic settings
```

Unattended:

```powershell
$cred = Get-Credential azureadmin
./Deploy-All.ps1 -AdminCredential $cred -NoPause
```

## 3. Validate each checkpoint

| After | Confirm |
|---|---|
| `00` | `Get-AzResourceGroup -Name rg-netsec-demo` returns the group in `westus` |
| `01` | `Get-AzVirtualNetwork -ResourceGroupName rg-netsec-demo` lists 3 peered VNets |
| `02` | `Get-AzFirewall -ResourceGroupName rg-netsec-demo` shows Premium + a private IP |
| `03` | `Get-AzVM -ResourceGroupName rg-netsec-demo` lists 3 running VMs (no public IPs) |
| `04` | Front Door endpoint URL (printed by `04`) responds |
| `05` | `Get-AzOperationalInsightsWorkspace` exists and diagnostics are configured |

## 4. Connect to a VM

Portal → the VM → **Connect → Bastion** (there is no public RDP/SSH). Username `azureadmin`, password
from step 2.

## 5. Tear down (always)

```powershell
cd deploy
./99-teardown.ps1          # type the RG name to confirm; deletes everything, stops billing
```

## Troubleshooting

- **Image not found** → `Get-AzVMImageSku -Location westus -PublisherName <pub> -Offer <offer>`, update
  the SKU in `config.ps1`.
- **Quota error** → request an increase or lower `$VmSize`.
- **Kali fails** → `03-compute.ps1` accepts marketplace terms automatically; re-run if interrupted.
- **Re-running is safe** — every resource is created only if it does not already exist.
