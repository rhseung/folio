#!/bin/bash
# 넘겨받은 파일 중 sources와 tests 밖의 것(Package.swift)은 건드리지 않는다. 그래야 커밋 전 검사와 CI의 결과가 같다.
#
# 생성한 두 소스는 검사가 생성기의 출력과 바이트 단위로 비교하므로, 포매팅하면 검사가 실패한다. 그래서 둘은 그대로 둔다:
# sources/cli/generated(`folio-gen --check`), sources/cli/render/note-theme.swift(tests/unit/app의 NoteThemeCopyTests).
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:?usage: scripts/swift-format.sh format|lint [<file>...]}
shift
folders='^(sources|tests)/'
generated='^sources/cli/(generated/|render/note-theme\.swift$)'

if [ $# -eq 0 ]; then
    files=$(find sources tests -name '*.swift' -not -path '*/.build/*' -not -path '*/node_modules/*' | sort)
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
