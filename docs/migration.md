# Install and migrate the development VPS

This is the complete installation checklist for the current single-node VPS.
Follow it in order.

Ansible treats the VPS as a generic Debian/Ubuntu server. It does not inspect,
back up, stop, start, delete, or otherwise manage the old Docker Compose
projects. You perform the few legacy-stack actions explicitly below.

Commands marked **local** run on your Mac from the `infra` repository. Commands
marked **VPS** run after connecting to `deploy@167.233.59.107`.

## 1. Understand what will be installed

One `make bootstrap` run installs and configures:

- pinned k3s with its packaged Traefik enabled on ports 80 and 443;
- Kubernetes secret encryption at rest;
- Gateway API CRDs and the shared public Gateway;
- cert-manager and Let's Encrypt certificates;
- private, `ClusterIP`-only Argo CD;
- the CloudNativePG operator and one PostgreSQL 16 instance;
- ephemeral Redis;
- Cortex API and web workloads;
- Podolog web workload.

The VPS does not clone application repositories, build images, or receive
GitHub Actions credentials. Cortex and Podolog images are built by GitHub
Actions and pulled from public GHCR packages. Argo CD pulls the private `infra`
repository with its own read-only deploy key.

## 2. Check the local prerequisites

**Local:**

```bash
cd /Users/genatokarev/Projects/infra

python3 --version
make --version
ssh -V
git status
```

Python must be 3.12 or newer. You also need Git, Make, OpenSSH, and normal SSH
access to the VPS. Install those first if a command is missing.

Verify the existing VPS login and sudo access:

```bash
ssh -o IdentitiesOnly=yes deploy@167.233.59.107
sudo -v
exit
```

The SSH command must use the key already authorized for `deploy`. `sudo -v`
must accept `deploy`'s sudo password.

## 3. Install the pinned local automation tools

**Local:**

```bash
make ansible-setup
```

This creates the ignored `ansible/.venv` and installs the pinned Ansible,
Ansible Lint, Helm, and kubeconform versions. It does not modify the VPS.

## 4. Configure the public, non-secret values

Set your real email address in both files:

```text
ansible/inventories/development/group_vars/all/main.yml
platform/config/certificates.yaml
```

Replace `REPLACE_WITH_LETSENCRYPT_EMAIL` with the same address in both places.
Do not change the configured hostnames unless DNS and all application callback
URLs will change too.

Confirm these public DNS records point to the VPS:

```text
podolog-warsaw.pl             A  167.233.59.107
www.podolog-warsaw.pl         A  167.233.59.107
cortex-dev.podolog-warsaw.pl  A  167.233.59.107
```

**Local verification:**

```bash
dig +short podolog-warsaw.pl A
dig +short www.podolog-warsaw.pl A
dig +short cortex-dev.podolog-warsaw.pl A
```

All three commands must resolve to `167.233.59.107`. Remove the obsolete
`argocd.podolog-warsaw.pl` record; Argo CD will not be public.

## 5. Configure the Image Updater GitHub App

Reuse the GitHub App created earlier for release promotion. Do not create a
second App. In **Settings → Developer settings → GitHub Apps**, open it and set:

- **Repository permissions → Contents:** Read and write;
- **Repository permissions → Pull requests:** Read and write;
- every other permission: No access;
- webhook: disabled.

Under **Install App**, confirm that it is installed on the `gena-tokarev`
account with **Only select repositories → infra**. Approve the updated
permissions if GitHub requests it.

Record these three values in your password manager:

```text
GitHub App ID            numeric App ID on the App's General page
Installation ID          number at the end of the installation Configure URL
GitHub App private key   complete downloaded .pem contents
```

The installation URL resembles:

```text
https://github.com/settings/installations/67890
```

In that example the installation ID is `67890`. Use the numeric **App ID**, not
the Client ID beginning with `Iv`, for Image Updater. If the original `.pem` is
no longer available locally, generate a new private key under the App's
**Private keys** section. Do not copy it to the VPS.

Keep the existing `INFRA_APP_CLIENT_ID` and `INFRA_APP_PRIVATE_KEY` values in
the Cortex and Podolog GitHub environments temporarily. The new workflows do
not use them, but remove them only after step 14 verifies Image Updater.

If an infra ruleset blocks direct writes to `main`, keep this App as a bypass
actor so Cortex development updates can be committed. Podolog production still
uses a pull request because its Image Updater policy explicitly requests one.

