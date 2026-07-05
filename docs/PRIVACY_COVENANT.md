# Privacy Covenant

The writer owns the writing.

The writer's device stores `.anky` files.

The server only receives writing when the writer explicitly asks for reflection.

The server processes the `.anky` transiently.

The server returns a reflection.

The server forgets.

By default, the server must never persist:

- raw `.anky`
- reconstructed writing
- private reflections
- prompt text
- model output connected to writing

The server may temporarily hold writing in memory during one reflection request. That temporary handling is not storage and must not become a journal, archive, analytics corpus, or hidden memory.

A new writer may receive one automatic trial grant of 2 reflection credits.

The automatic trial grant is app-bound, platform-bound, RevenueCat-backed, account-idempotent, and may use device attestation where reliable.

The grant happens inside `POST /anky`, only for a valid complete `.anky` reflection request.

The trial grant must not include writing.

The trial grant must not require screenshots, `.anky` files, reconstructed text, private reflections, prompts, or journal content.

The trial grant may use:

- accountId
- platform
- app version
- RevenueCat customer state
- platform attestation result when available and reliable
- minimal abuse-prevention metadata

The trial grant must not turn Anky into a cloud journal.

The trial grant must not create an Anky user account, Anky database, writing archive, prompt archive, reflection archive, or analytics over writing content.

The server still receives writing only when the writer explicitly asks for reflection.

The server still processes the `.anky` transiently.

The server still forgets.

The “DM JP for free credits” flow may remain as a fallback support path, but it must never include writing.
