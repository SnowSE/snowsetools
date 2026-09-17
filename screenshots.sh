#!/usr/bin/env bash
# Look at the pages instead of guessing at them.
#
# Dumps each page's real rendered HTML (logged in, with seeded data), wraps it
# in a document that loads the freshly built stylesheet, and screenshots it in
# headless Chrome at whatever width you ask for. Output lands in tmp/screens.
#
#   ./screenshots.sh                 # 390x900, a phone
#   W=820 H=1000 ./screenshots.sh    # a tablet
#   W=1440 H=900 SUFFIX=-wide ./screenshots.sh
#
# Needs: the dev image (snowse-dev:local), a postgres for the test database, and
# the ability to pull zenika/alpine-chrome. See AGENTS.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

W="${W:-390}"
H="${H:-900}"
SUFFIX="${SUFFIX:-}"
PAGES=(home syllabi discord admin programs scheduling)

DB_CONTAINER="snowse-shots-db"
NETWORK="snowse-shots-net"
DB_USER="syllabus_test_user"
DB_PASS="syllabus_test_pass"
DB_NAME="snow_se_tools_test"

cleanup() {
    docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$NETWORK" >/dev/null 2>&1 || true
docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$DB_CONTAINER" --network "$NETWORK" \
    -e "POSTGRES_USER=${DB_USER}" -e "POSTGRES_PASSWORD=${DB_PASS}" -e "POSTGRES_DB=${DB_NAME}" \
    --tmpfs /var/lib/postgresql:rw,noexec,nosuid,size=512m \
    postgres:18-alpine >/dev/null

for _ in $(seq 1 30); do
    docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 && break
    sleep 1
done

in_dev() {
    docker run --rm --network "$NETWORK" -v "$PWD":/app -w /app \
        -e "MIX_ENV=${1}" \
        -e "DATABASE_URL=ecto://${DB_USER}:${DB_PASS}@${DB_CONTAINER}/${DB_NAME}" \
        snowse-dev:local sh -c "git config --global --add safe.directory '*'; ${2}"
}

echo "building assets…"
in_dev dev "mix assets.build" >/dev/null

echo "rendering pages…"
in_dev test "mix test --only snapshot test/snow_se_tools_web/page_snapshot_dump_test.exs" >/dev/null

cp priv/static/assets/css/app.css tmp/screens/app.css

python3 - <<'PY'
from pathlib import Path

out = Path("tmp/screens")
shell = (
    '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"/>'
    '<meta name="viewport" content="width=device-width, initial-scale=1"/>'
    '<link rel="stylesheet" href="app.css"/></head><body>\nPAGE\n</body></html>'
)

for html in sorted(out.glob("*.html")):
    if html.name.startswith("page-"):
        continue
    (out / f"page-{html.name}").write_text(shell.replace("PAGE", html.read_text()))
PY

echo "shooting ${W}x${H}…"
for page in "${PAGES[@]}"; do
    docker run --rm -v "$PWD/tmp/screens":/data --entrypoint chromium-browser \
        zenika/alpine-chrome:latest \
        --no-sandbox --headless --disable-gpu --hide-scrollbars \
        --window-size="${W},${H}" \
        --screenshot="/data/shot-${page}${SUFFIX}.png" \
        "file:///data/page-${page}.html" >/dev/null 2>&1
done

ls -la tmp/screens/shot-*"${SUFFIX}".png | awk '{print $5, $9}'
