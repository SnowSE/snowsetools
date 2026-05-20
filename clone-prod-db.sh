#!/usr/bin/env bash
# Clone production database from Kubernetes into local Docker Compose
# Usage: ./clone-prod-db.sh
kubectl exec -n simple-syllabus postgres-0 -c postgres -- sh -c 'pg_dump -U "$POSTGRES_USER" --no-owner --no-acl --clean --if-exists "$POSTGRES_DB"' \
  | docker exec -i simplesyllabusreporter-db-1 psql -U syllabus_user -d simple_syllabus_reporter_dev
