#!/bin/sh
set -eu

dump_file=${1:-}
if [ -z "$dump_file" ] || [ ! -f "$dump_file" ]; then
  echo "Usage: $0 /absolute/path/to/cortex.dump" >&2
  exit 1
fi
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

kubectl -n cortex rollout status statefulset/cortex-postgres --timeout=180s
postgres_user=$(kubectl -n cortex get secret cortex-runtime -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
postgres_db=$(kubectl -n cortex get secret cortex-runtime -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)

table_count=$(kubectl -n cortex exec cortex-postgres-0 -- \
  psql -U "$postgres_user" -d "$postgres_db" -Atc \
  "select count(*) from pg_catalog.pg_tables where schemaname = 'public'")
if [ "$table_count" != 0 ]; then
  echo "Target database is not empty ($table_count public tables); refusing to restore." >&2
  exit 1
fi

kubectl -n cortex exec -i cortex-postgres-0 -- \
  pg_restore --exit-on-error --no-owner --no-privileges \
  -U "$postgres_user" -d "$postgres_db" < "$dump_file"

kubectl -n cortex exec cortex-postgres-0 -- \
  psql -U "$postgres_user" -d "$postgres_db" -c '\\dt'
