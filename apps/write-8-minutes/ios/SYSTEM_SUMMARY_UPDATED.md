# Anky iOS Assessment

No files were modified during the assessment pass. This report reflects the current repo at `/Users/kithkui/anky/apps/write-8-minutes/ios`.

## 1. Current Architecture Overview

### Entry Point And Root Routing

| Component | Path | Current role |
|---|---|---|
| App entry | `Anky/AnkyApp.swift:5` | `@main` app launches `AppRoot()`. |
| App delegate | `Anky/AnkyApp.swift:16` | Sets `UNUserNotificationCenter` delegate and handles WBS notification taps. |
| Root shell | `Anky/AppRoot.swift:4` | Main routing, tabs, write surface state, WBS debug overlay, sealing flow, Face ID/iCloud prompts. |
| Main tab bar | `Anky/AppRoot.swift:1387` | Three visible tabs: Write, Map, You. |
| WBS spike VM | `Anky/AppRoot.swift:41` | `@StateObject private var writeBeforeScrollSpike = WriteBeforeScrollSpikeViewModel()`. |

`AppRoot` is currently the central orchestration point. It owns navigation, writing lifecycle, WBS unlock application, notification routing, sealing flow, profile/archive routes, Face ID lock, iCloud restore, and debug overlays. This makes it functional but overburdened.

Important routing behavior:

- App launch forces tab `0` and `.deepWrite`: `Anky/AppRoot.swift:419-444`.
- Scene active also forces writing unless sealing: `Anky/AppRoot.swift:447-458`.
- Pending WBS launch intents route into writing: `Anky/AppRoot.swift:124-153`.
- Sealed sessions go into a post-session sealing screen: `Anky/AppRoot.swift:156-166`.
- “Done” / gate completion currently routes to main screen via `finishSealingToMainScreen`: `Anky/AppRoot.swift:168-178`.
- “Go back to attempted app” applies unlock, then tries `UIApplication.shared.open(returnURL)`: `Anky/AppRoot.swift:193-203`.

### Main Screens

| Screen | Path | Notes |
|---|---|---|
| Writing screen | `Anky/Features/Write/WriteView.swift` | Current primary app surface. Forward-only text input, top pills, 8-second silence behavior. |
| Writing VM | `Anky/Features/Write/WriteViewModel.swift` | Session engine integration, draft persistence, WBS metrics, silence close, archive save. |
| Home chamber | `Anky/Features/CheckIn/HomeDailyChamberView.swift` | Old home/check-in dashboard still exists but app launch now bypasses it into writing. |
| Check-in flow | `Anky/Features/CheckIn/CheckInFlowView.swift` | Write/Talk/Image/Deep Write selection. Not aligned with WBS-first direction. |
| Map | `Anky/Features/Map/MapViewModel.swift` | Writing-day map, streak, total minutes, complete sessions. |
| Archive chamber | `Anky/Features/CheckIn/HomeDailyChamberView.swift:659` | Lists saved `.anky` sessions and reflections. |
| You/profile | `Anky/Features/You/YouViewModel.swift` | Account, export, backup, recovery, credits, stats. |
| Post-session sealing | `Anky/AppRoot.swift` | New ritual ending flow embedded inside `AppRoot`. |

### Core Stores / Services

| Component | Path | Notes |
|---|---|---|
| `.anky` writer | `Anky/Core/Protocol/AnkyWriter.swift` | Character-level protocol primitive. |
| WBS writing engine | `Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift` | Testable wrapper around `AnkyWriter`. |
| Local archive | `Anky/Core/Storage/LocalAnkyArchive.swift` | Saves `.anky` files in app Documents. |
| Active draft | `Anky/Core/Storage/ActiveDraftStore.swift:6` | Saves open draft to `Documents/ActiveDrafts`. |
| Session index | `Anky/Core/Storage/SessionIndexStore.swift` | JSON index of saved sessions. |
| Reflection store | `Anky/Core/Storage/ReflectionStore.swift:49` | Local JSON reflections in Application Support. |
| Mirror client | `Anky/Core/Mirror/MirrorClient.swift:6` | Remote reflection/nudge API client. |
| Notifications | `Anky/Core/Notifications/LocalNotificationScheduler.swift:4` | Daily reminder scheduler. WBS notification path is in shield action extension. |
| App group | `Anky/Core/WriteBeforeScroll/AppGroupStorage.swift` | Uses `group.com.jpfraneto.Anky`. |
| WBS unlock state | `Anky/Core/WriteBeforeScroll/UnlockStateStore.swift` | App Group persisted unlock/write-today state. |
| WBS event log | `Anky/Core/WriteBeforeScroll/WriteBeforeScrollEventLogStore.swift:60` | App Group local event log, max 300 events. |
| Screen Time selection | `Anky/Core/WriteBeforeScroll/ScreenTimeSelectionStore.swift` | Stores opaque FamilyActivitySelection in App Group. |
| Shield controller | `Anky/Core/WriteBeforeScroll/ScreenTimeShieldController.swift:7` | Applies/clears ManagedSettings shields. |
| Relock scheduler | `Anky/Core/WriteBeforeScroll/ScreenTimeUnlockScheduler.swift:6` | Uses DeviceActivity to schedule relock. |

