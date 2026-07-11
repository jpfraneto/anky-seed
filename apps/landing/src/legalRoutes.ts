export type LegalLocale = "en" | "es" | "fr" | "de" | "zh-Hans" | "hi";
export type LegalDocumentKind = "protocol" | "privacy" | "terms";

export type LegalRoute = {
  canonicalPath: string;
  kind: LegalDocumentKind;
  label: string;
  locale: LegalLocale;
  pageTitle: string;
};

const route = (
  canonicalPath: string,
  kind: LegalDocumentKind,
  locale: LegalLocale,
  label: string,
  pageTitle: string,
): LegalRoute => ({ canonicalPath, kind, label, locale, pageTitle });

const protocol = route("/protocol", "protocol", "en", "Protocol", "Anky Protocol");
const privacyEN = route(
  "/privacy-policy",
  "privacy",
  "en",
  "Privacy",
  "Anky Privacy Policy",
);
const termsEN = route("/terms", "terms", "en", "Terms", "Anky Terms of Use");
const privacyES = route(
  "/es/privacy-policy",
  "privacy",
  "es",
  "Privacidad",
  "Política de privacidad de Anky",
);
const termsES = route(
  "/es/terms",
  "terms",
  "es",
  "Términos",
  "Términos de uso de Anky",
);
const privacyFR = route(
  "/fr/privacy-policy",
  "privacy",
  "fr",
  "Confidentialité",
  "Politique de confidentialité d’Anky",
);
const termsFR = route(
  "/fr/terms",
  "terms",
  "fr",
  "Conditions",
  "Conditions d’utilisation d’Anky",
);
const privacyDE = route(
  "/de/privacy-policy",
  "privacy",
  "de",
  "Datenschutz",
  "Anky-Datenschutzrichtlinie",
);
const termsDE = route(
  "/de/terms",
  "terms",
  "de",
  "Bedingungen",
  "Anky-Nutzungsbedingungen",
);
const privacyZH = route(
  "/zh-hans/privacy-policy",
  "privacy",
  "zh-Hans",
  "隐私政策",
  "Anky 隐私政策",
);
const termsZH = route(
  "/zh-hans/terms",
  "terms",
  "zh-Hans",
  "使用条款",
  "Anky 使用条款",
);
const privacyHI = route(
  "/hi/privacy-policy",
  "privacy",
  "hi",
  "गोपनीयता",
  "Anky गोपनीयता नीति",
);
const termsHI = route(
  "/hi/terms",
  "terms",
  "hi",
  "शर्तें",
  "Anky उपयोग की शर्तें",
);

const routes = new Map<string, LegalRoute>([
  ["/protocol", protocol],
  ["/privacy-policy", privacyEN],
  ["/privacy", privacyEN],
  ["/terms", termsEN],
  ["/terms-and-conditions", termsEN],
  ["/terms-of-service", termsEN],
  ["/es/privacy-policy", privacyES],
  ["/es/terms", termsES],
  ["/fr/privacy-policy", privacyFR],
  ["/fr/terms", termsFR],
  ["/de/privacy-policy", privacyDE],
  ["/de/terms", termsDE],
  ["/zh-hans/privacy-policy", privacyZH],
  ["/zh-hans/terms", termsZH],
  ["/hi/privacy-policy", privacyHI],
  ["/hi/terms", termsHI],
  ["/privacy-policy-french", privacyFR],
  ["/privacy-policy-espanol", privacyES],
  ["/politica-de-privacidad", privacyES],
  ["/privacy-policy-german", privacyDE],
  ["/privacy-policy-chinese", privacyZH],
  ["/privacy-policy-hindi", privacyHI],
]);

export const canonicalLegalRoutes = [
  protocol,
  privacyEN,
  termsEN,
  privacyES,
  termsES,
  privacyFR,
  termsFR,
  privacyDE,
  termsDE,
  privacyZH,
  termsZH,
  privacyHI,
  termsHI,
] as const;

export function normalizePathname(pathname: string): string {
  if (pathname === "/") return pathname;
  return pathname.replace(/\/+$/, "") || "/";
}

export function resolveLegalRoute(pathname: string): LegalRoute | undefined {
  return routes.get(normalizePathname(pathname).toLowerCase());
}
