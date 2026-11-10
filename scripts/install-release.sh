#!/usr/bin/env bash
# Installs committed code only: origin/main, or a ref given (a throwaway merge of PR branches, say). Uncommitted or
# unmerged work in this checkout, or in another session's worktree, never ships.
set -euo pipefail
cd "$(dirname "$0")/.."
git fetch -q origin
ref="${1:-origin/main}"
sha=$(git rev-parse --verify "$ref^{commit}")
tmp=$(mktemp -d)
dir="$tmp/folio"
git worktree add -q --detach "$dir" "$sha"
trap 'git worktree remove --force "$dir"; rmdir "$tmp"' EXIT
cd "$dir"
mise trust -q
mise run install-mac
mise run install-cli
echo "installed $(scripts/version.sh get) ($(scripts/version.sh build)) from $(git rev-parse --short HEAD)"
