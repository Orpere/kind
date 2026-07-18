# 🚀 Cilium Cluster Mesh — A Practical Guide

> *This guide walks you through connecting two Kubernetes clusters so a Service in Cluster A can talk to a Service in Cluster B, using Cilium Cluster Mesh — with every single step covered, verified, and testable.*
>
> It explains the concepts in **plain language**, shows **how it works on different infrastructures** (your laptop with kind, AWS, Azure AKS, bare-metal servers, same region or different regions), and gives you **runnable commands** for the full lab on kind.

---

## 🧠 What is Cilium Cluster Mesh? (For non-technical people)

Imagine you have **two separate cities** (clusters), each with their own buildings (pods) and roads (network). Normally, nothing can cross between cities — a building in City A cannot call a building in City B.

🌉 **Cilium Cluster Mesh builds a secure bridge between the cities.** Now a building in City A can reach a building in City B directly, using the same local address — and the bridge is **private, encrypted, and mutually verified** (each city proves who it is before any data moves).

```mermaid
graph TB
    subgraph "🌆 Cluster A — City A"
        A1["🏢 Pod: frontend<br/>10.0.1.5"]
        A2["📦 Service: api<br/>10.1.0.10"]
    end
    subgraph "🌃 Cluster B — City B"
        B1["🏢 Pod: backend<br/>10.2.1.8"]
        B2["📦 Service: database<br/>10.3.0.20"]
    end
    A1 -- "🚀 Wants to call 'database'" --> CM["🌉 Cilium Cluster Mesh<br/>🔐 encrypted + 🪪 verified"]
    CM -- "🔗 Secure tunnel (mTLS)" --> B2
    B2 -- "⬅️ Routes to" --> B1
    style CM fill:#4A90D9,stroke:#2C5F8A,color:#fff
```

### The three security promises

| Promise | What it means | How we deliver it |
|---------|---------------|-------------------|
| 🔐 **Encrypted** | Nobody can read the traffic between clusters | mTLS on the control plane; optional WireGuard/IPsec on the data plane |
| 🪪 **Mutually authenticated (mTLS)** | Each cluster proves its identity to the other | A **single shared CA** (digital trust root) installed on both |
| 🚫 **Private** | The connection point is never on the public internet | `NodePort`/`LoadBalancer` on trusted networks, or `ClusterIP` + tunnel across networks |

> **mTLS vs WireGuard — the simple version:** *mTLS* is the digital ID check + lock that proves who is talking and scrambles the connection handshake (always on). *WireGuard* is an extra padlock on the bulk packet flow (optional, recommended on untrusted networks). On a trusted local network (e.g. both kind clusters on your laptop), mTLS alone is enough.

---

## 🗺️ Deployment Scenarios (where can this run?)

Cilium Cluster Mesh works the same way *logically* everywhere — two clusters, one shared trust root, a private link. What changes is **how the link is physically established** and **what address the clusters dial**. Below are the common scenarios, each with a diagram.

### 🅰️ Scenario A — Two Kind clusters on one laptop (this lab)

Both clusters are Docker containers on your machine, sharing one Docker network. They reach each other directly. **No cloud, no VPN, no MetalLB required.** NodePort + mTLS is enough.

```mermaid
flowchart LR
    subgraph HOST["💻 Your Laptop"]
        subgraph DK["🐳 Docker Network"]
            A["🔵 kind cluster-a<br/>🚪 NodePort"]
            B["🟢 kind cluster-b<br/>🚪 NodePort"]
        end
        CA["🔑 Shared CA<br/>(mTLS trust)"]
    end
    A <-->|"🔐 mTLS over local net"| B
    CA -.->|"🪪 trusted by"| A
    CA -.->|"🪪 trusted by"| B
    style A fill:#2471A3,stroke:#1A5276,color:#fff
    style B fill:#27AE60,stroke:#1E8449,color:#fff
    style CA fill:#8E44AD,stroke:#5B2C6F,color:#fff
    style DK fill:#2C3E50,stroke:#1ABC9C,color:#fff
```

---

### 🅱️ Scenario B — Same cloud, same region (e.g. two EKS / two AKS in one VPC/region)

Both clusters run in the **same provider and region**, on a **shared private network** (VPC or VNet). They are directly reachable via private IPs. Use a managed `LoadBalancer` (or NodePort) + mTLS. No VPN needed.

```mermaid
flowchart LR
    subgraph CLOUD["☁️ AWS / Azure — Region us-east-1"]
        subgraph VPC["🔒 Private VPC / VNet"]
            A["🔵 EKS / AKS cluster-a<br/>🎯 Internal LB"]
            B["🟢 EKS / AKS cluster-b<br/>🎯 Internal LB"]
        end
        CA["🔑 Shared CA<br/>(mTLS trust)"]
    end
    A <-->|"🔐 mTLS over private network"| B
    CA -.->|"🪪 trusted by"| A
    CA -.->|"🪪 trusted by"| B
    style A fill:#2471A3,stroke:#1A5276,color:#fff
    style B fill:#27AE60,stroke:#1E8449,color:#fff
    style CA fill:#8E44AD,stroke:#5B2C6F,color:#fff
    style VPC fill:#2C3E50,stroke:#1ABC9C,color:#fff
```

> On AWS use **internal** `LoadBalancer` (not internet-facing). On Azure use an internal `LoadBalancer`. Never make the mesh endpoint public.

---

### 🅲️ Scenario C — Same cloud, different regions (e.g. EKS us-east-1 ↔ EKS eu-west-1)

The clusters are in the **same provider but different regions**, so they are on **separate networks**. You connect them with the provider's **private peering / VPN** (AWS VPC Peering or Transit Gateway, Azure VNet peering or VPN Gateway). mTLS + private peering = secure.

```mermaid
flowchart LR
    subgraph R1["☁️ AWS — Region us-east-1"]
        A["🔵 EKS cluster-a"]
        CA["🔑 Shared CA"]
    end
    subgraph R2["☁️ AWS — Region eu-west-1"]
        B["🟢 EKS cluster-b"]
        CB["🔑 Shared CA"]
    end
    A <-->|"🔐 VPC Peering / Transit GW<br/>(private, mTLS)"| B
    CA ===|"🤝 identical"| CB
    style A fill:#2471A3,stroke:#1A5276,color:#fff
    style B fill:#27AE60,stroke:#1E8449,color:#fff
    style CA fill:#8E44AD,stroke:#5B2C6F,color:#fff
    style CB fill:#8E44AD,stroke:#5B2C6F,color:#fff
```

---

### 🅳️ Scenario D — Different clouds (AWS EKS ↔ Azure AKS)

Clusters live in **different providers**, so there is **no native private peering**. You build a **site-to-site encrypted tunnel** between them (IPsec VPN or WireGuard), then run mTLS over it. This is the "ClusterIP + tunnel" pattern.

