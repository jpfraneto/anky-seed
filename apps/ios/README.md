# ANKY iOS

Native SwiftUI only. No React Native, no Expo.

This is the current iOS v0 loop:

```txt
Write -> local .anky -> Reveal -> optional signed Ask Anky -> local reflection -> Map
```

## Current Features

- Three native tabs: `Write`, `Map`, `You`.
- Write opens first as a full-screen ritual surface with no tab bar or navigation chrome, focuses the keyboard, and captures forward-only typing.
- Write shows the typed text at low opacity behind an 8-minute Ankyverse ring and an 8-second silence ring.
- Light haptics fire on each accepted key, stronger haptics mark each minute, and warning haptics begin after 5 seconds of silence.
- Paste, deletion, replacement, rich text, and newline input are blocked.
- The first accepted character starts the `.anky` session with epoch milliseconds.
- Later accepted characters store delta milliseconds.
- 8000ms of silence appends terminal `8000` and closes the ritual.
- Completed `.anky` files are saved as `<sha256>.anky`.
- Reveal shows the reconstructed writing as the primary surface, with date, time, duration, word count, hash, Copy text, and Copy `.anky`.
- Reveal includes the local ownership reminder: writing only leaves the device after an explicit reflection request and only after 8 minutes.
- Fragments show copy actions only.
- Complete ankys show `Ask Anky` when no local reflection exists.
- `Ask Anky` sends the exact `.anky` UTF-8 bytes to `POST /anky` with signature headers.
- Returned reflections are stored locally by `.anky` hash.
- Map shows the local trail by day, with today state, complete/fragment/reflection counts, previews, day detail, and Reveal navigation.
- You shows public key, recovery phrase reveal/copy after local auth, Face ID app lock, daily local reminders, local export, free-credit/WhatsApp contact, `$ANKY` CA copy, privacy, and RevenueCat-backed credits.

## Build And Run

Open the project in Xcode:

```sh
open apps/ios/Anky.xcodeproj
```

Select the `Anky` scheme and run on an iOS simulator or device.

Command-line build:

```sh
xcodebuild -project apps/ios/Anky.xcodeproj -scheme Anky -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/anky-ios-derived build
```

## Local Mirror

From the repository root:

```sh
cd services/mirror
ANKY_DEV_BYPASS_CREDITS=true ANKY_DEV_MOCK_MIRROR=true bun run dev
```

Or with the Makefile:

```sh
ANKY_DEV_BYPASS_CREDITS=true ANKY_DEV_MOCK_MIRROR=true make mirror-dev
```

The mirror listens on port `3000` by default and exposes `POST /anky`.

Health check:

```sh
curl http://127.0.0.1:3000/health
```

## Railway Mirror

Deployment notes live in `services/mirror/README.md` and `infra/railway/mirror.md`.

Production variables:

```sh
ANKY_ENV=production
NODE_ENV=production
OPENROUTER_API_KEY=...
OPENROUTER_MODEL=...
OPENROUTER_PRIVACY_CONFIRMED=true
REVENUECAT_SECRET_KEY=...
REVENUECAT_PROJECT_ID=...
REVENUECAT_CREDIT_CODE=CRD
ANKY_MIRROR_DISABLED=false
ANKY_DEV_BYPASS_CREDITS=false
ANKY_DEV_MOCK_MIRROR=false
```

Verify a deployed mirror:

```sh
curl https://<railway-domain>/health
```

Current Railway status: `https://mirror-production-a23c.up.railway.app/health` is live. Production is configured with `ANKY_MIRROR_DISABLED=false`, so `Ask Anky` should reach `POST /anky`; success still depends on a valid app signature, OpenRouter availability, and the writer having RevenueCat `CRD` credits.

To verify current non-secret Railway state:

```sh
railway run --service mirror --environment production -- sh -c 'printf "ANKY_MIRROR_DISABLED=%s\nOPENROUTER_PRIVACY_CONFIRMED=%s\nREVENUECAT_CREDIT_CODE=%s\n" "$ANKY_MIRROR_DISABLED" "$OPENROUTER_PRIVACY_CONFIRMED" "$REVENUECAT_CREDIT_CODE"'
```

## Configure Mirror URL

In the iOS app, open `You` and set `Mirror base URL`.

