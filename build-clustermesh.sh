#!/usr/bin/env bash
#
# build-clustermesh.sh
#
# Builds two kind clusters (cluster-a / cluster-b) with eBPF kube-proxy replacement,
# installs Cilium with the full feature set (Hubble Relay + UI, metrics, mTLS via a
# shared CA), connects them with ClusterMesh, and runs an end-to-end cross-cluster
# connectivity test.
#
# Prerequisites: kind, kubectl, docker, cilium CLI, openssl
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_A="cluster-a"
CLUSTER_B="cluster-b"
CTX_A="kind-cluster-a"
CTX_B="kind-cluster-b"
CA_CRT="ca.crt"
CA_KEY="ca.key"
CILIUM_VERSION="1.19.3"
SERVICE_TYPE="NodePort"          # NodePort works on kind without MetalLB
GLOBAL_ANNOTATION="service.cilium.io/global=true"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log()  { echo -e "\n\033[1;34m==>\033[0m \033[1m$*\033[0m"; }
ok()   { echo -e "\033[32m✓\033[0m $*"; }
warn() { echo -e "\033[33m!\033[0m $*"; }
die()  { echo -e "\033[31m✗\033[0m $*" >&2; exit 1; }

for bin in kind kubectl docker cilium openssl; do
  command -v "$bin" >/dev/null || die "$bin is not installed"
done

# Deploy the shared CA secret (tagged so Helm can adopt it) into one cluster.
apply_ca() {
  local ctx=$1
  kubectl --context "$ctx" -n kube-system create secret generic cilium-ca \
    --from-file=ca.crt="$SCRIPT_DIR/$CA_CRT" \
    --from-file=ca.key="$SCRIPT_DIR/$CA_KEY" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  kubectl --context "$ctx" -n kube-system label secret cilium-ca \
    app.kubernetes.io/managed-by=Helm --overwrite
  kubectl --context "$ctx" -n kube-system annotate secret cilium-ca \
    meta.helm.sh/release-name=cilium meta.helm.sh/release-namespace=kube-system --overwrite
}

# Install Cilium with the full feature set on one cluster.
install_cilium() {
  local ctx=$1 name=$2 id=$3
  cilium install --context "$ctx" \
    --version "$CILIUM_VERSION" \
    --set "cluster.name=$name" \
    --set "cluster.id=$id" \
    --set tls.caSecretName=cilium-ca \
    --set clustermesh.enableEndpointSliceSynchronization=true \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set "hubble.metrics.enabled={dns,drop,tcp,flow,port-distribution,icmp,http}" \
    --wait
}

cleanup_test_pod() {
  kubectl delete pod mesh-test --context "$CTX_A" --ignore-not-found >/dev/null 2>&1 || true
}

# ----------------------------------------------------------------------------
# Phase 0 — Prerequisites
# ----------------------------------------------------------------------------
log "Phase 0: Prerequisites"
echo "kind:   $(kind version 2>/dev/null | head -1)"
echo "cilium: $(cilium version 2>/dev/null | head -1)"
ok "tools present"

# ----------------------------------------------------------------------------
# Phase 1 — Create the two kind clusters
# ----------------------------------------------------------------------------
log "Phase 1: Create kind clusters (eBPF / kube-proxy replacement)"
for cfg in kind-bpf-a.yaml kind-bpf-b.yaml; do
  [ -f "$SCRIPT_DIR/$cfg" ] || die "missing $cfg in $SCRIPT_DIR"
done
kind create cluster --config "$SCRIPT_DIR/kind-bpf-a.yaml" --name "$CLUSTER_A"
kind create cluster --config "$SCRIPT_DIR/kind-bpf-b.yaml" --name "$CLUSTER_B"
ok "clusters created: $(kind get clusters | tr '\n' ' ')"

# ----------------------------------------------------------------------------
# Phase 2 — Shared CA (mTLS trust root)
# ----------------------------------------------------------------------------
log "Phase 2: Create shared CA and push to both clusters"
if [ ! -f "$SCRIPT_DIR/$CA_CRT" ] || [ ! -f "$SCRIPT_DIR/$CA_KEY" ]; then
  warn "CA not found — generating a fresh shared CA (10y)"
  openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$SCRIPT_DIR/$CA_KEY" -out "$SCRIPT_DIR/$CA_CRT" -days 3650 -subj "/CN=clustermesh-ca"
fi
apply_ca "$CTX_A"
apply_ca "$CTX_B"
ok "shared CA applied to both clusters"

