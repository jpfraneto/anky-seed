# ANKY Android

Native Kotlin only. Do not use React Native or Expo.

Android follows the same product law as iOS:

- the `.anky` file is the canonical artifact
- writing is stored locally on the device
- reflections are stored locally on the device
- the mirror contract is exactly `POST /anky`
- the request body is the exact `.anky`
- the protocol fixtures in `protocol/fixtures` are shared test vectors

Do not share UI code with iOS. Share only product law, protocol law, fixtures, and the mirror API contract.

## Package IDs

- Release: `app.anky.mobile`
- Debug: `app.anky.mobile.debug`

Release signing and Google Play upload notes live in [PLAY_STORE_RELEASE.md](PLAY_STORE_RELEASE.md).

## Build

From `apps/android`:

```bash
./gradlew :app:test
./gradlew :app:assembleDebug
./gradlew :app:bundleRelease
```

Release signing reads only from uncommitted `local.properties` or environment variables. Do not commit keystores, passwords, RevenueCat secret keys, recovery phrases, or mirror secrets.

`bundleRelease` intentionally fails if release signing is not configured. See [PLAY_STORE_RELEASE.md](PLAY_STORE_RELEASE.md) for the required upload-key properties.

## Implemented Surfaces

- Write opens as the first tab, captures forward-only glyph input, saves an active local draft, appends terminal silence after 8 seconds, saves a canonical `.anky`, indexes it, and opens Reveal.
- Reveal loads the `.anky` file by hash, reconstructs text from protocol bytes, shows stats, supports copy actions, gates Ask Anky to complete sessions, signs exact bytes, and stores returned reflections locally.
- Map rebuilds from the local archive and reflection files, groups sessions by day, distinguishes complete sessions from fragments, and opens Reveal.
- You shows/copies the public key, gates recovery phrase reveal behind local authentication, exposes app lock, local daily reminders, mirror URL, archive export/share, free-credit copy, `$ANKY` info/contract copy, privacy text, and disabled RevenueCat purchase state unless Android products are configured.

## Local Storage

The app uses app-specific internal storage:

```text
filesDir/Anky/active-draft.anky
filesDir/Ankys/<sha256>.anky
filesDir/Anky/reflections/<sha256>.json
filesDir/Anky/session-index.json
filesDir/Anky/identity.enc
filesDir/Anky/identity.iv
```

Identity material is encrypted with an Android Keystore AES-GCM key and excluded from Android backup/device transfer rules.

## Known Gaps

- RevenueCat Android products and the Android public SDK key are not configured, so purchases are disabled honestly.
- Daily reminders use inexact local alarms and require Android notification permission on Android 13+.
- Instrumentation tests compile/package but require a connected device or emulator to execute.
