export type Env = {
  port: number;
  devBypassCredits: boolean;
  devMockMirror: boolean;
  openrouterApiKey: string;
  openrouterModel: string;
  revenueCatSecretKey: string;
  revenueCatProjectId: string;
  requestTimeToleranceMs: number;
};

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  return {
    port: numberFromEnv(source.PORT, 3000),
    devBypassCredits: source.ANKY_DEV_BYPASS_CREDITS === "true",
    devMockMirror: source.ANKY_DEV_MOCK_MIRROR === "true",
    openrouterApiKey: source.OPENROUTER_API_KEY ?? "",
    openrouterModel: source.OPENROUTER_MODEL ?? "",
    revenueCatSecretKey: source.REVENUECAT_SECRET_KEY ?? "",
    revenueCatProjectId: source.REVENUECAT_PROJECT_ID ?? "",
    requestTimeToleranceMs: numberFromEnv(source.REQUEST_TIME_TOLERANCE_MS, 300000),
  };
}

function numberFromEnv(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}
