# ANKY Android ← iOS Parity Goal

## Purpose

This goal exists because the Android app must not merely be a working Android shell. It must feel like the same Anky vessel as the native SwiftUI iOS app.

The task is to **photocopy the current Swift app into a native Android implementation** as closely as possible, while translating it into idiomatic Kotlin / Jetpack Compose.

This does **not** mean copying Swift code. It means preserving the complete product experience:

- visual language
- layout
- assets
- texture/background treatment
- typography
- spacing
- animation/transition feel
- copy
- screen structure
- user flows
- empty/loading/error states
- privacy posture
- ritual constraints
- local-first behavior
- `.anky` protocol behavior
- signed mirror request behavior
- credits behavior

The iOS app in `apps/ios` is the canonical product and design reference. The Android app in `apps/android` should become the Android-native translation of that app, not a generic Material Design reinterpretation.

---

## Source of Truth

Read these before modifying Android code:

1. `apps/ios`
   - Canonical implementation.
   - Treat this as the executable design/product spec.

2. `apps/ios/Anky.xcodeproj`
   - Confirms the production iOS app target and included assets/files.

3. `apps/ios/Package.swift` and tests
   - Protocol, identity, storage, signing, and implementation invariants.

4. `apps/ios/Anky/Features/Write`
   - Canonical writing ritual behavior.

5. `apps/ios/Anky/Features/Reveal`
   - Canonical reveal/reflection behavior.

6. `apps/ios/Anky/Features/Map`
   - Canonical local archive/map behavior.

7. `apps/ios/Anky/Features/You`
   - Canonical identity, privacy, export, recovery phrase, app lock, credits, and settings behavior.

8. `apps/ios/Anky/Assets.xcassets`
   - Canonical visual assets, app icon, images, textures, symbols, colors, and visual identity sources.

9. `protocol/SPEC.md`
   - Canonical `.anky` protocol law.

10. `services/mirror`
    - Canonical backend contract for Ask Anky.

11. Existing root/product/privacy/API docs
    - Preserve all product law, privacy law, and API contract decisions.

---

## Definition of “Photocopy”

For this goal, “photocopy” means:

### Must match iOS as closely as possible

- Same app surfaces.
- Same screen hierarchy.
- Same dark ritual mood.
- Same text/copy.
- Same assets/textures when available.
- Same colors and contrast.
- Same typography scale and hierarchy.
- Same spacing and layout relationships.
- Same button/card/surface treatment.
- Same empty/loading/error states.
- Same tab structure.
- Same Write ritual state.
- Same Reveal state logic.
- Same Map/archive presentation.
- Same You/settings/privacy posture.
- Same credits UI state.
- Same app lock and recovery phrase gates.

### Must remain Android-native

Use Kotlin and Jetpack Compose. Do not introduce React Native, Expo, WebView, Flutter, or a cross-platform UI layer.

Android may use platform-native behavior for:

- BiometricPrompt / device credential
- Android share sheet
- notification permissions/reminders
- keyboard/IME quirks
- Android accessibility semantics
- Android file/storage APIs

But platform-native behavior should support the Anky experience, not replace it with generic Android UI.

### Must not redesign

Do not make creative product/design decisions unless the Swift app has no answer and the gap is documented.

Avoid:

- generic Material default screens
- default blue/purple buttons
- default card-heavy settings pages
- new icons that do not exist in iOS
- new copy that changes tone
- redesigned onboarding
- redesigned Write ritual
- extra explanations or dashboards
- adding features to compensate for missing polish

The goal is not “make it nicer.” The goal is “make it the same.”

---

## Non-Negotiable Product Laws

Do not break these while working on parity.

1. **Writing is local-first.**
   - Writing stays on device during the writing ritual.
   - No network request during writing.
   - No analytics/logging of writing.

2. **`.anky` is canonical.**
   - Preserve exact `.anky` byte semantics.
   - Do not wrap protocol bytes in JSON.
   - Do not alter hash behavior.

3. **Ask Anky is explicit.**
   - The backend receives writing only when the user taps Ask Anky on an eligible complete session.
   - No background upload of writing.
   - No upload from Map, You, Reveal load, export, app open, credits refresh, or reminders.

