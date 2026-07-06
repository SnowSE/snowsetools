#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="snow_se_tools_precommit_db"

# DB config matching config/test.exs defaults
DB_USER="syllabus_test_user"
DB_PASS="syllabus_test_pass"
DB_NAME="snow_se_tools_test"
HOST_PORT=15433

cleanup() {
    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Kill any existing container with the same name
podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

# Start ephemeral postgres container (tmpfs = no persistence)
podman run \
    -d \
    --name "$CONTAINER_NAME" \
    -p "127.0.0.1:${HOST_PORT}:5432" \
    -e "POSTGRES_USER=${DB_USER}" \
    -e "POSTGRES_PASSWORD=${DB_PASS}" \
    -e "POSTGRES_DB=${DB_NAME}" \
    --tmpfs /var/lib/postgresql:rw,noexec,nosuid,size=512m \
    postgres:18-alpine

# Wait for postgres to be ready
for i in $(seq 1 30); do
    if podman exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! podman exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    echo "ERROR: test database failed to start" >&2
    exit 1
fi

# Point the app at our temporary DB
export DATABASE_URL="ecto://${DB_USER}:${DB_PASS}@localhost:${HOST_PORT}/${DB_NAME}"

cd "$SCRIPT_DIR"
exec mix precommit