```mermaid
flowchart LR
    subgraph AWS["☁️ AWS — EKS cluster-a"]
        A["🔵 EKS cluster-a<br/>🔒 ClusterIP"]
        CA["🔑 Shared CA"]
    end
    subgraph AZ["🔷 Azure — AKS cluster-b"]
        B["🟢 AKS cluster-b<br/>🔒 ClusterIP"]
        CB["🔑 Shared CA"]
    end
    A <-->|"🔐 IPsec / WireGuard tunnel<br/>(mTLS on top)"| B
    CA ===|"🤝 identical"| CB
    style A fill:#2471A3,stroke:#1A5276,color:#fff
    style B fill:#27AE60,stroke:#1E8449,color:#fff
    style CA fill:#8E44AD,stroke:#5B2C6F,color:#fff
    style CB fill:#8E44AD,stroke:#5B2C6F,color:#fff
```

---

### 🅴️ Scenario E — Bare-metal / on-prem servers

Clusters run on **physical servers in your datacenter** (or VMs you control). There is no managed LoadBalancer, so you typically use **NodePort** on a trusted LAN, or **MetalLB** if you want a stable IP. Across sites, use a **VPN / WireGuard tunnel**.

```mermaid
flowchart LR
    subgraph DC["🏢 On-Prem Datacenter"]
        subgraph LAN["🔒 Private LAN"]
            A["🔵 Bare-metal cluster-a<br/>🚪 NodePort / MetalLB"]
            B["🟢 Bare-metal cluster-b<br/>🚪 NodePort / MetalLB"]
        end
        CA["🔑 Shared CA"]
    end
    A <-->|"🔐 mTLS"| B
    CA -.->|"🪪 trusted by"| A
    CA -.->|"🪪 trusted by"| B
    style A fill:#2471A3,stroke:#1A5276,color:#fff
    style B fill:#27AE60,stroke:#1E8449,color:#fff
    style CA fill:#8E44AD,stroke:#5B2C6F,color:#fff
    style LAN fill:#2C3E50,stroke:#1ABC9C,color:#fff
```

> Across two datacenters/sites with no routed link, keep the service `ClusterIP` and connect via a WireGuard/IPsec site-to-site tunnel (same as Scenario D).

---

### 📊 Scenario cheat-sheet

| Scenario | Infrastructure | Network reachability | Exposure method | Extra encryption |
|----------|---------------|----------------------|-----------------|-----------------|
| 🅰️ Kind (laptop) | 2 kind clusters, Docker | Direct (same net) | NodePort | mTLS (WireGuard optional) |
| 🅱️ Same cloud, same region | EKS/AKS ×2 in 1 VPC | Direct private IPs | Internal LoadBalancer | mTLS |
| 🅲️ Same cloud, diff region | EKS ×2 in 2 regions | Peering/VPN needed | Internal LB + peering | mTLS |
| 🅳️ Diff cloud (AWS↔Azure) | EKS + AKS | No native peering | ClusterIP + tunnel | mTLS + IPsec/WireGuard |
| 🅴️ Bare-metal / on-prem | Physical servers | LAN or VPN | NodePort / MetalLB | mTLS (+ tunnel across sites) |

> **Rule of thumb:** if the clusters can already reach each other over a *private* path, just expose the mesh (NodePort/LB) and rely on mTLS. If they *can't* reach each other, keep it `ClusterIP` and build an encrypted tunnel first.

---

## 🏗️ High-Level Architecture

```mermaid
graph LR
    subgraph "🖥️ Host Machine"
        KIND["⚙️ Kind Runtime (Docker containers)"]
    end
    subgraph "🔵 Cluster A<br/>kind-cluster-a"
        CP_A["🎮 Control Plane<br/>kind-cluster-a-control-plane"]
        W1_A["💻 Worker Node"]
        CIL_A["🛡️ Cilium Agent<br/>eBPF + kube-proxy replacement"]
        SVC_A["📡 Service: frontend<br/>ClusterIP: 10.1.0.50"]
        POD_A["🏢 Pod: frontend-v1<br/>10.0.1.10"]
    end
    subgraph "🟢 Cluster B<br/>kind-cluster-b"
        CP_B["🎮 Control Plane<br/>kind-cluster-b-control-plane"]
        W1_B["💻 Worker Node"]
        CIL_B["🛡️ Cilium Agent<br/>eBPF + kube-proxy replacement"]
        SVC_B["📡 Service: backend<br/>ClusterIP: 10.3.0.50"]
        POD_B["🏢 Pod: backend-v1<br/>10.2.1.10"]
    end
    KIND --> CP_A
    KIND --> CP_B
    CIL_A ---|"🌉 Cluster Mesh<br/>Wireguard Tunnel"| CIL_B
    POD_A --> SVC_A
    POD_B --> SVC_B
```

---

## 📋 Prerequisites

| Tool | Purpose | Check Command |
|------|---------|---------------|
| 🐳 **Docker** | Runs Kind nodes | `docker --version` |
| ⚡ **Kind** | Local K8s clusters | `kind --version` |
| ☸️ **kubectl** | Talk to clusters | `kubectl --version` |
| 🛡️ **Cilium CLI** | Install & manage Cilium | `cilium --version` |

---

# 👣 Complete Step-by-Step Walkthrough

## Step 0 — Full Environment Setup

### 0a. Create both Kind clusters

```bash
kind create cluster --config kind-bpf-a.yaml
kind create cluster --config kind-bpf-b.yaml
```

### 0b. Verify clusters exist

```bash
kind get clusters
```

**Expected output:**
```
cluster-a
cluster-b
```

### 0c. Identify cluster contexts in kubectl

```bash
kubectl config get-contexts
```

**Expected output (context names):**
```
kind-cluster-a
kind-cluster-b
```

### 0d. Check both clusters are fully operational

```bash
kubectl cluster-info --context kind-cluster-a
kubectl cluster-info --context kind-cluster-b
kubectl get nodes --context kind-cluster-a
kubectl get nodes --context kind-cluster-b
```

**Expected output:** Both control planes reachable, both nodes `Ready`.

### 0e. 🆔 Identify clusters — assign unique cluster IDs

Cilium Cluster Mesh requires **each cluster to have a unique ID** (1–255) and a name. These are baked into Cilium's identity-based networking. If both clusters use the default ID `1`, the mesh will not route correctly.

| Cluster | Context | Assigned ID | Assigned Name |
|---------|---------|-------------|---------------|
| 🔵 Cluster A | `kind-cluster-a` | **1** | `cluster-a` |
| 🟢 Cluster B | `kind-cluster-b` | **2** | `cluster-b` |

