# Implementation Plan: Azure Network Security Demo Lab Workshop

**Branch**: `001-netsec-demo-lab` (spec directory; git branch intentionally NOT created — see spec Assumptions) | **Date**: 2026-06-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-netsec-demo-lab/spec.md`

## Summary

Deliver a modernized Azure Network Security demonstration lab as a guided, checkpoint-gated
**Azure PowerShell** workshop in **West US**. The lab provisions a hub-and-spoke topology (1 hub + 2
spokes) with Azure Firewall Premium (IDPS), default-deny NSGs, forced-tunnel UDR, three Bastion-only
lab VMs, a layered web-protection chain (Front Door Premium WAF → Application Gateway WAFv2 → demo web
app), and centralized Log Analytics. The technical approach is a set of idempotent, parameterized
`Az` module scripts under `deploy/` driven by a single `config.ps1`, run in dependency order (00→05)
with a mandatory teardown — already implemented and now formalized, validated, and plan-traced against
the constitution. Microsoft Defender for Cloud and Microsoft Sentinel are out of scope.

## Technical Context

**Language/Version**: PowerShell 7+ (`Az` module, current GA)

**Primary Dependencies**: `Az.Accounts`, `Az.Resources`, `Az.Network`, `Az.Compute`,
`Az.OperationalInsights`, `Az.KeyVault`, `Az.Websites`, `Az.Cdn`, `Az.FrontDoor`

**Storage**: N/A (no application datastore). State lives in Azure Resource Manager; the only local
"data" is the `config.ps1` configuration profile (the `$Global:Lab` hashtable)

**Testing**: Manual checkpoint validation per module (Pester optional/future); idempotent re-run as the
regression check; `Get-Az*` assertions at each stage gate

**Target Platform**: Azure (West US, parameterized); operator workstation runs PowerShell 7+ on
Windows/macOS/Linux

**Project Type**: Infrastructure-as-scripts workshop (sequential deployment modules + README guide +
spec artifacts), not an application

**Performance Goals**: Full guided build completes within a half-day workshop window; Firewall Premium
and Application Gateway WAFv2 provisioning are the long poles (~10–15 min each)

**Constraints**: Single-region default (`westus`) and single resource group; no secrets in source
(credentials via `Get-Credential`); Bastion-only admin (no public RDP/SSH); default-deny networking;
premium-SKU cost disclosure up front; DDoS optional and default-off; mandatory teardown

**Scale/Scope**: 1 hub + 2 spoke VNets, 3 VMs, 1 firewall, 1 App Gateway, 1 Front Door profile, 1 web
app, 1 Log Analytics workspace; 9 deployment scripts + 1 config + README; audience is a single
facilitator/learner per subscription

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against the Azure Network Security Demo Lab Constitution v2.0.1.

### Initial gate (pre-Phase 0)

| # | Principle | How the plan satisfies it | Status |
|---|-----------|---------------------------|--------|
| I | Source Fidelity & Currency Validation | Topology preserved (hub + 2 spokes, firewall, WAF chain, Bastion, monitoring); Server 2019→2022 and Win10→Win11 modernized; deviations (Bastion in hub, Key Vault deferred with TLS inspection, Log Analytics in stage 5) documented in research.md | PASS |
| II | Microsoft Learn as Source of Truth | Cmdlet chains (Firewall Premium policy/IDPS, Front Door via `Az.Cdn` + `Az.FrontDoor` WAF, Bastion, App Gateway WAFv2) validated via Microsoft Learn MCP; citations in research.md | PASS |
| III | Region-Aware Deployment (West US) | `westus` is a single `config.ps1` variable; `00-preflight.ps1` gates region + `Get-AzComputeResourceSku` + `Get-AzVMUsage` before provisioning | PASS |
| IV | Azure PowerShell-First, Reproducible & Idempotent | `Az`-only scripts; deterministic prefix/suffix naming; create-if-absent idempotency; no secrets in source | PASS |
| V | Workshop-First Pedagogy | Each module has objective/prereqs/cmdlets/what-why/expected output/checkpoint; README walkthrough + teardown + cost disclosure | PASS |
| VI | Sequential, Checkpoint-Gated Deployment | Modules 00→05 in dependency order with `Write-LabCheckpoint` gates; `Deploy-All.ps1` pauses between stages; Bastion-only admin | PASS |
| VII | Secure-by-Default & Least-Privilege | Default-deny NSGs; UDR forces all egress through firewall; `Get-Credential` (no hard-coded secrets); diagnostics to Log Analytics; Juice Shop marked demo-only and isolated | PASS |

**Result**: PASS — no violations. Complexity Tracking not required.

**Out-of-scope confirmation**: Microsoft Defender for Cloud and Microsoft Sentinel are excluded, per
constitution intro and Principle I.

### Post-design re-check (after Phase 1)

Re-evaluated after producing research.md, data-model.md, contracts/modules.md, and quickstart.md. No new
components, services, or secrets were introduced by the design; the module contracts encode the
checkpoint gates (Principle VI) and the config schema centralizes the single-region parameter
(Principle III) and secret-free posture (Principle IV/VII). **Constitution Check still PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/001-netsec-demo-lab/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output — decisions, cmdlet validations, deviations
├── data-model.md        # Phase 1 output — config schema + resource entities/relationships
├── quickstart.md        # Phase 1 output — fastest path to a running lab
├── contracts/
│   └── modules.md       # Phase 1 output — module input/output/checkpoint contracts
├── checklists/
│   └── requirements.md  # Spec quality checklist (already created)
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
deploy/
├── config.ps1           # Single source of truth: region, naming, address spaces, images, toggles
├── 00-preflight.ps1     # Sign-in, region/SKU/quota gate, resource group
├── 01-networking.ps1    # Hub + 2 spoke VNets, subnets, peering, public IPs
├── 02-security-core.ps1 # Firewall Premium policy + IDPS, firewall, NSGs, UDR, optional DDoS
├── 03-compute.ps1       # 3 VMs (Get-Credential) + Azure Bastion
├── 04-app-delivery.ps1  # Web App + App Gateway WAFv2 + Front Door Premium + WAF
├── 05-monitoring.ps1    # Log Analytics workspace + diagnostic settings
├── 99-teardown.ps1      # Confirmed resource-group deletion
└── Deploy-All.ps1       # Checkpoint-gated orchestrator (stages 00→05)

README.md                # Workshop guide: architecture (Mermaid), cost, run steps, walkthrough
.specify/memory/constitution.md   # Governing constitution (v2.0.1)
```

**Structure Decision**: Infrastructure-as-scripts. There is no `src/`+`tests/` application layout
because the deliverable is a deployment workshop, not an app. The numbered `deploy/` scripts map 1:1 to
the constitution's Principle VI deployment stages; `config.ps1` is the single configuration surface; the
`specs/001-netsec-demo-lab/` tree holds the governing artifacts. This layout already exists in the
repository and is preserved by this plan.

## Complexity Tracking

> Not required — Constitution Check passed with no violations.
