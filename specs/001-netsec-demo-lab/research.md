# Phase 0 Research: Azure Network Security Demo Lab Workshop

**Date**: 2026-06-18 | **Plan**: [plan.md](plan.md) | **Spec**: [spec.md](spec.md)

This document resolves the technical unknowns behind the deployment scripts. Each decision was
validated against current Microsoft Learn documentation (Constitution Principle II). There are no
remaining `NEEDS CLARIFICATION` items.

## Decision 1 — Deployment tooling: Azure PowerShell (`Az` module)

- **Decision**: Use the `Az` PowerShell module on PowerShell 7+ as the sole authoritative deployment
  mechanism.
- **Rationale**: Constitution Principle IV and the Azure Network Security PoC Part 2 reference both use
  Azure PowerShell. Scripts are diff-able, parameterizable, and idempotent.
- **Alternatives considered**: Azure CLI (rejected — not the reference tooling); raw ARM/Bicep
  (rejected — less suited to a step-by-step teaching walkthrough, though valid for production IaC);
  portal click-through (rejected — not reproducible).

## Decision 2 — Region: West US, gated, single variable

- **Decision**: Default to `westus`, exposed as one `config.ps1` variable; enforce a pre-flight
  availability gate before any billable resource.
- **Rationale**: Principle III. West US is a recommended region with broad service availability, but
  subscription quota and per-SKU availability still vary, so `00-preflight.ps1` runs `Get-AzLocation`,
  `Get-AzComputeResourceSku -Location westus`, and `Get-AzVMUsage -Location westus`.
- **Alternatives considered**: Indonesia Central (rejected in v2.0.0 — alternate region, no AZs,
  demand-driven SKUs); hard-coding region per resource (rejected — prevents retargeting).

## Decision 3 — Azure Firewall Premium + IDPS

- **Decision**: Create a Firewall Policy with `-SkuTier Premium`, attach
  `New-AzFirewallPolicyIntrusionDetection -Mode Alert`, then deploy the firewall with
  `New-AzFirewall -SkuName AZFW_VNet -SkuTier Premium -FirewallPolicyId -VirtualNetworkName -PublicIpName`.
- **Rationale**: Principle I keeps Firewall Premium from the reference; IDPS in Alert mode is the
  Premium-tier demonstrator. Validated via Microsoft Learn (Azure Firewall Premium PowerShell).
- **Alternatives considered**: TLS inspection as the Premium demonstrator (deferred — requires Key
  Vault intermediate-CA certificate setup; documented as an optional advanced add-on to keep the core
  workshop friction-low); Firewall Standard (rejected — would not demonstrate Premium IDPS).
- **Documented deviation (Principle I & VII)**: Because TLS inspection is deferred, **no Key Vault is
  provisioned in the core lab**. Constitution Principle I/VI/VII reference Key Vault only as the backing
  store for firewall TLS-inspection certificates; that mandate is conditional on TLS inspection being
  enabled. Key Vault (and the `Az.KeyVault` module) are therefore intentionally omitted; they become
  required only if a learner enables the optional TLS-inspection add-on.

## Decision 4 — Front Door Standard/Premium via `Az.Cdn` (+ `Az.FrontDoor` for WAF)

- **Decision**: Use `New-AzFrontDoorCdnProfile -SkuName Premium_AzureFrontDoor -Location Global`, then
  `New-AzFrontDoorCdnEndpoint`, `…OriginGroup`, `…Origin`, `…Route`; attach a WAF policy via
  `Az.FrontDoor` (`New-AzFrontDoorWafPolicy -Sku Premium_AzureFrontDoor -Mode Prevention` with
  `Microsoft_DefaultRuleSet`).
- **Rationale**: Principle I requires the modern Front Door Standard/Premium (not classic). The control
  plane lives in `Az.Cdn`; the managed WAF policy object for Premium lives in `Az.FrontDoor`. Both
  validated via Microsoft Learn.
- **Alternatives considered**: Classic Azure Front Door / `Az.FrontDoor` profile cmdlets (rejected —
  legacy); Front Door Standard (acceptable, but Premium enables managed WAF rule sets used in the demo).

## Decision 5 — Application Gateway WAFv2 (Prevention)