```bash
echo "Cluster A → ID=1  name=cluster-a"
echo "Cluster B → ID=2  name=cluster-b"
```

```mermaid
graph LR
    subgraph "🔵 Cluster A"
        A_ID["🆔 cluster.id = 1<br/>cluster.name = cluster-a"]
    end
    subgraph "🟢 Cluster B"
        B_ID["🆔 cluster.id = 2<br/>cluster.name = cluster-b"]
    end
    A_ID -- "🔗 Mesh needs unique IDs" --> B_ID
    B_ID -- "✅ IDs are different → works" --> A_ID
```

### 0e. Create the right certificates (mTLS trust root)

#### 🪪 What certificates do we need? (plain language)

Think of certificates like **digital ID cards** issued by a **trusted passport office**
(the Certificate Authority, or **CA**). For Cluster Mesh with mTLS you need exactly **one
shared CA** that *both* clusters trust:

| File | What it is | Who creates it | Shared? |
|------|-----------|----------------|--------|
| `ca.crt` | The CA's public ID (the "passport office" certificate) | You, once | ✅ Same on both clusters |
| `ca.key` | The CA's private signing key (keep secret!) | You, once | ✅ Same on both clusters |
| Cluster serving certs | Per-cluster TLS certs used for the mesh API | **Cilium generates these automatically** from the shared CA | ❌ Each cluster has its own |

> 🔑 **Key point:** you only create the **CA** (`ca.crt` + `ca.key`). Cilium then
> automatically issues the actual per-cluster certificates from that CA. Because both
> clusters trust the *same* CA, they accept each other's certs → that is **mTLS**.
> If each cluster made its *own* CA, you'd hit the `Cilium CA certificates do not match` error.

#### 🛠️ Step 1 — Create the shared CA (one time)

```bash
# Create a self-signed CA: 4096-bit key, valid 10 years, CN=clustermesh-ca
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout ca.key -out ca.crt -days 3650 -subj "/CN=clustermesh-ca"
```

This writes two files in your current directory: `ca.crt` (public) and `ca.key` (private).
Keep `ca.key` safe — anyone with it can issue trusted certificates.

#### 🛠️ Step 2 — Verify the CA looks correct (optional but recommended)

```bash
openssl x509 -in ca.crt -noout -subject -issuer -dates
# Expected: Subject/Issuer both = /CN=clustermesh-ca  (self-signed root)
```

#### 🛡️ Step 3 — Install the SAME CA on both clusters

Package `ca.crt` + `ca.key` into a Kubernetes secret named `cilium-ca` in the
`kube-system` namespace of **each** cluster. Cilium reads this secret at install time.

```bash
kubectl create secret generic cilium-ca -n kube-system \
  --from-file=ca.crt=ca.crt --from-file=ca.key=ca.key --context kind-cluster-a
kubectl create secret generic cilium-ca -n kube-system \
  --from-file=ca.crt=ca.crt --from-file=ca.key=ca.key --context kind-cluster-b
```

Confirm both clusters hold the identical CA:

```bash
kubectl --context kind-cluster-a -n kube-system get secret cilium-ca -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -fingerprint
kubectl --context kind-cluster-b -n kube-system get secret cilium-ca -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -fingerprint
# The two fingerprints MUST be identical
```

#### 🔗 Step 4 — Point Cilium at the shared CA at install time

The install commands (steps 0f/0g) already include these flags so Cilium uses your CA:

```bash
--set clustermesh.apiserver.tls.ca.cert=/var/lib/cilium-ca/ca.crt \
--set clustermesh.apiserver.tls.ca.key=/var/lib/cilium-ca/ca.key
```

Cilium then auto-generates the per-cluster serving certificates from this CA, and the
clusters mutually authenticate over mTLS.

```mermaid
flowchart TB
    OP["👤 You"] -->|"🔧 openssl"| CA["🔑 Shared CA<br/>ca.crt + ca.key"]
    CA -->|"📦 kubectl create secret cilium-ca"| SA["🗄️ cluster-a"]
    CA -->|"📦 kubectl create secret cilium-ca"| SB["🗄️ cluster-b"]
    SA -->|"🪪 Cilium issues serving cert"| MA["🔵 Mesh API A"]
    SB -->|"🪪 Cilium issues serving cert"| MB["🟢 Mesh API B"]
    MA <-->|"🔐 mTLS (both trust same CA)"| MB
    style CA fill:#8E44AD,stroke:#5B2C6F,color:#fff
    style SA fill:#2471A3,stroke:#1A5276,color:#fff
    style SB fill:#27AE60,stroke:#1E8449,color:#fff
    style MA fill:#2471A3,stroke:#1A5276,color:#fff
    style MB fill:#27AE60,stroke:#1E8449,color:#fff
```

> ⚠️ **Never** use `--allow-mismatching-ca` as a fix for a CA mismatch — it disables the
> identity check. The correct fix is always: use **one shared CA** as shown above.
>
> **WireGuard (optional):** because both kind clusters share the same local Docker
> network, mTLS alone is sufficient for this exercise. To add an extra data-plane
> encryption layer (e.g. on untrusted networks), append
> `--enable-wireguard --wireguard-enabled` to the install commands below.

### 0f. Install Cilium on Cluster A (with cluster ID 1)

```bash
cilium install \
    --context kind-cluster-a \
    --set cluster.id=1 \
    --set cluster.name=cluster-a \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.installCRDs=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true \
    --set ingressController.enabled=true \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set clustermesh.apiserver.tls.ca.cert=/var/lib/cilium-ca/ca.crt \
    --set clustermesh.apiserver.tls.ca.key=/var/lib/cilium-ca/ca.key
```

> **Security:** the last two lines point Cilium at the **shared CA** created earlier (Phase/Step: single root of trust for mTLS). This is what authenticates and encrypts the mesh control/API traffic.
> **WireGuard (optional):** both clusters run on the same local kind/Docker network, so mTLS alone is sufficient for this exercise. To add an extra data-plane encryption layer on untrusted networks, append `--enable-wireguard --wireguard-enabled` to the install command.

Wait for Cilium to be ready:

```bash
cilium status --context kind-cluster-a --wait
```

### 0g. Install Cilium on Cluster B (with cluster ID 2)

```bash
cilium install \
    --context kind-cluster-b \
    --set cluster.id=2 \
    --set cluster.name=cluster-b \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set gatewayAPI.enabled=true \
    --set gatewayAPI.installCRDs=true \
    --set gatewayAPI.enableAlpn=true \
    --set gatewayAPI.enableAppProtocol=true \
    --set ingressController.enabled=true \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set clustermesh.apiserver.tls.ca.cert=/var/lib/cilium-ca/ca.crt \
    --set clustermesh.apiserver.tls.ca.key=/var/lib/cilium-ca/ca.key
```

