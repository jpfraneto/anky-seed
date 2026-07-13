import SwiftUI

/// The level-up ceremony.
///
/// The frame never moves — PaintingFrameMetrics places it exactly where the
/// main screen holds it; the world darkens and blooms around it. Sequence:
/// final strokes → held breath → candlelit aubergine → WELCOME TO LEVEL {N}
/// → the 8-second glimpse (bloom, breath, recede) → ghost Begin → drain.
struct UnveilCeremonyView: View {
    let level: Int
    let coordinator: LevelPaintingCoordinator
    let onFinished: () -> Void

    private enum Beat {
        case finalStrokes
        case heldBreath
        case darkening
        case title
        case waitingForGlimpse
        case glimpseBloom
        case glimpseHold
        case glimpseRecede
        case begin
        case drain
    }

    @State private var beat: Beat = .finalStrokes
    @State private var completedAssets: PaintingRevealAssets?
    @State private var completedTitle = ""
    @State private var glimpseAssets: PaintingRevealAssets?
    @State private var completedProgress: Double = 0.72
    @State private var glimpseProgress: Double = 0
    @State private var darkness: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var beginOpacity: Double = 0
    @State private var glowOvershoot: Double = 0
    @State private var contentOpacity: Double = 1
    @State private var theme = LevelTheme.fallback
    @State private var showsInfo = false

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geometry in
                // The frame holds the exact spot the main screen measured for
                // its painting — the ceremony → main transition never moves it.
                let frame = PaintingFramePosition.lastHomeGlobalRect
                    ?? PaintingFrameMetrics.frameRect(in: geometry.size)

