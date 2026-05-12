# ANKY Android

Native Kotlin only. Do not use React Native or Expo.

Android follows the same product law as iOS:

- the `.anky` file is the canonical artifact
- writing is stored locally on the device
- reflections are stored locally on the device
- the mirror contract is exactly `POST /anky`
- the request body is the exact `.anky`
- the protocol fixtures in `protocol/fixtures` are shared test vectors

Do not share UI code with iOS. Share only product law, protocol law, fixtures, and the mirror API contract.
