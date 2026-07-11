import { describe, expect, test } from "bun:test";
import {
  canonicalLegalRoutes,
  normalizePathname,
  resolveLegalRoute,
} from "../src/legalRoutes";

const expectedPublicRoutes = [
  "/privacy-policy",
  "/terms",
  "/es/privacy-policy",
  "/es/terms",
  "/fr/privacy-policy",
  "/fr/terms",
  "/de/privacy-policy",
  "/de/terms",
  "/zh-hans/privacy-policy",
  "/zh-hans/terms",
  "/hi/privacy-policy",
  "/hi/terms",
] as const;

describe("public legal routes", () => {
  test("all canonical privacy and terms routes resolve without a trailing slash", () => {
    for (const path of expectedPublicRoutes) {
      const resolved = resolveLegalRoute(path);
      expect(resolved, path).toBeDefined();
      expect(resolved?.canonicalPath).toBe(path);
    }
  });

  test("a refresh-style trailing slash resolves to the same document", () => {
    for (const path of expectedPublicRoutes) {
      expect(resolveLegalRoute(`${path}/`)?.canonicalPath).toBe(path);
    }
    expect(normalizePathname("/terms///")).toBe("/terms");
  });

  test("legacy aliases resolve only to corrected canonical documents", () => {
    expect(resolveLegalRoute("/privacy")?.canonicalPath).toBe("/privacy-policy");
    expect(resolveLegalRoute("/privacy-policy-french")?.canonicalPath).toBe(
      "/fr/privacy-policy",
    );
    expect(resolveLegalRoute("/terms-and-conditions")?.canonicalPath).toBe(
      "/terms",
    );
    expect(resolveLegalRoute("/terms-of-service")?.canonicalPath).toBe(
      "/terms",
    );
  });

  test("each document has localized language and page metadata", () => {
    const legal = canonicalLegalRoutes.filter((item) => item.kind !== "protocol");
    expect(legal).toHaveLength(12);
    for (const item of legal) {
      expect(item.label.length).toBeGreaterThan(0);
      expect(item.pageTitle).toContain("Anky");
      expect(["en", "es", "fr", "de", "zh-Hans", "hi"]).toContain(item.locale);
    }
  });
});

describe("shared canonical legal content", () => {
  const localeDirectories = ["en", "es", "fr", "de", "zh-Hans", "hi"];
  const iosAnky = new URL("../../ios/Anky/", import.meta.url);

  test("all six bundled privacy and terms documents exist and are current", async () => {
    for (const locale of localeDirectories) {
      for (const name of ["PrivacyPolicy.md", "TermsAndConditions.md"]) {
        const file = Bun.file(new URL(`${locale}.lproj/${name}`, iosAnky));
        expect(await file.exists(), `${locale}/${name}`).toBe(true);
        const content = await file.text();
        expect(content).toContain("2026");
        expect(content).toContain("pro");
        expect(content).not.toMatch(/\$11\.99|\$88(?:\.00|\.90)?/);
        expect(content).not.toContain("DeviceCheck");
      }
    }
  });

  test("hosting redirects point legacy paths at canonical SPA routes", async () => {
    const redirects = await Bun.file(new URL("../public/_redirects", import.meta.url)).text();
    expect(redirects).toContain("/privacy /privacy-policy 301");
    expect(redirects).toContain("/privacy-policy-french /fr/privacy-policy 301");
    expect(redirects).toContain("/* /index.html 200");
    expect(redirects).not.toMatch(/privacy-policy\.md|terms-of-service\.md/);
  });

  test("the legal renderer creates functional inline links", async () => {
    const source = await Bun.file(
      new URL("../src/components/LegalPage.tsx", import.meta.url),
    ).text();
    expect(source).toContain("normalized.matchAll(linkPattern)");
    expect(source).toContain("href={match[2]}");
  });
});
