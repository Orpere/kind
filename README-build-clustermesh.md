# build-clustermesh.sh — Cilium ClusterMesh Lab on kind

A single, self-contained Bash script that builds a working **Cilium ClusterMesh**
between two local [kind](https://kind.sigs.k8s.io/) clusters and proves it with an
end-to-end cross-cluster request.

```bash
./build-clustermesh.sh
```

When it finishes you get two connected clusters, a global `backend` service shared
across them, and a verified `Hello from Cluster B! 🎉` response served from
`cluster-b` to a pod in `cluster-a`.

---

## What it does (phases)

| Phase | Action | Result |
|-------|--------|--------|
| 0 | Prerequisite check | Confirms `kind`, `kubectl`, `docker`, `cilium`, `openssl` are present |
| 1 | Create clusters | `cluster-a` + `cluster-b` (eBPF kube-proxy replacement, no default CNI) |
| 2 | Shared CA | Pushes the local `ca.crt`/`ca.key` into both clusters as the `cilium-ca` secret (mTLS trust root) |
| 3 | Install Cilium | Full feature set on both: Hubble Relay + UI, metrics, `clustermesh.enableEndpointSliceSynchronization`, mTLS via shared CA |
| 4 | Enable mesh | `clustermesh enable --service-type NodePort` on both, waits for the apiserver |
| 5 | Connect | `clustermesh connect` links the two clusters (mTLS over the shared CA) |
| 6 | Global service | Deploys `backend` in `cluster-b` and the identical Service in `cluster-a`, annotated `service.cilium.io/global=true` |
| 7 | Test | Runs a `curlimages/curl` pod in `cluster-a`, resolves `backend` via DNS and curls it across the mesh; prints ClusterMesh status + remote nodes |

The temporary test pod is removed automatically on exit (via `trap`).

---

## Topology diagram

### Component diagram (what the script deploys)

```mermaid
flowchart TB
    subgraph HOST["💻 Local machine — Docker"]
        direction LR
        subgraph A["🐳 kind cluster-a"]
            direction TB
            ANODE["🖥️ Nodes<br/>control-plane + worker"]
            ACIL["🛡️ Cilium<br/>agent + operator<br/>kube-proxy → eBPF"]
            AHUB["📊 Hubble<br/>Relay + UI"]
            ACA["🔑 Secret cilium-ca<br/>(shared mTLS root)"]
            ATEST["🧪 mesh-test<br/>curlimages/curl"]
        end

        subgraph B["🐳 kind cluster-b"]
            direction TB
            BNODE["🖥️ Nodes<br/>control-plane + worker"]
            BCIL["🛡️ Cilium<br/>agent + operator<br/>kube-proxy → eBPF"]
            BHUB["📊 Hubble<br/>Relay + UI"]
            BCA["🔑 Secret cilium-ca<br/>(same mTLS root)"]
            BBE["📦 backend ×2<br/>http-echo"]
            BSV["📦 Service backend<br/>global=true"]
        end
    end

    AAPI(("🌉 clustermesh-apiserver<br/>etcd · kvstore")):::cp
    BAPI(("🌉 clustermesh-apiserver<br/>etcd · kvstore")):::cp

    ANODE --- ACIL
    ACIL --- AHUB
    ACIL -.->|adopts| ACA
    ATEST --- ACIL

    BNODE --- BCIL
    BCIL --- BHUB
    BCIL -.->|adopts| BCA
    BBE --- BCIL
    BSV --- BBE

    ACA ===|"🔐 identical CA<br/>(mTLS)"| BCA
    AAPI <==>|"🔐 mTLS over mesh"| BAPI
    ACIL -.->|"sync endpoints<br/>(NodePort)"| AAPI
    BCIL -.->|"sync endpoints<br/>(NodePort)"| BAPI

    classDef cp fill:#7D3C98,stroke:#5B2C6F,color:#fff;
    classDef ca fill:#8E44AD,stroke:#5B2C6F,color:#fff;
    classDef cilium fill:#2471A3,stroke:#1A5276,color:#fff;
    classDef hub fill:#16A085,stroke:#117864,color:#fff;
    classDef workload fill:#27AE60,stroke:#1E8449,color:#fff;
    classDef svc fill:#2E86C1,stroke:#1F618D,color:#fff;
    classDef node fill:#154360,stroke:#1A5276,color:#fff;

    class ANODE,BNODE node;
    class ACA,BCA ca;
    class ACIL,BCIL cilium;
    class AHUB,BHUB hub;
    class ATEST,BBE workload;
    class BSV svc;
```

**Legend:** 🖥️ nodes · 🛡️ Cilium CNI/Proxy · 📊 Hubble observability · 🔑 shared
trust root (CA) · 📦 workload · 🌉 ClusterMesh control plane (etcd + kvstore).

---

### Request flow (cross-cluster test)

```mermaid
sequenceDiagram
    autonumber
    participant T as 🧪 mesh-test<br/>(cluster-a)
    participant CA as 🛡️ Cilium A
    participant API as 🌉 apiserver A
    participant API2 as 🌉 apiserver B
    participant CB as 🛡️ Cilium B
    participant S as 📦 backend<br/>(cluster-b)

    T->>CA: curl backend:8080 (DNS resolve)
    CA->>API: lookup global service endpoints
    API-->>CA: remote endpoints (cluster-b pods)
    CA->>API2: 🔐 mTLS request over mesh (NodePort)
    API2->>CB: route to remote backend
    CB->>S: forward to pod
    S-->>CB: "Hello from Cluster B! 🎉"
    CB->>API2: 🔐 mTLS response
    API2->>CA: return over mesh
    CA-->>T: response delivered
```

**Flow in one sentence:** a pod in `cluster-a` asks for `backend`; Cilium resolves it
to `cluster-b`'s pods, signs and encrypts the request with mTLS (shared CA), sends it
across the local Docker network to `cluster-b`, where Cilium delivers it to the
`backend` pods and returns `Hello from Cluster B! 🎉`.

---

## Prerequisites

- `kind`, `kubectl`, `docker`, `cilium` CLI, `openssl`
- A `ca.crt` + `ca.key` in this directory (the script generates a 10-year CA if missing)
- The manifest files alongside the script: `kind-bpf-a.yaml`, `kind-bpf-b.yaml`,
  `deploy-backend.yaml`, `deploy-backend-service.yaml`

> 💡 The script leaves the two clusters **running** when it finishes so you can explore
> (e.g. `cilium hubble ui --context kind-cluster-a`). Delete them with
> `kind get clusters | xargs -I {} kind delete cluster --name {}`.

---

## Key implementation notes

- **kube-proxy replacement (eBPF):** the kind configs set `disableDefaultCNI: true`
  and `kubeProxyMode: "none"`, so Cilium fully owns service load-balancing and
  cross-cluster routing.
- **Shared CA = mTLS:** both clusters trust the *same* `cilium-ca` secret, so the
  ClusterMesh control plane is mutually authenticated and encrypted. The secret is
  labelled `app.kubernetes.io/managed-by=Helm` so the Cilium Helm install can adopt it.
- **Global service annotation:** the correct key is
  `service.cilium.io/global=true`. Cilium only syncs **endpoints** across the mesh —
  it does **not** create the `Service` object remotely — so the identical `backend`
  Service must exist in **both** clusters (hence `deploy-backend-service.yaml`).
- **`clustermesh.enableEndpointSliceSynchronization=true`** is required so the remote
  endpoints are merged into the local `backend` Service.
- **Test pod choice:** `curlimages/curl` is used instead of `ubuntu-debug.yaml`
  because the latter installs tools via `apt-get`, which needs pod internet egress.

---

## What gets created

| Object | Cluster | Purpose |
|--------|---------|---------|
| `cluster-a` / `cluster-b` | Docker | The two kind clusters |
| `cilium-ca` secret | both | Shared mTLS trust root |
| Cilium + Hubble | both | CNI, observability, metrics |
| `clustermesh-apiserver` (NodePort) | both | Mesh control plane + etcd |
| `backend` Deployment + Service (`global`) | cluster-b | The shared application |
| `backend` Service (`global`) | cluster-a | Remote endpoint merge target |
| `mesh-test` pod (temp) | cluster-a | Runs the cross-cluster curl, then deleted |