> **Security:** same shared-CA flags as Cluster A (mTLS). Optional `--enable-wireguard --wireguard-enabled` adds data-plane encryption (not required for this local kind exercise).

```bash
cilium status --context kind-cluster-b --wait
```

### 0h. Run Cilium connectivity test on each cluster

```bash
cilium connectivity test --context kind-cluster-a
cilium connectivity test --context kind-cluster-b
```

### 0i. Verify Cilium status on both

```bash
cilium status --context kind-cluster-a
cilium status --context kind-cluster-b
```

**Expected output:** Both show `Cilium: OK`, `NodeStatus: Connected`, `KubeProxyReplacement: Strict`.

### 0j. Verify cluster IDs are correctly assigned

```bash
cilium config view --context kind-cluster-a | grep -E "cluster-(id|name)"
cilium config view --context kind-cluster-b | grep -E "cluster-(id|name)"
```

**Expected output:**
```
cluster-id                                       1
cluster-name                                      cluster-a
```
```
cluster-id                                       2
cluster-name                                      cluster-b
```

### 0k. (Alternative) Set cluster ID/name via the Cilium CLI

If Cilium is already installed and you need to change the cluster ID or name, you can use `cilium config set` instead of re-installing. **Note:** the cluster ID is a core identity used by Cilium's eBPF datapath, so changing it requires the agent and operator to restart and re-derive identities.

Set the values on each cluster:

```bash
# Cluster A → ID 1, name cluster-a
cilium config set --context kind-cluster-a cluster-id 1
cilium config set --context kind-cluster-a cluster-name cluster-a

# Cluster B → ID 2, name cluster-b
cilium config set --context kind-cluster-b cluster-id 2
cilium config set --context kind-cluster-b cluster-name cluster-b
```

Roll the Cilium daemonset and operator so the new ID takes effect (the agents must restart to re-initialize the eBPF identity allocator):

```bash
kubectl rollout restart -n kube-system ds/cilium --context kind-cluster-a
kubectl rollout restart -n kube-system deployment/cilium-operator --context kind-cluster-a
kubectl rollout restart -n kube-system ds/cilium --context kind-cluster-b
kubectl rollout restart -n kube-system deployment/cilium-operator --context kind-cluster-b
```

Wait for the restart to complete and confirm the IDs are now applied:

```bash
cilium status --context kind-cluster-a --wait
cilium status --context kind-cluster-b --wait
cilium config view --context kind-cluster-a | grep -E "cluster-(id|name)"
cilium config view --context kind-cluster-b | grep -E "cluster-(id|name)"
```

> ⚠️ Changing a cluster ID after pods have been assigned identities can cause brief network disruption while endpoints are re-derived. It is safest to set the correct ID at **install time** (steps 0f/0g) and only use `config set` when necessary. Also ensure the two clusters use **different** IDs (1–255); duplicate IDs break Cluster Mesh routing.

---

## Step 1 — Enable the Cluster Mesh API

Cilium nodes in each cluster need to expose a port so the *other* cluster can reach them. The `cilium clustermesh enable` command takes a `--service-type` flag that controls how the `cilium-clustermesh` service is published. Pick the option that fits your environment:

| Service type | Best for | Requires | Stable address? |
|--------------|----------|----------|-----------------|
| `NodePort` | Kind / bare-metal labs (default for this exercise) | Nothing extra | ❌ Random port per node |
| `LoadBalancer` | Cloud, or Kind + **optional** MetalLB | A LoadBalancer implementation | ✅ Stable LB IP |
| `ClusterIP` + tunnel | Restricted / separate networks | VPN / gateway / port-forward | ➖ Depends on tunnel |

> All three expose the same `cilium-clustermesh` API (TLS on port `32379` by default); only the *reachability* mechanism differs. For this local kind exercise, **NodePort needs nothing extra** — MetalLB is only needed if you specifically want a `LoadBalancer` IP.

### 1a. Option A — NodePort (default, zero-config on Kind)

Kind has no cloud LoadBalancer, so `NodePort` works out of the box and needs no extra components. A high port is opened on every node and the other cluster connects to `<node-ip>:<nodeport>`.

Enable on Cluster A:
```bash
cilium clustermesh enable --context kind-cluster-a --service-type NodePort
```

Enable on Cluster B:
```bash
cilium clustermesh enable --context kind-cluster-b --service-type NodePort
```

Because the NodePort is randomized, tell Cilium which node address to advertise (otherwise it may pick an unreachable one):
```bash
# Advertise the kind node's IP so the remote cluster can reach it
cilium clustermesh enable --context kind-cluster-a \
  --service-type NodePort \
  --clustermesh-apiserver-node-port 32379
```

### 1b. Option B — LoadBalancer (stable IP; **optional** MetalLB on Kind)

