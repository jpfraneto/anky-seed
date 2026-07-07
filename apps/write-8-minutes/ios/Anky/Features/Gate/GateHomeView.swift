import SwiftUI

/// The renewed main surface: the gate. Answers, at a glance —
/// am I protected, what is gated, what is my next ritual, did I write
/// before scrolling today, and how alive is my signal.
/// Everything shown here is derived locally; nothing leaves the device.
struct GateHomeView: View {
    @ObservedObject var screenTime: WriteBeforeScrollSpikeViewModel
    let onWrite: () -> Void
    let onSetup: () -> Void
    let onSettings: () -> Void
    let onArchive: () -> Void
    let onYou: () -> Void

    @State private var signal = SignalCalculator.snapshot(
        screenTimeState: WriteBeforeScrollScreenTimeState(),
        unlockState: UnlockState(grant: nil, lastWroteAt: nil),
        events: [],
        sessionDays: []
    )

    @State private var gateProgress = EightDayGateProgress()
    @State private var quickPassesRemaining = QuickPassStore.dailyAllowance
    @State private var dailyTargetMinutes = DailyTargetStore.defaultMinutes
    @State private var showedUpDays: Set<Date> = []
    @State private var avatarImage = AvatarStore().loadImage()

    private var writerName: String? {
        WritingAnchorStore().writerName
    }

    private var usesNotificationFallback: Bool {
        WriteBeforeScrollLaunchBridgeModeResolver.resolve() == .notification
    }

    private enum GatePhase {
        case needsAuthorization
        case needsSelection
        case gateOff
        case unlocked
        case protected
    }

    private var phase: GatePhase {
        if !screenTime.isScreenTimeAuthorized {
            return .needsAuthorization
        }
        if !signal.isGateConfigured {
            return .needsSelection
        }
        if signal.isCurrentlyUnlocked {
            return .unlocked
        }
        if signal.isShieldActive {
            return .protected
        }
        return .gateOff
    }

    private var statusTitle: String {
        switch phase {
        case .needsAuthorization:
            return "The door is not built yet."
        case .needsSelection:
            return "No apps are gated yet."
        case .gateOff:
            return "The gate is quiet right now."
        case .unlocked:
            return "You wrote first. The gate is open."
        case .protected:
            return signal.wroteToday
                ? "You wrote before you scrolled."
                : "Your gate is on."
        }
    }

    private var statusSubtitle: String {
        switch phase {
        case .needsAuthorization:
            return "Anky needs Screen Time permission to place a writing gate before noisy apps."
        case .needsSelection:
            return "Pick the apps that pull you out of yourself."
        case .gateOff:
            return "Your chosen apps are open without a gate. Turn it on when you are ready."
        case .unlocked:
            if let expiresAt = signal.unlockExpiresAt {
                return "Unlocked until \(expiresAt.formatted(date: .omitted, time: .shortened)). The gate returns on its own."
            }
            return "The gate returns on its own."
        case .protected:
            return signal.wroteToday
                ? "The gate is holding for the rest of the day."
                : "Your feed has not gotten you first today."
        }
    }

    private var primaryCTATitle: String {
        switch phase {
        case .needsAuthorization:
            return "Continue setup"
        case .needsSelection:
            return "Choose apps"
        case .gateOff, .unlocked, .protected:
            return "Write now"
        }
    }

    private func primaryCTAAction() {
        switch phase {
        case .needsAuthorization, .needsSelection:
            onSetup()
        case .gateOff, .unlocked, .protected:
            onWrite()
        }
    }

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    statusBlock

                    primaryCTA

                    if phase == .gateOff {
                        Button {
                            screenTime.forceLock()
                            refreshSignal()
                        } label: {
                            Text(AnkyLocalization.ui("Turn on gate"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.ankyInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(
                                    LinearGradient(
                                        colors: [Color.ankySlate.opacity(0.18), Color.ankyViolet.opacity(0.14)],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    in: Capsule()
                                )
                                .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }

                    showedUpStrip

                    cardsGrid

                    if usesNotificationFallback && phase != .needsAuthorization {
                        Text(AnkyLocalization.ui("On this iOS version, Anky uses a notification to bring you back to the writing gate."))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.80))
                            .lineSpacing(3)
                    }

                    footerLinks
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            screenTime.refresh()
            refreshSignal()
        }
        .onChange(of: screenTime.state) { _ in
            refreshSignal()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.ankyGold.opacity(0.5), lineWidth: 1))
                    .shadow(color: Color.ankyViolet.opacity(0.14), radius: 10, y: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(AnkyLocalization.ui(gateProgress.isComplete
                    ? "8-Day Gate complete"
                    : "Day \(gateProgress.currentDayNumber) of 8"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ankyGold)

                if let writerName {
                    Text(writerName)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)
                }
            }

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(
                            colors: [Color.ankyPaper.opacity(0.80), Color.ankyPaper.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("Settings"))
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AnkyLocalization.ui(statusTitle))
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(Color.ankyInk)
                .lineSpacing(3)

