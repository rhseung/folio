#!/usr/bin/env bash
# Takes the note-view pictures a CI run left in its note-screens artifact (missing or changed ones) as the new
# references. The references must come from CI's runner, whose macOS the comparison checks (tests/unit/app/support/note-pixels.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
run="${1:?usage: mise run note-screens -- <CI run ID>}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh run download "$run" --name note-screens --dir "$tmp"
refs=tests/unit/app/references/notes
mkdir -p "$refs"
n=0
for f in "$tmp"/*.png; do
  case "$f" in *-diff.png) continue ;; esac
  cp "$f" "$refs/"
  n=$((n + 1))
done
cp "$tmp/machine.txt" "$refs/machine.txt"
echo "$n pictures from run $run in $refs ($(cat "$refs/machine.txt"))"
