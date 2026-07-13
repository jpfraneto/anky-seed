# Continuity Apps

A **continuity app** is software where the user’s continuity does not begin on the company’s server.

It begins on the user’s device.

The core infrastructure is simple:

```text
first launch
→ generate seed phrase on device
→ derive keypair / account
→ store private material locally
→ sign actions
→ server verifies continuity without owning identity
```

This is the missing center of the idea.

A continuity app is not just an app with memory. It is not just a local-first app. It is not just an AI app that remembers context. It is an app where the person has a **portable cryptographic root** that allows the system to recognize the same human thread over time without requiring a platform-owned login.

The seed phrase is not a crypto feature.

It is the **continuity root**.

---

## The shortest definition

A continuity app is an app where identity is generated locally, carried by the user, and proven through signatures instead of being issued by the platform.

Most apps say:

```text
create account → authenticate session → use app
```

A continuity app says:

```text
create local continuity root → act → sign the trace → continue
```

The account is not the beginning.

The practice is the beginning.

The cryptographic identity exists to protect the practice, not to become the product.

---

## The seed phrase model

On first launch, the app generates a seed phrase on the user’s device.

In Anky’s case, the current model is:

```text
12-word recovery phrase
→ BIP39 mnemonic
→ Base EOA keypair
→ derived at m/44'/60'/0'/0/0
→ accountId: eip155:8453:<checksum_ethereum_address>
```

The important part is not that this is “crypto.”

The important part is that the app does not need to ask the platform, Google, Apple, Privy, a social login, or a backend database to create the user’s root identity.

The user’s device creates it.

The private key stays on the device.

The public account can be shared with the server.

The private material should never be sent to the server.

This creates a different kind of software relationship:

```text
The server does not own the user.
The server recognizes the user’s continuity.
```

---

## What gets stored on the device

The device stores the secret that anchors continuity.

That usually means:

- the seed phrase, or encrypted seed material;
- the derived private key;
- local app state connected to that identity;
- optionally, a local database of traces, drafts, artifacts, and recovery metadata.

In user-facing language, this should not necessarily be called a wallet.

It can be called:

```text
recovery key
local identity
continuity key
private account
```

The user does not need to feel like they are using a crypto app.

They are using an app that belongs to them.

The cryptography should live underneath the floorboards.

---

## What the server sees

The server does not need the seed phrase.

It only needs enough information to verify that a request came from the same continuity root as before.

For Anky, the shape is something like:

```http
POST /anky
Content-Type: text/plain
X-Anky-Identity-Version: anky.base.eoa.v1
X-Anky-Account: eip155:8453:<checksum_ethereum_address>
X-Anky-Signature-Type: eip712
X-Anky-Signature: <signature>
X-Anky-Request-Time: <timestamp>

<exact .anky bytes>
```

The body is the artifact.

The signature proves authorship.

The account identifies the continuity thread.

The server can verify:

```text
Did the holder of this private key sign this exact request?
Is this the same continuity root as before?
Is this request fresh enough to accept?
Does this account have credits, entitlement, or permission?
```

The server does **not** need to know the user’s name.

The server does **not** need a password.

The server does **not** need a JWT session as the source of truth.

The server does **not** need to possess the user’s identity.

---

## Why this matters

The normal internet turns identity into an account controlled by someone else.

```text
email login
social login
platform account
password reset
session token
terms-controlled access
```

That model is convenient, but the user’s continuity lives inside the platform.

A continuity app reverses the direction.

```text
the user has the root
apps recognize the root
actions are signed by the root
artifacts can move with the root
```

This lets the app say:

> I can recognize that this is still you, without owning you.

That is the heart of the architecture.

---

## Continuity is not memory alone

A lot of apps now say they have memory.

But platform memory is not the same as user continuity.

Platform memory says:

```text
we remember things about you
```

Continuity says:

```text
you carry the thread
```

That distinction matters.

A continuity app may remember things, but its memory should be downstream of the user’s cryptographic continuity root. The app can store traces, reflections, credits, preferences, and history, but those things should attach to the user’s locally generated identity, not to a platform-owned account.

The server may witness.

The user carries.

---

## Anky as the concrete example

Anky’s continuity begins before any reflection, subscription, payment, or AI call.

