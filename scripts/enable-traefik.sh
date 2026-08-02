#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this script as root.' >&2
  exit 1
fi
if ss -ltn '( sport = :80 or sport = :443 )' | tail -n +2 | grep -q .; then
  echo 'Ports 80 or 443 are still occupied. Stop the legacy Nginx stack first.' >&2
  ss -ltnp '( sport = :80 or sport = :443 )' >&2 || true
  exit 1
fi

install -m 600 "$repo_root/bootstrap/k3s/config.final.yaml" /etc/rancher/k3s/config.yaml
systemctl restart k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl -n kube-system rollout status deployment/traefik --timeout=300s
kubectl -n gateway-system wait gateway/public --for=condition=Programmed --timeout=180s
kubectl -n kube-system get service traefik
kubectl -n gateway-system get gateway,certificate
