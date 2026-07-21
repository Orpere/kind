#!/usr/bin/env bash
# validate-sealed.sh — Validate all SealedSecrets in a directory
# Usage: ./validate-sealed.sh <cert-file> [directory]
# Exit code: 0 = all valid, 1 = errors found
set -euo pipefail

CERT_FILE="${1:?Usage: $0 <cert-file> [directory]}"
DIR="${2:-.}"

if [ ! -f "${CERT_FILE}" ]; then
  echo "Error: Certificate file not found: ${CERT_FILE}" >&2
  exit 1
fi

ERRORS=0
CHECKED=0

echo "Validating SealedSecrets in: ${DIR}"
echo "Using cert: ${CERT_FILE}"
echo "---"

while IFS= read -r -d '' f; do
  # Skip non-YAML files
  if ! grep -q "kind: SealedSecret" "${f}" 2>/dev/null; then
    continue
  fi

  CHECKED=$((CHECKED + 1))
  echo -n "  Checking: ${f} ... "

  if kubeseal --validate --recovery-public-key "${CERT_FILE}" -f "${f}" &>/dev/null; then
    echo "OK"
  else
    echo "FAILED"
    ERRORS=$((ERRORS + 1))
  fi
done < <(find "${DIR}" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)

echo "---"
echo "Checked: ${CHECKED} | Failed: ${ERRORS}"

if [ "${ERRORS}" -gt 0 ]; then
  echo "Validation failed." >&2
  exit 1
fi

echo "All SealedSecrets are valid."
