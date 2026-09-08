#!/usr/bin/env bash
# Build a testable Android APK for this LÖVE port.
#
# Usage (from the repo root, or pass the repo path):
#   bash tools/make-apk.sh
#   bash tools/make-apk.sh /path/to/gen1recomp-dev
#
# Needs: zip, git, Java 11+, Android SDK (ANDROID_SDK_ROOT or ANDROID_HOME).
# First run clones love-android (~several hundred MB) and compiles native
# libs. Later runs only re-zip the game and rebuild the embed APK.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" != "" && -d "$1" ]]; then
  ROOT="$(cd "$1" && pwd)"
fi

APP_NAME="Pokemon Ruby"
APP_ID="com.gen1recomp.ruby"
VERSION_CODE="1"
VERSION_NAME="0.0.0-dev"
LOVE_ANDROID_REF="11.5a"
OUT_DIR="$ROOT/dist"
WORK="${LOVE_ANDROID_DIR:-$ROOT/.love-android}"
LOVE_ZIP="$OUT_DIR/ruby.love"
APK_OUT="$OUT_DIR/ruby-debug.apk"

die() { echo "error: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing $1"; }

need zip
need git

mkdir -p "$OUT_DIR"

GEN="$ROOT/assets/generated"
if [[ ! -d "$GEN/ui" && ! -d "$GEN/battle" ]]; then
  die "assets/generated is empty. Import the ROM on desktop first, then pack."
fi
echo "==> packing $LOVE_ZIP"
rm -f "$LOVE_ZIP"
(
  cd "$ROOT"
  zip -r -q "$LOVE_ZIP" main.lua conf.lua src assets data lib \
    -x "*.gba" -x "*.GBA" -x "no.gba" \
    -x "*.apk" -x "*.aab" -x "*.love" \
    -x ".DS_Store" -x "**/__pycache__/*" || true
  zip -r -q "$LOVE_ZIP" assets/generated
)

[[ -f "$LOVE_ZIP" ]] || die "failed to write $LOVE_ZIP"
echo "    $(du -h "$LOVE_ZIP" | cut -f1)  $LOVE_ZIP"

if [[ ! -x "$WORK/gradlew" ]]; then
  echo "==> cloning love-android ($LOVE_ANDROID_REF) into $WORK"
  rm -rf "$WORK"
  git clone --depth 1 --recurse-submodules --shallow-submodules \
    -b "$LOVE_ANDROID_REF" \
    https://github.com/love2d/love-android.git "$WORK"
fi

echo "==> embedding game.love"
mkdir -p "$WORK/app/src/embed/assets"
cp -f "$LOVE_ZIP" "$WORK/app/src/embed/assets/game.love"

PROPS="$WORK/gradle.properties"
if [[ -f "$PROPS" ]]; then
  # Wiki-style keys used by current love-android.
  if grep -q '^app.application_id=' "$PROPS" 2>/dev/null; then
    sed -i.bak \
      -e "s/^app.application_id=.*/app.application_id=$APP_ID/" \
      -e "s/^app.version_code=.*/app.version_code=$VERSION_CODE/" \
      -e "s/^app.version_name=.*/app.version_name=$VERSION_NAME/" \
      -e "s/^app.name=.*/app.name=$APP_NAME/" \
      -e "s/^app.orientation=.*/app.orientation=landscape/" \
      "$PROPS"
  fi
fi

if [[ -z "${ANDROID_SDK_ROOT:-}" && -n "${ANDROID_HOME:-}" ]]; then
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
fi
if [[ -z "${ANDROID_SDK_ROOT:-}" ]]; then
  for cand in \
    "$HOME/Android/Sdk" \
    "$HOME/Library/Android/sdk" \
    "/usr/lib/android-sdk"
  do
    if [[ -d "$cand" ]]; then export ANDROID_SDK_ROOT="$cand"; break; fi
  done
fi
[[ -n "${ANDROID_SDK_ROOT:-}" ]] || die "set ANDROID_SDK_ROOT to your Android SDK"

echo "==> gradle assembleEmbedNoRecordDebug"
cd "$WORK"
chmod +x gradlew
./gradlew --no-daemon assembleEmbedNoRecordDebug

APK="$(find "$WORK/app/build/outputs/apk" -name '*.apk' | head -n 1)"
[[ -n "$APK" ]] || die "gradle produced no apk"
cp -f "$APK" "$APK_OUT"
echo "==> $APK_OUT"
echo "install with:  adb install -r \"$APK_OUT\""
