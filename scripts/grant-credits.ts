#!/usr/bin/env bun
const [publicKey, amountText] = process.argv.slice(2);

if (!publicKey || !amountText || !/^\d+$/.test(amountText)) {
  console.error("usage: bun run scripts/grant-credits.ts <public-key> <amount>");
  process.exit(1);
}

const amount = Number(amountText);
const secretKey = process.env.REVENUECAT_SECRET_KEY ?? "";
const projectId = process.env.REVENUECAT_PROJECT_ID ?? "";
const creditCode = process.env.REVENUECAT_CREDIT_CODE ?? "CRD";
const idempotencyKey =
  process.env.ANKY_GRANT_CREDITS_IDEMPOTENCY_KEY ??
  `manual-grant:${publicKey}:${amount}:${new Date().toISOString().slice(0, 10)}`;
const dryRun = process.env.ANKY_GRANT_CREDITS_DRY_RUN !== "false";

if (!secretKey || !projectId || !creditCode || dryRun) {
  console.log(
    JSON.stringify(
      {
        status: "stubbed",
        publicKey,
        amount,
        creditCode,
        idempotencyKey,
        message:
          "RevenueCat grant call is not enabled. Set REVENUECAT_SECRET_KEY, REVENUECAT_PROJECT_ID, REVENUECAT_CREDIT_CODE, and ANKY_GRANT_CREDITS_DRY_RUN=false to execute it.",
      },
      null,
      2,
    ),
  );
  process.exit(0);
}

const response = await fetch(
  `https://api.revenuecat.com/v2/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(publicKey)}/virtual_currencies/transactions`,
  {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secretKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify({
      adjustments: {
        [creditCode]: amount,
      },
    }),
  },
);

const body = await response.text();
if (!response.ok) {
  console.error(
    JSON.stringify(
      {
        status: "failed",
        statusCode: response.status,
        publicKey,
        amount,
        creditCode,
        idempotencyKey,
        body,
      },
      null,
      2,
    ),
  );
  process.exit(1);
}

console.log(
  JSON.stringify(
    {
      status: "granted",
      publicKey,
      amount,
      creditCode,
      idempotencyKey,
      revenueCat: JSON.parse(body),
    },
    null,
    2,
  ),
);
