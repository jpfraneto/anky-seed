# Anky Base Identity Protocol

Current identity version: `anky.base.eoa.v1`

The writer identity is a Base/EVM account controlled locally by a 12-word BIP39 English recovery phrase.

## Descriptor

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

The recovery phrase and private key never leave the device. The EIP-55 checksum address is the writer identity, RevenueCat App User ID, credit identity, and idempotency identity. Chain ID stays in configuration and the EIP-712 domain.

## Mirror Request Signing

`POST /anky` sends the exact `.anky` UTF-8 bytes as `text/plain; charset=utf-8`. The body is not wrapped in JSON.

Headers:

```txt
X-Anky-Identity-Version: anky.base.eoa.v1
X-Anky-Account: 0xChecksumAddress
X-Anky-Signature-Type: eip712
X-Anky-Signature: 0x...
X-Anky-Request-Time: <epoch_ms>
X-Anky-Client: ios | android | other
```

The server computes SHA-256 over the exact received body bytes and represents the result as a `0x`-prefixed `bytes32`.

EIP-712 domain:

```json
{
  "name": "Anky",
  "version": "1",
  "chainId": 8453
}
```

Primary type:

```txt
AnkyMirrorRequest(
  string identityVersion,
  address account,
  string method,
  string path,
  bytes32 bodyHash,
  uint64 requestTime,
  string client
)
```

The server recovers the signer from the typed-data signature and requires it to equal the address inside `X-Anky-Account`.

## Fixtures

The fixtures under `protocol/identity/fixtures` use the public BIP39 test mnemonic:

```txt
abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
```

This mnemonic is public test-only material and must never be used for production identity.

## Future Smart Accounts

The reserved future version is `anky.base.erc1271.v1`. It will verify the EIP-712 digest with ERC-1271 `isValidSignature(hash, signature)` and accepted magic value `0x1626ba7e`. This protocol does not implement RPC calls, smart-account creation, WalletConnect, Coinbase Smart Wallet, Privy, or ERC-4337.
