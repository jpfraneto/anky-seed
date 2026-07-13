# Privacy Truth Table

Generated from the final iOS and backend code on 2026-07-11.

| Flow | Off-device payload | Linked to identity | Tracking | App Store data type | Purpose |
| --- | --- | --- | --- | --- | --- |
| `POST /anky` reflection/nudge | Exact `.anky` bytes transiently, EIP-712 account headers, artifact hash returned, intent, app version/client metadata | Yes | No | Other User Content, User ID, Product Interaction | App Functionality |
| `POST /level/prepare` | Writing text transiently for painting distillation, level, signed account headers | Yes | No | Other User Content, User ID, Product Interaction | App Functionality |
| `POST /level/sessions` | Session artifact hash, seconds, sealed timestamp, signed account headers | Yes | No | Product Interaction, User ID | App Functionality, Analytics |
| `GET /level/status` | Signed account headers over empty body | Yes | No | User ID, Product Interaction | App Functionality |
| `POST /level/ceremony-shown` | Level number, signed account headers | Yes | No | Product Interaction, User ID | App Functionality, Analytics |
| `GET /level/assets/:level/:file` | Signed account headers, requested level/file | Yes | No | User ID, Product Interaction | App Functionality |
| `POST /events/emergency-unlock` | Event name/time/origin metadata, signed account headers; backend stores hashed account | Yes | No | Product Interaction, User ID | App Functionality, Analytics |
| `POST /events/funnel` | Whitelisted funnel event/origin, signed account headers; backend stores hashed account | Yes | No | Product Interaction, User ID | Analytics |
| `POST /subscription/identify` | RevenueCat app user id/account, signed account headers; backend refreshes entitlement | Yes | No | Purchases, User ID | App Functionality |
| RevenueCat SDK | App user id, subscription/purchase status, StoreKit purchase metadata handled by RevenueCat SDK | Yes at the app level | No | Purchase History, User ID; SDK manifest independently declares generic Purchase History as unlinked | App Functionality |
| `DELETE /account` | Signed empty-body account deletion request | Yes | No | User ID, Product Interaction | App Functionality |
| Support email | Sender email address, subject/body/attachments selected by the user, and prefilled pseudonymous support id | Yes | No | Email Address, Customer Support, User ID | App Functionality |
| Service diagnostics | Random request id; hashed account/artifact ids; client/version; status, latency/duration, provider, entitlement and coarse failure fields; never raw writing or keys | Yes where an account hash is present | No | Other Diagnostic Data, User ID | App Functionality, Analytics |
| Screen Time extensions | App Group `UserDefaults` and local shield state only | No off-device payload | No | Not collected by Anky server | App Functionality |
| Widget | Local App Group reads only | No off-device payload | No | Not collected by Anky server | App Functionality |

Backend commitment: raw writings are never persisted server-side. `.anky` bytes and level-prepare text exist only in request memory long enough to validate, reflect, nudge, or distill. Writing-derived personalized painting scene/title metadata and generated painting packages are retained account-scoped until account deletion. Logs and durable tables store safe diagnostic fields, hashes, timestamps, account hashes/ids where required for auth/subscription, subscription state, level/session metadata, generated painting metadata/assets, and whitelisted usage events.

Privacy manifest mapping:
- App manifest declares User ID, Other User Content, Purchase History, Product Interaction, Email Address, Customer Support, and Other Diagnostic Data; all tracking flags are false.
- All four extension manifests declare required-reason UserDefaults access for App Group reads/writes; no collection categories.
- `NUTRITION_LABEL.md` is the manual App Store Connect transcription artifact.
