#!/usr/bin/env bash
# Builds FolioTectonic.xcframework: Tectonic as a static library for iOS devices, the iOS simulator and macOS (#41).
# CI runs it (.github/workflows/tectonic.yml) and publishes the zip as a release asset; the app's builds only fetch that
# zip, checked by the sha256 in tectonic/pin.json (scripts/tectonic.sh), so neither the repository nor an app build
# needs Rust or these sources.
#
# Tectonic is built from its release tag with tectonic/patches applied: ios-coretext.patch lets XeTeX find fonts with
# CoreText on iOS as it does on macOS, so no fontconfig is needed. HarfBuzz comes with Tectonic; ICU is the SDK's
# libicucore, called through ICU 79's headers with renaming off.
#
#   scripts/tectonic-build.sh <work folder> <output zip>
#   scripts/tectonic-build.sh --inputs     prints the hash that names a build of the current inputs
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

TECTONIC_TAG="tectonic@0.17.0"
TECTONIC_COMMIT="8c0126a9653239a2e6e0a5274af9b8510f643030"
DEPLOYMENT=26.0
# url sha256
LIBPNG="https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.xz d80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389"
FREETYPE="https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.xz 36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f"
GRAPHITE2="https://github.com/silnrsi/graphite/releases/download/1.3.15/graphite2-1.3.15.tgz c6bc8b4252724665297f7cad0c55897285c673f9b8e6db3522ace833593fe0b1"
ICU="https://github.com/unicode-org/icu/releases/download/release-79.1/icu4c-79.1-sources.tgz 06fa63ecb521048f8082f12ad988f6b678d90cbd88aafce24cbc94902b191d99"

