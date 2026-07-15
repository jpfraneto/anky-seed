import RevenueCat
import SwiftUI

/// The single subscription presentation used during onboarding, from Pro
/// veils, after lapse, and from Settings. StoreKit supplies every price;
/// RevenueCat supplies current entitlement and trial eligibility.
struct PaywallView: View {
    enum Context {
        case onboarding
        case lapsed
        case veil(origin: String)

        var isOnboarding: Bool {
            if case .onboarding = self { return true }
            return false
        }
    }

    private enum Plan {
        case annual
        case monthly
    }

    @ObservedObject var store: EntitlementStore
    let context: Context
    let onCompleted: () -> Void

    @State private var plan: Plan = .annual

    /// Onboarding renders inside a fixed, non-scrolling budget, so the ask is
    /// tightened to a single screen: no voice paragraph, a smaller image, a
    /// condensed benefit list, and closer spacing. The lapsed/veil sheets keep
    /// the fuller layout since they already scroll.
    private var isCompact: Bool { context.isOnboarding }

    var body: some View {
        VStack(spacing: isCompact ? 11 : 16) {
            paywallImage

            Text(AnkyLocalization.ui(titleText))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)

            if !isCompact {
                Text(AnkyLocalization.ui(voiceLine))
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            proBenefits

            if !store.isEntitledForGating {
                planSelector
            }

            Text(AnkyLocalization.ui(paymentLine))
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .accessibilityIdentifier("paywall.renewalTerms")

            if let errorLine = store.purchaseErrorLine, !store.isEntitledForGating {
                statusLine(errorLine, color: Color.ankyMadder.opacity(0.9))
            }

            if let restoreLine = store.restoreStatusLine, !store.isEntitledForGating {
                statusLine(restoreLine, color: Color.ankyInkSoft)
            }

            if shouldShowRetry {
                retryBlock
            }

            purchaseCTA

            footer
        }
        .task {
            await refreshStorePresentation()
        }
        .onAppear {
            if !store.isEntitledForGating {
                AnkyFunnel.report(AnkyFunnel.paywallShown, origin: funnelOrigin)
                PaywallPressureLedger.recordPaywallShown()
            }
        }
    }

