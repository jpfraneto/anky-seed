# Android Play Store Release

Release package name: `app.anky.mobile`

Debug builds use `app.anky.mobile.debug` so they can be installed beside the Play build.

This document is a release checklist for Google Play. It must not weaken Anky's product law: writing stays local by default, the mirror receives exact `.anky` bytes only after an explicit Ask Anky tap, and private identity material never leaves the device.

## Local Signing Inputs

Do not commit keystores, passwords, or `local.properties`.

Copy `apps/android/local.properties.example` to `apps/android/local.properties`, or set equivalent environment variables:

```properties
ANKY_ANDROID_KEYSTORE_FILE=/absolute/path/to/anky-upload-key.jks
ANKY_ANDROID_KEYSTORE_PASSWORD=...
ANKY_ANDROID_KEY_ALIAS=anky-upload
ANKY_ANDROID_KEY_PASSWORD=...
ANKY_ANDROID_VERSION_CODE=1
ANKY_ANDROID_VERSION_NAME=0.1.0
ANKY_REVENUECAT_ANDROID_PUBLIC_KEY=...
```

`ANKY_REVENUECAT_ANDROID_PUBLIC_KEY` is optional until Android RevenueCat products are configured. Never put RevenueCat secret keys in the app.

The release build reads only uncommitted local properties or environment variables. `.gitignore` excludes `local.properties`, `keystore.properties`, `*.jks`, and `*.keystore`.

## Versioning

- Release `applicationId`: `app.anky.mobile`.
- Debug `applicationId`: `app.anky.mobile.debug`.
- `versionCode` comes from `ANKY_ANDROID_VERSION_CODE`; increment it for every artifact uploaded to Play.
- `versionName` comes from `ANKY_ANDROID_VERSION_NAME`; keep it aligned with the release tag.
- Keep Play uploads below Play Console's `versionCode` maximum.
- Confirm values before release:

```bash
./gradlew :app:printReleaseSigningStatus
```

## Play App Signing

1. Enroll `app.anky.mobile` in Play App Signing.
2. Keep the Play app signing key managed by Google Play.
3. Use a local upload key for `bundleRelease`.
4. Store the upload keystore outside the repository.
5. If the upload key is lost, rotate it through Play Console rather than changing the application id.

Google Play uses Play App Signing to manage the app signing key and uses the developer upload key for App Bundle uploads. Android App Bundles uploaded to Play must be signed with the configured upload key.

## Build Commands

From `apps/android`:

```bash
./gradlew :app:printReleaseSigningStatus
./gradlew :app:test
./gradlew :app:assembleDebug
./gradlew :app:bundleRelease
```

The release bundle is written to:

```text
apps/android/app/build/outputs/bundle/release/app-release.aab
```

If signing properties are missing, `bundleRelease` fails before producing a release bundle. A Play upload must be signed with the configured upload key.

## Internal Testing

Use internal testing first for trusted testers and release smoke tests.

Checklist:

- Build a signed `.aab` with the upload key.
- Create an internal testing release in Play Console.
- Upload `app-release.aab`.
- Add tester Google accounts or a tester group.
- Verify install from the Play link on at least one physical Android device.
- Run a complete local write/reveal flow.
- Confirm no network request happens on app open or during writing.
- Confirm Ask Anky sends only after an explicit tap and only for a complete `.anky`.
- Confirm copy/export actions are explicit user actions.

Internal app sharing can be useful for quick artifact checks, but do not treat it as the production signing path. Internal app sharing artifacts may be re-signed by Google and are not the same gate as a track release.

## Closed Testing

Use closed testing before production or whenever account policy requires it.

Checklist:

- Create a closed testing track with a named tester list.
- Upload a signed `.aab` with a higher `versionCode` than prior Play uploads.
- Add release notes that mention only product-visible changes, not private implementation details.
- Keep the test focused on the Anky loop: Write locally, Reveal locally, Ask Anky explicitly, Map local archive, You privacy/export/settings.
- For newly created personal developer accounts, plan for Google's closed testing production-access requirements before launch.
- Collect tester feedback outside the app. Do not add analytics over writing content to satisfy test feedback.

## App Content Forms

Complete these Play Console sections before any non-internal release:

- Privacy policy URL: use the repository privacy policy or hosted equivalent.
- Data safety form.
- Content rating questionnaire.
- Target audience and content.
- Ads declaration: Anky currently has no ads.
- App access: no login account is required.
- Financial features/declarations: only configure if required by current Play Console prompts for purchases or token-related informational copy.

## Data Safety Draft

Answer from the actual shipped binary, not from intent. Current Android behavior:

