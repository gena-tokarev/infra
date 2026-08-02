#!/bin/sh
set -eu

ARGO_CHART_VERSION=9.5.12
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
age_key=${1:-}
repo_key=${2:-}

if [ -z "$age_key" ] || [ -z "$repo_key" ]; then
  echo "Usage: $0 /absolute/path/to/age.key /absolute/path/to/infra-repository-key" >&2
  exit 1
fi
for command_name in helm kubectl; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "$command_name is required." >&2
    exit 1
  }
done
test -f "$age_key"
test -f "$repo_key"
grep -q '^AGE-SECRET-KEY-' "$age_key"
grep -Eq 'image: ghcr.io/gena-tokarev/argocd-sops-plugin@sha256:[0-9a-f]{64}$' \
  "$repo_root/bootstrap/argocd/values.yaml" || {
    echo 'The SOPS plugin has not been published and pinned yet.' >&2
    exit 1
  }

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd create secret generic argocd-sops-age \
  --from-file=key.txt="$age_key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd create secret generic infra-repository \
  --from-literal=type=git \
  --from-literal=url=git@github.com:gena-tokarev/infra.git \
  --from-file=sshPrivateKey="$repo_key" \
  --dry-run=client -o yaml | \
  kubectl label --local -f - \
    argocd.argoproj.io/secret-type=repository \
    -o yaml | kubectl apply -f -

helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version "$ARGO_CHART_VERSION" \
  --namespace argocd \
  --values "$repo_root/bootstrap/argocd/values.yaml" \
  --wait --timeout 10m

kubectl apply -f "$repo_root/bootstrap/platform-root.yaml"
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=180s
kubectl -n argocd get applications
