# ANKY: Walking Meditation — 2.3.0 (70)

Handoff for the evolution described in `EVOLUTIONARY_PROMPT.md`. Written 2026-10-27.

## 1. Audit (what was there before)

- **Live app 2.2.0 (69)** was "the simplest writing app": one writing page plus a drawer. The 2026-10-16 commit `a9b07f5` had removed RevenueCat, the paywall, the server client, AI reflections, and the ReplayKit recorder. Their code survived in git history, and the signer and purchase config were reused from it.
- **App Store Connect:** `anky.monthly` ($8.99 US, no intro offer) and `anky.annual` ($49.99, with a **3-day App Store free trial**) both exist, in group "Anky Pro". Both are **DEVELOPER_REMOVED_FROM_SALE**.
- **RevenueCat:** offering `default` → `$rc_monthly` = `anky.monthly`, `$rc_annual` = `anky.annual`. Entitlement `pro`.
- **Backend** (`mirror-production-a23c.up.railway.app`, healthy) verified RevenueCat server-side, but ran a *free* AI lane for non-subscribers.
- **Camera/"screen recorder":** this was ReplayKit screen recording with a selfie cutout, saved to the photo library. No files were kept by the app. It is retired. Sessions use native camera capture instead.
- **Livestream:** `livestream/` at the repo root is an OBS overlay. There was no phone-to-viewer pipeline.

## 2. What changed

| Area | Files |
| --- | --- |
| Access policy (pure, tested) | `Anky/Core/Access/AccessPolicy.swift`, `TrustedClock.swift` |
| Session model + store + export (pure, tested) | `Anky/Core/Session/*` |
| Signed server client | `Anky/Core/Server/*` |
| RevenueCat (monthly only) | `Anky/Purchases/SubscriptionService.swift` |
| Live access + paywall | `Anky/Features/Access/*` |
| Sessions UI, recorders, memories, AI sheet | `Anky/Features/Expression/*` |
| Integration | `GeshtuWorldView`, `GeshtuState`, `SessionDrawerView` (sessions in Recents, streaks removed), `WriteView` (ribbon slot, reopen gate), `WriteViewModel` (`lastSealReplacedHash`), `AnkySettingsView` (Subscription, Export my memories), `YouViewModel` (Delete All Data clears sessions), `AnkyApp` (launch refresh), `Info.plist` (mic, camera, background audio) |
| Backend (**uncommitted**, see §7) | `backend/access/*`, `backend/live/*`, `server.ts` (AI gate, free lane removed), `level/db.ts` migration, `account/routes.ts`, `debug/routes.ts`, tests, `ROUTE_AUTH_TABLE.md`, `README.md` |

### Rules as implemented

- **Free days** start at the first session (or a reopened writing). They last exactly 7×24h. The start is stored in the Keychain (device copy plus an iCloud-Keychain-synced copy) and in the server ledger. The earliest start wins, so a reinstall or a second device cannot reopen them.
- **Clock:** a monotonic high-water mark is kept in the Keychain. If the device clock is more than 10 minutes behind it while offline, the state is `unverified`: creating waits, memories stay open. A server answer anchors "now" through system uptime.
- **Subscription** is trusted offline for up to 7 days after the last RevenueCat verification. Past a known expiry with no re-check, the state is `unverified`, not "complete", because the subscription may have renewed.
- **Open-session boundary:** a session started while access was open may take new segments for up to 12 hours after access ends. The policy is only asked when something *starts*, so a recording is never cut off.
- **AI:** client requires a verified subscriber, and the server independently returns 402 before building any prompt.
- **Read/export:** always allowed, in every state.
- **Gate:** if free days end with no subscription, the shield's "Write" button opens the apps for the day instead of trapping the person.

### Storage

- `Documents/Sessions/<uuid>/session.json` holds the manifest (`anky.session`, version 1). It is written atomically, unknown kinds still decode, and a newer version is never rewritten.
- `Documents/Sessions/<uuid>/media/` holds `voice-*.m4a`, or `.caf` if a recording was interrupted, and `video-*.mov`.
- Writings stay at `Documents/Ankys/<sha256>.anky`, unchanged. Sessions reference them by hash. Historical writings are never wrapped into sessions or relabeled.

## 3. Verified

