#!/bin/bash
# Pre-submission gate: verify an Anky archive's merged Info.plist actually
# carries every key the sources promise, so the 1.2.1(46) regression (URL
# types, Live Activities, and usage strings silently dropped; MinimumOSVersion
# drifted to 17.0) can never ship unnoticed again.
#
# Usage:
#   scripts/verify-archive-plist.sh <path-to-.xcarchive-or-.app>
#
# Exit 0 = archive matches source truth; anything else = DO NOT UPLOAD.
set -u

IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: verify-archive-plist.sh <.xcarchive or .app>}"

if [[ "$TARGET" == *.xcarchive ]]; then
    APP="$TARGET/Products/Applications/Anky.app"
else
    APP="$TARGET"
fi
PLIST="$APP/Info.plist"
[ -f "$PLIST" ] || { echo "FAIL: no Info.plist at $PLIST"; exit 1; }

# Source truth, read live so the check never drifts from the project.
PBX="$IOS_ROOT/Anky.xcodeproj/project.pbxproj"
expected_version=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PBX" | head -1)
expected_build=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' "$PBX" | head -1)
expected_min_os=$(sed -n 's/.*IPHONEOS_DEPLOYMENT_TARGET = \([^;]*\);.*/\1/p' "$PBX" | head -1)

fail=0
check() { # key, expectation-description, python-expr over parsed plist dict `d`
    local key="$1" why="$2" expr="$3"
    python3 - "$PLIST" "$key" "$expr" <<'EOF'
import json, plistlib, sys
plist_path, key, expr = sys.argv[1], sys.argv[2], sys.argv[3]
with open(plist_path, 'rb') as f:
    d = plistlib.load(f)
v = d.get(key)
ok = eval(expr, {"v": v, "d": d})
print(("PASS" if ok else "FAIL") + f"  {key} = {v!r}")
sys.exit(0 if ok else 1)
EOF
    if [ $? -ne 0 ]; then
        echo "      ^ expected: $why"
        fail=1
    fi
}

echo "== $APP"
echo "-- identity"
check CFBundleShortVersionString "MARKETING_VERSION ($expected_version) from pbxproj" "v == '$expected_version'"
check CFBundleVersion "CURRENT_PROJECT_VERSION ($expected_build) from pbxproj" "v == '$expected_build'"
check MinimumOSVersion "IPHONEOS_DEPLOYMENT_TARGET ($expected_min_os) from pbxproj" "v == '$expected_min_os'"

echo "-- merged from Anky/Info.plist"
check CFBundleURLTypes "anky:// deep-link scheme (widget + quick action routing)" \
    "bool(v) and any('anky' in t.get('CFBundleURLSchemes', []) for t in v)"
check ITSAppUsesNonExemptEncryption "export compliance answered (False)" "v is False"

echo "-- merged from INFOPLIST_KEY_ build settings"
check NSSupportsLiveActivities "trial Live Activity" "v is True"
check NSCameraUsageDescription "camera usage string (selfie avatar) — missing = crash on use" "bool(v)"
check NSMicrophoneUsageDescription "microphone usage string (dictation) — missing = crash on use" "bool(v)"
check NSSpeechRecognitionUsageDescription "speech usage string (spoken check-in) — missing = crash on use" "bool(v)"
check NSPhotoLibraryUsageDescription "photo library usage string" "bool(v)"
check NSFaceIDUsageDescription "Face ID purpose string" "bool(v) and 'Face ID' in v"
check LSApplicationCategoryType "App Store category" "v == 'public.app-category.healthcare-fitness'"

if [[ "$TARGET" == *.xcarchive ]]; then
    echo "-- extension bundles (version lockstep)"
    while IFS= read -r -d '' ext_plist; do
        name=$(basename "$(dirname "$ext_plist")")
        python3 - "$ext_plist" "$expected_version" "$expected_build" <<'EOF'
import plistlib, sys
p, ver, build = sys.argv[1], sys.argv[2], sys.argv[3]
with open(p, 'rb') as f:
    d = plistlib.load(f)
ok = d.get('CFBundleShortVersionString') == ver and d.get('CFBundleVersion') == build
print(("PASS" if ok else "FAIL") + f"  {d.get('CFBundleIdentifier')} {d.get('CFBundleShortVersionString')}({d.get('CFBundleVersion')})")
sys.exit(0 if ok else 1)
EOF
        [ $? -ne 0 ] && fail=1
    done < <(find "$APP/PlugIns" -name Info.plist -maxdepth 2 -print0 2>/dev/null)
fi

echo
if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAIL — archive does not match source truth. Do not upload."
    exit 1
fi
echo "RESULT: PASS — archive Info.plist matches source truth."
