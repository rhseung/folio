#!/usr/bin/env bash
# Puts the iPad's TeX engine (Siglum's BusyTeX: TeX Live in WebAssembly) in .build/tex-engine/TexEngine, which the
# iPad app bundles. The engine is code, so it ships inside the app and is never downloaded by it (App Store 2.5.2);
# packages it lacks are data the app fetches from a CTAN mirror of TeX Live. Every download is checked against the
# hash in app/resources/tex-engine.json, the one file to change for a new runtime or engine. Where the engine files
# live is still open (#41): if they move, only this step changes.
set -euo pipefail
cd "$(dirname "$0")/.."
pin=app/resources/tex-engine.json
out=.build/tex-engine
dest="$out/TexEngine"
stamp="$out/pin"
want=$(shasum -a 256 "$pin" scripts/tex-engine.sh | shasum -a 256 | cut -d' ' -f1)
if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then exit 0; fi

value() { jq -er "$1" "$pin"; }
fetch() { # url sha256 file
  if [ ! -f "$3" ] || ! echo "$2  $3" | shasum -a 256 -c --status; then
    curl -fL --retry 3 --progress-bar -o "$3.part" "$1"
    mv "$3.part" "$3"
  fi
  echo "$2  $3" | shasum -a 256 -c --status || { echo "$3 does not match its pinned sha256" >&2; rm -f "$3"; exit 1; }
}

mkdir -p "$out/downloads"
runtime="$out/downloads/runtime-$(value .runtime.version).tar.gz"
tlpdb="$out/downloads/texlive.tlpdb.xz"
fetch "$(value .runtime.url)" "$(value .runtime.sha256)" "$runtime"
fetch "$(value .texlive.tlpdb)" "$(value .texlive.tlpdbSha256)" "$tlpdb"

tmp="$out/unpack"
rm -rf "$tmp" "$dest"
mkdir -p "$tmp" "$dest/bundles"
tar -xzf "$runtime" -C "$tmp"
# The runtime holds every engine's bundles, and .raw copies the CDN serves for range requests. The app keeps the
# .data.gz of the engine it runs; leaveOut names the other engines' bundles, and cm-super (60 MB of T1 Type 1 fonts).
leave=$(value '.leaveOut | join(" ")')
for meta in "$tmp"/*.meta.json; do
  name=$(basename "$meta" .meta.json)
  case " $leave " in *" $name "*) continue ;; esac
  cp "$tmp/$name.data.gz" "$tmp/$name.meta.json" "$dest/bundles/"
done
cp "$tmp"/*.json "$dest/bundles/"
mkdir -p "$dest/wasm"
cp "$tmp/wasm/busytex.wasm" "$tmp/wasm/busytex.js" "$dest/wasm/"
cp "$tmp/xzwasm.js" "$dest/"
cp "$tmp/runtime.json" "$dest/"
rm -rf "$tmp"

# Which TeX Live package holds a file TeX asked for. Siglum's own tables miss fonts like kotex's uwmj*.tfm (package
# uhc). The package database is the snapshot the runtime's formats were built from: it is pinned, where the mirror's
# changes daily, and which package holds a file hardly ever moves. That host checks for bots, which the app's own
# downloads could not pass, so the app fetches packages from the mirror instead.
xz -dc "$tlpdb" | awk '
  /^name / { pkg = $2; dot = index(pkg, "."); next }
  /^ / && pkg != "" && dot == 0 {
    path = $1
    if (path !~ /^(RELOC\/)?(texmf-dist\/)?(tex|fonts\/(tfm|vf|type1|enc|map)|bibtex\/(bst|bib))\//) next
    n = split(path, parts, "/"); file = parts[n]
    if (file ~ /\.(sty|cls|tex|def|cfg|clo|fd|ldf|tfm|vf|pfb|enc|map|bst|bib)$/ && !(file in seen)) { seen[file] = 1; print file "\t" pkg }
  }' | LC_ALL=C sort > "$dest/files.tsv"
echo "$want" > "$stamp"
du -sh "$dest"
