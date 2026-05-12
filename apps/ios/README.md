# ANKY iOS

Native SwiftUI only. Do not use React Native or Expo.

The app should open directly into Write with the keyboard ready.

The iOS client owns:

- local `.anky` capture
- local active draft storage
- local completed `.anky` archive
- local reflection storage attached to the `.anky` hash
- local Solana-compatible identity and request signing
- RevenueCat credit purchase and balance UI
- `POST /anky` integration with the mirror service

The server is not memory. The device stores the writer's writing.
