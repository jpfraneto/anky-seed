# ANKY iOS

Native SwiftUI only. No React Native, no Expo.

This is the current iOS loop:

```txt
Write -> local .anky -> seal crossroads (keep writing / reflection / leave) -> strata
```

## Root surface

The live root is the Geshtu world (`Anky/Features/Geshtu/GeshtuWorldView.swift`).
`geshtuWorldEnabled` is hardwired `true` in `Anky/AppRoot.swift`; the legacy
three-tab flow described below is the fallback branch of the router, not the
canonical surface. Writing stays on the device: the only upload is the
explicit reflection request at the crossroads, gated by the subscription.

## Legacy features (fallback route)

- Three native tabs: `Write`, `Map`, `You`.
- Write opens first as a full-screen ritual surface with no tab bar or navigation chrome, focuses the keyboard, and captures forward-only typing.
- Write shows the typed text at low opacity behind an 8-minute Ankyverse ring and a configurable 1-8 second stillness ring.
- Light haptics fire on each accepted key, stronger haptics mark each minute, and warning haptics begin after 5 seconds of silence.
- Paste, deletion, replacement, rich text, and newline input are blocked.
- The first accepted character starts the `.anky` session with epoch milliseconds.
- Later accepted characters store delta milliseconds.
- The configured stillness duration closes the active writing surface and stores the terminal millisecond marker (`8000` by default); completion is based only on accumulated writing deltas.
- Completed `.anky` files are saved as `<sha256>.anky`.
- Reveal shows the reconstructed writing as the primary surface, with date, time, duration, word count, hash, Copy text, and Copy `.anky`.
- Reveal includes the local ownership reminder: writing only leaves the device after an explicit reflection request and only after 8 minutes.
- Fragments show copy actions only.
- Complete ankys show `Ask Anky` when no local reflection exists.
- `Ask Anky` must send the exact `.anky` UTF-8 bytes to `POST /anky` with Base EIP-712 identity headers.
- Returned reflections are stored locally by `.anky` hash.
- Map shows the local trail by day, with today state, complete/fragment/reflection counts, previews, day detail, and Reveal navigation.
- You shows local Base account identity, recovery phrase reveal/copy/recover actions after local auth, Face ID app lock, daily local reminders, local export, support/contact, privacy, and RevenueCat-backed subscription status.

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

## Local Backend

The backend lives at `backend/` in the repository root (package
`@anky/backend`, one Bun/Hono server rooted in `backend/server.ts`). The old
`services/mirror` path no longer exists.

```sh
cd backend
bun install
ANKY_DEV_BYPASS_SUBSCRIPTION=true ANKY_DEV_MOCK_MIRROR=true bun run dev
```

The server listens on port `3000` by default. `POST /anky` is the reflection
route; the outwards pivot adds profiles/posts/moderation/blocks, web-login
(QR), `/subscriptions` (reader passes), and the SSR web reader routes — see
`backend/ROUTE_AUTH_TABLE.md`.

Health check:

```sh
curl http://127.0.0.1:3000/health
```

## Railway Mirror

Deployment notes live in `backend/README.md` and the root `railway.toml`.

Production variables:

```sh
ANKY_ENV=production
NODE_ENV=production
OPENROUTER_API_KEY=...
OPENROUTER_MODEL=...
OPENROUTER_PRIVACY_CONFIRMED=true
REVENUECAT_SECRET_KEY=...
REVENUECAT_PROJECT_ID=...
REVENUECAT_ENTITLEMENT_ID=pro
ANKY_MIRROR_DISABLED=false
ANKY_DEV_BYPASS_SUBSCRIPTION=false
ANKY_DEV_MOCK_MIRROR=false
```

Subscription product setup:

Use the production App Store bundle ID `com.jpfraneto.Anky`.

App Store Connect has one approved auto-renewable subscription, plus one
non-renewing purchase outside the group:

| Product ID | Plan | RevenueCat package |
| --- | --- | --- |
| `anky.annual` | Annual subscription | Annual package |
| `anky.pass` | Reader pass — $4.99, non-renewing, 30 days of one writer's subscriber pieces | Offering product (no `pro` entitlement; server mints the per-writer edge) |

RevenueCat dashboard setup:

- Entitlement: `pro`
- Offering: `default`
- Annual package product: `anky.annual`
- Public Apple SDK key in iOS source must be an `appl_...` key.
- App Store Server Notifications should point to RevenueCat.
- RevenueCat webhooks should point to Railway.

Verify a deployed mirror:

```sh
curl https://<railway-domain>/health
```

Current Railway status: `https://mirror-production-a23c.up.railway.app/health` is live. Production is configured with `ANKY_MIRROR_DISABLED=false`, so gated backend work should reach Railway; success still depends on a valid app signature, OpenRouter availability, and RevenueCat webhook-maintained `pro` entitlement state.

To verify current non-secret Railway state:

```sh
railway run --service mirror --environment production -- sh -c 'printf "ANKY_MIRROR_DISABLED=%s\nOPENROUTER_PRIVACY_CONFIRMED=%s\nREVENUECAT_ENTITLEMENT_ID=%s\n" "$ANKY_MIRROR_DISABLED" "$OPENROUTER_PRIVACY_CONFIRMED" "$REVENUECAT_ENTITLEMENT_ID"'
```