    private var paywallImage: some View {
        Image("anky-flow-paywall")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: isCompact ? 186 : 250)
            .frame(height: isCompact ? 126 : 210)
            .shadow(color: Color.ankyGold.opacity(0.12), radius: 14, y: 5)
            .accessibilityHidden(true)
    }

    // MARK: Copy

    private var titleText: String {
        if store.isEntitledForGating {
            if store.isPromotionalEntitlement {
                return "Anky Pro is active — a gift"
            }
            return store.isInIntroTrialForGating ? "Your Anky Pro trial is active" : "Anky Pro is active"
        }
        switch context {
        case .onboarding:
            return "Choose Anky Pro"
        case .lapsed:
            return "Renew Anky Pro"
        case .veil:
            return "Anky Pro"
        }
    }

    private var voiceLine: String {
        if store.isEntitledForGating {
            if store.isPromotionalEntitlement {
                return "Your Pro access was granted. Nothing is charged and nothing renews."
            }
            return "Both subscription durations unlock the same Anky Pro features."
        }
        switch context {
        case .onboarding:
            return "Writing, local history, the Screen Time gate, Quick Passes, emergency access, and painting levels 1–8 remain free."
        case .lapsed:
            return "Your writing, saved reflections, gate, Quick Passes, emergency access, and delivered paintings remain yours. Renew only for Pro features."
        case .veil:
            return "Unlock new AI reflections and nudges, the 96-day journey, automatic target unlocking, adaptive suggestions, and personalized paintings after level 8."
        }
    }

    private var proBenefits: some View {
        VStack(alignment: .leading, spacing: isCompact ? 7 : 9) {
            Text(AnkyLocalization.ui("Anky Pro includes"))
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.ankyMadder.opacity(0.85))

            ForEach(benefitLines, id: \.self) { benefit($0) }
        }
        .padding(isCompact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.ankyPaper.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.ankyGold.opacity(0.32), lineWidth: 0.7)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.proBenefits")
    }

    private var benefitLines: [String] {
        if isCompact {
            return [
                "New AI reflections and writing nudges, subject to service limits",
                "Automatic rest-of-day unlocking and adaptive daily targets",
            ]
        }
        return [
            "AI reflections and writing nudges, subject to service limits",
            "Full access to the 96-day writing journey",
            "Automatic rest-of-day unlock after reaching your target",
            "Adaptive daily-target suggestions",
            "Personalized painting progression after level 8, subject to progress and service limits",
        ]
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ankyGold)
            Text(AnkyLocalization.ui(text))
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var paymentLine: String {
        if store.isEntitledForGating {
            return activeSubscriptionLine
        }
        guard let price = selectedPrice else {
            return store.isLoadingPackages
                ? "The price is settling in…"
                : "This plan is unavailable right now. Retry, restore purchases, or continue with free writing."
        }
        switch plan {
        case .annual where annualTrialIsConfirmed:
            return AnkyLocalization.ui(
                "Annual trial renewal disclosure format",
                price
            )
        case .annual:
            return AnkyLocalization.ui(
                "Annual renewal disclosure format",
                price
            )
        case .monthly:
            return AnkyLocalization.ui(
                "Monthly renewal disclosure format",
                price
            )
        }
    }

    private var activeSubscriptionLine: String {
        if store.isPromotionalEntitlement {
            guard let endDate = store.activeExpirationDate else {
                return "Complimentary Pro access is open-ended. Nothing is charged and nothing renews."
            }
            return AnkyLocalization.ui(
                "Complimentary Pro access through date format",
                endDate.formatted(date: .abbreviated, time: .omitted)
            )
        }
        guard let renewalDate = store.activeRenewalDate else {
            return "Your subscription is active on this Apple ID. Manage it in App Store subscriptions."
        }
        let date = renewalDate.formatted(date: .abbreviated, time: .omitted)
        if let price = activePriceAndPeriod {
            if store.isInIntroTrialForGating {
                return AnkyLocalization.ui("Active trial renewal format", date, price)
            }
            return AnkyLocalization.ui("Active subscription renewal format", date, price)
        }
        return AnkyLocalization.ui("Active subscription renewal date format", date)
    }

    private var activePriceAndPeriod: String? {
        guard let price = SubscriptionPriceFormatter.price(store.activePackage?.storeProduct) else {
            return nil
        }
        if store.activeProductID == AnkyPurchasesConfig.monthlyProductID {
            return AnkyLocalization.ui("price per month format", price)
        }
        if store.activeProductID == AnkyPurchasesConfig.annualProductID {
            return AnkyLocalization.ui("price per year format", price)
        }
        return price
    }

    private var funnelOrigin: String {
        switch context {
        case .onboarding:
            return "onboarding"
        case .lapsed:
            return "lapsed"
        case .veil(let origin):
            return origin
        }
    }

    // MARK: Plans

    private var planSelector: some View {
        VStack(spacing: isCompact ? 8 : 10) {
            planOption(
                .annual,
                title: store.annualPackage?.storeProduct.localizedTitle
                    ?? AnkyLocalization.ui("Anky Pro Annual"),
                detail: annualDetail
            )
            planOption(
                .monthly,
                title: store.monthlyPackage?.storeProduct.localizedTitle
                    ?? AnkyLocalization.ui("Anky Pro Monthly"),
                detail: monthlyDetail
            )
        }
        .accessibilityIdentifier("paywall.planSelector")
    }

    private var annualDetail: String {
        guard let price = SubscriptionPriceFormatter.price(store.annualPackage?.storeProduct) else {
            return store.isLoadingPackages
                ? "1 year · price settling in"
                : "1 year · price unavailable"
        }
        if annualTrialIsConfirmed {
            return AnkyLocalization.ui("Annual plan eligible detail format", price)
        }
        return AnkyLocalization.ui("Annual plan detail format", price)
    }

    private var monthlyDetail: String {
        guard let price = SubscriptionPriceFormatter.price(store.monthlyPackage?.storeProduct) else {
            return store.isLoadingPackages
                ? "1 month · price settling in"
                : "1 month · price unavailable · no introductory trial"
        }
        return AnkyLocalization.ui("Monthly plan detail format", price)
    }

    private var annualTrialIsConfirmed: Bool {
        store.annualTrialEligibility.displaysTrial
            && SubscriptionCatalogPolicy.hasExpectedAnnualFreeTrial(store.annualPackage?.storeProduct)
    }

    private func planOption(_ option: Plan, title: String, detail: String) -> some View {
        let isSelected = plan == option
        return Button {
            guard plan != option else { return }
            AnkyHaptics.selection()
            plan = option
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(isSelected ? Color.ankyInk : Color.ankyInk.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AnkyLocalization.ui(detail))
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isSelected ? Color.ankyGold : Color.ankySlate.opacity(0.55))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, isCompact ? 15 : 12)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.ankyPaper.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.ankyGold.opacity(0.85) : Color.ankySlate.opacity(0.35),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(AnkyLocalization.ui(detail))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(option == .annual ? "paywall.annualPlan" : "paywall.monthlyPlan")
    }

    private var selectedPackage: Package? {
        plan == .annual ? store.annualPackage : store.monthlyPackage
    }

    private var selectedPrice: String? {
        SubscriptionPriceFormatter.price(selectedPackage?.storeProduct)
    }

    // MARK: Actions and footer

    private var purchaseCTA: some View {
        purchaseButton
            .disabled(store.isPurchasing || (!store.isEntitledForGating && selectedPackage == nil))
            .opacity((!store.isEntitledForGating && selectedPackage == nil) ? 0.58 : 1)
            .padding(.top, 4)
            .accessibilityIdentifier("paywall.purchase")
    }

    /// Onboarding wears the pale PaperThreadButtonStyle so the CTA matches every
    /// earlier screen; the lapsed/veil sheets keep the brighter ThreadButtonStyle.
    @ViewBuilder
    private var purchaseButton: some View {
        let button = Button(action: purchaseSelected) {
            Group {
                if store.isPurchasing {
                    ProgressView().tint(Color.ankyInk)
                } else {
                    Text(AnkyLocalization.ui(purchaseCTATitle))
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        if isCompact {
            button.buttonStyle(PaperThreadButtonStyle())
        } else {
            button.buttonStyle(ThreadButtonStyle())
        }
    }

    private var purchaseCTATitle: String {
        if store.isEntitledForGating {
            return "Done"
        }
        guard let price = selectedPrice else {
            return store.isLoadingPackages ? "Settling…" : "Plan unavailable"
        }
        switch plan {
        case .annual where annualTrialIsConfirmed:
            return "Start 3-day free trial"
        case .annual:
            return AnkyLocalization.ui("Subscribe annually CTA format", price)
        case .monthly:
            return AnkyLocalization.ui("Subscribe monthly CTA format", price)
        }
    }

    /// Onboarding's escape hatch, demoted from a prominent capsule to a quiet
    /// footer link ("Skip") that sits beside "Have a code?".
    private func skipFreeWriting() {
        AnkyHaptics.light()
        guard OnboardingSubscriptionPolicy.allowsFreeContinuation(
            while: catalogPresentationState
        ), OnboardingSubscriptionPolicy.shouldAdvance(after: .continueFree) else { return }
        onCompleted()
    }

    private var catalogPresentationState: SubscriptionCatalogPresentationState {
        if store.isLoadingPackages { return .loading }
        return store.packages.isEmpty ? .unavailable : .available
    }

    private var footer: some View {
        VStack(spacing: isCompact ? 9 : 12) {
            footerButton(store.isRestoring ? "Restoring…" : "Restore Purchases") {
                restore()
            }
            .disabled(store.isRestoring)
            .accessibilityIdentifier("paywall.restore")

            HStack(spacing: 18) {
                Link(destination: SubscriptionLegalLinks.termsOfUseURL) {
                    footerLabel("Terms of Use")
                }
                .accessibilityLabel(AnkyLocalization.ui("Open Terms of Use"))
                .accessibilityIdentifier("paywall.terms")

                Text("·")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.ankySlate.opacity(0.6))
                    .accessibilityHidden(true)

                Link(destination: SubscriptionLegalLinks.privacyPolicyURL) {
                    footerLabel("Privacy Policy")
                }
                .accessibilityLabel(AnkyLocalization.ui("Open Privacy Policy"))
                .accessibilityIdentifier("paywall.privacy")
            }

            if !store.isEntitledForGating {
                HStack(spacing: 16) {
                    if context.isOnboarding {
                        footerButton("Skip") {
                            skipFreeWriting()
                        }
                        .accessibilityLabel(AnkyLocalization.ui("Skip and continue with free writing"))
                        .accessibilityIdentifier("paywall.continueFree")

                        Text("·")
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(Color.ankySlate.opacity(0.6))
                            .accessibilityHidden(true)
                    }

                    footerButton("Have a code?") {
                        redeemCode()
                    }
                    .accessibilityIdentifier("paywall.redeem")
                }
            }
        }
        .padding(.top, 2)
    }

    private func footerLabel(_ title: String) -> some View {
        Text(AnkyLocalization.ui(title))
            .font(.system(size: 13, weight: .regular, design: .serif))
            .foregroundStyle(Color.ankySlate)
            .underline()
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerLabel(title)
        }
        .buttonStyle(.plain)
    }

    private var shouldShowRetry: Bool {
        !store.isEntitledForGating
            && !store.isLoadingPackages
            && (store.offeringsErrorLine != nil || selectedPackage == nil)
    }

    private var retryBlock: some View {
        VStack(spacing: 7) {
            if let line = store.offeringsErrorLine {
                statusLine(line, color: Color.ankyMadder.opacity(0.9))
            }
            footerButton("Try again") {
                AnkyHaptics.light()
                Task { await refreshStorePresentation() }
            }
            .accessibilityIdentifier("paywall.retry")
        }
    }

    private func statusLine(_ line: String, color: Color) -> some View {
        Text(AnkyLocalization.ui(line))
            .font(.system(size: 14, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
    }

    private func refreshStorePresentation() async {
        await store.loadPackages()
        await store.refreshAnnualTrialEligibility()
    }

    private func purchaseSelected() {
        guard !store.isPurchasing else { return }
        if store.isEntitledForGating {
            onCompleted()
            return
        }
        guard let package = selectedPackage else {
            store.noteSelectedPackageUnavailable()
            return
        }
        AnkyHaptics.light()
        Task {
            let purchased = await store.purchase(package)
            guard purchased,
                  OnboardingSubscriptionPolicy.shouldAdvance(after: .purchaseActivated) else {
                return
            }
            AnkyFunnel.report(
                store.isInIntroTrialForGating ? AnkyFunnel.trialStarted : AnkyFunnel.subscribed,
                origin: funnelOrigin
            )
            AnkyHaptics.success()
            AnkyHaptics.medium()
            onCompleted()
        }
    }

    private func restore() {
        guard !store.isRestoring else { return }
        AnkyHaptics.light()
        Task {
            await store.restore()
            guard store.isEntitledForGating,
                  OnboardingSubscriptionPolicy.shouldAdvance(after: .restoreActivated) else {
                return
            }
            onCompleted()
        }
    }

    private func redeemCode() {
        AnkyHaptics.light()
        Task {
            guard await store.ensureConfigured() else {
                store.noteStoreUnreachable()
                return
            }
            Purchases.shared.presentCodeRedemptionSheet()
        }
    }
}

/// The same presentation remains reachable after onboarding from Settings and
/// every genuine Pro veil.
struct PaywallSheet: View {
    @ObservedObject var store: EntitlementStore
    let origin: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    Spacer(minLength: 36)

                    PaywallView(
                        store: store,
                        context: .veil(origin: origin),
                        onCompleted: { dismiss() }
                    )

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