### Entitlements

Entitlements are present:

- Main app: `Anky/Anky.entitlements:5-22`
  - `com.apple.developer.family-controls`
  - iCloud containers
  - App Group `group.com.jpfraneto.Anky`
- Shield action/configuration/monitor extensions each include Family Controls and the same App Group:
  - `AnkyWriteBeforeScrollShieldAction/AnkyWriteBeforeScrollShieldAction.entitlements:5-10`
  - `AnkyWriteBeforeScrollShieldConfiguration/AnkyWriteBeforeScrollShieldConfiguration.entitlements:5-10`
  - `AnkyWriteBeforeScrollMonitor/AnkyWriteBeforeScrollMonitor.entitlements:5-10`

## 2. Current Writing Experience

### Where The Writing Screen Lives

- UI: `Anky/Features/Write/WriteView.swift`
- State/session logic: `Anky/Features/Write/WriteViewModel.swift`
- Core engine: `Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift`
- Protocol primitive: `Anky/Core/Protocol/AnkyWriter.swift`

### How The Session Works

The writing view is currently a full-screen forward-only text surface. `WriteView` embeds `ForwardOnlyTextView` and binds accepted input to `WriteViewModel.accept`: `Anky/Features/Write/WriteView.swift:46-57`.

The session starts on first accepted character. The top pill state is:

- Before input: `just write`
- Started: `stop to unlock · 15 min`
- 88 seconds: `stop to unlock · 30 min`
- 8 minutes: `stop to unlock · rest of day`

See `Anky/Features/Write/WriteView.swift:165-244`.

The 8-minute mark does not end the session. It changes the unlock tier. The session ends only when the 8-second silence sentinel fires.

### 8-Second Inactivity Timeout

The canonical timeout is `AnkyDuration.terminalSilenceMs = 8000`: `Anky/Core/Protocol/AnkyDuration.swift:6`.

`WriteViewModel` tracks silence from `sessionEngine.lastAcceptedMs`:

- Live calculation: `Anky/Features/Write/WriteViewModel.swift:796-820`
- Close trigger: `Anky/Features/Write/WriteViewModel.swift:802-804`
- Seal call after silence: `Anky/Features/Write/WriteViewModel.swift:853-858`
- Sleep-based scheduled close: `Anky/Features/Write/WriteViewModel.swift:509-518`

The UI dims across silence using `silenceProgress`: `Anky/Features/Write/WriteView.swift:178-180`.

### Text Input Constraints

`ForwardOnlyTextView` is a `UITextView` wrapper: `Anky/Features/Write/WriteView.swift:729`.

Current behavior:

- Backspace/delete: rejected when replacement text is empty: `WriteView.swift:897-900`.
- Newline/return: rejected: `WriteView.swift:902-905`.
- Append at end: accepted: `WriteView.swift:907-910`.
- Editing before the current tail: rejected: `WriteView.swift:921-922`.
- Tail replacement/autocorrect: allowed only from last word boundary forward: `WriteView.swift:925-965`.
- Cursor is forced to end: `WriteView.swift:817-823`.
- Autocorrection is enabled: `WriteView.swift:752`.
- Spell checking is enabled: `WriteView.swift:754`.
- Autocapitalization is enabled: `WriteView.swift:753`.
- Paste is not globally disabled. A paste at the end is accepted as a multi-character append; a destructive paste before the tail is rejected unless it qualifies as tail replacement.