                ZStack {
                    // The room: warm paper below, living aubergine darkness above.
                    LazureWall(mood: theme.wallMood)
                    aubergineDarkness
                        .opacity(darkness)

                    if beat == .waitingForGlimpse {
                        PaintingGenerationWaitView()
                            .transition(.opacity)
                    }

                    // The never-moving frame.
                    Group {
                        if showsGlimpsePainting, let glimpseAssets {
                            PaintingView(
                                assets: glimpseAssets,
                                progress: glimpseProgress,
                                glowTint: theme.glowTint,
                                glowStrength: 1 + glowOvershoot
                            )
                        } else if let completedAssets {
                            PaintingView(
                                assets: completedAssets,
                                progress: completedProgress,
                                glowTint: theme.glowTint,
                                glowStrength: 1 + glowOvershoot
                            )
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                    ceremonyText(frame: frame, containerSize: geometry.size)
                        .opacity(titleOpacity * contentOpacity)

                    beginButton(frame: frame, containerSize: geometry.size)
                        .opacity(beginOpacity * contentOpacity)
                }
            }
            .ignoresSafeArea()

            // Quiet exits above the room: the writer is never held hostage
            // by a ceremony — skip on the left, what-is-this on the right.
            ceremonyTopBar
                .opacity(contentOpacity)
        }
        .onAppear(perform: start)
        .sheet(isPresented: $showsInfo) {
            CeremonyInfoSheet(level: level)
        }
    }

    private var ceremonyTopBar: some View {
        HStack {
            Button {
                guard beat != .drain else { return }
                drainAndFinish()
            } label: {
                Text(AnkyLocalization.ui("skip"))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ankyPaperDeep.opacity(0.75))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("Skip the unveiling"))

            Spacer()

            Button {
                showsInfo = true
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ankyPaperDeep.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Color.ankyInk.opacity(0.25), in: Circle())
                    .overlay(Circle().strokeBorder(Color.ankyGold.opacity(0.30), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("What is happening?"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var showsGlimpsePainting: Bool {
        switch beat {
        case .glimpseBloom, .glimpseHold, .glimpseRecede, .begin, .drain:
            return glimpseAssets != nil
        default:
            return false
        }
    }

    /// Candlelit aubergine breathing into burnt umber — never pure black.
    private var aubergineDarkness: some View {
        ZStack {
            Color(.displayP3, red: 0.16, green: 0.10, blue: 0.17) // deep aubergine
            RadialGradient(
                colors: [
                    Color(.displayP3, red: 0.32, green: 0.18, blue: 0.10).opacity(0.55), // burnt umber warmth
                    Color.clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    private func ceremonyText(frame: CGRect, containerSize: CGSize) -> some View {
        VStack(spacing: 14) {
            Text(AnkyLocalization.ui("WELCOME TO LEVEL %d", level))
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .tracking(6)
                .foregroundStyle(Color.ankyGold)

            if !completedTitle.isEmpty {
                Text(AnkyLocalization.ui("ceremony revealed title format", completedTitle, AnkyLevel.thresholdSeconds(forLevel: level).formatted()))
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyPaperDeep.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .position(x: containerSize.width / 2, y: frame.maxY + 64)
    }

    private func beginButton(frame: CGRect, containerSize: CGSize) -> some View {
        Button {
            drainAndFinish()
        } label: {
            Text(AnkyLocalization.ui("Begin"))
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(Color.ankyGoldLight)
                .padding(.horizontal, 38)
                .padding(.vertical, 12)
                .background(
                    Capsule().strokeBorder(Color.ankyGold.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .position(x: containerSize.width / 2, y: frame.maxY + 140)
    }

    // MARK: The sequence

    private func start() {
        let packages = coordinator.ceremonyPackages(forLevel: level)
        completedAssets = packages.completed.flatMap(PaintingRevealAssets.init)
        completedTitle = packages.completed?.title ?? ""
        glimpseAssets = packages.glimpse.flatMap(PaintingRevealAssets.init)
        theme = LevelTheme(package: packages.glimpse ?? packages.completed)

        // 1. The final strokes land. The painting view is inserted in this
        // same render pass, so the animation must start one tick later —
        // otherwise SwiftUI materializes it directly at the end value.
        completedProgress = 0.72
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: CeremonyTiming.finalStrokesSeconds)) {
                completedProgress = 1
            }
        }
        after(CeremonyTiming.finalStrokesSeconds) {
            beat = .heldBreath
            after(CeremonyTiming.heldBreathSeconds) {
                beat = .darkening
                withAnimation(.easeInOut(duration: CeremonyTiming.darkeningSeconds)) {
                    darkness = 1
                }
                after(CeremonyTiming.darkeningSeconds) {
                    beat = .title
                    withAnimation(.easeIn(duration: CeremonyTiming.titleFadeSeconds)) {
                        titleOpacity = 1
                    }
                    after(CeremonyTiming.titleFadeSeconds) {
                        beginGlimpse()
                    }
                }
            }
        }
    }

    private func beginGlimpse() {
        if glimpseAssets != nil {
            playGlimpse()
            return
        }
        // The writer outran generation: the darkness breathes a short while,
        // then the ceremony moves on regardless — Begin is never withheld.
        beat = .waitingForGlimpse
        Task {
            if let package = await coordinator.waitForCeremonyPackage(level: level, attempts: 6) {
                glimpseAssets = PaintingRevealAssets(package: package)
                theme = LevelTheme(package: package)
            }
            guard beat == .waitingForGlimpse else {
                return // the writer already skipped out
            }
            playGlimpse()
        }
    }

    private func playGlimpse() {
        guard glimpseAssets != nil else {
            // Generation is still breathing; don't hold the writer hostage —
            // the glimpse will be waiting on the main painting instead.
            showBegin()
            return
        }
        // The glimpse painting enters this render pass at 0; the 8-second
        // bloom starts on the next tick so the insertion doesn't swallow it.
        beat = .glimpseBloom
        glimpseProgress = 0
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: CeremonyTiming.glimpseBloomSeconds)) {
                glimpseProgress = 1
            }
        }
        after(CeremonyTiming.glimpseBloomSeconds) {
            beat = .glimpseHold
            after(CeremonyTiming.glimpseHoldSeconds) {
                beat = .glimpseRecede
                withAnimation(.easeInOut(duration: CeremonyTiming.glimpseRecedeSeconds)) {
                    glimpseProgress = 0
                }
                // Begin fades in during the recede — anky shows you where
                // you're going; you earn it back stroke by stroke.
                showBegin()
            }
        }
    }

    private func showBegin() {
        beat = .begin
        withAnimation(.easeIn(duration: CeremonyTiming.beginFadeSeconds)) {
            beginOpacity = 1
        }
    }

    private func drainAndFinish() {
        beat = .drain
        coordinator.markCeremonyShown(level)
        withAnimation(.easeOut(duration: 0.6)) {
            contentOpacity = 0
        }
        // Pigment bleeds outward into the room: the glow overshoots in the
        // palette, then settles as the darkness lifts.
        withAnimation(.easeInOut(duration: CeremonyTiming.drainSeconds * 0.45)) {
            glowOvershoot = 1.6
        }
        withAnimation(.easeInOut(duration: CeremonyTiming.drainSeconds).delay(CeremonyTiming.drainSeconds * 0.25)) {
            glowOvershoot = 0
            darkness = 0
        }
        after(CeremonyTiming.drainSeconds) {
            onFinished()
        }
    }

    private func after(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

private struct PaintingGenerationWaitView: View {
    var body: some View {
        ZStack {
            WatercolorVeilView(register: .aubergine)

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.ankyGoldLight.opacity(0.85))
                Text(AnkyLocalization.ui(AnkyCopyRegistry.generationWait))
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ankyGoldLight)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The small "what is happening" sheet behind the ceremony's info button.
private struct CeremonyInfoSheet: View {
    let level: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    AnkySunGlyph(size: 26, color: .ankyGold)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ankyInkSoft)
                            .frame(width: 34, height: 34)
                            .background(Color.ankyPaper.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.ui("Close"))
                }

                Text(AnkyLocalization.ui("The unveiling"))
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ankyInk)

                Text(AnkyLocalization.ui("Every level of your practice is a painting. Each second you write reveals the current one, stroke by stroke — and past level 8, Anky paints each canvas from the essence of your writing, never the words themselves."))
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AnkyLocalization.ui("You just completed a painting. It hangs in your gallery now, finished and yours. What blooms and recedes here is a glimpse of the next canvas — you earn it back stroke by stroke."))
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(28)
        }
        .presentationDetents([.medium, .large])
    }
}
