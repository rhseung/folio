#!/bin/bash
# Formats (`format`) or checks (`lint`) the Swift sources with the toolchain's swift-format (.swift-format): every file
# in app, app-tests, app-ui-tests and the packages' sources and tests, or those of the files given (lefthook passes the
# staged ones). A file given outside these folders (a Package.swift) is left alone, so a commit and CI agree.
#
# Two generated sources are left as they are written, since a check compares each byte for byte with what its writer
# makes now and formatting would fail it: folio-cli/generated (`folio-gen --check`) and folio-cli/render/note-theme.swift
# (NoteThemeCopyTests in app-tests). Nobody edits either by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:?usage: scripts/swift-format.sh format|lint [<file>...]}
shift
folders='^(app|app-tests|app-ui-tests|packages/[^/]+/(sources|tests))/'
generated='^packages/folio-core/sources/folio-cli/(generated/|render/note-theme\.swift$)'

if [ $# -eq 0 ]; then
    files=$(find app app-tests app-ui-tests packages/*/sources packages/*/tests -name '*.swift' -not -path '*/.build/*' | sort)
else
    files=$(printf '%s\n' "$@")
fi
files=$(grep -E "$folders" <<< "$files" | grep -vE "$generated" || true)
[ -n "$files" ] || exit 0

case $mode in
format) tr '\n' '\0' <<< "$files" | xargs -0 swift format format --in-place --parallel ;;
lint) tr '\n' '\0' <<< "$files" | xargs -0 swift format lint --strict --parallel ;;
*) echo "unknown mode $mode: format or lint" >&2; exit 2 ;;
esac
