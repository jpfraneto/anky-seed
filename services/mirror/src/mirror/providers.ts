import type { Env } from "../env";
import { parseMirrorResponse, type MirrorResponse } from "./parseMirrorResponse";

type ProviderFetch = (url: string, init: RequestInit) => Promise<Response>;

export type ProviderPrivacy = {
  zeroDataRetentionConfirmed: boolean;
  contentLoggingDisabled: boolean;
  trainingDisabled: boolean;
};

export type ReflectionProviderResult = MirrorResponse & {
  provider: string;
  chargeable: boolean;
};

export type ReflectionProvider = {
  name: string;
  privacy: ProviderPrivacy;
  reflect(input: { env: Env; prompt: string; fetchImpl?: ProviderFetch }): Promise<ReflectionProviderResult>;
};

export async function routeReflection(input: {
  env: Env;
  prompt: string;
  fetchImpl?: ProviderFetch;
  providers?: ReflectionProvider[];
}): Promise<ReflectionProviderResult> {
  const providers = input.providers ?? providersForEnv(input.env);
  const failures: string[] = [];

  for (const provider of providers) {
    if (input.env.requireZdr && !providerMeetsZdr(provider.privacy)) {
      failures.push(`${provider.name}:ZDR_NOT_CONFIRMED`);
      continue;
    }
    try {
      return await provider.reflect({ env: input.env, prompt: input.prompt, fetchImpl: input.fetchImpl });
    } catch (error) {
      failures.push(`${provider.name}:${safeProviderFailure(error)}`);
    }
  }

  throw new Error(`PROVIDERS_FAILED:${failures.join(",")}`);
}

export function providersForEnv(env: Env): ReflectionProvider[] {
  const byName: Record<string, ReflectionProvider> = {
    openrouter: openRouterProvider,
    bankr: providerWithPrivacy(bankrProvider, env.bankrZdrConfirmed),
    poiesis: providerWithPrivacy(poiesisProvider, env.poiesisZdrConfirmed),
    default: defaultFallbackProvider,
  };
  return env.providerOrder.map((name) => byName[name]).filter((provider): provider is ReflectionProvider => Boolean(provider));
}

export function providerMeetsZdr(privacy: ProviderPrivacy): boolean {
  return privacy.zeroDataRetentionConfirmed && privacy.contentLoggingDisabled && privacy.trainingDisabled;
}

export const openRouterProvider: ReflectionProvider = {
  name: "openrouter",
  privacy: {
    zeroDataRetentionConfirmed: true,
    contentLoggingDisabled: true,
    trainingDisabled: true,
  },
  async reflect(input) {
    if (input.env.devMockMirror) {
      return {
        provider: "mock",
        chargeable: false,
        title: "Small Steady Thread",
        reflection: "Here is what I saw: a brief thread held without needing to become anything else.",
      };
    }

    if (!input.env.openrouterApiKey || !input.env.openrouterModel) {
      throw new Error("OPENROUTER_NOT_CONFIGURED");
    }
    if (!input.env.openrouterPrivacyConfirmed) {
      throw new Error("OPENROUTER_ZDR_NOT_CONFIRMED");
    }

    const fetcher = input.fetchImpl ?? fetch;
    const response = await fetcher("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      signal: AbortSignal.timeout(input.env.openrouterTimeoutMs),
      headers: {
        Authorization: `Bearer ${input.env.openrouterApiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://anky.app",
        "X-Title": "Anky Mirror",
      },
      body: JSON.stringify({
        model: input.env.openrouterModel,
        messages: [{ role: "user", content: input.prompt }],
        response_format: { type: "json_object" },
        provider: { data_collection: "deny", zdr: true },
      }),
    });

    if (!response.ok) throw new Error(`OPENROUTER_HTTP_${response.status}`);
    const json = await response.json() as { choices?: Array<{ message?: { content?: unknown } }> };
    const content = json?.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("OPENROUTER_EMPTY");
    return { ...parseMirrorResponse(content), provider: "openrouter", chargeable: true };
  },
};

export const bankrProvider: ReflectionProvider = {
  name: "bankr",
  privacy: {
    zeroDataRetentionConfirmed: false,
    contentLoggingDisabled: false,
    trainingDisabled: false,
  },
  async reflect(input) {
    if (!input.env.bankrZdrConfirmed) throw new Error("BANKR_ZDR_NOT_CONFIRMED");
    if (!input.env.bankrLlmGatewayUrl || !input.env.bankrLlmGatewayApiKey) throw new Error("BANKR_NOT_CONFIGURED");
    throw new Error("BANKR_ADAPTER_STAGED");
  },
};

export const poiesisProvider: ReflectionProvider = {
  name: "poiesis",
  privacy: {
    zeroDataRetentionConfirmed: false,
    contentLoggingDisabled: false,
    trainingDisabled: false,
  },
  async reflect(input) {
    if (!input.env.poiesisZdrConfirmed) throw new Error("POIESIS_ZDR_NOT_CONFIRMED");
    if (!input.env.poiesisLlmUrl || !input.env.poiesisLlmApiKey) throw new Error("POIESIS_NOT_CONFIGURED");
    throw new Error("POIESIS_ADAPTER_STAGED");
  },
};

export const defaultFallbackProvider: ReflectionProvider = {
  name: "default",
  privacy: {
    zeroDataRetentionConfirmed: true,
    contentLoggingDisabled: true,
    trainingDisabled: true,
  },
  async reflect() {
    return {
      provider: "default",
      chargeable: false,
      title: "mirror unavailable",
      reflection: "hey, thanks for being who you are. my thoughts:\n\nAnky could not safely reach a confirmed private reflection provider right now. Your writing remains on this device. No credit was spent.",
    };
  },
};

function safeProviderFailure(error: unknown): string {
  if (!(error instanceof Error)) return "UNKNOWN";
  if (/^[A-Z0-9_]+$/.test(error.message)) return error.message;
  if (/^OPENROUTER_HTTP_\d{3}$/.test(error.message)) return error.message;
  if (error.name === "TimeoutError" || error.name === "AbortError") return "PROVIDER_TIMEOUT";
  return "PROVIDER_FAILED";
}

function providerWithPrivacy(provider: ReflectionProvider, confirmed: boolean): ReflectionProvider {
  return {
    ...provider,
    privacy: {
      zeroDataRetentionConfirmed: confirmed,
      contentLoggingDisabled: confirmed,
      trainingDisabled: confirmed,
    },
  };
}
