//
//  PaywallView.swift
//  Anky
//
//  "Keep Anky alive." The only purchase surface in the app. Everything it
//  states about money comes from StoreKit through RevenueCat; if the store
//  has not answered, it says so instead of showing a number.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject private var access = AccessController.shared
    @ObservedObject private var subscriptions = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var message: String?
    @State private var showsManage = false

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.ankyInkSoft)
                                .frame(width: 40, height: 40)
                                .ankyGlass(in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AnkyLocalization.ui("Close"))
                    }

                    Text(AnkyLocalization.ui("Keep Anky alive."))
                        .font(.fraunces(34, weight: .regular))
                        .foregroundStyle(Color.ankyInk)

                    Text(AnkyLocalization.ui("Your subscription sustains this space for expression, memory, and awareness."))
                        .font(.fraunces(19, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(freeLine)
                        .font(.fraunces(16, weight: .light))
                        .foregroundStyle(Color.ankyInkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    if access.state.isSubscriber {
                        subscribedBlock
                    } else {
                        offerBlock
                    }

                    if let message {
                        Text(message)
                            .font(.fraunces(15, weight: .light, italic: true))
                            .foregroundStyle(Color.ankyInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    links
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.light)
        .task { await subscriptions.loadPlan() }
        .manageSubscriptionsSheet(isPresented: $showsManage)
        .animation(.easeInOut(duration: 0.25), value: message)
    }

    private var freeLine: String {
        switch access.state {
        case .freeNotStarted, .freeActive:
            return AnkyLocalization.ui("Your first seven days are free. You won't be charged unless you choose to subscribe.")
        default:
            return AnkyLocalization.ui("Your first seven days were free. You won't be charged unless you choose to subscribe.")
        }
    }

    // MARK: The offer

    @ViewBuilder
    private var offerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let plan = subscriptions.plan {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AnkyLocalization.ui("Anky, monthly"))
                        .font(.fraunces(15, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft)
                    Text(AnkyLocalization.ui("%@ per month", plan.localizedPrice))
                        .font(.fraunces(28, weight: .regular))
                        .foregroundStyle(Color.ankyInk)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ankyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)

                AnkyPrimaryButton(
                    AnkyLocalization.ui("Subscribe for %@ a month", plan.localizedPrice),
                    isEnabled: !access.isTransacting,
                    isLoading: subscriptions.activity == .purchasing
                ) {
                    Task { await purchase() }
                }

                Text(disclosure(price: plan.localizedPrice))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ankyInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if subscriptions.planUnavailable {
                Text(AnkyLocalization.ui("The App Store isn't answering right now, so there's no price to show. Nothing has been charged. Try again in a moment."))
                    .font(.fraunces(16, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                AnkySecondaryButton(AnkyLocalization.ui("Try again")) {
                    Task { await subscriptions.loadPlan() }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.ankyInk)
                    Text(AnkyLocalization.ui("Asking the App Store for the price…"))
                        .font(.fraunces(15, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft)
                }
            }

            Button {
                Task { await restore() }
            } label: {
                Text(subscriptions.activity == .restoring
                     ? AnkyLocalization.ui("Restoring…")
                     : AnkyLocalization.ui("Restore purchases"))
                    .font(.fraunces(16, weight: .regular))
                    .underline()
                    .foregroundStyle(Color.ankyInk)
            }
            .buttonStyle(.plain)
            .disabled(access.isTransacting)
        }
    }

    private func disclosure(price: String) -> String {
        AnkyLocalization.ui(
            "%@ per month, renewing automatically every month until you cancel. Payment is charged to your Apple ID only when you confirm the purchase. Cancel any time in Settings › Apple ID › Subscriptions, at least 24 hours before the next renewal; you keep access until the end of the paid month.",
            price
        )
    }

    @ViewBuilder
    private var subscribedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AnkyLocalization.ui("You're subscribed. Thank you for keeping Anky alive."))
                .font(.fraunces(18, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .fixedSize(horizontal: false, vertical: true)
            if subscriptions.hasBillingIssue {
                Text(AnkyLocalization.ui("Apple couldn't renew your subscription. Update your payment method with Apple to keep it."))
                    .font(.fraunces(15, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyMadder)
                    .fixedSize(horizontal: false, vertical: true)
            } else if subscriptions.willNotRenew, case .subscriber(let expiresAt?) = access.state {
                Text(AnkyLocalization.ui("It won't renew. Access continues until %@.", expiresAt.formatted(date: .long, time: .omitted)))
                    .font(.fraunces(15, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
            }
            AnkySecondaryButton(AnkyLocalization.ui("Manage subscription")) {
                showsManage = true
            }
        }
    }

    private var links: some View {
        HStack(spacing: 18) {
            Button(AnkyLocalization.ui("Terms of Use")) { openURL(AnkyPurchasesConfig.termsOfUseURL) }
            Button(AnkyLocalization.ui("Privacy Policy")) { openURL(AnkyPurchasesConfig.privacyPolicyURL) }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.ankyInkSoft)
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: Actions

    private func purchase() async {
        message = nil
        switch await access.purchase() {
        case .activated:
            AnkyHaptics.success()
            message = AnkyLocalization.ui("Welcome. Anky is open.")
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        case .cancelled:
            message = nil
        case .pending:
            message = AnkyLocalization.ui("Apple is still confirming this purchase (for example, waiting for approval). Anky will open as soon as it's confirmed.")
        case .nothingToRestore:
            message = nil
        case .failed(let text):
            message = text
        }
    }

    private func restore() async {
        message = nil
        switch await access.restore() {
        case .activated:
            AnkyHaptics.success()
            message = AnkyLocalization.ui("Your subscription is restored.")
        case .nothingToRestore:
            message = AnkyLocalization.ui("No active Anky subscription was found for this Apple ID.")
        case .failed(let text):
            message = text
        case .cancelled, .pending:
            message = nil
        }
    }
}
