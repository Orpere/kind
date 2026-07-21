#!/usr/bin/env bash
# fetch-cert.sh — Fetch the Sealed Secrets public cert from a cluster
# Usage: ./fetch-cert.sh <cluster-context> [output-dir]
set -euo pipefail

CLUSTER="${1:?Usage: $0 <cluster-context> [output-dir]}"
OUTPUT_DIR="${2:-./certs}"

mkdir -p "${OUTPUT_DIR}"

echo "Fetching sealed-secrets cert from cluster: ${CLUSTER}"

if ! kubectl --context "${CLUSTER}" get secret sealed-secrets-gpg-keys \
  -n kube-system -o jsonpath='{.data.secrets\.io}' &>/dev/null; then
  echo "Error: sealed-secrets-gpg-keys secret not found in cluster ${CLUSTER}" >&2
  echo "Ensure the controller is deployed with GPG keys configured." >&2
  exit 1
fi

kubectl --context "${CLUSTER}" get secret sealed-secrets-gpg-keys \
  -n kube-system \
  -o jsonpath='{.data.secrets\.io}' | base64 -d \
  > "${OUTPUT_DIR}/${CLUSTER}-sealed-secrets.asc"

echo "Cert saved to: ${OUTPUT_DIR}/${CLUSTER}-sealed-secrets.asc"
echo ""
echo "Use with kubeseal:"
echo "  kubeseal --format gpg --recovery-public-key ${OUTPUT_DIR}/${CLUSTER}-sealed-secrets.asc -f secret.yaml -w sealed.yaml"
