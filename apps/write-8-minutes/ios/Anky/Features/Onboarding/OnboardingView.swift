import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Analytics-free local record of where the flow was left, for physical QA.
/// 1–11 = the in-view screens (10 = paywall), 12 = gate setup, 13 = the
/// Day 1 threshold, 0 = finished. Never leaves the device.
enum OnboardingFlowProgress {
    static let key = "anky.onboardingLastScreen"

    static func mark(_ screen: Int) {
        UserDefaults.standard.set(screen, forKey: key)
    }

    static func markFinished() {
        UserDefaults.standard.set(0, forKey: key)
    }
}

/// The 13-screen onboarding. Screens 1–5 are the pre-dawn world (the scroll
/// world, aubergine washes pooling on parchment); from screen 6 the lazure
/// paper wall dawns behind Anky and stays — including screen 10, the paywall:
/// the world turned to light at Meet Anky, and the thread does not un-fill
/// because money entered the room. One tap or gesture per screen; the only
/// typing is the optional name. Screens 12 (gate setup) and 13 (Day 1
/// threshold) live in AppRoot — this view ends by calling `onFinished`.
struct AnkyOnboardingView: View {
    @ObservedObject var entitlements: EntitlementStore
    let onFinished: () -> Void

    @State private var screen = 1
    @State private var writerName = ""
    @State private var targetMinutes: Double = Double(DailyTargetStore.defaultMinutes)
    @State private var phoneHoursBracket: PhoneHoursBracket?
    @State private var mathBeatOneVisible = false
    @State private var mathBeatTwoVisible = false
    @State private var mathCTAVisible = false
    @State private var notificationsDenied = false
    @State private var isRequestingNotifications = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var showsSelfieCamera = false
    @State private var avatarImage: UIImage? = AvatarStore().loadImage()

    private static let dawnStartScreen = 6
    private static let targetScreenIndex = 8
    private static let paywallScreenIndex = 10
    private static let screenCount = 11

