#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this script as root.' >&2
  exit 1
fi
install -m 600 "$repo_root/bootstrap/k3s/config.initial.yaml" /etc/rancher/k3s/config.yaml
systemctl restart k3s
echo 'Traefik is disabled. Restart the legacy Nginx and application Compose stacks.'
