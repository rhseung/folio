#!/usr/bin/env bash
# Reads and moves Folio's version. The marketing version lives in FolioVersion (Swift, so the CLI compiles it in); the
# build number is the commit count, which grows with every merge to main because main is squash-only.
#   version.sh get                      0.1.0
#   version.sh build                    the build number of HEAD
#   version.sh xcconfig                 writes .build/version.xcconfig, which project.yml gives the app
#   version.sh bump major|minor|patch   rewrites FolioVersion
#   version.sh tag                      tags origin/main as v<version> and pushes the tag
set -euo pipefail
cd "$(dirname "$0")/.."
source=sources/domain/shared/app/folio-version.swift

read_version() { sed -nE 's/.*static let marketing = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' | head -1; }

get() {
  local v
  v=$(read_version < "$source")
  [ -n "$v" ] || { echo "no X.Y.Z version in $source" >&2; exit 1; }
  echo "$v"
}

build() {
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    echo "warning: shallow clone, the build number is not the commit count" >&2
  fi
  git rev-list --count HEAD 2>/dev/null || echo 0
}

case "${1:-}" in
  get) get ;;
  build) build ;;
  xcconfig)
    mkdir -p .build
    printf 'MARKETING_VERSION = %s\nCURRENT_PROJECT_VERSION = %s\n' "$(get)" "$(build)" > .build/version.xcconfig
    ;;
  bump)
    IFS=. read -r major minor patch <<< "$(get)"
    case "${2:-}" in
      major) new="$((major + 1)).0.0" ;;
      minor) new="$major.$((minor + 1)).0" ;;
      patch) new="$major.$minor.$((patch + 1))" ;;
      *) echo "usage: mise run version-bump -- major|minor|patch" >&2; exit 2 ;;
    esac
    perl -pi -e "s/(static let marketing = \")[0-9.]+(\")/\${1}$new\${2}/" "$source"
    [ "$(get)" = "$new" ] || { echo "could not rewrite $source" >&2; exit 1; }
    echo "$new"
    ;;
  tag)
    # 로컬 체크아웃에는 머지하지 않은 작업이 있을 수 있으므로, 태그는 origin/main에 단다.
    git fetch -q origin main --tags
    v=$(git show origin/main:"$source" | read_version)
    [ -n "$v" ] || { echo "no version on origin/main" >&2; exit 1; }
    tag="v$v"
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      echo "$tag already exists; bump the version first (mise run version-bump -- patch)" >&2
      exit 1
    fi
    git tag -a "$tag" origin/main -m "Folio $v"
    git push origin "$tag"
    echo "$tag pushed; the release workflow drafts its release"
    ;;
  *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
