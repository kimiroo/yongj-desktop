#!/bin/bash

set -euo pipefail

REPO_URL="https://github.com/kimiroo/yongj-desktop.git" 
SCRIPT_NAME="configure.sh"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git이 설치돼 있지 않음"

tmp_dir="$(mktemp -d /tmp/dotfiles-XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

log "Cloning $REPO_URL into $tmp_dir..."
git clone --depth 1 "$REPO_URL" "$tmp_dir"

[[ -x "$tmp_dir/$SCRIPT_NAME" ]] || chmod +x "$tmp_dir/$SCRIPT_NAME"

log "Running $SCRIPT_NAME $*"
"$tmp_dir/$SCRIPT_NAME" "$@"
