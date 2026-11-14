#!/bin/bash
# test-ipad와 CI가 미리 켜는 시뮬레이터가 같아야 부팅이 빌드와 겹친다. 그래서 이미 켠 iPad를 먼저 고른다.
set -euo pipefail
pick() { grep -m1 -E '^ +iPad' | grep -oE '[0-9A-F-]{36}' || true; }
id=$(xcrun simctl list devices booted available | pick)
[ -n "$id" ] || id=$(xcrun simctl list devices available | pick)
[ -n "$id" ] || {
  echo "no available iPad simulator" >&2
  exit 1
}
case "${1:-}" in
  "") echo "$id" ;;
  boot) xcrun simctl bootstatus "$id" -b >/dev/null ;;
  *)
    echo "usage: scripts/ipad-simulator.sh [boot]" >&2
    exit 2
    ;;
esac