### Autocomplete / Swipe / Multi-Character Input

`WritingSessionEngine.accept` expands multi-character appended input into character-level `.anky` events: `Anky/Core/WriteBeforeScroll/WritingSessionEngine.swift:74-104`.

Synthetic timing is distributed from the previous append timestamp to the insertion timestamp: `WritingSessionEngine.swift:151-170`.

There are tests for this:

- Multi-character append reconstructs correctly: `Anky/Tests/WriteBeforeScrollTests.swift:29-45`
- Tiny batch append timing: `WriteBeforeScrollTests.swift:47-65`
- Multi-character append contributes to thresholds: `WriteBeforeScrollTests.swift:192-215`

Tail autocorrect is implemented by replacing the suffix in the underlying writer: `Anky/Core/Protocol/AnkyWriter.swift:65-96`.

### `.anky` Generation And Saving

`AnkyWriter` writes one character per line:

- First line: absolute epoch + character
- Later lines: delta + character
- Spaces are encoded as `SPACE`

See `Anky/Core/Protocol/AnkyWriter.swift:47-63` and `AnkyWriter.swift:110-112`.

Saved sessions go through `WriteViewModel.persistSealedSession`: `Anky/Features/Write/WriteViewModel.swift:861-878`, then `LocalAnkyArchive.save`.

Important red flag: `AnkyWriter` supports appending terminal silence `8000`: `Anky/Core/Protocol/AnkyWriter.swift:98-104`, and `WritingSessionEngine` exposes `closeWithTerminalSilence`: `WritingSessionEngine.swift:131-133`. But I did not see `WriteViewModel.sealAndSave` call `sessionEngine.closeWithTerminalSilence()` before saving. It sets `protocolText = sessionEngine.protocolText`: `WriteViewModel.swift:539`. That means sealed `.anky` files may not currently include the terminal `8000` sentinel even though the protocol supports it.

### After Completion

When 8000ms silence fires, `WriteViewModel.sealAndSave` saves the session and calls its completion handler: `WriteViewModel.swift:531-562`.

`AppRoot.revealOnMap` now routes to `.sealing`: `Anky/AppRoot.swift:156-166`.

The post-session flow is now a three-beat sealing sequence in `AppRoot`:

- Beat 1 seal/loading animation.
- Beat 2 reflection.
- Beat 3 gate/done/stay.

This is embedded in `AppRoot`, not isolated into its own feature module.

### Reflections

Reflections are remote-generated through `MirrorClient.askAnky`, which sends the `.anky` bytes to the backend: `Anky/Core/Mirror/MirrorClient.swift:15-31`, `MirrorClient.swift:125-151`.

Responses are stored locally as JSON via `ReflectionStore`: `Anky/Core/Storage/ReflectionStore.swift:49-67`.

So writing is local by default until reflection generation, export, or backup features are invoked.

## 3. Current Write Before Scroll / App Blocking State

### What Exists Today

There is a real WBS spike, not just stubs.

| Area | Current state |
|---|---|
| FamilyControls authorization | Implemented in debug VM: `WriteBeforeScrollSpikeViewModel.swift:96-109`. |
| App selection | Implemented with `FamilyActivityPicker` in debug panel: `WriteBeforeScrollDebugPanel.swift:85-96`. |
| Hardcoded X | Not possible through Apple APIs; documented in `SCREEN_TIME_SPIKE_NOTES.md:78`. |
| ManagedSettings shield | Implemented in `ScreenTimeShieldController.swift:21-68`. |
| Shield config UI | Implemented in `ShieldConfigurationExtension.swift:23-44`. |
| Shield action handling | Implemented in `ShieldActionExtension.swift:33-94`. |
| Notification fallback | Implemented in `ShieldActionExtension.swift:96-163`. |
| Direct open | Scaffolded, not active. |
| App Group bridge intent | Implemented in `WriteBeforeScrollLaunchBridgeStore.swift`. |
| Unlock state | Implemented in `UnlockStateStore.swift` and `WriteBeforeScrollScreenTimeStateStore.swift`. |
| Relock | Implemented via DeviceActivity: `ScreenTimeUnlockScheduler.swift:13-60` and monitor extension. |
| Local event logging | Implemented in `WriteBeforeScrollEventLogStore.swift:3-120`. |
| Debug panel | Implemented and visible in app: `WriteBeforeScrollDebugPanel.swift`. |

