# Wallet-Funded Credits

RevenueCat remains the launch credit ledger. Anky should not ship a wallet dashboard, token list, balances, send/receive screens, or broad transaction UI in this pass.

Future direction:

- A writer may eventually fund reflection credits with Base USDC from their Anky address.
- The mirror/server side should use a `WalletCreditFundingProvider` interface, not product endpoints that expose wallet behavior broadly.
- Reconciliation must grant credits only after a confirmed Base USDC payment maps to one Anky address and one credit quote/reference.
- RevenueCat and wallet-funded credits need an explicit reconciliation rule before production: no double grants, no silent balance merging, no credit spend before reflection success.
- Veil.cash/privacy funding is only a placeholder until contracts, docs, risk review, env, and integration tests exist.

Current placeholder:

- `services/mirror/src/index.ts`
- `VeilCashFundingProviderPlaceholder` fails closed with `VEIL_CASH_INTEGRATION_NOT_CONFIGURED`.

No production transaction flow is implemented here.
