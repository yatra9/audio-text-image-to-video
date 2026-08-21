#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${1:?project directory required}"
WORK_ROOT="/opt/libav-wasm-dev"
EMSDK_DIR="$WORK_ROOT/emsdk"
LIBAV_DIR="$WORK_ROOT/libav.js"
NPM_DEPS="$WORK_ROOT/npm-deps"
LIBAV_TAG="v5.4.6.1.1"
EMSDK_VERSION="3.1.55"
LIBAV_VERSION="5.4.6.1.1"
FINAL_HTML="$PROJECT_DIR/index.html"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
trap 'echo; echo "BUILD FAILED at line $LINENO" >&2' ERR

log "Installing Debian build prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates git curl xz-utils bzip2 tar gzip unzip \
  build-essential pkg-config autoconf automake libtool m4 cmake ninja-build \
  patch gawk file perl \
  python3 nodejs npm

mkdir -p "$WORK_ROOT"

log "Preparing Emscripten SDK $EMSDK_VERSION"
if [[ ! -d "$EMSDK_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
else
  git -C "$EMSDK_DIR" fetch --prune --tags
fi
cd "$EMSDK_DIR"
./emsdk install "$EMSDK_VERSION"
./emsdk activate "$EMSDK_VERSION"
# shellcheck disable=SC1091
source "$EMSDK_DIR/emsdk_env.sh"
emcc --version | head -n 1

log "Preparing libav.js $LIBAV_TAG (existing checkout will be reused)"
if [[ ! -d "$LIBAV_DIR/.git" ]]; then
  git clone https://github.com/Yahweasel/libav.js.git "$LIBAV_DIR"
fi
git -C "$LIBAV_DIR" fetch --prune --tags
git -C "$LIBAV_DIR" checkout -f "$LIBAV_TAG"
git -C "$LIBAV_DIR" reset --hard "$LIBAV_TAG"
cd "$LIBAV_DIR"

# v1.19 forced dependency recipes to rerun and could re-apply patches to an
# already-patched tree. Recreate generated build artifacts from a clean state.
log "Cleaning generated libav.js build tree"
rm -rf "$LIBAV_DIR/build"

# Node 18 + Emscripten 3.1.55 match the upstream CI for this libav.js release.
# This tag does not ship package-lock.json, so npm ci cannot be used on a fresh
# checkout. Prefer npm ci only when a compatible lock file actually exists.
if [[ ! -d node_modules ]]; then
  if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
    npm ci --no-audit --no-fund
  else
    npm install --no-audit --no-fund
  fi
fi

log "Building local upstream obsolete + aac-af input runtimes"

OBSOLETE_CONFIG="$LIBAV_DIR/configs/configs/obsolete/ffmpeg-config.txt"
AAC_CONFIG="$LIBAV_DIR/configs/configs/aac-af/ffmpeg-config.txt"

[[ -s "$OBSOLETE_CONFIG" ]] || { echo "Missing obsolete config" >&2; exit 1; }
[[ -s "$AAC_CONFIG" ]] || { echo "Missing aac-af config" >&2; exit 1; }

grep -F -- "--enable-demuxer=mp3" "$OBSOLETE_CONFIG" >/dev/null || {
  echo "obsolete config does not enable MP3 demuxer" >&2; exit 1;
}
grep -F -- "--enable-decoder=mp3" "$OBSOLETE_CONFIG" >/dev/null || {
  echo "obsolete config does not enable MP3 decoder" >&2; exit 1;
}
grep -F -- "--enable-muxer=matroska" "$OBSOLETE_CONFIG" >/dev/null || {
  echo "obsolete config does not enable Matroska muxer" >&2; exit 1;
}

# The app uses asetnsamples to packetize resampled PCM into the exact
# frame size requested by libopus (normally 960 samples at 48 kHz).
# Some upstream obsolete configs omit this filter even though aresample exists.
if ! grep -F -- "--enable-filter=asetnsamples" "$OBSOLETE_CONFIG" >/dev/null; then
  echo "--enable-filter=asetnsamples" >> "$OBSOLETE_CONFIG"
fi
grep -F -- "--enable-filter=asetnsamples" "$OBSOLETE_CONFIG" >/dev/null || {
  echo "failed to enable asetnsamples filter" >&2; exit 1;
}

# Upstream mk/ffmpeg.mk makes the per-variant ffbuild/config.mak depend on
# this ffmpeg-config.txt, so normal make will reconfigure after the edit.

grep -F -- "--enable-demuxer=aac" "$AAC_CONFIG" >/dev/null || {
  echo "aac-af config does not enable AAC demuxer" >&2; exit 1;
}
grep -F -- "--enable-decoder=aac" "$AAC_CONFIG" >/dev/null || {
  echo "aac-af config does not enable AAC decoder" >&2; exit 1;
}

grep -F -- "--enable-encoder=aac" "$AAC_CONFIG" >/dev/null || {
  echo "aac-af config does not enable AAC encoder" >&2; exit 1;
}
grep -F -- "--enable-muxer=mp4" "$AAC_CONFIG" >/dev/null || {
  echo "aac-af config does not enable MP4 muxer" >&2; exit 1;
}
grep -F -- "--enable-muxer=matroska" "$AAC_CONFIG" >/dev/null || {
  echo "aac-af config does not enable Matroska muxer" >&2; exit 1;
}

# AAC decode path uses the same audio filter graph as MP3.
if ! grep -F -- "--enable-filter=asetnsamples" "$AAC_CONFIG" >/dev/null; then
  echo "--enable-filter=asetnsamples" >> "$AAC_CONFIG"
fi
grep -F -- "--enable-filter=asetnsamples" "$AAC_CONFIG" >/dev/null || {
  echo "failed to enable asetnsamples in aac-af" >&2; exit 1;
}


log "Downloading/extracting FFmpeg dependencies if needed"

# Resolve FFmpeg version from this libav.js release's root Makefile.
# v5.4.6.1.1 defines:
#   FFMPEG_VERSION_MAJOR=6
#   FFMPEG_VERSION_MINREV=1.1
FFMPEG_VERSION_MAJOR="$(
  sed -n 's/^[[:space:]]*FFMPEG_VERSION_MAJOR[[:space:]]*=[[:space:]]*//p' \
    "$LIBAV_DIR/Makefile" | head -n1 | tr -d '\r'
)"
FFMPEG_VERSION_MINREV="$(
  sed -n 's/^[[:space:]]*FFMPEG_VERSION_MINREV[[:space:]]*=[[:space:]]*//p' \
    "$LIBAV_DIR/Makefile" | head -n1 | tr -d '\r'
)"