- `swift test`: 233 tests, 0 failures. New suites: AccessPolicy (17), TrustedClock (8), ExpressionSession (10), signing contract (3).
- `ANKY_LOCAL_BACKEND=http://localhost:8080 swift test --filter ServerContractIntegrationTests`: 3/3 pass against the new backend running locally. They cover the ledger opening once and never moving, a non-subscriber getting 402 for AI, and live returning "not configured".
- `xcodebuild test` (AnkyTests): succeeded.
- Backend: `bun test` 183/183 and `tsc` clean.
- Simulator (iPhone 16 Pro, Debug), driven with `axe`:
  - threshold, writing, the 8-second seal, and the ribbon;
  - recovery after the app was killed mid-session;
  - voice record, stop, CAF→m4a, manifest;
  - ending a session, the memory view, voice playback;
  - session export (a 154 KB zip with manifest, .anky, .txt, .m4a, README) through the share sheet;
  - the non-subscriber AI sheet;
  - the paywall showing the **live StoreKit price, $8.99/month**;
  - the expiry screen (`-ankyFreeAccessStartedDaysAgo 8`, Debug only), with memories still opening and playing after expiry.

## 4. Not verified

- **Camera video:** the simulator has no camera. Needs a real iPhone (permission, recording, interruption by a call, front/back switch, playback, export).
- **Background voice recording** with the screen locked, on a device.
- **Purchase, restore, cancellation, billing issue:** not exercised. Needs sandbox/TestFlight once `anky.monthly` is back on sale.
- **Deployed backend:** not deployed, so production does not have `/access/status` yet. The app degrades to the Keychain ledger, and the server ledger only takes effect after deploy.
- **Livestreaming:** not end to end, and **not offered in the UI.** See §6.

## 5. Migration and data-loss risks

- Existing writings are untouched and listed as standalone writings. Existing users get their 7 days starting at their first 2.3.0 session. They are not backdated.
- "Delete All Data" now also deletes sessions and media. It does not delete the free-access ledger, by design, and the UI says so.
- Deleting a session deletes its writings, voice, and video. A confirmation asks first and suggests export.
- An interrupted voice recording stays `.caf`, which is playable and exported as is.

## 6. Livestreaming: what exists and what's missing

Exists:
- Backend `GET /live/capabilities`, `POST /live/start|stop|report`, and admin `POST /debug/live/:id/end`, all on Cloudflare Stream Live Inputs and fully unit-tested with mocked Cloudflare.
- Client methods `liveAvailable`, `startLive`, `stopLive`.
- The session segment type `live`.

Missing, so "Go live" is **not shown**:
1. A Cloudflare Stream account: set `CLOUDFLARE_STREAM_ACCOUNT_ID`, `CLOUDFLARE_STREAM_API_TOKEN`, `CLOUDFLARE_STREAM_CUSTOMER_CODE`. Decide `CLOUDFLARE_STREAM_RECORDING_MODE`: the iframe viewer may need `automatic` for RTMPS playback.
2. An iOS broadcaster: an RTMPS encoder such as HaishinKit, or WHIP over WebRTC. It was not added because it could not be verified end to end here.
3. A viewer page with **Report** and **block** controls, plus moderation contact info, to meet App Review 1.2 for user-generated live content.
4. A verified real broadcast from an iPhone to a viewer before the UI entry is enabled.

## 7. Done after founder approval (2026-10-27)

- Backend committed (`f8b6049`) and **deployed** to Railway production. Health is OK, logs are clean, and the Swift contract tests pass **against production**: the ledger opens once and never moves, a non-subscriber gets 402 for AI, and live reports "not configured".
- `anky.monthly` is **back on sale** (state APPROVED, all 175 territories plus new ones). `anky.annual` stays removed from sale. There will be no annual plan.
- App Store **Billing Grace Period is on: 3 days, all renewals**, in production and sandbox. When a renewal fails, the person keeps access for 3 days while Apple retries. If payment recovers, the month still counts from the original renewal date, so those days are paid retroactively. RevenueCat keeps `pro` active during grace, and the paywall tells the person to update their payment method.
- Release 2.3.0 (70), development-signed, is installed and launches on the founder's iPhone 15. The Release binary passes the wallet/crypto `strings` scan.
- 6.9" screenshots are in `AppStoreScreenshots/walking/en-US/`.

## 8. Device QA

**Verified on the founder's iPhone 15** (2026-10-27) with the XCUITest `AnkyUITests/AnkyDeviceUITests`, run three times, all passing:
- Camera recording: permission, record, stop, then the memory shows "Video · 0:06" with a thumbnail and playback.
- Voice in the background: record, Home, 25 s, back, stop, then the memory shows "Voice · 0:29". This is the audio background mode a locked phone uses. XCUITest cannot press the lock button, so the lock itself is part of the manual check below.
- The test deletes its own session. After the runs, the Release build was reinstalled.

