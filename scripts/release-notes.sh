#!/usr/bin/env bash
# The GitHub release's body, from the PRs merged to main between two commits.
#   release-notes.sh body <since> [<until>]   the body on stdout; an empty <since> means no earlier release
#   release-notes.sh preview [<since>]        the same, since the latest v* tag unless given
# The first release (no earlier tag) gathers every PR merged before it.
#
# A PR that changes what the student sees writes its patch notes in its own body (AGENTS.md "PR 전 점검"): a
# `## 패치 노트` section of lines `- feat: …`, `- fix: …` or `- change: …`, each optionally ending in `(folio://…)`. The
# PR's body is read here at release time, not its commit message, so a body edited after the merge still counts. The
# lines go into the release under the same heading, after a marker naming their shape, in `### feat`, `### fix` and
# `### change` groups; the app reads them back from GitHub's releases (`PatchNotes` in FolioDomain) and passes over the
# group headings. Keep `format`, the kinds and the line shape in step with that reader.
set -euo pipefail
cd "$(dirname "$0")/.."
format=1

# Squash merges put one commit per PR on main; a PR counts when its merge commit is in since..until.
prs() {
  local since=$1 until=$2
  local repo shas q
  repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
  if [ -n "$since" ]; then
    shas=$(git rev-list "$since..$until" | jq -R . | jq -sc .)
    # The search is cut at the day of <since> to stay short; the SHAs decide.
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

# The PR body's first paragraph, without markdown emphasis or the trailing session link.
summary='def summary: (.body // "") | split("\n\n") | map(select(test("^\\s*(#|https://claude.ai/)") | not)) | (.[0] // "")
  | gsub("\\*\\*|`"; "") | gsub("\\s*\n\\s*"; " ") | ltrimstr(" ") | rtrimstr(" ");'

# The item lines of a body's `## 패치 노트` section, written the one way the app reads (`- feat: …`). The section ends at
# the next heading of its level or above, so a body grouped under `### feat` is read whole; prose and blank lines in it
# are left out.
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
