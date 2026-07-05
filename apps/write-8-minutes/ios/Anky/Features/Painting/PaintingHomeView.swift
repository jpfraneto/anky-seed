import SwiftUI
import FamilyControls

/// THE PAINTING IS THE APP.
///
/// The main screen is a two-page pager: page one is the current level's
/// painting at its true progress, page two the journey map. Everything else
/// (write, quick pass, history, blocked apps) is quiet chrome beneath the
/// frame. No streak pill, no flame, no day counter — the paintings and the
/// journey tiles tell the story in the product's own language.
struct PaintingHomeView: View {
    @ObservedObject var screenTime: WriteBeforeScrollSpikeViewModel
    let onWrite: () -> Void
    let onSetup: () -> Void
    let onSettings: () -> Void
    let onHistory: () -> Void
    let onYou: () -> Void
    let onEmergency: () -> Void

    @State private var signal = SignalCalculator.snapshot(
        screenTimeState: WriteBeforeScrollScreenTimeState(),
        unlockState: UnlockState(grant: nil, lastWroteAt: nil),
        events: [],
        sessionDays: []
    )
    @State private var quickPassesRemaining = QuickPassStore.dailyAllowance
    @State private var dailyTargetMinutes = DailyTargetStore.defaultMinutes
    @State private var levelProgress = AnkyLevel.progress(forTotalSeconds: 0)
    @State private var package: PaintingPackage?
    @State private var revealAssets: PaintingRevealAssets?
    @State private var theme = LevelTheme.fallback
    @State private var displayedProgress: Double = 0
    @State private var strokeBeatSeconds = 0
    @State private var heroPage = 0
    @State private var showsGallery = false
    @State private var ceremonyOwed = false
    @State private var recentSessions: [SessionSummary] = []
    @State private var blockedSelection = FamilyActivitySelection()
    @State private var atBoundary = false
    @State private var showsBoundaryVeil = false
    @State private var showsJourneyPaywall = false
    @EnvironmentObject private var entitlements: EntitlementStore

    private enum GatePhase {
        case needsAuthorization
        case needsSelection
        case ready
    }

    private var phase: GatePhase {
        if !screenTime.isScreenTimeAuthorized { return .needsAuthorization }
        if !signal.isGateConfigured { return .needsSelection }
        return .ready
    }

