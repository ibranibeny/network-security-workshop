# Module Contracts: Azure Network Security Demo Lab Workshop

**Date**: 2026-06-18 | **Plan**: [../plan.md](../plan.md)

The "interfaces" this project exposes are its **deployment modules**. Each module is a CLI-style
contract: a learner runs it from `deploy/` with optional inputs, it mutates Azure state, and it must
satisfy a **checkpoint** (the postcondition) before the next module may start (Constitution Principle
VI). All modules dot-source `config.ps1` and are idempotent (create-if-absent).

## Conventions

- **Invocation**: `./<module>.ps1` from the `deploy/` folder, PowerShell 7+, signed in via `Az`.
- **Shared input**: `$Global:Lab` from `config.ps1`.
- **Checkpoint signal**: `Write-LabCheckpoint` prints the postcondition; failure raises (stops the run).
- **Idempotency**: re-running MUST NOT duplicate or corrupt resources.

## `00-preflight.ps1`

| Aspect | Contract |
|---|---|
| Inputs | `config.ps1`; interactive `Connect-AzAccount` if no context |
| Preconditions | Az modules installed; PowerShell 7+ |
| Actions | Verify modules; sign in; validate region (`Get-AzLocation`), VM SKU (`Get-AzComputeResourceSku`), quota (`Get-AzVMUsage`); create resource group |
| Postcondition (checkpoint) | Resource group exists in `westus`; region/SKU/quota validated |
| Failure modes | Missing module → throw; region/SKU unavailable → throw; low quota → warn |

## `01-networking.ps1`

| Aspect | Contract |
|---|---|
| Preconditions | `00` checkpoint passed |
| Actions | Create hub + 2 spoke VNets + subnets; peer hub↔spoke1, hub↔spoke2; create firewall/bastion/appgw public IPs |
| Postcondition | 3 peered VNets; required public IPs present |
| Failure modes | Address overlap → throw; peering name collision handled by guard |

## `02-security-core.ps1`

| Aspect | Contract |
|---|---|
| Preconditions | `01` checkpoint passed |
| Actions | (optional) DDoS plan; Firewall Policy Premium + IDPS Alert; Azure Firewall Premium; rule collections (spoke admin + FQDN); NSG1/NSG2 (deny-by-default); route table `0.0.0.0/0`→firewall; associate NSG + UDR to spoke subnets |
| Postcondition | Firewall Premium deployed; private IP printed; spokes carry NSG + UDR |
| Failure modes | Firewall provisioning timeout → throw; missing `AzureFirewallSubnet` → throw |

## `03-compute.ps1`

| Aspect | Contract |
|---|---|
| Inputs | optional `-AdminCredential`; otherwise `Get-Credential` prompt |
| Preconditions | `02` checkpoint passed |
| Actions | Accept Kali marketplace terms; create NICs (no public IP); create Win11, Kali, Win Server VMs; deploy Bastion (Standard) in hub |
| Postcondition | 3 VMs running; reachable only via Bastion |
| Failure modes | Image unavailable → throw (verify with `Get-AzVMImageSku`); weak password → Azure validation error |

## `04-app-delivery.ps1`

| Aspect | Contract |
|---|---|
| Preconditions | `03` checkpoint passed |
| Actions | (toggle) App Service plan + Web App (Juice Shop container); App Gateway WAFv2 + OWASP 3.2 Prevention policy; Front Door Premium profile/endpoint/origin-group/origin/route + Front Door WAF |
| Postcondition | Front Door endpoint reachable; layered WAF chain in place |
| Failure modes | App Gateway provisioning timeout → throw; origin misconfig → health probe fails (surfaced) |

## `05-monitoring.ps1`

| Aspect | Contract |
|---|---|
| Preconditions | `04` checkpoint passed |
| Actions | Create Log Analytics workspace; enable diagnostic settings for firewall, App Gateway, Front Door, firewall public IP |
| Postcondition | Diagnostics flowing to the workspace |
| Failure modes | Resource not yet ready → diagnostic category query skipped gracefully |

## `99-teardown.ps1`

| Aspect | Contract |
|---|---|
| Inputs | optional `-Force`; otherwise type-to-confirm RG name |
| Preconditions | none (safe anytime) |
| Actions | List resources; confirm; `Remove-AzResourceGroup -AsJob` |
| Postcondition | Resource group deletion started; billing stops on completion |
| Failure modes | Wrong confirmation → abort (no deletion) |

## `Deploy-All.ps1`

| Aspect | Contract |
|---|---|
| Inputs | optional `-AdminCredential`, `-NoPause` |
| Actions | Run `00`→`05` in order; pause at each checkpoint unless `-NoPause`; stop on first failure |
| Postcondition | All six checkpoints passed; full lab deployed |

## Contract ↔ requirement traceability

| Module | Primary FRs (spec.md) |
|---|---|
| `00-preflight` | FR-002, FR-010 |
| `01-networking` | FR-003 |
| `02-security-core` | FR-004, FR-005, FR-013 (DDoS toggle) |
| `03-compute` | FR-006, FR-008, FR-012 |
| `04-app-delivery` | FR-007 |
| `05-monitoring` | FR-009, FR-016 |
| `99-teardown` | FR-014 |
| `Deploy-All` | FR-001, FR-011 |
| README walkthrough | FR-013, FR-015, FR-017 |
