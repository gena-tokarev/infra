#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

for chart in charts/cortex-data charts/cortex charts/podolog; do
  helm lint "$chart"
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

helm template cortex-data charts/cortex-data --namespace cortex > "$tmp_dir/cortex-data.yaml"
helm template cnpg cloudnative-pg \
  --repo https://cloudnative-pg.github.io/charts \
  --version 0.29.0 \
  --namespace cnpg-system > "$tmp_dir/cloudnative-pg.yaml"
helm template cortex charts/cortex --namespace cortex \
  -f environments/development/cortex/values.yaml \
  -f environments/development/cortex/release.yaml > "$tmp_dir/cortex.yaml"
helm template podolog charts/podolog --namespace podolog \
  -f environments/development/podolog/values.yaml \
  -f environments/development/podolog/release.yaml > "$tmp_dir/podolog.yaml"
kubectl kustomize platform/config > "$tmp_dir/platform.yaml"
kubectl kustomize clusters/development/platform > "$tmp_dir/platform-apps.yaml"
kubectl kustomize clusters/development/workloads > "$tmp_dir/workload-apps.yaml"

grep -q 'targetRevision: 0.29.0' clusters/development/platform/cloudnative-pg.yaml
grep -Eq 'tag: 1\.30\.0@sha256:[0-9a-f]{64}$' clusters/development/platform/cloudnative-pg.yaml
grep -Eq 'image: ghcr.io/cloudnative-pg/postgresql:16\.10-system-trixie@sha256:[0-9a-f]{64}$' \
  charts/cortex-data/values.yaml
grep -q 'cortex-postgres-rw:5432' ansible/vault.example.yml

for manifest in "$tmp_dir"/*.yaml; do
  if command -v kubeconform >/dev/null 2>&1; then
    kubeconform -strict -summary -ignore-missing-schemas "$manifest"
  else
    docker run --rm -i \
      ghcr.io/yannh/kubeconform:v0.7.0-alpine@sha256:8f0eeaaa96ba27ba1500b0e4b1c215acc358d159c62a7ecae58d7a03403287b0 \
      -strict -summary -ignore-missing-schemas < "$manifest"
  fi
done

find scripts -type f -name '*.sh' -exec bash -n {} \;
if command -v shellcheck >/dev/null 2>&1; then
  find scripts -type f -name '*.sh' -exec shellcheck {} +
fi

vault_file=ansible/inventories/development/group_vars/all/vault.yml
if test -f "$vault_file"; then
  head -n 1 "$vault_file" | grep -Eq '^\$ANSIBLE_VAULT;1\.[12];AES256(;development)?$' || {
    echo "$vault_file is not an encrypted Ansible Vault file." >&2
    exit 1
  }
else
  echo "Vault has not been initialized yet; run make vault-create before bootstrap." >&2
fi

if git grep -nE 'BEGIN (OPENSSH|RSA) PRIVATE KEY|AUTH_(ACCESS|REFRESH)_TOKEN_SECRET=' -- ':!ansible/vault.example.yml' ':!scripts/validate.sh'; then
  echo 'A plaintext secret appears to be tracked.' >&2
  exit 1
fi
