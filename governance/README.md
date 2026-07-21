# Governance

This directory contains policies, compliance frameworks, and operational guidelines for the infrastructure.

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

## Topics Covered

- Security policies and access control
- Compliance standards (SOC2, ISO 27001, HIPAA, etc.)
- Change management and approval workflows
- Audit logging and monitoring requirements
- Incident response procedures
- Infrastructure-as-Code review processes
- Identity and Access Management (IAM) — see [Keycloak deployment](./keycloak/README.md)

## Related Resources

- [./keycloak](./keycloak/README.md) — IAM deployment with Kustomize + config-as-code
- [./secret-management](../secret-management/README.md) — secrets handling governed by these policies
