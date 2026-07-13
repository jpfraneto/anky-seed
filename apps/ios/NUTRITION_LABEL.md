# Anky App Privacy Nutrition Label

Repository source of truth revised July 11, 2026. Use these selections in App Store Connect for the iOS app. Apple defines collection at the app level to include Anky and integrated third-party partners. Where one data type has both transient and retained flows, the retained flow controls the answer.

## Tracking

- **Tracking:** No.
- Anky does not combine data with third-party data for advertising or share it with data brokers, and it does not track people across other companies' apps or websites.

## Data linked to the user

The identity is a pseudonymous Anky writer/account identifier, not a real-name account. Each item is **not used for tracking**.

### User ID — App Functionality

- Base wallet/account identifier used in signed backend requests and as RevenueCat's app-user ID.
- Evidence: `Anky/Core/Identity/WriterIdentity.swift`, `Anky/Core/Identity/AnkyPostSigner.swift`, `Anky/Purchases/AnkyPurchasesConfig.swift`, and backend request authentication in `backend/server.ts`.

### Purchase History — App Functionality

- Apple/StoreKit and RevenueCat product, transaction, subscription, trial/period, expiry, and entitlement state.
- Evidence: `Anky/Purchases/EntitlementStore.swift`, `backend/subscription/routes.ts`, and `backend/subscription/revenuecat.ts`.
- Payment-card details are entered with Apple and are not available to Anky.

### Other User Content — App Functionality

- Writings remain local by default. Exact `.anky` bytes used for a requested AI reflection or nudge are processed transiently and not retained by the Anky backend.
- Text submitted for personalized painting generation is processed transiently, but writing-derived scene/title metadata and generated painting packages are retained for delivery to the account. That retained derivative makes this category discloseable.
- Evidence: `Anky/Core/Mirror/MirrorClient.swift`, `Anky/Core/Level/LevelSyncClient.swift`, `backend/server.ts`, `backend/painting/routes.ts`, and `backend/painting/pipeline.ts`.

### Product Interaction — App Functionality and Analytics

- Whitelisted subscription funnel events; emergency-unlock event; session artifact hashes, duration, and sealed timestamps; level/ceremony state; generation history and quota metadata.
- Evidence: `Anky/Core/Level/LevelSyncClient.swift`, `backend/events/routes.ts`, `backend/level/db.ts`, and `backend/painting/router.ts`.

### Email Address — App Functionality

- Collected only when a person chooses to send an email to Anky support; the mail service exposes the sender address.
- Evidence: support `mailto:` composers in `Anky/Features/Settings/AnkySettingsView.swift` and `Anky/Features/You/YouViewModel.swift`.

### Customer Support — App Functionality

- The subject/body and attachments the person chooses to send, plus the pseudonymous support ID prefilled in the message body.
- Evidence: `Anky/Features/You/YouViewModel.swift` and the support sections in Settings/You.

### Other Diagnostic Data — App Functionality and Analytics

- Retained service diagnostics can include a random request ID, hashed account and artifact identifiers, client/app version, status, latency/duration, provider, entitlement result, and coarse failure codes. They exclude raw writing, prompts, reflections, recovery phrases, and private keys.
- Evidence: `SafeLogFields`, `createSafeLogger`, and endpoint logging in `backend/server.ts`; assertions in `backend/test/privacy.test.ts`.

## Data not linked to the user

- No separate Anky data category should be marked only as not linked.
- RevenueCat's embedded SDK manifest independently declares its generic `PurchaseHistory` collection as not linked, but this app supplies a pseudonymous RevenueCat app-user ID and persists account-scoped entitlement state. The conservative app-level App Store Connect answer for Purchase History is therefore **linked**.

## Data not collected

- Name (the optional in-app name remains local/inside optional user-controlled encrypted backup)
- Phone number, physical address, and other contact information
- Payment information, credit information, and other financial information
- Precise or coarse location
- Contacts
- Emails or text messages outside an optional support request
- Photos or videos (check-in image selection is local and not uploaded)
- Audio data (speech recognition uses Apple's on-device/OS service path; Anky does not retain or upload audio)
- Browsing history and search history
- Health and fitness data
- Sensitive information requested as a structured category
- Advertising data
- Crash data and performance data sent to Anky (there is no crash-reporting or third-party analytics SDK)
- Device ID (the current code has no DeviceCheck, App Attest, IDFA, vendor-ID, or custom device-ID collection)

## Optional local and Apple-controlled data

- Local `.anky` writing, saved reflections, settings, archive indexes, and static painting progress are stored on-device.
- Optional backups are AES-GCM encrypted before being written to the person's iCloud container; an optional recovery phrase can be stored in iCloud Keychain. These are user-controlled Apple services, not readable Anky backend storage.
- Screen Time selections/state stay in the local App Group and Screen Time frameworks; extensions send no off-device payload.

## Required-reason APIs

- Main app: UserDefaults (`CA92.1`) for app/app-group settings; File Timestamp (`C617.1`) for local archive/file metadata.
- Glance widget/Live Activity extension: UserDefaults (`CA92.1`) for local App Group state.
- DeviceActivity monitor extension: UserDefaults (`CA92.1`) for App Group shield state.
- Shield Action extension: UserDefaults (`CA92.1`) for App Group shield/action routing state.
- Shield Configuration extension: UserDefaults (`CA92.1`) for App Group shield UI state.

## SDK manifests

- RevenueCat ships `RevenueCat_RevenueCat.bundle/PrivacyInfo.xcprivacy`; the resolved version declares required-reason UserDefaults use and unlinked Purchase History for app functionality.
- CryptoSwift ships `CryptoSwiftResources.bundle/PrivacyInfo.xcprivacy`; web3swift uses CryptoSwift through SPM.
- The Release archive must contain the main app manifest, all four extension manifests, and the SDK manifests.
