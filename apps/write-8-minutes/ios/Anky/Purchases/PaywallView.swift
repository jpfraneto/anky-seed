import SwiftUI
import RevenueCat

/// The ask. One screen, two prices, no tricks — the trial timeline says
/// exactly what will happen and when, in Anky's voice.
///
/// Painted post-dawn: the world turns to light at Meet Anky and the
/// paywall comes after it, so it lives in the same warm room as the
/// journey map — ink serif on the lazure wall, hairline gold thread,
/// filled ThreadButtonStyle. The thread does not un-fill because money
/// entered the room. The onboarding and lapsed variants are the same
/// room with different words: `Context` changes copy only, never styling.
///
/// Canon guardrails, deliberately structural:
/// - Switching plans updates only the selector, the payment line, and the
///   CTA label. It never opens a sheet, never shows a discount, never
///   counts down.
/// - Purchase failure or cancellation changes nothing on screen beyond
///   one quiet line. The screen itself is the ask; asking twice in the
///   same breath is off-canon.
struct PaywallView: View {
    /// Which words the room speaks. Copy only — one palette, one layout.
    enum Context {
        /// Screen 10 of onboarding, between the journey map and notifications.
        case onboarding
        /// Re-entry after the trial expired unconverted or the subscription ended.
        case lapsed
        /// Launched from a veil or boundary surface (phase-3). The origin is
        /// the funnel's `paywall_shown {origin}` tag.
        case veil(origin: String)
    }

    private enum Plan {
        case yearly
        case monthly
    }

    /// QA / App Review escape hatch: when true, a quiet "later" link
    /// advances without purchase. Compiled out of Release builds; flip
    /// the DEBUG value to false to test the hard gate.
    #if DEBUG
    private static let paywallIsSkippable = true
    #else
    private static let paywallIsSkippable = false
    #endif

    @ObservedObject var store: EntitlementStore
    let context: Context
    let onCompleted: () -> Void

    @State private var plan: Plan = .yearly
    @State private var isTrialEligible = true
    @State private var showsTerms = false
    @State private var showsPrivacy = false