- Default Railway mirror: `https://mirror-production-a23c.up.railway.app`
- iOS simulator talking to local mirror: `http://127.0.0.1:3000`
- Physical iPhone talking to local mirror: `http://<your-mac-lan-ip>:3000`

Use the base URL only, not `/anky`; the app appends `/anky`.

## Test Ask Anky

1. Start the local mirror in dev mode with `ANKY_DEV_BYPASS_CREDITS=true` and `ANKY_DEV_MOCK_MIRROR=true`.
2. In the app, write a complete 8-minute `.anky`.
3. Wait for silence close and Reveal.
4. Tap `Ask Anky`.
5. The mock reflection should appear and then persist locally for that hash.

Fragments intentionally do not show `Ask Anky`.

## Local Storage

- Active draft: Application Support, `Anky/active-draft.anky`
- Completed `.anky` files: Documents, `Ankys/<sha256>.anky`
- Reflections: Application Support, `Anky/reflections/<sha256>.json`
- Session index: Application Support, `Anky/session-index.json`
- First app open date: UserDefaults
- Identity private key: Keychain, local device only
- Mirror base URL: UserDefaults via `AppStorage`
- Daily reminder preference: UserDefaults plus local notification schedule

## Map

Map is local-only. It rebuilds a session index from local `.anky` files, joins local reflection metadata by hash, groups sessions by calendar day, and shows a small local Ankyverse position based on first app open date. It makes no server calls.

## You

You is the local control surface:

- Identity public key and copy action.
- 12-word recovery phrase generated on first app open, stored in Keychain, and revealable only after local auth.
- Optional biometric confirmation for sensitive identity settings.
- Local daily reminder scheduling with `UserNotifications`.
- Native export/share of individual `.anky` files and reflection JSON files.
- Safe DM JP / WhatsApp message containing only public key, platform, and app version.
- WhatsApp opens JP directly at `+56 9 8549 1126`.
- RevenueCat-backed credit balance, credit packs, purchase buttons, and manual refresh.
- `$ANKY` contract address copy and link to `https://anky.app/ankycoin`.
- Privacy policy link to `https://anky.app/privacy-policy.md`.
- DEBUG-only mirror URL and destructive local reset tools.

## Tests

Run iOS Swift tests:

```sh
swift test --package-path apps/ios --scratch-path /tmp/anky-ios-swiftpm
```

The tests cover parser/reconstruction/duration/hash, generated writer output, canonical signing message, exact body hash, Ed25519 identity signing, reflection store save/load, archive listing, Ask Anky eligibility, and the safe free-credit message.

## Privacy Guarantees

- No backend call happens while writing, revealing, copying, exporting, or browsing Map.
- The server receives writing only when the writer taps `Ask Anky`.
- The request body is the exact `.anky` bytes, not JSON.
- The app does not log raw `.anky`, reconstructed writing, or reflection text.
- Reflections are stored locally on device.
- DM JP free-credit message includes only public key, platform, and app version.

## Known Limitations

- No Android implementation in this pass.
- RevenueCat purchases require the App Store Connect products, RevenueCat offering, and virtual currency grant rules to remain aligned with the product IDs in `RevenueCatCreditsClient.swift`.
- No production OpenRouter tuning in iOS; local mirror dev mode is supported.
- Recovery phrase identity is implemented with the BIP39 English word list and deterministic ANKY Ed25519 key derivation.
- Identity is Ed25519 with Solana-style base58 public key/signature, but not yet Solana BIP44 path compatible.
- Face ID app lock is local and simple; it is not a full enterprise security boundary.
- No cloud sync, database, analytics, Map geospatial view, or newline support.
- Export uses native sharing of individual local files, not a zip archive.

## Crypto Compatibility Note

The mirror verifies Ed25519 signatures with a 32-byte base58 public key and 64-byte base58 signature. iOS generates a local CryptoKit Ed25519 identity and signs the canonical `ANKY_POST_V1` message in that compatible shape.

The gap: this is recovery-phrase backed, but not yet Solana BIP44 path compatible. The phrase remains local in Keychain and is never sent.

## Next Steps

- Add seed phrase generation/recovery when identity UX is ready.
- Add RevenueCat-backed credits.
- Improve export with a zip archive.
- Wire shared protocol fixtures directly into Swift tests.
- Add Android after the iOS loop remains stable.