if [[ -z "$FFMPEG_VERSION_MAJOR" || -z "$FFMPEG_VERSION_MINREV" ]]; then
  echo "Could not determine FFmpeg version from $LIBAV_DIR/Makefile" >&2
  exit 1
fi

FFMPEG_VERSION="${FFMPEG_VERSION_MAJOR}.${FFMPEG_VERSION_MINREV}"
echo "FFmpeg version: $FFMPEG_VERSION"

# Robust FFmpeg source prefetch.
# Upstream make downloads:
#   https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
# A transient TLS/reset there used to abort the whole build.
FFMPEG_TARBALL="$LIBAV_DIR/build/ffmpeg-${FFMPEG_VERSION}.tar.xz"
mkdir -p "$LIBAV_DIR/build"

if [[ ! -s "$FFMPEG_TARBALL" ]]; then
  TMP_XZ="$FFMPEG_TARBALL.part"
  rm -f "$TMP_XZ"

  log "Fetching FFmpeg ${FFMPEG_VERSION} from ffmpeg.org (with retries)"
  if curl -fL \
      --retry 6 \
      --retry-delay 3 \
      --retry-all-errors \
      --connect-timeout 20 \
      --max-time 900 \
      "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
      -o "$TMP_XZ"; then
    mv "$TMP_XZ" "$FFMPEG_TARBALL"
  else
    rm -f "$TMP_XZ"
    log "ffmpeg.org failed; falling back to GitHub tag n${FFMPEG_VERSION}"

    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    GITHUB_TGZ="$TMP_DIR/ffmpeg.tar.gz"
    curl -fL \
      --retry 6 \
      --retry-delay 3 \
      --retry-all-errors \
      --connect-timeout 20 \
      --max-time 900 \
      "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz" \
      -o "$GITHUB_TGZ"

    tar -xzf "$GITHUB_TGZ" -C "$TMP_DIR"
    GITHUB_DIR="$TMP_DIR/FFmpeg-n${FFMPEG_VERSION}"
    [[ -d "$GITHUB_DIR" ]] || {
      echo "GitHub FFmpeg archive did not contain expected directory: $GITHUB_DIR" >&2
      exit 1
    }

    mv "$GITHUB_DIR" "$TMP_DIR/ffmpeg-${FFMPEG_VERSION}"
    (
      cd "$TMP_DIR"
      tar -cJf "$TMP_XZ" "ffmpeg-${FFMPEG_VERSION}"
    )
    mv "$TMP_XZ" "$FFMPEG_TARBALL"
    rm -rf "$TMP_DIR"
    trap - EXIT
  fi
fi

[[ -s "$FFMPEG_TARBALL" ]] || {
  echo "FFmpeg source archive is missing after download attempts." >&2
  exit 1
}

make extract

JOBS="$(nproc 2>/dev/null || echo 2)"
log "Building local obsolete runtime with asetnsamples"
rm -f   "dist/libav-${LIBAV_VERSION}-obsolete.js"   "dist/libav-${LIBAV_VERSION}-obsolete.wasm.js"   "dist/libav-${LIBAV_VERSION}-obsolete.wasm.wasm"
make -j"$JOBS" "dist/libav-${LIBAV_VERSION}-obsolete.js"

