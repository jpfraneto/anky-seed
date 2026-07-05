# Freeze

This repo is currently frozen around the smallest true Anky:

- `.anky` is the artifact
- `POST /anky` is the only app-facing mirror endpoint
- the server does not store writing
- credits live outside the writing system
- official mobile trial credits may be granted lazily inside `POST /anky`
- automatic trial grants must be app-bound, platform-bound, RevenueCat-backed, and account-idempotent
- device attestation may assist abuse prevention but must not block real first-time writers
- native clients obey the protocol
- no database until proven necessary

Before adding any feature, explain which law it serves.
