# Sealed Secrets — GitOps-Native Secret Encryption

[Sealed Secrets](https://github.com/bitnami/sealed-secrets) by Bitnami is a Kubernetes controller and CLI tool that lets you **encrypt Kubernetes Secrets into safe-to-store `SealedSecret` custom resources**. The encrypted `SealedSecret` can be committed to any repository (even public ones) and decrypted only by the controller running in your target cluster.

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

## Architecture

```mermaid
graph TB
    subgraph "Outside Cluster (Developer)"
        DEV[👤 Developer]
        SEC[🔒 Secret<br/>plaintext]
        KUBESEAL["🔏 kubeseal CLI<br/>(encryption)"]
        SS[📦 SealedSecret<br/>encrypted]
        GIT[📂 Git Repository]
    end

    subgraph "Inside Kubernetes Cluster"
        subgraph "Controller Pod"
            C[⚙️ Controller]
            KEY["🔑 Private Key<br/>RSA 4096"]
        end
        SS_CRD[📋 SealedSecret CRD]
        SEC_OUT[🔒 Secret<br/>plaintext]
        POD[🚀 Application Pod]
    end

    subgraph "Key Distribution"
        PUB_CERT["🗝️ Public Certificate<br/>safe to share"]
        WEB["🌐 Web Server / S3<br/>(distribution)"]
    end

    DEV -->|"Creates"| SEC
    KUBESEAL -->|"Encrypts with<br/>public cert"| SS
    SEC --> KUBESEAL
    PUB_CERT --> KUBESEAL
    DEV -->|"Pushes"| GIT
    GIT -.->|"ArgoCD / Flux<br/>syncs to cluster"| SS_CRD
    SS_CRD -->|"Decrypts with<br/>private key"| C
    KEY --> C
    C -->|"Creates"| SEC_OUT
    SEC_OUT -->|"Mounted or<br/>injected"| POD
    C -->|"Serves"| PUB_CERT
    PUB_CERT -.->|"kubeseal --fetch-cert"| KUBESEAL
    PUB_CERT -.-> WEB
    WEB -.->|"Offline developers<br/>download cert"| KUBESEAL

    classDef primary fill:#1E3A5F,color:#FFFFFF,stroke:#15294A,stroke-width:2px
    classDef secondary fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8,stroke-width:2px
    classDef data fill:#0F766E,color:#FFFFFF,stroke:#0D5E57,stroke-width:2px
    classDef user fill:#F59E0B,color:#FFFFFF,stroke:#D97706,stroke-width:2px

    class C,SS_CRD primary
    class SS,DEV,GIT user
    class SEC,SEC_OUT,KUBESEAL secondary
    class KEY,PUB_CERT data
    class POD secondary
    class WEB secondary
```

### How It Works — Step by Step

```mermaid
sequenceDiagram
    participant Dev as 👤 Developer
    participant KS as 🔏 kubeseal
    participant Ctrl as ⚙️ Controller
    participant K8s as ☸️ K8s API
    participant Git as 📂 Git Repo

    Note over Dev,Git: Setup: Developer fetches the public key
    Dev->>KS: kubeseal --fetch-cert > mycert.pem
    KS->>Ctrl: GET /v1/cert.pem
    Ctrl-->>KS: Public certificate
    KS-->>Dev: mycert.pem (safe to share)

    Note over Dev,Git: Sealing: Developer encrypts a Secret
    Dev->>Dev: Create Secret YAML (local, dry-run)
    Dev->>KS: kubeseal --cert mycert.pem < secret.yaml
    KS->>KS: Encrypt each secret key<br/>with RSA-OAEP + AES-GCM
    KS-->>Dev: SealedSecret YAML (encrypted)

    Note over Dev,Git: GitOps: Push to Git, sync to cluster
    Dev->>Git: git push (SealedSecret YAML)
    Git->>K8s: ArgoCD/Flux syncs SealedSecret resource
    K8s->>Ctrl: Controller watches SealedSecret CRD
    Ctrl->>Ctrl: Decrypt with private key
    Ctrl->>K8s: Create native Secret
    K8s-->>Dev: Pods consume the Secret
```

## Core Concepts

### Cryptographic Model

Sealed Secrets uses **asymmetric encryption** with RSA 4096-bit keys:

```mermaid
graph LR
    subgraph "Encryption (kubeseal)"
        PLAIN[📄 Secret<br/>plaintext]
        CERT["🗝️ Public Cert<br/>RSA 4096"]
        AES["🔑 AES-256 key<br/>ephemeral"]
        ENC[🔐 Encrypted payload]
        SS_ENC[📦 SealedSecret<br/>YAML]
    end

    subgraph "Decryption (Controller)"
        SS_ENC2[📦 SealedSecret<br/>YAML]
        PRIV["🔐 Private Key<br/>RSA 4096"]
        DEC_AES["🔑 AES-256 key<br/>recovered"]
        PLAIN_OUT[📄 Secret<br/>plaintext]
    end

    PLAIN -->|"Encrypt with AES-256"| ENC
    AES -->|"generate once"| ENC
    CERT -->|"Wrap AES key<br/>with RSA-OAEP"| ENC
    ENC --> SS_ENC

    SS_ENC2 -->|"Unwrap AES key<br/>with RSA-OAEP"| DEC_AES
    PRIV --> DEC_AES
    DEC_AES -->|"Decrypt payload"| PLAIN_OUT

    classDef public fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8,stroke-width:2px
    classDef private fill:#EF4444,color:#FFFFFF,stroke:#DC2626,stroke-width:2px
    classDef process fill:#1E3A5F,color:#FFFFFF,stroke:#15294A,stroke-width:2px
    classDef data fill:#0F766E,color:#FFFFFF,stroke:#0D5E57,stroke-width:2px

    class CERT public
    class PRIV private
    class PLAIN,SS_ENC,SS_ENC2,PLAIN_OUT process
    class ENC data
    class AES,DEC_AES public
```

Each value in `spec.encryptedData` is independently encrypted:
1. A random AES-256 key is generated per value.
2. The plaintext value is encrypted with that AES key (AES-GCM).
3. The AES key itself is wrapped (encrypted) with the RSA public key (RSA-OAEP).
4. The combined payload (encrypted value + wrapped key) is stored in the SealedSecret.

### The SealedSecret Custom Resource

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mysecret
  namespace: mynamespace
spec:
  encryptedData:
    password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq.....
  template:
    type: Opaque
    metadata:
      labels:
        app: myapp
      annotations:
        sealedsecrets.bitnami.com/managed: "true"
```

The controller unseals this into a native `Secret`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
  namespace: mynamespace
  labels:
    app: myapp
  ownerReferences:
    - apiVersion: bitnami.com/v1alpha1
      kind: SealedSecret
      name: mysecret
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # base64 "password123"
```

### Sealing Scopes

| Scope | Name Locked | Namespace Locked | Use Case |
|-------|-------------|------------------|----------|
| `strict` (default) | Yes | Yes | Maximum security — secret is pinned to one name+namespace |
| `namespace-wide` | No | Yes | Can rename the SealedSecret within a namespace |
| `cluster-wide` | No | No | Can move to any namespace, any name |

```bash
# Strict scope (default)
kubeseal < secret.yaml > sealed.yaml

# Namespace-wide
kubeseal --scope namespace-wide < secret.yaml > sealed.yaml

# Cluster-wide
kubeseal --scope cluster-wide < secret.yaml > sealed.yaml
```

## Installation

### Controller

```bash
# Deploy the controller
kubectl apply -f https://github.com/bitnami/sealed-secrets/releases/latest/download/controller.yaml

# Or with Helm
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm install sealed-secrets -n kube-system \
  --set-string fullnameOverride=sealed-secrets-controller \
  sealed-secrets/sealed-secrets
```

### Kubeseal CLI

```bash
# macOS
brew install kubeseal

# Linux
KUBESEAL_VERSION=$(curl -sL https://api.github.com/repos/bitnami/sealed-secrets/tags | \
  jq -r '.[0].name' | cut -c2-)
curl -OL "https://github.com/bitnami/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Usage — Sealing Secrets

### Basic Workflow

```bash
# 1. Create a Secret locally (dry-run)
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=s3cret \
  --dry-run=client -o yaml > secret.yaml

# 2. Seal it
kubeseal -f secret.yaml -w sealed-secret.yaml

# 3. The sealed YAML is safe to commit
cat sealed-secret.yaml

# 4. Apply to the cluster
kubectl apply -f sealed-secret.yaml

# 5. Verify the unsealed Secret exists
kubectl get secret db-credentials
```

### Raw Mode (without kubectl)

```bash
# Encrypt a single value directly
echo -n "my-password" | kubeseal --raw \
  --namespace myapp \
  --name db-credentials

# Output: AgBChHUWLMx...
```

## Sharing Keys Without kubectl Access

One of the most common questions is: **How can developers seal secrets without direct kubectl access to the cluster?**

The answer is that the **public certificate is all that's needed to seal secrets**, and it is safe to share with anyone.

### The Key Distribution Model

```mermaid
graph TB
    subgraph "Cluster (kubectl access)"
        CTRL[⚙️ Sealed Secrets<br/>Controller]
        CERT[🗝️ Public Certificate<br/>/v1/cert.pem]
    end

    subgraph "Key Distribution Channels"
        FETCH["🔏 kubeseal --fetch-cert"]
        WEB["🌐 Publish to web<br/>https://certs.internal/..."]
        S3["☁️ Publish to S3/GCS<br/>gs://certs/sealed.pem"]
        GIT["📂 Store in infra<br/>repo (safe)"]
    end

    subgraph "Developers (no kubectl)"
        DEV1[👤 Developer A<br/>--cert mycert.pem]
        DEV2[👤 Developer B<br/>--cert URL]
        CI[🤖 CI/CD Pipeline<br/>--cert from S3]
    end

    CTRL -->|"serves at<br/>/v1/cert.pem"| CERT
    CERT --> FETCH
    CERT --> WEB
    CERT --> S3
    CERT --> GIT

    FETCH --> DEV1
    WEB --> DEV2
    S3 --> CI
    GIT --> DEV1
    GIT --> CI

    classDef primary fill:#1E3A5F,color:#FFFFFF,stroke:#15294A,stroke-width:2px
    classDef secondary fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8,stroke-width:2px
    classDef accent fill:#F59E0B,color:#FFFFFF,stroke:#D97706,stroke-width:2px
    classDef success fill:#10B981,color:#FFFFFF,stroke:#059669,stroke-width:2px

    class CTRL primary
    class CERT secondary
    class DEV1,DEV2 accent
    class CI success
```

### Method 1: Fetch Certificate Once, Distribute as File

```bash
# Admin (with kubectl access) fetches the certificate once
kubeseal --fetch-cert > sealed-secrets-cert.pem

# Share the file securely (or in a private repo)
# The certificate is PUBLIC — it's the encryption key, not the decryption key

# Developer (no kubectl) seals offline
kubeseal --cert sealed-secrets-cert.pem \
  -f secret.yaml -w sealed-secret.yaml
```

### Method 2: Publish Certificate to a Web Server

```bash
# Admin publishes the certificate
kubeseal --fetch-cert | \
  gsutil cp - gs://my-org-sealed-secrets-certs/prod-cluster.pem

# Developer seals using the URL
kubeseal --cert https://storage.googleapis.com/my-org-sealed-secrets-certs/prod-cluster.pem \
  -f secret.yaml -w sealed-secret.yaml

# Or using environment variable
export SEALED_SECRETS_CERT=https://storage.googleapis.com/my-org-sealed-secrets-certs/prod-cluster.pem
kubeseal -f secret.yaml -w sealed-secret.yaml
```

### Method 3: Controller URL (kubectl Required)

If a developer has kubectl configured but limited permissions (e.g., cannot read Secrets), they can still fetch the cert from the controller directly:

```bash
# Works without any special RBAC — the controller serves the cert anonymously
kubeseal --fetch-cert > mycert.pem

# Or inline
kubeseal -f secret.yaml -w sealed-secret.yaml
```

### CI/CD Pipeline Integration

```yaml
# .github/workflows/seal-secrets.yml
jobs:
  seal:
    steps:
      - run: |
          # Download the public cert from a secure distribution point
          curl -o sealed-cert.pem https://certs.internal/sealed-secrets/prod.pem

          # Seal secrets for the target environment
          for env in staging prod; do
            kubeseal --cert sealed-cert.pem \
              -f secrets/$env/secret.yaml \
              -w sealed-secrets/$env/sealed-secret.yaml
          done
```

## ArgoCD Integration

Sealed Secrets works naturally with ArgoCD and other GitOps tools because SealedSecrets are *just Kubernetes manifests* that can be tracked in Git.

### How ArgoCD Syncs SealedSecrets

```mermaid
graph TB
    GIT[📂 Git Repository<br/>SealedSecrets YAML]
    ARGO[🔄 ArgoCD]
    K8S[☸️ Kubernetes API]
    SS[📋 SealedSecret CRD]
    CTRL[⚙️ Sealed Secrets<br/>Controller]
    SEC[🔒 Native Secret]

    GIT -->|"sync"| ARGO
    ARGO -->|"apply"| K8S
    K8S --> SS
    SS -->|"watch"| CTRL
    CTRL -->|"decrypt & create"| SEC

    subgraph "Sync Order"
        CRD_INSTALLED[📋 SealedSecret CRD<br/>must exist first]
        CTRL_DEPLOY[⚙️ Controller<br/>Deployment running]
    end

    CRD_INSTALLED --> CTRL_DEPLOY

    classDef primary fill:#1E3A5F,color:#FFFFFF,stroke:#15294A,stroke-width:2px
    classDef secondary fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8,stroke-width:2px
    classDef success fill:#10B981,color:#FFFFFF,stroke:#059669,stroke-width:2px
    classDef accent fill:#F59E0B,color:#FFFFFF,stroke:#D97706,stroke-width:2px

    class GIT accent
    class ARGO secondary
    class SEC success
    class SS,CTRL primary
    class K8S secondary
    class CRD_INSTALLED,CTRL_DEPLOY primary
```

### Sync Order with ArgoCD

```yaml
# Application: sealed-secrets-infra.yaml
# This must be deployed FIRST — installs the CRD and controller
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets-controller
spec:
  source:
    repoURL: https://github.com/bitnami/sealed-secrets
    path: helm/sealed-secrets
    targetRevision: main
    helm:
      releaseName: sealed-secrets
      values: |
        fullnameOverride: sealed-secrets-controller
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```yaml
# Application: app-secrets.yaml
# This deploys SealedSecrets — depends on controller being ready
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-secrets
spec:
  source:
    repoURL: https://github.com/myorg/app-config
    path: sealed-secrets/
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### ArgoCD Sync Waves

Use sync waves to ensure the controller is ready before SealedSecrets are applied:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets-controller
  annotations:
    argocd.argoproj.io/sync-wave: "-5"  # Deploy first
spec:
  ...
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-secrets
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Deploy after controller is healthy
spec:
  ...
```

### ArgoCD Resource Pruning

When a SealedSecret is deleted from Git, ArgoCD will prune it from the cluster. The controller will see the SealedSecret is gone and delete the corresponding Secret. This is the **default behavior** — the Secret is owned by the SealedSecret via `ownerReferences`.

To decouple them (keep the Secret if the SealedSecret is deleted), add this annotation *before* sealing:

```yaml
metadata:
  annotations:
    sealedsecrets.bitnami.com/skip-set-owner-references: "true"
```

### ArgoCD + Multi-Cluster Workflow

```mermaid
graph LR
    GIT[📂 Git Repo]
    CI[🤖 CI/CD<br/>seal per env]

    subgraph "Cluster: Staging"
        ARGO_S[🔄 ArgoCD]
        CTRL_S[⚙️ Controller<br/>staging-key]
        SEC_S[🔒 Secrets<br/>staging]
    end

    subgraph "Cluster: Production"
        ARGO_P[🔄 ArgoCD]
        CTRL_P[⚙️ Controller<br/>prod-key]
        SEC_P[🔒 Secrets<br/>production]
    end

    GIT -->|"sealed-secrets/staging/"| CI
    GIT -->|"sealed-secrets/prod/"| CI
    CI -->|"seal with staging cert"| GIT
    CI -->|"seal with prod cert"| GIT
    GIT --> ARGO_S
    GIT --> ARGO_P
    ARGO_S -->|"apply"| CTRL_S
    ARGO_P -->|"apply"| CTRL_P
    CTRL_S --> SEC_S
    CTRL_P --> SEC_P

    classDef primary fill:#1E3A5F,color:#FFFFFF,stroke:#15294A,stroke-width:2px
    classDef secondary fill:#2563EB,color:#FFFFFF,stroke:#1D4ED8,stroke-width:2px
    classDef accent fill:#F59E0B,color:#FFFFFF,stroke:#D97706,stroke-width:2px

    class GIT accent
    class CI accent
    class ARGO_S,ARGO_P secondary
    class CTRL_S,CTRL_P primary
    class SEC_S,SEC_P secondary
```

Each cluster has its own controller with a unique key pair. Secrets must be sealed with the **target cluster's** certificate. A CI pipeline can seal secrets for multiple clusters by using the appropriate cert.

## Secret Rotation

### Key Renewal

The controller automatically renews the sealing key every 30 days. Old keys are **not deleted** — existing SealedSecrets remain decryptable.

```bash
# Configure renewal period (deployment flag)
--key-renew-period=720h  # 30 days (default)
--key-renew-period=0     # Disable automatic renewal
```

### Rotating the Actual Secret Value

1. Update the plaintext Secret locally.
2. Re-seal with `kubeseal`.
3. Commit the updated SealedSecret YAML to Git.
4. ArgoCD syncs the change to the cluster.

```bash
# Roll a new password
echo -n "${NEW_PASSWORD}" | kubectl create secret generic db-credentials \
  --from-file=password=/dev/stdin \
  --dry-run=client -o yaml > secret.yaml

# Re-seal
kubeseal --cert mycert.pem \
  -f secret.yaml \
  -w sealed-secrets/db-credentials.yaml

# Commit and push
git add sealed-secrets/db-credentials.yaml
git commit -m "Rotate db-credentials password"
git push
```

### Re-encrypting with a New Key

If the sealing private key is compromised:

1. Delete the old key Secret: `kubectl delete secret -n kube-system sealed-secrets-key`
2. Trigger a new key generation (restart the controller pod).
3. Re-encrypt all SealedSecrets with the new certificate using the `--re-encrypt` flag:
   ```bash
   kubeseal --re-encrypt < sealed-secret-old.yaml > sealed-secret-new.yaml
   ```
4. Apply the re-encrypted SealedSecrets.

## Production Readiness Checklist

- [ ] **Controller HA**: Run at least 2 controller replicas with `--disable-discovery=false` (default).
- [ ] **Backup the sealing key**: The private key is stored in a Secret in `kube-system`. Back it up.
  ```bash
  kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
  ```
- [ ] **Certificate distribution**: Automate publishing the public certificate to a web server or object store.
- [ ] **SealedSecret validation**: Use `kubeseal --validate` in CI to catch invalid SealedSecrets before they reach the cluster.
- [ ] **Sync waves in ArgoCD**: Ensure the controller Application is synced before SealedSecret Applications.
- [ ] **Monitoring**: Alert on controller errors (Prometheus metrics exposed on port 8080).
- [ ] **Audit logging**: Enable Kubernetes audit logging to track SealedSecret creation and controller activity.
- [ ] **Namespace isolation**: Use RBAC to restrict who can create SealedSecrets in each namespace.

## Directory Structure

```text
secrets-management/sealdsecrets/
├── README.md                  # This document
├── overlay/
│   ├── dev/
│   │   ├── kustomization.yaml # Dev overlay for Sealed Secrets controller
│   │   └── sealed-secrets.yaml
│   └── prod/
│       ├── kustomization.yaml # Prod overlay for Sealed Secrets controller
│       └── sealed-secrets.yaml
└── sealed-secrets/
    ├── app-credentials.yaml   # Example SealedSecret
    └── db-credentials.yaml    # Example SealedSecret
```

## Troubleshooting

### SealedSecret stuck in pending

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets-controller

# Verify the CRD exists
kubectl get crd sealedsecrets.bitnami.com

# Check if the SealedSecrets namespace matches
kubectl get sealedsecret mysecret -o yaml | grep namespace
```

### "Failed to decrypt" error

```bash
# The SealedSecret was likely sealed for a different cluster or different scope.
# Verify the certificate used:
kubeseal --fetch-cert | openssl x509 -text -noout | grep Subject

# The SealedSecret's name/namespace scope must match what it was sealed for.
```

### ArgoCD sync fails on SealedSecret

```bash
# Check resource status
argocd app get app-secrets

# The CRD must be installed before ArgoCD can apply SealedSecrets.
# Ensure the controller Application is synced and healthy first.

# Check for sync errors
argocd app logs app-secrets
```

## References

- [Sealed Secrets GitHub Repository](https://github.com/bitnami/sealed-secrets)
- [Sealed Secrets Release Notes](https://github.com/bitnami/sealed-secrets/releases)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
