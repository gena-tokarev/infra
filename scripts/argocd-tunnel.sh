#!/usr/bin/env bash
set -euo pipefail

host=${ARGOCD_SSH_HOST:-167.233.59.107}
port=${ARGOCD_SSH_PORT:-22}
user=${ARGOCD_SSH_USER:-deploy}
local_port=${ARGOCD_LOCAL_PORT:-8080}

# Resolve the current ClusterIP on every invocation. SSH can reach this address
# directly, so no long-running kubectl port-forward process is needed on the VPS.
service_ip=$(
  ssh \
    -p "$port" \
    "$user@$host" \
    env K3S_CONFIG_FILE=/dev/null \
    kubectl --kubeconfig /home/deploy/.kube/config \
      -n argocd get service argocd-server \
      -o 'jsonpath={.spec.clusterIP}'
)

if [[ ! $service_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unable to resolve the Argo CD Service ClusterIP." >&2
  exit 1
fi

echo "Argo CD will be available at http://localhost:${local_port} while this command is running."
exec ssh \
  -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3 \
  -L "127.0.0.1:${local_port}:${service_ip}:80" \
  -p "$port" \
  "$user@$host"
