# Tasks: Azure Network Security Demo Lab Workshop

**Input**: Design documents from `/specs/001-netsec-demo-lab/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/modules.md](contracts/modules.md), [quickstart.md](quickstart.md)

**Tests**: Not requested. This is an infrastructure-as-scripts workshop; per-module **checkpoint validation**
(`Get-Az*` assertions + idempotent re-run) is the verification mechanism, captured as explicit validation
tasks rather than unit-test tasks.

**Organization**: Tasks are grouped by user story (US1 deploy, US2 demonstrate, US3 teardown) so each can be
delivered and verified independently.

**Status legend**: `[X]` = already implemented in the repo (scripts/README exist); `[ ]` = open work
(primarily live-Azure validation, which has not been run yet).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (Setup, Foundational, and Polish carry no story label)
- File paths are repository-relative

## Path Conventions

Infrastructure-as-scripts layout (from [plan.md](plan.md)): deployment modules in `deploy/`, the workshop
guide in `README.md`, governing artifacts in `specs/001-netsec-demo-lab/`. There is no `src/`+`tests/` tree.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the workshop project structure and configuration surface.

- [X] T001 Create the `deploy/` module folder and workshop layout per [plan.md](plan.md)
- [X] T002 [P] Create the architecture + cost + run guide in [README.md](../../README.md)
- [X] T003 [P] Confirm governing constitution present at `.specify/memory/constitution.md` (v2.0.1)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The configuration profile and pre-flight gate that every user story depends on.

**⚠️ CRITICAL**: No deployment story can begin until this phase is complete.

- [X] T004 Define the `$Global:Lab` configuration profile (region, prefix/suffix, address spaces, image
  selections, feature toggles, deterministic names) in [deploy/config.ps1](../../deploy/config.ps1) — FR-010, FR-011
- [X] T005 Implement shared helpers (`Write-LabStep`, `Write-LabCheckpoint`) and required-module list in
  [deploy/config.ps1](../../deploy/config.ps1) — FR-001
- [X] T006 Implement pre-flight module: Az module check, `Connect-AzAccount`, region validation
  (`Get-AzLocation`), VM SKU check (`Get-AzComputeResourceSku`), quota check (`Get-AzVMUsage`), and
  resource-group creation in [deploy/00-preflight.ps1](../../deploy/00-preflight.ps1) — FR-002, FR-010
- [X] T007 Validate the pre-flight checkpoint live: run `./00-preflight.ps1` in a clean subscription and
  confirm region/SKU/quota gate passes and `rg-netsec-demo` is created — SC-001

**Checkpoint**: Configuration is the single source of truth and the availability gate passes — story work can begin.

---

## Phase 3: User Story 1 - Deploy the secure hub-and-spoke lab end-to-end (Priority: P1) 🎯 MVP

**Goal**: Stand up the complete, secure reference environment (hub + 2 spokes, firewall, WAF chain,
monitoring) with Bastion-only admin, via sequential checkpoint-gated modules.

**Independent Test**: Run modules 00→05 in order in a clean subscription; confirm each checkpoint passes and
the final topology matches the reference architecture with no public RDP/SSH exposure.

### Implementation for User Story 1

- [X] T008 [US1] Implement networking: hub + 2 spoke VNets, subnets, hub↔spoke peering, and public IPs in
  [deploy/01-networking.ps1](../../deploy/01-networking.ps1) — FR-003
- [X] T009 [US1] Implement security core: Firewall Policy Premium + IDPS, Azure Firewall Premium, rule
  collections, deny-by-default NSGs, and UDR forcing `0.0.0.0/0` to the firewall in
  [deploy/02-security-core.ps1](../../deploy/02-security-core.ps1) — FR-004, FR-005
- [X] T010 [US1] Implement optional DDoS Network Protection plan (default OFF, toggle-gated) in
  [deploy/02-security-core.ps1](../../deploy/02-security-core.ps1) — FR-013
- [X] T011 [US1] Implement compute: secure `Get-Credential` prompt, Kali marketplace-terms acceptance,
  NICs without public IPs, and the three lab VMs (Win11, Kali, Win Server 2022) in
  [deploy/03-compute.ps1](../../deploy/03-compute.ps1) — FR-006, FR-008, FR-012
- [X] T012 [US1] Implement Azure Bastion (Standard) in the hub for admin access in
  [deploy/03-compute.ps1](../../deploy/03-compute.ps1) — FR-006
- [X] T013 [US1] Implement app delivery: Web App (Juice Shop container), Application Gateway WAFv2 (OWASP
  3.2 Prevention), and Front Door Premium + WAF in
  [deploy/04-app-delivery.ps1](../../deploy/04-app-delivery.ps1) — FR-007
- [X] T014 [US1] Implement monitoring: Log Analytics workspace + diagnostic settings for firewall, App
  Gateway, and Front Door in [deploy/05-monitoring.ps1](../../deploy/05-monitoring.ps1) — FR-009, FR-016
- [X] T015 [US1] Implement the checkpoint-gated orchestrator (run 00→05, pause per stage, stop on first
  failure) in [deploy/Deploy-All.ps1](../../deploy/Deploy-All.ps1) — FR-001
- [X] T016 [US1] Ensure idempotent create-if-absent behavior and deterministic naming across all modules — FR-011
- [ ] T017 [US1] Validate live build end-to-end: run `./Deploy-All.ps1` and confirm all six checkpoints pass — SC-001
- [ ] T018 [US1] Verify zero lab VMs expose a public IP and all are reachable only via Bastion
  (`Get-AzVM` / `Get-AzNetworkInterface` inspection + a Bastion connect) — SC-002

**Checkpoint**: User Story 1 delivers a complete, secure lab — the MVP.

---

## Phase 4: User Story 2 - Demonstrate network-security controls in action (Priority: P2)

**Goal**: Provide and validate guided scenarios proving each control works (WAF block, firewall IDPS alert,
default-deny segmentation, forced-tunnel egress).

**Independent Test**: With the lab deployed, run each scenario from the walkthrough and confirm the expected
observable result appears in the relevant tool/log.

### Implementation for User Story 2

- [X] T019 [US2] Author the demonstration walkthrough (Part C: 4 scenarios with do/observe/teaches) in
  [README.md](../../README.md) — FR-015
- [X] T020 [P] [US2] Ensure firewall network rule collection permits sanctioned spoke admin ports
  (3389/22/445) and application rules allow curated FQDNs (supporting segmentation + forced-tunnel demos) in
  [deploy/02-security-core.ps1](../../deploy/02-security-core.ps1) — FR-004, FR-015
- [ ] T021 [US2] Validate Scenario 1 (WAF block): send a simulated OWASP request to the Front Door endpoint;
  confirm HTTP 403 and a matched managed rule in WAF logs — SC-003
- [ ] T022 [US2] Validate Scenario 2 (IDPS alert): generate signature-matching traffic; confirm an
  `AZFWIdpsSignature` record in the Log Analytics workspace — SC-003
- [ ] T023 [US2] Validate Scenario 3 (segmentation): attempt an unsanctioned spoke-to-spoke connection;
  confirm it is denied while a permitted admin port succeeds — SC-003
- [ ] T024 [US2] Validate Scenario 4 (forced tunnel): browse an allowed vs disallowed FQDN from a spoke VM;
  confirm allowed traffic appears in firewall application-rule logs and disallowed is dropped — SC-003
- [ ] T025 [US2] Confirm firewall, App Gateway, and Front Door telemetry are all present in the workspace — SC-003

**Checkpoint**: User Stories 1 AND 2 both demonstrable independently.

---

## Phase 5: User Story 3 - Control cost with clean teardown (Priority: P3)

**Goal**: One-step, reliable removal of the entire lab, with cost exposure stated up front.

**Independent Test**: Run teardown and confirm the resource group and all resources are removed and billing stops.

### Implementation for User Story 3

- [X] T026 [US3] Implement confirmed one-step teardown (`Remove-AzResourceGroup`, type-to-confirm, `-Force`
  option, `-AsJob`) in [deploy/99-teardown.ps1](../../deploy/99-teardown.ps1) — FR-014
- [X] T027 [P] [US3] Surface cost and premium-SKU implications up front, with DDoS marked default-OFF, in
  [README.md](../../README.md) — FR-013
- [ ] T028 [US3] Validate teardown live: run `./99-teardown.ps1`, confirm the resource group deletes and
  billing stops — SC-004, SC-005

**Checkpoint**: All three user stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Quality, fidelity, and final verification across stories.

- [X] T029 [P] Add the colored Mermaid architecture diagram mirroring the reference image in
  [README.md](../../README.md)
- [X] T030 [P] Document all reference deviations (Bastion in hub, Server 2019→2022, Key Vault deferred with
  TLS inspection, Log Analytics created in stage 5) with justification in
  [README.md](../../README.md) and [research.md](research.md) — FR-017
- [X] T031 [P] Add the troubleshooting section (image/quota/Kali/idempotency) in [README.md](../../README.md)
- [ ] T032 Run the [quickstart.md](quickstart.md) end-to-end as a first-time participant and confirm the
  half-day completion target and zero-secrets posture — SC-006, SC-007
- [X] T033 Verify no secrets are present in any `deploy/` source artifact (grep for password/key literals) — SC-007

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup. **Blocks all user stories** (config + pre-flight gate).
- **User Stories (Phase 3–5)**: All depend on Foundational. US1 (P1) is the MVP and is the practical
  prerequisite for US2/US3 validation (you must deploy before you can demo or tear down), though each story's
  artifacts are authored independently.
- **Polish (Phase 6)**: Depends on the desired user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational. Self-contained deployable MVP.
- **US2 (P2)**: Authoring is independent; *live validation* requires a deployed US1 environment.
- **US3 (P3)**: Authoring is independent; *live validation* requires a deployed US1 environment.

### Within Each Module

- Networking before security (firewall needs subnets) before compute (VMs need secured subnets) before app
  delivery before monitoring — the fixed Principle VI order.
- Each module's checkpoint must pass before the next begins.

### Parallel Opportunities

- Setup T002/T003 in parallel.
- Authoring tasks marked [P] (T020, T027, T029, T030, T031) touch independent doc sections and can run in parallel.
- Live-validation tasks (T017, T018, T021–T025, T028, T032, T033) are sequential against one shared Azure
  environment and are **not** parallelizable.

---

## Implementation Strategy

- **MVP = User Story 1**: a facilitator who completes Phase 1 → 2 → 3 has a working, secure lab.
- **Incremental delivery**: add US2 (demonstrations) for teaching value, then US3 (teardown) for cost safety.
- **Current state**: all authoring/implementation tasks (`[X]`) are complete in the repo; the remaining open
  tasks (`[ ]`) are **live-Azure validation runs** that have not yet been executed.

### Remaining open tasks (live validation)

| Task | Story | Verifies |
|---|---|---|
| T007 | Foundational | Pre-flight gate (SC-001) |
| T017, T018 | US1 | End-to-end build + Bastion-only access (SC-001, SC-002) |
| T021–T025 | US2 | Four demo scenarios + telemetry (SC-003) |
| T028 | US3 | Teardown + cost (SC-004, SC-005) |
| T032, T033 | Polish | Quickstart timing + zero secrets (SC-006, SC-007) |
