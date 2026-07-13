# App Store subscription resubmission — Anky iOS 1.3.0 (55)

Prepared July 11, 2026. This is the operator runbook for the replacement binary. Repository work does not modify RevenueCat, App Store Connect, or the deployed website.

**Repository-complete:** iOS build/version source, paywall/free path, entitlement lifecycle, six app localizations, bundled legal documents, public legal-route source, tests, privacy documentation, and review copy.

**Still manual:** deploy the landing site; verify and test the live RevenueCat configuration; complete both subscriptions in App Store Connect; archive/upload/select build 55; attach both subscriptions to version 1.3.0; update metadata; submit the app and subscriptions together.

> **iOS invariant: DO NOT USE `anky.yearly` FOR IOS.** The only iOS annual product is `anky.annual`. Android configuration is separate.

## Subscription localizations

Enter these display names and descriptions for both subscription products. The description field allows at most 45 characters. The counts below were measured programmatically as Unicode code points with Bun; grapheme counts are included for clarity.

| Locale | Monthly display name | Annual display name | Description for both | Code points | Graphemes |
| --- | --- | --- | --- | ---: | ---: |
| English | Anky Pro Monthly | Anky Pro Annual | AI reflections, journey & art after level 8 | 43 | 43 |
| Spanish | Anky Pro Mensual | Anky Pro Anual | Reflexiones IA, viaje y arte tras nivel 8 | 41 | 41 |
| French | Anky Pro mensuel | Anky Pro annuel | Réflexions IA, parcours et art après niv. 8 | 43 | 43 |
| German | Anky Pro Monatlich | Anky Pro Jährlich | KI-Reflexionen, Reise und Kunst ab Level 9 | 42 | 42 |
| Simplified Chinese | Anky Pro 月度订阅 | Anky Pro 年度订阅 | AI 反思、96 天旅程与 8 级后艺术 | 20 | 20 |
| Hindi | Anky Pro मासिक | Anky Pro वार्षिक | AI चिंतन, यात्रा और स्तर 8 के बाद कला | 37 | 26 |

Re-run the measurement from the repository root:

```sh
bun -e 'const copy={en:"AI reflections, journey & art after level 8",es:"Reflexiones IA, viaje y arte tras nivel 8",fr:"Réflexions IA, parcours et art après niv. 8",de:"KI-Reflexionen, Reise und Kunst ab Level 9",zhHans:"AI 反思、96 天旅程与 8 级后艺术",hi:"AI चिंतन, यात्रा और स्तर 8 के बाद कला"}; for (const [locale,value] of Object.entries(copy)) console.log(locale,[...value].length,Array.from(new Intl.Segmenter(locale,{granularity:"grapheme"}).segment(value)).length)'
```

## Monthly subscription App Review notes

App Store Connect allows 4,000 characters. The text below is intentionally below that limit.

```text
Product ID: anky.monthly
Duration: 1 month
Introductory offer: none

This auto-renewable subscription grants the RevenueCat entitlement `pro`. It unlocks exactly the same Pro services as the annual product: (1) new server-generated AI reflections for writings without a saved reflection; (2) server-generated AI writing nudges instead of the local fallback; (3) the full 96-day writing journey; (4) automatic rest-of-day Screen Time unlocking after the configured daily writing target is reached; (5) adaptive daily-target suggestions; and (6) personalized painting progression and later painting ceremonies after level 8. Generated services are subject to reasonable service, safety, capacity, generation, and abuse-prevention limits.

Fresh-install path to the paywall: tap “I know.” → “How does it work?” → “Look at my day.” → choose any phone-hours option → “Show me how.” → “Hi, Anky.” → “later” on the optional name screen → “Commit to 8 minutes a day.” → “Begin.” The “Choose Anky Pro” paywall appears. Tap the “Anky Pro Monthly” card, then the button labelled “Subscribe for [localized App Store price] per month.”

Later path: from the painting home screen, tap the top-right gear labelled “Settings” → the first “Subscription” section → its status card. The same paywall opens.

“Restore Purchases” appears below the purchase/free controls and also directly in the Settings Subscription section. “Terms of Use” and “Privacy Policy” are visible links in the paywall footer. During onboarding, “Continue with free writing” finishes onboarding without subscribing; it remains available if products fail to load.

Privacy Policy: https://anky.app/privacy-policy
Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Annual subscription App Review notes

Use this only after App Store Connect confirms the intended three-day free-trial offer is configured for eligible new subscribers.

```text
Product ID: anky.annual
Duration: 1 year
Introductory offer: 3-day free trial for eligible new subscribers

