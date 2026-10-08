import RevenueCat
import SwiftUI

/// The single subscription presentation used during onboarding, from Pro
/// veils, after lapse, and from Settings. StoreKit supplies every price;
/// RevenueCat supplies current entitlement. Annual and monthly buy the same
/// one thing: better new reflections.
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

    @ObservedObject var store: EntitlementStore
    let context: Context
    let onCompleted: () -> Void
    @State private var selectedPlan: AnkySubscriptionPlan = .annual

    /// Onboarding renders inside a fixed, non-scrolling budget, so it uses
    /// slightly tighter spacing. The content itself is identical everywhere.
    private var isCompact: Bool { context.isOnboarding }

    var body: some View {
        VStack(spacing: isCompact ? 11 : 16) {
            Text(AnkyLocalization.ui(titleText))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)

            Text(AnkyLocalization.ui(voiceLine))
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            proBenefits

            if !store.isEntitledForGating {
                planChoices
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
            selectFirstAvailablePlanIfNeeded()
        }
        .onAppear {
            if !store.isEntitledForGating {
                AnkyFunnel.report(AnkyFunnel.paywallShown, origin: funnelOrigin)
                PaywallPressureLedger.recordPaywallShown()
            }
        }
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
            return "Anky Pro"
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
            return "Your subscription is active on this Apple ID. Manage it in App Store subscriptions."
        }
        switch context {
        case .onboarding:
            return "Anky Pro only changes the quality of new reflections. Writing and everything else stay free."
        case .lapsed:
            return "Renew for stronger new reflections. Writing and everything else stay free."
        case .veil:
            return "Unlock stronger, more thoughtful reflections from Anky."
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
        ["Better reflections from Anky's strongest available model"]
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
        switch selectedPlan {
        case .annual:
            return AnkyLocalization.ui("Annual renewal disclosure format", price)
        case .monthly:
            return AnkyLocalization.ui("Monthly renewal disclosure format", price)
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

    private var planChoices: some View {
        VStack(spacing: isCompact ? 8 : 10) {
            planRow(.annual)
            planRow(.monthly)
        }
    }

    private func planRow(_ plan: AnkySubscriptionPlan) -> some View {
        let package = package(for: plan)
        let selected = selectedPlan == plan
        let title = package?.storeProduct.localizedTitle ?? AnkyLocalization.ui(
            plan == .annual ? "Anky Pro Annual" : "Anky Pro Monthly"
        )
        let detail = planDetail(plan)

        return Button {
            guard package != nil else { return }
            AnkyHaptics.selection()
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)

                    Text(AnkyLocalization.ui(detail))
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(selected ? Color.ankyGold : Color.ankyInkSoft.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, isCompact ? 11 : 12)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 66 : 72)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.ankyPaper.opacity(selected ? 0.78 : 0.54))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                selected ? Color.ankyGold.opacity(0.85) : Color.ankyInk.opacity(0.10),
                                lineWidth: selected ? 1 : 0.7
                            )
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(package == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(title). \(AnkyLocalization.ui(detail))")
        .accessibilityIdentifier("paywall.\(plan.rawValue)Plan")
    }

    private func planDetail(_ plan: AnkySubscriptionPlan) -> String {
        guard let price = SubscriptionPriceFormatter.price(package(for: plan)?.storeProduct) else {
            return store.isLoadingPackages
                ? (plan == .annual ? "1 year · price settling in" : "1 month · price settling in")
                : (plan == .annual ? "1 year · price unavailable" : "1 month · price unavailable")
        }
        return AnkyLocalization.ui(
            plan == .annual ? "Annual plan detail format" : "Monthly plan detail format",
            price
        )
    }

    private func package(for plan: AnkySubscriptionPlan) -> Package? {
        switch plan {
        case .annual: return store.annualPackage
        case .monthly: return store.monthlyPackage
        }
    }

    private var selectedPackage: Package? {
        package(for: selectedPlan)
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
        return AnkyLocalization.ui(
            selectedPlan == .annual ? "Subscribe annually CTA format" : "Subscribe monthly CTA format",
            price
        )
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
    }

    private func selectFirstAvailablePlanIfNeeded() {
        guard selectedPackage == nil else { return }
        if store.annualPackage != nil {
            selectedPlan = .annual
        } else if store.monthlyPackage != nil {
            selectedPlan = .monthly
        }
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
