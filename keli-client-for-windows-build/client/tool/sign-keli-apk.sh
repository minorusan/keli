#!/usr/bin/env bash
# Re-sign the freshly-built Keli release APK with a legacy v1 (JAR) signature alongside v2/v3.
#
# Why this exists: `flutter build apk --release` (AGP + build-tools 35) produces a v2-only APK once
# minSdk >= 24, and AGP ignores `enableV1Signing` on the Flutter debug signing config. HUAWEI/EMUI 8
# (e.g. the MediaPad M5 Lite, Android 8) then rejects the APK with "App not installed". apksigner only
# emits v1 when told a min-sdk < 24, so we re-sign here with --min-sdk-version 21.
#
# Run from keli/client AFTER `flutter build apk --release ...`, BEFORE the backend serves it.
set -euo pipefail

APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
KS="${ANDROID_DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"
APKSIGNER="$(ls "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/apksigner | sort -V | tail -1)"

[ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 1; }
[ -f "$KS" ] || { echo "debug keystore not found: $KS" >&2; exit 1; }

"$APKSIGNER" sign \
  --ks "$KS" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey \
  --min-sdk-version 21 \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  "$APK"

# Assert v1 is physically present (the EMUI fix); fail loudly if not.
if unzip -l "$APK" | grep -qiE 'META-INF/.*\.RSA'; then
  echo "✓ Keli APK re-signed with v1+v2(+v3): $APK"
else
  echo "✗ v1 (JAR) signature missing after re-sign — EMUI will reject it" >&2
  exit 1
fi
