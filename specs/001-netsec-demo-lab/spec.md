# Feature Specification: Azure Network Security Demo Lab Workshop

**Feature Branch**: `001-netsec-demo-lab` (spec directory; git branch intentionally NOT created — see Assumptions)

**Created**: 2026-06-18

**Status**: Draft

**Input**: User description: "Implement the feature specification based on the updated constitution. also adding workshop guidance on how to run through this workshop demo"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy the secure hub-and-spoke lab end-to-end (Priority: P1)

A workshop facilitator (or self-paced learner) opens the workshop, signs in to an Azure
subscription, and follows sequential, checkpoint-gated modules to stand up the complete
network-security lab: a hub virtual network with Azure Firewall Premium, two peered spoke
networks containing lab VMs, layered web protection (Application Gateway WAFv2 behind Azure
Front Door), centralized logging, and Bastion-based administration — all in the default region
(West US) using Azure PowerShell.

**Why this priority**: Without a reliably deployable lab there is nothing to teach. This is the
minimum viable product: a participant who completes only this story has a working, secure
reference environment.

**Independent Test**: Run modules 0→5 in order in a clean subscription and confirm each module's
checkpoint passes and the final environment matches the reference architecture (hub + 2 spokes,
firewall, WAF chain, monitoring), with no public RDP/SSH exposure.

**Acceptance Scenarios**:

1. **Given** a subscription with sufficient quota in West US, **When** the facilitator runs the
   pre-flight module, **Then** region/SKU/quota are validated and the resource group is created
   before any billable resource is provisioned.
2. **Given** the pre-flight checkpoint passed, **When** the networking and security modules run,
   **Then** three peered VNets exist and all spoke egress is forced through the Azure Firewall via
   user-defined routes.
3. **Given** the compute module completed, **When** the facilitator connects to a lab VM, **Then**
   access is only possible through Azure Bastion and never via a public IP on the VM.
4. **Given** any single module fails its checkpoint, **When** the facilitator inspects the output,
   **Then** the failure is surfaced before the next module begins (no silent cascade).

---

### User Story 2 - Demonstrate network-security controls in action (Priority: P2)

During the workshop, the facilitator runs a set of guided demonstration scenarios that prove each
control works: a web attack blocked by the WAF, malicious traffic flagged by the firewall's
intrusion detection, default-deny network segmentation between spokes, and forced-tunnel egress
through the firewall.

**Why this priority**: The lab's teaching value comes from *observing* the controls behave, not
just from their existence. This depends on Story 1 but delivers the core learning outcome.

**Independent Test**: With the lab deployed, execute each demo scenario from the workshop guide and
confirm the expected, observable result (blocked request, alert/log entry, denied connection,
routed path) appears in the relevant tool or log.

**Acceptance Scenarios**:

1. **Given** the deployed WAF chain, **When** a simulated OWASP-style malicious request is sent to
   the public endpoint, **Then** the request is blocked and the block is visible in WAF logs.
2. **Given** the firewall with intrusion detection enabled, **When** test traffic matching a
   signature traverses the firewall, **Then** an alert is recorded in the Log Analytics workspace.
3. **Given** the default-deny NSGs, **When** a learner attempts an unsanctioned spoke-to-spoke or
   Internet-inbound connection, **Then** the connection is denied.
4. **Given** centralized diagnostics, **When** the facilitator queries the workspace, **Then**
   firewall, App Gateway, and Front Door telemetry are present.

---

### User Story 3 - Control cost with clean teardown (Priority: P3)

After the session, the facilitator removes the entire lab in one reliable step so no premium-SKU
resources keep accruing cost, and understands the cost exposure before starting.

**Why this priority**: Premium Firewall, Front Door Premium, Bastion, and optional DDoS are
expensive; safe, complete cleanup is essential for a workshop but is not needed until the lab has
been built and demonstrated.

**Independent Test**: Run the teardown module and confirm the resource group and all contained
resources are removed and billing stops.

**Acceptance Scenarios**:

1. **Given** a deployed lab, **When** the facilitator runs teardown and confirms, **Then** the
   entire resource group is deleted.
2. **Given** the workshop introduction, **When** a participant reads the cost section, **Then** the
   premium-SKU cost implications and the default-off status of DDoS are stated up front.

---

### Edge Cases

- **Region/SKU/quota gap**: If a required VM size, image, or service SKU is unavailable (or quota is
  exhausted) in the target region, the pre-flight gate MUST stop the workshop with an actionable
  message rather than failing partway through provisioning.
- **Re-run / partial state**: If a module is re-run after a partial deployment, existing resources
  MUST be reused rather than duplicated or corrupted (idempotent behavior).
- **Marketplace terms**: If the Kali Linux image terms have not been accepted, the compute module
  MUST accept them automatically (or instruct the learner) rather than fail opaquely.
- **Stale reference values**: If a legacy image URN, SKU, or cmdlet parameter from the original lab
  is no longer valid, it MUST be replaced with the current Microsoft-documented equivalent.
