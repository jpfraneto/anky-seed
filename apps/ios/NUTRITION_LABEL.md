# Anky App Privacy Nutrition Label

> **Superseded for 2.3.0 by [`APP_PRIVACY_ANSWERS.md`](APP_PRIVACY_ANSWERS.md).** The answers below were true for 2.2.0 only.

Repository source of truth, revised October 16, 2026 for version 2.2.0. Use these answers in App Store Connect → App Privacy.

## Answer: Data Not Collected

From 2.2.0 the app makes no network requests of its own: no Anky backend, no RevenueCat, no analytics, crash-reporting or advertising SDKs. Verified by building the app and finding no `URLSession`/`URLRequest` in any target, and no third-party SDKs linked (the only package left is `secp256k1.swift`, used offline to derive the iCloud backup key).

- **Tracking:** No.
- **Data linked to the user:** none.
- **Data not linked to the user:** none.

## Why each former category no longer applies

- **User ID:** the anonymous key never leaves the device; it only encrypts the optional iCloud backup.
- **Purchase History:** there are no in-app purchases and no RevenueCat.
- **Other User Content:** writing is never sent anywhere. "Copy prompt + writing" only puts text on the clipboard.
- **Product Interaction:** the Screen Time event log is local only.
- **Email Address:** support opens the person's own mail app; Anky does not collect anything through the app. Apple does not count data a user chooses to send by email from outside the app.

## Apple services the person controls

iCloud backup (encrypted, in the person's own iCloud Drive), Screen Time, local notifications and Face ID are handled by Apple and are not collection by Anky.

If any network feature, SDK or server call is added again, this file and the App Store Connect answers must be revised before release.
