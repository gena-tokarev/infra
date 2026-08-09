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

## Importing an old development database

Bootstrap creates a fresh database. If old data matters, take a PostgreSQL
custom-format dump from the old deployment before stopping it. After bootstrap,
copy that dump to the current primary and restore it manually only after checking
that its schema and ownership match `cortex`/`cortex_auth`.

CloudNativePG chooses pod names, so discover the primary instead of hard-coding
one:

```bash
kubectl -n cortex get pods -l cnpg.io/cluster=cortex-postgres
```

For this development environment, a logical `pg_dump`/`pg_restore` transfer is
the clearest migration method. Keep the dump outside Git and delete server-side
copies after validating the import.

## Backups and production limits

CloudNativePG manages PostgreSQL correctly, but an operator is not itself a
backup. This setup does not yet configure object-storage backups or point-in-time
recovery. Before treating Cortex as production, configure the supported Barman
Cloud plugin with off-server object storage, test restores, and define retention.
On a one-node VPS, off-server backups matter more than adding a second database
pod on the same machine.