- **Decision**: Deploy `New-AzApplicationGateway` with `-Sku WAF_v2` and attach a WAF policy
  (`New-AzApplicationGatewayFirewallPolicy`) using OWASP managed rule set 3.2 in Prevention mode.
- **Rationale**: Principles I and VII — layered L7 protection with default-deny WAF behavior.
- **Alternatives considered**: WAF on the gateway config block only (rejected — separate WAF policy
  object is the current recommended pattern and reusable).

## Decision 6 — Azure Bastion placement in the HUB (documented deviation)

- **Decision**: Place `AzureBastionSubnet` (`10.0.25.128/26`) in the hub VNet and deploy
  `New-AzBastion -Sku Standard` with a Standard static public IP; Bastion reaches spoke VMs over
  peering.
- **Rationale**: Principle VI mandates Bastion-only admin. Putting Bastion in the hub is the standard
  hub-spoke pattern and avoids a Bastion per spoke. This deviates from the original template (which
  placed Bastion in a spoke) and is recorded here and in the README per Principle I.
- **Alternatives considered**: Bastion in spoke2 (reference layout — rejected for the cleaner hub
  pattern); public IPs on VMs (prohibited by Principle VI/VII).

## Decision 7 — Lab VM images (modernized, validated)

- **Decision**: Windows 11 client (`MicrosoftWindowsDesktop/windows-11`), Kali Linux
  (`kali-linux/kali/kali`, marketplace terms accepted via `Set-AzMarketplaceTerms`), Windows Server
  2022 (`MicrosoftWindowsServer/WindowsServer/2022-datacenter-azure-edition`). VM size
  `Standard_D2s_v3`. All image SKUs are `config.ps1` variables.
- **Rationale**: Principle I modernizes Win10→Win11 and Server 2019→2022. Image SKUs drift, so they are
  parameterized and the README instructs verifying with `Get-AzVMImageSku` if a deploy reports an
  unavailable image.
- **Alternatives considered**: Pinned image versions (rejected — `latest` plus a documented
  verification step is more resilient for a workshop run over time).

## Decision 8 — Credentials & secrets handling

- **Decision**: Collect the VM local-admin credential at runtime via
  `Get-Credential -UserName azureadmin`; never store secrets in source.
- **Rationale**: Principle IV/VII. Supports non-interactive automation via an optional
  `-AdminCredential` parameter on `03-compute.ps1` / `Deploy-All.ps1`.
- **Alternatives considered**: Hard-coded password (prohibited); Key Vault-generated VM password
  (valid future enhancement; deferred to keep the first run simple).

## Decision 9 — Idempotency & naming

- **Decision**: Deterministic names from `prefix`/`suffix` (e.g. `NS-…-demo`); every resource is
  created only if `Get-Az*` returns nothing.
- **Rationale**: Principle IV — re-running a module must not duplicate or corrupt resources.
- **Alternatives considered**: Random suffixes (rejected — non-deterministic, harder to teach/clean up).

## Decision 10 — Demo web app: OWASP Juice Shop, isolated

- **Decision**: Run `bkimminich/juice-shop` as a Linux container on App Service behind the WAF chain,
  clearly labeled demo-only.
- **Rationale**: Principle VII — provides a realistic but contained WAF target without becoming a real
  attack surface beyond the lab.
- **Alternatives considered**: A custom vulnerable app (rejected — Juice Shop is well-known and
  purpose-built for security demos).

## Cross-cutting: out of scope

Microsoft Defender for Cloud and Microsoft Sentinel are intentionally excluded (constitution v2.0.x),
matching the PoC Part 2 reference environment. Monitoring is limited to a Log Analytics workspace plus
diagnostic settings.

## Cross-cutting: Log Analytics staging (documented deviation)

Constitution Principle VI lists Log Analytics under the stage-0 pre-flight grouping. In the
implementation the workspace is created in **stage 5 (`05-monitoring.ps1`)** instead, so that
diagnostic settings can be wired immediately after all telemetry-producing resources (firewall, WAF,
DDoS) exist. This ordering deviation keeps the dependency graph clean and is recorded here per
Principle I; pre-flight (`00-preflight.ps1`) still performs login, region/SKU/quota validation, and
resource-group creation.