## 6. Publish the infrastructure and `main` image channels

Commit and push this infra implementation first:

```bash
cd /Users/genatokarev/Projects/infra
git status
git add -A
git diff --cached
git commit -m "feat: add Argo CD Image Updater"
git push origin main
```

Then commit and push the updated workflows in Cortex and Podolog. A successful
`main` workflow now validates the application and publishes affected images
with both an immutable `sha-<commit>` tag and a movable `main` tag. It never
checks out or writes to `infra`.

After the first publication, make these three GitHub packages public:

```text
ghcr.io/gena-tokarev/cortex-auth-api
ghcr.io/gena-tokarev/cortex-web
ghcr.io/gena-tokarev/podolog-web
```

For each package, open your GitHub profile → **Packages** → package → **Package
settings** → **Danger Zone → Change visibility → Public**. The source
repositories may remain public or private independently; Kubernetes only needs
anonymous read access to these packages.

Confirm that the existing bootstrap release files contain real digests:

```bash
if grep -R -nE 'sha256:0{64}' environments/development; then
  echo "Application release digests are still missing"
  exit 1
fi
```

Confirm all three `main` tags exist:

```bash
docker buildx imagetools inspect ghcr.io/gena-tokarev/cortex-auth-api:main
docker buildx imagetools inspect ghcr.io/gena-tokarev/cortex-web:main
docker buildx imagetools inspect ghcr.io/gena-tokarev/podolog-web:main
```

Do not continue while an application workflow or any of these inspections is
failing.

## 7. Create the read-only Argo CD deploy key

This is a new, dedicated key for Argo CD to read the private `infra` repository.
It is not the VPS login key and not the GitHub App key.

**Local:**

```bash
ssh-keygen \
  -t ed25519 \
  -N '' \
  -C argocd-infra-readonly \
  -f "$HOME/.ssh/argocd_infra_readonly"

cat "$HOME/.ssh/argocd_infra_readonly.pub"
```

In `gena-tokarev/infra`, open **Settings → Deploy keys → Add deploy key**. Paste
the public-key line, name it `argocd-infra-readonly`, and leave **Allow write
access** unchecked.

The complete contents of `$HOME/.ssh/argocd_infra_readonly` will be stored as
`vault_argocd_repository_private_key` in the next step. This key remains
read-only; Image Updater uses the separate GitHub App credential.

## 8. Create and fill the encrypted Ansible Vault

There are two different passwords:

- the **development Vault password** encrypts `vault.yml`; keep it in your
  password manager and enter it when Make/Ansible prompts;
- the **Argo CD admin password** is used to sign in to the private Argo UI.

Generate the Argo password hash first:

```bash
make argocd-password-hash
```

Enter the intended Argo admin password twice and save both the password and the
printed bcrypt hash in your password manager.

Generate strong hex values for PostgreSQL and the three authentication secrets.
Hex avoids URL-encoding problems in `DATABASE_URL`:

```bash
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 32
```

Save each output temporarily in your password manager and assign them, in
order, to:

```text
vault_cortex_postgres_password
vault_auth_access_token_secret
vault_auth_refresh_token_secret
vault_auth_external_state_secret
```

Create and edit the encrypted Vault:

```bash
make vault-create
make vault-edit
```

When `make vault-create` asks for a password, create the development Vault
password. In the editor, replace every `REPLACE_WITH...` value. The finished
plaintext shown only inside the Vault editor has this structure:

```yaml
vault_argocd_admin_password: YOUR_ARGO_ADMIN_PASSWORD
vault_argocd_admin_password_hash: YOUR_BCRYPT_HASH
vault_argocd_repository_private_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  COMPLETE_PRIVATE_KEY_CONTENT
  -----END OPENSSH PRIVATE KEY-----
vault_image_updater_github_app_id: "YOUR_NUMERIC_APP_ID"
vault_image_updater_github_app_installation_id: "YOUR_NUMERIC_INSTALLATION_ID"
vault_image_updater_github_app_private_key: |
  -----BEGIN RSA PRIVATE KEY-----
  COMPLETE_GITHUB_APP_PRIVATE_KEY
  -----END RSA PRIVATE KEY-----

vault_cortex_postgres_password: YOUR_HEX_POSTGRES_PASSWORD
vault_cortex_database_url: postgresql://cortex:YOUR_HEX_POSTGRES_PASSWORD@cortex-postgres-rw:5432/cortex_auth?schema=public

vault_auth_access_token_secret: YOUR_FIRST_AUTH_HEX_VALUE
vault_auth_refresh_token_secret: YOUR_SECOND_AUTH_HEX_VALUE
vault_auth_external_state_secret: YOUR_THIRD_AUTH_HEX_VALUE
vault_google_client_id: YOUR_GOOGLE_OAUTH_CLIENT_ID
vault_google_client_secret: YOUR_GOOGLE_OAUTH_CLIENT_SECRET
```

