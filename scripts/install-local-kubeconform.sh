#!/usr/bin/env bash
set -euo pipefail

version=v0.7.0
os=$(uname -s)
arch=$(uname -m)

case "$os/$arch" in
  Darwin/x86_64)
    platform=darwin-amd64
    checksum=c6771cc894d82e1b12f35ee797dcda1f7da6a3787aa30902a15c264056dd40d4
    ;;
  Linux/x86_64)
    platform=linux-amd64
    checksum=c31518ddd122663b3f3aa874cfe8178cb0988de944f29c74a0b9260920d115d3
    ;;
  *)
    echo "Unsupported local platform for pinned kubeconform: $os/$arch" >&2
    exit 1
    ;;
esac

repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
tools_dir="$repo_root/ansible/.tools"
binary="$tools_dir/kubeconform"

if test -x "$binary" && "$binary" -v | grep -q "$version"; then
  exit 0
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
archive="$tmp_dir/kubeconform.tar.gz"
curl --fail --silent --show-error --location \
  "https://github.com/yannh/kubeconform/releases/download/$version/kubeconform-$platform.tar.gz" \
  --output "$archive"
if test "$os" = Darwin; then
  printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check
else
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
fi
tar -xzf "$archive" -C "$tmp_dir" kubeconform
mkdir -p "$tools_dir"
install -m 0755 "$tmp_dir/kubeconform" "$binary"
