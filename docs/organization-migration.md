# Move Infra and Cortex to `gt-engineering`

Podolog remains in the personal `gena-tokarev` account. Its repository,
webhook and `ghcr.io/gena-tokarev/podolog-web` package do not change.

The repository transfer preserves repository webhooks and deploy keys, and
GitHub redirects the former repository URLs. The redirects provide migration
time; the committed configuration uses the new canonical URLs.

## What is already changed in source

- All Argo CD sources and AppProject allowlists use
  `git@github.com:gt-engineering/infra.git`.
- Image Updater writes to `https://github.com/gt-engineering/infra.git`.
- Cortex CI publishes to `ghcr.io/gt-engineering/cortex-auth-api` and
  `ghcr.io/gt-engineering/cortex-web`.
- Image Updater tracks those two organization-owned packages.
- Podolog continues to use the personal repository and GHCR namespace.

The development Cortex release file intentionally continues referencing the
last known-good personal images until the new organization packages exist.
Image Updater replaces each reference independently after it sees a public
`main` tag in the new package namespace.

## 0. Verify the local repository remotes

The local remotes have already been changed. Verify them before committing:

```bash
git -C /Users/genatokarev/Projects/infra remote -v
git -C /Users/genatokarev/Projects/cortex remote -v
git -C /Users/genatokarev/Projects/podolog remote -v
```

Expected push/fetch URLs:

```text
infra:   git@github.com:gt-engineering/infra.git
cortex:  git@github.com:gt-engineering/cortex.git
podolog: git@github.com:gena-tokarev/podolog.git
```

## 1. Verify transferred repository settings

In **gt-engineering/infra → Settings → Deploy keys**, verify that
`argocd-infra-readonly` still exists and that write access is disabled.

In **gt-engineering/infra → Settings → Webhooks**, verify the Argo CD
webhook still exists, is active, and retains its secret. Do not create a second
copy if GitHub transferred the existing webhook.

In **gt-engineering/cortex → Settings → Webhooks**, verify the GHCR Image
Updater webhook still exists and is subscribed to **Packages**. A GitHub `ping`
delivery may receive `400 unsupported event type: ping`; test the next real
`package` delivery instead.

## 2. Give the release GitHub App access to the organization

The Image Updater writer GitHub App must be installed on `gt-engineering`.
An installation on the personal account cannot write to the organization's
private `infra` repository.

The cleanest option for this dedicated App is to transfer the App registration
to `gt-engineering`:

1. Open personal **Settings → Developer settings → GitHub Apps**.
2. Open the release/Image Updater App.
3. Open **Advanced → Transfer ownership** and select `gt-engineering`.
4. In the App permissions, retain:
   - **Contents: Read and write**;
   - **Pull requests: Read and write**;
   - everything else at **No access**.
5. Open **Install App**, install it on `gt-engineering`, choose **Only select
   repositories**, and select only `infra`.

The numeric App ID and existing private key normally remain tied to the same
App registration. The organization installation has a new installation ID.
Open the installed App's **Configure** page and copy the number from its URL:

```text
https://github.com/organizations/gt-engineering/settings/installations/12345678
                                                                        ^^^^^^^^
                                                                        installation ID
```

Edit the encrypted Vault:

```bash
cd /Users/genatokarev/Projects/infra
make vault-edit
```

Replace only:

```yaml
vault_image_updater_github_app_installation_id: "12345678"
```

If you created a new App instead of transferring the existing one, also replace
`vault_image_updater_github_app_id` and
`vault_image_updater_github_app_private_key` with values belonging to that new
App.

Commit only the encrypted Vault file. Never commit its plaintext contents.

## 3. Publish the organization-owned Cortex images

Commit and push the prepared Cortex changes:

```bash
cd /Users/genatokarev/Projects/cortex

git diff --check
git add -- \
  .github/workflows/ci.yml \
  README.md \
  apps/auth-api/Dockerfile \
  apps/web/Dockerfile
git commit -m "ci: publish Cortex images under gt-engineering"
git push origin main
```

