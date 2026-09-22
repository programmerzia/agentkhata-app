#!/usr/bin/env bash
# Build a signed release APK for download from CoreBari, and print what the
# catalog's `android` block needs.
#
#   scripts/release-apk.sh [api-url] [update-feed-url]
#     api-url          default https://agentkhata.corebari.net
#     update-feed-url  default https://corebari.com/api/apps/agentkhata/android
#                      (where the APK is published, not where the API lives)
#
# Before running: raise `version:` in app/pubspec.yaml (the number after +
# must go up every release, or phones refuse the update).
set -euo pipefail
API="${1:-https://agentkhata.corebari.net}"
FEED="${2:-https://corebari.com/api/apps/agentkhata/android}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/sdk/flutter/bin:$PATH" JAVA_HOME="${JAVA_HOME:-$HOME/sdk/jdk17}" ANDROID_HOME="${ANDROID_HOME:-$HOME/sdk/android}"

KEYS="${AGENTKHATA_KEY_PROPERTIES:-$HOME/.android-keys/agentkhata-key.properties}"
[ -f "$KEYS" ] || { echo "No release key at $KEYS — refusing to build a debug-signed release." >&2; exit 1; }

VERSION="$(grep '^version:' "$ROOT/app/pubspec.yaml" | awk '{print $2}')"
NAME="${VERSION%%+*}"; CODE="${VERSION##*+}"

cd "$ROOT/app"
flutter build apk --release --dart-define=AGENTKHATA_API="$API" --dart-define=AGENTKHATA_UPDATES="$FEED"
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/agentkhata-$NAME.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"

SHA="$(sha256sum "$OUT" | awk '{print $1}')"
SIZE="$(stat -c %s "$OUT")"
cat <<INFO

Built $OUT
  versionName  $NAME
  versionCode  $CODE
  sha256       $SHA
  sizeBytes    $SIZE
  releasedAt   $(date +%F)

Next: upload the file to the downloads path on the server, then set these
values in the agentkhata entry's \`android\` block in corebari's catalog.
INFO
