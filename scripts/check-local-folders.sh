#!/usr/bin/env bash
# The app reaches Application Support only through LocalFolders, which refuses this Mac's real folders to tests,
# previews and renders. A path asked of the system anywhere else would skip that refusal; app-tests is checked too,
# since a test is where a hand-made path would recover the user's unfinished recordings into a fixture. Packages
# can't import LocalFolders and have no business there, so for them any use fails.
set -euo pipefail
cd "$(dirname "$0")/.."
hits=$(rg -n --glob '*.swift' \
  -e 'applicationSupportDirectory' \
  -e 'NSSearchPathForDirectoriesInDomains' \
  -e 'Library/Application Support' \
  app app-tests packages \
  | rg -v '^(app/app/local-folders|app-tests/local-folders-tests)\.swift:' || true)
if [[ -n "$hits" ]]; then
  echo "Application Support reached outside LocalFolders (use LocalFolders.applicationSupport; packages don't use it):" >&2
  echo "$hits" >&2
  exit 1
fi
