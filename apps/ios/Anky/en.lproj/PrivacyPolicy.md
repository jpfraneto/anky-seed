# Anky Privacy Policy

Effective and revised: July 11, 2026

Anky is local-first. Core writing works without an account login or subscription. Your writing stays on your device unless you choose to export or back it up, contact support, or explicitly request a server-generated feature. This policy explains those choices and the limited records needed to operate Anky.

## 1. Who we are

Anky is operated by **Anky, Inc.**, a Delaware corporation. Contact us at **[support@anky.app](mailto:support@anky.app)**.

This policy covers the Anky iOS app, anky.app, the Anky backend, purchases, support, and related services. Anky is not a medical, mental-health, crisis, legal, financial, or spiritual-advice service.

## 2. Free and Pro features

The following remain free and do not require Anky Pro:

- Starting and completing new writing sessions
- Creating, continuing, saving, browsing, copying, exporting, and deleting local writings
- Reading reflections already saved on the device
- A local, non-server writing nudge when Pro is inactive
- The Screen Time gate, selecting protected apps, and enabling or disabling protection
- Three daily Quick Passes under the current unlock policy
- Emergency access and emergency unlock
- Static painting progression through level 8
- Previously delivered personalized paintings
- Archive and writing history
- Settings, local/iCloud backup, import/export, account deletion, support, and legal screens

An active lowercase `pro` entitlement is required only for:

1. New server-generated AI reflections for writings without a saved reflection, subject to service limits.
2. Server-generated AI writing nudges instead of the free local fallback, subject to service limits.
3. Full access to the 96-day writing journey.
4. Automatic rest-of-day Screen Time unlocking after the configured daily writing target is reached.
5. Adaptive daily-target suggestions.
6. Progression beyond level 8, including personalized painting generation and later painting ceremonies, subject to progress, writing, safety, capacity, and generation limits.

Generated services are always subject to reasonable service, safety, capacity, and abuse-prevention limits.

## 3. Information stored locally

Anky stores the following on your device or in its shared App Group storage:

- `.anky` writing files, active drafts, readable reconstructions, and local session indexes
- Saved AI reflections and previously downloaded paintings
- Writing time, level, journey, daily-target, Quick Pass, and unlock progress
- Settings, reminder choices, selected Screen Time app/category tokens, and gate state
- A pseudonymous Anky writer/app-user identifier and signing keys protected by iOS Keychain
- A recovery phrase, unless you choose to back it up to iCloud Keychain
- A non-authoritative subscription cache used for display continuity; paid actions require current verification

Writing, saving, continuing, browsing, copying, exporting, deleting, reading an existing reflection, using the gate, using Quick Passes, and using emergency access do not send writing to the Anky backend.

Screen Time selections are handled by Apple frameworks and local App Group storage. Anky does not send your list of protected apps to its backend.

## 4. Information sent when you request generated services

### AI reflections

When you explicitly request a new AI reflection, the app sends the exact `.anky` bytes to the Anky backend over an authenticated connection. The backend validates the file and hash, reconstructs the text, and sends the text with an instruction prompt to the configured AI provider. The generated reflection returns to your device and is saved locally.

### AI writing nudges

When Pro is currently verified and you request a server nudge, the app sends the current `.anky` writing to the same backend and AI-processing path. If Pro is inactive or cannot be verified, the app uses a local fallback and does not send the writing for a server nudge.

### Personalized paintings after level 8

When personalized progression is available and requested, the app sends the writing since the prior level to the Anky backend. The backend uses an AI model to distill visual themes and sends that derived prompt to an image-generation provider. The raw writing is processed transiently and is not saved in the backend database. Generated painting files and their account-scoped metadata are stored so they can be delivered again, until account deletion or operational/legal retention requires otherwise.

The service uses **OpenRouter** for configured model routing. Current code can route text to models supplied by providers such as Anthropic, Google, and DeepSeek, and image generation to OpenAI models. Bankr or Poiesis endpoints can be used only when configured; privacy-sensitive fallbacks are skipped unless their required zero-data-retention setting has been confirmed. Provider availability and model selection may change. Providers process submitted content under their own terms and policies.

Anky requests privacy-protective, no-training/zero-retention routing settings where supported. We cannot promise that every independent provider has identical practices. Do not submit content you do not want processed for the requested feature.

## 5. Backend and operational records

The backend uses a pseudonymous Anky writer identifier derived from the app's local cryptographic profile. It is not a traditional username/password account. Signed requests prove control of that identifier without sending your recovery phrase.

To provide and protect the service, the backend may store:

- The pseudonymous writer/app-user identifier
- Session hashes, durations, and timestamps used for level progress; not the writing text
- Level and ceremony state, painting metadata and files, generation status, and request idempotency records
- Service quotas and abuse-prevention counters
- Subscription product, transaction, store, period, expiration, and `pro` entitlement state received through RevenueCat
- First-party product events such as onboarding, paywall, purchase, lapse, and emergency-unlock events, associated with a hashed or pseudonymous identifier
- Sanitized diagnostics such as request time, app version, platform, request hash, route, provider, status/error category, and latency

The backend is designed not to persist raw writing, reconstructed writing, generated reflection text, or nudge text after completing the request. It does not use writing to train Anky-owned models. Limited content may be retained only when you deliberately provide it to support, when needed to investigate a security incident you report, or when law requires it.

Anky has no third-party advertising or cross-app tracking SDK. Anky does not sell personal data or use writing for advertising. First-party product events and diagnostics are used for app functionality, reliability, capacity, security, abuse prevention, and limited product analytics.

## 6. Apple, RevenueCat, and subscriptions

Anky offers optional auto-renewable monthly and annual subscriptions through Apple's App Store. Both durations unlock the same Anky Pro feature set. The localized price and renewal terms Apple shows at purchase time control.

The annual plan may include a three-day trial only for an eligible user and only when Apple displays that offer. The monthly plan has no introductory trial under the current configuration. Subscriptions renew automatically unless cancelled in Apple's subscription settings.

Apple handles payment, renewal, cancellation, billing, purchase history, and refund requests. Anky does not receive or store complete payment-card information.

RevenueCat manages purchase validation and entitlement delivery. Apple and RevenueCat provide purchase, transaction, product, subscription, store, expiration, trial/intro-period, and entitlement information linked to the pseudonymous Anky app-user identifier. Purchase and restore flows refresh entitlement state. Promotional or open-ended RevenueCat grants may also activate Pro.

Anky does not sell or use reflection credits, credit packs, or credit balances.

## 7. Optional Apple services and user choices

- **Encrypted iCloud backup:** If enabled, Anky creates an AES-GCM encrypted archive of local writings and reflections and stores it in your iCloud Documents container. The recovery phrase can separately be stored in iCloud Keychain at your request. Apple controls iCloud account and infrastructure data.
- **Export/import/share:** Files go to or come from the destination you choose. Anky cannot control copies after you export or share them.
- **Notifications:** iOS stores your reminder permission and schedule. A trial-ending reminder is scheduled only from a currently verified active trial.
- **Speech and photos:** If you choose a speech or image check-in, iOS permission and Apple framework rules apply. The current image check-in is not uploaded to the Anky backend or retained as a personalized-painting input.
- **Optional profile image:** A selfie/avatar you choose during onboarding is stored in local app Documents and is not uploaded to the Anky backend. It may be included in Apple device backups you enable.
- **Support:** The app opens your mail client. You choose whether to send, and your message may include your email address, pseudonymous support ID, app/platform version, text, screenshots, or attachments you provide.

## 8. Retention and deletion

Local data remains until you delete individual content, use in-app deletion, remove applicable backups, or delete the app. Deleting the app does not cancel an Apple subscription.

The in-app **Delete Account & Data** action sends an authenticated deletion request for account-scoped backend records, then removes local writings, reflections, settings, identifiers, recovery material, cached state, and the Anky iCloud backup accessible to the app. Backend deletion includes session/level records, events, quotas, generation records, and personalized painting assets controlled by Anky.

Some records cannot be deleted by Anky: Apple purchase history, RevenueCat records needed to validate purchases or comply with law, support messages retained for a legitimate support/legal purpose, copies you exported, and Apple-controlled backups. A later RevenueCat webhook may recreate minimal subscription state for the same App Store purchase.

Operational records are kept only as long as reasonably needed for the purposes above, legal obligations, security, fraud/abuse prevention, dispute resolution, and accounting. Contact **[support@anky.app](mailto:support@anky.app)** for a privacy request.

## 9. Security, international processing, and your rights

We use reasonable technical and organizational safeguards, including encrypted transport, signed requests, Keychain storage, and encrypted optional backups. No system is perfectly secure. Protect your device, Apple ID, recovery phrase, and exported files.

Anky, Inc. is based in the United States. Data you choose to send may be processed in the United States and other countries where our providers operate.

Depending on where you live, you may have rights to access, correct, delete, export, restrict, or object to processing. Much of Anky's data is local and directly controlled by you. Contact us for data Anky controls.

## 10. Children, changes, and contact

Anky is not intended for children under 13. Users under 18 should use it with permission from a parent or guardian. Contact us if you believe a child submitted personal information.

We may update this policy and will revise its date when we do.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
