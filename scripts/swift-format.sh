#!/bin/bash
# Formats (`format`) or checks (`lint`) the Swift sources with the toolchain's swift-format (.swift-format): every file
# in app, app-tests and the packages, or the files given (lefthook passes the staged ones).
#
# folio-cli/generated is left as folio-gen writes it: `folio-gen --check` compares that file byte for byte with the
# generator's output, so formatting it would fail the check, and nobody edits it by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:?usage: scripts/swift-format.sh format|lint [<file>...]}
shift
generated='^packages/folio-core/sources/folio-cli/generated/'

if [ $# -eq 0 ]; then
    files=$(find app app-tests packages/*/sources packages/*/tests -name '*.swift' -not -path '*/.build/*' | sort)
else
    files=$(printf '%s\n' "$@")
fi
files=$(grep -vE "$generated" <<< "$files" || true)
[ -n "$files" ] || exit 0

case $mode in
format) tr '\n' '\0' <<< "$files" | xargs -0 swift format format --in-place --parallel ;;
lint) tr '\n' '\0' <<< "$files" | xargs -0 swift format lint --strict --parallel ;;
*) echo "unknown mode $mode: format or lint" >&2; exit 2 ;;
esac