    var body: some View {
        VStack(spacing: 18) {
            Text(AnkyLocalization.ui(titleText))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)

            Text(AnkyLocalization.ui(voiceLine))
                .font(.system(size: 16, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            if !store.isEntitled, isTrialEligible {
                trialTimeline
            }

            if !store.isEntitled {
                planSelector
            }

            // Full body legibility, deliberately — never fine print.
            Text(AnkyLocalization.ui(paymentLine))
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)

            if let errorLine = store.purchaseErrorLine, !store.isEntitled {
                Text(AnkyLocalization.ui(errorLine))
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(Color.ankyMadder.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            // Offline / store-unreachable is a visible state with a way
            // back, never a silently dead buy button.
            if let offeringsLine = store.offeringsErrorLine, !store.isEntitled, store.packages.isEmpty {
                VStack(spacing: 8) {
                    Text(AnkyLocalization.ui(offeringsLine))
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Color.ankyMadder.opacity(0.9))
                        .multilineTextAlignment(.center)

                    Button {
                        AnkyHaptics.light()
                        Task {
                            await store.loadPackages()
                            isTrialEligible = await store.yearlyTrialEligibility()
                        }
                    } label: {
                        if store.isLoadingPackages {
                            ProgressView()
                                .tint(Color.ankyInkSoft)
                        } else {
                            Text(AnkyLocalization.ui("Try again"))
                                .font(.system(size: 14, weight: .medium, design: .serif))
                                .foregroundStyle(Color.ankyGold)
                                .underline()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLoadingPackages)
                }
            }

            if let restoreLine = store.restoreStatusLine, !store.isEntitled {
                Text(AnkyLocalization.ui(restoreLine))
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(Color.ankyInkSoft)
                    .multilineTextAlignment(.center)
            }

            cta

            footer
        }
        .task(id: store.packages.count) {
            await store.loadPackages()
            isTrialEligible = await store.yearlyTrialEligibility()
        }
        .onAppear {
            if !store.isEntitled {
                AnkyFunnel.report(AnkyFunnel.paywallShown, origin: funnelOrigin)
                PaywallPressureLedger.recordPaywallShown()
            }
        }
        .sheet(isPresented: $showsTerms) {
            TermsAndConditionsReflectionSheet()
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
        .sheet(isPresented: $showsPrivacy) {
            PrivacyPolicyReflectionSheet()
                .presentationDetents([.fraction(0.8)])
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
    }

    // MARK: - Copy

    private var titleText: String {
        if store.isEntitled {
            if store.isPromotionalEntitlement {
                return "Anky is open — a gift"
            }
            return store.isInIntroTrial ? "Your trial is open" : "Anky is open"
        }
        switch context {
        case .onboarding:
            return isTrialEligible ? "Try Anky for $0" : "Write before you scroll."
        case .lapsed:
            return "The door is still here"
        case .veil:
            return AnkyCopyRegistry.paywallSheetTitle
        }
    }

    private var voiceLine: String {
        if store.isEntitled {
            if store.isPromotionalEntitlement {
                return "Your access was granted — nothing is charged, nothing renews. The mirror, the paintings, the journey, and the daily door are open."
            }
            return store.isInIntroTrial
                ? "You are already inside the deepening. The door stays open until your trial ends."
                : "Your practice is active. The mirror, the paintings, the journey, and the daily door are open."
        }
        switch context {
        case .onboarding:
            return "Walk the first three days of the gate with me. If it isn't yours, leave freely."
        case .lapsed:
            return "Everything you sealed stays yours to read, always. The gate, new sessions, and my reflections need the practice to be alive."
        case .veil:
            return AnkyCopyRegistry.paywallSheetVoiceLine
        }
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

    private var paymentLine: String {
        if store.isEntitled {
            return activeSubscriptionLine
        }
        if plan == .yearly && isTrialEligible {
            // 3.1.2: the conversion is spelled out under the trial CTA, not
            // only in the plan card above.
            return "No payment due today. Then \(yearlyPriceText)/year — auto-renews until you cancel."
        }
        return "Billed today. Auto-renews until you cancel."
    }

    private var ctaTitle: String {
        if store.isEntitled {
            return "Done"
        }
        switch plan {
        case .yearly:
            if isTrialEligible {
                return "Start my 3 free days"
            }
            return "Continue — \(yearlyPriceText)/year"
        case .monthly:
            return "Begin — \(monthlyPriceText)/month"
        }
    }

    private var yearlyPriceText: String {
        SubscriptionPriceFormatter.price(store.yearlyPackage?.storeProduct, fallback: "$88")
    }

    private var monthlyPriceText: String {
        SubscriptionPriceFormatter.price(store.monthlyPackage?.storeProduct, fallback: "$11.99")
    }

    private var yearlyWeeklyText: String {
        "\(SubscriptionPriceFormatter.weekly(of: store.yearlyPackage?.storeProduct, fallback: "$1.69"))/wk"
    }

    private var activeSubscriptionLine: String {
        if store.isPromotionalEntitlement {
            guard let endDate = store.activeExpirationDate else {
                return "Complimentary access, open-ended. Nothing will ever be charged for it."
            }
            let date = endDate.formatted(date: .abbreviated, time: .omitted)
            return "Complimentary access through \(date). Nothing will be charged — when it ends, the door simply asks again."
        }
        let price = activeSubscriptionPriceLine
        guard let renewalDate = store.activeRenewalDate else {
            return "Your subscription is active on this Apple ID. Manage it from App Store subscriptions."
        }
        let date = renewalDate.formatted(date: .abbreviated, time: .omitted)
        if store.isInIntroTrial {
            return "Your free trial is active. You will be charged \(price) on \(date) unless you cancel in App Store subscriptions."
        }
        return "Your subscription is active. You will be charged \(price) on \(date) unless you cancel in App Store subscriptions."
    }

    private var activeSubscriptionPriceLine: String {
        let product = store.activePackage?.storeProduct ?? store.yearlyPackage?.storeProduct
        if store.activeProductID == AnkyPurchasesConfig.monthlyProductID {
            return "\(SubscriptionPriceFormatter.price(product, fallback: "$11.99"))/month"
        }
        return "\(SubscriptionPriceFormatter.price(product, fallback: "$88"))/year"
    }

    // MARK: - Timeline

    /// Three nodes on a hairline gold thread — the same visual grammar as
    /// the 8-day map, telling the trial exactly as it will happen. Today's
    /// node is filled; the days still to come are outlines.
    private var trialTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineNode(
                label: "Today",
                line: "The door opens. Full practice, nothing held back.",
                isFilled: true,
                isLast: false
            )
            timelineNode(
                label: "Day 2",
                line: "I'll remind you before your trial ends. No surprises.",
                isFilled: false,
                isLast: false
            )
            timelineNode(
                label: "Day 3",
                line: "First Daily Unlock. Stay if this is yours.",
                isFilled: false,
                isLast: true
            )
        }
        .padding(.vertical, 2)
    }

    private func timelineNode(label: String, line: String, isFilled: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(Color.ankyGold, lineWidth: 1)
                    .background(Circle().fill(isFilled ? Color.ankyGold : Color.clear))
                    .frame(width: isFilled ? 12 : 11, height: isFilled ? 12 : 11)
                    .padding(.top, 3)

                if !isLast {
                    // Hairline, same weight as the 8-day map's LazureDivider.
                    Rectangle()
                        .fill(Color.ankyGold.opacity(0.5))
                        .frame(width: 0.5)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AnkyLocalization.ui(label))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .tracking(2.5)
                    .foregroundStyle(Color.ankyMadder.opacity(0.85))

                Text(AnkyLocalization.ui(line))
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, isLast ? 0 : 16)
            }

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Plan selector

    private var planSelector: some View {
        VStack(spacing: 10) {
            planOption(
                .yearly,
                title: isTrialEligible ? "Yearly — 3 days free, then \(yearlyPriceText)/year" : "Yearly — \(yearlyPriceText)/year",
                trailing: yearlyWeeklyText
            )
            planOption(
                .monthly,
                title: "\(monthlyPriceText)/month · no free trial",
                trailing: nil
            )
        }
    }

    /// Warm cream cards a half-step lighter than the wall. Selection is a
    /// gold hairline with a very faint interior wash; unselected is a
    /// gray-violet hairline. Tapping updates only the selector, the
    /// payment line, and the CTA label.
    private func planOption(_ option: Plan, title: String, trailing: String?) -> some View {
        let isSelected = plan == option
        return Button {
            guard plan != option else {
                return
            }
            AnkyHaptics.selection()
            plan = option
        } label: {
            HStack(spacing: 12) {
                Text(AnkyLocalization.ui(title))
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(isSelected ? Color.ankyInk : Color.ankyInk.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer()

                if let trailing {
                    Text(AnkyLocalization.ui(trailing))
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ankyGold)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.ankyPaper.opacity(0.72))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.ankyGold.opacity(0.07))
                        }
                    }
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - CTA & footer

    private var cta: some View {
        Button(action: purchaseSelected) {
            Group {
                if store.isPurchasing {
                    ProgressView()
                        .tint(Color.ankyInk)
                } else {
                    Text(AnkyLocalization.ui(ctaTitle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ThreadButtonStyle())
        .disabled(store.isPurchasing)
        .padding(.top, 6)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                footerLink(store.isRestoring ? "Restoring…" : "Restore Purchases") {
                    restore()
                }
                footerDot
                footerLink("Terms") {
                    showsTerms = true
                }
                footerDot
                footerLink("Privacy") {
                    showsPrivacy = true
                }
            }

            if !store.isEntitled {
                footerLink("Have a code?") {
                    redeemCode()
                }
            }

            if Self.paywallIsSkippable {
                Button {
                    onCompleted()
                } label: {
                    Text(AnkyLocalization.ui("later"))
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private var footerDot: some View {
        Text("·")
            .font(.system(size: 13, design: .serif))
            .foregroundStyle(Color.ankySlate.opacity(0.6))
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(AnkyLocalization.ui(title))
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankySlate)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func purchaseSelected() {
        guard !store.isPurchasing else {
            return
        }
        if store.isEntitled {
            onCompleted()
            return
        }
        AnkyHaptics.light()
        let startedTrialEligible = isTrialEligible
        Task {
            await store.loadPackages()
            guard let package = plan == .yearly ? store.yearlyPackage : store.monthlyPackage else {
                // Offerings unreachable: loadPackages surfaced the line and
                // the retry link. Loaded but missing this plan: say so.
                if !store.packages.isEmpty {
                    store.noteSelectedPackageUnavailable()
                }
                return
            }
            let purchased = await store.purchase(package)
            guard purchased else {
                // Cancelled or failed: the screen stays as it is (plus at
                // most one quiet line). No guilt copy, no modal — the ask
                // was already made.
                return
            }
            let startedTrial = plan == .yearly && startedTrialEligible
            AnkyFunnel.report(
                startedTrial ? AnkyFunnel.trialStarted : AnkyFunnel.subscribed,
                origin: funnelOrigin
            )
            AnkyHaptics.success()
            AnkyHaptics.medium()
            onCompleted()
        }
    }

    private func restore() {
        guard !store.isRestoring else {
            return
        }
        AnkyHaptics.light()
        Task {
            await store.restore()
            if store.isEntitled {
                onCompleted()
            }
        }
    }

    /// Offer-code redemption. Until the products exist in App Store
    /// Connect the sheet has nothing to redeem against — presenting it is
    /// harmless. An unconfigured SDK retries configuration first and says
    /// so if the store stays unreachable.
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

/// The paywall as a presentable sheet (phase-3 §4) — launched from every
/// veil and boundary surface. Same dawn room as the onboarding ask; the
/// sheet dismisses itself on purchase or restore, and the surface beneath
/// unveils on its own because entitlement changed. Nothing is ever locked
/// behind this sheet that wasn't gently visible through its veil.
struct PaywallSheet: View {
    @ObservedObject var store: EntitlementStore
    /// Funnel tag for `paywall_shown {origin}` — e.g. "reflection",
    /// "ceremony", "journey", "widget", "quick_action".
    let origin: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    Spacer(minLength: 44)

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