It begins when the app creates a local identity.

The user opens Anky. The app silently generates a recovery phrase and derives a Base account. The user does not need to understand Base, wallets, EIP-712, or signatures. The app simply has a private root that can prove continuity.

Then the user writes.

The canonical artifact is the `.anky` file.

That file is not only text. It contains timing, rhythm, silence, completion, and interruption. It is a trace of contact.

When Anky sends that trace to the mirror service, the request is signed by the local private key. The server can verify that the same continuity root is making the request.

That makes possible:

```text
credits without login
reflections without username/password
abuse prevention without identity extraction
portable authorship of .anky artifacts
future recovery from seed phrase
future cross-device continuity
```

The app does not need to become a wallet UI.

There should be no RPC flow, no WalletConnect, no transaction screen, no “buy crypto” surface, and no smart-wallet ceremony unless the product truly needs it later.

The crypto is infrastructure.

The ritual is the product.

---

## The deeper pattern

The pattern underneath continuity apps is:

```text
activity → signed trace → continuity → identity
```

The user acts first.

The action leaves a trace.

The trace is signed by the user’s local key.

The signed traces accumulate.

Over time, the person’s continuity becomes visible.

Identity is not a profile form. Identity is what becomes legible through repeated action.

This is why continuity apps feel different from account-based apps.

They do not begin by asking:

> Who are you?

They begin by protecting the moment where the user does something true.

Then they preserve the thread.

---

## What continuity apps are not

### They are not normal login apps

A normal login app creates a server-side account and gives the user access to it.

A continuity app creates a local root and lets the server recognize signatures from it.

### They are not wallet apps

A continuity app can use wallet-like infrastructure without presenting itself as a wallet.

The user does not need to see crypto language unless recovery, export, or advanced settings require it.

### They are not AI memory apps

AI memory is usually controlled by the model provider or application.

Continuity should be controlled by the user’s root identity.

AI can reflect the trace, but the trace belongs to the user.

### They are not merely local-first apps

Local-first storage is useful, but local storage alone does not prove continuity across requests, devices, or services.

The cryptographic root is what lets the app say:

```text
this action belongs to the same continuing subject
```

without needing a platform-owned account.

---

## Product principles

A continuity app should obey these laws.

### 1. Generate identity locally

The first identity should be born on the device.

Not from a signup form.

Not from OAuth.

Not from a company database.

### 2. Keep private material private

The seed phrase and private key should remain on the user’s device.

The server should never receive them.

### 3. Use signatures as proof

Requests should be signed.

Artifacts can be signed.

The signature is what lets the server verify authorship and continuity.

### 4. Hide the machinery

The user does not need to think about keys every day.

The app should feel simple, human, and direct.

The key should appear only when the user needs recovery, export, security, or advanced control.

### 5. Make recovery real

If the seed phrase is the continuity root, losing it can mean losing the thread.

So the product must eventually teach the user, gently and clearly, how to preserve it.

This should not be scary, but it should be honest.

### 6. Attach server state to the continuity root

Credits, entitlements, paid reflections, usage limits, backups, and artifacts can all attach to the public account derived from the local seed.

The account is a recognition point, not a possession point.

### 7. Keep the ritual above the rails

The cryptographic layer should protect the experience.

It should not dominate the experience.

In Anky, the point is still writing for eight minutes.

The continuity key exists so that the writing can belong to the writer.

---

## The architecture in one diagram

```text
User device
  ├─ generates 12-word seed phrase
  ├─ derives private key
  ├─ stores private material locally
  ├─ creates local traces and artifacts
  └─ signs requests
          │
          ▼
Server
  ├─ receives public account
  ├─ receives signed request
  ├─ verifies signature
  ├─ checks credits / entitlement / replay protection
  ├─ runs reflection or service logic
  └─ returns result
          │
          ▼
User continuity
  ├─ remains anchored in the user’s key
  ├─ can be recovered by the seed phrase
  ├─ can accumulate artifacts over time
  └─ is recognized, not owned, by apps
```

---

## The one-line thesis

A continuity app is powered by a seed phrase generated on the user’s device, stored privately on that device, and used to sign traces of action so the system can recognize the same human thread over time without owning the person.

That is the infrastructure.

The poetry comes after.