    var body: some View {
        ZStack {
            LazureWall(mood: theme.wallMood)

            GeometryReader { geometry in
                let frame = PaintingFrameMetrics.frameRect(in: geometry.size)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 24)
                            .padding(.top, 12)

                        heroPager(side: frame.width)
                            .frame(height: frame.width + 44)
                            .padding(.top, max(8, frame.minY - 68))

                        chrome
                            .padding(.horizontal, 24)
                            .padding(.top, 26)
                            .padding(.bottom, 120)
                    }
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            screenTime.refresh()
            refreshEverything()
            playStrokeBeatIfOwed()
        }
        .onChange(of: screenTime.state) { _ in
            refreshSignal()
        }
        .fullScreenCover(isPresented: $showsGallery) {
            GalleryView(currentLevel: levelProgress.level)
        }
        .fullScreenCover(isPresented: $showsBoundaryVeil) {
            BoundaryCeremonyVeilView(entitlements: entitlements)
        }
        .sheet(isPresented: $showsJourneyPaywall) {
            PaywallSheet(store: entitlements, origin: "journey")
        }
        .onChange(of: entitlements.isEntitled) { _ in
            // Unveiling: the boundary dissolves the moment entitlement lands.
            showsBoundaryVeil = false
            refreshEverything()
        }
    }

    // MARK: Hero pager

    private func heroPager(side: CGFloat) -> some View {
        VStack(spacing: 14) {
            TabView(selection: $heroPage) {
                paintingPage(side: side)
                    .tag(0)
                if entitlements.isEntitledForGating {
                    JourneyMapView(side: side)
                        .tag(1)
                } else {
                    // Phase-3 §3: the journey misted, Anky waiting at tile 1.
                    VeiledFeature(
                        surface: "journey",
                        message: AnkyCopyRegistry.veilJourney,
                        onTap: { showsJourneyPaywall = true }
                    ) {
                        JourneyMapView(side: side, heldAtFirstTile: true)
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
                    .tag(1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: side + 8)

            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { page in
                    Circle()
                        .fill(heroPage == page ? Color.ankyGold : Color.ankyInkSoft.opacity(0.28))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: heroPage)
        }
    }

    private func paintingPage(side: CGFloat) -> some View {
        VStack {
            ZStack(alignment: .bottom) {
                Group {
                    if let revealAssets {
                        // A completed painting whose ceremony is still owed
                        // carries a small waiting glow until the unveiling.
                        PaintingView(
                            assets: revealAssets,
                            progress: displayedProgress,
                            glowTint: theme.glowTint,
                            glowStrength: ceremonyOwed ? 1.45 : 1
                        )
                    } else {
                        // Package not ready yet: a waiting canvas, breathing.
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.ankyPaperDeep)
                            .overlay(
                                Text("anky is preparing your canvas…")
                                    .font(.ankyCaption)
                                    .foregroundStyle(Color.ankyInkSoft)
                            )
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .onTapGesture {
                    if strokeBeatSeconds > 0 {
                        skipStrokeBeat()
                    } else if atBoundary {
                        // §2: at the held-100% moment, the painting opens
                        // onto the veiled next canvas, one tap from the ask.
                        showsBoundaryVeil = true
                    } else {
                        showsGallery = true
                    }
                }

                frameFooter
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            .frame(width: side, height: side)
            .overlay(alignment: .topLeading) {
                Text("lvl \(levelProgress.level)")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ankyGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.ankyInk.opacity(0.35), in: Capsule())
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Spiral + progress bar + percent, resting on the frame's bottom edge.
    private var frameFooter: some View {
        HStack(spacing: 10) {
            AnkySunGlyph()
                .frame(width: 18, height: 18)
                .opacity(0.9)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.ankyInk.opacity(0.25))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.ankyGoldLight, .ankyGold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geometry.size.width * displayedProgress))
                }
            }
            .frame(height: 4)

            Text("\(Int((displayedProgress * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ankyPaper)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ankyInk.opacity(0.30), in: Capsule())
    }

    // MARK: Chrome beneath the frame

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 18) {
            primaryCTA

            if phase == .ready, quickPassesRemaining > 0 {
                Button(action: onWrite) {
                    Text("Quick pass — one sentence · \(quickPassesRemaining) left today")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            if !blockedSelection.applicationTokens.isEmpty {
                blockedAppsRow
            }

            historyCard

            footerLinks
        }
    }

    private var primaryCTA: some View {
        Button {
            switch phase {
            case .needsAuthorization, .needsSelection:
                onSetup()
            case .ready:
                onWrite()
            }
        } label: {
            HStack(spacing: 10) {
                AnkySunGlyph()
                    .frame(width: 20, height: 20)
                Text(AnkyLocalization.ui(phase == .ready ? "Write" : (phase == .needsSelection ? "Choose apps" : "Continue setup")))
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Color.ankyInk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [Color.ankyGoldLight, theme.buttonWarmth.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
            .shadow(color: theme.glowTint.opacity(0.30), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var blockedAppsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(blockedSelection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.15)
                        .frame(width: 34, height: 34)
                        .background(Color.ankyPaper.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel(AnkyLocalization.ui("Apps waiting behind the door"))
    }

    /// Dates and times only — never the writing's words. Words stay behind
    /// a tap into history.
    private var historyCard: some View {
        Button(action: onHistory) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AnkyLocalization.ui("History"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.9))
                    .textCase(.uppercase)

                if recentSessions.isEmpty {
                    Text(AnkyLocalization.ui("Your first page is waiting."))
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                } else {
                    ForEach(recentSessions.prefix(3), id: \.hash) { session in
                        HStack {
                            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 15, weight: .medium, design: .serif))
                                .foregroundStyle(Color.ankyInk)
                            Spacer()
                            Text(AnkyDuration.formatted(session.durationMs))
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.ankyInkSoft)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.ankyPaper.opacity(0.80), Color.ankyPaper.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
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
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            if let writerName = WritingAnchorStore().writerName {
                Text(writerName)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ankyInk)
            }
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(width: 38, height: 38)
                    .background(Color.ankyPaper.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("Settings"))
        }
    }

    private var footerLinks: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 22) {
                Button(action: onYou) {
                    Label(AnkyLocalization.ui("You"), systemImage: "person.crop.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            // Phase-2 §2: the emergency door — permanently visible, very
            // quiet, near the "waiting behind the door" chrome. Also the
            // App Review escape hatch.
            Button(action: onEmergency) {
                Text(AnkyLocalization.ui(AnkyCopyRegistry.emergencyLink))
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.55))
                    .underline(false)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: State

    private func refreshEverything() {
        refreshSignal()
        refreshLevel()
    }

    private func refreshSignal() {
        let now = Date()
        let sessions = SessionIndexStore().load()
        recentSessions = sessions
        signal = SignalCalculator.snapshot(
            screenTimeState: screenTime.state,
            unlockState: UnlockStateStore().load(),
            events: WriteBeforeScrollEventLogStore().load(),
            sessionDays: sessions.map(\.createdAt)
        )
        quickPassesRemaining = QuickPassStore().remainingPasses(now: now)
        dailyTargetMinutes = DailyTargetStore().effectiveTargetMinutes(now: now)
        blockedSelection = WriteBeforeScrollScreenTimeSelectionStore().loadSelection()
    }

    private func refreshLevel() {
        let store = LevelProgressStore()
        store.backfillIfNeeded(from: SessionIndexStore().load())
        // Phase-3: the free tier presents the boundary — level 2 serenely
        // complete — while the counter underneath keeps every second.
        let entitled = entitlements.isEntitledForGating
        levelProgress = store.presentedProgress(entitled: entitled)
        atBoundary = store.isAtBoundary(entitled: entitled)
        ceremonyOwed = store.owedCeremonyLevel != nil && !atBoundary

        let assetStore = PaintingAssetStore()
        assetStore.installStarterIfNeeded()
        // The painting for the level the writer is IN; if it isn't installed
        // (yet), fall back to the newest one we have.
        let installed = assetStore.installedPackage(forLevel: levelProgress.level)
            ?? assetStore.installedLevels().last.flatMap { assetStore.installedPackage(forLevel: $0) }
        if package != installed {
            package = installed
            revealAssets = installed.flatMap(PaintingRevealAssets.init)
            theme = LevelTheme(package: installed)
        }
        displayedProgress = paintingProgress
    }

    /// The reveal progress of the displayed painting. A painting behind the
    /// writer's current level is complete; the current level's reveals by
    /// percent within the level.
    private var paintingProgress: Double {
        guard let package else { return 0 }
        if package.level < levelProgress.level { return 1 }
        return levelProgress.percent
    }

    // MARK: Post-session stroke beat

    /// Today's strokes arrive over ~2-3s, proportional to seconds written.
    private func playStrokeBeatIfOwed() {
        let pending = LevelProgressStore().consumePendingStrokeSeconds()
        guard pending > 0, revealAssets != nil else { return }
        strokeBeatSeconds = pending

        let target = paintingProgress
        let delta = min(Double(pending) / Double(max(1, levelProgress.secondsRequired)), target)
        displayedProgress = max(0, target - delta)

        // Proportional: a 12-minute session visibly paints more than one
        // sentence — longer sessions get the full three seconds.
        let duration = min(3.0, 1.2 + Double(pending) / 240.0)
        withAnimation(.easeInOut(duration: duration)) {
            displayedProgress = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            strokeBeatSeconds = 0
        }
    }

    private func skipStrokeBeat() {
        strokeBeatSeconds = 0
        withAnimation(.easeOut(duration: 0.2)) {
            displayedProgress = paintingProgress
        }
    }
}

/// Phase-3 §2: the pending moment at the boundary. The level-2 painting is
/// complete and stays theirs; the *next* canvas waits under the veil, one
/// tap from the paywall. Serene, never broken — the bar behind reads 100%.
private struct BoundaryCeremonyVeilView: View {
    @ObservedObject var entitlements: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsPaywall = false

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                VeiledFeature(
                    surface: "ceremony",
                    message: AnkyCopyRegistry.veilCeremony,
                    onTap: { showsPaywall = true }
                ) {
                    // The waiting canvas — the same breathing paper the
                    // entitled see while anky paints.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.ankyPaperDeep)
                        .aspectRatio(1, contentMode: .fit)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 44)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(AnkyLocalization.ui("not yet"))
                        .font(.ankyCaption)
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.bottom, 44)
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallSheet(store: entitlements, origin: "ceremony")
        }
        .onChange(of: entitlements.isEntitled) { entitled in
            if entitled {
                dismiss()
            }
        }
    }
}

