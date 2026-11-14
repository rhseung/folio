#!/usr/bin/env bash
# Package.swift의 바이너리 타깃이 sources/tectonic/vendor의 FolioTectonic.xcframework를 가리키므로, 받은 라이브러리를
# 그 자리에 둔다.
set -euo pipefail
cd "$(dirname "$0")/../.."
pin=sources/tectonic/pin.json
dest=sources/tectonic/vendor
url=$(jq -er .url "$pin")
sha=$(jq -er .sha256 "$pin")
built=$(jq -er .inputs "$pin")
now=$(sources/tectonic/build.sh --inputs)
if [ "$built" != "$now" ]; then
  echo "warning: sources/tectonic/pin.json is a build of inputs $built, but the bridge, patches and build script are now $now;" \
    "the Tectonic workflow publishes their build and prints the pin to copy" >&2
fi
[ -n "$sha" ] || {
  echo "sources/tectonic/pin.json has no sha256 yet: the Tectonic workflow prints it once it has published $url" >&2
  exit 1
}
if [ -f "$dest/pin" ] && [ "$(cat "$dest/pin")" = "$sha" ] && [ -d "$dest/FolioTectonic.xcframework" ]; then exit 0; fi

mkdir -p .build/tectonic
zip=.build/tectonic/FolioTectonic-$sha.zip
if [ ! -f "$zip" ] || ! echo "$sha  $zip" | shasum -a 256 -c --status; then
  curl -fL --retry 3 --progress-bar -o "$zip.part" "$url"
  mv "$zip.part" "$zip"
fi
echo "$sha  $zip" | shasum -a 256 -c --status || {
  echo "$url does not match the sha256 in $pin" >&2
  rm -f "$zip"
  exit 1
}
rm -rf "$dest"
mkdir -p "$dest"
ditto -x -k "$zip" "$dest"
echo "$sha" >"$dest/pin"