Use the same PostgreSQL password in both relevant lines. Existing Google OAuth
credentials must allow this callback URL:

```text
https://cortex-dev.podolog-warsaw.pl/api/external-auth/google/callback
```

Verify that the file is ciphertext, not YAML plaintext:

```bash
head -n 1 ansible/inventories/development/group_vars/all/vault.yml
```

It must begin with `$ANSIBLE_VAULT;`. Commit and push only that encrypted file:

```bash
git add ansible/inventories/development/group_vars/all/vault.yml
git diff --cached
git commit -m "chore: add encrypted development vault"
git push origin main
```

Back up the Vault password in your password manager. After confirming that the
encrypted Vault is committed and recoverable, remove the temporary read-only
Argo key files. Keep the GitHub App `.pem` in your password manager until Image
Updater is verified:

```bash
rm "$HOME/.ssh/argocd_infra_readonly" "$HOME/.ssh/argocd_infra_readonly.pub"
```

## 9. Validate everything before touching the VPS

**Local:**

```bash
make ansible-check
```

This must finish successfully. It checks Ansible, Helm charts, remote chart
rendering, Kubernetes schemas, scripts, image digests, and Vault encryption. A
warning that the Vault is uninitialized is acceptable only before step 8; it is
not acceptable now.

## 10. Optionally preserve the old Cortex database

Skip this section if the old development data is disposable. CloudNativePG will
create a new, empty database and a new Kubernetes PVC.

If the data matters, create a logical dump before stopping Docker. The exact
Compose directory and service name are legacy details, so verify them first.

**VPS:**

```bash
cd /home/deploy/apps/focoris
docker compose ps
docker compose exec -T postgres sh -ec \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > /home/deploy/cortex-before-k3s.dump
test -s /home/deploy/cortex-before-k3s.dump
ls -lh /home/deploy/cortex-before-k3s.dump
```

If the PostgreSQL Compose service is not named `postgres`, substitute its actual
service name. Copy the dump off the VPS as well:

```bash
scp deploy@167.233.59.107:/home/deploy/cortex-before-k3s.dump \
  ./cortex-before-k3s.dump
```

Bootstrap does not import this dump automatically. Complete the fresh install
first, then follow [Cortex database](database.md) for a deliberate import. Do not
restore over a database that has accepted new writes.

## 11. Stop the old services and free ports 80/443

Run these commands manually on the VPS. They are not part of Ansible.

**VPS:**

```bash
cd /home/deploy/apps/focoris
docker compose stop

cd /home/deploy/apps/podolog
docker compose stop

cd /home/deploy/apps/infra
docker compose stop
```

If a directory or Compose project has a different name, use its actual location.
Do not run `docker compose down -v`; that would delete Docker volumes.

Confirm that ports 80 and 443 are free:

```bash
sudo ss -ltnp '( sport = :80 or sport = :443 )'
```

The command must show no listeners. If containers restarted because of their
restart policies, stop them again before continuing.

## 12. Install the complete cluster

Return to the local terminal.

**Local:**

```bash
cd /Users/genatokarev/Projects/infra
make bootstrap
```

Enter, in order:

1. the development Vault password;
2. `deploy`'s VPS sudo password.

Do not interrupt a healthy run. The first run downloads k3s and container images,
installs controllers, obtains certificates, runs the Prisma migration, and waits
for application health, so it can take several minutes.

The playbook is idempotent. If it fails after fixing a configuration or network
problem, run `make bootstrap` again.

## 13. Verify the cluster

**Local:**

