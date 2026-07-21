#!/usr/bin/env bash
# rotate-keys.sh — Rotate GPG keys for Sealed Secrets across clusters
# Usage: ./rotate-keys.sh <cluster-context> <new-key-ascii-file>
# This script:
#   1. Fetches the current trusted keys from the cluster
#   2. Appends the new key
#   3. Updates the Kubernetes Secret
#   4. Re-encrypts all SealedSecrets in the target cluster
set -euo pipefail

CLUSTER="${1:?Usage: $0 <cluster-context> <new-key-file>}"
NEW_KEY_FILE="${2:?Usage: $0 <cluster-context> <new-key-file>}"
NAMESPACE="${3:-kube-system}"

cleanup() { rm -f current-keys.asc; }
trap cleanup EXIT

if [ ! -f "${NEW_KEY_FILE}" ]; then
  echo "Error: Key file not found: ${NEW_KEY_FILE}" >&2
  exit 1
fi

if ! grep -q "BEGIN PGP PUBLIC KEY BLOCK" "${NEW_KEY_FILE}"; then
  echo "Error: ${NEW_KEY_FILE} does not appear to be an ASCII-armored GPG public key" >&2
  exit 1
fi

echo "=== Step 1: Fetch current trusted keys from ${CLUSTER} ==="
kubectl --context "${CLUSTER}" get secret sealed-secrets-gpg-keys \
  -n "${NAMESPACE}" \
  -o jsonpath='{.data.secrets\.io}' | base64 -d > current-keys.asc

CURRENT_KEY_COUNT=$(grep -c "BEGIN PGP PUBLIC KEY BLOCK" current-keys.asc || true)
echo "Current trusted keys: ${CURRENT_KEY_COUNT}"

echo ""
echo "=== Step 2: Append new key (skip if already present) ==="
NEW_FP=$(gpg --with-fingerprint --with-colons "${NEW_KEY_FILE}" 2>/dev/null | grep '^fpr' | head -1 | cut -d: -f10)
if [ -n "${NEW_FP}" ] && grep -q "${NEW_FP}" current-keys.asc 2>/dev/null; then
  echo "Key fingerprint ${NEW_FP} already in trusted keys. Skipping append."
else
  cat "${NEW_KEY_FILE}" >> current-keys.asc
fi

NEW_KEY_COUNT=$(grep -c "BEGIN PGP PUBLIC KEY BLOCK" current-keys.asc || true)
echo "Updated trusted keys: ${NEW_KEY_COUNT}"

echo ""
echo "=== Step 3: Update Kubernetes Secret ==="
kubectl --context "${CLUSTER}" create secret generic sealed-secrets-gpg-keys \
  -n "${NAMESPACE}" \
  --from-file=secrets.io=current-keys.asc \
  --dry-run=client -o yaml | kubectl --context "${CLUSTER}" apply -f -

echo ""
echo "=== Step 4: Re-encrypt all SealedSecrets ==="
# Get all SealedSecrets across namespaces
SS_LIST=$(kubectl --context "${CLUSTER}" get sealedsecrets --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')

if [ -z "${SS_LIST}" ]; then
  echo "No SealedSecrets found to re-encrypt."
else
  echo "Re-encrypting SealedSecrets:"
  echo "${SS_LIST}" | while IFS='/' read -r ns name; do
    echo "  - ${ns}/${name}"
    kubectl --context "${CLUSTER}" get sealedsecret "${name}" -n "${ns}" -o yaml | \
      kubeseal --format gpg \
        --recovery-public-key current-keys.asc \
        --re-encrypt -o yaml | \
      kubectl --context "${CLUSTER}" apply -f -
  done
fi

echo ""
echo "=== Cleanup ==="
rm -f current-keys.asc

echo ""
echo "Key rotation complete for cluster: ${CLUSTER}"
echo "Next steps:"
echo "  1. Verify all SealedSecrets are decrypted correctly"
echo "  2. Revoke the old GPG key if compromised"
echo "  3. Update CI/CD pipelines with the new cert"
