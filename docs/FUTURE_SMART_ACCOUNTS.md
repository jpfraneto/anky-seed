# Future Smart Accounts

The current release does not implement smart wallets.

Current supported identity:

```txt
identityVersion: anky.base.eoa.v1
accountKind: eoa
verification: EIP-712 EOA signature recovery
```

Future possible identity:

```txt
identityVersion: anky.base.erc1271.v1
accountKind: erc1271
verification: EIP-712 digest + ERC-1271 isValidSignature(hash, signature)
accepted magic value: 0x1626ba7e
```

Smart accounts would be controllers/verifiers for the writer identity. They would not become a writing archive, journal database, memory system, or reflection store.

ERC-1271 is useful later because contract accounts cannot be verified by EOA signature recovery alone. The mirror can eventually compute the same EIP-712 digest and ask the contract account whether the signature is valid.

ERC-4337 is only relevant later if Anky wants transaction execution or account abstraction. It is not needed for local-first writing identity and mirror request authentication.

This release intentionally does not add:

- smart-account creation
- Coinbase Smart Wallet
- Privy
- WalletConnect
- MetaMask integration
- ERC-4337 UserOperations
- wallet UI
- send/receive UI
- balance/token UI
- on-chain `.anky` storage
- on-chain reflection storage
- RPC calls in the mirror auth path
