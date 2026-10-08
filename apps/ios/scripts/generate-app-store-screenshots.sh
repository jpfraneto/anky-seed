#!/bin/bash
#
# generate-app-store-screenshots.sh
#
# One command: build Anky, capture every canonical scene in every supported
# locale from a real iOS Simulator, compose the marketing frames, validate the
# files, and write a manifest.
#
#   ./scripts/generate-app-store-screenshots.sh
#   ./scripts/generate-app-store-screenshots.sh --locale es-MX
#   ./scripts/generate-app-store-screenshots.sh --scene archive
#   ./scripts/generate-app-store-screenshots.sh --skip-capture   # recompose only
#
# Nothing here is UI automation. The app stages each scene itself from a
# bundled fixture (see Anky/Support/Screenshot) and writes a signal file when
# the frame has settled; this script waits for that signal, then shoots.
#
set -euo pipefail

cd "$(dirname "$0")/.."
IOS_ROOT="$(pwd)"
OUT="$IOS_ROOT/AppStoreScreenshots"
DERIVED="$IOS_ROOT/build/screenshots"
SCHEME="Anky"
PROJECT="Anky.xcodeproj"
BUNDLE_ID="com.jpfraneto.Anky"
DEVICE_NAME="${ANKY_SCREENSHOT_DEVICE_NAME:-iPhone 16 Pro Max}"
HEADLINE_FONT="${ANKY_HEADLINE_FONT:-Noteworthy Bold}"
SCENES=(ritual simplicity reflection archive recording)
SIGNAL="anky-screenshot-signal.json"
READY_TIMEOUT=45

ONLY_LOCALE=""
ONLY_SCENE=""
SKIP_BUILD=0
SKIP_CAPTURE=0
KEEP_SIM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale) ONLY_LOCALE="$2"; shift 2 ;;
    --scene) ONLY_SCENE="$2"; shift 2 ;;   # one scene, or a comma-separated list
    --device) DEVICE_NAME="$2"; shift 2 ;;
    --font) HEADLINE_FONT="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-capture) SKIP_CAPTURE=1; shift ;;
    --keep-simulator) KEEP_SIM=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

step "Checking prerequisites"
[[ "$(uname -s)" == "Darwin" ]] || fail "This needs macOS — the iOS Simulator does not exist anywhere else."
command -v xcodebuild >/dev/null || fail "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"
command -v xcrun >/dev/null || fail "xcrun not found."
command -v ruby >/dev/null || fail "ruby not found (needed to assemble the fixtures)."
xcrun simctl help >/dev/null 2>&1 || fail "xcrun simctl is unavailable — check xcode-select -p."
echo "  $(sw_vers -productName) $(sw_vers -productVersion) · $(xcodebuild -version | head -1)"
echo "  developer dir: $(xcode-select -p)"

step "Assembling fixtures"
ruby "$IOS_ROOT/scripts/assemble-screenshot-fixtures.rb"
# The camera-bubble still is authored in AppStoreScreenshots/assets and mirrored
# into the asset catalog, so replacing one file is all it takes to change it.
cp "$OUT/assets/selfie-still.png" \
   "$IOS_ROOT/Anky/Assets.xcassets/ScreenshotSelfieStill.imageset/selfie-still.png"

LOCALE_CODES=$(ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))["locales"].each { |l| puts [l["appLocale"], l["appStoreLocale"], l["simulatorLanguage"], l["simulatorLocale"], l["keyboards"].join(",")].join("|") }' "$OUT/locales.json")

# ------------------------------------------------------------------ capture

