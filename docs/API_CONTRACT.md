# Anky API Contract

The Anky mirror server has one app-facing endpoint:

```txt
POST /anky
```

This endpoint receives one exact `.anky` artifact, verifies a Base/EVM identity signature, mirrors the writing, spends one credit only after a real provider succeeds, returns a reflection, and forgets the writing.

The server is a mirror, not memory.

The mirror runtime/product logic is intentionally consolidated in `backend/server.ts`.

## Endpoint

```txt
POST /anky
Content-Type: text/plain; charset=utf-8
Accept: application/json
```

The request body is the exact `.anky` UTF-8 bytes. There is no JSON wrapper and no alternate writing format.

## Required Headers

```txt
X-Anky-Identity-Version: anky.base.eoa.v1
X-Anky-Account: 0xChecksumAddress
X-Anky-Signature-Type: eip712
X-Anky-Signature: 0x...
X-Anky-Request-Time: <epoch_ms>
X-Anky-Client: ios | android | other
```

Optional official-app headers:

```txt
X-Anky-App-Version: <version_or_build>
X-Anky-Trial-Proof: <platform_attestation_token>
```

Trial proof must not contain writing and must not replace request signature verification.

Optional x402 payment header:

```txt
PAYMENT-SIGNATURE: <base64_payment_payload>
```

If the writer has no available credit, the endpoint returns `402 Payment Required` with `PAYMENT-REQUIRED`. The client creates a payment payload from that header and retries with `PAYMENT-SIGNATURE`. On success, the server returns `PAYMENT-RESPONSE`.

Optional streaming response:

```txt
Accept: text/event-stream
```

With this header, `POST /anky` returns Server-Sent Events. `update` events describe safe processing stages such as identity verification, protocol validation, x402 quote creation, provider start, provider finish, settlement, and completion. The final `reflection` event contains the markdown string. The stream must never include raw writing, prompt text, signatures, or trial proofs.

## Identity

Current identity version: `anky.base.eoa.v1`

The writer identity is a local Base EOA:

```txt
accountKind: eoa
productionChainId: 8453
testChainId: 84532
account: 0xChecksumAddress
recovery: bip39-english-12-word
derivationPath: m/44'/60'/0'/0/0
curve: secp256k1
signing: EIP-712
```

The EIP-55 checksum address is the writer identity, RevenueCat App User ID, credit account key, idempotency identity, and free-credit grant target when official app/device proof is valid. Chain ID stays in env and EIP-712 domain data.

The server does not issue identity. There is no register, login, session, profile, or account endpoint.

## EIP-712 Request Signature

The server computes SHA-256 over the exact received body bytes and represents it as a `0x`-prefixed `bytes32`.

Domain:

```json
{
  "name": "Anky",
  "version": "1",
  "chainId": 8453
}
```

Primary type:

```txt
AnkyMirrorRequest {
  string identityVersion
  address account
  string method
  string path
  bytes32 bodyHash
  uint64 requestTime
  string client
}
```

Message values:

```txt
identityVersion: anky.base.eoa.v1
account: 0xChecksumAddress
method: POST
path: /anky
bodyHash: 0x<sha256_of_exact_body_bytes>
requestTime: <epoch_ms>
client: same value as X-Anky-Client
```

Verification rules:

1. Read exact raw request body bytes.
2. Compute `bodySha256`.
3. Require `X-Anky-Identity-Version: anky.base.eoa.v1`.
4. Parse `X-Anky-Account` as an EIP-55-compatible `0x...` address.
5. Normalize the address to EIP-55 checksum format.
6. Require Base mainnet chain ID `8453`.
7. Reconstruct the EIP-712 domain, type, and message from server-derived values.
8. Recover/verify the signer address from `X-Anky-Signature`.
9. Reject if the recovered address does not equal the account address.
10. Reject stale request times using the configured freshness window.
11. Use the normalized checksum address for credits and idempotency.

`personal_sign` is not part of this API.

## Request Body

The body is an exact `.anky` artifact. Example shape only:

```txt
1770000000000 h
0042 e
0091 l
0035 l
0048 o
8000
```

The API must not accept JSON writing bodies.

## Success Response

```txt
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
X-Anky-Hash: <sha256_hex>
X-Anky-Credits-Remaining: 7 | null

# three word title

markdown reflection text
```

Success is always a markdown string. `X-Anky-Hash` is SHA-256 of the exact request body bytes. The client uses it to attach the reflection to the local `.anky`.

Error responses remain JSON so clients can branch on stable error codes.

## Error Codes

```txt
400 INVALID_ANKY
400 INCOMPLETE_RITUAL
401 MISSING_IDENTITY_VERSION
401 UNSUPPORTED_IDENTITY_VERSION
401 MISSING_ACCOUNT
401 INVALID_ACCOUNT
401 UNSUPPORTED_CHAIN
401 INVALID_SIGNATURE_TYPE
401 MISSING_SIGNATURE
401 INVALID_SIGNATURE
402 INSUFFICIENT_CREDITS
409 DUPLICATE_IN_PROGRESS
409 DUPLICATE_SUCCEEDED
413 BODY_TOO_LARGE
429 RATE_LIMITED
500 MIRROR_FAILED
```

`DUPLICATE_IN_PROGRESS` means the same address and `.anky` hash is already being processed. `DUPLICATE_SUCCEEDED` means it already succeeded and will not spend again.

## Credit Rules

RevenueCat is the launch credit ledger. The backend uses the checksum address as the RevenueCat customer/App User ID.

Idempotency key:

```txt
sha256(address + ":" + ankyHash)
```

Trial grants require official-app/device proof. A public address alone must not grant trial credits.

Development credit bypass may bypass credits only. It must not bypass request identity verification.

The current tested credit contract is prepare-before-model, spend-after-chargeable-provider-success. A model failure before spend does not charge and does not need a refund. The no-charge default fallback returns safely without spending.

Manual credit support copy:

```txt
my Anky address is <0xChecksumAddress>
```

## Privacy

The backend must not persist:

- raw `.anky`
- reconstructed writing
- prompts containing writing
- reflections
- AI memory
- embeddings
- journal history
- recovery phrases
- private keys
- raw app/device proof tokens

The device remains the writer's archive.

## Forbidden Endpoints

Do not add:

```txt
/register
/session
/me
/wallet
/identity
/login
/profile
/submit
/seal
/proof
/v1/reflections
```

Future ERC-1271 smart-account verification is documented in `docs/FUTURE_SMART_ACCOUNTS.md` and is not a current product feature.