inputs() {
  (cd "$root" && cat scripts/tectonic-build.sh tectonic/bridge/Cargo.toml tectonic/bridge/src/*.rs tectonic/bridge/include/* \
    tectonic/patches/*.patch) | shasum -a 256 | cut -c1-12
}
if [ "${1:-}" = "--inputs" ]; then inputs; exit 0; fi

work="$(mkdir -p "$1" && cd "$1" && pwd)"
zip="$2"
case "$zip" in /*) ;; *) zip="$PWD/$zip" ;; esac
src="$work/src"
mkdir -p "$src" "$work/downloads"

fetch() { # "url sha256" -> path of the checked download
  set -- $1
  local file="$work/downloads/$(basename "$1")"
  if [ ! -f "$file" ] || ! echo "$2  $file" | shasum -a 256 -c --status; then
    curl -fsSL --retry 3 -o "$file.part" "$1" && mv "$file.part" "$file"
  fi
  echo "$2  $file" | shasum -a 256 -c --status || { echo "$file does not match its pinned sha256" >&2; exit 1; }
  echo "$file"
}

for dep in "$LIBPNG" "$FREETYPE" "$GRAPHITE2" "$ICU"; do tar -xf "$(fetch "$dep")" -C "$src"; done
icu_include="$work/icu-include"
rm -rf "$icu_include" && mkdir -p "$icu_include/unicode"
cp "$src"/icu/source/{common,i18n,io}/unicode/*.h "$icu_include/unicode/"

# The bridge's Cargo.toml finds Tectonic at ../tectonic, so both sit side by side in the work folder.
if [ ! -d "$work/tectonic/.git" ]; then
  git init -q "$work/tectonic"
  git -C "$work/tectonic" remote add origin https://github.com/tectonic-typesetting/tectonic.git
fi
git -C "$work/tectonic" fetch -q --depth 1 origin "refs/tags/$TECTONIC_TAG"
git -C "$work/tectonic" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
git -C "$work/tectonic" clean -qfdx
[ "$(git -C "$work/tectonic" rev-parse HEAD)" = "$TECTONIC_COMMIT" ] || { echo "$TECTONIC_TAG is no longer $TECTONIC_COMMIT" >&2; exit 1; }
git -C "$work/tectonic" submodule update -q --init --depth 1 crates/bridge_harfbuzz/harfbuzz
for patch in "$root"/tectonic/patches/*.patch; do git -C "$work/tectonic" apply "$patch"; done
rm -rf "$work/bridge" && cp -R "$root/tectonic/bridge" "$work/bridge"
# Tectonic's own lock pins every crate it was released with; only the bridge itself is new to it.
cp "$work/tectonic/Cargo.lock" "$work/bridge/Cargo.lock"

slice() { # name sdk cmake-system rust-target min-flag
  local name=$1 sdk=$2 system=$3 target=$4 min=$5
  local sysroot prefix build
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  prefix="$work/prefix/$name"
  build="$work/native/$name"
  rm -rf "$prefix" "$build"
  mkdir -p "$prefix/lib/pkgconfig" "$prefix/include" "$build"

  cat > "$build/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME "$system")
set(CMAKE_OSX_SYSROOT "$sysroot")
set(CMAKE_OSX_ARCHITECTURES "arm64")
set(CMAKE_OSX_DEPLOYMENT_TARGET "$DEPLOYMENT")
set(CMAKE_C_COMPILER "$(xcrun --sdk "$sdk" --find clang)")
set(CMAKE_CXX_COMPILER "$(xcrun --sdk "$sdk" --find clang++)")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
  # zlib and libicucore come with the SDK, which has no .pc files for them (and no ICU headers).
  printf 'prefix=%s/usr\nincludedir=${prefix}/include\nlibdir=${prefix}/lib\n\nName: zlib\nDescription: SDK zlib\nVersion: 1.2.12\nLibs: -lz\nCflags: -I${includedir}\n' \
    "$sysroot" > "$prefix/lib/pkgconfig/zlib.pc"
  printf 'includedir=%s\n\nName: icu-uc\nDescription: SDK libicucore\nVersion: 79.1\nLibs: -licucore\nCflags: -I${includedir} -DU_DISABLE_RENAMING=1\n' \
    "$icu_include" > "$prefix/lib/pkgconfig/icu-uc.pc"

  cm() {
    cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$build/toolchain.cmake" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="$min" -DCMAKE_CXX_FLAGS="$min" -DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@"
  }
  local zlib=(-DZLIB_LIBRARY="$sysroot/usr/lib/libz.tbd" -DZLIB_INCLUDE_DIR="$sysroot/usr/include")
  cm -S "$src/libpng-1.6.59" -B "$build/libpng" -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_FRAMEWORK=OFF -DPNG_TESTS=OFF \
    -DPNG_TOOLS=OFF "${zlib[@]}"
  cmake --build "$build/libpng" && cmake --install "$build/libpng"
  cm -S "$src/graphite2-1.3.15" -B "$build/graphite2" -DBUILD_TESTING=OFF -DGRAPHITE2_NFILEFACE=ON -DGRAPHITE2_NTRACING=ON \
    -DGRAPHITE2_TELEMETRY=OFF
  cmake --build "$build/graphite2" && cmake --install "$build/graphite2"
  cm -S "$src/freetype-2.14.3" -B "$build/freetype" -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_HARFBUZZ=ON \
    -DFT_DISABLE_PNG=OFF -DFT_REQUIRE_PNG=ON -DFT_DISABLE_ZLIB=OFF -DFT_REQUIRE_ZLIB=ON "${zlib[@]}" \
    -DPNG_LIBRARY="$prefix/lib/libpng16.a" -DPNG_PNG_INCLUDE_DIR="$prefix/include/libpng16"
  cmake --build "$build/freetype" && cmake --install "$build/freetype"

  # Only the target's C flags carry the platform: global CFLAGS would also reach build scripts compiled for this Mac,
  # and psm's host assembly then fails with an iOS minimum version.
  local var=${target//-/_}
  env CARGO_TARGET_DIR="$work/cargo-target" PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
    TECTONIC_PKGCONFIG_FORCE_SEMI_STATIC=1 IPHONEOS_DEPLOYMENT_TARGET=$DEPLOYMENT MACOSX_DEPLOYMENT_TARGET=$DEPLOYMENT \
    "CFLAGS_$var=-DU_DISABLE_RENAMING=1 $min" "CXXFLAGS_$var=-DU_DISABLE_RENAMING=1 $min" \
    cargo build --manifest-path "$work/bridge/Cargo.toml" --target "$target" --release
  # One archive per slice, so the app links a single library.
  mkdir -p "$work/lib/$name"
  libtool -static -o "$work/lib/$name/libFolioTectonic.a" "$work/cargo-target/$target/release/libfolio_tectonic.a" \
    "$prefix/lib/libfreetype.a" "$prefix/lib/libgraphite2.a" "$prefix/lib/libpng16.a"
}

slice ios iphoneos iOS aarch64-apple-ios "-miphoneos-version-min=$DEPLOYMENT"
slice ios-simulator iphonesimulator iOS aarch64-apple-ios-sim "-mios-simulator-version-min=$DEPLOYMENT"
slice macos macosx Darwin aarch64-apple-darwin "-mmacosx-version-min=$DEPLOYMENT"

out="$work/FolioTectonic.xcframework"
rm -rf "$out" "$zip"
args=()
for name in ios ios-simulator macos; do args+=(-library "$work/lib/$name/libFolioTectonic.a" -headers "$work/bridge/include"); done
xcodebuild -create-xcframework "${args[@]}" -output "$out"
(cd "$work" && ditto -c -k --keepParent FolioTectonic.xcframework "$zip")
shasum -a 256 "$zip"