This auto-renewable subscription grants the RevenueCat entitlement `pro`. It unlocks exactly the same Pro services as monthly: (1) new server-generated AI reflections for writings without a saved reflection; (2) server-generated AI writing nudges instead of the local fallback; (3) the full 96-day writing journey; (4) automatic rest-of-day Screen Time unlocking after the configured daily writing target is reached; (5) adaptive daily-target suggestions; and (6) personalized painting progression and later painting ceremonies after level 8. Generated services are subject to reasonable service, safety, capacity, generation, and abuse-prevention limits.

Fresh-install path to the paywall: tap “I know.” → “How does it work?” → “Look at my day.” → choose any phone-hours option → “Show me how.” → “Hi, Anky.” → “later” on the optional name screen → “Commit to 8 minutes a day.” → “Begin.” The “Choose Anky Pro” paywall appears with “Anky Pro Annual” selected. Positively confirmed eligible users see “3 days free” and the “Start 3-day free trial” button. Ineligible, unknown, loading, or eligibility-error states show the normal annual price/renewal terms and “Subscribe for [localized App Store price] per year,” with no trial promise.

Later path: from the painting home screen, tap the top-right gear labelled “Settings” → the first “Subscription” section → its status card. The same paywall opens.

“Restore Purchases” appears below the purchase/free controls and also directly in the Settings Subscription section. “Terms of Use” and “Privacy Policy” are visible links in the paywall footer. During onboarding, “Continue with free writing” finishes onboarding without subscribing; it remains available if products fail to load.

Privacy Policy: https://anky.app/privacy-policy
Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Legal footer for every localized App Store description

Append the matching block to the full app description for every locale. Keep the URLs unmodified.

### English

```text
Privacy Policy: https://anky.app/privacy-policy
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

### Spanish

```text
Política de privacidad: https://anky.app/es/privacy-policy
Términos de uso: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

### French

```text
Politique de confidentialité : https://anky.app/fr/privacy-policy
Conditions d’utilisation : https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

### German

```text
Datenschutzrichtlinie: https://anky.app/de/privacy-policy
Nutzungsbedingungen: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

### Simplified Chinese

```text
隐私政策：https://anky.app/zh-hans/privacy-policy
使用条款：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

### Hindi

```text
गोपनीयता नीति: https://anky.app/hi/privacy-policy
उपयोग की शर्तें: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## RevenueCat manual verification

The repository cannot prove live dashboard state. Perform every item against the production Anky project:

- [ ] In **Apps & providers**, confirm the iOS app/bundle is connected to the intended App Store Connect app and the Release public SDK key is the `appl_…` key used by `AnkyPurchasesConfig`; it must not be a RevenueCat Test Store key.
- [ ] Open **Product catalog → Products**. Confirm an Apple product with identifier exactly `anky.monthly` exists and resolves to the one-month App Store subscription.
- [ ] Confirm an Apple product with identifier exactly `anky.annual` exists and resolves to the one-year App Store subscription.
- [ ] Search the Apple/iOS products and remove any stale `anky.yearly` association from packages offered to iOS. Do not delete or alter a legitimate Android/Google product solely because Android uses that identifier.
- [ ] Open **Product catalog → Entitlements → `pro`**. Confirm the identifier is lowercase `pro` and attach both Apple products `anky.monthly` and `anky.annual`.
- [ ] Open **Product catalog → Offerings → `default`**. Confirm the offering identifier is exactly `default` and that it is available to customers.
- [ ] Confirm the Monthly package in `default` resolves to the Apple `anky.monthly` product and the Annual package resolves to the Apple `anky.annual` product. Both packages must lead to the same `pro` entitlement.
- [ ] Confirm no active Targeting/Experiment result replaces `default` with an offering that omits either iOS product. The binary explicitly loads offering identifier `default`.
- [ ] Under **Project settings → General → Sandbox testing access**, allow the intended sandbox app-user IDs to receive testing entitlements.
- [ ] With a fresh Apple Sandbox account, buy monthly. In **Customers**, open the pseudonymous Anky app-user/writer ID and confirm current `CustomerInfo`/customer state contains active lowercase `pro`, product `anky.monthly`, and App Store sandbox environment.
- [ ] Expire/cancel the sandbox subscription, relaunch from terminated state, and verify `pro` becomes inactive and no new automatic daily unlock is created.
- [ ] With another fresh Sandbox account, buy annual. Confirm active `pro`, product `anky.annual`, the intended trial period for an eligible account, and no trial promise for a known ineligible account.
- [ ] Tap in-app **Restore Purchases** using the same Apple Sandbox account. Confirm active `pro` returns and the RevenueCat customer history records the restore/current entitlement.
- [ ] Test a successful purchase, user cancellation, failed transaction, purchase whose product is deliberately detached from `pro` in a non-production test setup, restore success, and restore with no entitlement. Restore the correct configuration immediately after the negative test.
- [ ] Confirm RevenueCat webhooks continue sending subscription state to the configured Anky backend and that the backend records entitlement `pro` for both products.

