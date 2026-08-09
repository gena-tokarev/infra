#!/usr/bin/env bash
set -euo pipefail

version=v4.2.3
os=$(uname -s)
arch=$(uname -m)

case "$os/$arch" in
  Darwin/x86_64)
    platform=darwin-amd64
    checksum=ff3ac86755a45f3422473bc1200776aac0fe04c5766abe6ca66699f7b564b23b
    ;;
  Linux/x86_64)
    platform=linux-amd64
    checksum=e9b88b4ee95b18c706839c28d3a0220e5bc470e9cd9262410c90793c45ff8b7c
    ;;
  *)
    echo "Unsupported local platform for pinned Helm: $os/$arch" >&2
    exit 1
    ;;
esac

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tools_dir="$repo_root/ansible/.tools"
helm_bin="$tools_dir/helm"

if test -x "$helm_bin" && "$helm_bin" version --short | grep -q "^$version"; then
  exit 0
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
archive="$tmp_dir/helm.tar.gz"
curl --fail --silent --show-error --location \
  "https://get.helm.sh/helm-$version-$platform.tar.gz" \
  --output "$archive"
if test "$os" = Darwin; then
  printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check
else
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
fi
tar -xzf "$archive" -C "$tmp_dir"
mkdir -p "$tools_dir"
install -m 0755 "$tmp_dir/$platform/helm" "$helm_bin"