A successful `main` workflow creates:

```text
ghcr.io/gt-engineering/cortex-auth-api:main
ghcr.io/gt-engineering/cortex-web:main
```

Only an affected service may be published. If one package is not created,
make a harmless source change in that service or run its workflow with a commit
that affects it.

After first publication, open each package under the `gt-engineering`
organization and change **Package settings → Change visibility** to
**Public**. Public visibility is required because the cluster intentionally has
no GHCR pull credential.

If **Public** says `Setting is disabled by organization administrators`, first
enable public package creation as an organization owner:

1. Open GitHub **Your organizations → gt-engineering → Settings**.
2. In the organization settings sidebar, open **Packages**.
3. Under **Package Creation**, enable **Public**. Keep **Private** enabled too.
4. Save the organization setting if GitHub displays a save button.
5. Return to each Cortex package's **Package settings → Danger Zone →
   Change visibility**.
6. Select **Public**, enter the package name exactly, and confirm.

Do this for both `cortex-auth-api` and `cortex-web`. Making a GHCR package
public allows anonymous pulls and cannot later be reversed to private. The
repository itself remains private; package visibility is an independent
setting.

At the time this guide was written, anonymous inspection of both organization
package names returned `403 Forbidden`. This means they are not currently
publicly pullable: they may be private after the transfer, or the first workflow
run may still need to create them. In **Organization → Packages**, handle
either case:

- if the packages already exist, grant `gt-engineering/cortex` Actions access
  with write permission and make them public;
- if they do not exist, push the Cortex change first, let its workflow create
  them, and then make them public.

If organization package policy prevents changing visibility or creating a
package, enable public container packages in the `gt-engineering` organization
settings before rerunning the workflow.

Verify both images locally:

```bash
docker buildx imagetools inspect ghcr.io/gt-engineering/cortex-auth-api:main
docker buildx imagetools inspect ghcr.io/gt-engineering/cortex-web:main
```

Both commands must show a `linux/amd64` manifest.

## 4. Apply the Infra changes

Only continue after both organization images are publicly inspectable. Commit
and push the Infra source changes, including the encrypted Vault update:

```bash
cd /Users/genatokarev/Projects/infra

git diff --check
make ansible-check
git add -- \
  README.md \
  ansible \
  bootstrap \
  charts \
  clusters \
  docs \
  platform \
  scripts/argocd-tunnel.sh
git commit -m "chore: migrate infrastructure to gt-engineering"
git push origin main
```

Immediately reconcile the Vault-managed Kubernetes credentials and the new
canonical repository URL:

```bash
make bootstrap
```

`make bootstrap` does not rebuild the cluster. It is idempotent and updates the
Argo repository credential and Image Updater GitHub App Secret in place.

## 5. Verify the migration

Check Argo CD and Image Updater:

```bash
cd /Users/genatokarev/Projects/infra
make lens-tunnel
```

Keep that command running. In another terminal:

```bash
export KUBECONFIG="$HOME/.kube/cortex-development.yaml"

kubectl -n argocd get applications
kubectl -n argocd get imageupdater application-images
kubectl -n argocd logs deployment/argocd-image-updater-controller --since=15m
```

Expected results:

- Argo Applications are `Synced` and `Healthy`.
- Image Updater is `Ready`.
- Its logs show Cortex images under `ghcr.io/gt-engineering`.
- Image Updater commits changed Cortex digests directly to
  `gt-engineering/infra`.
- Podolog still creates pull requests against `gt-engineering/infra` while its
  image remains `ghcr.io/gena-tokarev/podolog-web`.

Finally, confirm the Cortex release file was updated to organization images:

```bash
grep 'image:' environments/development/cortex/release.yaml
```

Do not manually replace the old image references before the new public packages
exist. The running deployment can safely keep using the old immutable digests
during this migration.
