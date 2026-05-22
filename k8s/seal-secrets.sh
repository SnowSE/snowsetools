#!/usr/bin/env nix-shell
#!nix-shell -i bash -p kubeseal kubectl openssl

set -euo pipefail

SECRETS_FILE="$(dirname "$0")/secrets.env"
APP_SEALED_SECRET_OUT="$(dirname "$0")/base/sealed-secret.yaml"
DB_SEALED_SECRET_OUT="$(dirname "$0")/base/sealed-secret-db.yaml"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "Error: $SECRETS_FILE not found. Copy secrets.env.example to secrets.env and fill in values." >&2
  exit 1
fi

source "$SECRETS_FILE"

UPDATE_DB=true
if [ -f "$DB_SEALED_SECRET_OUT" ] && grep -q 'encryptedData' "$DB_SEALED_SECRET_OUT" 2>/dev/null; then
  printf "DB sealed secret already exists. Rotate database password? [y/N] "
  read -r reply
  if [ "${reply}" != "y" ] && [ "${reply}" != "Y" ]; then
    UPDATE_DB=false
  fi
fi

SECRET_KEY_BASE="$(openssl rand -hex 64)"

kubectl create secret generic app-secrets \
  --from-literal=SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
  --from-literal=OIDC_ISSUER="${OIDC_ISSUER}" \
  --from-literal=OIDC_CLIENT_ID="${OIDC_CLIENT_ID}" \
  --from-literal=AI_ENDPOINT="${AI_ENDPOINT}" \
  --from-literal=AI_API_KEY="${AI_API_KEY}" \
  --namespace=simple-syllabus \
  --dry-run=client -o yaml \
  | kubeseal \
      --controller-name=sealed-secrets-controller \
      --controller-namespace=kube-system \
      --format yaml > "$APP_SEALED_SECRET_OUT"

echo "Written app secrets to $APP_SEALED_SECRET_OUT"

if [ "$UPDATE_DB" = "true" ]; then
  POSTGRES_PASSWORD="$(openssl rand -hex 32)"
  DATABASE_URL="ecto://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}/${POSTGRES_DB}"

  kubectl create secret generic db-secrets \
    --from-literal=DATABASE_URL="${DATABASE_URL}" \
    --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
    --from-literal=POSTGRES_DB="${POSTGRES_DB}" \
    --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    --namespace=simple-syllabus \
    --dry-run=client -o yaml \
    | kubeseal \
        --controller-name=sealed-secrets-controller \
        --controller-namespace=kube-system \
        --format yaml > "$DB_SEALED_SECRET_OUT"

  echo "Written db secrets to $DB_SEALED_SECRET_OUT"
  echo ""
  echo "After applying and restarting the postgres pod, run this to update the DB password:"
  cat <<'EOF'
  kubectl exec -n simple-syllabus postgres-0 -- sh -c 'escaped=$(printf "%s" "$POSTGRES_PASSWORD" | sed "s/'"'"'/'"'"''"'"'/g") && psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '"'"'$escaped'"'"'"'
EOF
else
  echo "Skipped db secret rotation."
fi
