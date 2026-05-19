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
  autoTrialEnabled: boolean;
  trialCredits: number;
  iosTrialEnabled: boolean;
  iosDeviceCheckRequired: boolean;
  appleDeviceCheckTeamId: string;
  appleDeviceCheckKeyId: string;
  appleDeviceCheckPrivateKey: string;
  appleDeviceCheckEnv: "production" | "development";
  androidTrialEnabled: boolean;
  androidPlayIntegrityRequired: boolean;
  androidPublicKeyTrialsConfirmed: boolean;
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
    autoTrialEnabled: source.ANKY_AUTO_TRIAL_ENABLED === "true",
    trialCredits: numberFromEnv(source.ANKY_TRIAL_CREDITS, 8),
    iosTrialEnabled: source.ANKY_IOS_TRIAL_ENABLED === "true",
    iosDeviceCheckRequired: source.ANKY_IOS_DEVICECHECK_REQUIRED !== "false",
    appleDeviceCheckTeamId: source.APPLE_DEVICECHECK_TEAM_ID ?? "",
    appleDeviceCheckKeyId: source.APPLE_DEVICECHECK_KEY_ID ?? "",
    appleDeviceCheckPrivateKey: source.APPLE_DEVICECHECK_PRIVATE_KEY ?? "",
    appleDeviceCheckEnv:
      source.APPLE_DEVICECHECK_ENV === "development" ? "development" : "production",
    androidTrialEnabled: source.ANKY_ANDROID_TRIAL_ENABLED === "true",
    androidPlayIntegrityRequired: source.ANKY_ANDROID_PLAY_INTEGRITY_REQUIRED !== "false",
    androidPublicKeyTrialsConfirmed: source.ANKY_ANDROID_PUBLIC_KEY_TRIALS_CONFIRMED === "true",
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
    if (
      env.autoTrialEnabled &&
      env.iosTrialEnabled &&
      env.iosDeviceCheckRequired &&
      (
        missingOrPlaceholder(env.appleDeviceCheckTeamId) ||
        missingOrPlaceholder(env.appleDeviceCheckKeyId) ||
        missingOrPlaceholder(env.appleDeviceCheckPrivateKey)
      )
    ) {
      failures.push("Apple DeviceCheck credentials are required when iOS automatic trials are enabled");
    }
    if (
      env.androidTrialEnabled &&
      (!env.androidPublicKeyTrialsConfirmed || env.androidPlayIntegrityRequired)
    ) {
      failures.push(
        "Android automatic trials require ANKY_ANDROID_PUBLIC_KEY_TRIALS_CONFIRMED=true and ANKY_ANDROID_PLAY_INTEGRITY_REQUIRED=false until Play Integrity/device recall is implemented",
      );
    }
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
