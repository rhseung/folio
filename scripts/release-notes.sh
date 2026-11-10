#!/usr/bin/env bash
# Release notes from the PRs merged to main between two commits.
#   release-notes.sh draft <since> [<until>]              a release-notes/<version>.json draft on stdout
#   release-notes.sh body <notes.json> <since> [<until>]  the GitHub release's markdown on stdout
#   release-notes.sh file [<since>]                       the draft into release-notes/<version>.json, since the last tag
# <since> is the previous release tag; empty means there is none (the first release lists no PRs).
#
# release-notes/<version>.json is meant as the source the patch notes (#415) bundle into the app; its format follows
# #415 once that design is approved, so this generator keeps the PR-to-item step in one place (item below). A PR that
# carries a fragment, release-notes/next/<PR>.json in the commit being released, gives its item as written. Any other
# feat, fix or perf PR gets an item drafted from its closed issue's feature name or its body's opening, to be edited
# into a short noun phrase before the tag. The release body is rendered from the notes file, so an edited file wins.
set -euo pipefail
cd "$(dirname "$0")/.."

# Squash merges put one commit per PR on main; a PR counts when its merge commit is in since..until.
prs() {
  local since=$1 until=$2
  [ -n "$since" ] || { echo '[]'; return; }
  local repo date shas
  repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
  shas=$(git rev-list "$since..$until" | jq -R . | jq -sc .)
  # The search is cut at the day of <since> to stay short; the SHAs decide.
  date=$(git log -1 --format=%cs "$since")
  gh api graphql --paginate -f q="repo:$repo is:pr is:merged base:main merged:>=$date" -f query='
    query($q: String!, $endCursor: String) {
      search(query: $q, type: ISSUE, first: 50, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { ... on PullRequest { number title body mergeCommit { oid } closingIssuesReferences(first: 5) { nodes { number title } } } }
      }
    }' --jq '.data.search.nodes[]' |
    jq -sc --argjson shas "$shas" '[.[] | select(.mergeCommit.oid as $o | $shas | index($o))] | sort_by(.number)'
}

# The PR body's first paragraph, without markdown emphasis or the trailing session link.
summary='def summary: (.body // "") | split("\n\n") | map(select(test("^\\s*(#|https://claude.ai/)") | not)) | (.[0] // "")
  | gsub("\\*\\*|`"; "") | gsub("\\s*\n\\s*"; " ") | ltrimstr(" ") | rtrimstr(" ");'
kind='def kind: .title | capture("^(?<t>[a-z]+)(\\([^)]*\\))?!?:").t // "" | {feat: "new", fix: "fixed", perf: "changed"}[.] // null;'

# The fragments at <until>, as {"<PR>": fragment}.
fragments() {
  local until=$1 f
  for f in $(git ls-tree --name-only "$until" release-notes/next/ 2>/dev/null | grep -E '/[0-9]+\.json$' || true); do
    git show "$until:$f" | jq -c --arg pr "$(basename "$f" .json)" '{($pr): .}'
  done | jq -sc 'add // {}'
}

draft() {
  local since=${1-} until=${2:-HEAD}
  prs "$since" "$until" | jq --arg v "$(scripts/version.sh get)" --arg d "$(git log -1 --format=%cs "$until")" \
    --argjson frag "$(fragments "$until")" "$summary $kind"'
    # A feature name: the closed issue'"'"'s title up to its colon, else the name a body opens with ("항목 메뉴 정리(#403)의
    # 첫 부분입니다"), else the first sentence. PRs that land on the same name become one item.
    def name: if (.closingIssuesReferences.nodes | length) > 0
      then .closingIssuesReferences.nodes[0].title | sub("\\s*:.*$"; "")
      else summary | (capture("^(?<n>[^(.]{1,40})\\(#[0-9]+[,)]").n // sub("(?<s>[^.]*[.!?]).*$"; "\(.s)")) end;
    def item: ($frag[.number | tostring]) as $f
      | if $f then {prs: [.number]} + $f
        elif kind then {kind: kind, title: name, prs: [.number], issues: [.closingIssuesReferences.nodes[].number]}
        else empty end;
    {schemaVersion: 1, version: $v, date: $d, items: [.[] | item]
      | group_by([.kind, .title]) | map((.[0] | del(.issues)) + {prs: (map(.prs[]) | unique)} + ({issues: (map(.issues // [] | .[]) | unique)} | if .issues == [] then {} else . end))
      | sort_by(.prs[0])}'
}

body() {
  local notes=${1:?notes.json} since=${2-} until=${3:-HEAD}
  local list
  list=$(prs "$since" "$until")
  jq -rn --slurpfile n "$notes" --argjson prs "$list" --arg first "$([ -n "$since" ] || echo 1)" "$summary"'
    # Known kinds first in this order; a kind the #415 format adds still gets its own heading.
    def heading: {new: "새 기능", fixed: "고침", changed: "바뀜"}[.] // .;
    def rank: . as $k | ["new", "fixed", "changed"] | index($k) // 9;
    [ ($n[0].items | group_by(.kind) | sort_by(.[0].kind | rank) | .[] |
        "## \(.[0].kind | heading)\n" + (map("- \(.title // .text)" + (.prs // [] | map(" #\(.)") | join(""))) | join("\n")) + "\n"),
      if $first == "1" then "첫 릴리스입니다.\n" else empty end,
      if ($prs | length) == 0 then empty else
        "## 머지된 PR\n" + ($prs | map("- \(.title) (#\(.number))" + (summary | if . == "" then "" else "\n  \(.[0:280])" end)) | join("\n")) + "\n"
      end,
      # TODO(#414): once the app is signed with a Developer ID and notarized, this note goes.
      "## 설치\n서명과 공증을 하지 않은 빌드입니다. 압축을 풀어 `/Applications`에 옮긴 뒤 처음 한 번 `xattr -dr com.apple.quarantine /Applications/Folio.app`을 실행하거나, 시스템 설정 > 개인정보 보호 및 보안에서 \"그래도 열기\"를 누릅니다.\n"
    ] | join("\n")'
}

case "${1:-}" in
  draft) shift; draft "$@" ;;
  body) shift; body "$@" ;;
  file)
    since="${2:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)}"
    out="release-notes/$(scripts/version.sh get).json"
    mkdir -p release-notes
    draft "$since" > "$out"
    echo "$out (since ${since:-no tag, so no PRs}); edit the texts into short noun phrases and merge it before the tag"
    ;;
  *) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