4. **Privacy posture must remain intact.**
   - Do not log raw writing, `.anky` bodies, recovery phrases, private keys, seeds, reflections, or signatures.
   - Do not add analytics SDKs or crash reporters that capture private content.
   - Do not store plaintext server-side by accident.

5. **Identity must remain local.**
   - Recovery phrase / seed / private key material must be protected.
   - Public key may be visible/copyable as in iOS.
   - Recovery phrase reveal/copy must remain gated by local authentication.

6. **Mirror signing must remain compatible.**
   - Signed request must match backend expectations.
   - Android must sign exact `.anky` request bytes.
   - Headers must remain compatible with `services/mirror`.

7. **Credits remain RevenueCat-backed.**
   - Android public SDK key only in app config.
   - RevenueCat secret key stays server-side only.
   - Google service account JSON never goes into app, Git, or local app config.

8. **Google Play identity is fixed.**
   - Release `applicationId`: `app.anky.mobile`
   - Debug application id should remain installable separately, e.g. `app.anky.mobile.debug`.

---

## Required First Step: iOS Inventory

Before changing Android code, perform and document an iOS inventory.

Create or update:

```text
apps/android/IOS_PARITY_MAP.md
```

This file should include:

1. iOS screen inventory
   - screen name
   - source Swift files
   - Android equivalent files
   - parity status

2. iOS component inventory
   - reusable SwiftUI components
   - visual role
   - Android Compose equivalent
   - parity status

3. iOS asset inventory
   - source asset name/path
   - type: image, texture, icon, color, app icon, symbol, etc.
   - where used in iOS
   - Android destination resource
   - parity status

4. iOS copy inventory
   - key user-facing strings
   - Swift source location
   - Android string/equivalent location
   - parity status

5. Behavior inventory
   - Write behavior
   - Reveal behavior
   - Map behavior
   - You behavior
   - app lock
   - recovery phrase
   - export/share
   - reminders
   - credits
   - mirror request

Do not skip this and jump straight into Compose edits.

---

## Required Asset Migration

Migrate the actual iOS visual assets that are part of the current product identity.

Inspect:

```text
apps/ios/**/Assets.xcassets
apps/ios/**/*.png
apps/ios/**/*.jpg
apps/ios/**/*.jpeg
apps/ios/**/*.webp
apps/ios/**/*.svg
apps/ios/**/*.pdf
```

Also search Swift files for asset references:

```bash
rg 'Image\(|Color\(|\.background|\.overlay|asset|Assets|UIImage|NSImage|symbol|icon|texture|background' apps/ios
```

For every relevant iOS visual asset:

1. Copy it into the Android project.
2. Rename to Android-safe resource names:
   - lowercase
   - numbers allowed
   - underscores allowed
   - no spaces
   - no hyphens
   - no uppercase
3. Place it appropriately:
   - texture/background/raster artwork → `apps/android/app/src/main/res/drawable-nodpi`
   - simple vector/icon → `apps/android/app/src/main/res/drawable`
   - launcher icons → `mipmap-*` and adaptive icon resources as appropriate
4. Use it in Compose where the iOS app uses it.
5. Record mapping in `apps/android/IOS_PARITY_MAP.md`.

Do not approximate with gradients, generic icons, or Material defaults when an iOS asset exists.

If an iOS asset cannot be migrated cleanly, document:

- source path
- reason it cannot be migrated
- temporary Android fallback
- what is needed to close the gap

---

## Required Design System Port

Port the iOS product language into a small Android Compose design system.

Expected Android structure may include something like:

```text
apps/android/app/src/main/java/.../ui/theme/
  AnkyColors.kt
  AnkyTypography.kt
  AnkySpacing.kt
  AnkyShapes.kt
  AnkyTheme.kt

apps/android/app/src/main/java/.../ui/components/
  AnkyScreenBackground.kt
  AnkyGlassCard.kt
  AnkyButton.kt
  AnkyTabBar.kt
  AnkyHeader.kt
  AnkyGlyph.kt
  AnkyProgressRing.kt
  AnkyEmptyState.kt
```