If you want a stable IP instead of a random port, use `--service-type LoadBalancer`. On a real cloud this is automatic; on **Kind** you must first install [MetalLB](https://metallb.universe.tf/) (an optional add-on — **not required** for the NodePort default). Skip this option entirely if NodePort is fine.

**1. Install MetalLB on both clusters** (one-time):
```bash
# For each cluster context
for CTX in kind-cluster-a kind-cluster-b; do
  kubectl --context "$CTX" apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
  kubectl --context "$CTX" -n metallb-system wait --for=condition=Ready pods --all --timeout=120s
done
```

**2. Give MetalLB an IP pool** matching the Kind docker network (default `172.18.0.0/16` / `172.19.0.0/16`). Create this on both clusters:
```bash
cat <<'EOF' | kubectl --context kind-cluster-a apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: clustermesh-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.18.255.0/24   # adjust to your kind network
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: clustermesh-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - clustermesh-pool
EOF
# Repeat the same manifest for kind-cluster-b (use its network range)
```

**3. Enable the mesh with LoadBalancer** on both clusters:
```bash
cilium clustermesh enable --context kind-cluster-a --service-type LoadBalancer
cilium clustermesh enable --context kind-cluster-b --service-type LoadBalancer
```

**4. Grab the assigned LB IP** (this is the stable address the other cluster connects to):
```bash
kubectl get svc -n kube-system cilium-clustermesh --context kind-cluster-a \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'
```

### 1c. Option C — ClusterIP + tunnel (no NodePort/LB exposure)

If you cannot open a NodePort or LB (e.g. restricted networks), keep the service as `ClusterIP` and make it reachable through your own networking — a VPN, a gateway, or a manual `kubectl port-forward`. This is the most manual option.

**1. Enable with ClusterIP** on both clusters:
```bash
cilium clustermesh enable --context kind-cluster-a --service-type ClusterIP
cilium clustermesh enable --context kind-cluster-b --service-type ClusterIP
```

**2. Expose it locally** (example using port-forward; for real cross-host reachability use a site-to-site VPN or ingress/gateway instead):
```bash
# Forward the apiserver port to localhost on Cluster B's machine
kubectl --context kind-cluster-b port-forward -n kube-system svc/cilium-clustermesh 32379:32379 &
```

**3. Connect using the reachable address** instead of relying on auto-discovery:
```bash
cilium clustermesh connect --context kind-cluster-a \
  --destination-context kind-cluster-b \
  --destination-api-server https://<reachable-ip-or-hostname>:32379
```
Replace `<reachable-ip-or-hostname>` with whatever your tunnel/VPN makes reachable (the LB IP, VPN IP, or `localhost` if port-forwarding on the same host).

### 1d. Verify the mesh service was created

```bash
kubectl get svc -n kube-system --context kind-cluster-a | grep clustermesh
kubectl get svc -n kube-system --context kind-cluster-b | grep clustermesh
```

**Expected output:** A `cilium-clustermesh` service exists on both clusters — type `NodePort`, `LoadBalancer`, or `ClusterIP` depending on the option you chose.

**What happened:**
- TLS certificates were generated for encrypted communication
- A `cilium-clustermesh` service (port `32379` by default) was created on both clusters
- Cilium agents are now listening for inbound mesh connections

```mermaid
sequenceDiagram
    participant User as 👤 You
    participant CA as 🔵 Cluster A
    participant CB as 🟢 Cluster B
    User->>CA: cilium clustermesh enable --service-type <NodePort|LoadBalancer|ClusterIP>
    CA-->>User: ✅ TLS certs created, service ready
    User->>CB: cilium clustermesh enable --service-type <NodePort|LoadBalancer|ClusterIP>
    CB-->>User: ✅ TLS certs created, service ready
```

---

## Step 2 — Connect the Clusters

### 2a. Inspect Cluster B's mesh status

```bash
cilium clustermesh status --context kind-cluster-b
```

Note the mesh endpoint — for NodePort this is the node IP and port; for LoadBalancer the assigned LB IP; for ClusterIP the tunneled/reachable address you set up in Step 1. This is the address Cluster A will connect to.

### 2b. Connect Cluster A → Cluster B

```bash
cilium clustermesh connect --context kind-cluster-a --destination-context kind-cluster-b
```

This command:
1. Reads the TLS certificates from Cluster A
2. Connects to Cluster B's exposed `cilium-clustermesh` service (NodePort, LoadBalancer, or tunneled ClusterIP — whichever you chose in Step 1)
3. Establishes an encrypted Wireguard (or VXLAN) tunnel
4. Begins bidirectional endpoint and service sync

### 2c. Verify the mesh connection — on BOTH sides

```bash
cilium clustermesh status --context kind-cluster-a
cilium clustermesh status --context kind-cluster-b
```

**Expected output on both:**
```
Number of cluster meshed: 1
Cluster "cluster-b" (or "cluster-a"): configured, connected
```

If you see `disconnected` or `failed`, check that the mesh service endpoint (NodePort, LoadBalancer IP, or tunneled address from Step 1) is reachable from the other cluster.

### 2c(i). Troubleshooting: Cilium CA certificate mismatch

If `cilium clustermesh connect` fails with:

```
Error: Unable to connect cluster: Cilium CA certificates do not match between clusters
cluster-a and cluster-b. Use --allow-mismatching-ca to allow this by adding remote CAs
to the CA bundle
```

This means each cluster generated its **own** self-signed CA when `clustermesh enable` ran, so Cluster A does not trust Cluster B's certificates (and vice versa). Fix it one of two ways:

**Option 1 — Allow the mismatch (fast, recommended for labs/demos):**

Add `--allow-mismatching-ca` to the connect command. This appends the remote cluster's CA to the local CA bundle so both sides trust each other:

```bash
cilium clustermesh connect \
  --context kind-cluster-a \
  --destination-context kind-cluster-b \
  --allow-mismatching-ca
```

**Option 2 — Share a single CA (proper, recommended for production):**

Use the *same* CA on both clusters instead of letting each generate its own. Pre-create a shared CA secret on both clusters, then enable the mesh pointing at it:

```bash
# Generate (or reuse) a single CA, then create the secret on BOTH clusters
kubectl create secret generic cilium-ca \
  --namespace kube-system \
  --from-file=ca.crt=ca.crt --from-file=ca.key=ca.key \
  --context kind-cluster-a
kubectl create secret generic cilium-ca \
  --namespace kube-system \
  --from-file=ca.crt=ca.crt --from-file=ca.key=ca.key \
  --context kind-cluster-b

# Re-enable the mesh using the shared CA on both clusters
cilium clustermesh enable --context kind-cluster-a --service-type NodePort
cilium clustermesh enable --context kind-cluster-b --service-type NodePort

# Connect — no --allow-mismatching-ca needed
cilium clustermesh connect --context kind-cluster-a --destination-context kind-cluster-b
```

> With Option 2 the CAs already match, so the connect command succeeds without the flag.

### 2d. Check Cilium node list to see remote nodes

```bash
kubectl get ciliumnode --context kind-cluster-a
kubectl get ciliumnode --context kind-cluster-b
```

Both clusters should show **both** their own node and the remote cluster's node entries.

```mermaid
graph TB
    subgraph "🔵 Cluster A"
        CA_CM["🌉 Cluster Mesh Controller"]
        CA_EP["📋 Endpoint Discovery"]
    end
    subgraph "🟢 Cluster B"
        CB_CM["🌉 Cluster Mesh Controller"]
        CB_EP["📋 Endpoint Discovery"]
    end
    CA_CM -- "1️⃣ Establish Wireguard/VXLAN tunnel" --> CB_CM
    CB_CM -- "2️⃣ Accept & encrypt" --> CA_CM
    CA_EP -- "3️⃣ Sync Service endpoints" --> CB_EP
    CB_EP -- "4️⃣ Sync Service endpoints" --> CA_EP
    style CA_CM fill:#4A90D9,stroke:#2C5F8A,color:#fff
    style CB_CM fill:#4A90D9,stroke:#2C5F8A,color:#fff
```

---

## 🌐 Cross-Environment Clusters (different networks / no direct reachability)

> **Note:** This section applies when the two clusters live in **separate networks**
> (different VPCs, on-prem ↔ cloud, regions with no peering) — *not* the default
> local kind exercise, where both clusters share one Docker network and reach each other
> directly via NodePort + mTLS. For the local kind exercise, you do **not** need
> WireGuard, a VPN, or MetalLB.

When the two clusters live in **different environments or networks** (separate VPCs, on-prem ↔ cloud, different regions with no peering), Cluster A cannot reach Cluster B's `cilium-clustermesh` endpoint directly. The secure, production-grade pattern is:

1. Keep the mesh API **internal** (`ClusterIP`) — never expose it via NodePort/LoadBalancer to the public internet.
2. Build an **encrypted site-to-site tunnel** between the two networks (WireGuard or cloud IPsec).
3. Use a **single shared CA** so the clusters mutually authenticate over mTLS (no `--allow-mismatching-ca`).

This gives you defense-in-depth: the transport tunnel encrypts the data plane, and ClusterMesh's own mTLS (shared CA) authenticates each cluster. On an untrusted network you want **both**; on a trusted local network, mTLS alone (the default kind exercise) is sufficient.

### A. Shared CA (do this first — required for all options)

Generate one CA and install the **same** secret on both clusters so their certificates are trusted:

```bash
# Create a CA once (or reuse an existing internal CA)
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout ca.key -out ca.crt -days 3650 \
  -subj "/CN=clustermesh-ca"

# Install the SAME ca.crt/ca.key on both clusters
kubectl create secret generic cilium-ca -n kube-system \
  --from-file=ca.crt=ca.crt --from-file=ca.key=ca.key \
  --context kind-cluster-a
kubectl create secret generic cilium-ca -n kube-system \
  --from-file=ca.crt=ca.crt --from-file=ca.key=ca.key \
  --context kind-cluster-b
```

Then enable the mesh as `ClusterIP` on both (no public exposure):

```bash
cilium clustermesh enable --context kind-cluster-a --service-type ClusterIP
cilium clustermesh enable --context kind-cluster-b --service-type ClusterIP
```

### B. Option 1 — WireGuard site-to-site (most aligned with Cilium)

Run a WireGuard tunnel between a gateway node/router in each cluster. The `cilium-clustermesh` `ClusterIP` is only reachable through that tunnel.

```bash
# On Cluster A's gateway host (example keys — generate your own)
wg genkey | tee a_privatekey | wg pubkey > a_publickey
wg genkey | tee b_privatekey | wg pubkey > b_publickey

# Cluster A gateway → peer with Cluster B gateway
wg set wg0 private-key ./a_privatekey \
  peer "$(cat b_publickey)" \
  allowed-ips 0.0.0.0/0 \
  endpoint <B-GATEWAY-PUBLIC-IP>:51820 \
  persistent-keepalive 25
ip link set wg0 up

# Mirror the symmetric config on Cluster B's gateway (peer = A's public key + endpoint)
```

Route the remote cluster's pod/servcie CIDR through the tunnel, then connect pointing at the **tunnel-reachable** address:

```bash
cilium clustermesh connect --context kind-cluster-a \
  --destination-context kind-cluster-b \
  --destination-api-server https://<B-CLUSTER-INTERNAL-IP>:32379
```

WireGuard already encrypts with AEAD ciphers, so it stacks cleanly on top of ClusterMesh mTLS.

### C. Option 2 — Cloud IPsec / provider VPN (AWS Transit Gateway, GCP Cloud VPN, Azure VPN Gateway)

If the clusters run in cloud VPCs, use the provider's managed encrypted peering instead of rolling your own WireGuard:

- **AWS:** VPC peering or Transit Gateway + Site-to-Site VPN (IPsec).
- **GCP:** Cloud VPN (HA VPN, IPsec) between the two VPC networks.
- **Azure:** VPN Gateway (IPsec/IKE) or ExpressRoute.

After the private tunnel/VPC peering is up, the `cilium-clustermesh` `ClusterIP` becomes reachable over the private link:

```bash
cilium clustermesh connect --context kind-cluster-a \
  --destination-context kind-cluster-b \
  --destination-api-server https://<B-CLUSTER-INTERNAL-IP>:32379
```

Provider-managed IPsec means you get encryption and IKE key rotation without managing it yourself.

### D. Option 3 — Central/shared CA + mTLS over the tunnel (security baseline)

Regardless of which transport (WireGuard or cloud VPN) you choose, the security baseline is the **shared CA from section A**. This ensures:

- Each cluster proves its identity to the other via mutual TLS (no anonymous handshake).
- A compromised node in one network cannot impersonate the other cluster's apiserver.
- You avoid `--allow-mismatching-ca`, which would blindly trust any remote CA.

> **Do not** expose `cilium-clustermesh` via NodePort/LoadBalancer to the public internet. Even though ClusterMesh uses TLS, a public endpoint dramatically increases attack surface. Keep it `ClusterIP` and reach it only through the encrypted tunnel.

---

## Step 3 — Deploy the Backend Service (on Cluster B)

### 3a. Create the deployment and service YAML

```yaml
# deploy-backend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: http
        image: hashicorp/http-echo:latest
        args:
          - "-text=Hello from Cluster B! 🎉"
          - "-listen=:8080"
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: default
spec:
  selector:
    app: backend
  ports:
    - port: 8080
      targetPort: 8080
```

### 3b. Apply to Cluster B

```bash
kubectl apply --context kind-cluster-b -f deploy-backend.yaml
```

### 3c. Verify the deployment and service

```bash
kubectl get pods --context kind-cluster-b -l app=backend
kubectl get svc --context kind-cluster-b backend
kubectl describe svc --context kind-cluster-b backend
```

**Expected output:** 2 pods `Running`, service `backend` with ClusterIP `10.3.x.x`.

---

## Step 4 — Export the Service to the Cluster Mesh

### 4a. Annotate the service as globally visible

```bash
kubectl annotate service backend --context kind-cluster-b "cilium.io/global-service=true"
```

### 4b. Verify the export was registered

```bash
kubectl get ciliumserviceexport --context kind-cluster-b -A
kubectl get ciliumserviceimport --context kind-cluster-a -A
kubectl get ciliumserviceimport --context kind-cluster-b -A
```

**Expected output:** A `CiliumServiceExport` exists on Cluster B, and a matching `CiliumServiceImport` exists on **both** clusters.

### 4c. (Alternative) Confirm via Cilium CLI

```bash
cilium service list --context kind-cluster-a
cilium service list --context kind-cluster-b
```

Cluster A will now show a `backend` service entry with backends pointing to **Cluster B's pods**, even though those pods are in a different cluster.

---

## Step 5 — Deploy an Ubuntu Debug Pod (with full network tools)

We'll deploy a **single self-contained manifest** (`ubuntu-debug.yaml`) that adds a `ubuntu-debug` pod to the test environment with **everything** needed for testing already installed in one go: `curl`, `nc`, `nslookup`, `dig`, `ping`, `tcpdump`, `nmap`, `traceroute`, `mtr`, `iperf3`, `socat`, `ethtool`, `conntrack`, `arping`, and more. No separate post-deploy install step is required.

```bash
# Deploy the debug pod on Cluster A (the caller side) with one command
kubectl apply --context kind-cluster-a -f ubuntu-debug.yaml

# Wait for it to be Running
kubectl wait --context kind-cluster-a --for=condition=Ready pod/ubuntu-debug --timeout=300s
```

The pod installs its network tools automatically on first start (~100–200MB download). Once `Running`, all later tests run directly inside it:

```bash
kubectl exec --context kind-cluster-a -it ubuntu-debug -- bash
```

---

## Step 6 — Test Cross-Cluster Connectivity

### 6a. Basic HTTP test with curl (DNS name)

```bash
kubectl exec --context kind-cluster-a -it ubuntu-debug -- curl -v http://backend.default.svc.cluster.local:8080
```

**Expected response:**
```
Hello from Cluster B! 🎉
```

### 6b. Test with curl (just the service name — same namespace)

```bash
kubectl exec --context kind-cluster-a -it ubuntu-debug -- curl -s http://backend:8080
```

**Expected:** Same result as above.

### 6c. Test with netcat (raw TCP connection)

```bash
kubectl exec --context kind-cluster-a -it ubuntu-debug -- bash -c 'echo -e "GET / HTTP/1.0\r\nHost: backend\r\n\r\n" | nc -w 3 backend 8080'
```

**Expected:** The HTTP response with `Hello from Cluster B! 🎉`.

### 6d. Test by ClusterIP directly

```bash
# Get the backend ClusterIP that Cluster A sees
BACKEND_IP=$(kubectl get svc --context kind-cluster-a backend -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo "Backend ClusterIP visible on A: $BACKEND_IP"

# If the above returns empty, get it from Cluster B (same IP should appear on A)
BACKEND_IP=$(kubectl get svc --context kind-cluster-b backend -o jsonpath='{.spec.clusterIP}')
echo "Backend ClusterIP on B: $BACKEND_IP"

# Curl directly by IP
kubectl exec --context kind-cluster-a -it ubuntu-debug -- curl -s http://"$BACKEND_IP":8080
```

### 6e. Verify DNS resolution

```bash
kubectl exec --context kind-cluster-a -it ubuntu-debug -- nslookup backend.default.svc.cluster.local
```

**Expected output:** The DNS name resolves to the backend's ClusterIP.

```bash
kubectl exec --context kind-cluster-a -it ubuntu-debug -- dig backend.default.svc.cluster.local +short
```

**Expected output:** The ClusterIP address (e.g., `10.1.0.x`).

### 6f. Test negative case: verify it fails BEFORE mesh is disconnected

```bash
# This should STILL work (the mesh is up)
kubectl exec --context kind-cluster-a -it ubuntu-debug -- curl -s --connect-timeout 3 http://backend:8080
```

Now **temporarily disable the mesh** and confirm it breaks:

```bash
# Disconnect the mesh momentarily to prove cross-cluster routing is real
cilium clustermesh disconnect --context kind-cluster-a

# Now try again — should FAIL
kubectl exec --context kind-cluster-a -it ubuntu-debug -- curl -s --connect-timeout 5 http://backend:8080
```

**Expected:** Connection timeout / failure.

```bash
# Reconnect
cilium clustermesh connect --context kind-cluster-a --destination-context kind-cluster-b
# Wait for reconnection
sleep 5
cilium clustermesh status --context kind-cluster-a
```

```bash
# Verify it works again
kubectl exec --context kind-cluster-a -it ubuntu-debug -- curl -s --connect-timeout 5 http://backend:8080
```

**Expected:** `Hello from Cluster B! 🎉` — the mesh heals automatically.

---

## Step 7 — Observe with Hubble

### 7a. Port-forward Hubble UI

```bash
kubectl --context kind-cluster-a port-forward -n kube-system svc/hubble-ui 12000:80
```

Open **[http://localhost:12000](http://localhost:12000)** in your browser.

### 7b. Generate traffic and watch in Hubble

While the Hubble UI is open, run the curl test again:

```bash
kubectl exec --context kind-cluster-a -it ubuntu-debug -- curl -s http://backend:8080
```

In the Hubble UI you'll see the flow:
```
ubuntu-debug (cluster-a) ────► backend (cluster-b)   port 8080   ✅
```

### 7c. Hubble via CLI (alternative)

```bash
cilium hubble port-forward --context kind-cluster-a &
sleep 2
hubble observe --from-pod default/ubuntu-debug
```

You'll see the TCP handshake and HTTP request crossing the mesh.

```mermaid
graph LR
    subgraph "🖥️ Hubble UI @ localhost:12000"
        UI["📊 Real-time Service Map<br/>Shows cross-cluster flows"]
    end
    subgraph "🔵 Cluster A"
        HUB_A["🔭 Hubble Relay A"]
    end
    subgraph "🟢 Cluster B"
        HUB_B["🔭 Hubble Relay B"]
    end
    HUB_A -- "📤 Service flow telemetry" --> UI
    HUB_B -- "📤 Service flow telemetry" --> UI
    style UI fill:#F8E71C,stroke:#B3A100,color:#000
```

---

## 🗺️ Complete Traffic Flow (Packet Walk)

```mermaid
flowchart LR
    subgraph "🔵 Cluster A"
        A_POD["🏢 Pod: ubuntu-debug<br/>10.0.1.10"]
        A_CIL["🛡️ Cilium eBPF<br/>@ Node A"]
        A_RESOLVE["🔍 DNS resolves<br/>backend → 10.1.0.50<br/>(ClusterIP on A)"]
    end
    subgraph "🌉 Cluster Mesh Tunnel"
        TUNNEL["🔗 Wireguard Tunnel<br/>Encrypted"]
    end
    subgraph "🟢 Cluster B"
        B_CIL["🛡️ Cilium eBPF<br/>@ Node B"]
        B_SVC["📡 Service: backend<br/>ClusterIP: 10.3.0.50"]
        B_POD["🏢 Pod: backend-v1<br/>10.2.1.10"]
    end
    A_POD -- "1️⃣ HTTP GET :8080" --> A_RESOLVE
    A_RESOLVE -- "2️⃣ Dest IP = backend ClusterIP" --> A_CIL
    A_CIL -- "3️⃣ eBPF sees remote endpoint<br/>→ encapsulates packet" --> TUNNEL
    TUNNEL -- "4️⃣ Wireguard decrypt" --> B_CIL
    B_CIL -- "5️⃣ DNAT + route to local pod" --> B_SVC
    B_SVC -- "6️⃣ Forward" --> B_POD
    B_POD -- "7️⃣ 'Hello from Cluster B!' 🎉" --> B_CIL
    B_CIL -- "8️⃣ Encrypt + send back" --> TUNNEL
    TUNNEL -- "9️⃣ Decrypt @ A" --> A_CIL
    A_CIL -- "🔟 Deliver response" --> A_POD
    style TUNNEL fill:#F5A623,stroke:#D4891E,color:#fff
    style A_CIL fill:#4A90D9,stroke:#2C5F8A,color:#fff
    style B_CIL fill:#7ED321,stroke:#4A8C12,color:#fff
```

---

## ✅ Complete Verification Checklist

| # | Step | Action | Verify With |
|---|------|--------|-------------|
| 1 | Create clusters | `kind create cluster --config kind-bpf-a.yaml` | `kind get clusters` → `cluster-a`, `cluster-b` |
| 2 | Identify contexts | built-in | `kubectl config get-contexts` → `kind-cluster-a`, `kind-cluster-b` |
| 3 | Nodes ready | `kubectl get nodes --context kind-cluster-a` | All `Ready` |
| 4 | Create shared CA (mTLS root) | `openssl ...` + `kubectl create secret cilium-ca` on both | Both clusters share the same `cilium-ca` secret |
| 5 | Assign cluster IDs | `--set cluster.id=1` on A, `--set cluster.id=2` on B (or `cilium config set`) | `cilium config view` shows unique IDs |
| 6 | Install Cilium A | `cilium install --context kind-cluster-a --set cluster.id=1 ... --set clustermesh.apiserver.tls.ca.*` | `cilium status --context kind-cluster-a --wait` → `OK` |
| 7 | Install Cilium B | `cilium install --context kind-cluster-b --set cluster.id=2 ... --set clustermesh.apiserver.tls.ca.*` | `cilium status --context kind-cluster-b --wait` → `OK` |
| 7 | Connectivity test | `cilium connectivity test --context kind-cluster-a` | All checks pass |
| 8 | Enable mesh A | `cilium clustermesh enable --context kind-cluster-a --service-type <NodePort\|LoadBalancer\|ClusterIP>` | `cilium clustermesh status` shows enabled |
| 9 | Enable mesh B | `cilium clustermesh enable --context kind-cluster-b --service-type <NodePort\|LoadBalancer\|ClusterIP>` | `cilium clustermesh status` shows enabled |
| 10 | Connect clusters | `cilium clustermesh connect --context kind-cluster-a --destination-context kind-cluster-b` | `cilium clustermesh status` → `Connected` on both |
| 11 | Remote nodes seen | `kubectl get ciliumnode --context kind-cluster-a` | Shows node from both clusters |
| 12 | Deploy backend B | `kubectl apply --context kind-cluster-b -f deploy-backend.yaml` | `kubectl get pods --context kind-cluster-b` → `Running` |
| 13 | Export service | `kubectl annotate service backend --context kind-cluster-b "cilium.io/global-service=true"` | `kubectl get ciliumserviceimport --context kind-cluster-a -A` → exists |
| 14 | Deploy debug pod A | `kubectl apply --context kind-cluster-a -f ubuntu-debug.yaml` | `kubectl wait --for=condition=Ready pod/ubuntu-debug` |
| 15 | Install tools | Tools auto-installed by `ubuntu-debug.yaml` pod | Tools available in pod |
| 16 | curl DNS name | `curl backend.default.svc.cluster.local:8080` | `Hello from Cluster B! 🎉` |
| 17 | curl short name | `curl backend:8080` | `Hello from Cluster B! 🎉` |
| 18 | nc raw TCP | `echo 'GET / HTTP/1.0' \| nc -w 3 backend 8080` | HTTP 200 response |
| 19 | curl by ClusterIP | `curl <ClusterIP>:8080` | `Hello from Cluster B! 🎉` |
| 20 | DNS resolve | `nslookup backend.default.svc.cluster.local` | ClusterIP returned |
| 21 | dig short | `dig backend.default.svc.cluster.local +short` | ClusterIP returned |
| 22 | Hubble visual | Port-forward → browser | Flow visible in UI |
| 23 | Disconnect test | `cilium clustermesh disconnect --context kind-cluster-a` | curl → **fails** |
| 24 | Reconnect test | `cilium clustermesh connect ...` | curl → **works again** |

---

## 🧹 Full Teardown

```bash
# Remove the debug pod
kubectl delete pod --context kind-cluster-a ubuntu-debug

# Remove the backend deployment and service
kubectl delete -f deploy-backend.yaml --context kind-cluster-b 2>/dev/null

# Disconnect the mesh
cilium clustermesh disconnect --context kind-cluster-a 2>/dev/null

# Disable the mesh on both clusters
cilium clustermesh disable --context kind-cluster-a 2>/dev/null
cilium clustermesh disable --context kind-cluster-b 2>/dev/null

# List and delete all Kind clusters
kind get clusters
kind get clusters | xargs -I {} kind delete cluster --name {}
```

---

## 🎯 Summary

```mermaid
graph TB
    START["🚦 Start: Two isolated Kind clusters"]
    IDENTIFY["🔍 Identify cluster contexts<br/>kind get clusters + kubectl config get-contexts"]
    ASSIGN_ID["🆔 Assign unique cluster IDs<br/>Cluster A → ID=1, name=cluster-a<br/>Cluster B → ID=2, name=cluster-b"]
    INSTALL["🛡️ Install Cilium on both<br/>cilium install + status --wait"]
    TEST_INSTALL["✅ Cilium connectivity test<br/>cilium connectivity test"]
    ENABLE["🌉 Enable Cluster Mesh API<br/>cilium clustermesh enable --service-type NodePort"]
    CONNECT["🔗 Connect the clusters<br/>cilium clustermesh connect"]
    VERIFY_CONN["👀 Verify connection<br/>cilium clustermesh status → Connected"]
    DEPLOY["📦 Deploy backend on B"]
    EXPORT["🌍 Export service as Global<br/>cilium.io/global-service=true"]
    DEPLOY_DEBUG["🐧 Deploy Ubuntu debug pod on A<br/>+ install curl nc dnsutils"]
    TEST["🧪 Test: curl, nc, nslookup, dig<br/>across the mesh"]
    HUBBLE["🔭 Observe with Hubble UI"]

    START --> IDENTIFY --> ASSIGN_ID --> INSTALL --> TEST_INSTALL --> ENABLE --> CONNECT
    CONNECT --> VERIFY_CONN --> DEPLOY --> EXPORT --> DEPLOY_DEBUG --> TEST --> HUBBLE

    style START fill:#4A90D9,stroke:#2C5F8A,color:#fff
    style TEST fill:#7ED321,stroke:#4A8C12,color:#fff
    style HUBBLE fill:#F8E71C,stroke:#B3A100,color:#000
```

**Key takeaway:** Once Cilium Cluster Mesh is configured, a service in one cluster is reachable from another cluster **by the same DNS name** — no external load balancers, no VPN, no complex networking configuration. It just works. ✨
