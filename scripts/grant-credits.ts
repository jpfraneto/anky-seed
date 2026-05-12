#!/usr/bin/env bun
const [publicKey, amountText] = process.argv.slice(2);

if (!publicKey || !amountText || !/^\d+$/.test(amountText)) {
  console.error("usage: bun run scripts/grant-credits.ts <public-key> <amount>");
  process.exit(1);
}

const amount = Number(amountText);
const secretKey = process.env.REVENUECAT_SECRET_KEY ?? "";
const projectId = process.env.REVENUECAT_PROJECT_ID ?? "";
const dryRun = process.env.ANKY_GRANT_CREDITS_DRY_RUN !== "false";

if (!secretKey || !projectId || dryRun) {
  console.log(
    JSON.stringify(
      {
        status: "stubbed",
        publicKey,
        amount,
        message:
          "RevenueCat grant call is not enabled. Set REVENUECAT_SECRET_KEY, REVENUECAT_PROJECT_ID, and ANKY_GRANT_CREDITS_DRY_RUN=false to wire the provider call.",
      },
      null,
      2,
    ),
  );
  process.exit(0);
}

console.error("RevenueCat grant endpoint is not implemented in this foundation pass.");
process.exit(1);