## App Store Connect manual verification and submission

- [ ] Open **Apps → Anky → Subscriptions** and the intended subscription group.
- [ ] Confirm `anky.monthly` is an auto-renewable **1 Month** product and `anky.annual` is an auto-renewable **1 Year** product. Product identifiers cannot be corrected after creation; create the correct product if a wrong identifier was used.
- [ ] Confirm both products are in the same subscription group and at the same service level because they provide identical access.
- [ ] For `anky.monthly`, confirm there is **no introductory offer** in any storefront under the current configuration.
- [ ] For `anky.annual`, confirm the intended introductory offer is **Free**, **3 Days**, and available only to eligible new subscribers. If this is not fully configured, do not describe or submit it as having a trial.
- [ ] Complete price schedules, tax category, availability, cleared-for-sale state, and all required agreements/banking/tax prerequisites for both products.
- [ ] Enter all six display-name/description localizations exactly as listed above. Optional promotional artwork may remain empty.
- [ ] Upload a current App Review screenshot for each subscription. Use a screenshot of build 55 showing both titles, explicit 1-month/1-year durations, localized StoreKit prices and periods, automatic-renewal terms, **Restore Purchases**, **Privacy Policy**, and **Terms of Use**. The annual screenshot may show trial language only with positively confirmed eligibility.
- [ ] Paste the matching review note from this document into each product's Review Notes field.
- [ ] Resolve every missing-metadata warning until both subscriptions show **Ready to Submit**.
- [ ] In app version **1.3.0**, select replacement build **55** under Build after upload processing completes.
- [ ] Under the version's **In-App Purchases and Subscriptions** section, attach both `anky.monthly` and `anky.annual`. They must be submitted with the replacement app version, not separately afterward.
- [ ] In **App Privacy**, set the dedicated Privacy Policy URL to `https://anky.app/privacy-policy` (and localized privacy URLs where App Store Connect permits localization).
- [ ] Update all six full App Store descriptions with the matching legal footer above. This is the Terms of Use metadata remediation; do not rely only on the Privacy Policy URL field.
- [ ] Verify the support/marketing URLs remain functional and no old raw Markdown legal URL is used.
- [ ] Complete the App Privacy questionnaire using `apps/ios/NUTRITION_LABEL.md`, then publish those responses.
- [ ] Submit version 1.3.0 build 55 and both subscriptions together for review.

**DO NOT USE `anky.yearly` FOR IOS.**

## Reviewer response

Do not paste this until the replacement binary has been uploaded/selected, both subscriptions have reached Ready to Submit and are attached to the app version, the legal website has been deployed, and the localized App Store descriptions have been updated.

```text
Thank you for the review guidance. We uploaded and selected replacement binary Anky 1.3.0 (55) and submitted both auto-renewable subscriptions with this app version: `anky.monthly` (1 month, no introductory offer) and `anky.annual` (1 year, with a 3-day free trial only for eligible new subscribers). Both products grant the same lowercase RevenueCat entitlement, `pro`, and are in the same subscription group/service level.

The replacement binary corrects subscription presentation: it shows conspicuous localized monthly/annual titles, explicit durations, complete localized App Store prices and billing periods, renewal terms, the exact Pro services, Restore Purchases, and functional Privacy Policy and Terms of Use links. Annual trial language and its trial-specific button now appear only after StoreKit/RevenueCat positively confirms eligibility; unknown, unavailable, failed, and ineligible states show ordinary annual purchase terms. Monthly does not show a trial.

Fresh users can choose “Continue with free writing” during onboarding, including while products are unavailable. Writing, local history, the Screen Time gate, Quick Passes, emergency access, saved reflections, and static painting levels 1–8 remain available without Pro. We also fixed stale cached entitlement handling so an expired subscription cannot create a new paid automatic daily unlock before current verification.

We removed stale virtual-currency-era and hardcoded-price language, corrected free-versus-Pro descriptions, and updated all six bundled and public legal localizations. The paywall links directly to:
Privacy Policy: https://anky.app/privacy-policy
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

The App Store description in every supported locale now includes Terms of Use and Privacy Policy information. Current subscription screenshots and review notes are attached to both products.
```

## Landing deployment (do not run until approved)

Build and verify from the landing app:

```sh
cd ~/anky/apps/landing
bun install
bun run test
bun run lint
bun run build
```

The established deployment entry point is:

```sh
cd ~/anky/apps/landing
make deploy
```

That Make target runs:

```sh
bun run build
bunx wrangler pages deploy dist --project-name anky-landing --branch main --commit-dirty=true
```

Do not deploy as part of repository preparation. After an authorized deployment, verify every canonical and legacy URL in a private browser window and from an external network before submitting to App Review.
