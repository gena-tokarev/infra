# GitHub and registry configuration

This document describes the current credential and release architecture. The
application repositories publish images; they do not connect to the VPS,
Kubernetes, Argo CD or this repository.

## Application repositories

Cortex and Podolog GitHub Actions use their automatic `GITHUB_TOKEN` to publish
images to GHCR. They publish:

- immutable `sha-<40-character-commit>` tags;
- a movable `main` tag after a successful `main` build.

The following packages are public so k3s and Image Updater can pull them
without registry credentials:

```text
ghcr.io/gt-engineering/cortex-auth-api
ghcr.io/gt-engineering/cortex-web
ghcr.io/gena-tokarev/podolog-web
```

Application GitHub environments require no VPS, SSH, Kubernetes, Argo CD,
Ansible Vault or infra-repository writer credential.

## Argo CD repository reader

Argo CD reads the private `gt-engineering/infra` repository using a dedicated SSH
deploy key:

- register only the public key under **infra → Settings → Deploy keys**;
- leave **Allow write access** unchecked;
- store the complete private key as
  `vault_argocd_repository_private_key` in Ansible Vault.

Generate it locally if a new environment needs one:

```bash
key_dir=$(mktemp -d)
ssh-keygen -t ed25519 -N '' -C argocd-infra-readonly \
  -f "$key_dir/argocd-infra"
cat "$key_dir/argocd-infra.pub"
```

Back up the private key securely until it is stored in the encrypted Vault.
Do not reuse the VPS login key.

## Image Updater repository writer

Argo CD Image Updater uses a separate GitHub App installed only on `infra`.
Its repository permissions are:

```text
Contents:      Read and write
Pull requests: Read and write
Everything else: No access
```

The webhook is disabled because Image Updater initiates GitHub API requests;
the App does not receive GitHub events.

Store these values in Ansible Vault:

```text
vault_image_updater_github_app_id
vault_image_updater_github_app_installation_id
vault_image_updater_github_app_private_key
```

The App ID is the numeric value on the App's General page. The installation ID
is the number in its installation configuration URL:

```text
https://github.com/settings/installations/INSTALLATION_ID
```

Ansible creates the `argocd-image-updater-git` Secret in the `argocd`
namespace. Argo CD does not receive this writer credential.

If a repository ruleset blocks direct writes to `main`, allow this App to
bypass that rule for Cortex development updates. Podolog updates use a pull
request and still require review and merge.

## Release flow

```text
Application source push
        ↓
GitHub Actions validates and publishes a GHCR image
        ↓
Image Updater resolves main to an immutable digest
        ↓
Cortex: direct infra commit
Podolog: infra pull request
        ↓
Argo CD reads the merged infra state
        ↓
Kubernetes rolls out the selected digest
```

The current writer policy is defined in:

```text
platform/image-updater/image-updater.yaml
```

The committed release state is stored in:

```text
environments/development/cortex/release.yaml
environments/development/podolog/release.yaml
```

## Credential boundaries

| Credential | Stored in | Can do |
| --- | --- | --- |
| Application `GITHUB_TOKEN` | Ephemeral GitHub Actions context | Publish that repository's GHCR images |
| Argo deploy key | Ansible Vault and Argo repository Secret | Read `infra` |
| Image Updater GitHub App key | Ansible Vault and Image Updater Secret | Commit/open PRs only in `infra` |
| VPS SSH key | Trusted operator machine and VPS `authorized_keys` | Log in as `deploy` |
| Kubernetes kubeconfig | VPS and protected local copy | Administer the cluster |

Do not copy one credential into another trust boundary merely because both use
GitHub or SSH.
