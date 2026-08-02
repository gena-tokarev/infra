#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

for chart in charts/cortex-data charts/cortex charts/podolog; do
  helm lint "$chart"
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

helm template cortex-data charts/cortex-data --namespace cortex > "$tmp_dir/cortex-data.yaml"
helm template cortex charts/cortex \
  --namespace cortex \
  -f environments/development/cortex/values.yaml \
  -f environments/development/cortex/release.yaml > "$tmp_dir/cortex.yaml"
helm template podolog charts/podolog \
  --namespace podolog \
  -f environments/development/podolog/values.yaml \
  -f environments/development/podolog/release.yaml > "$tmp_dir/podolog.yaml"
kubectl kustomize platform/config > "$tmp_dir/platform.yaml"
kubectl kustomize clusters/development/platform > "$tmp_dir/platform-apps.yaml"
kubectl kustomize clusters/development/workloads > "$tmp_dir/workload-apps.yaml"

for manifest in "$tmp_dir"/*.yaml; do
  if command -v kubeconform >/dev/null 2>&1; then
    kubeconform -strict -summary -ignore-missing-schemas "$manifest"
  else
    docker run --rm -i \
      ghcr.io/yannh/kubeconform:v0.7.0-alpine@sha256:8f0eeaaa96ba27ba1500b0e4b1c215acc358d159c62a7ecae58d7a03403287b0 \
      -strict -summary -ignore-missing-schemas < "$manifest"
  fi
done

find scripts tools/argocd-sops-plugin -type f \
  \( -name '*.sh' -o -name 'generate-manifests' \) \
  -exec sh -n {} \;

if command -v shellcheck >/dev/null 2>&1; then
  find scripts tools/argocd-sops-plugin -type f \
    \( -name '*.sh' -o -name 'generate-manifests' \) \
    -exec shellcheck {} +
fi

git ls-files '*.sops.yaml' | while IFS= read -r encrypted_file; do
  grep -q '^sops:' "$encrypted_file"
  grep -q 'ENC\[' "$encrypted_file"
  if grep -Eq 'REPLACE_WITH|AGE-SECRET-KEY-' "$encrypted_file"; then
    echo "Unsafe placeholder or age identity in $encrypted_file" >&2
    exit 1
  fi
done

if git grep -n 'AGE-SECRET-KEY-' -- ':!*.md' ':!scripts/validate.sh'; then
  echo 'An age private identity is tracked by Git.' >&2
  exit 1
fi
