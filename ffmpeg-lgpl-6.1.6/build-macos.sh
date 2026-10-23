#!/bin/bash
# Builds the LGPL-only FFmpeg used for testing in FFmpeg Stage B (macOS, universal arm64 + x86_64, macOS 12+).
# Reproducible: pinned source versions and SHA-256 checksums; no --enable-gpl, no --enable-nonfree; nothing from
# Homebrew or the system except Apple's SDK frameworks and libz/libbz2/libiconv.
# usage: scripts/ffmpeg-lgpl/build-macos.sh <work-folder>     (the work folder must be outside the app's repository)
# Output: <work-folder>/dist/ffmpeg (universal), BUILD-INFO.txt, licenses/.
set -euo pipefail
WORK="${1:?work folder required}"
mkdir -p "$WORK"/{downloads,src,dist,dist/licenses,logs}
WORK="$(cd "$WORK" && pwd)"
MIN_MACOS=12.0
JOBS=$(sysctl -n hw.ncpu)

# name|url|sha256
SOURCES='
ffmpeg-6.1.6.tar.xz|https://ffmpeg.org/releases/ffmpeg-6.1.6.tar.xz|d4fcb164028dd3beee5d92c0ac72e46aac6973c75ea12dc14de07bf8f407370a
freetype-2.14.3.tar.xz|https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.xz|36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f
harfbuzz-14.6.0.tar.xz|https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz|d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586
zimg-release-3.0.6.tar.gz|https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz|be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577
pkgconf-3.0.10.tar.xz|https://distfiles.ariadne.space/pkgconf/pkgconf-3.0.10.tar.xz|9371b2f6372da574d4c6dc96fe9b1463037bcf6afcb6671c1555afde7b17e2de
nasm-2.16.03.tar.xz|https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz|1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148
'
echo "$SOURCES" | while IFS='|' read -r name url sum; do
  [ -z "$name" ] && continue
  f="$WORK/downloads/$name"
  [ -f "$f" ] || curl -sSLf -o "$f" "$url"
  got=$(shasum -a 256 "$f" | cut -d' ' -f1)
  [ "$got" = "$sum" ] || { echo "CHECKSUM MISMATCH $name: $got"; exit 1; }
  echo "verified $name"
done

# Host build tools (arm64 host, never shipped): pkgconf and nasm (x86 assembler for the Intel slice).
TOOLS="$WORK/tools"
if [ ! -x "$TOOLS/bin/pkg-config" ]; then
  rm -rf "$WORK/src/pkgconf-3.0.10"; tar xf "$WORK/downloads/pkgconf-3.0.10.tar.xz" -C "$WORK/src"
  (cd "$WORK/src/pkgconf-3.0.10" && ./configure --prefix="$TOOLS" --disable-shared && make -j"$JOBS" && make install) > "$WORK/logs/pkgconf.log" 2>&1
  ln -sf pkgconf "$TOOLS/bin/pkg-config"
fi
if [ ! -x "$TOOLS/bin/nasm" ]; then
  rm -rf "$WORK/src/nasm-2.16.03"; tar xf "$WORK/downloads/nasm-2.16.03.tar.xz" -C "$WORK/src"
  (cd "$WORK/src/nasm-2.16.03" && ./configure --prefix="$TOOLS" && make -j"$JOBS" && make install) > "$WORK/logs/nasm.log" 2>&1
fi
export PATH="$TOOLS/bin:$PATH"