### Can It Actually Block Apps?

Yes, on a physical iPhone with Family Controls authorization and a selected app token, it should apply ManagedSettings shields.

The shield controller:

- Requires authorization approved: `ScreenTimeShieldController.swift:23`.
- Loads saved selection: `ScreenTimeShieldController.swift:36`.
- Applies app/category/domain shields: `ScreenTimeShieldController.swift:50-54`.
- Records state as active: `ScreenTimeShieldController.swift:56-66`.

This is not meaningful in simulator.

### Can It React When User Opens A Blocked App?

Yes. The shield configuration extension renders copy and logs `shield_rendered`: `ShieldConfigurationExtension.swift:23-44`.

The shield action extension handles primary/secondary button presses: `ShieldActionExtension.swift:33-45`.

Primary button:

1. Resolves bridge mode.
2. Saves pending launch intent.
3. Logs events.
4. Either attempts direct open or sends notification fallback.

See `ShieldActionExtension.swift:48-94`.

### Direct Open Vs Notification Fallback

Direct open is not currently active.

`WriteBeforeScrollLaunchBridgeModeResolver` intentionally returns `.notification` even on iOS 26.5 because the local SDK does not expose `ShieldActionResponse.openParentalControlsApp`. This is documented in:

- `Anky/Core/WriteBeforeScroll/WriteBeforeScrollLaunchBridgeModeResolver.swift`
- `AnkyWriteBeforeScrollShieldAction/ShieldActionExtension.swift:165-170`
- `SCREEN_TIME_SPIKE_NOTES.md:49-80`

The fallback notification path is implemented and debounced:

- Notification content: `ShieldActionExtension.swift:117-124`
- Immediate notification request: `ShieldActionExtension.swift:126-131`
- Mark sent/log scheduled: `ShieldActionExtension.swift:132-134`
- Debounce: `ShieldActionExtension.swift:101-112`

### Can It Unlock Apps After Writing?

Yes, partially.

`WriteViewModel` computes available grants and suppresses CTAs while apps are already unlocked:

- Grant calculation and offer check: `WriteViewModel.swift:623-632`
- Unlock tapped logging: `WriteViewModel.swift:142-153`

`AppRoot` applies the grant through the spike VM: `Anky/AppRoot.swift:117-122`.

The spike VM:

- Persists unlock in `UnlockStateStore`.
- Clears shield.
- Updates Screen Time state.
- Logs `unlock_granted`.
- Schedules relock.

See `WriteBeforeScrollSpikeViewModel.swift:138-162`.

### Unlock Ladder Correctness

Current ladder exists but has one major bug.

`UnlockPolicy` defines:

- Sentence: 15 minutes
- Presence: 30 minutes
- Presence threshold: 88 seconds
- Full anky: end of local day

See `UnlockPolicy.swift:40-43`, `UnlockPolicy.swift:51-77`.

But the sentence tier currently grants on `snapshot.hasUnlockableWriting`, meaning any non-whitespace character, not a completed sentence with a period: `UnlockPolicy.swift:68`.

There is even a test codifying this incorrect behavior: `Anky/Tests/WriteBeforeScrollTests.swift:79-89`.

`UnlockPolicy.hasCompletedSentence` exists and checks for a period with alphanumeric content before it: `UnlockPolicy.swift:79-85`, but it is not used by `grant`.

Same issue exists in metrics availability: `WriteBeforeScrollSessionMetrics.swift:142-146`.

### Production Readiness

The WBS loop is a working spike, not production-ready.

Fragile/incomplete areas:

- Debug panel is the setup surface.
- App selection is labeled “select X” but can select any apps/categories.
- Direct open is documented but not available in this SDK.
- Emergency unlock secondary button only closes shield and logs; it does not grant a managed unlock: `ShieldActionExtension.swift:40-42`.
- “Sentence” threshold is wrong.
- WBS routing is still coupled through `AppRoot`.
- Screen Time entitlement/App Store approval remains a distribution risk.
- Notification fallback depends on notification permission, Focus, and user tapping the notification.

## 4. Current Onboarding State

