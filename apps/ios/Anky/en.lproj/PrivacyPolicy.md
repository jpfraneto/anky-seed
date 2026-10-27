# Anky Privacy Policy

Effective and revised: October 27, 2026

Anky (Anky: Walking Meditation) is a place to write, speak and record while you walk or sit still. What you express is saved on your iPhone. There is no login, no analytics, no advertising and no tracking, and Anky does not use your location.

## 1. Who we are

Anky is operated by **Anky, Inc.**, a Delaware corporation. Contact us at **[support@anky.app](mailto:support@anky.app)**.

This policy covers the Anky iOS app and the anky.app website. Anky is not a medical, mental-health, crisis, legal or financial service.

## 2. What stays on your iPhone

Anky stores these things on your iPhone only:

- Your sessions: writings (as `.anky` files), voice recordings, videos, and each session's details (when it started and ended, which ways you chose to express yourself, and the optional "walking" or "staying still" label you picked)
- Reflections you asked for, once they come back to your iPhone
- Any unfinished draft, and the index used to list your past sessions
- Your settings
- If you use the Screen Time gate: the apps you chose (as opaque Apple identifiers), the gate's state and your unlocks
- A random anonymous account identifier, kept in the iOS Keychain (see section 4)

Your writings, voice recordings and videos are not sent to Anky. We cannot read, hear or watch them, and we have no copy of them.

## 3. Microphone and camera

Anky uses the microphone only while you record your voice, or the sound of a video, and the camera only while you record a video. Recording starts when you press record and stops when you stop it. A voice recording can keep going while the screen is locked, so the phone can stay in your pocket while you walk; that is the only reason Anky uses audio in the background.

Recordings are saved on your iPhone. They are never uploaded, and they are never transcribed, by Anky or by anyone else.

## 4. What Anky's server receives

There is no account to create. On first launch the app creates a random anonymous account identifier on your iPhone. It is not your name, email, phone number or Apple ID, and it is never shown in the app. The app uses it to authenticate the few requests it makes to Anky's server:

- **Free days and subscription check.** When you open Anky, the app asks the server whether your free days or subscription are active. This request contains no writing, recording or session content.
- **Free-access record.** When you begin your first session, the server records a one-way SHA-256 hash of your anonymous identifier and the time your seven free days began. This record contains nothing you wrote, said or recorded. **It is kept even after you use Delete All Data**, because its only purpose is to make sure the seven free days begin once per account and cannot be restarted. It cannot be used to recover or read any of your content.
- **Subscription status.** If you subscribe, the server keeps your anonymous identifier together with your subscription's status (product, whether it is active, when it renews or expires), which it learns from RevenueCat (section 6).
- **Reflections**, only if you ask for one (section 5).

To keep the service working and to prevent abuse, the server also keeps per-day counts of requests and, for reflections, a one-way hash of the reflected text (not the text itself) so the same request is not processed or charged twice. Our hosting provider sees your IP address to deliver each request; Anky uses it only briefly to limit abusive traffic and does not store it with your identifier.

## 5. AI reflections (optional, subscribers only)

"Reflect with Anky" is optional and available only to subscribers. Nothing is sent unless you tap it for a specific writing and then confirm.

- **What is sent:** the `.anky` file of that one writing, meaning its text and the timing of its keystrokes, along with your anonymous identifier and the app version. Voice recordings and videos are never sent.
- **Who processes it:** Anky's server passes the writing to an AI inference provider, which runs a large language model (currently Anthropic's Claude models, reached through AI gateway services) to write the reflection. Anky only uses providers configured for zero data retention, with logging of content and training on content turned off; if no such provider is available, no reflection is generated.
- **Retention:** Anky's server does not store your writing or the reflection. The model provider processes the text only to generate the reflection. The reflection is sent back to your iPhone and saved there.

Nothing else in Anky uses AI.

## 6. Subscriptions and payment

Anky offers seven free days of its core experience, starting with your first session. No payment details are collected and nothing is charged when they end.

The subscription is an auto-renewing monthly subscription sold by Apple through the App Store. Apple handles payment; Anky never receives your payment card or billing details. Anky uses **RevenueCat** to manage subscriptions: RevenueCat receives your anonymous account identifier and your App Store purchase and subscription records so it can tell the app whether you are subscribed. See RevenueCat's privacy policy at [revenuecat.com/privacy](https://www.revenuecat.com/privacy). Cancel or manage your subscription in your Apple Account's subscription settings.

If your free days end and you do not subscribe, everything you already created stays on your iPhone, readable and exportable.

## 7. What Anky does not do

- It does not upload or transcribe your writing, voice or video. The only content that ever leaves your iPhone is a single writing you choose to send for a reflection.
- It does not use your location.
- It does not include analytics, crash-reporting, advertising or tracking SDKs, and it does not track you across apps or websites.
- It does not sell or share your data, or use it to train AI models.

## 8. Apple services you can choose to use

- **iCloud backup:** if you turn it on, Anky encrypts your writings and reflections with AES-GCM and stores the encrypted file in your own iCloud Drive. Voice recordings and videos are not included. What is needed to decrypt the backup is saved in your iCloud Keychain so you can restore it on a new iPhone. Apple runs iCloud; Anky never sees the backup.
- **Screen Time:** if you turn on the gate, Apple's Screen Time frameworks handle permission and app selection. Your list of apps stays on the device.
- **Notifications:** reminders and the gate's notifications are scheduled locally by iOS.
- **Face ID:** used only to confirm it is you before turning on iCloud backup. Apple handles the check; Anky only learns yes or no.

Your iPhone's own device backups, if you use them, are handled by Apple under Apple's terms.

## 9. Export

**Settings → Export my memories** creates a single .zip file with every session's details, the original audio and video files, your writings as `.anky` and plain text, and your reflections as Markdown. Export works with or without a subscription. Where the file goes after that is up to you.

## 10. Deleting your data

Delete a single session or writing from its menu. **Settings → Delete All Data** removes every session, writing, voice recording, video, reflection and setting from your iPhone, along with the anonymous identifier and your Anky iCloud backup. Deleting the app also removes its local data.

Delete All Data does not cancel a subscription; cancel it with Apple. The anonymous free-access record described in section 4 is kept so the free days cannot restart. The subscription status record on Anky's server and the subscriber record at RevenueCat are tied only to the anonymous identifier; once it is deleted from your iPhone, those records can no longer be connected to you or to anything you created. For any other deletion request, write to **[support@anky.app](mailto:support@anky.app)**.

## 11. Support

Settings can open your mail app or a chat link. Nothing is sent unless you send it, and then we receive what you chose to write.

## 12. Children, changes and contact

Anky is not intended for children under 13. If this policy changes, we will update it here and revise the date above.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
