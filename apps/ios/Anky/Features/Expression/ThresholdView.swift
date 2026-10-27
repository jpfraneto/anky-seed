//
//  ThresholdView.swift
//  Anky
//
//  The page before a session: an invitation, not a task.
//
//      Go for a walk.
//      Or stay right where you are.
//
//      How would you like to express yourself?
//      Write · Talk · Record
//      or simply begin, in silence
//
//  Choosing a medium does not fix the session's format; switching later is
//  one tap. Walking is a context the person may name (by tapping one of the
//  two lines), never a requirement and never inferred.
//

import SwiftUI

struct ThresholdView: View {
    @ObservedObject var expression: ExpressionController
    @ObservedObject var access: AccessController
    let onOpenDrawer: () -> Void
    let onSubscribe: () -> Void
    let onExport: () -> Void

    @State private var setting: SessionSetting?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DrawerButton(action: onOpenDrawer)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Spacer(minLength: 24)

            if let denial = creationDenial {
                FreeAccessCompleteView(
                    denial: denial,
                    onSubscribe: onSubscribe,
                    onRestore: {
                        switch await access.restore() {
                        case .activated: return AnkyLocalization.ui("Your subscription is restored.")
                        case .nothingToRestore: return AnkyLocalization.ui("No active Anky subscription was found for this Apple ID.")
                        case .failed(let text): return text
                        case .cancelled, .pending: return nil
                        }
                    },
                    onRetry: { Task { await access.refresh() } },
                    onViewMemories: onOpenDrawer,
                    onExport: onExport
                )
                .padding(.horizontal, 28)
            } else {
                invitation
            }

            Spacer(minLength: 24)

            if creationDenial == nil, let line = accessLine {
                Text(line)
                    .font(.fraunces(13, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var creationDenial: AccessDenial? {
        if case .denied(let reason) = access.decide(.startSession) { return reason }
        return nil
    }

    private var invitation: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                settingLine(AnkyLocalization.ui("Go for a walk."), value: .walking, size: 34, italic: false)
                settingLine(AnkyLocalization.ui("Or stay right where you are."), value: .still, size: 21, italic: true)
            }
            .padding(.bottom, 44)

            Text(AnkyLocalization.ui("How would you like to express yourself?"))
                .font(.fraunces(17, weight: .regular))
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)

            HStack(spacing: 12) {
                ForEach(ExpressionChoice.allCases) { choice in
                    MediumTile(choice: choice) {
                        Task { await expression.begin(setting: setting, medium: choice.medium) }
                    }
                }
            }
            .padding(.horizontal, 24)

            Button {
                AnkyHaptics.light()
                Task { await expression.begin(setting: setting, medium: .silence) }
            } label: {
                Text(AnkyLocalization.ui("or simply begin, in silence"))
                    .font(.fraunces(16, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
                    .underline(color: Color.ankyInkSoft.opacity(0.4))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .frame(maxWidth: 520)
    }

    /// Tapping a line names the session's setting; tapping again un-names it.
    private func settingLine(_ text: String, value: SessionSetting, size: CGFloat, italic: Bool) -> some View {
        Button {
            AnkyHaptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                setting = setting == value ? nil : value
            }
        } label: {
            Text(text)
                .font(.fraunces(size, weight: italic ? .light : .regular, italic: italic))
                .foregroundStyle(setting == nil || setting == value ? Color.ankyInk : Color.ankyInkSoft.opacity(0.55))
                .multilineTextAlignment(.center)
                .overlay(alignment: .bottom) {
                    if setting == value {
                        Capsule()
                            .fill(Color.ankyInk.opacity(0.5))
                            .frame(width: 28, height: 2)
                            .offset(y: 8)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(setting == value ? .isSelected : [])
        .accessibilityHint(AnkyLocalization.ui("Optional. Names this session; you can express either way."))
    }

    /// Plain facts about access, never a countdown.
    private var accessLine: String? {
        switch access.state {
        case .freeNotStarted:
            return AnkyLocalization.ui("Your first seven days are free. No payment details, and nothing is charged when they end.")
        case .freeActive(let endsAt):
            return AnkyLocalization.ui("Free until %@. Nothing is charged when it ends.", endsAt.formatted(date: .abbreviated, time: .shortened))
        case .subscriber, .freeExpired, .unverified:
            return nil
        }
    }
}

/// Shown where the invitation stood, once new sessions need a subscription
/// (or access can't be verified right now). Memories stay open either way.
struct FreeAccessCompleteView: View {
    let denial: AccessDenial
    let onSubscribe: () -> Void
    let onRestore: () async -> String?
    let onRetry: () -> Void
    let onViewMemories: () -> Void
    let onExport: () -> Void

    @State private var restoreMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.fraunces(28, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.fraunces(18, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                if denial == .needsVerification {
                    AnkyPrimaryButton(AnkyLocalization.ui("Try again"), action: onRetry)
                    AnkySecondaryButton(AnkyLocalization.ui("Subscribe"), action: onSubscribe)
                } else {
                    AnkyPrimaryButton(AnkyLocalization.ui("Subscribe"), action: onSubscribe)
                    AnkySecondaryButton(AnkyLocalization.ui("Restore purchases")) {
                        Task { restoreMessage = await onRestore() }
                    }
                }
                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.fraunces(15, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 22) {
                    quietButton(AnkyLocalization.ui("View my memories"), action: onViewMemories)
                    quietButton(AnkyLocalization.ui("Export my memories"), action: onExport)
                }
                .padding(.top, 4)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var title: String {
        denial == .needsVerification
            ? AnkyLocalization.ui("Anky couldn't confirm your access.")
            : AnkyLocalization.ui("Your seven days with Anky are complete.")
    }

    private var lines: [String] {
        if denial == .needsVerification {
            return [
                AnkyLocalization.ui("Everything you've expressed is still yours, and still here."),
                AnkyLocalization.ui("Connect to the internet so Anky can check your subscription or your free days.")
            ]
        }
        return [
            AnkyLocalization.ui("Everything you've expressed is still yours."),
            AnkyLocalization.ui("To continue creating new sessions, subscribe to Anky.")
        ]
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            Text(title)
                .font(.fraunces(15, weight: .regular))
                .underline(color: Color.ankyInkSoft.opacity(0.4))
                .foregroundStyle(Color.ankyInk)
        }
        .buttonStyle(.plain)
    }
}