```bash
ssh deploy@167.233.59.107 'kubectl get nodes -o wide'
ssh deploy@167.233.59.107 'kubectl get pods -A'
ssh deploy@167.233.59.107 \
  'kubectl -n argocd get imageupdater application-images'
ssh deploy@167.233.59.107 \
  'kubectl -n argocd rollout status deployment/argocd-image-updater'
ssh deploy@167.233.59.107 \
  'kubectl -n cortex get clusters.postgresql.cnpg.io,pods,services,pvc'
ssh deploy@167.233.59.107 \
  'kubectl -n gateway-system get gateway,certificate'

curl -I https://podolog-warsaw.pl
curl -I https://www.podolog-warsaw.pl
curl https://cortex-dev.podolog-warsaw.pl/api/health
```

Expected results:

- the k3s node is `Ready`;
- all application/controller pods are running or completed successfully;
- `application-images` reports `Ready=True`;
- `cortex-postgres` reports ready and its PVC is `Bound`;
- the Podolog and Cortex certificates report ready;
- Podolog responds over HTTPS;
- the `www` hostname redirects to the apex hostname;
- Cortex health returns a successful minimal response.

## 14. Open the private Argo CD UI

**Local, terminal 1:**

```bash
cd /Users/genatokarev/Projects/infra
make argocd-tunnel
```

Keep that command running. Open this URL in a browser:

```text
http://localhost:8080
```

Sign in with:

```text
username: admin
password: the Argo CD admin password stored in your password manager
```

Argo CD is intentionally unreachable from the public internet. Closing the SSH
tunnel removes local browser access but does not affect deployments.

Verify in Argo that the platform and workload Applications are `Synced` and
`Healthy`, including `argocd-image-updater` and `image-updater-config`.

Image Updater checks every five minutes. After the application workflows have
published their `main` tags, verify its behavior:

```bash
ssh deploy@167.233.59.107 \
  'kubectl -n argocd logs deployment/argocd-image-updater --tail=200'

cd /Users/genatokarev/Projects/infra
git pull --rebase origin main
git log --oneline -10
```

Expected behavior:

- Cortex gets a verified GitHub App commit updating only changed digests in
  `environments/development/cortex/release.yaml`;
- Podolog gets an Image Updater pull request changing
  `environments/development/podolog/release.yaml`;
- Podolog does not deploy until you review and merge that PR.

After both behaviors are confirmed, remove `INFRA_APP_CLIENT_ID` and
`INFRA_APP_PRIVATE_KEY` from the Cortex `development` and Podolog `production`
GitHub environments. Delete either environment only if it is otherwise empty.
Keep the GitHub App installed on `infra`; Image Updater now uses it.

For a future Cortex production environment:

1. seed `environments/production/cortex/release.yaml` with the exact digests
   currently deployed in development;
2. create a distinct `cortex-production` Argo Application using the production
   values and release files;
3. add an Image Updater `applicationRef` matching `cortex-production` that
   tracks the same `cortex-auth-api:main` and `cortex-web:main` images;
4. set its write-back target to the production release file and configure
   `pullRequest.github: {}`;
5. require infra validation and a human merge before Argo can see the change.

Production therefore receives the exact GHCR artifacts already exercised in
development; only the write-back approval policy differs.

## 15. Roll back an Image Updater release

For a bad Cortex development image, first commit `ignoreTags: ["*"]` for the
affected image in `platform/image-updater/image-updater.yaml`. Wait until the
configuration is Synced, then revert the relevant release commit. Without this
pause, Image Updater will immediately select the bad `main` digest again.

For Podolog production, close an unmerged Image Updater PR. If it was already
merged, disable that image rule, revert the release commit, and wait for Argo to
reconcile. Re-enable the rule only after `main` points at an acceptable image.
Database migrations are not reversed and must remain backward-compatible.

## 16. Manual fallback to the old Docker deployment

If bootstrap fails and you want the old deployment back, run on the VPS:

```bash
sudo systemctl stop k3s

cd /home/deploy/apps/infra
docker compose start

cd /home/deploy/apps/podolog
docker compose start

cd /home/deploy/apps/focoris
docker compose start
```

Confirm that the old public endpoints work again. This does not delete k3s,
Kubernetes PVCs, or Docker volumes.

To retry later:

1. stop the old Compose projects again;
2. confirm ports 80 and 443 are free;
3. run `make bootstrap` locally.

Do not let both Traefik and the old Nginx stack compete for ports 80/443. A VPS
or Docker restart may restart legacy containers according to their Docker
restart policies, so check the port owners whenever switching between stacks.