    private var isDawn: Bool {
        screen >= Self.dawnStartScreen
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Group {
                    switch screen {
                    case 1: problemScreen
                    case 2: solutionScreen
                    case 3: mechanismScreen
                    case 4: hoursScreen
                    case 5: mathScreen
                    case 6: meetAnkyScreen
                    case 7: nameScreen
                    case 8: targetScreen
                    case 9: paintingsScreen
                    case 10: paywallScreen
                    default: notificationsScreen
                    }
                }
                .transition(.opacity)

                OnboardingDots(current: screen, total: Self.screenCount, isDawn: isDawn)
                    .padding(.top, 20)
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 30)
            // AppRoot ignores the keyboard safe area globally, so the flow
            // makes its own room: the content column lifts above the keyboard.
            .padding(.bottom, keyboardHeight)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        }
        .ignoresSafeArea()
        .simultaneousGesture(onboardingSwipeGesture)
        .animation(.easeInOut(duration: 0.35), value: screen)
        .onAppear {
            OnboardingFlowProgress.mark(screen)
        }
        .onChange(of: screen) { newScreen in
            OnboardingFlowProgress.mark(newScreen)
            if newScreen == 5 {
                revealMathBeats()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            keyboardHeight = max(0, UIScreen.main.bounds.maxY - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .fullScreenCover(isPresented: $showsSelfieCamera) {
            SelfieCameraPicker { image in
                if let image {
                    avatarImage = image
                    AvatarStore().save(image)
                }
                showsSelfieCamera = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Background (pre-dawn aubergine → dawn)

    private var background: some View {
        ZStack {
            Color.ankyPaper.ignoresSafeArea()

            // The scroll world before dawn: deep violet lazure pooling on
            // parchment — the ceremony's aubergine register, never black.
            LazureWall(mood: .dusk)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.ankyViolet.opacity(0.26),
                            Color.ankyViolet.opacity(0.08),
                            Color.ankyRose.opacity(0.10),
                            Color.ankyViolet.opacity(0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                )
                .opacity(isDawn ? 0 : 1)

            LazureWall(mood: .dawn)
                .opacity(isDawn ? 1 : 0)

            // A breathing wash for the one true threshold: the world
            // turning to light when Anky steps forward.
            if screen == Self.dawnStartScreen {
                WatercolorVeilView(register: .pale)
                    .opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: isDawn)
    }

    // MARK: - Screen 1 · The problem

    private var problemScreen: some View {
        VStack(spacing: 13) {
            onboardingImage("onboarding-1")
            nightTitle("The world is thinking for you.")
            nightBody("Every morning, someone else decides what will shape your day.")
            nightCTA("I know.") { advance() }
        }
    }

    // MARK: - Screen 2 · The solution

    private var solutionScreen: some View {
        VStack(spacing: 13) {
            onboardingImage("onboarding-2")
            nightTitle("Anky puts a door before the noise.")
            nightBody("Your apps stay locked until you've heard from yourself first.")
            nightCTA("How does it work?") { advance() }
        }
    }

    // MARK: - Screen 3 · The mechanism

    private var mechanismScreen: some View {
        VStack(spacing: 13) {
            onboardingImage("onboarding-3")
            nightTitle("Write before you scroll.")
            VStack(spacing: 8) {
                nightBody("One sentence opens your apps for 15 minutes.")
                nightBody("Your daily writing opens them for the rest of the day.")
            }
            nightCTA("Show me the cost.") { advance() }
        }
    }

    private func onboardingImage(_ name: String, maxWidth: CGFloat = 400, height: CGFloat = 480) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .frame(height: height)
            .shadow(color: Color.ankyGold.opacity(0.16), radius: 18, y: 8)
            .offset(y: -20)
            .padding(.bottom, -20)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    // MARK: - Screen 4 · Make it personal

    private var hoursScreen: some View {
        VStack(spacing: 12) {
            onboardingImage("onboarding-4", maxWidth: 368, height: 336)
            nightTitle("How many hours a day are you on your phone?")
            nightBody("Be honest.")

            VStack(spacing: 10) {
                ForEach(PhoneHoursBracket.allCases, id: \.self) { bracket in
                    Button {
                        AnkyHaptics.light()
                        phoneHoursBracket = bracket
                        UserDefaults.standard.set(bracket.rawValue, forKey: "anky.dailyPhoneHours")
                        advance(haptic: false)
                    } label: {
                        Text(AnkyLocalization.ui(bracket.label))
                            .font(.system(size: 19, weight: .medium, design: .serif))
                            .foregroundStyle(Color.ankyInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background {
                                Capsule()
                                    .fill(Color.ankyPaper.opacity(0.72))
                                    .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.45), lineWidth: 0.7))
                                    .shadow(color: Color.ankyViolet.opacity(0.14), radius: 10, y: 3)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Screen 5 · The visceral math

    private var mathScreen: some View {
        VStack(spacing: 14) {
            onboardingImage("onboarding-5", maxWidth: 344, height: 304)

            VStack(spacing: 6) {
                Text(AnkyLocalization.ui("That's \(wakingYears) years"))
                    .font(.system(size: 52, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ankyMadder)
                    .shadow(color: Color.ankyRose.opacity(0.40), radius: 14)
                Text(AnkyLocalization.ui("of your waking life."))
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
            }
            .opacity(mathBeatOneVisible ? 1 : 0)
            .offset(y: mathBeatOneVisible ? 0 : 10)

            Text(AnkyLocalization.ui("What if you used a small part of that to connect with yourself first?"))
                .font(.system(size: 21, weight: .medium, design: .serif))
                .foregroundStyle(Color.ankyUmber)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .opacity(mathBeatTwoVisible ? 1 : 0)
                .offset(y: mathBeatTwoVisible ? 0 : 10)

            nightCTA("Show me how.") { advance() }
                .opacity(mathCTAVisible ? 1 : 0)
        }
        .multilineTextAlignment(.center)
    }

    /// round(hours × 40 / 16) on the bracket midpoint — a lifetime of
    /// adult years spent inside the feed.
    private var wakingYears: Int {
        let hours = phoneHoursBracket?.midpointHours ?? 3.5
        return max(1, Int((hours * 40 / 16).rounded()))
    }

    private func revealMathBeats() {
        mathBeatOneVisible = false
        mathBeatTwoVisible = false
        mathCTAVisible = false
        withAnimation(.easeOut(duration: 0.6).delay(0.15)) { mathBeatOneVisible = true }
        withAnimation(.easeOut(duration: 0.6).delay(0.95)) { mathBeatTwoVisible = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.7)) { mathCTAVisible = true }
    }

    // MARK: - Screen 6 · Meet Anky (dawn)

    private var meetAnkyScreen: some View {
        VStack(spacing: 18) {
            AnkySpriteView(sequence: .waveFront, size: 190)

            Text(AnkyLocalization.ui("This is Anky."))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)

            dawnBody("I hold the door. I open it when you write with me. I'm not here to keep you out — I'm here to make sure you go in first.")

            dawnCTA("Hi, Anky.") { advance() }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Screen 7 · The name

    private var nameScreen: some View {
        VStack(spacing: 18) {
            // Anky listens for the name — and steps aside when the
            // keyboard needs the room.
            if keyboardHeight == 0 {
                AnkySpriteView(sequence: .shyListening, size: 110)
                    .transition(.opacity)
            }

            Text(AnkyLocalization.ui("What should I call you?"))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                selfieButton
            }

            VeilCard {
                TextField(
                    text: $writerName,
                    prompt: Text(AnkyLocalization.ui("Your name"))
                        .foregroundColor(Color.ankyInkSoft.opacity(0.72))
                ) {
                    EmptyView()
                }
                    .font(.ankyProse)
                    .foregroundStyle(Color.ankyInk)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { saveNameAndAdvance() }
            }

            Text(AnkyLocalization.ui("Stays on this phone. Nothing you write ever leaves unsealed."))
                .font(.ankyCaption)
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)

            dawnCTA("Continue") { saveNameAndAdvance() }

            Button {
                writerName = ""
                AnkyHaptics.light()
                advance()
            } label: {
                Text(AnkyLocalization.ui("later"))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    /// The optional selfie: taken once here, kept only on this phone,
    /// and worn as the writer's face across the rest of the app.
    private var selfieButton: some View {
        Button {
            AnkyHaptics.light()
            showsSelfieCamera = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 92)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.ankyPaper.opacity(0.62))
                            .frame(width: 92, height: 92)

                        Image(systemName: "camera")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Color.ankyInkSoft)
                    }
                }
                .overlay(Circle().strokeBorder(Color.ankyGold.opacity(0.55), lineWidth: 1))
                .shadow(color: Color.ankyViolet.opacity(0.16), radius: 12, y: 4)

                Text(AnkyLocalization.ui(avatarImage == nil ? "add a selfie" : "retake"))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnkyLocalization.ui("Take a selfie"))
    }

    private func saveNameAndAdvance() {
        let store = WritingAnchorStore()
        store.save(writerName: writerName, anchorSentence: store.anchorSentence)
        advance()
    }

    // MARK: - Screen 8 · The target

    private var targetScreen: some View {
        VStack(spacing: 18) {
            AnkySpriteView(sequence: .seated, size: 110)

            Text(AnkyLocalization.ui("Choose a daily writing target."))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            VeilCard {
                VStack(spacing: 14) {
                    Text(AnkyLocalization.ui("\(Int(targetMinutes)) minute\(Int(targetMinutes) == 1 ? "" : "s") a day"))
                        .font(.ankyHeading)
                        .foregroundStyle(Color.ankyInk)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.15), value: Int(targetMinutes))

                    Slider(
                        value: $targetMinutes,
                        in: Double(DailyTargetStore.minutesRange.lowerBound)...Double(DailyTargetStore.minutesRange.upperBound),
                        step: 1
                    )
                    .tint(Color.ankyGold)

                    HStack(spacing: 0) {
                        ForEach(DailyTargetStore.minutesRange, id: \.self) { minute in
                            Button {
                                AnkyHaptics.selection()
                                targetMinutes = Double(minute)
                            } label: {
                                Text("\(minute)")
                                    .font(.system(size: 14, weight: minute == Int(targetMinutes) ? .semibold : .regular, design: .monospaced))
                                    .foregroundStyle(minute == Int(targetMinutes) ? Color.ankyGold : Color.ankyInkSoft.opacity(0.55))
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                    .animation(.easeOut(duration: 0.15), value: Int(targetMinutes))
                }
            }

            Text(AnkyLocalization.ui("This is a floor, not a ceiling. I will never stop you at the target — and I'll never cut you off."))
                .font(.ankyCaption)
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            dawnCTA("Commit to \(targetMinutes.formatted(.number.precision(.fractionLength(0)))) minutes a day.") {
                let chosenMinutes = Int(targetMinutes)
                DailyTargetStore().setInitialTarget(chosenMinutes)
                WriteBeforeScrollEventLogStore().append(
                    .onboardingTargetSet,
                    metadata: [
                        "targetMinutes": "\(chosenMinutes)",
                        "changedFromDefault": "\(chosenMinutes != DailyTargetStore.defaultMinutes)"
                    ]
                )
                advance()
            }
        }
    }

    // MARK: - Screen 9 · The paintings

    /// The reward, shown before the ask: the first painting fully revealed
    /// (bundled, so it renders offline) above the locked underdrawings of
    /// what's waiting — the same tiles the gallery shows after Day 1.
    private var paintingsScreen: some View {
        VStack(spacing: 18) {
            Text(AnkyLocalization.ui("Your words become paintings."))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                OnboardingHeroPainting()
                    .frame(maxWidth: 240)

                Text(AnkyLocalization.ui("“The Door” · your first canvas"))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft)
            }

            HStack(spacing: 12) {
                ForEach(2...5, id: \.self) { level in
                    OnboardingLockedPaintingTile(level: level)
                }
            }
            .frame(maxWidth: 320)

            dawnBody("As you write, I paint. Every minute reveals another stroke of the canvas — and when a painting completes, the next is already waiting.")

            Text(AnkyLocalization.ui("Day 1 begins the moment you close this screen."))
                .font(.ankyCaption)
                .foregroundStyle(Color.ankyInkSoft)

            dawnCTA("Begin.") { advance() }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Screen 10 · The paywall (post-dawn, same room as the map)

    /// The ask, placed after the paintings promise (the reward made
    /// visible) and before the Day 1 threshold. Hard gate — skippability
    /// lives inside PaywallView behind `paywallIsSkippable`.
    private var paywallScreen: some View {
        PaywallView(store: entitlements, context: .onboarding) {
            advance(haptic: false)
        }
        .onAppear {
            // Returning subscriber, restore, or QA re-run: the ask was
            // already answered — continue to notifications.
            if entitlements.isEntitledForGating {
                advance(haptic: false)
            }
        }
    }

    // MARK: - Screen 11 · Notifications

    private var notificationsScreen: some View {
        VStack(spacing: 18) {
            AnkySpriteView(sequence: .idleFront, size: 130)

            Text(AnkyLocalization.ui("When your apps knock, I'll answer."))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            dawnBody("When a blocked app tries to open, I send you a notification. Tap it, write with me, and the door opens. Without this, the door has no handle.")

            if notificationsDenied {
                Text(AnkyLocalization.ui("You can turn this on later in Settings."))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft)
                    .transition(.opacity)
            }

            dawnCTA("Allow notifications") {
                requestNotifications()
            }
            .disabled(isRequestingNotifications)
        }
        .multilineTextAlignment(.center)
    }

    private func requestNotifications() {
        guard !isRequestingNotifications else { return }
        isRequestingNotifications = true
        Task { @MainActor in
            let granted = await LocalNotificationScheduler().requestAuthorization()
            // The trial started one screen before permission existed —
            // place the honest reminder now that it can actually fire.
            await entitlements.syncTrialReminder()
            if granted {
                onFinished()
            } else {
                withAnimation(.easeOut(duration: 0.3)) { notificationsDenied = true }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                onFinished()
            }
        }
    }

    // MARK: - Shared pieces

    private var onboardingSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36, coordinateSpace: .local)
            .onEnded { value in
                guard screen != Self.targetScreenIndex else {
                    return
                }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 70, abs(horizontal) > abs(vertical) * 1.35 else {
                    return
                }
                if horizontal < 0 {
                    advanceFromSwipe()
                } else {
                    retreatFromSwipe()
                }
            }
    }

    private func advanceFromSwipe() {
        guard screen < Self.screenCount else {
            return
        }
        guard screen != Self.paywallScreenIndex else {
            return
        }
        advance(haptic: true)
    }

    private func retreatFromSwipe() {
        var previous = screen - 1
        if previous == Self.paywallScreenIndex && entitlements.isEntitledForGating {
            previous -= 1
        }
        guard previous >= 1 else {
            return
        }
        AnkyHaptics.light()
        withAnimation(.easeInOut(duration: 0.35)) {
            screen = previous
        }
    }

    private func advance(haptic: Bool = false) {
        if haptic {
            AnkyHaptics.light()
        }
        var next = screen + 1
        if next == Self.paywallScreenIndex && entitlements.isEntitledForGating {
            // Returning subscriber: the ask was already answered.
            next += 1
        }
        if next <= Self.screenCount {
            withAnimation(.easeInOut(duration: 0.35)) { screen = next }
        } else {
            onFinished()
        }
    }

    private func nightTitle(_ text: String) -> some View {
        Text(AnkyLocalization.ui(text))
            .font(.system(size: 27, weight: .medium, design: .serif))
            .foregroundStyle(Color.ankyInk)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .minimumScaleFactor(0.78)
    }

    private func nightBody(_ text: String) -> some View {
        Text(AnkyLocalization.ui(text))
            .font(.system(size: 17, weight: .regular, design: .serif))
            .foregroundStyle(Color.ankyInkSoft)
            .multilineTextAlignment(.center)
            .lineSpacing(6)
            .minimumScaleFactor(0.8)
    }

    private func dawnBody(_ text: String) -> some View {
        Text(AnkyLocalization.ui(text))
            .font(.ankyProse)
            .foregroundStyle(Color.ankyInkSoft)
            .lineSpacing(5)
            .multilineTextAlignment(.center)
    }

    /// Pre-dawn CTA: the golden thread as a thin outline on parchment —
    /// at dawn (ThreadButtonStyle) it fills with light.
    private func nightCTA(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            Text(AnkyLocalization.ui(title))
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Color.ankyInk)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.ankyPaper.opacity(0.85), Color.ankyGoldLight.opacity(0.45)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay {
                            Capsule().strokeBorder(
                                LinearGradient(
                                    colors: [Color.ankyGoldLight, Color.ankyGold],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                        }
                        .shadow(color: Color.ankyGold.opacity(0.24), radius: 14, y: 4)
                }
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private func dawnCTA(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            Text(AnkyLocalization.ui(title))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ThreadButtonStyle())
        .padding(.top, 12)
    }
}

// MARK: - Phone hours brackets

private enum PhoneHoursBracket: String, CaseIterable {
    case oneToTwo = "1-2"
    case threeToFour = "3-4"
    case fiveToSix = "5-6"
    case sevenPlus = "7+"

    var label: String {
        switch self {
        case .oneToTwo: return "1–2 hours"
        case .threeToFour: return "3–4 hours"
        case .fiveToSix: return "5–6 hours"
        case .sevenPlus: return "7+ hours"
        }
    }

    var midpointHours: Double {
        switch self {
        case .oneToTwo: return 1.5
        case .threeToFour: return 3.5
        case .fiveToSix: return 5.5
        case .sevenPlus: return 8
        }
    }
}

// MARK: - Paintings screen pieces

/// The bundled level-1 painting, fully revealed — the one image that is
/// guaranteed to exist before any network call, framed the way the gallery
/// frames every finished Anky.
private struct OnboardingHeroPainting: View {
    private static let image: UIImage? = {
        guard
            let url = Bundle.main.url(
                forResource: "final",
                withExtension: "png",
                subdirectory: "StarterPainting"
            )
        else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Color.ankyPaper
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.ankyGold.opacity(0.55), lineWidth: PaintingFrameMetrics.borderWidth)
        )
        .shadow(color: Color.ankyGold.opacity(0.28), radius: 18, y: 6)
        .accessibilityHidden(true)
    }
}

/// A future painting, small: its underdrawing (cached webp from the CDN,
/// parchment while it loads or offline) behind a quiet lock — the same
/// promise the gallery's locked tiles keep after Day 1.
private struct OnboardingLockedPaintingTile: View {
    let level: Int
    @State private var underdrawing: UIImage?

    var body: some View {
        ZStack {
            Group {
                if let underdrawing {
                    Image(uiImage: underdrawing)
                        .resizable()
                } else {
                    Color.ankyPaper.opacity(0.85)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.ankyGold.opacity(0.45), lineWidth: 1)
            )

            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ankyInkSoft)
                .frame(width: 26, height: 26)
                .background(Color.ankyPaper.opacity(0.72), in: Circle())
        }
        .accessibilityHidden(true)
        .task(id: level) {
            underdrawing = await StaticPaintingCDN.loadUnderdrawing(level: level)
        }
    }
}

// MARK: - Progress dots

private struct OnboardingDots: View {
    let current: Int
    let total: Int
    let isDawn: Bool

    var body: some View {
        HStack(spacing: 9) {
            ForEach(1...total, id: \.self) { index in
                Circle()
                    .fill(dotColor(index))
                    .frame(width: index == current ? 8 : 6,
                           height: index == current ? 8 : 6)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
    }

    private func dotColor(_ index: Int) -> Color {
        if index == current {
            return .ankyGold
        }
        return isDawn ? Color.ankyInk.opacity(0.18) : Color.ankyViolet.opacity(0.32)
    }
}

// MARK: - Selfie camera

/// Front-camera capture for the writer's avatar. The image never leaves
/// the device — AvatarStore keeps it in the app's Documents directory.
private struct SelfieCameraPicker: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onComplete(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }
    }
}

// MARK: - Screen 12 · Day 1 threshold overlay

/// Shown by AppRoot over the live writing surface after gate setup.
/// Dismissing it is the moment onboarding completes — the person steps
/// through the door and the session is already breathing underneath.
struct DayOneThresholdOverlay: View {
    let onStartWriting: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.ankyPaper.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                AnkySunGlyph(size: 44, color: .ankyGold)

                Text(AnkyLocalization.ui("Day 1."))
                    .font(.system(size: 44, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ankyInk)

                Text(AnkyLocalization.ui("Write whatever is in your mind."))
                    .font(.ankyHeading)
                    .foregroundStyle(Color.ankyInkSoft)

                Button {
                    AnkyHaptics.success()
                    AnkyHaptics.medium()
                    onStartWriting()
                } label: {
                    Text(AnkyLocalization.ui("Start writing"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ThreadButtonStyle())
                .padding(.top, 10)
            }
            .padding(.horizontal, 44)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            OnboardingFlowProgress.mark(13)
        }
    }
}