Onboarding exists at `Anky/Features/Onboarding/OnboardingView.swift`.

Current onboarding is three pages:

- “You don't need another place to perform.”
- “Anky gives you 8 minutes to let out what you're carrying.”
- “At the end, you see what was underneath.”

See `OnboardingView.swift:18-22`.

CTA copy:

- “Be with what is here”
- “Let it all out”
- “Write 8 minutes”

See `OnboardingView.swift:222-226`.

Onboarding state is stored in `@AppStorage("anky.onboardingCompleted")`: `Anky/AppRoot.swift:18`.

Current onboarding does not:

- Ask user to select distracting apps.
- Request Screen Time authorization.
- Request notification permission for fallback.
- Explain Write Before You Scroll.
- Teach the 15/30/day unlock ladder.
- Create a first successful writing gate.
- Connect clearly to the renewed thesis.

It is still the old 8-minute private writing/reflection onboarding.

## 5. Current Home / Archive / User State

### Current Tabs

Visible bottom tabs are:

- Write
- Map
- You

Defined in `Anky/AppRoot.swift:1390-1394`.

There are also internal selected tab routes for archive/reveal, but they are not visible tab bar items.

### Home

`HomeDailyChamberView` exists at `Anky/Features/CheckIn/HomeDailyChamberView.swift:3`.

It emphasizes:

- Greeting/hero.
- Weekly calendar.
- “Check in again.”
- Latest reflection.
- Portal row: Map, Archive, Deep Write.
- Privacy footer.

See `HomeDailyChamberView.swift:20-43`.

But current app launch now forces writing, so this old home is not the primary user experience on open: `Anky/AppRoot.swift:419-444`.

### Archive

Archive exists inside `HomeDailyChamberView.swift:659`.

It lists:

- Saved `.anky` files from `LocalAnkyArchive`: `HomeDailyChamberView.swift:663`.
- Reflections from `ReflectionStore`: `HomeDailyChamberView.swift:664`.
- Cards with preview, duration, title/reflection: `HomeDailyChamberView.swift:813-850`.

Archive supports browsing by date but not full search.

### Check-In Modes

`CheckInFlowView` supports:

- Write
- Talk
- Image
- Deep Write

See `Anky/Features/CheckIn/CheckInFlowView.swift:14-20` and `CheckInFlowView.swift:83-106`.

This is product debt relative to “now we ONLY write.” It still exists and should either be hidden or eventually removed/migrated.

### Map / Stats

`MapViewModel` tracks:

- Complete anky count.
- Total writing minutes.
- Current streak.
- Complete sessions.

See `Anky/Features/Map/MapViewModel.swift:10-13`, `MapViewModel.swift:54-59`.

These are writing-practice stats, not WBS stats. There are no mature protected-minutes, blocked-app attempts, gates completed, or “signal recovered” metrics yet.

## 6. Current Monetization / Subscription State

Monetization exists, but it is credit-pack based, not subscription/paywall based.

### RevenueCat

`RevenueCatCreditsClient` imports RevenueCat: `Anky/Features/You/RevenueCatCreditsClient.swift:2`.

It configures:

- API key: `RevenueCatCreditsClient.swift:22-24`
- Virtual currency code `CRD`: `RevenueCatCreditsClient.swift:24`
- Offering `Credits`: `RevenueCatCreditsClient.swift:25`
- Products:
  - `inc.anky.credits.3`
  - `inc.anky.credits.11`
  - `inc.anky.credits.33`

See `RevenueCatCreditsClient.swift:26-30`.

It supports:

- Identify customer: `RevenueCatCreditsClient.swift:41-71`
- Fetch balance: `RevenueCatCreditsClient.swift:73-77`
- Fetch packages: `RevenueCatCreditsClient.swift:79-104`
- Purchase credits: `RevenueCatCreditsClient.swift:106-127`

### StoreKit

`RevealView` imports StoreKit: `Anky/Features/Reveal/RevealView.swift:2`.

### Superwall

No Superwall import was found.

### Current Model

Current monetization appears tied to reflection credits, not access to WBS. `YouViewModel` owns credit balance/packages and RevenueCat client: `Anky/Features/You/YouViewModel.swift:20-24`, `YouViewModel.swift:39`.

A “paywall after first successful gate” would naturally fit after:

