#!/usr/bin/env bash
set -euo pipefail

host=${LENS_SSH_HOST:-167.233.59.107}
port=${LENS_SSH_PORT:-22}
user=${LENS_SSH_USER:-deploy}
local_port=${LENS_LOCAL_PORT:-6443}

echo "The k3s API will be available to Lens at https://127.0.0.1:${local_port} while this command is running."
exec ssh \
  -N \
  -o ExitOnForwardFailure=yes \
  -L "127.0.0.1:${local_port}:127.0.0.1:6443" \
  -p "$port" \
  "$user@$host"
