# Android Device QA Runbook

This runbook validates the native Android app on a real device or emulator before release. It is a manual QA gate, not a feature spec. Do not add app behavior to make a check pass; record failures and fix the implementation separately.

## Scope

Validate the shipped Android surfaces against the current product and protocol laws:

- Writing starts local, stays local during input, and becomes a canonical `.anky` only after terminal silence.
- Recovery phrase and app lock flows are gated by local authentication.
- Reveal, Map, export/share, reminders, and mirror flows behave from explicit user actions.
- Mirror requests are signed `POST /anky` requests with exact `.anky` bytes.
- Logs do not expose writing, reflections, recovery phrases, private keys, seeds, or raw protocol bodies.
- Debug and release artifacts have distinct package identities and release signing/versioning is sane.

## Prerequisites

- Android Studio or Android SDK command-line tools.
- A physical Android device or emulator with Play Services if testing notification and biometric flows.
- USB debugging enabled, or an emulator visible in `adb devices`.
- Java 17 available.
- From this repository root, use `apps/android` for Gradle commands.
- For release checks, configure signing through uncommitted `apps/android/local.properties` or environment variables only.

Recommended device matrix:

- One current emulator or device on Android 14+.
- One Android 13+ device/emulator for notification permission behavior.
- One device with biometric or device credential enrolled for app lock and recovery phrase gates.

Record for every run:

```text
Date:
Tester:
Device model:
Android version:
Build type: debug / Play internal / release APK set
Git commit:
Version code/name:
Mirror base URL used:
```

## Build And Install

From `apps/android`:

```bash
./gradlew :app:test
./gradlew :app:assembleDebug
adb devices
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell pm list packages | grep 'app.anky.mobile'
```

Pass:

- Unit tests pass before device testing.
- Debug install succeeds.
- Installed debug package is `app.anky.mobile.debug`.
- If a Play/release build is already installed as `app.anky.mobile`, the debug build can remain installed beside it.

Fail:

- Debug replaces the release package.
- Debug package id is not suffixed with `.debug`.
- Build requires checked-in keystore or secret files.

To reset the debug app between test cases:

```bash
adb shell pm clear app.anky.mobile.debug
```

## Logcat Baseline

Start a clean log capture before each privacy-sensitive section:

```bash
adb logcat -c
adb logcat -v time > /tmp/anky-android-logcat.txt
```

Stop with `Ctrl-C`, then inspect:

```bash
rg -i 'recovery|phrase|seed|private|\\.anky|reflection|prompt|signature|hello|test writing text' /tmp/anky-android-logcat.txt
```

Pass:

- No recovery phrase, private key, seed, raw `.anky`, reconstructed writing, reflection text, prompt, or raw signature material appears in logs.
- Lifecycle/build logs are acceptable only if they do not contain private content.

Fail:

- Any user writing text, recovery phrase word, reflection text, raw `.anky` body, or private identity material appears in logcat.

## First Launch

1. Reset the app with `adb shell pm clear app.anky.mobile.debug`.
2. Launch from the home screen or:

   ```bash
   adb shell monkey -p app.anky.mobile.debug 1
   ```

3. Observe the first visible screen.
4. Open the `You` tab and note the accountId.
5. Stop and relaunch the app.

Pass:

- First visible app surface is `Write`.
- No login, cloud sync, analytics consent, or server account setup is required.
- `You` shows a stable accountId after relaunch.
- No recovery phrase is visible on first launch.
- No network call is observed on first launch if network inspection is enabled.

Fail:

- The app opens to a non-local onboarding/account flow.
- Recovery phrase appears without a local authentication action.
- Identity changes after a normal relaunch.

## App Lock

Use a device with biometric or device credential enrolled.

1. Open `You`.
2. Enable `App lock`.
3. Complete the system authentication prompt that appears after the setting is enabled.
4. Force-stop the app:

   ```bash
   adb shell am force-stop app.anky.mobile.debug
   ```

5. Relaunch the app.
6. Try canceling the authentication prompt.
7. Relaunch again and authenticate successfully.
8. Disable `App lock` from `You`.
9. Force-stop and relaunch.

Pass:

- Enabling app lock stores the setting and immediately presents the app lock authentication gate.
- On relaunch with app lock enabled, protected app surfaces are not usable before authentication succeeds.
- Canceling authentication keeps the app locked.
- Successful authentication unlocks the app.
- After disabling app lock, relaunch does not require authentication.

Fail:

- Write, Map, You, identity material, or archive content is accessible before successful unlock.
- App lock can be enabled without immediately presenting the authentication gate.
- Canceling the prompt still unlocks the app.

## Recovery Phrase Gates

1. Open `You`.
2. Tap `Reveal recovery phrase`.
3. Cancel the authentication prompt.
4. Tap `Reveal recovery phrase` again and authenticate.
5. Note that the phrase appears only after authentication.
6. Tap `Copy`.
7. Paste into a private scratch field outside the app only to confirm clipboard content, then delete it.

Pass:

- Reveal requires local authentication every time the phrase is not already displayed.
- Canceling reveal does not show the phrase.
- Copy is only available after the phrase has been revealed by local authentication.
- The phrase is not logged.

Fail:

- Phrase is visible or copied after a canceled authentication.
- Phrase appears in screenshots/logcat unintentionally during unrelated flows.

## Writing Input And IME Mutation

Use at least the default Android keyboard. If possible, repeat with Gboard and one OEM keyboard.

1. Reset the app.
2. Launch and focus the `Write` screen.
3. Type `a`, `b`, `c` slowly.
4. Observe the large glyph display after each key.
5. Verify no autocorrect strip or suggestion replaces previous input.
6. Type a space as a normal accepted glyph.
7. Type punctuation such as `.` and `!`.
8. Try newline/enter from hardware keyboard if available.

Pass:

- Each accepted single glyph appears one at a time.
- Space is accepted as a glyph.
- Punctuation is accepted as a glyph.
- Newline/enter is rejected.
- The input field remains visually hidden and does not accumulate visible text.
- No network call occurs during writing.

Fail:

- Autocorrect mutates prior text.
- Suggestions insert a word or multi-character replacement into the draft.
- Newline is accepted.
- Writing input is sent to a server before Ask Anky.

## Paste, Backspace, Replacement Blocking

Prepare clipboard content by copying a multi-word string from another app on the same device, such as `pasted text`.

Then:

1. Open `Write`.
2. Long-press or use keyboard shortcuts to paste the clipboard into the writing surface.
3. Press backspace/delete with software or hardware keyboard.
4. Select any suggestion chip or replacement candidate if the keyboard offers one.
5. Use `adb` to send a delete key as a hardware-key proxy:

   ```bash
   adb shell input keyevent KEYCODE_DEL
   ```

6. Continue by typing one normal single glyph.

Pass:

- Paste of multi-character text is rejected.
- Backspace/delete does not remove previously accepted glyphs from the draft.
- Replacement candidates do not change prior accepted glyphs.
- After rejected mutation attempts, normal single-glyph input still works.
- The app may show the closing/stay state, but draft content must remain forward-only.

Fail:

- Paste inserts multiple characters.
- Backspace removes or changes a prior glyph.
- Replacement/autocorrect rewrites the draft.
- Rejected mutation crashes or freezes input.

## Draft Restore

1. Reset the app.
2. Start writing several glyphs.
3. Before the 8-second terminal silence closes the session, press Home or force-stop quickly:

   ```bash
   adb shell am force-stop app.anky.mobile.debug
   ```

4. Relaunch immediately.
5. Continue typing a new single glyph before the remaining silence window ends.
6. Repeat the test, but relaunch and do not type.

Pass:

- Active draft survives process death/relaunch.
- Continuing before terminal silence appends to the same draft.
- If no new glyph is typed after restore, the restored draft closes after the remaining silence interval.
- No duplicate session appears in Map from a single restored draft.

Fail:

- Active draft is lost.
- Restored draft gets duplicated in Map.
- Restored draft never closes after silence.

## Terminal Silence Close

1. Reset the app and launch `Write`.
2. Type a short fragment such as `hello`.
3. Stop typing for at least 8 seconds.
4. Observe automatic navigation to `Reveal`.
5. Press `Back`, then open `Map`.

Pass:

- The app waits for terminal silence rather than requiring a save button.
- After approximately 8 seconds of silence, the draft is saved as a `.anky`.
- Reveal opens automatically.
- Reveal marks the short session as `Fragment`.
- Map shows one local session for the fragment.

Fail:

- Draft closes before silence.
- Draft never closes.
- Reveal cannot load the saved hash.
- Map does not show the saved session.

## Complete Ritual

This app treats a complete Anky as at least 8 minutes of ritual duration. Run this once per release candidate.

1. Reset the app.
2. Type naturally for at least 8 minutes.
3. Stop typing for at least 8 seconds.
4. Wait for `Reveal`.

Pass:

- Progress reaches completion without crashing or visible input accumulation.
- Reveal marks the session as `Complete Anky`.
- `Ask Anky` is visible only for the complete session and only if no reflection is already saved.
- Map later shows the session as `complete`.

Fail:

- Complete session is labeled as a fragment.
- Ask Anky appears for an incomplete fragment.
- Long writing causes excessive memory, UI, or battery issues.

## Reveal

Use one fragment and one complete session.

1. Open a saved session in `Reveal`.
2. Verify reconstructed text matches accepted glyphs.
3. Tap the floating `copy writing` control and paste into a private scratch field.
4. Open a saved reflection and scroll until the floating copy control switches to `copy reflection`; tap it and confirm the pasted text contains the reflection title plus body.
5. Confirm copied-state feedback appears briefly as `copied writing` or `copied reflection`.
6. Verify duration/hash/status are visible.
7. For the fragment, confirm the privacy reminder says fragments are local and cannot Ask Anky.
8. For the complete session before reflection, confirm the bottom floating `ask anky` prompt appears, tapping it scrolls to the inline Ask Anky action, and the inline badge says `8 free reflections included`.
9. For a saved reflection with local `creditsRemaining`, confirm `N reflection(s) left` appears under the reflection.
10. Tap the Reveal delete control, confirm the dialog says `delete forever?`, cancel once, then repeat and confirm deletion removes the local session from Reveal/Map.

Pass:

- Reconstructed text matches the intended accepted glyph sequence.
- Fragment Reveal has no Ask Anky button.
- Complete Reveal has Ask Anky only before a reflection exists.
- Copy actions are explicit user actions.
- Delete removes only local archive/reflection/index state and makes no network request.

Fail:

- Reconstruction differs from typed glyphs.
- Ask Anky is available for fragments.
- Copy controls copy writing/reflection without a user tap.
- Reveal deletion makes a network request or leaves the deleted session visible in Map.

## Map

1. Create at least two sessions on the same day: one fragment and one complete session.
2. Open `Map`.
3. Tap each session row.
4. Return to `Map` after each Reveal.
5. After a successful mirror response, revisit `Map`.

Pass:

- Empty archive initially says `No local ankys yet.`
- Sessions group under the correct local date.
- Rows distinguish `fragment` and `complete`.
- Preview text is local reconstructed text.
- Tapping a row opens the correct Reveal.
- Sessions with saved reflections show `saved reflection`.

Fail:

- Map depends on a server call.
- Rows open the wrong hash.
- Reflection state is not reflected after successful Ask Anky.

## Export And Share

1. Create at least one saved session.
2. Open `You`.
3. Tap `Export archive`.
4. Tap `Share export`.
5. In the Android share sheet, choose a local target you control.
6. Inspect the shared zip on a workstation if possible.

Pass:

- Export is initiated only from `You`.
- Share sheet opens through an explicit user action.
- Shared MIME is a zip archive.
- Archive contains local `.anky` files and local metadata/reflections when present.
- Export does not require network access or server permission.

Fail:

- Export starts automatically.
- Export requires a mirror/server call.
- Export omits saved local sessions.
- Export includes recovery phrase, private key, seed, or keystore material.

## Reminders

On Android 13+, notification permission may be required.

1. Open `You`.
2. Enable `Daily reminder`.
3. If the system asks for notification permission, grant it for the positive path.
4. Check scheduled alarm state:

   ```bash
   adb shell dumpsys alarm | rg -i 'anky|DailyReminder|app.anky.mobile'
   ```

5. Disable `Daily reminder`.
6. Check alarm state again.

Pass:

- Enabling the switch schedules a local reminder.
- Disabling the switch cancels the local reminder.
- Reminder setup does not create a server account or cloud schedule.
- On Android 13+, denied notification permission is recorded as a platform limitation, not a privacy failure.

Fail:

- Reminder scheduling contacts a server.
- Reminder remains scheduled after disabling.
- Notification permission denial crashes the app.

## Mirror Signing

Run this only with a complete session. Prefer a controlled HTTPS staging mirror or HTTPS tunnel that records method, path, headers, and exact request body. Android release builds should not rely on cleartext LAN HTTP; if a debug-only cleartext capture endpoint is used, configure the device/build explicitly and never persist raw writing in the capture logs.

1. Start a request capture endpoint reachable from the device.
2. In `You`, set `Mirror base URL` to the capture endpoint base URL and tap `Save mirror URL`.
3. Open a complete session in `Reveal`.
4. Tap `Ask Anky`.
5. Inspect the captured request.