log "Building local aac-af runtime with asetnsamples"
rm -f   "dist/libav-${LIBAV_VERSION}-aac-af.js"   "dist/libav-${LIBAV_VERSION}-aac-af.wasm.js"   "dist/libav-${LIBAV_VERSION}-aac-af.wasm.wasm"
make -j"$JOBS" "dist/libav-${LIBAV_VERSION}-aac-af.js"

OBSOLETE_FRONT="$LIBAV_DIR/dist/libav-${LIBAV_VERSION}-obsolete.js"
OBSOLETE_FACTORY="$LIBAV_DIR/dist/libav-${LIBAV_VERSION}-obsolete.wasm.js"
OBSOLETE_WASM="$LIBAV_DIR/dist/libav-${LIBAV_VERSION}-obsolete.wasm.wasm"

AAC_FRONT="$LIBAV_DIR/dist/libav-${LIBAV_VERSION}-aac-af.js"
AAC_FACTORY="$LIBAV_DIR/dist/libav-${LIBAV_VERSION}-aac-af.wasm.js"
AAC_WASM="$LIBAV_DIR/dist/libav-${LIBAV_VERSION}-aac-af.wasm.wasm"

for f in \
  "$OBSOLETE_FRONT" "$OBSOLETE_FACTORY" "$OBSOLETE_WASM" \
  "$AAC_FRONT" "$AAC_FACTORY" "$AAC_WASM"
do
  [[ -s "$f" ]] || { echo "Missing local build output: $f" >&2; exit 1; }
done

log "Fetching output/mux and WebCodecs bridge packages from npm"
rm -rf "$NPM_DEPS"
mkdir -p "$NPM_DEPS/webcodecs" "$NPM_DEPS/bridge"
cd "$NPM_DEPS"
WEB_PKG="$(npm pack --silent @libav.js/variant-webcodecs@6.10.9 | tail -n 1)"
BRIDGE_PKG="$(npm pack --silent libavjs-webcodecs-bridge@0.3.2 | tail -n 1)"
tar -xzf "$WEB_PKG" -C webcodecs --strip-components=1
tar -xzf "$BRIDGE_PKG" -C bridge --strip-components=1

OUTPUT_FRONT="$NPM_DEPS/webcodecs/dist/libav-6.10.9.0-webcodecs.js"
OUTPUT_FACTORY="$NPM_DEPS/webcodecs/dist/libav-6.10.9.0-webcodecs.wasm.js"
OUTPUT_WASM="$NPM_DEPS/webcodecs/dist/libav-6.10.9.0-webcodecs.wasm.wasm"
BRIDGE_JS="$NPM_DEPS/bridge/dist/libavjs-webcodecs-bridge.js"
for f in "$OUTPUT_FRONT" "$OUTPUT_FACTORY" "$OUTPUT_WASM" "$BRIDGE_JS"; do
  [[ -s "$f" ]] || { echo "Missing npm dependency output: $f" >&2; exit 1; }
done

log "Bundling everything into index.html (app v1.27)"
python3 "$PROJECT_DIR/scripts/bundle.py" \
  --template "$PROJECT_DIR/app-template.html" \
  --obsolete-front "$OBSOLETE_FRONT" \
  --obsolete-factory "$OBSOLETE_FACTORY" \
  --obsolete-wasm "$OBSOLETE_WASM" \
  --aac-front "$AAC_FRONT" \
  --aac-factory "$AAC_FACTORY" \
  --aac-wasm "$AAC_WASM" \
  --output-front "$OUTPUT_FRONT" \
  --output-factory "$OUTPUT_FACTORY" \
  --output-wasm "$OUTPUT_WASM" \
  --bridge "$BRIDGE_JS" \
  --out "$FINAL_HTML"

log "Writing build information"
{
  echo "libav.js dual-input offline build v1.27"
  echo "libav.js: $LIBAV_TAG"
  echo "Emscripten: $EMSDK_VERSION"
  echo "MP3/Opus/FLAC/WAV input: locally built upstream obsolete runtime"
  echo "AAC/ADTS/M4A input variant: aac-af"
  echo "local obsolete WASM bytes: $(stat -c%s "$OBSOLETE_WASM")"
  echo "aac-af WASM bytes: $(stat -c%s "$AAC_WASM")"
  echo "Final HTML bytes: $(stat -c%s "$FINAL_HTML")"
  echo
  echo "IMPORTANT LICENSE NOTE"
  echo "libav.js/FFmpeg components are LGPL-licensed. If you distribute the compiled HTML,"
  echo "you must satisfy the applicable source-code/license obligations. The exact source"
  echo "checkout used by this build remains at: $LIBAV_DIR"
  echo "Upstream: https://github.com/Yahweasel/libav.js"
} > "$PROJECT_DIR/BUILD-INFO.txt"

log "Done"
echo "Final HTML: $FINAL_HTML"
echo "local obsolete WASM: $(du -h "$OBSOLETE_WASM" | awk '{print $1}')"
echo "aac-af WASM: $(du -h "$AAC_WASM" | awk '{print $1}')"
echo "Final HTML: $(du -h "$FINAL_HTML" | awk '{print $1}')"
