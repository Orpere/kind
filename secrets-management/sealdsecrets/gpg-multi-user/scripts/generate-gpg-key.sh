#!/usr/bin/env bash
# generate-gpg-key.sh — Generate a GPG key for a team member to use with Sealed Secrets
# Usage: ./generate-gpg-key.sh <name> <email> [expiry]
set -euo pipefail

USER_NAME="${1:?Usage: $0 <name> <email> [expiry]}"
USER_EMAIL="${2:?Usage: $0 <name> <email> [expiry]}"
EXPIRY="${3:-1y}"

if ! command -v gpg &>/dev/null && ! command -v gpg2 &>/dev/null; then
  echo "Error: gpg/gpg2 not found. Install GnuPG: https://gnupg.org/" >&2
  exit 1
fi

GPG_CMD=$(command -v gpg2 || command -v gpg)

echo "Generating GPG key for ${USER_NAME} <${USER_EMAIL}> (expires: ${EXPIRY})"

cat <<EOF | "${GPG_CMD}" --batch --gen-key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${USER_NAME}
Name-Email: ${USER_EMAIL}
Expire-Date: ${EXPIRY}
%no-protection  # No passphrase — suitable for CI/CD bots. For human keys, remove this line and set a passphrase.
%commit
EOF

echo ""
echo "=== Generated Key ==="
"${GPG_CMD}" --list-keys --keyid-format long "${USER_EMAIL}"

echo ""
echo "=== Export Public Key ==="
"${GPG_CMD}" --armor --export "${USER_EMAIL}" > "${USER_EMAIL}.pub.asc"
echo "Public key exported to: ${USER_EMAIL}.pub.asc"
echo ""
echo "Next steps:"
echo "  1. Share ${USER_EMAIL}.pub.asc with the cluster administrator"
echo "  2. The admin adds it to the sealed-secrets-gpg-keys Secret"
echo "  3. Use: kubeseal --format gpg --recovery-public-key <cert> -f secret.yaml -w sealed.yaml"