- Raw `.anky` writing: stored locally in app-specific internal storage. Not collected by Anky unless the writer explicitly taps Ask Anky on a complete Anky.
- Mirror request body: exact `.anky` bytes are transmitted to the mirror only after explicit Ask Anky. The mirror contract is transient processing and no server-side journal.
- Reflections: stored locally on device. The mirror returns a reflection in the Ask Anky response; do not add analytics or crash breadcrumbs containing reflection text.
- Public key: used as writer identifier, mirror auth identity, and RevenueCat App User ID. It may be transmitted for mirror and credit flows.
- Recovery phrase/private key/seed: local only, Keystore-protected, never transmitted.
- Purchases/credits: Google Play and RevenueCat handle purchase and entitlement state when configured. Use only the Android public SDK key in the app.
- Notifications: local daily reminder only.
- Export/share: explicit user action through Android share sheet.
- Account deletion: Anky has no server account/login in this Android app. If future account creation is added, update Play's data deletion answers before release.

Security/privacy answers to preserve:

- Data is encrypted in transit for mirror/RevenueCat network calls.
- Sensitive identity material is encrypted at rest using Android Keystore-backed protection.
- No raw writing logs, prompts, model responses, or private reflections in app logs.
- No cloud journal, cloud sync, social feed, or server-side archive.

Google requires the Data safety form for apps on closed, open, or production tracks; internal-only testing is treated differently in the Play help docs. Re-check the form before promoting beyond internal testing.

## Content Rating Draft

Anky is a writing/ritual utility, not a social network, dating app, gambling app, medical app, or game.

Suggested questionnaire posture for the current app:

- User-generated content is local and private by default.
- The app does not publish writing publicly.
- The app does not include ads.
- The app does not include gambling, sexual content, graphic violence, drug instruction, or realistic violence as app-provided content.
- The mirror is optional and returns private text to the writer; do not characterize it as public content exchange.
- If future features add public sharing, social surfaces, feeds, or externally visible user content, redo the questionnaire before release.

Always answer the live Play Console questionnaire truthfully for the submitted binary; do not copy this draft blindly if the app changes.

## RevenueCat Android Product Setup

Current app behavior is intentionally disabled unless Android RevenueCat configuration exists.

Setup checklist:

- Create or confirm the Android app in RevenueCat with package name `app.anky.mobile`.
- Use the Android public SDK key as `ANKY_REVENUECAT_ANDROID_PUBLIC_KEY`.
- Never put a RevenueCat secret key in Android source, `local.properties`, or BuildConfig.
- Configure Google Play products for Android. Do not reuse iOS App Store product IDs unless RevenueCat/Play configuration explicitly maps them.
- Create products/packages/offerings in RevenueCat for Android credit packages.
- Connect RevenueCat to Google Play with the required Play Developer API/service-account setup in the RevenueCat dashboard.
- Use the writer public key as RevenueCat App User ID.
- Verify purchase and credit balance on an internal testing track before enabling purchase UI as active.
- Backend remains responsible for spending credits when `POST /anky` succeeds.

Known iOS product IDs are references only:

```text
inc.dev.anky.credits.22
inc.dev.anky.credits.88_bonus_11
inc.dev.anky.credits.333_bonus_88
```

## Privacy And Protocol Release Gate

Before every Play upload, verify:

- No React Native, Expo, Flutter, shared UI layer, cloud journal, or cloud sync was added.
- No backend call happens during writing or app open.
- Ask Anky sends `POST /anky` only after explicit user action.
- Request `Content-Type` is `text/plain; charset=utf-8`.
- Request body is exact `.anky` bytes, not JSON.
- Signature headers are present: `X-Anky-Public-Key`, `X-Anky-Signature`, `X-Anky-Request-Time`, `X-Anky-Client: android`.
- Hash/signature are computed over exact UTF-8 bytes.
- Fragments remain local/copy/export only and cannot Ask Anky.
- Raw `.anky`, reconstructed writing, prompts, reflections, recovery phrase, private key, and seed are not logged.
- Android backup/device transfer excludes identity ciphertext and IV files.

## Pre-Upload Checklist

- `applicationId` is `app.anky.mobile`.
- Debug build installs as `app.anky.mobile.debug`.
- `versionCode` is greater than every previously uploaded artifact.
- `versionName` matches the release tag.
- `./gradlew :app:test` passes.
- `./gradlew :app:bundleRelease` creates a signed `.aab`.
- `bundleRelease` was built with the Android RevenueCat public SDK key if purchases are enabled.
- No RevenueCat secret key, mirror secret, keystore, password, recovery phrase, or `.env` value is committed.
- Mirror endpoint remains `POST /anky` with `text/plain; charset=utf-8`.
- Android privacy copy still states that writing stays local unless the writer taps Ask Anky.
- Play Console data safety answers match the privacy covenant.

## References

- Google Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756
- Android app signing and upload keys: https://developer.android.com/guide/publishing/app-signing.html
- Google Play release tracks: https://support.google.com/googleplay/android-developer/answer/9859348
- Google Play internal/closed testing: https://support.google.com/googleplay/android-developer/answer/9845334
- Google Play Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Google Play content ratings: https://support.google.com/googleplay/android-developer/answer/9898843
- RevenueCat Android SDK: https://www.revenuecat.com/docs/getting-started/installation/android
- RevenueCat product configuration: https://www.revenuecat.com/docs/projects/configuring-products
