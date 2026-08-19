# Cortex database

## What is installed

Argo CD installs the official CloudNativePG operator and a PostgreSQL 16 cluster
named `cortex-postgres`. The application connects to the operator-managed
read/write service:

```text
cortex-postgres-rw.cortex.svc:5432
```

The cluster has one PostgreSQL instance and one 10 Gi `local-path` PVC. This is
appropriate for the current single-node development VPS, but it is not high
availability: another replica on the same VPS would not protect against a host
failure.

The PostgreSQL image and the CloudNativePG Helm chart are pinned. Argo CD is
prevented from pruning the `Cluster` resource accidentally. Never delete the
cluster or its PVC to perform an application rollback.

## Credentials

The role and database are non-secret configuration:

```text
role:     cortex
database: cortex_auth
```

Ansible creates `cortex-database-credentials` as a
`kubernetes.io/basic-auth` Secret before Argo creates the database. Its password
comes from `vault_cortex_postgres_password`. The matching application URL in
Vault must use the operator-managed service:

```text
postgresql://cortex:URL_ENCODED_PASSWORD@cortex-postgres-rw:5432/cortex_auth?schema=public
```

## Inspecting the database

CloudNativePG chooses Pod names, so discover resources instead of hard-coding
an instance name:

```bash
kubectl -n cortex get cluster.postgresql.cnpg.io cortex-postgres
kubectl -n cortex get pods,pvc,services \
  -l cnpg.io/cluster=cortex-postgres
```

The application uses `cortex-postgres-rw`; do not connect to a Pod IP directly.

## Logical development backup

This cluster does not yet have automated backups. For a manual logical backup,
first identify the primary and stream a custom-format dump to the trusted local
machine:

```bash
primary=$(kubectl -n cortex get pods \
  -l cnpg.io/cluster=cortex-postgres,cnpg.io/instanceRole=primary \
  -o jsonpath='{.items[0].metadata.name}')

kubectl -n cortex exec "$primary" -- \
  pg_dump --format=custom --username=postgres --dbname=cortex_auth \
  > "cortex-$(date +%Y%m%d-%H%M%S).dump"
```

Verify the file is non-empty and store it off the VPS. A backup is not trusted
until a restore has been tested. Restore into an isolated database or
replacement cluster first; do not overwrite the active database merely to test
a dump.

## Credential rotation

The database password exists in both
`vault_cortex_postgres_password` and the URL-encoded password portion of
`vault_cortex_database_url`. Update both with `make vault-edit`, commit the
encrypted Vault and run `make bootstrap`. Ansible reapplies the labelled
credentials Secret and CloudNativePG reconciles the database role.

## Backups and production limits

CloudNativePG manages PostgreSQL lifecycle, but an operator is not a backup.
This setup does not configure object-storage backups or point-in-time recovery.
Before treating Cortex as production, configure CloudNativePG's supported
object-storage backup integration, define retention, monitor backup failures and
test full restoration regularly. On a one-node VPS, an off-host backup matters
more than adding another database Pod on the same machine.
