#!/usr/bin/env bash
# Clone production database from Kubernetes into local Docker Compose
# Usage: ./clone-prod-db.sh
set -euo pipefail

NAMESPACE="snow-se-tools"
PROD_POD="postgres-0"
PROD_CONTAINER="postgres"
LOCAL_CONTAINER="simplesyllabusreporter-db-1"
LOCAL_USER="syllabus_user"
LOCAL_DB="snow_se_tools_dev"
DUMP_FILE="$(mktemp /tmp/prod_dump.XXXXXX.sql)"

cleanup() {
  rm -f "$DUMP_FILE" "$DUMP_FILE.gz"
}

trap cleanup EXIT

echo ">> Resolving production database credentials..."
PROD_USER=$(kubectl exec -n "$NAMESPACE" "$PROD_POD" -c "$PROD_CONTAINER" -- printenv POSTGRES_USER 2>/dev/null || echo "postgres")
PROD_DB=$(kubectl exec -n "$NAMESPACE" "$PROD_POD" -c "$PROD_CONTAINER" -- printenv POSTGRES_DB 2>/dev/null || echo "app")

echo "    user=$PROD_USER db=$PROD_DB"

echo ">> Dumping production database to compressed temp file in prod container..."
kubectl exec -n "$NAMESPACE" "$PROD_POD" -c "$PROD_CONTAINER" -- \
  sh -c "pg_dump -U \"$PROD_USER\" --no-owner --no-acl --clean --if-exists \"$PROD_DB\" | gzip > /tmp/prod_dump.sql.gz"

echo ">> Copying dump from prod pod to host..."
REMOTE_SIZE=$(kubectl exec -n "$NAMESPACE" -c "$PROD_CONTAINER" "$PROD_POD" -- stat -c%s /tmp/prod_dump.sql.gz)
echo "    Remote compressed size: $REMOTE_SIZE bytes ($(numfmt --to=iec-i --suffix=B $REMOTE_SIZE))"

kubectl cp "$NAMESPACE/$PROD_POD:/tmp/prod_dump.sql.gz" "$DUMP_FILE.gz" -c "$PROD_CONTAINER"

kubectl exec -n "$NAMESPACE" "$PROD_POD" -c "$PROD_CONTAINER" -- rm /tmp/prod_dump.sql.gz 2>/dev/null || true

echo ">> Verifying transfer integrity..."
LOCAL_SIZE=$(stat -c%s "$DUMP_FILE.gz")
echo "    Local compressed size:  $LOCAL_SIZE bytes ($(numfmt --to=iec-i --suffix=B $LOCAL_SIZE))"

if [ "$REMOTE_SIZE" != "$LOCAL_SIZE" ]; then
  echo ">> ERROR: Dump file size mismatch! Transfer may have been truncated."
  rm -f "$DUMP_FILE.gz"
  exit 1
fi

echo "    ✓ Sizes match"

echo ">> Decompressing dump file..."
gunzip -f "$DUMP_FILE.gz"

echo ">> Recreating local database..."
docker exec -i "$LOCAL_CONTAINER" psql -U "$LOCAL_USER" -d postgres -v ON_ERROR_STOP=1 <<SQL
DROP DATABASE IF EXISTS "$LOCAL_DB" WITH (FORCE);
CREATE DATABASE "$LOCAL_DB" OWNER "$LOCAL_USER";
SQL

echo ">> Restoring into fresh local database..."
docker exec -i "$LOCAL_CONTAINER" psql -U "$LOCAL_USER" -d "$LOCAL_DB" < "$DUMP_FILE"

echo ">> Local database restored."

echo ">> Comparing row counts..."
echo ""

tables=$(kubectl exec -n "$NAMESPACE" "$PROD_POD" -c "$PROD_CONTAINER" -- \
  psql -U "$PROD_USER" "$PROD_DB" -t -A -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;")

printf "%-60s %10s %10s %s\n" "Table" "Prod" "Local" "Status"
printf "%-60s %10s %10s %s\n" "----------------------------------------" "----------" "----------" "----"

mismatches=0

for table in $tables; do
  prod_count=$(kubectl exec -n "$NAMESPACE" "$PROD_POD" -c "$PROD_CONTAINER" -- \
    psql -U "$PROD_USER" "$PROD_DB" -t -A -c "SELECT COUNT(*) FROM ${table};")

  local_count=$(docker exec -i "$LOCAL_CONTAINER" psql -U "$LOCAL_USER" -d "$LOCAL_DB" -t -A \
    -c "SELECT COUNT(*) FROM ${table};")

  if [ "$prod_count" = "$local_count" ]; then
    status="✓"
  else
    status="✗ mismatch"
    mismatches=$((mismatches + 1))
  fi

  printf "%-60s %10s %10s %s\n" "$table" "$prod_count" "$local_count" "$status"
done

echo ""

if [ "$mismatches" -gt 0 ]; then
  echo ">> WARN: Found $mismatches table(s) with mismatched row counts."
  exit 1
else
  echo ">> All tables match."
fi
