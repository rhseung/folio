#!/usr/bin/env bash
# The app reaches Application Support only through LocalFolders, which refuses this Mac's real folders to tests,
# previews and renders. A path asked of the system anywhere else would skip that refusal.
set -euo pipefail
cd "$(dirname "$0")/.."
hits=$(rg -n --glob '*.swift' \
  -e 'applicationSupportDirectory' \
  -e 'NSSearchPathForDirectoriesInDomains' \
  -e 'Library/Application Support' \
  app \
  | rg -v '^app/app/local-folders\.swift:' || true)
if [[ -n "$hits" ]]; then
  echo "Application Support reached outside LocalFolders (use LocalFolders.applicationSupport):" >&2
  echo "$hits" >&2
  exit 1
fi