Re-run it with: `xcodebuild test -project Anky.xcodeproj -scheme Anky -destination id=<device> -only-testing:AnkyUITests -allowProvisioningUpdates`. This needs Settings › Developer › Enable UI Automation and an unlocked phone.

**Subscription on the device** (`AnkySandboxPurchaseUITests`, passing):
- The account on the founder's phone already holds `pro`. Settings shows "Subscribed", and Restore purchases answers "Your subscription is restored." A fresh purchase sheet could not be exercised without resetting the identity, which was not done.
- "Reflect with Anky" reached production as a verified subscriber (server log `statusCode=200`, `supported_reflection`). That exposed a **production blocker**: every AI credential on Railway is failing (Bankr 401, OpenRouter 401, Poiesis 530), so the server fell back to a placeholder text with HTTP 200, and the app saved it. Fixed in `5848f67` and deployed: the server now returns MIRROR_FAILED and the app refuses placeholders. On the device the person now sees "The reflection didn't come through. Nothing was saved or charged."
- **Resolved 2026-10-27:** the founder supplied an OpenRouter *management* key, which can't run models. With it I created a dedicated inference key, `anky-production` (OpenRouter, **$20/month cap**), and set it as `OPENROUTER_API_KEY` on Railway. The management key is not stored anywhere; it expires 2026-11-03, and the founder should rotate it since it appeared in chat. Short tiers moved from Gemini Flash Lite, which has no zero-retention endpoint, to Claude Haiku 4.5 (`ebd7158`). All tiers pass in production, and **a subscriber reflection came back on the founder's iPhone** ("You found the off switch is actually just a pair of shoes."). Bankr (401) and Poiesis (530) are still failing, so OpenRouter is the only working lane.
- (Historical) The founder must replace or fund the AI provider keys (`BANKR_LLM_GATEWAY_API_KEY`, `OPENROUTER_API_KEY`, `POIESIS_*`) on Railway before AI works for subscribers. Check with: `railway run bun <probe>`, or ask for a reflection.

### Upload

2.3.0 (70) was archived (the Release binary passes the wallet/crypto scan), exported and **uploaded to App Store Connect** on 2026-10-27 (delivery `9b549d68-caa1-48cb-af04-901a8f4da4c8`). It is not submitted for review.

### Still manual (needs a sandbox Apple ID)

1. **Camera, by hand:** switch to the front camera and record. During a take, receive a call: the take should stop cleanly and appear in the memory.
2. **Locked-screen voice:** Talk → record → lock the phone and walk for 2 minutes → unlock → stop. The memory's voice length should cover the whole time.
3. **Purchase (sandbox):** Settings › Subscription › Subscribe. Sign in with a sandbox tester. The confirmed price should match. Settings should then show "Subscribed", and "Reflect with Anky" should return a reflection.
4. **Restore:** delete and reinstall the app, then Restore purchases: the subscription should come back, and the free days should not restart.
5. **Cancel:** cancel in the sandbox subscription settings. After the accelerated period expires, new sessions should be locked and memories still open.

## 9. Next human actions

1. ~~Deploy backend~~ and ~~put monthly back on sale~~: done (§7).
2. Optionally remove `anky.annual`'s 3-day free-trial offer so it can never surface.
3. **Remaining device QA** (§8): sandbox purchase, restore, cancel, a real screen lock, a call during a take. Camera and background voice are verified.
4. ~~AI provider keys~~: fixed via OpenRouter (§8). Optionally repair or remove the Bankr and Poiesis lanes.
5. App Privacy answers in App Store Connect: see `APP_PRIVACY_ANSWERS.md`. That page can't be set through the API.
6. ~~Listing, screenshots, review notes, build~~: version 2.3.0 is prepared in App Store Connect (six-locale text, new en-US 6.9" screenshots, review notes, latest build attached). Remaining: enter App Privacy answers, then press **Submit for Review**.
7. ~~Terms liability cap~~: the founder kept the new cap. ~~Livestreaming~~: the founder deferred it (not now); §6 lists what it needs.
8. Decide whether to trim `PrivacyInfo.xcprivacy` collected data types to match `APP_PRIVACY_ANSWERS.md` (UserID and PurchaseHistory only).
9. ~~Release-archive wallet/crypto scan~~: clean for build 70.
10. Landing: `apps/landing/test/legalRoutes.test.ts` still fails one redirects check that predates this work. The legal pages update on the next landing deploy.
