# Base Identity Law

Anky identity is Base-native.

The writer identity is a Base account. In the current release that account is a local EOA controlled by a 12-word BIP39 English recovery phrase.

Current descriptor:

```json
{
  "identityVersion": "anky.base.eoa.v1",
  "accountKind": "eoa",
  "chain": "Base",
  "productionChainId": 8453,
  "testChainId": 84532,
  "account": "0xChecksumAddress",
  "recovery": "bip39-english-12-word",
  "derivationPath": "m/44'/60'/0'/0/0",
  "curve": "secp256k1",
  "signingScheme": "eip712"
}
```

The app may call this the writer's "Anky address" or "Base account" in UX. It must not expose a wallet product surface yet: no send, receive, balances, tokens, transaction feed, wallet connect flow, or external wallet requirement.

The 12-word recovery phrase controls the Anky Base account. The phrase never leaves the device. The server does not issue identity, recover identity, or store identity secrets.

There is no register, session, login, profile, account server, or cloud journal.

The active account identity format is:

```txt
0xChecksumAddress
```

Base chain ID remains protocol/server configuration and EIP-712 domain data. It is not embedded in the active user identity string.

The checksum address is the RevenueCat App User ID, credit identity, idempotency identity, and free-credit grant target when official-app/device proof is valid.

Mirror requests are signed with EIP-712 typed data. The `.anky` body remains exact local artifact bytes, sent only to `POST /anky` for reflection.

The `.anky` body is not put on-chain. Reflections are not put on-chain. Any future on-chain action must seal hashes only, never writing text, prompts, reflections, embeddings, or journal history.

Legacy identity material, if present, is legacy only. It may be retained locally for manual support and credit migration, but new `POST /anky` requests must use `anky.base.eoa.v1`.
