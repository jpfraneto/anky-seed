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
    @State private var nameImageScale: CGFloat = 1
    @FocusState private var isNameFieldFocused: Bool
    @State private var swipeTranslation: CGFloat = 0
    @State private var swipeTargetScreen: Int?
    @State private var swipeLockedHorizontal: Bool?
    @State private var isSettlingSwipe = false

    private static let dawnStartScreen = 6
    private static let targetScreenIndex = 8
    private static let paywallScreenIndex = 10
    private static let screenCount = 11
    private static let ctaFooterHeight: CGFloat = 16

    private var isDawn: Bool {
        screen >= Self.dawnStartScreen
    }

    private var keyboardLift: CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        return screen == 7 ? min(28, keyboardHeight * 0.12) : keyboardHeight
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                // The pager: the current screen rides the finger, its
                // neighbor slides in from the side — the native page feel.
                // CTA taps keep the quieter crossfade.
                ZStack {
                    screenView(screen)
                        .offset(x: swipeTranslation)

                    if let target = swipeTargetScreen {
                        screenView(target)
                            .offset(x: swipeTranslation + (target > screen ? pageWidth : -pageWidth))
                    }
                }

                OnboardingDots(current: screen, total: Self.screenCount, isDawn: isDawn)
                    .padding(.top, 20)
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, keyboardLift)
            .animation(.easeOut(duration: 0.25), value: keyboardLift)
        }
        .ignoresSafeArea()
        .simultaneousGesture(onboardingSwipeGesture)
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

    // MARK: - Pager

    @ViewBuilder
    private func screenView(_ index: Int) -> some View {
        Group {
            switch index {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }

    private var pageWidth: CGFloat {
        UIScreen.main.bounds.width
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
            nightTitle("The world thinks for you.")
            nightBody("Every morning, an algorithm decides what is on your mind.")
            nightCTA("I know.") { advance() }
        }
    }

    // MARK: - Screen 2 · The solution

    private var solutionScreen: some View {
        VStack(spacing: 13) {
            onboardingImage("anky-flow-door-before-noise")
            nightTitle("Anky puts a door before the noise.")
            nightBody("Your most distracting apps stay locked until you hear your own voice.")
            nightCTA("How does it work?") { advance() }
        }
    }

    // MARK: - Screen 3 · The mechanism

    private var mechanismScreen: some View {
        VStack(spacing: 13) {
            onboardingImage("onboarding-3")
            nightTitle("Write before you scroll.")
            nightBody("One sentence grants a free 15-minute Quick Pass. With Anky Pro, reaching your daily target automatically unlocks protected apps for the rest of the day.")
            nightCTA("Look at my day.") { advance() }
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

    private func flowImage(_ name: String, maxWidth: CGFloat, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .frame(height: height)
            .shadow(color: Color.ankyGold.opacity(0.12), radius: 14, y: 5)
            .accessibilityHidden(true)
    }

    // MARK: - Screen 4 · Make it personal

    private var hoursScreen: some View {
        VStack(spacing: 12) {
            onboardingImage("onboarding-4", maxWidth: 368, height: 336)
            nightTitle("How many hours a day are you on your phone?")
            nightBody("(Be honest)")

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
                Text(AnkyLocalization.ui("That's %d years", wakingYears))
                    .font(.system(size: 52, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ankyMadder)
                    .shadow(color: Color.ankyRose.opacity(0.40), radius: 14)
                Text(AnkyLocalization.ui("of your waking life."))
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
            }
            .opacity(mathBeatOneVisible ? 1 : 0)
            .offset(y: mathBeatOneVisible ? 0 : 10)

            Text(AnkyLocalization.ui("What if you used a small part of that to know yourself?"))
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
            flowImage("anky-flow-this-is-anky", maxWidth: 500, height: 472)

            Text(AnkyLocalization.ui("I am Anky."))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)

            dawnBody("I'm not here to change you. I'm not here to give you advice. I'm just here to witness you being who you are.")

            dawnCTA("Hi, Anky.") { advance() }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Screen 7 · The name

    private var nameScreen: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissNameKeyboard()
                }

            VStack(spacing: 18) {
                // Anky listens for the name — and steps aside when the
                // keyboard needs the room.
                if keyboardHeight == 0 {
                    flowImage("anky-flow-name-badge", maxWidth: 316, height: 316)
                        .scaleEffect(nameImageScale)
                        .transition(.opacity)
                        .gesture(nameImageMagnification)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                nameImageScale = 1
                            }
                        }
                        .onTapGesture {
                            dismissNameKeyboard()
                        }
                }

                Text(AnkyLocalization.ui("What should I call you?"))
                    .font(.ankyTitle)
                    .foregroundStyle(Color.ankyInk)
                    .multilineTextAlignment(.center)
                    .onTapGesture {
                        dismissNameKeyboard()
                    }

                VeilCard {
                    TextField(
                        text: $writerName,
                        prompt: Text(AnkyLocalization.ui("Your name"))
                            .foregroundColor(Color.ankyInkSoft.opacity(0.72))
                    ) {
                        EmptyView()
                    }
                        .focused($isNameFieldFocused)
                        .font(.ankyProse)
                        .foregroundStyle(Color.ankyInk)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { saveNameAndAdvance() }
                }

                Text(AnkyLocalization.ui("Anky doesn't send your name to its backend. It stays in app data and may be included in your Apple device backup. Anky's code is open source."))
                    .font(.ankyCaption)
                    .foregroundStyle(Color.ankyInkSoft)
                    .multilineTextAlignment(.center)
                    .onTapGesture {
                        dismissNameKeyboard()
                    }

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
                        .frame(minWidth: 88)
                        .frame(height: Self.ctaFooterHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dismissNameKeyboard() {
        guard screen == 7 else {
            return
        }
        isNameFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var nameImageMagnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                nameImageScale = min(2.6, max(1, value))
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    nameImageScale = min(2.6, max(1, value))
                }
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
            flowImage("anky-flow-daily-target", maxWidth: 330, height: 126)

            Text(AnkyLocalization.ui("Choose a daily writing target."))
                .font(.ankyTitle)
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            VeilCard {
                VStack(spacing: 14) {
                    Text(AnkyLocalization.ui("minute count format", Int(targetMinutes)))
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

            dawnCTA(AnkyLocalization.ui("Commit to %d minutes a day.", Int(targetMinutes))) {
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

            Text(AnkyLocalization.ui("(You can change this later)"))
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.58))
                .multilineTextAlignment(.center)
                .frame(height: Self.ctaFooterHeight)
        }
    }

    // MARK: - Screen 9 · The paintings

    /// The reward, shown before the ask: the first painting fully revealed
    /// (bundled, so it renders offline) above the locked underdrawings of
    /// what's waiting — the same tiles the gallery shows after Day 1.
    private var paintingsScreen: some View {
        VStack(spacing: 18) {
            Text(AnkyLocalization.ui("As you write, I paint."))
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

            dawnBody("Every minute reveals another stroke of the canvas — and when a painting completes, the next is already waiting.")

            Text(AnkyLocalization.ui("Day 1 begins today."))
                .font(.ankyCaption)
                .foregroundStyle(Color.ankyInkSoft)

            dawnCTA("Begin.") { advance() }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Screen 10 · The paywall (post-dawn, same room as the map)

    /// The ask, placed after the paintings promise (the reward made
    /// visible) and before the Day 1 threshold. Purchase and restore are
    /// primary, with an explicit free-writing continuation in PaywallView.
    private var paywallScreen: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                PaywallView(store: entitlements, context: .onboarding) {
                    advance(haptic: false)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
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
            flowImage("anky-flow-apps-knock", maxWidth: 356, height: 404)

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

    /// The finger drags the screen itself: the current page follows the
    /// touch, the neighbor slides in beside it, and the release settles or
    /// snaps back with the gesture's own momentum. On the target screen the
    /// slider owns the surface, so only a left-edge back-swipe tracks.
    private var onboardingSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                guard !isSettlingSwipe else {
                    return
                }
                if screen == Self.targetScreenIndex, value.startLocation.x >= 44 {
                    return
                }
                if swipeLockedHorizontal == nil {
                    swipeLockedHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.2
                }
                guard swipeLockedHorizontal == true else {
                    return
                }
                let horizontal = value.translation.width
                let target: Int?
                if horizontal < 0 {
                    target = screen == Self.targetScreenIndex ? nil : nextSwipeScreen
                } else {
                    target = previousSwipeScreen
                }
                swipeTargetScreen = target
                // Nothing to reveal in this direction: rubber-band instead.
                swipeTranslation = target == nil ? horizontal / 4 : horizontal
            }
            .onEnded { value in
                let wasHorizontal = swipeLockedHorizontal == true
                swipeLockedHorizontal = nil
                guard wasHorizontal, !isSettlingSwipe else {
                    return
                }
                let horizontal = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let flick = abs(predicted) > pageWidth * 0.55 && predicted * horizontal > 0
                guard let target = swipeTargetScreen,
                      abs(horizontal) > pageWidth * 0.30 || flick else {
                    cancelSwipe()
                    return
                }
                settleSwipe(to: target)
            }
    }

    private var nextSwipeScreen: Int? {
        guard screen != Self.paywallScreenIndex else {
            return nil
        }
        var next = screen + 1
        if next == Self.paywallScreenIndex && entitlements.isEntitledForGating {
            next += 1
        }
        return next <= Self.screenCount ? next : nil
    }

    private var previousSwipeScreen: Int? {
        var previous = screen - 1
        if previous == Self.paywallScreenIndex && entitlements.isEntitledForGating {
            previous -= 1
        }
        return previous >= 1 ? previous : nil
    }

    private func cancelSwipe() {
        withAnimation(.easeOut(duration: 0.24)) {
            swipeTranslation = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            if !isSettlingSwipe, swipeTranslation == 0 {
                swipeTargetScreen = nil
            }
        }
    }

    private func settleSwipe(to target: Int) {
        isSettlingSwipe = true
        AnkyHaptics.light()
        withAnimation(.easeOut(duration: 0.22)) {
            swipeTranslation = target > screen ? -pageWidth : pageWidth
        }
        // The slide already moved the pages; the screen swap itself must
        // not replay as a crossfade.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                screen = target
                swipeTranslation = 0
                swipeTargetScreen = nil
            }
            isSettlingSwipe = false
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
        onboardingCTA(title, action: action)
    }

    /// The dawn screens once wore the solid-gold ThreadButtonStyle; the primary
    /// action now keeps the first screens' pale parchment-and-gold thread the
    /// whole way through, so the button never "evolves" mid-onboarding.
    private func dawnCTA(_ title: String, action: @escaping () -> Void) -> some View {
        onboardingCTA(title, action: action)
    }

    private func onboardingCTA(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            Text(AnkyLocalization.ui(title))
        }
        .buttonStyle(PaperThreadButtonStyle())
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
