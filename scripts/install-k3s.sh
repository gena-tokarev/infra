#!/bin/sh
set -eu

K3S_VERSION=v1.36.1+k3s1
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this script as root.' >&2
  exit 1
fi
if [ "$(uname -m)" != x86_64 ]; then
  echo 'This bootstrap is pinned for x86_64.' >&2
  exit 1
fi
if command -v k3s >/dev/null 2>&1; then
  echo 'k3s is already installed; refusing to replace it.' >&2
  exit 1
fi

install -d -m 700 /etc/rancher/k3s
install -m 600 "$repo_root/bootstrap/k3s/config.initial.yaml" /etc/rancher/k3s/config.yaml

installer=$(mktemp)
trap 'rm -f "$installer"' EXIT INT TERM
curl --fail --silent --show-error --location https://get.k3s.io --output "$installer"
INSTALL_K3S_VERSION="$K3S_VERSION" sh "$installer"

k3s kubectl wait --for=condition=Ready node --all --timeout=120s
k3s --version
