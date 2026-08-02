# VPS GitOps infrastructure

This private repository is the desired state for the single-node k3s cluster on
`167.233.59.107`. Argo CD pulls it with a read-only deploy key; application CI
never connects to the VPS or Kubernetes.

## Public endpoints

| Host | Workload |
| --- | --- |
| `podolog-warsaw.pl` | Podolog Next.js site |
| `www.podolog-warsaw.pl` | Redirect to the apex host |
| `cortex-dev.podolog-warsaw.pl/api/*` | Cortex auth API |
| `cortex-dev.podolog-warsaw.pl/*` | Cortex web app |
| `argocd.podolog-warsaw.pl` | Argo CD with GitHub login |

## Release flow

1. An application workflow validates and publishes a public GHCR image.
2. The workflow's narrowly scoped GitHub App commits the immutable digest here.
3. Argo CD detects the commit, runs any migration hook, and reconciles k3s.
4. Rollback is a Git revert of the relevant release file.

The SOPS age identity and Argo repository private key exist only in Kubernetes
and offline recovery storage. Git contains only encrypted application secrets.

## One-time setup

Follow these documents in order:

1. [GitHub and DNS setup](docs/github-setup.md)
2. [SOPS and age setup](docs/secrets.md)
3. [VPS bootstrap and cutover](docs/cutover.md)
4. [Rollback](docs/rollback.md)

Before bootstrapping, publish the SOPS plugin workflow, make its GHCR package
public, replace `REPLACE_WITH_LETSENCRYPT_EMAIL`, and confirm
`bootstrap/argocd/values.yaml` contains a plugin image pinned by `@sha256:`.

## Validation

CI runs the same entrypoint locally:

```bash
./scripts/validate.sh
```

It lints and renders Helm charts, renders Kustomize roots, schema-checks the
manifests, parses shell scripts, and rejects tracked age identities or malformed
SOPS files.