1. Shield opened.
2. User wrote.
3. Unlock was granted.
4. App returned to attempted app or main screen.

Implementation should avoid breaking existing RevenueCat app user IDs and credit balances.

## 7. Current Notification State

### Local Notifications

There are two local-notification systems:

1. Daily reminder scheduler:
   - `Anky/Core/Notifications/LocalNotificationScheduler.swift:4`
   - Requests alert/sound authorization: `LocalNotificationScheduler.swift:12-14`
   - Schedules “write your anky today”: `LocalNotificationScheduler.swift:16-33`

2. WBS shield fallback notification:
   - `AnkyWriteBeforeScrollShieldAction/ShieldActionExtension.swift:114-163`
   - Title: “Write before you scroll”
   - Body: “Tap to open Anky and write.”
   - `userInfo.route = "writeBeforeScroll"`

### Notification Taps

Handled in app delegate:

- Set delegate: `Anky/AnkyApp.swift:21`
- If route is `writeBeforeScroll`, logs event and posts local notification: `Anky/AnkyApp.swift:25-45`
- `AppRoot` receives it and routes to WBS writing: `Anky/AppRoot.swift:416-418`

### Push Notifications

No push notification system was found.

### Can It Tell The User “Tap Notification Or Tap Here If You Didn’t Get It”?

Yes, partially.

Shield copy supports notification fallback states through `WriteBeforeScrollLaunchBridgeStore.copy`.

Tests assert:

- Direct open button: “Open Anky”
- Notification initial: “Send notification”
- Notification sent: “Tap notification - or resend”
- Disabled: “Open Anky manually”

See `Anky/Tests/WriteBeforeScrollTests.swift:292-314`.

Note the code currently uses ASCII hyphen text, not the exact em dash phrasing.

## 8. Privacy And Local Data

### Where Writing Is Stored

- Active draft: `Documents/ActiveDrafts/dotAnky.anky` via `ActiveDraftStore`: `Anky/Core/Storage/ActiveDraftStore.swift:10-18`.
- Sealed sessions: app Documents through `LocalAnkyArchive`.
- Session metadata: Application Support JSON via `SessionIndexStore`.
- Reflections: Application Support JSON via `ReflectionStore`: `ReflectionStore.swift:53-67`.

### What Leaves Device

Writing leaves the device when a reflection/nudge is requested.

`MirrorClient` sends raw `.anky` bytes as the POST body: `Anky/Core/Mirror/MirrorClient.swift:125-151`.

It also sends signed identity/account headers: `MirrorClient.swift:132-144`.

RevenueCat receives purchase/customer identity data for reflection credits.

Optional iCloud backup exists through `YouViewModel` dependencies: `YouViewModel.swift:40`, `YouViewModel.swift:78-83`.

### Auth / Account

There is a local writer identity/account system through `WriterIdentityStore`, used by You/profile, RevenueCat identity, signing, backup/recovery.

### App Group Data

WBS stores app-blocking state locally in App Group:

- Selected opaque tokens / counts.
- Unlock state.
- Pending launch bridge intent.
- Event logs.
- Shield state.

This is good. Raw writing should not be placed in App Group or exposed to extensions.

### Privacy Boundary To Preserve

Hard boundary recommended:

- Raw writing stays in main app container only.
- Extensions should only access WBS routing/shield/unlock state, never writing content.
- Selected app tokens remain opaque and local.
- Reflection upload must be explicit and explainable.
- Completion/share surfaces should not reveal raw writing by default.

## 9. Build Health

Commands run:

- Project/file inspection.
- Symbol searches for WBS, Screen Time, RevenueCat, StoreKit, notifications.
- Entitlement inspection.
- `xcodebuild -list -project Anky.xcodeproj`

`xcodebuild -list` succeeded.

Targets:

- `Anky`
- `AnkyWriteBeforeScrollShieldAction`
- `AnkyWriteBeforeScrollShieldConfiguration`
- `AnkyWriteBeforeScrollMonitor`

Schemes:

- `Anky`
- Extension schemes
- RevenueCat schemes

Swift packages include RevenueCat `5.73.0`, Web3swift, CryptoSwift, secp256k1, BigInt.

I did not run a full build or tests in this assessment pass. The repo has tests including `Anky/Tests/WriteBeforeScrollTests.swift`, but the current WBS tests include at least one test that encodes the incorrect “sentence unlock after first character” behavior.

