#!/usr/bin/env bash
# The GitHub release's body, from the PRs merged to main between two commits.
#   release-notes.sh body <since> [<until>]   the body on stdout; an empty <since> means no earlier release
#   release-notes.sh preview [<since>]        the same, since the latest v* tag unless given
#
# 머지한 뒤에 고친 본문도 반영되도록 커밋 메시지가 아니라 PR 본문을 릴리스할 때 읽는다. 앱은 릴리스 본문을 FolioDomain의
# `PatchNotes`로 읽으므로, `format`, 종류, 줄 모양을 바꾸면 `PatchNotes`도 함께 고친다.
set -euo pipefail
cd "$(dirname "$0")/.."
format=1

# main은 스쿼시 머지만 받아 PR마다 커밋이 하나이므로, 머지 커밋이 since..until에 있는 PR만 센다.
prs() {
  local since=$1 until=$2
  local repo shas q
  repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
  if [ -n "$since" ]; then
    shas=$(git rev-list "$since..$until" | jq -R . | jq -sc .)
    # 검색은 결과를 줄이려고 <since>의 날짜로만 자르므로, 실제로 포함할 PR은 SHA로 정한다.
    q="repo:$repo is:pr is:merged base:main merged:>=$(git log -1 --format=%cs "$since")"
  else
    shas=$(git rev-list "$until" | jq -R . | jq -sc .)
    q="repo:$repo is:pr is:merged base:main"
  fi
  gh api graphql --paginate -f q="$q" -f query='
    query($q: String!, $endCursor: String) {
      search(query: $q, type: ISSUE, first: 50, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { ... on PullRequest { number title body mergeCommit { oid } } }
      }
    }' --jq '.data.search.nodes[]' |
    jq -sc --argjson shas "$shas" '[.[] | select(.mergeCommit.oid as $o | $shas | index($o))] | sort_by(.number)'
}

summary='def summary: (.body // "") | split("\n\n") | map(select(test("^\\s*(#|https://claude.ai/)") | not)) | (.[0] // "")
  | gsub("\\*\\*|`"; "") | gsub("\\s*\n\\s*"; " ") | ltrimstr(" ") | rtrimstr(" ");'

# 절은 같은 수준 이상의 다음 제목에서 끝나므로, `### feat` 아래로 묶은 본문도 끝까지 읽는다.
notes='def notes: (.body // "") | gsub("\r"; "") | split("\n") | map(sub("^\\s+"; "") | sub("\\s+$"; "")) as $lines
  | ($lines | map(test("^##\\s+패치 노트$")) | index(true)) as $start
  | if $start == null then [] else
      $lines[$start + 1:] | (map(test("^#{1,2}(\\s|$)")) | index(true)) as $end
      | (if $end == null then . else .[:$end] end)
      | map(select(test("^[-*]\\s+(feat|fix|change)\\s*:\\s*\\S")) | sub("^[-*]\\s+(?<k>feat|fix|change)\\s*:\\s*"; "- \(.k): "))
    end;
  def kinds: ["feat", "fix", "change"];
  def kind: capture("^- (?<k>[^:]+):").k;'

body() {
  local since=${1-} until=${2:-HEAD}
  local list
  list=$(prs "$since" "$until")
  jq -rn --argjson prs "$list" --arg first "$([ -n "$since" ] || echo 1)" --arg marker "<!-- folio-patch-notes $format -->" \
    "$summary $notes"'
    # One `### <kind>` group per kind in the order the app lists them, each in PR order; a line two PRs wrote alike once.
    ($prs | map(notes[]) | reduce .[] as $l ([]; if index([$l]) then . else . + [$l] end)) as $items
    | (kinds | map(. as $k | [$items[] | select(kind == $k)] | select(length > 0) | "### \($k)\n" + join("\n") + "\n")) as $groups
    | [ "## 패치 노트\n\($marker)\n" + (if ($groups | length) == 0 then "사용자에게 보이는 변화가 없습니다.\n" else "\n" + ($groups | join("\n")) end),
        if $first == "1" then "첫 릴리스입니다.\n" else empty end,
        if ($prs | length) == 0 then empty else
          "## 머지된 PR\n" + ($prs | map("- \(.title) (#\(.number))" + (summary | if . == "" then "" else "\n  \(.[0:280])" end)) | join("\n")) + "\n"
        end,
        # TODO(#414): once the app is signed with a Developer ID and notarized, this note goes.
        "## 설치\n서명과 공증을 하지 않은 빌드입니다. 압축을 풀어 `/Applications`에 옮긴 뒤 처음 한 번 `xattr -dr com.apple.quarantine /Applications/Folio.app`을 실행하거나, 시스템 설정 > 개인정보 보호 및 보안에서 \"그래도 열기\"를 누릅니다.\n"
      ] | join("\n")'
}

case "${1:-}" in
  body) shift; body "$@" ;;
  preview) body "${2-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)}" HEAD ;;
  *) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