- **Missing credentials**: VM admin credentials MUST be collected securely at runtime; the workshop
  MUST never embed a password in source.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The workshop MUST be delivered as sequential, dependency-ordered modules, each with a
  learning objective, prerequisites, the exact Azure PowerShell cmdlets, a "what/why" explanation,
  expected output, and a validation checkpoint.
- **FR-002**: A pre-flight module MUST validate region, VM SKU availability, and compute quota in the
  target region, and create the resource group, before any billable resource is provisioned.
- **FR-003**: The lab MUST provision a hub-and-spoke topology of one hub and two spoke virtual
  networks with peering, matching the reference architecture.
- **FR-004**: The lab MUST deploy Azure Firewall Premium with a firewall policy and intrusion
  detection, and force all spoke egress through the firewall via user-defined routes.
- **FR-005**: Network Security Groups MUST enforce a default-deny posture, permitting only the flows
  each scenario requires.
- **FR-006**: Administrative access to all lab VMs MUST be via Azure Bastion only; no lab VM may have
  a public IP or public RDP/SSH exposure.
- **FR-007**: The lab MUST deploy layered web protection: a web application behind Application Gateway
  WAFv2 (Prevention mode) behind Azure Front Door with WAF.
- **FR-008**: The lab MUST provision three lab VMs using current, supported images (a current Windows
  client, a Kali Linux image, and a current Windows Server), with image versions validated against
  current Microsoft documentation.
- **FR-009**: Diagnostic logging MUST be enabled and routed to a central Log Analytics workspace for
  the firewall, Application Gateway, and Front Door.
- **FR-010**: The region MUST be a single configurable parameter, defaulting to West US, never
  hard-coded per resource.
- **FR-011**: Resource naming MUST be deterministic (prefix/suffix) and modules MUST be idempotent
  where the platform allows, so re-running does not duplicate or corrupt resources.
- **FR-012**: No secrets (passwords, tokens, certificates) may appear in source; VM credentials MUST
  be supplied securely at runtime.
- **FR-013**: The workshop MUST surface estimated cost and premium-SKU implications up front, with
  DDoS Protection defaulting to off.
- **FR-014**: A teardown module MUST allow complete deletion of the lab in one reliable step.
- **FR-015**: The workshop MUST include a guided walkthrough describing how to run the demonstration
  scenarios (web attack blocked by WAF, firewall intrusion-detection alert, default-deny segmentation,
  forced-tunnel egress) and how to observe the expected results.
- **FR-016**: Microsoft Defender for Cloud and Microsoft Sentinel MUST NOT be part of the lab scope.
- **FR-017**: Every deviation from the reference lab (e.g., placing Bastion in the hub, modernizing
  Server 2019→2022) MUST be documented with a short justification.

### Key Entities *(include if feature involves data)*

- **Hub network**: The central virtual network hosting shared security services (firewall, gateway
  subnet, Bastion); peered to each spoke.
- **Spoke network**: A workload virtual network containing lab VMs; routes egress through the hub
  firewall and is segmented by NSGs.
- **Lab VM**: A demonstration virtual machine (Windows client, Kali Linux, or Windows Server) reached
  only through Bastion.
- **Web protection chain**: The ordered path Internet → Front Door (WAF) → Application Gateway (WAF) →
  demo web app.
- **Monitoring workspace**: The central Log Analytics workspace receiving diagnostic telemetry.
- **Configuration profile**: The single source of truth for region, naming, address spaces, image
  selections, and feature toggles.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A facilitator can deploy the complete lab from a clean subscription by following the
  modules in order, with every module checkpoint passing on the first run in a correctly quota'd
  subscription.
- **SC-002**: 100% of lab VMs are reachable only through Bastion; zero lab VMs expose a public IP or
  public RDP/SSH.
- **SC-003**: All four demonstration scenarios (WAF block, firewall alert, segmentation deny, forced
  tunnel) produce their expected, observable result.
- **SC-004**: A facilitator can fully remove the lab and stop billing in a single teardown step.
- **SC-005**: Cost and premium-SKU implications are visible before any resource is created, and DDoS
  defaults to off.
- **SC-006**: A first-time participant can complete the end-to-end build within a typical workshop
  session window (about half a day), including reading the explanations.
- **SC-007**: Zero secrets are present in the workshop source artifacts.

## Assumptions

- **Audience**: Workshop facilitators and learners with basic Azure familiarity and rights to create
  the listed resources in a subscription with adequate quota in West US.
- **Tooling**: Participants use PowerShell 7+ with the Az module; the walkthrough is the source of
  truth (portal/CLI are optional reference only).
- **Git isolation**: The `before_specify` git hook (feature-branch creation) was intentionally **not**
  executed because this project folder is nested inside a larger home-directory Git repository wired
  to a live remote; running git operations here risks committing unrelated files. The spec directory
  was created directly. The project still needs its own isolated repository before any commit/push.
- **Scope boundary**: Microsoft Defender for Cloud and Microsoft Sentinel are out of scope by design.
- **Deviations from reference**: Azure Bastion is placed in the hub (reaches all spokes via peering),
  and legacy OS images are modernized to current supported versions; these are documented per FR-017.
- **Cost**: Premium SKUs incur real cost; DDoS Protection is optional and defaults to off.