TODO/FIXME search found the important direct-open TODOs:

- `WriteBeforeScrollLaunchBridgeModeResolver.swift`
- `ShieldActionExtension.swift:165-170`
- `SCREEN_TIME_SPIKE_NOTES.md:79`

## 10. Gap Analysis Against Renewed Anky

| Desired capability | Current status | Existing files involved | Main gap | Risk |
|---|---:|---|---|---|
| Sharp 3-screen WBS onboarding | Partial | `OnboardingView.swift` | Old writing/reflection thesis | Medium |
| User selects distracting apps | Partial | `WriteBeforeScrollDebugPanel.swift`, `ScreenTimeSelectionStore.swift` | Debug-only setup | Medium |
| Screen Time authorization | Partial | `WriteBeforeScrollSpikeViewModel.swift` | Debug-only UX | Medium |
| Shield/lock screen works | Partial | Shield extensions, `ScreenTimeShieldController.swift` | Needs production QA/entitlement approval | High |
| User can write from blocked-app path | Partial | `AppRoot.swift`, bridge store | Works through pending intent, still root-coupled | Medium |
| Direct app open | Missing/scaffolded | bridge resolver/action extension | SDK symbol unavailable in Swift interface | High |
| Notification fallback | Implemented | `ShieldActionExtension.swift`, `AnkyApp.swift` | Permission/Focus dependence | Medium |
| Button copy adapts to path | Partial | bridge store, shield config | Direct mode not active | Medium |
| 1 sentence unlocks 15 min | Partial/incorrect | `UnlockPolicy.swift` | Grants on any non-whitespace char | High |
| 88 seconds unlocks 30 min | Implemented | `UnlockPolicy.swift` | Needs real-device UX polish | Low |
| 8 minutes unlocks day | Implemented | `UnlockPolicy.swift` | End-of-day behavior needs QA | Low |
| Unlock state machine | Partial | unlock stores/state machine | Debug architecture, emergency incomplete | Medium |
| Relock after expiration | Partial | DeviceActivity scheduler/monitor | Real-device reliability/App Store risk | High |
| Local event logging | Implemented | `WriteBeforeScrollEventLogStore.swift` | Debug-readable only | Low |
| Home shows protected apps/next gate | Missing | old home | Needs new WBS home model/UI | Medium |
| 8-day journey | Missing | none | Not built | Medium |
| Signal/streak/protected-time metrics | Partial | `MapViewModel.swift`, WBS event log | Old streak only; no protected metrics | Medium |
| Archive of sessions | Implemented | archive/session/reflection stores | Not redesigned for `/you` detail | Medium |
| Reflection after writing | Implemented | `MirrorClient`, sealing flow | Remote/credits UX needs WBS alignment | Medium |
| Paywall after first gate | Missing | RevenueCat credits client | Current monetization is credit packs | High |
| Share card without private writing | Missing | none obvious | Needs new share artifact | Medium |
| Widget support | Missing | no widget target found | New target/App Group read model needed | Medium |
| Strong local privacy boundary | Partial | archive/reflection/app group stores | Reflection upload and backup need clearer product boundary | Medium |

## 11. Recommended Implementation Sequence

### Phase 1 — Stabilize Current WBS Foundation

Goal: Make the existing spike correct and reliable before productizing.

Files likely touched:

- `UnlockPolicy.swift`
- `WriteBeforeScrollSessionMetrics.swift`
- `WriteBeforeScrollTests.swift`
- `WriteViewModel.swift`
- `ScreenTimeShieldController.swift`
- `ShieldActionExtension.swift`
- `WriteBeforeScrollSpikeViewModel.swift`
- `SCREEN_TIME_SPIKE_NOTES.md`

Risks:

- Screen Time behavior can only be proven on physical devices.
- Direct open depends on SDK availability.
- Current tests encode wrong sentence behavior.

Acceptance criteria:

- Sentence unlock requires completed period/dot sentence.
- 88s and full anky tiers still pass.
- `.anky` sealed files include terminal `8000` if that is protocol-required.
- Real-device blocked app to shield to bridge to write to unlock to relock works.
- Emergency unlock behavior is explicit and not accidental.

### Phase 2 — Renewed Onboarding And Setup

