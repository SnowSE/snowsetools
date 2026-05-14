#!/usr/bin/env nix-shell
#!nix-shell -i bash -p kubeseal kubectl openssl

set -euo pipefail

SECRETS_FILE="$(dirname "$0")/secrets.env"
SEALED_SECRET_OUT="$(dirname "$0")/base/sealed-secret.yaml"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "Error: $SECRETS_FILE not found. Copy secrets.env.example to secrets.env and fill in values." >&2
  exit 1
fi

source "$SECRETS_FILE"

if [ -f "$SEALED_SECRET_OUT" ] && grep -q 'encryptedData' "$SEALED_SECRET_OUT" 2>/dev/null; then
  echo "Warning: $SEALED_SECRET_OUT already contains sealed secrets."
  printf "Overwrite and rotate all secrets? [y/N] "
  read -r reply
  if [ "${reply}" != "y" ] && [ "${reply}" != "Y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

SECRET_KEY_BASE="$(openssl rand -hex 64)"
POSTGRES_PASSWORD="$(openssl rand -hex 32)"
DATABASE_URL="ecto://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}/${POSTGRES_DB}"

kubectl create secret generic app-secrets \
  --from-literal=SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=OIDC_ISSUER="${OIDC_ISSUER}" \
  --from-literal=OIDC_CLIENT_ID="${OIDC_CLIENT_ID}" \
  --from-literal=AI_ENDPOINT="${AI_ENDPOINT}" \
  --from-literal=AI_API_KEY="${AI_API_KEY}" \
  --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
  --from-literal=POSTGRES_DB="${POSTGRES_DB}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --namespace=simple-syllabus \
  --dry-run=client -o yaml \
  | kubeseal \
      --controller-name=sealed-secrets-controller \
      --controller-namespace=kube-system \
      --format yaml > "$SEALED_SECRET_OUT"

echo "Written to $SEALED_SECRET_OUT"