## Configure Mirror URL

In the iOS app, open `You` and set `Mirror base URL`.

- Default Railway mirror: `https://mirror-production-a23c.up.railway.app`
- iOS simulator talking to local mirror: `http://127.0.0.1:3000`
- Physical iPhone device testing should use the Railway/staging HTTPS mirror or an HTTPS tunnel to the local mirror. Plain `http://<your-mac-lan-ip>:3000` requires an explicit debug ATS exception before iOS will allow it.

Use the base URL only, not `/anky`; the app appends `/anky`.

## Test Ask Anky

1. Start the local mirror in dev mode with `ANKY_DEV_BYPASS_SUBSCRIPTION=true` and `ANKY_DEV_MOCK_MIRROR=true`.
2. In the app, write a complete 8-minute `.anky`.
3. Wait for silence close and Reveal.
4. Tap `Ask Anky`.
5. The mock reflection should appear and then persist locally for that hash.

Fragments intentionally do not show `Ask Anky`.

## Subscription QA

On a real iPhone with the RevenueCat dashboard and App Store Connect products configured:

1. Fresh install and confirm the app has a local Anky Base account.
2. Confirm RevenueCat configures under that writer identity, not an anonymous app user ID.
3. Open the subscription paywall and confirm RevenueCat returns offering `default`.
4. Confirm every purchase surface shows only annual product `anky.annual`.
5. Purchase the annual plan and confirm entitlement `pro` becomes active and the localized annual renewal disclosure is shown.
6. Confirm Restore Purchases restores `pro` on the same Apple ID.
7. Confirm the backend recognizes the subscription through RevenueCat webhooks; do not add raw Apple server-notification handling to the iOS app.

## Local Storage

- Active draft: Application Support, `Anky/active-draft.anky`
- Completed `.anky` files: Documents, `Ankys/<sha256>.anky`
- Reflections: Application Support, `Anky/reflections/<sha256>.json`
- Session index: Application Support, `Anky/session-index.json`
- First app open date: UserDefaults
- Identity recovery phrase/private key: local Keychain, with optional user-enabled iCloud Keychain recovery backup
- Mirror base URL: UserDefaults via `AppStorage`
- Daily reminder preference: UserDefaults plus local notification schedule

## Map

Map is local-only. It rebuilds a session index from local `.anky` files, joins local reflection metadata by hash, groups sessions by calendar day, and shows a small local Ankyverse position based on first app open date. It makes no server calls.

## You

You is the local control surface:

- Local Anky address/Base account status and copy action.
- 12-word recovery phrase generated on first app open, stored in Keychain, and revealable only after local auth.
- Optional biometric confirmation for sensitive identity settings.
- Local daily reminder scheduling with `UserNotifications`.
- Native export/share of individual `.anky` files and reflection JSON files.
- Support email composer with a pseudonymous support ID; the user controls the message and attachments sent.
- RevenueCat-backed subscription status and Restore Purchases.
- Privacy policy link to `https://anky.app/privacy-policy`.
- DEBUG-only mirror URL and destructive local reset tools.

## Tests

Run iOS Swift tests:

```sh
swift test --package-path apps/ios --scratch-path /tmp/anky-ios-swiftpm
```

The tests should cover parser/reconstruction/duration/hash, generated writer output, exact body hash, Base EOA identity derivation, EIP-712 signing, reflection store save/load, archive listing, Ask Anky eligibility, and subscription gating behavior.

## Privacy Guarantees

- No backend call happens merely because the writer is typing, revealing, copying, exporting, or browsing local history.
- A requested AI reflection or server nudge sends exact `.anky` bytes transiently. Personalized painting preparation after level 8 sends the relevant writing text transiently; writing-derived metadata and generated packages persist account-scoped for delivery.
- The app does not log raw `.anky`, reconstructed writing, or reflection text.
- Reflections are stored locally on device.
- Support email prefills only the pseudonymous support ID; the mail provider also receives the sender address and whatever content the user chooses to send.

## Known Limitations

- RevenueCat purchases require App Store Connect product `anky.annual`, entitlement `pro`, offering `default`, and Railway webhook handling to remain aligned with `Anky/Purchases/AnkyPurchasesConfig.swift` and `Anky/Purchases/PurchaseConstants.swift`.
- Subscription trials and introductory offers require real App Store Connect or StoreKit configuration. RevenueCat owns StoreKit purchases and restores in the app.
- No production OpenRouter tuning in iOS; local mirror dev mode is supported.
- iOS Base EOA signing is implemented with `web3swift`/`Web3Core` and fixture-tested against the shared Base EIP-712 protocol vectors.
- Face ID app lock is local and simple; it is not a full enterprise security boundary.
- There is no third-party analytics SDK. The backend stores whitelisted funnel events, safe service diagnostics, subscription state, level/session metadata, and personalized painting packages; optional encrypted iCloud backup is user-controlled.
- Export uses native sharing of individual local files, not a zip archive.

## Crypto Compatibility Note

The current mirror verifies Base EOA EIP-712 signatures. iOS must derive the same fixture account from the public BIP39 test mnemonic and sign the same `AnkyMirrorRequest` typed data before `Ask Anky` is considered compatible.

## Next Steps

- Add App Attest or a stronger attestation path if future backend abuse pressure warrants it.
- Improve export with a zip archive.
