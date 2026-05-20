# Identity Backup

Anky identity is local. The 12-word recovery phrase controls the Anky address. Passwords and biometrics are local gates; they are not an Anky login and are never sent to the mirror.

## iOS

iOS has an explicit “Back up Anky identity” action. It writes the recovery phrase to a synchronizable iCloud Keychain item only after local authentication. Copy says: “This stores your recovery phrase in your device/cloud keychain. Anky cannot read it.”

The normal on-device keychain item remains device-only. The cloud backup is opt-in.

## Android

Android must not rely blindly on Android Keystore-encrypted blobs restoring across devices. The safe backup path is an explicit encrypted identity envelope:

- user chooses export/import intentionally;
- envelope uses a password-derived key;
- recovery phrase is encrypted before leaving app-private storage;
- password/biometric gates stay local and are not server login;
- no identity secret is sent to Anky.

This pass documents the Android-safe design. Production encrypted envelope export/import remains blocked until UX, KDF parameters, file format, and tests are implemented.
