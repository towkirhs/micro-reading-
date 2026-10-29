#!/usr/bin/env bash
# Generates the android/ folder (it is not committed) and adds notification
# support. Needs the Flutter SDK on PATH. Used by CI and for local builds.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

flutter create --no-pub --org dev.towkirhs --project-name micro_reader \
  --platforms=android "$tmp/app"
rm -rf android
cp -R "$tmp/app/android" android
python3 tools/patch_android.py

echo "android/ is ready. Next: flutter pub get && flutter build apk --release"