# ----------------------------------------------------------------------------
# Phase 3 — Install Cilium (full feature set)
# ----------------------------------------------------------------------------
log "Phase 3: Install Cilium (full feature set) on both clusters"
install_cilium "$CTX_A" "$CLUSTER_A" 1
install_cilium "$CTX_B" "$CLUSTER_B" 2
cilium status --context "$CTX_A" --wait
cilium status --context "$CTX_B" --wait
ok "Cilium ready (Hubble Relay + UI enabled)"

# ----------------------------------------------------------------------------
# Phase 4 — Enable ClusterMesh (NodePort) and connect
# ----------------------------------------------------------------------------
log "Phase 4: Enable ClusterMesh (service-type=$SERVICE_TYPE)"
cilium clustermesh enable --context "$CTX_A" --service-type "$SERVICE_TYPE"
cilium clustermesh enable --context "$CTX_B" --service-type "$SERVICE_TYPE"
# Wait for both apiserver deployments to be ready before connecting.
for ctx in "$CTX_A" "$CTX_B"; do
  kubectl --context "$ctx" -n kube-system rollout status deploy/clustermesh-apiserver --timeout=180s
done

log "Phase 5: Connect clusters"
cilium clustermesh connect --context "$CTX_A" --destination-context "$CTX_B"
# Give agents a moment to establish node-to-node mesh connections.
sleep 30
ok "clusters connected"

# ----------------------------------------------------------------------------
# Phase 6 — Share a service across clusters (Cilium Global Service)
# ----------------------------------------------------------------------------
log "Phase 6: Deploy global backend service"
# Real backend in cluster-b (manifest already carries the global annotation).
kubectl apply --context "$CTX_B" -f "$SCRIPT_DIR/deploy-backend.yaml"
# Identical Service object in cluster-a: Cilium only syncs endpoints across the
# mesh, it does NOT create the Service remotely, so it must exist on both sides.
kubectl apply --context "$CTX_A" -f "$SCRIPT_DIR/deploy-backend-service.yaml"
kubectl wait --context "$CTX_B" --for=condition=Available deployment/backend --timeout=180s
# Wait for remote endpoints to sync into cluster-a. Poll the EndpointSlice instead of
# a fixed sleep: under load the Cilium endpoint sync can take well over 25s.
echo -n "  waiting for cluster-b backend endpoints to sync into cluster-a"
for i in $(seq 1 60); do
  if kubectl get endpointslices -l kubernetes.io/service-name=backend \
      --context "$CTX_A" -o jsonpath='{.items[0].endpoints}' 2>/dev/null \
      | grep -q 'addresses'; then
    echo " done"
    break
  fi
  sleep 5
  echo -n "."
done
ok "global service deployed"

# ----------------------------------------------------------------------------
# Phase 7 — End-to-end cross-cluster test
# ----------------------------------------------------------------------------
log "Phase 7: End-to-end cross-cluster test"
# Use a prebuilt image (curlimages/curl) so the test does NOT depend on pod
# internet egress for apt-get. (ubuntu-debug.yaml relies on apt and only works
# where pods have outbound internet access.)
trap cleanup_test_pod EXIT
kubectl run mesh-test --context "$CTX_A" \
  --image=curlimages/curl:latest --restart=Never \
  --command -- sh -c 'sleep 3600'
kubectl wait --context "$CTX_A" --for=condition=Ready pod/mesh-test --timeout=180s

echo "--- DNS resolution ---"
kubectl exec --context "$CTX_A" mesh-test -- \
  sh -c 'nslookup backend.default.svc.cluster.local || getent hosts backend.default.svc.cluster.local' || true

echo "--- HTTP request to backend in cluster-b via the mesh ---"
if out=$(kubectl exec --context "$CTX_A" mesh-test -- curl -s --max-time 15 backend:8080); then
  echo "$out"
  [ "$out" = "Hello from Cluster B! 🎉" ] \
    && ok "CROSS-CLUSTER CONNECTIVITY WORKS" \
    || die "unexpected response: $out"
else
  die "cross-cluster curl failed"
fi

echo "--- ClusterMesh status ---"
cilium clustermesh status --context "$CTX_A"

echo "--- Remote nodes visible from cluster-a (proves mesh is live) ---"
kubectl get ciliumnode --context "$CTX_A"

log "DONE — two clusters built, Cilium full features installed, mesh connected and tested."
echo "Hubble UI can be opened with: cilium hubble ui --context $CTX_A"
