#!/usr/bin/env bash
# ios-coretext.patch는 XeTeX가 iOS에서도 macOS처럼 CoreText로 글꼴을 찾게 하므로 fontconfig가 필요 없다. ICU는 SDK의
# libicucore를 쓰고, ICU 79의 헤더로 renaming을 끈 채 부른다.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"

TECTONIC_TAG="tectonic@0.17.0"
TECTONIC_COMMIT="8c0126a9653239a2e6e0a5274af9b8510f643030"
DEPLOYMENT=26.0
LIBPNG="https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.xz d80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389"
FREETYPE="https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.xz 36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f"
GRAPHITE2="https://github.com/silnrsi/graphite/releases/download/1.3.15/graphite2-1.3.15.tgz c6bc8b4252724665297f7cad0c55897285c673f9b8e6db3522ace833593fe0b1"
ICU="https://github.com/unicode-org/icu/releases/download/release-79.1/icu4c-79.1-sources.tgz 06fa63ecb521048f8082f12ad988f6b678d90cbd88aafce24cbc94902b191d99"

# 워크플로도 입력에 넣는다. 워크플로가 Rust, Xcode, CMake, Ninja, pkg-config의 판을 고정하므로, 빠뜨리면 도구만 바꾼
# 빌드가 같은 이름의 이전 릴리스를 찾고 빌드를 건너뛴다.
inputs() {
  (cd "$root/sources/tectonic" && cat build.sh bridge/Cargo.toml bridge/src/*.rs bridge/include/* patches/*.patch \
    ../../.github/workflows/tectonic.yml) | shasum -a 256 | cut -c1-12
}
if [ "${1:-}" = "--inputs" ]; then inputs; exit 0; fi

work="$(mkdir -p "$1" && cd "$1" && pwd)"
zip="$2"
case "$zip" in /*) ;; *) zip="$PWD/$zip" ;; esac
src="$work/src"
mkdir -p "$src" "$work/downloads"

fetch() {
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

# 브리지의 Cargo.toml이 Tectonic을 ../tectonic에서 찾으므로, 작업 폴더에 둘을 나란히 둔다.
if [ ! -d "$work/tectonic/.git" ]; then
  git init -q "$work/tectonic"
  git -C "$work/tectonic" remote add origin https://github.com/tectonic-typesetting/tectonic.git
fi
git -C "$work/tectonic" fetch -q --depth 1 origin "refs/tags/$TECTONIC_TAG"
git -C "$work/tectonic" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
git -C "$work/tectonic" clean -qfdx
[ "$(git -C "$work/tectonic" rev-parse HEAD)" = "$TECTONIC_COMMIT" ] || { echo "$TECTONIC_TAG is no longer $TECTONIC_COMMIT" >&2; exit 1; }
git -C "$work/tectonic" submodule update -q --init --depth 1 crates/bridge_harfbuzz/harfbuzz
for patch in "$root"/sources/tectonic/patches/*.patch; do git -C "$work/tectonic" apply "$patch"; done
rm -rf "$work/bridge" && cp -R "$root/sources/tectonic/bridge" "$work/bridge"
# Tectonic의 lock 파일은 릴리스 때의 모든 crate 판을 고정하고, 거기에 없는 것은 브리지 자신뿐이다.
cp "$work/tectonic/Cargo.lock" "$work/bridge/Cargo.lock"

slice() {
  local name=$1 sdk=$2 system=$3 target=$4 min=$5 deployment=$6
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
  # zlib과 libicucore는 SDK에 들어 있지만, SDK에는 그 .pc 파일이 없고 ICU 헤더도 없다.
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

  # 플랫폼은 타깃의 C 플래그에만 넣는다. 전역 CFLAGS는 이 Mac용으로 컴파일하는 build script에도 들어가서, psm의 호스트
  # 어셈블리가 iOS 최소 버전 때문에 실패한다. deployment 변수도 그 slice의 것 하나만 설정한다. clang은 플랫폼을 지정하지
  # 않은 컴파일에서 이 변수를 읽는데, 둘 다 설정하면 macOS slice에서 aws-lc-sys의 컴파일러 검사가 iOS용으로 빌드되었다.
  local var=${target//-/_}
  env -u IPHONEOS_DEPLOYMENT_TARGET -u MACOSX_DEPLOYMENT_TARGET "$deployment=$DEPLOYMENT" \
    CARGO_TARGET_DIR="$work/cargo-target" PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
    TECTONIC_PKGCONFIG_FORCE_SEMI_STATIC=1 \
    "CFLAGS_$var=-DU_DISABLE_RENAMING=1 $min" "CXXFLAGS_$var=-DU_DISABLE_RENAMING=1 $min" \
    cargo build --manifest-path "$work/bridge/Cargo.toml" --target "$target" --release
  mkdir -p "$work/lib/$name"
  libtool -static -o "$work/lib/$name/libFolioTectonic.a" "$work/cargo-target/$target/release/libfolio_tectonic.a" \
    "$prefix/lib/libfreetype.a" "$prefix/lib/libgraphite2.a" "$prefix/lib/libpng16.a"
}

slice ios iphoneos iOS aarch64-apple-ios "-miphoneos-version-min=$DEPLOYMENT" IPHONEOS_DEPLOYMENT_TARGET
slice ios-simulator iphonesimulator iOS aarch64-apple-ios-sim "-mios-simulator-version-min=$DEPLOYMENT" IPHONEOS_DEPLOYMENT_TARGET
slice macos macosx Darwin aarch64-apple-darwin "-mmacosx-version-min=$DEPLOYMENT" MACOSX_DEPLOYMENT_TARGET

out="$work/FolioTectonic.xcframework"
rm -rf "$out" "$zip"
args=()
for name in ios ios-simulator macos; do args+=(-library "$work/lib/$name/libFolioTectonic.a" -headers "$work/bridge/include"); done
xcodebuild -create-xcframework "${args[@]}" -output "$out"
(cd "$work" && ditto -c -k --keepParent FolioTectonic.xcframework "$zip")
shasum -a 256 "$zip"
