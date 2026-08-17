# k3s GitOps infrastructure

This private repository provisions the complete single-node development cluster
at `167.233.59.107`. It treats the host as a generic server: Ansible has no
knowledge of existing Docker projects, directories, volumes, databases, proxy
configuration, certificates, or rollback procedures.

Application CI publishes public GHCR images without repository credentials.
Argo CD Image Updater resolves each `main` tag to an immutable digest and writes
the release files in this repository. Argo CD reconciles those releases but is
not public; access it through an SSH tunnel at `http://localhost:8080`.

## Setup

1. Install the pinned local tools:

   ```bash
   make ansible-setup
   ```

2. Set the same real `letsencrypt_email` in:

   - `ansible/inventories/development/group_vars/all/main.yml`
   - `platform/config/certificates.yaml`

3. Create and fill the encrypted development Vault:

   ```bash
   make vault-create
   make vault-edit
   ```

   Commit only the encrypted `vault.yml`; keep its password in a password
   manager. Follow [Secrets](docs/secrets.md) for the Argo repository key.

4. Ensure the bootstrap release files contain real digests and Cortex and
   Podolog have published their `main` image tags.

5. Follow the manual host preparation in [Migration](docs/migration.md). Existing
   services must release ports 80 and 443 before provisioning.

6. Validate and provision everything:

   ```bash
   make ansible-check
   make bootstrap
   make argocd-tunnel
   make lens-tunnel
   ```

`make bootstrap` installs pinned k3s with packaged Traefik enabled immediately,
installs CloudNativePG with a single PostgreSQL instance and an ephemeral Redis,
installs private Argo CD and Image Updater, applies
Vault-backed Kubernetes Secrets, synchronizes Cortex and Podolog, waits for
certificates, and checks the public HTTPS endpoints. It is idempotent and does
not call Docker.

## Public endpoints

| Host | Workload |
| --- | --- |
| `podolog-warsaw.pl` | Podolog web |
| `www.podolog-warsaw.pl` | Redirect to the apex host |
| `cortex-dev.podolog-warsaw.pl/api/*` | Cortex API |
| `cortex-dev.podolog-warsaw.pl/*` | Cortex web |

Additional guides: [database operations](docs/database.md),
[GitHub setup](docs/github-setup.md), and [rollback](docs/rollback.md).

## Private cluster access

`make argocd-tunnel` exposes only the private Argo CD UI on local port `8080`.
`make lens-tunnel` exposes the private k3s API on local port `6443` for Lens or
local `kubectl`. Both commands stay in the foreground and close their tunnel
when stopped with `Ctrl+C`; neither exposes a public VPS port.
