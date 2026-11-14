#!/usr/bin/env bash
# 이 체크아웃이나 다른 세션의 워크트리에 있는, 커밋하지 않았거나 머지하지 않은 작업이 설치되지 않도록 임시 워크트리에서 빌드한다.
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
