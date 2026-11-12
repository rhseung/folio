#!/usr/bin/env bash
# Puts FolioTectonic.xcframework (Tectonic as a static library, #41) where packages/folio-core's binary target expects
# it. The library is built by .github/workflows/tectonic.yml from tectonic/ and scripts/tectonic-build.sh and published
# as a release asset; tectonic/pin.json names that asset and its sha256, so the repository holds no binaries and a
# build needs no Rust. After changing tectonic/ or the build script, wait for that workflow and copy the pin it prints.
set -euo pipefail
cd "$(dirname "$0")/.."
pin=tectonic/pin.json
dest=packages/folio-core/vendor
url=$(jq -er .url "$pin")
sha=$(jq -er .sha256 "$pin")
built=$(jq -er .inputs "$pin")
now=$(scripts/tectonic-build.sh --inputs)
if [ "$built" != "$now" ]; then
  echo "warning: tectonic/pin.json is a build of inputs $built, but tectonic/ and the build script are now $now;" \
    "the Tectonic workflow publishes their build and prints the pin to copy" >&2
fi
[ -n "$sha" ] || { echo "tectonic/pin.json has no sha256 yet: the Tectonic workflow prints it once it has published $url" >&2; exit 1; }
if [ -f "$dest/pin" ] && [ "$(cat "$dest/pin")" = "$sha" ] && [ -d "$dest/FolioTectonic.xcframework" ]; then exit 0; fi

mkdir -p .build/tectonic
zip=.build/tectonic/FolioTectonic-$sha.zip
if [ ! -f "$zip" ] || ! echo "$sha  $zip" | shasum -a 256 -c --status; then
  curl -fL --retry 3 --progress-bar -o "$zip.part" "$url"
  mv "$zip.part" "$zip"
fi
echo "$sha  $zip" | shasum -a 256 -c --status || { echo "$url does not match the sha256 in $pin" >&2; rm -f "$zip"; exit 1; }
rm -rf "$dest"
mkdir -p "$dest"
ditto -x -k "$zip" "$dest"
echo "$sha" > "$dest/pin"
