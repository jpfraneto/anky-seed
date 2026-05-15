export type Env = {
  ankyEnv: string;
  nodeEnv: string;
  port: number;
  host: string;
  devBypassCredits: boolean;
  devMockMirror: boolean;
  mirrorDisabled: boolean;
  maxBodyBytes: number;
  openrouterApiKey: string;
  openrouterModel: string;
  openrouterTimeoutMs: number;
  openrouterPrivacyConfirmed: boolean;
  revenueCatSecretKey: string;
  revenueCatProjectId: string;
  revenueCatCreditCode: string;
  requestTimeToleranceMs: number;
};

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  return {
    ankyEnv: source.ANKY_ENV ?? "",
    nodeEnv: source.NODE_ENV ?? "",
    port: numberFromEnv(source.PORT, 3000),
    host: source.HOST ?? "0.0.0.0",
    devBypassCredits: source.ANKY_DEV_BYPASS_CREDITS === "true",
    devMockMirror: source.ANKY_DEV_MOCK_MIRROR === "true",
    mirrorDisabled: source.ANKY_MIRROR_DISABLED === "true",
    maxBodyBytes: numberFromEnv(source.ANKY_MAX_BODY_BYTES, 1_048_576),
    openrouterApiKey: source.OPENROUTER_API_KEY ?? "",
    openrouterModel: source.OPENROUTER_MODEL ?? "",
    openrouterTimeoutMs: numberFromEnv(source.OPENROUTER_TIMEOUT_MS, 45000),
    openrouterPrivacyConfirmed: source.OPENROUTER_PRIVACY_CONFIRMED === "true",
    revenueCatSecretKey: source.REVENUECAT_SECRET_KEY ?? "",
    revenueCatProjectId: source.REVENUECAT_PROJECT_ID ?? "",
    revenueCatCreditCode: source.REVENUECAT_CREDIT_CODE ?? "CRD",
    requestTimeToleranceMs: numberFromEnv(source.REQUEST_TIME_TOLERANCE_MS, 300000),
  };
}

export function isProductionEnv(env: Pick<Env, "ankyEnv" | "nodeEnv">): boolean {
  return env.ankyEnv === "production" || env.nodeEnv === "production";
}

export function assertProductionSafe(env: Env): void {
  if (!isProductionEnv(env)) return;

  const failures: string[] = [];
  if (env.devBypassCredits) failures.push("ANKY_DEV_BYPASS_CREDITS must not be true");
  if (env.devMockMirror) failures.push("ANKY_DEV_MOCK_MIRROR must not be true");

  if (!env.mirrorDisabled) {
    if (missingOrPlaceholder(env.openrouterApiKey)) failures.push("OPENROUTER_API_KEY is required");
    if (missingOrPlaceholder(env.openrouterModel)) failures.push("OPENROUTER_MODEL is required");
    if (!env.openrouterPrivacyConfirmed) {
      failures.push("OPENROUTER_PRIVACY_CONFIRMED=true is required after routing privacy has been verified");
    }
    if (missingOrPlaceholder(env.revenueCatSecretKey)) failures.push("REVENUECAT_SECRET_KEY is required");
    if (missingOrPlaceholder(env.revenueCatProjectId)) failures.push("REVENUECAT_PROJECT_ID is required");
    if (missingOrPlaceholder(env.revenueCatCreditCode)) failures.push("REVENUECAT_CREDIT_CODE is required");
  }

  if (failures.length > 0) {
    throw new Error(`Unsafe production mirror configuration:\n- ${failures.join("\n- ")}`);
  }
}

function numberFromEnv(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function missingOrPlaceholder(value: string): boolean {
  return !value || value.startsWith("REPLACE_WITH_") || value === "...";
}
