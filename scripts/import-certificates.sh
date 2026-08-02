#!/bin/sh
set -eu

certificate_dir=${1:-}
if [ -z "$certificate_dir" ]; then
  echo "Usage: $0 /absolute/path/to/exported-certificates" >&2
  exit 1
fi
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

kubectl create namespace gateway-system --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gateway-system create secret tls podolog-tls \
  --cert="$certificate_dir/podolog/fullchain.pem" \
  --key="$certificate_dir/podolog/privkey.pem" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gateway-system get secret podolog-tls