if [[ $SKIP_CAPTURE -eq 0 ]]; then

  step "Selecting a simulator"
  UDID=$(xcrun simctl list devices available -j | ruby -rjson -e '
    data = JSON.parse(STDIN.read)["devices"]
    want = ARGV[0]
    match = data.flat_map { |runtime, list|
      next [] unless runtime.include?("iOS")
      list.select { |d| d["isAvailable"] && d["name"] == want }
    }.first
    print match ? match["udid"] : ""' "$DEVICE_NAME")

  if [[ -z "$UDID" ]]; then
    echo "  no \"$DEVICE_NAME\" found; creating one"
    RUNTIME=$(xcrun simctl list runtimes -j | ruby -rjson -e '
      rs = JSON.parse(STDIN.read)["runtimes"].select { |r| r["isAvailable"] && r["identifier"].include?("iOS") }
      print rs.max_by { |r| Gem::Version.new(r["version"]) }&.fetch("identifier").to_s')
    [[ -n "$RUNTIME" ]] || fail "No iOS simulator runtime is installed. Xcode ▸ Settings ▸ Components."
    UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_NAME" "$RUNTIME") \
      || fail "Could not create a \"$DEVICE_NAME\" simulator. Available device types: xcrun simctl list devicetypes"
  fi
  echo "  $DEVICE_NAME · $UDID"
  export ANKY_SCREENSHOT_DEVICE="$DEVICE_NAME"

  if [[ $SKIP_BUILD -eq 0 ]]; then
    step "Building $SCHEME (Debug, simulator)"
    xcodebuild build \
      -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
      -destination "id=$UDID" -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO \
      | grep -E '^(\*\*|error:|warning: .*(deprecated|unused))' || true
    [[ "${PIPESTATUS[0]}" -eq 0 ]] || fail "Build failed. Re-run without the filter to see why: xcodebuild build -project $PROJECT -scheme $SCHEME -destination \"id=$UDID\" -derivedDataPath $DERIVED"
  fi

  APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "$SCHEME.app" -type d | head -1)
  [[ -n "$APP" ]] || fail "No built $SCHEME.app under $DERIVED. Run without --skip-build."
  echo "  app: ${APP#$IOS_ROOT/}"

  boot_device() {
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || {
      xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
      xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
    }
  }

  # Scenes 01 and 02 are nothing without a keyboard, and the software keyboard
  # only appears when iOS believes no hardware keyboard is attached.
  #
  # `ConnectHardwareKeyboard` is a Simulator.app preference, stored per device
  # inside a DevicePreferences dictionary keyed by UDID and read when the app
  # takes ownership of the device. Two consequences, both learned the hard way:
  #
  #   * The top-level `ConnectHardwareKeyboard` key does nothing.
  #   * A purely headless `simctl boot` gives no keyboard either — nobody is
  #     around to honour the preference. Simulator.app has to run, with the
  #     preference already set to 0 before it opens the device.
  #
  # So the sequence is: quit Simulator.app, write the pref, open Simulator.app
  # onto this device. `defaults ... -dict-add` cannot reliably merge into a
  # nested dictionary, so the plist is read out as JSON, edited and imported.
  set_hardware_keyboard_off() {
    local plist="${TMPDIR:-/tmp}/anky-sim-prefs.plist"
    local json="${TMPDIR:-/tmp}/anky-sim-prefs.json"
    if defaults export com.apple.iphonesimulator "$plist" 2>/dev/null; then
      if plutil -convert json -o "$json" "$plist" 2>/dev/null; then
        ruby -rjson -e '
          path, udid = ARGV
          data = JSON.parse(File.read(path)) rescue {}
          data["DevicePreferences"] ||= {}
          data["DevicePreferences"][udid] ||= {}
          data["DevicePreferences"][udid]["ConnectHardwareKeyboard"] = false
          File.write(path, JSON.generate(data))
        ' "$json" "$UDID" 2>/dev/null \
          && plutil -convert xml1 -o "$plist" "$json" 2>/dev/null \
          && defaults import com.apple.iphonesimulator "$plist" 2>/dev/null
      fi
    fi
    # Belt and braces: the documented one-liner, in case the export path failed.
    defaults write com.apple.iphonesimulator DevicePreferences -dict-add "$UDID" \
      "{ConnectHardwareKeyboard = 0; }" 2>/dev/null || true
  }

  quit_simulator_app() {
    if pgrep -qx Simulator 2>/dev/null; then
      osascript -e 'quit app "Simulator"' >/dev/null 2>&1 || killall Simulator >/dev/null 2>&1 || true
      for _ in $(seq 1 20); do pgrep -qx Simulator 2>/dev/null || break; sleep 0.5; done
    fi
  }

  open_simulator_app() {
    open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
      if pgrep -qx Simulator 2>/dev/null; then break; fi
      sleep 0.5
    done
    boot_device
    sleep 2
  }

  # Last resort, and the thing a human would do: Simulator's own
  # I/O ▸ Keyboard ▸ Connect Hardware Keyboard toggle (⇧⌘K). Driving a menu
  # shortcut needs Accessibility permission for whatever is running this
  # script; without it osascript fails harmlessly and we fall through.
  toggle_hardware_keyboard_via_ui() {
    pgrep -qx Simulator 2>/dev/null || return 1
    osascript >/dev/null 2>&1 <<'APPLESCRIPT' || return 1
tell application "Simulator" to activate
delay 0.8
tell application "System Events" to keystroke "k" using {command down, shift down}
delay 0.8
APPLESCRIPT
    return 0
  }

  # Everything we can learn about why a keyboard did not appear, written where
  # it can be read later instead of scrolling past in a terminal.
  dump_keyboard_diagnostics() {
    local locale="$1" scene="$2" container="$3" out="$OUT/keyboard-diagnostics.txt"
    {
      echo "Anky screenshot pipeline — keyboard diagnostics"
      echo "generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      echo "failed on: $locale / $scene"
      echo "device:    $DEVICE_NAME  $UDID"
      echo
      echo "=== host ==="
      sw_vers; xcodebuild -version | head -2
      echo
      echo "=== Simulator.app running? ==="
      pgrep -lx Simulator || echo "not running"
      echo
      echo "=== com.apple.iphonesimulator DevicePreferences ==="
      defaults read com.apple.iphonesimulator DevicePreferences 2>&1 | head -80
      echo
      echo "=== booted devices ==="
      xcrun simctl list devices | grep -i booted || echo "(none booted)"
      echo
      echo "=== device global preferences ==="
      xcrun simctl spawn "$UDID" defaults read -g 2>&1 | head -40
      echo
      echo "=== app signal file ==="
      if [[ -n "$container" && -f "$container/Documents/$SIGNAL" ]]; then
        cat "$container/Documents/$SIGNAL"
      else
        echo "(no signal file)"
      fi
      echo
      echo "=== recent keyboard / Anky log ==="
      xcrun simctl spawn "$UDID" log show --last 90s --style compact \
        --predicate 'processImagePath CONTAINS "Anky" OR subsystem CONTAINS "keyboard"' 2>&1 \
        | tail -60 || echo "(log unavailable)"
    } > "$out" 2>&1
    xcrun simctl io "$UDID" screenshot --type png "$OUT/keyboard-diagnostic-frame.png" >/dev/null 2>&1 || true
    echo "  diagnostics written: AppStoreScreenshots/keyboard-diagnostics.txt" >&2
    echo "  frame at failure:    AppStoreScreenshots/keyboard-diagnostic-frame.png" >&2
  }

  wait_for_ready() {
    local scene="$1" deadline=$((SECONDS + READY_TIMEOUT)) container status
    while (( SECONDS < deadline )); do
      container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
      if [[ -n "$container" && -f "$container/Documents/$SIGNAL" ]]; then
        status=$(ruby -rjson -e 'j=JSON.parse(File.read(ARGV[0])); print "#{j["status"]}|#{j["reason"]}"' "$container/Documents/$SIGNAL" 2>/dev/null || true)
        case "$status" in
          ready*) return 0 ;;
          failed*) echo "     app reported: ${status#failed|}" >&2; return 1 ;;
        esac
      fi
      sleep 0.4
    done
    echo "     timed out after ${READY_TIMEOUT}s waiting for the $scene scene" >&2
    return 1
  }

  CAPTURE_FAILURES=0
  KEYBOARD_SCENES_SKIPPED=0
  while IFS='|' read -r APP_LOCALE STORE_LOCALE SIM_LANG SIM_LOCALE KEYBOARDS; do
    [[ -n "$APP_LOCALE" ]] || continue
    if [[ -n "$ONLY_LOCALE" && "$ONLY_LOCALE" != "$STORE_LOCALE" && "$ONLY_LOCALE" != "$APP_LOCALE" ]]; then continue; fi

    step "Capturing $STORE_LOCALE ($APP_LOCALE)"
    # The device language is set globally, not just per app, so the software
    # keyboard, the status bar and every system control match the locale.
    boot_device
    xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array "$SIM_LANG" >/dev/null 2>&1 || true
    xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string "$SIM_LOCALE" >/dev/null 2>&1 || true
    IFS=',' read -r -a KB <<< "$KEYBOARDS"
    xcrun simctl spawn "$UDID" defaults write -g AppleKeyboards -array "${KB[@]}" >/dev/null 2>&1 || true
    xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true >/dev/null 2>&1 || true
    # Quit, write the preference, reopen onto this device: the language change
    # needs the reboot and the keyboard needs Simulator.app to honour the pref.
    quit_simulator_app
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    set_hardware_keyboard_off
    open_simulator_app

    xcrun simctl install "$UDID" "$APP" >/dev/null
    # Apple's canonical marketing time, full bars, charged.
    xcrun simctl status_bar "$UDID" override \
      --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 \
      --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true

    mkdir -p "$OUT/raw/$STORE_LOCALE"
    for index in "${!SCENES[@]}"; do
      SCENE="${SCENES[$index]}"
      if [[ -n "$ONLY_SCENE" && ",$ONLY_SCENE," != *",$SCENE,"* ]]; then continue; fi
      NAME=$(printf '%02d-%s.png' "$((index + 1))" "$SCENE")

      attempt_scene() {
        xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
        CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
        if [[ -n "$CONTAINER" ]]; then rm -f "$CONTAINER/Documents/$SIGNAL"; fi

        xcrun simctl launch "$UDID" "$BUNDLE_ID" \
          -ANKY_SCREENSHOT_MODE YES \
          -ANKY_SCREENSHOT_SCENE "$SCENE" \
          -ANKY_SCREENSHOT_LOCALE "$APP_LOCALE" \
          -AppleLanguages "($SIM_LANG)" \
          -AppleLocale "$SIM_LOCALE" >/dev/null
        wait_for_ready "$SCENE"
      }

      if attempt_scene; then
        xcrun simctl io "$UDID" screenshot --type png "$OUT/raw/$STORE_LOCALE/$NAME" >/dev/null 2>&1
        echo "  ✓ $NAME"
      elif [[ "$SCENE" == "ritual" || "$SCENE" == "simplicity" ]] && toggle_hardware_keyboard_via_ui; then
        # The preference did not take. Ask Simulator to toggle the hardware
        # keyboard the way a person would, then try this scene once more.
        echo "     toggled Simulator's hardware keyboard; retrying" >&2
        if attempt_scene; then
          xcrun simctl io "$UDID" screenshot --type png "$OUT/raw/$STORE_LOCALE/$NAME" >/dev/null 2>&1
          echo "  ✓ $NAME (after keyboard toggle)"
        else
          echo "  ✗ $NAME" >&2
          CAPTURE_FAILURES=$((CAPTURE_FAILURES + 1))
          CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
          dump_keyboard_diagnostics "$STORE_LOCALE" "$SCENE" "$CONTAINER"
          KEYBOARD_SCENES_SKIPPED=1
        fi
      else
        echo "  ✗ $NAME" >&2
        CAPTURE_FAILURES=$((CAPTURE_FAILURES + 1))
        if [[ "$SCENE" == "ritual" || "$SCENE" == "simplicity" ]]; then
          CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
          dump_keyboard_diagnostics "$STORE_LOCALE" "$SCENE" "$CONTAINER"
          KEYBOARD_SCENES_SKIPPED=1
        fi
      fi
    done
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  done <<< "$LOCALE_CODES"

  [[ $KEEP_SIM -eq 1 ]] || xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  if [[ $KEYBOARD_SCENES_SKIPPED -eq 1 ]]; then
    printf '\033[33m  note: the writing scenes (01, 02) were skipped — the simulator will not\n'
    printf '        raise a software keyboard. Known and parked; see AppStoreScreenshots/README.md.\n'
    printf '        Everything else below was captured normally.\033[0m\n'
  elif [[ $CAPTURE_FAILURES -ne 0 ]]; then
    fail "$CAPTURE_FAILURES scene(s) never reached a ready state — nothing was composed from a guess."
  fi
fi

# ------------------------------------------------------------------ compose

step "Composing marketing frames"
swift "$IOS_ROOT/scripts/screenshot-compose.swift" "$OUT" --font "$HEADLINE_FONT"

# ------------------------------------------------------------------- report

step "Done"
TOTAL=$(find "$OUT/final" -name '*.png' | wc -l | tr -d ' ')
echo "  $TOTAL upload-ready images"
echo "  final:        $OUT/final"
echo "  contact sheets: $OUT/contact"
echo "  manifest:     $OUT/manifest.json"
