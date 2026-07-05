# Continuity Contracts

Foundry project for `Continuity`, deployed from `src/ANKY_MIRRORS.sol`.

## Contract

- Collection: `Continuity`
- Symbol: `MIRROR`
- Max supply: `888`
- Base mint price: `0.0037 ETH`
- Holder mint price: `0.00185 ETH`
- Discount rule: claiming wallet must hold more than `8,000,000 $ANKY`
- `$ANKY` token: `0x323e74C31915db296b82B032f9665924F31efBA3` on Base

Claims are authorized by an EIP-712 signature from `ANKY_MIRRORS_MINT_SIGNER`.
Each FID and each claiming wallet can open one mirror.

## Gifts

Mirrors can be prepaid for a specific FID with `giftMirror`.

- Gifts do not expire.
- A gift reserves one of the `888` mirrors until the gifted FID claims.
- The sponsor pays `priceFor(sponsorWallet)`, so `$ANKY` holder discounts apply to the sponsor.
- The gifted FID later claims with `0 ETH`.
- Sponsorship history is permanent: `sponsorOfFid`, `sponsorFidOfFid`, and `sponsoredPricePaid` are not deleted after claim.
- Sponsor FID history is queryable with `getSponsoredFidsByFid(sponsorFid)`.

`giftMirror` requires an EIP-712 `MirrorGift` signature from `ANKY_MIRRORS_MINT_SIGNER` so the `sponsorFid => giftedFids` ledger cannot be spoofed by arbitrary callers.

## Setup

```sh
cp .env.example .env
```

Fill in:

- `PRIVATE_KEY`: deployer private key
- `BASE_RPC_URL`: Base RPC URL
- `BASESCAN_API_KEY`: Basescan API key for verification
- `ANKY_MIRRORS_OWNER`: owner/admin address
- `ANKY_MIRRORS_MINT_SIGNER`: backend signer for claim/finalization authorization
- `ANKY_MIRRORS_TREASURY`: withdrawal recipient
- `ANKY_MIRRORS_CONTRACT_URI`: collection metadata URI

## Build And Test

```sh
forge build
forge test
```

## Deploy

Dry run on Base:

```sh
source .env
forge script script/DeployAnkyMirrors.s.sol:DeployAnkyMirrors \
  --rpc-url "$BASE_RPC_URL"
```

Broadcast and verify on Base mainnet:

```sh
source .env
forge script script/DeployAnkyMirrors.s.sol:DeployAnkyMirrors \
  --rpc-url "$BASE_RPC_URL" \
  --broadcast \
  --verify \
  --chain 8453 \
  --etherscan-api-key "$BASESCAN_API_KEY"
```

The deployment script reads constructor args from `.env` and does not pass them on the command line.
