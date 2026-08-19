#!/usr/bin/env bash
set -euo pipefail

host=${ARGOCD_SSH_HOST:-167.233.59.107}
port=${ARGOCD_SSH_PORT:-22}
user=${ARGOCD_SSH_USER:-deploy}

echo "Argo CD will be available at http://localhost:8080 while this command is running."
exec ssh \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3 \
  -L 8080:127.0.0.1:8080 \
  -p "$port" \
  "$user@$host" \
  env K3S_CONFIG_FILE=/dev/null \
  kubectl --kubeconfig /home/deploy/.kube/config -n argocd port-forward \
    --address 127.0.0.1 service/argocd-server 8080:80