            Text(AnkyLocalization.ui(statusSubtitle))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.ankyInkSoft)
                .lineSpacing(4)
        }
    }

    private var primaryCTA: some View {
        Button(action: primaryCTAAction) {
            Text(AnkyLocalization.ui(primaryCTATitle))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ankyInk)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [Color.ankyGoldLight, Color.ankyGold],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                .shadow(color: Color.ankyGold.opacity(0.30), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// The last weeks at a glance: one circle per day, gold when the
    /// writer showed up (met the daily target). Today sits at the right
    /// edge; the past scrolls away to the left.
    private var showedUpStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days: [Date] = stride(from: -59, through: 0, by: 1).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days, id: \.self) { day in
                        let showedUp = showedUpDays.contains(day)
                        let isToday = day == today

                        VStack(spacing: 6) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.ankyInkSoft.opacity(0.75))

                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 15, weight: showedUp ? .semibold : .regular, design: .serif))
                                .foregroundStyle(showedUp ? Color.ankyInk : Color.ankyInkSoft.opacity(0.8))
                                .frame(width: 38, height: 38)
                                .background {
                                    if showedUp {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.ankyGoldLight, Color.ankyGold],
                                                    startPoint: .top, endPoint: .bottom
                                                )
                                            )
                                            .shadow(color: Color.ankyGold.opacity(0.35), radius: 8, y: 2)
                                    } else {
                                        Circle()
                                            .fill(Color.ankyPaper.opacity(0.45))
                                            .overlay(Circle().strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5))
                                    }
                                }
                                .overlay {
                                    if isToday {
                                        Circle().strokeBorder(Color.ankyViolet.opacity(0.85), lineWidth: 1.5)
                                    }
                                }
                        }
                        .id(day)
                        .accessibilityLabel(AnkyLocalization.ui(showedUp
                            ? "Showed up on \(day.formatted(date: .abbreviated, time: .omitted))"
                            : day.formatted(date: .abbreviated, time: .omitted)))
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(today, anchor: .trailing)
            }
        }
    }

    private var cardsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                gateCard(
                    title: "Protected",
                    value: protectedValueText,
                    caption: phase == .needsSelection || phase == .needsAuthorization
                        ? "nothing gated yet"
                        : (signal.isShieldActive ? "gate on" : (signal.isCurrentlyUnlocked ? "open for now" : "gate off"))
                )

                gateCard(
                    title: "Signal",
                    value: "\(signal.signalPercent)%",
                    caption: signal.currentStreakDays > 0
                        ? "alive and returning"
                        : "write to begin"
                )
            }

            HStack(spacing: 12) {
                gateCard(
                    title: "Today",
                    value: signal.gatesCompletedToday > 0
                        ? "\(signal.gatesCompletedToday) gate\(signal.gatesCompletedToday == 1 ? "" : "s")"
                        : (signal.wroteToday ? "wrote first" : "—"),
                    caption: signal.wroteToday
                        ? "you wrote before scrolling"
                        : "the day is still yours"
                )

                gateCard(
                    title: "Next unlock",
                    value: nextUnlockValueText,
                    caption: nextUnlockCaptionText
                )
            }

            gateDayCard
        }
    }

    private var protectedValueText: String {
        var parts: [String] = []
        if signal.selectedApplicationCount > 0 {
            parts.append("\(signal.selectedApplicationCount) app\(signal.selectedApplicationCount == 1 ? "" : "s")")
        }
        if signal.selectedCategoryCount > 0 {
            parts.append("\(signal.selectedCategoryCount) categor\(signal.selectedCategoryCount == 1 ? "y" : "ies")")
        }
        if signal.selectedWebDomainCount > 0 {
            parts.append("\(signal.selectedWebDomainCount) site\(signal.selectedWebDomainCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "none" : parts.joined(separator: " · ")
    }

    private var nextUnlockValueText: String {
        if signal.isCurrentlyUnlocked, let expiresAt = signal.unlockExpiresAt {
            return "open until \(expiresAt.formatted(date: .omitted, time: .shortened))"
        }
        if quickPassesRemaining > 0 {
            return "1 sentence → 15 min"
        }
        return "\(dailyTargetMinutes) min → the day"
    }

    private var nextUnlockCaptionText: String {
        if quickPassesRemaining > 0 {
            return "\(quickPassesRemaining) pass\(quickPassesRemaining == 1 ? "" : "es") left · \(dailyTargetMinutes) min → the day"
        }
        return "passes return at midnight"
    }

    private var gateDayCard: some View {
        let currentDay = gateProgress.currentDayNumber
        let isCurrentDayComplete = gateProgress.isDayComplete(currentDay)

        return HStack(spacing: 12) {
            Image(systemName: isCurrentDayComplete ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.ankyGold.opacity(isCurrentDayComplete ? 1 : 0.6))

            VStack(alignment: .leading, spacing: 3) {
                Text(AnkyLocalization.ui(gateProgress.isComplete
                    ? "The 8-Day Gate · complete"
                    : "The 8-Day Gate · Day \(currentDay)"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ankyInkSoft)

                Text(AnkyLocalization.ui(EightDayGate.title(forDay: currentDay)))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ankyInk)
            }

            Spacer()

            Text("\(gateProgress.completedDayCount)/8")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.80))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.ankyPaper.opacity(0.80), Color.ankyPaper.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                )
        }
        .shadow(color: Color.ankyViolet.opacity(0.14), radius: 18, y: 6)
    }

    private func gateCard(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AnkyLocalization.ui(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.90))
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ankyInk)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(AnkyLocalization.ui(caption))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.80))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.ankyPaper.opacity(0.80), Color.ankyPaper.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                )
        }
        .shadow(color: Color.ankyViolet.opacity(0.14), radius: 18, y: 6)
    }

    private var footerLinks: some View {
        HStack(spacing: 22) {
            footerLink(title: "Archive", systemImage: "books.vertical", action: onArchive)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func footerLink(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(AnkyLocalization.ui(title), systemImage: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ankyInkSoft)
        }
        .buttonStyle(.plain)
    }

    private func refreshSignal() {
        let now = Date()
        let sessions = SessionIndexStore().load()
        let events = WriteBeforeScrollEventLogStore().load()
        avatarImage = AvatarStore().loadImage()
        refreshShowedUpDays(sessions: sessions, now: now)
        signal = SignalCalculator.snapshot(
            screenTimeState: screenTime.state,
            unlockState: UnlockStateStore().load(),
            events: events,
            sessionDays: sessions.map(\.createdAt)
        )
        quickPassesRemaining = QuickPassStore().remainingPasses(now: now)
        dailyTargetMinutes = DailyTargetStore().effectiveTargetMinutes(now: now)
        refreshGateProgress(events: events)
    }

    /// A day counts as "showed up" when its sealed writing adds up to the
    /// daily target. Judged against the current target — the store keeps
    /// no per-day history.
    private func refreshShowedUpDays(sessions: [SessionSummary], now: Date) {
        let calendar = Calendar.current
        let targetMs = DailyTargetStore().effectiveTargetMs(now: now, calendar: calendar)
        var msPerDay: [Date: Int64] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.createdAt)
            msPerDay[day, default: 0] += session.durationMs
        }
        showedUpDays = Set(msPerDay.filter { $0.value >= targetMs }.keys)
    }

    private func refreshGateProgress(events: [WriteBeforeScrollEvent]) {
        let hasCompletedDailyUnlock = events.contains { event in
            event.name == .dailyTargetReached
                || (event.name == .unlockGranted && event.tierRawValue == UnlockTier.daily.rawValue)
        }
        let hasWrittenPastTarget = events.contains { $0.name == .sessionOvershoot }
        gateProgress = EightDayGateStore().refreshDerivedCompletions(
            hasCompletedFirstGate: FirstGateStore().hasCompletedFirstGate,
            protectedTargetCount: signal.selectedApplicationCount
                + signal.selectedCategoryCount
                + signal.selectedWebDomainCount,
            hasCompletedDailyUnlock: hasCompletedDailyUnlock,
            hasWrittenPastTarget: hasWrittenPastTarget,
            isGateOn: signal.isShieldActive || signal.isCurrentlyUnlocked
        )
    }
}
