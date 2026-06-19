# Phase 1 Data Model: Azure Network Security Demo Lab Workshop

**Date**: 2026-06-18 | **Plan**: [plan.md](plan.md)

This lab has no application database. The "data model" is (a) the **configuration profile** that drives
every module and (b) the **resource entities** the lab provisions and their relationships. Field names
match the `$Global:Lab` hashtable in [`deploy/config.ps1`](../../deploy/config.ps1).

## Configuration profile (`$Global:Lab`)

| Field group | Key fields | Validation / rule |
|---|---|---|
| Identity | `Prefix`, `Suffix` | Short, deterministic; drive all resource names |
| Region | `Location` (default `westus`) | Single source; gated by `00-preflight` |
| Toggles | `EnableDdos` (false), `DeployFrontDoor`, `DeployAppGateway`, `DeployWebApp` | Booleans; control optional/cost-bearing stages |
| Compute | `VmSize` (`Standard_D2s_v3`), `Win11Image`, `KaliImage`, `WinSrvImage`, `WebAppContainerImage` | Image hashtables (Publisher/Offer/Sku/Version); validated per Principle I |
| Group | `ResourceGroup` (`rg-netsec-<suffix>`) | One RG holds the entire lab (enables one-step teardown) |
| Networking | `HubVnet`/`Spoke1Vnet`/`Spoke2Vnet`, subnet names, `*Prefix` address spaces, static VM IPs | CIDR layout below; reserved subnet names exact |
| Security | `FirewallName`, `FirewallPolicy`, `FirewallPip`, `Nsg1`, `Nsg2`, `RouteTable`, `DdosPlan` | Names deterministic; no Key Vault in core lab (see research Decision 3) |
| Compute names | `Win11Vm`, `KaliVm`, `WinSrvVm`, `Bastion`, `BastionPip`, `AdminUsername` | `AdminUsername=azureadmin`; password NOT stored |
| App delivery | `AppServicePlan`, `WebApp`, `AppGwName`, `AppGwPip`, `AppGwWafPolicy`, `FrontDoor*` | Front Door endpoint/WAF names alphanumeric |
| Monitoring | `Workspace` | One Log Analytics workspace receives all diagnostics |

### Address-space layout (CIDR)

| Network | Prefix | Subnets |
|---|---|---|
| Hub | `10.0.25.0/24` | `AzureFirewallSubnet 10.0.25.0/26`, `AGWAFSubnet 10.0.25.64/26`, `AzureBastionSubnet 10.0.25.128/26` |
| Spoke1 | `10.0.27.0/24` | `SPOKE1-SUBNET1 10.0.27.0/26` (Win11 `10.0.27.4`), `SPOKE1-SUBNET2 10.0.27.64/26` (Kali `10.0.27.68`) |
| Spoke2 | `10.0.28.0/24` | `SPOKE2-SUBNET1 10.0.28.0/26` (Win Server `10.0.28.4`) |

## Resource entities & relationships

```mermaid
erDiagram
    RESOURCE_GROUP ||--|| HUB_VNET : contains
    RESOURCE_GROUP ||--|| SPOKE1_VNET : contains
    RESOURCE_GROUP ||--|| SPOKE2_VNET : contains
    RESOURCE_GROUP ||--|| LOG_ANALYTICS : contains
    HUB_VNET ||--|| FIREWALL : hosts
    HUB_VNET ||--|| APP_GATEWAY : hosts
    HUB_VNET ||--|| BASTION : hosts
    FIREWALL ||--|| FIREWALL_POLICY : "governed by"
    FIREWALL_POLICY ||--|| IDPS : includes
    HUB_VNET ||--o{ SPOKE1_VNET : peers
    HUB_VNET ||--o{ SPOKE2_VNET : peers
    SPOKE1_VNET ||--|| WIN11_VM : hosts
    SPOKE1_VNET ||--|| KALI_VM : hosts
    SPOKE2_VNET ||--|| WINSRV_VM : hosts
    SPOKE1_VNET ||--|| NSG1 : "secured by"
    SPOKE2_VNET ||--|| NSG2 : "secured by"
    SPOKE1_VNET ||--|| ROUTE_TABLE : "routes via"
    SPOKE2_VNET ||--|| ROUTE_TABLE : "routes via"
    ROUTE_TABLE ||--|| FIREWALL : "next hop"
    FRONT_DOOR ||--|| APP_GATEWAY : "origin"
    APP_GATEWAY ||--|| WEB_APP : "backend"
    BASTION ||--o{ WIN11_VM : "admin access"
    BASTION ||--o{ KALI_VM : "admin access"
    BASTION ||--o{ WINSRV_VM : "admin access"
    FIREWALL ||--|| LOG_ANALYTICS : "diagnostics"
    APP_GATEWAY ||--|| LOG_ANALYTICS : "diagnostics"
    FRONT_DOOR ||--|| LOG_ANALYTICS : "diagnostics"

    %% ---- colour styling (groups entities by role) ----
    classDef edge     fill:#D6E4FF,stroke:#2B59C3,color:#0a1f4d;
    classDef security fill:#FFC9C9,stroke:#C0392B,color:#4d0000;
    classDef vm       fill:#E5D4FF,stroke:#7B3FBF,color:#2a0a4d;
    classDef net      fill:#FFE9B0,stroke:#C8901B,color:#3a2a00;
    classDef mon      fill:#C9F2D8,stroke:#2E9E5B,color:#03331a;

    class FRONT_DOOR,APP_GATEWAY,WEB_APP edge
    class FIREWALL,FIREWALL_POLICY,IDPS,NSG1,NSG2,ROUTE_TABLE,BASTION security
    class WIN11_VM,KALI_VM,WINSRV_VM vm
    class RESOURCE_GROUP,HUB_VNET,SPOKE1_VNET,SPOKE2_VNET net
    class LOG_ANALYTICS mon
```

> 🎨 **Colour key:** 🔵 web‑delivery edge (Front Door / App Gateway / web app) ·
> 🔴 security & access (Firewall / policy / IDPS / NSG / route table / Bastion) ·
> 🟣 lab VMs · 🟡 network containers (RG / VNets) · 🟢 monitoring (Log Analytics).

### State / lifecycle rules

- **Creation order** is fixed (Principle VI): RG → VNets/peering/PIPs → firewall/NSG/UDR → VMs/Bastion →
  WAF chain → monitoring. A resource is created only if absent (idempotent).
- **Forced tunneling**: spoke subnets associate `ROUTE_TABLE` whose `0.0.0.0/0` next hop is the
  firewall private IP (read dynamically after the firewall exists).
- **Deny-by-default**: each NSG allows Bastion RDP/SSH and intra-VNet, denies Internet inbound.
- **Teardown**: deleting `RESOURCE_GROUP` removes every entity above and stops billing.

## Key entity ↔ spec mapping

| Spec entity (spec.md) | Concrete resources |
|---|---|
| Hub network | `HUB_VNET` + firewall/gateway/bastion subnets |
| Spoke network | `SPOKE1_VNET`, `SPOKE2_VNET` + NSG + route table |
| Lab VM | `WIN11_VM`, `KALI_VM`, `WINSRV_VM` |
| Web protection chain | `FRONT_DOOR` → `APP_GATEWAY` → `WEB_APP` |
| Monitoring workspace | `LOG_ANALYTICS` |
| Configuration profile | `$Global:Lab` in `config.ps1` |
