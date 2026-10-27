# App Privacy answers — Anky: Walking Meditation 2.3.0

What to enter in App Store Connect › App Privacy for 2.3.0 (70), and what
`Anky/PrivacyInfo.xcprivacy` should say so the two agree. Supersedes
`NUTRITION_LABEL.md` ("Data Not Collected" was true for 2.2.0 only; 2.3.0 talks
to Anky's server and RevenueCat again).

Written 2026-10-27 from the code: `Anky/Core/Server/AnkyServerClient.swift`
(the only `URLSession` caller in the app), `Anky/Purchases/SubscriptionService.swift`
(RevenueCat, `appUserID` = the anonymous account id), `backend/access/routes.ts`,
`backend/level/db.ts`, `backend/server.ts` (reflection providers, ZDR).

## Q1. Do you or your third-party partners collect data from this app?

**Yes.**

## Q2. Data types collected

Only two. Everything else is **not collected**.

| Category › Type | Linked to the user? | Used for tracking? | Purposes |
|---|---|---|---|
| **Identifiers › User ID** | **Yes** | **No** | **App Functionality** |
| **Purchases › Purchase History** | **Yes** | **No** | **App Functionality** |

### Identifiers › User ID

The app creates a random anonymous account identifier on the device. It is sent
(as the request's authenticated account) to Anky's server on every request
(`POST /access/status` at launch/foreground, `POST /anky` for a reflection) and
is the RevenueCat `appUserID`. The server stores it with the subscription status
(`subscription_state`), in short-lived request bookkeeping
(`request_idempotency`, `account_daily_quota`), and as a SHA-256 hash in the
free-access ledger (`free_access_ledger`, kept after Delete All Data).

- Linked: **Yes.** It *is* the identifier the records are keyed by. "Anonymous"
  does not make it unlinked in Apple's sense: Apple counts data as linked when
  it is tied to an account or ID, even one with no name or email.
- Tracking: **No.** Never combined with third-party data for advertising, never
  shared with a data broker, no IDFA.
- Purpose: **App Functionality** (authenticating requests, enforcing the seven
  free days once per account, subscription entitlement, abuse prevention — all
  of which Apple files under App Functionality).

### Purchases › Purchase History

RevenueCat receives the App Store purchase/subscription records for the
account; the server keeps the entitlement state (product id, active, expiry,
environment) from RevenueCat webhooks and lookups.

- Linked: **Yes** (keyed by the account id above). RevenueCat's own SDK
  manifest declares Purchase History as *not linked*, but that is RevenueCat's
  default for anonymous RC ids. Anky sets `appUserID` to its own account id
  and stores the entitlement against it, so it is linked here.
- Tracking: **No.**
- Purpose: **App Functionality.**

## Q3. Data types NOT collected, and why

Answer "not collected" for every other type. The ones a reviewer might ask about:

- **User Content › Other User Content (the writing sent for a reflection): not
  collected.** Apple's definition of "collect" is transmitting data off the
  device in a way that lets the developer or its partners access it for longer
  than necessary to service the request in real time. A reflection is serviced
  in real time: the server forwards the `.anky` bytes to the model provider,
  streams the reflection back to the device and keeps neither the writing nor
  the reflection. The only providers the server will use are flagged zero data
  retention / no content logging / no training (`privacyRequiresZdr: true` in
  `backend/server.ts`; Bankr and Poiesis are skipped unless
  `*_ZDR_CONFIRMED=true`, OpenRouter requests carry
  `provider: { data_collection: "deny", zdr: true }`). The server does keep a
  SHA-256 of the reflected bytes for idempotency; a one-way hash is not the
  content. The feature is also optional, subscriber-only, opt-in per writing
  and explained before sending.
  **If the founder cannot confirm** that the production hosting (Railway logs,
  any proxy) never records request bodies, or that the production env really
  has ZDR confirmed for every provider in `providerOrder`, declare instead:
  *User Content › Other User Content — Linked: Yes — Tracking: No — App
  Functionality.* Over-declaring is safe; under-declaring is not.
- **User Content › Audio Data, Photos or Videos: not collected.** Voice and video
  stay in `Documents/Sessions/<id>/media`, never leave the device, never
  transcribed. Export is user-initiated to a destination the user picks.
- **Location (precise or coarse): not collected.** No location APIs. The server
  sees IP addresses only for in-memory rate limiting and does not store or
  geolocate them.
- **Contact Info › Email Address, Other User Content › Customer Support: not
  collected through the app.** Support opens the person's own Mail app (and a
  Telegram link); nothing is sent by the app itself.
- **Financial Info › Payment Info: not collected.** Apple processes payment.
- **Usage Data › Product Interaction, Diagnostics (crash, performance, other):
  not collected.** No analytics or crash SDKs; the 2.3.0 client sends no funnel
  or event data (the Screen Time event log is local only). The backend still has
  `funnel_events`/`session_ledger` tables from older clients, but 2.3.0 never
  calls those routes.
- **Identifiers › Device ID: not collected.** RevenueCat's
  `collectDeviceIdentifiers` / attribution APIs are not called.
- **Health & Fitness: not collected.** No HealthKit, no step counting.

## Q4. Tracking

**No** for both types. `NSPrivacyTracking` stays `false`, no tracking domains,
no App Tracking Transparency prompt needed.

## Recommended `Anky/PrivacyInfo.xcprivacy` change

The current manifest still declares the pre-2.2 set (Other User Content,
Product Interaction with Analytics, Email Address, Customer Support, Other
Diagnostic Data). Those no longer match the app, and it is missing two
required-reason API declarations that 2.3.0 code now uses:

- `ProcessInfo.processInfo.systemUptime` in
  `Features/Access/AccessController.swift` (trusted clock anchored to server
  time) → **System Boot Time, reason `35F9.1`** (measure elapsed time between
  events within the app).
- `.volumeAvailableCapacityForImportantUsageKey` in
  `Core/Session/ExpressionSessionStore.swift` (free space before recording) →
  **Disk Space, reason `E174.1`** (check there is enough space to write files).

Missing required-reason declarations get flagged at upload (ITMS-91053).

```diff
 	<key>NSPrivacyCollectedDataTypes</key>
 	<array>
 		<dict>
 			<key>NSPrivacyCollectedDataType</key>
 			<string>NSPrivacyCollectedDataTypeUserID</string>
 			...unchanged (linked true, tracking false, AppFunctionality)...
 		</dict>
-		<dict>
-			<key>NSPrivacyCollectedDataType</key>
-			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
-			...
-		</dict>
 		<dict>
 			<key>NSPrivacyCollectedDataType</key>
 			<string>NSPrivacyCollectedDataTypePurchaseHistory</string>
 			...unchanged (linked true, tracking false, AppFunctionality)...
 		</dict>
-		<dict>  NSPrivacyCollectedDataTypeProductInteraction  ... </dict>
-		<dict>  NSPrivacyCollectedDataTypeEmailAddress        ... </dict>
-		<dict>  NSPrivacyCollectedDataTypeCustomerSupport     ... </dict>
-		<dict>  NSPrivacyCollectedDataTypeOtherDiagnosticData ... </dict>
 	</array>
 	<key>NSPrivacyAccessedAPITypes</key>
 	<array>
 		<dict>  UserDefaults  CA92.1  (unchanged) </dict>
 		<dict>  FileTimestamp C617.1  (unchanged) </dict>
+		<dict>
+			<key>NSPrivacyAccessedAPIType</key>
+			<string>NSPrivacyAccessedAPICategorySystemBootTime</string>
+			<key>NSPrivacyAccessedAPITypeReasons</key>
+			<array>
+				<string>35F9.1</string>
+			</array>
+		</dict>
+		<dict>
+			<key>NSPrivacyAccessedAPIType</key>
+			<string>NSPrivacyAccessedAPICategoryDiskSpace</string>
+			<key>NSPrivacyAccessedAPITypeReasons</key>
+			<array>
+				<string>E174.1</string>
+			</array>
+		</dict>
 	</array>
```

If the conservative route for reflections is chosen (see Q3), keep the
`OtherUserContent` dict (linked true, tracking false, AppFunctionality) and
declare it in App Store Connect too. The two must match either way.

The extensions (shield, App Clip) ship their own manifests; they make no network
calls, so they should declare no collected data. Check them for the same
required-reason APIs if they share `ExpressionSessionStore` or the access code.