Pass:

- No request is sent before `Ask Anky`.
- Request method is `POST`.
- Path is exactly `/anky`.
- `Content-Type` is `text/plain; charset=utf-8`.
- Body is exact `.anky` text bytes, not JSON or multipart.
- Headers include:
  - `X-Anky-Account`
  - `X-Anky-Signature`
  - `X-Anky-Request-Time`
  - `X-Anky-Client: android`
- Body SHA-256 matches the hash shown in Reveal.
- AccountId matches the `You` screen accountId.
- If the endpoint returns a mismatched hash, the app reports an error and does not save a reflection.

Fail:

- Any mirror request occurs during app open, writing, Reveal copy, Map browsing, export, or reminder changes.
- Request body is JSON-wrapped.
- Signature headers are missing.
- Fragment sessions can call Ask Anky.

## Privacy And Network Checks

Use one of these methods:

- Android Studio Network Inspector for debug builds.
- A trusted local capture endpoint for mirror checks.
- Device/emulator proxy to a local tool such as mitmproxy when certificate setup is appropriate.

Required negative checks:

- First launch: no app network call.
- Writing: no app network call.
- Terminal silence save: no app network call.
- Reveal load/copy: no app network call.
- Map browsing: no app network call.
- Export/share: no app network call except the user-selected share target outside Anky.
- Reminder toggle: no app network call.
- `Refresh credits` may touch RevenueCat only when Android RevenueCat is configured.
- `Ask Anky` may call the configured mirror only after explicit tap on a complete session.

Pass:

- Network behavior matches the explicit-action model above.
- Logcat remains free of private content after all flows.

Fail:

- Any background analytics, cloud sync, cloud journal, or writing upload appears.
- Private content is present in logs, crash output, or request metadata.

## Release Bundle Sanity

Use this gate before Play internal testing. Signing inputs must come from uncommitted `local.properties` or environment variables.

From `apps/android`:

```bash
./gradlew :app:printReleaseSigningStatus
./gradlew :app:test
./gradlew :app:bundleRelease
```

Expected bundle:

```text
apps/android/app/build/outputs/bundle/release/app-release.aab
```

Sanity checks:

```bash
ls -lh app/build/outputs/bundle/release/app-release.aab
jarsigner -verify -verbose -certs app/build/outputs/bundle/release/app-release.aab
git status --short -- local.properties '*.jks' '*.keystore' keystore.properties
```

If `bundletool` is available:

```bash
bundletool validate --bundle app/build/outputs/bundle/release/app-release.aab
bundletool dump manifest --bundle app/build/outputs/bundle/release/app-release.aab --xpath /manifest/@package
```

Pass:

- `bundleRelease` creates a signed `.aab`.
- Release application id is `app.anky.mobile`.
- Debug application id remains `app.anky.mobile.debug`.
- `versionCode` is greater than every previous Play upload.
- `versionName` matches the release tag.
- Signing status prints configured signing without exposing secrets.
- No keystore, password, `local.properties`, RevenueCat secret key, recovery phrase, or mirror secret is tracked by Git.

Fail:

- Release signing is missing for a Play candidate.
- Bundle uses the debug package id.
- Version code was not incremented.
- Any secret file is staged or committed.

## Known External Gaps

These are not device QA failures unless the submitted release claims they are complete:

- RevenueCat Android products and Android public SDK key are not configured in the current scaffold, so purchase UI remains disabled.
- Real purchase and credit-balance validation must happen on a Play internal testing track after RevenueCat and Google Play products are configured.
- Daily reminders use local inexact alarms and depend on platform notification permission behavior on Android 13+.
- Mirror success depends on a reachable mirror, valid signing, OpenRouter/backing service availability, and available credits.
- Device QA requires an actual connected device or emulator; Gradle instrumentation packaging alone is not proof of runtime behavior.
- Screen-by-screen iOS visual comparison is tracked in `IOS_PARITY_MAP.md`; Android-only screenshots are not enough to waive missing iOS references.

## Final QA Sign-Off

Do not sign off unless every applicable row is marked Pass or explicitly waived with an owner and reason.

```text
First launch:
App lock:
Recovery phrase gates:
Writing input / IME mutation:
Paste / backspace / replacement blocking:
Draft restore:
Terminal silence close:
Complete ritual:
Reveal:
Map:
Side-by-side iOS visual comparison:
Export / share:
Reminders:
Mirror signing:
Privacy / logcat:
Release bundle sanity:
Known external gaps documented:

Waivers:

Tester:
Date:
```
