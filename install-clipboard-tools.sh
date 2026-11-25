#!/bin/sh
set -eu

src_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.local/src" && pwd)
bin_dir=${1:-"$HOME/.local/bin"}
mkdir -p "$bin_dir"

lsc="$bin_dir/lsc"
if [ "$(readlink "$lsc" 2>/dev/null || true)" != pf ] && { [ -e "$lsc" ] || [ -L "$lsc" ]; }; then
    printf 'install-clipboard-tools: %s already exists\n' "$lsc" >&2
    exit 1
fi

build_dir=$(mktemp -d "$bin_dir/.clipboard-build.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT

/usr/bin/clang -fobjc-arc -framework AppKit -framework ApplicationServices \
    "$src_dir/cpf.m" -o "$build_dir/cpf-appkit"
/usr/bin/clang -fobjc-arc -framework AppKit -framework ApplicationServices -framework UniformTypeIdentifiers \
    "$src_dir/pf.m" -o "$build_dir/pf"

mv "$build_dir/cpf-appkit" "$build_dir/pf" "$bin_dir/"
if [ ! -L "$lsc" ]; then
    ln -s pf "$lsc"
fi
