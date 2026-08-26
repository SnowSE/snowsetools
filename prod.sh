#!/usr/bin/env bash
# Wrapper around the production compose stack.
#
# It exists so --env-file/-f are never forgotten: prod.env has to be passed with
# --env-file for the ${VAR} substitutions in docker-compose.prod.yml to resolve,
# separately from the env_file: entry that injects the same file into the app
# container.
#
# Usage:
#   ./prod.sh up -d --build     # build and start everything
#   ./prod.sh logs -f app
#   ./prod.sh ps
#   ./prod.sh down
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f prod.env ]; then
  echo "prod.env is missing. Run: cp prod.env.example prod.env  and fill it in." >&2
  exit 1
fi

if grep -q 'REPLACE_ME' prod.env; then
  echo "prod.env still contains REPLACE_ME placeholders:" >&2
  grep -n 'REPLACE_ME' prod.env >&2
  exit 1
fi

exec docker compose --env-file prod.env -f docker-compose.prod.yml "$@"
