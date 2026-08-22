# Bootstrap the development cluster

This runbook creates the current infrastructure on a clean Debian/Ubuntu VPS.
It does not know about or operate any previous Docker, proxy, application,
database or certificate installation.

Ansible runs from a trusted local machine and connects as
`deploy@167.233.59.107`. It installs a single-node k3s cluster, private Argo CD,
Argo CD Image Updater, CloudNativePG, Cortex and Podolog.

## 1. Understand the result

Bootstrap installs:

- pinned k3s with packaged Traefik on public ports 80 and 443;
- Flannel networking, CoreDNS, ServiceLB and local-path storage from k3s;
- Kubernetes secret encryption at rest;
- Gateway API CRDs and a shared public Gateway;
- cert-manager and Let's Encrypt certificates;
- private, `ClusterIP`-only Argo CD;
- Argo CD Image Updater;
- CloudNativePG and one PostgreSQL 16 instance;
- ephemeral Redis;
- Cortex API and web workloads;
- Podolog web.

The VPS does not clone application repositories, build application images or
receive GitHub Actions credentials. Application CI publishes public GHCR
images. Argo CD reads this private repository and reconciles the cluster.

## 2. Prepare GitHub and DNS

Complete [GitHub and registry configuration](github.md), including:

- the read-only Argo CD deploy key;
- the Image Updater GitHub App;
- public Cortex and Podolog GHCR packages with `main` tags;
- real image digests in the development release files.

The following DNS records must resolve to `167.233.59.107`:

```text
podolog-warsaw.pl
www.podolog-warsaw.pl
cortex-dev.podolog-warsaw.pl
```

Verify them locally:

```bash
dig +short podolog-warsaw.pl A
dig +short www.podolog-warsaw.pl A
dig +short cortex-dev.podolog-warsaw.pl A
```

## 3. Prepare the local machine

Required local tools are Python 3.12 or newer, Git, Make and OpenSSH.

```bash
cd /Users/genatokarev/Projects/infra
python3 --version
make --version
ssh -V
make ansible-setup
```

`make ansible-setup` creates the ignored `ansible/.venv` and installs the
pinned Ansible, Helm and validation tooling. It does not change the VPS.

## 4. Prepare a clean VPS

The inventory expects:

```text
Host: 167.233.59.107
Port: 22
User: deploy
Architecture: x86_64
Minimum: 2 CPUs, 3.5 GiB RAM and 10 GiB free root-disk space
```

Create `deploy`, authorize the intended SSH public key and grant sudo access
before running Ansible. The development inventory currently uses
`/usr/bin/sudo.ws`, the classic sudo implementation available on the target
Ubuntu release. Verify it explicitly:

```bash
ssh -o IdentitiesOnly=yes deploy@167.233.59.107
sudo -v
command -v sudo.ws
exit
```

Both commands must succeed. If `deploy` or classic sudo is absent, provision
them once through the hosting provider's root console before continuing.

Ports 80 and 443 must be free on a new target:

```bash
ssh deploy@167.233.59.107 \
  "sudo.ws ss -ltnp '( sport = :80 or sport = :443 )'"
```

The expected output has no listeners. Bootstrap deliberately refuses to take
ports from an unrelated process.

## 5. Configure public inventory values

Review:

```text
ansible/inventories/development/hosts.yml
ansible/inventories/development/group_vars/all/main.yml
platform/config/certificates.yaml
```

The Let's Encrypt email must be identical in inventory and certificate
configuration. Confirm the hostnames, Git repository and pinned component
versions before provisioning another environment.

## 6. Create the encrypted Vault

Follow [Secrets with Ansible Vault](secrets.md). For a new environment:

```bash
make argocd-password-hash
make vault-create
make vault-edit
```

Replace every placeholder from `ansible/vault.example.yml`. Keep the Vault
password in a password manager and commit only the encrypted `vault.yml`.

## 7. Verify release artifacts

These public image channels must exist:

```bash
docker buildx imagetools inspect ghcr.io/gt-engineering/cortex-auth-api:main
docker buildx imagetools inspect ghcr.io/gt-engineering/cortex-web:main
docker buildx imagetools inspect ghcr.io/gena-tokarev/podolog-web:main
```

The bootstrap release files must contain three real immutable references:

```text
environments/development/cortex/release.yaml
environments/development/podolog/release.yaml
```

`make ansible-check` rejects placeholder digests.

## 8. Validate and provision

```bash
make ansible-check
make bootstrap
```

`make bootstrap` prompts for:

1. the VPS sudo password for `deploy`;
2. the development Vault password.

The first run downloads images and charts, installs controllers, issues
certificates, runs the Prisma migration and waits for health. It can take
several minutes. The playbook is idempotent: after correcting a reported
problem, run it again. Its Argo recovery step restarts only Applications whose
previous sync operation failed and whose desired state remains OutOfSync.

## 9. Verify the result

With the local cluster tunnel running, verify:

```bash
make lens-tunnel
```

In another terminal:

```bash
export KUBECONFIG="$HOME/.kube/cortex-development.yaml"
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl -n argocd get applications
kubectl -n argocd get imageupdater application-images
kubectl -n cortex get clusters.postgresql.cnpg.io,pods,services,pvc
kubectl -n gateway-system get gateway,certificates
```

Public verification:

```bash
curl --fail --head https://podolog-warsaw.pl
curl --fail https://cortex-dev.podolog-warsaw.pl/api/health
```

## 10. Private administration access

Open Argo CD through its SSH tunnel:

```bash
make argocd-tunnel
```

Then open `http://localhost:8080` and sign in as `admin` with the Vault-managed
Argo CD password.

For Lens or local `kubectl`, copy the generated kubeconfig once:

```bash
mkdir -p "$HOME/.kube"
scp deploy@167.233.59.107:/home/deploy/.kube/config \
  "$HOME/.kube/cortex-development.yaml"
chmod 600 "$HOME/.kube/cortex-development.yaml"
```

Run `make lens-tunnel` whenever local access to the private Kubernetes API is
needed. Both tunnels remain in the foreground and close with `Ctrl+C`.

## Recreating the server

Git, the encrypted Vault and GHCR reconstruct configuration and application
artifacts. They do not reconstruct PostgreSQL data. A replacement server also
requires a tested off-host database backup; see [Cortex database](database.md).

For replacement:

1. update the development inventory and tunnel host values if the IP changes;
2. update DNS;
3. prepare the `deploy` account and free ports;
4. run validation and bootstrap;
5. restore PostgreSQL deliberately;
6. verify private and public access.