Names may differ, but the design system must exist conceptually.

Port:

- dark background color(s)
- texture/background layering
- glass/card treatment
- button treatment
- pressed/disabled/loading states
- text hierarchy
- spacing rhythm
- corner radii
- borders/strokes
- subtle glows/shadows
- tab styling
- ritual surface treatment

Do not use default Material 3 styling as the visual identity. Material components may be used internally, but they must be wrapped/styled to look like Anky.

---

## Required Screen Parity

### App Root / Navigation

Android must match the iOS product shell.

Required:

- same primary tabs/surfaces as iOS
- same tab order
- same labels/copy
- same selected/unselected visual treatment
- same app lock startup behavior
- same initial screen behavior

Do not introduce onboarding/account setup unless iOS has it.

---

### Write

This is the most important screen.

The Android Write screen must match the iOS ritual as closely as possible.

Required:

- visual silence
- dark ritual background
- no generic text area visible while writing
- current glyph / current focus behavior matching iOS
- radial 8-minute progress treatment matching iOS
- terminal 8-second silence behavior
- no save button
- forward-only capture
- paste/backspace/replacement blocking
- hidden input behavior
- no network during writing
- same complete vs fragment logic
- same automatic Reveal transition after terminal silence
- same copy/tone/absence of copy as iOS

If Android IME behavior forces a platform-specific implementation, preserve the product outcome and document the difference.

Do not make Write look like a notes app.

---

### Reveal

Required parity:

- same layout hierarchy
- same background/texture treatment
- same status display for fragment vs complete
- same hash/duration/protocol metadata treatment
- same reconstructed text treatment
- same Ask Anky eligibility logic
- same reflection display logic
- same loading/error states
- same copy buttons
- same privacy reminder copy/tone
- same saved reflection behavior

Ask Anky must only be available when iOS would show it.

---

### Map

Required parity:

- same empty state
- same archive grouping logic
- same date/session row treatment
- same fragment vs complete visual states
- same saved reflection indicator
- same preview treatment
- same tap-to-Reveal behavior
- no server dependency
- same local-first feeling

Do not turn Map into a generic list screen.

---

### You

Required parity:

- same identity/public key display
- same app lock behavior
- same recovery phrase reveal/copy gates
- same export/share behavior
- same mirror base URL behavior if present
- same credits state and actions
- same privacy copy
- same settings hierarchy
- same disabled/unconfigured states
- same support/contact behavior

Do not expose recovery phrase or sensitive identity material without local authentication.

---

### Credits

Required parity with iOS and current Android readiness:

- RevenueCat Android public key from local/env config only.
- App User ID should be the local Anky public key.
- CRD balance should be loaded/displayed when configured.
- Purchase UI should use current offering/packages when configured.
- If RevenueCat Android is not configured, show a disabled/unavailable state that matches iOS tone.
- Do not include RevenueCat secret key.
- Do not include Google service account JSON.
- Do not fake credit balances.

---

### App Lock / Recovery Phrase

Required parity:

- app lock behavior should match iOS intent
- recovery phrase reveal gated by local auth
- recovery phrase copy gated by local auth
- canceling auth must not leak protected content
- protected content must not flash before lock

Use Android-native biometric/device credential UI, but preserve the iOS security posture.

---

## Required Copy Parity

User-facing copy should match iOS unless there is a platform-specific reason to differ.

Perform a copy inventory from Swift files:

```bash
rg 'Text\(|Button\(|Label\(|navigationTitle|alert|Alert|LocalizedString|String' apps/ios
```

Then compare with Android strings / Compose text.

Do not introduce clinical, corporate, generic, or overly explanatory language.

Anky’s tone should remain:

- quiet
- precise
- private
- ritual
- direct
- not therapeutic/medical
- not productivity-bro
- not social-network-like

---

## Required Interaction Parity

The Android implementation should match iOS behavior for:

- first launch
- identity creation/import if present
- app lock setup
- writing start
- writing continuation
- silence close
- draft restore
- complete vs fragment classification
- Reveal navigation
- Map navigation
- export/share
- reminder toggle
- credits refresh
- Ask Anky
- mirror error handling
- offline states