Goal: Replace old onboarding with WBS promise/mechanism/setup.

Files likely touched:

- `OnboardingView.swift`
- `AppRoot.swift`
- New WBS setup view/view model
- `WriteBeforeScrollSpikeViewModel.swift` or successor production VM
- `ScreenTimeSelectionStore.swift`

Risks:

- Screen Time permission copy must be truthful.
- Notification fallback setup should be requested only when needed.

Acceptance criteria:

- User understands “Write before you scroll.”
- User selects distracting apps.
- User authorizes Screen Time.
- User understands notification fallback if direct open is unavailable.
- First lock can be applied without debug panel.

### Phase 3 — Writing Gate And Post-Seal Product Loop

Goal: Make the blocked-app path feel like the core ritual, not a debug route.

Files likely touched:

- `WriteView.swift`
- `WriteViewModel.swift`
- `AppRoot.swift`
- Post-session sealing code
- `WriteBeforeScrollReturnTarget.swift`
- WBS unlock stores

Risks:

- `AppRoot` is already overloaded.
- Need to avoid duplicating writing UI.
- Returning to X/TikTok via URL scheme is best-effort and not generally guaranteed by Apple APIs.

Acceptance criteria:

- Opening Anky normally lands in writing.
- Opening from shield lands in writing.
- Sealing screen shows reflection/gate only.
- Gate button says “go back to X/TikTok/the app” when known.
- “Done” returns to main app screen, not back into writing accidentally.
- Unlock buttons do not show while already unlocked.

### Phase 4 — WBS Home / Signal State

Goal: Replace old dashboard emphasis with protected-app state and next gate.

Files likely touched:

- `HomeDailyChamberView.swift` or new `WriteBeforeScrollHomeView.swift`
- `AppRoot.swift`
- `WriteBeforeScrollScreenTimeStateStore.swift`
- `WriteBeforeScrollEventLogStore.swift`
- New metrics store

Risks:

- Need to define “home” carefully now that writing is the default surface.
- Old Map/CheckIn concepts may conflict with new thesis.

Acceptance criteria:

- Home shows protected apps.
- Shows locked/unlocked state.
- Shows next gate.
- Shows wrote-today/signal/streak/protected time.
- No debug panel needed for normal usage.

### Phase 5 — Archive, Privacy, Share, Monetization, Widgets

Goal: Product polish after the loop is real.

Files likely touched:

- Archive/You views
- `RevealViewModel`
- RevenueCat client/paywall layer
- New widget target
- App Group read models
- Privacy/legal copy

Risks:

- Current RevenueCat setup is credit-pack based, not subscription.
- Widgets require a stable App Group data contract.
- Share cards must not leak private writing.

Acceptance criteria:

- Archive detail contains raw writing/reflection.
- Completion share card reveals completion, not writing.
- Paywall appears after first successful gate.
- Widget shows wrote today/streak/protected state.
- Privacy boundary is clear in UI and implementation.

## 12. Final Summary

**What the app currently is**

A live private writing/reflection app that has recently gained a serious WBS Screen Time spike. The original app is still present: onboarding, check-in dashboard, map, archive, You/profile, reflection credits, exports, recovery, and iCloud backup. The current launch path now strongly favors the writing interface.

**What it is closest to becoming**

A hybrid WBS app inside the current repo: existing writing/protocol/storage/reflection systems can be reused, while Screen Time blocking, App Group bridge, notification fallback, unlock state, and local logging already exist as a working spine.

**The biggest technical risk**

Apple Screen Time behavior and distribution: FamilyControls/ManagedSettings/DeviceActivity require entitlement approval, real-device QA, and careful handling of direct-open vs notification fallback. The direct-open path is not currently active in the local SDK.

**The biggest product risk**

The app still contains two product centers: old “8-minute reflection/check-in” and new “private writing gate before scrolling.” Until onboarding, home, and archive are realigned, users will see a confusing mix of concepts.

**The first implementation prompt I recommend sending next**

“Stabilize the WBS foundation only: fix the sentence tier to require a completed period/dot sentence, update WBS metrics/tests accordingly, ensure sealed `.anky` sessions include the terminal `8000` sentinel if required by the protocol, and verify the real-device shield to bridge to write to unlock to relock loop without changing onboarding or archive yet.”
