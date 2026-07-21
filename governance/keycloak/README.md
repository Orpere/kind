# Keycloak Deployment — Kustomize + Config-as-Code

This directory defines a **declarative Keycloak deployment** using Kustomize, with all
Identity and Access Management (IAM) configuration — realms, users, roles, groups,
and policies — managed as code via Keycloak's realm import feature.

---

## 🗺️ Infrastructure Architecture Overview

```mermaid
graph TB
    subgraph "💻 Local Machine (Docker)"
        subgraph "🐳 kind cluster-a"
            A_CIL["🛡️ Cilium<br/>Agent + Operator"]
            A_HUB["📊 Hubble<br/>Relay + UI"]
            A_VAULT["🔐 Vault<br/>Secrets Manager"]
            A_SS["🔏 Sealed Secrets<br/>GitOps Encryption"]
            A_HARBOR["📦 Harbor<br/>Container Registry"]
        end

        subgraph "🐳 kind cluster-b"
            B_CIL["🛡️ Cilium<br/>Agent + Operator"]
            B_HUB["📊 Hubble<br/>Relay + UI"]
            B_VAULT["🔐 Vault<br/>Secrets Manager"]
            B_SS["🔏 Sealed Secrets<br/>GitOps Encryption"]
        end

        subgraph "🌐 Shared Infrastructure"
            MESH["🌉 Cilium ClusterMesh<br/>🔐 mTLS + 🎯 Service Mesh"]
            CA["🔑 Shared Root CA<br/>Digital Trust Anchor"]
        end
    end

    subgraph "🏛️ Governance & IAM"
        KC["👤 Keycloak<br/>Identity & Access Management"]
        GOV["📋 Governance Policies<br/>SOC2, ISO 27001, HIPAA"]
    end

    subgraph "🔒 Security & Secrets"
        VAULT["🔐 Vault<br/>Auto-Unseal + HA Raft"]
        SS_CTRL["🔏 Sealed Secrets Controller<br/>RSA 4096-bit Encryption"]
        UNSEAL["⏰ CronJob<br/>Auto-Unseal Recovery"]
    end

    A_CIL <-->|"🔐 Encrypted<br/>mTLS"| MESH
    B_CIL <-->|"🔐 Encrypted<br/>mTLS"| MESH
    CA -.->|"🪪 Trust"| A_CIL
    CA -.->|"🪪 Trust"| B_CIL
    CA -.->|"🪪 Trust"| VAULT

    A_VAULT -->|"🔑 API Keys<br/>& Certificates"| VAULT
    A_SS -->|"📦 SealedSecret CRD"| SS_CTRL
    SS_CTRL -->|"🔓 Decrypt"| A_VAULT
    UNSEAL -->|"🔐 Unseal Keys"| VAULT

    KC -->|"👤 Authentication"| GOV
    GOV -->|"🛡️ RBAC Policies"| A_CIL
    GOV -->|"🛡️ RBAC Policies"| B_CIL

    A_HARBOR -->|"📦 Images"| MESH
    MESH -->|"🌐 Cross-Cluster<br/>Service Discovery"| B_CIL

    classDef primary fill:#1E3A5F,color:#FFFFFF,stroke:#15294A,stroke-width:2px
    classDef secondary fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8,stroke-width:2px
    classDef accent fill:#F59E0B,color:#FFFFFF,stroke:#D97706,stroke-width:2px
    classDef success fill:#10B981,color:#FFFFFF,stroke:#059669,stroke-width:2px
    classDef data fill:#0F766E,color:#FFFFFF,stroke:#0D5E57,stroke-width:2px

    class A_CIL,B_CIL primary
    class MESH secondary
    class CA,VAULT,SS_CTRL accent
    class KC,GOV data
    class A_HUB,B_HUB,A_HARBOR success
```

---

## Structure

```
keycloak/
├── base/                          # Shared base resources
│   ├── kustomization.yaml         # Wires all resources
│   ├── deployment.yaml            # Keycloak Deployment (Quarkus distro)
│   ├── service.yaml               # ClusterIP Service
│   ├── configmap.yaml             # Keycloak configuration (env vars)
│   └── realm-import.yaml          # Realm definition with users/roles/groups/policies
├── overlays/
│   ├── dev/                       # Dev overlay (single replica, dev DB)
│   │   └── kustomization.yaml
│   └── prod/                      # Production overlay (HA, TLS, PostgreSQL)
│       └── kustomization.yaml
└── README.md
```

## Usage

```bash
# Deploy to dev
kustomize build governance/keycloak/overlays/dev | kubectl apply -f -

# Deploy to production
kustomize build governance/keycloak/overlays/prod | kubectl apply -f -
```

## Configuration as Code

All realm configuration lives in `base/realm-import.yaml`. This includes:

- **Realm** — master realm settings, themes, brute-force protection
- **Users** — user accounts with credentials, enabled/disabled state
- **Roles** — realm-level and client-level roles
- **Groups** — group hierarchy with assigned roles
- **Policies** — Keycloak Authorization Services policies (role-based, JS-based, etc.)

After initial deployment, the `--import-realm` CLI argument triggers Keycloak
to import realm JSON files from `/opt/keycloak/data/import` on startup. Subsequent
changes must be applied via the Keycloak Admin API or by re-deploying with updated
ConfigMap contents.

## Related Governance Policies

See [../README.md](../README.md) for the overarching governance framework,
including security policies, access control standards, and IaC review processes.