If Android differs due to platform constraints, document the difference in `apps/android/IOS_PARITY_MAP.md`.

---

## Required Visual QA

After implementation, capture Android screenshots on the emulator or device and compare them manually to iOS.

Minimum screenshots:

1. first launch / Write idle
2. Write active with current glyph
3. Reveal fragment
4. Reveal complete before reflection
5. Reveal with saved reflection
6. Map empty
7. Map with sessions
8. You main
9. recovery phrase gate
10. credits state
11. export/share entry point
12. app lock state

Add a section to `apps/android/IOS_PARITY_MAP.md`:

```text
Visual QA Screenshots
- screenshot name
- iOS reference
- Android screenshot path or notes
- status: pass / partial / fail
- notes
```

Do not claim visual parity without screenshots or a detailed manual comparison.

---

## Tests / Validation

Run feasible checks from `apps/android`:

```bash
./gradlew :app:test
./gradlew :app:assembleDebug
./gradlew :app:printReleaseSigningStatus
```

Run `bundleRelease` only if signing inputs are configured:

```bash
./gradlew :app:bundleRelease
```

If signing is absent and `bundleRelease` fails at signing, that is acceptable if release signing is intentionally gated.

Also inspect that no secrets were added:

```bash
git status --short
git diff --stat
git diff -- apps/android
```

Check that no forbidden files are tracked:

```bash
git status --short -- '*.jks' '*.keystore' 'local.properties' '*service-account*.json' '*credentials*.json'
```

If an emulator/device is available, follow:

```text
apps/android/ANDROID_DEVICE_QA.md
```

At minimum, manually validate:

- Write
- terminal silence
- Reveal
- Map
- You
- privacy/logcat
- mirror signing if possible

---

## Forbidden Changes

Do not:

- change `.anky` protocol semantics
- change backend mirror contract
- change request signing semantics
- send writing to server earlier than iOS
- log raw writing
- add analytics SDKs
- commit secrets
- commit keystores
- commit Google service account JSON
- commit `local.properties`
- change release `applicationId`
- replace iOS product language with generic Material defaults
- introduce new major product concepts
- change RevenueCat secret handling
- hide parity gaps in the final summary

---

## Expected Deliverables

By the end of this goal, the diff should include some or all of:

1. Migrated Android assets
   - `res/drawable-nodpi/*`
   - `res/drawable/*`
   - `res/mipmap-*/*`
   - adaptive icon resources if needed

2. Android design system updates
   - Anky-specific colors, typography, surfaces, buttons, tab treatment, backgrounds

3. Screen updates
   - Write
   - Reveal
   - Map
   - You
   - lock/recovery/credits states

4. Documentation
   - `apps/android/IOS_PARITY_MAP.md`
   - asset mapping and remaining gaps
   - screenshot QA notes if available

5. Validation output
   - commands run
   - pass/fail
   - remaining gaps

---

## Completion Criteria

This goal is complete only when:

1. Android visually resembles the Swift app screen-by-screen.
2. Actual iOS assets/textures used by the product have been migrated or explicitly documented as unavailable.
3. Android no longer looks like a generic Material scaffold.
4. The Write ritual feels like the iOS Write ritual.
5. Reveal, Map, and You preserve iOS hierarchy, tone, and behavior.
6. `.anky`, privacy, signing, storage, and RevenueCat invariants are unchanged.
7. `apps/android/IOS_PARITY_MAP.md` documents source-to-target parity.
8. Feasible Android tests/builds pass.
9. Remaining parity gaps are explicitly listed.

---

## Final Response Required From Codex

At the end, report:

1. Files changed.
2. Assets migrated:
   - iOS source path
   - Android resource path
   - where used
3. Screens updated.
4. Behavior preserved.
5. Tests/builds run and results.
6. Exact remaining parity gaps.
7. Any Android platform differences from iOS.
8. Confirmation that no secrets, keystores, `local.properties`, or service account JSON were committed.

Do not say “parity complete” unless the checklist above is honestly satisfied.