build_arch() {
  local ARCH="$1" P="$WORK/prefix-$1" S="$WORK/src-$1"
  rm -rf "$S" "$P"; mkdir -p "$S" "$P/lib/pkgconfig" "$P/include"
  local CF="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -O2"
  export MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS
  for a in freetype-2.14.3.tar.xz harfbuzz-14.6.0.tar.xz zimg-release-3.0.6.tar.gz ffmpeg-6.1.6.tar.xz; do tar xf "$WORK/downloads/$a" -C "$S"; done
  local HOSTFLAG=""; [ "$ARCH" = x86_64 ] && HOSTFLAG="--host=x86_64-apple-darwin"

  # FreeType (FTL licence option): no zlib/png/bzip2/brotli/harfbuzz
  (cd "$S/freetype-2.14.3" && CFLAGS="$CF" LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS" ./configure $HOSTFLAG --prefix="$P" --disable-shared --enable-static \
     --without-harfbuzz --without-png --without-zlib --without-bzip2 --without-brotli && make -j"$JOBS" && make install) > "$WORK/logs/freetype-$ARCH.log" 2>&1

  # zimg (WTFPL): no autotools here, so compile the library sources directly. arm64 keeps its NEON code;
  # x86_64 uses the portable C++ code (only HDR stills / collage HDR clips use zscale).
  ( cd "$S/zimg-release-3.0.6"; mkdir -p obj
    if [ "$ARCH" = arm64 ]; then DEF=-DZIMG_ARM; FILTER='/x86/'; else DEF=; FILTER='/(x86|arm)/'; fi
    find src/zimg -name '*.cpp' | grep -Ev "$FILTER" | while read -r f; do
      clang++ $CF -std=c++17 -DNDEBUG $DEF -fvisibility=hidden -fno-fast-math -ffp-contract=off -Isrc/zimg -c "$f" -o "obj/$(echo "$f" | tr / _).o"
    done
    ar rcs "$P/lib/libzimg.a" obj/*.o; cp src/zimg/api/zimg.h src/zimg/api/zimg++.hpp "$P/include/" ) > "$WORK/logs/zimg-$ARCH.log" 2>&1
  printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: zimg\nDescription: zimg\nVersion: 3.0.6\nLibs: -L${libdir} -lzimg -lc++\nCflags: -I${includedir}\n' "$P" > "$P/lib/pkgconfig/zimg.pc"

  # HarfBuzz ("Old MIT"): single-file build with FreeType support (drawtext needs it)
  ( cd "$S/harfbuzz-14.6.0/src"
    clang++ $CF -std=c++17 -DNDEBUG -DHAVE_FREETYPE=1 -DHAVE_PTHREAD=1 -I"$P/include/freetype2" -fno-exceptions -fno-rtti -fvisibility-inlines-hidden -c harfbuzz.cc -o harfbuzz.o
    ar rcs "$P/lib/libharfbuzz.a" harfbuzz.o; mkdir -p "$P/include/harfbuzz"; cp hb*.h "$P/include/harfbuzz/" ) > "$WORK/logs/harfbuzz-$ARCH.log" 2>&1
  printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: harfbuzz\nDescription: harfbuzz\nVersion: 14.6.0\nRequires.private: freetype2\nLibs: -L${libdir} -lharfbuzz -lc++\nCflags: -I${includedir}/harfbuzz\n' "$P" > "$P/lib/pkgconfig/harfbuzz.pc"

  # FFmpeg 6.1.6, LGPL v2.1+ (no --enable-gpl / --enable-version3 / --enable-nonfree); only the ffmpeg program
  local CROSS=""; [ "$ARCH" = x86_64 ] && CROSS="--enable-cross-compile --target-os=darwin --x86asmexe=$TOOLS/bin/nasm"
  ( cd "$S/ffmpeg-6.1.6" && PKG_CONFIG_PATH="$P/lib/pkgconfig" ./configure --prefix="$P" --arch="$ARCH" --cc="clang -arch $ARCH" --cxx="clang++ -arch $ARCH" $CROSS \
      --pkg-config="$TOOLS/bin/pkg-config" --pkg-config-flags=--static \
      --extra-cflags="-I$P/include -mmacosx-version-min=$MIN_MACOS" --extra-ldflags="-L$P/lib -mmacosx-version-min=$MIN_MACOS" --extra-libs=-liconv \
      --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib --enable-iconv \
      --enable-libfreetype --enable-libharfbuzz --enable-libzimg \
      --disable-ffplay --disable-ffprobe --disable-doc --disable-network --enable-static --disable-shared \
    && make -j"$JOBS" && make install ) > "$WORK/logs/ffmpeg-$ARCH.log" 2>&1
  grep -E '^License:' "$WORK/logs/ffmpeg-$ARCH.log" | grep -q 'LGPL version 2.1 or later' || { echo "LICENCE CHECK FAILED ($ARCH)"; exit 1; }
  echo "built $ARCH"
}
build_arch arm64
build_arch x86_64
lipo -create "$WORK/prefix-arm64/bin/ffmpeg" "$WORK/prefix-x86_64/bin/ffmpeg" -output "$WORK/dist/ffmpeg"
chmod 755 "$WORK/dist/ffmpeg"

# Licences that travel with the binary
S="$WORK/src-arm64"
cp "$S/ffmpeg-6.1.6/COPYING.LGPLv2.1" "$S/ffmpeg-6.1.6/LICENSE.md" "$WORK/dist/licenses/"
cp "$S/freetype-2.14.3/docs/FTL.TXT" "$WORK/dist/licenses/freetype-FTL.TXT"; cp "$S/freetype-2.14.3/LICENSE.TXT" "$WORK/dist/licenses/freetype-LICENSE.TXT"
cp "$S/harfbuzz-14.6.0/COPYING" "$WORK/dist/licenses/harfbuzz-COPYING"; cp "$S/harfbuzz-14.6.0/src/ms-use/COPYING" "$WORK/dist/licenses/harfbuzz-ms-use-COPYING"
cp "$S/zimg-release-3.0.6/COPYING" "$WORK/dist/licenses/zimg-COPYING"

{ echo "FFmpeg LGPL build — $(date -u +%FT%TZ)"; echo "SHA-256 $(shasum -a 256 "$WORK/dist/ffmpeg" | cut -d' ' -f1)"; lipo -info "$WORK/dist/ffmpeg"
  echo; echo "Sources:"; echo "$SOURCES" | sed '/^$/d'
  for a in arm64 x86_64; do echo; echo "== $a"; otool -l "$WORK/prefix-$a/bin/ffmpeg" | grep -A3 LC_BUILD_VERSION | grep -E 'minos|sdk'; otool -L "$WORK/prefix-$a/bin/ffmpeg" | tail -n +2; done
  echo; "$WORK/dist/ffmpeg" -hide_banner -buildconf; "$WORK/dist/ffmpeg" -hide_banner -L | head -3; } > "$WORK/dist/BUILD-INFO.txt" 2>&1
echo "done: $WORK/dist/ffmpeg"
