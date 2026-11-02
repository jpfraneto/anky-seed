//
//  LoomGateView.swift
//  Anky
//
//  The way into Anky, and the only door. One line at a time, with quiet
//  progress dots at the bottom:
//
//      why: three lines on what Anky is for
//      day above, night below                (tap the half you write in)
//      choose your font.                     (a grid, no scrolling)
//      how large?                            (− and +, with a live line)
//      when you make a typo:                 (erase, or keep going)
//      anky works when it's daily.           (an optional daily reminder)
//      Anky Pro                              (3 days free, then monthly)
//
//  Nothing is asked for: no name, no goals, no account. Without an active
//  trial or subscription the app stays here; the writer's past writings can
//  always be taken with them.
//

import StoreKit
import SwiftUI
import UIKit

/// Whether the welcome still owes its one showing. In the Keychain, so a
/// reinstall goes straight to the door instead of replaying the welcome.
enum LoomLedger {
    private static let account = "loom.welcome.done.v1"

    static func needsWelcome() -> Bool {
        #if DEBUG
        // Replay the welcome without wiping anything: `-loomReplay`.
        if ProcessInfo.processInfo.arguments.contains("-loomReplay") { return true }
        if ScreenshotMode.isActive { return false }
        #endif
        return ((try? KeychainClient().data(for: account)) ?? nil) == nil
    }

    static func markDone() {
        try? KeychainClient().save(Data([1]), account: account)
    }

    static func reset() {
        try? KeychainClient().delete(account: account)
    }
}

/// The welcome's colors: it stands on the writer's own paper or night.
enum LoomPalette {
    static let ground = Color.ankyPaper
    static let groundDeep = Color.ankyPaperDeep
    /// The welcome's voice: umber on paper, gold on night.
    static let thread = Color.ankyPigment(light: (0.310, 0.243, 0.180), night: (0.953, 0.757, 0.431))
    static let threadSoft = thread.opacity(0.62)
    static let threadFaint = thread.opacity(0.38)
}

struct LoomGateView: View {
    @ObservedObject var pro: AnkyPro
    /// Called once the welcome has been seen (the ledger is stamped here).
    let onWelcomed: () -> Void
    /// The writer is in: the gate fades and the page takes the keyboard.
    let onEnter: () -> Void

    /// Every step of the welcome, in order. The dots count these.
    private enum Step: Int, CaseIterable {
        case why1, why2, why3
        case appearance, typeface, size, erase
        case practice
    }

    private enum Phase: Equatable {
        case welcome(Step)
        case door
        case entering
    }

    @State private var phase: Phase
    @State private var sound = LoomSound()

    @AppStorage(AnkyAppearance.storageKey) private var appearance: AnkyAppearance = .paper
    @State private var preferences = WritingPreferencesStore().load()
    @State private var advancing = false
    /// The welcome ran this launch, so the door can step back into it.
    @State private var cameThroughWelcome = false
    /// The half of the day/night split the writer tapped.
    @State private var splitChoice: AnkyAppearance?
    /// Lines arrive a breath after their screen does.
    @State private var lineShown = false

    // The practice
    @State private var reminderTime = Date()

    // Door
    @State private var doorMessage: String?
    @State private var showsTerms = false
    @State private var showsPrivacy = false
    @State private var exportURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(pro: AnkyPro, needsWelcome: Bool, onWelcomed: @escaping () -> Void, onEnter: @escaping () -> Void) {
        self.pro = pro
        self.onWelcomed = onWelcomed
        self.onEnter = onEnter
        _phase = State(initialValue: needsWelcome ? .welcome(.why1) : .door)
        #if DEBUG
        // Open the welcome at one step for QA: `-loomReplay -welcomeStep 4`.
        if needsWelcome, let step = Step(rawValue: UserDefaults.standard.integer(forKey: "welcomeStep")),
           UserDefaults.standard.object(forKey: "welcomeStep") != nil {
            _phase = State(initialValue: .welcome(step))
        }
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LoomPalette.ground.ignoresSafeArea()

                switch phase {
                case .welcome(let step):
                    welcomeStep(step)
                        // The bar below never covers a step's content; the
                        // day/night split runs underneath it on purpose.
                        .padding(.bottom, step == .appearance ? 0 : Self.bottomBarHeight)
                        .id(step)
                        .transition(.opacity)
                case .door:
                    door(in: geometry.size)
                        .transition(.opacity)
                case .entering:
                    Color.clear
                }

                // The same chrome on every step: back at the top left, and
                // the way on in one fixed place at the bottom, over the dots.
                if case .welcome(let step) = phase {
                    VStack(spacing: 0) {
                        HStack {
                            if step != .why1 {
                                backButton(tint: step == .appearance ? Self.dayInk : LoomPalette.thread)
                            }
                            Spacer()
                        }
                        Spacer()
                        bottomBar(step)
                    }
                } else if phase == .door, cameThroughWelcome {
                    VStack {
                        HStack {
                            backButton(tint: LoomPalette.thread)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: phase)
        .onAppear(perform: appear)
        .onDisappear {
            sound.stop(over: 0.3)
        }
        .onChange(of: phase) { newPhase in
            if case .welcome(let step) = newPhase { arrive(at: step) }
        }
        .onChange(of: pro.access) { access in
            // A restore, a renewal arriving, or the first StoreKit answer.
            guard access == .active, phase == .door else { return }
            enter(celebrating: doorMessage != nil || pro.isWorking)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active { Task { await pro.refresh() } }
        }
        .sheet(isPresented: $showsTerms) {
            TermsAndConditionsReflectionSheet()
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
        .sheet(isPresented: $showsPrivacy) {
            PrivacyPolicyReflectionSheet()
                .presentationDragIndicator(.visible)
                .ankySheetBackground(PrivacySheetPalette.ink)
        }
    }

    private func appear() {
        if case .welcome(let step) = phase {
            sound.start()
            arrive(at: step)
        } else if phase == .door, pro.access == .active {
            enter(celebrating: false)
        }
    }

    private func arrive(at step: Step) {
        cameThroughWelcome = true
        if step == .appearance, splitChoice == nil {
            splitChoice = appearance
        }
        lineShown = reduceMotion
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.9)) { lineShown = true }
            }
        }
        if step == .practice {
            reminderTime = Date()
        }
    }

    private func next() {
        guard case .welcome(let step) = phase else { return }
        if let following = Step(rawValue: step.rawValue + 1) {
            phase = .welcome(following)
        } else {
            leaveWelcome()
        }
    }

    private func back() {
        AnkyHaptics.light()
        switch phase {
        case .welcome(let step):
            if let previous = Step(rawValue: step.rawValue - 1) {
                phase = .welcome(previous)
            }
        case .door:
            phase = .welcome(.practice)
        case .entering:
            break
        }
    }

    // MARK: - The chrome

    /// Secondary line + button + dots, always the same height.
    private static let bottomBarHeight: CGFloat = 150

    private func backButton(tint: Color) -> some View {
        Button(action: back) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.top, 4)
        .accessibilityLabel(Text(welcomeText("Back")))
    }

    private func bottomBar(_ step: Step) -> some View {
        let onNight = step == .appearance
        let tint = onNight ? Self.nightInk : LoomPalette.thread
        return VStack(spacing: 14) {
            // The secondary line: always there, so the button never moves.
            Group {
                switch step {
                case .why3:
                    Text(welcomeText("what you write never leaves this iPhone."))
                        .font(.fraunces(15, weight: .light, italic: true))
                        .foregroundStyle(LoomPalette.threadSoft)
                case .practice:
                    Button(action: advance) {
                        Text(welcomeText("welcome: not now"))
                            .font(.fraunces(16, weight: .light))
                            .foregroundStyle(LoomPalette.threadSoft)
                            .padding(.horizontal, 24)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                default:
                    Color.clear
                }
            }
            .frame(height: 36)
            .multilineTextAlignment(.center)

            if step == .practice {
                ThreadButton(
                    title: welcomeText("remind me at %@", reminderTime.formatted(date: .omitted, time: .shortened)),
                    filled: true
                ) {
                    AnkyHaptics.light()
                    Task { await scheduleReminder() }
                }
            } else {
                ThreadButton(title: welcomeText("continue"), tint: tint) { advance() }
            }

            ProgressDots(count: Step.allCases.count, current: step.rawValue, onNight: onNight)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 10)
    }

    // MARK: - 1. The welcome, one step at a time

    @ViewBuilder
    private func welcomeStep(_ step: Step) -> some View {
        switch step {
        case .why1:
            whyLine("your phone fills your day with other people's words.")
        case .why2:
            whyLine("anky gives you eight minutes for your own.")
        case .why3:
            whyLine("write without stopping. what comes out is what you were carrying.")
        case .appearance:
            dayAndNight
        case .typeface:
            settingScreen("choose your font.") { fontGrid }
        case .size:
            settingScreen("how large?") { sizeControl }
        case .erase:
            settingScreen("when you make a typo:") { eraseChoice }
        case .practice:
            practice
        }
    }

    /// One line, centered, and a way on. A tap anywhere also moves on.
    private func whyLine(_ key: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text(welcomeText(key))
                .font(.fraunces(29, weight: .light, relativeTo: .title))
                .foregroundStyle(LoomPalette.thread)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .opacity(lineShown ? 1 : 0)
            Spacer()
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    private func settingScreen<Control: View>(_ key: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 36) {
            Spacer()
            Text(welcomeText(key))
                .font(.fraunces(27, weight: .light, relativeTo: .title))
                .foregroundStyle(LoomPalette.thread)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            control()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    // MARK: Day and night

    /// Day above, night below, like yin and yang: each half is a page with
    /// the same line written on it. Tap one to choose it.
    private var dayAndNight: some View {
        VStack(spacing: 0) {
            half(.paper)
            half(.night)
        }
        .ignoresSafeArea()
    }

    private func half(_ choice: AnkyAppearance) -> some View {
        let isDay = choice == .paper
        let ground = isDay ? Self.dayGround : Self.nightGround
        let ink = isDay ? Self.dayInk : Self.nightInk
        let isChosen = splitChoice == choice
        return Button {
            choose {
                splitChoice = choice
                appearance = choice
            }
        } label: {
            ZStack {
                ground
                VStack(spacing: 18) {
                    Text(welcomeText("choose the color."))
                        .font(preferences.fontChoice.font(size: 30))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                    Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(ink.opacity(isChosen ? 0.9 : 0.35))
                }
                .padding(.horizontal, 32)
                // The night half's line sits above the bar that overlays it.
                .padding(.bottom, isDay ? 0 : Self.bottomBarHeight * 0.6)
                .opacity(isChosen ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(welcomeText(isDay ? "Day" : "Night")))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    fileprivate static let dayGround = Color(.displayP3, red: 0.965, green: 0.937, blue: 0.894)
    fileprivate static let nightGround = Color(.displayP3, red: 0.082, green: 0.075, blue: 0.114)
    fileprivate static let dayInk = Color(.displayP3, red: 0.310, green: 0.243, blue: 0.180)
    fileprivate static let nightInk = Color(.displayP3, red: 0.925, green: 0.855, blue: 0.757)

    // MARK: Font, size, typos

    /// Every font at once, each name in its own face: two columns, no scroll.
    private var fontGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(AnkyWritingFontChoice.allCases, id: \.self) { choice in
                choiceChip(isSelected: preferences.fontChoice == choice, height: 52) {
                    Text(welcomeText(choice.displayName))
                        .font(choice.font(size: 19))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } choose: {
                    preferences.fontChoice = choice
                }
            }
        }
    }

    /// A line in the chosen font, and − / + to make it smaller or larger.
    private var sizeControl: some View {
        let sizes = AnkyWritingTextSize.allCases
        let index = sizes.firstIndex(of: preferences.textSize) ?? 1
        return VStack(spacing: 36) {
            Text(welcomeText("this is how your words will look."))
                .font(preferences.fontChoice.font(size: preferences.textSize.pointSize))
                .foregroundStyle(LoomPalette.thread)
                .multilineTextAlignment(.center)
                .lineSpacing(preferences.textSize.pointSize * 0.42)
                .frame(minHeight: 120)
                .animation(.easeInOut(duration: 0.2), value: preferences.textSize)

            HStack(spacing: 28) {
                stepButton("minus", label: "Smaller", enabled: index > 0) {
                    preferences.textSize = sizes[index - 1]
                }
                stepButton("plus", label: "Larger", enabled: index < sizes.count - 1) {
                    preferences.textSize = sizes[index + 1]
                }
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AnkyHaptics.selection()
            sound.pluck()
            action()
            WritingPreferencesStore().save(preferences)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(LoomPalette.thread)
                .frame(width: 64, height: 64)
                .overlay(Circle().stroke(LoomPalette.thread.opacity(0.35), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(Text(welcomeText(label)))
    }

    private var eraseChoice: some View {
        VStack(spacing: 10) {
            choiceChip(isSelected: preferences.backspaceAllowed, height: 58) {
                Text(welcomeText("let me erase it")).font(.fraunces(19, weight: .light))
            } choose: {
                preferences.backspaceAllowed = true
            }
            choiceChip(isSelected: !preferences.backspaceAllowed, height: 58) {
                Text(welcomeText("leave it, keep going")).font(.fraunces(19, weight: .light))
            } choose: {
                preferences.backspaceAllowed = false
            }
        }
        .frame(maxWidth: 300)
    }

    private func choiceChip<Label: View>(
        isSelected: Bool,
        height: CGFloat,
        @ViewBuilder label: () -> Label,
        choose apply: @escaping () -> Void
    ) -> some View {
        Button {
            choose(apply)
        } label: {
            label()
                .foregroundStyle(isSelected ? LoomPalette.thread : LoomPalette.threadSoft)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LoomPalette.thread.opacity(isSelected ? 0.10 : 0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LoomPalette.thread.opacity(isSelected ? 0.55 : 0.14), lineWidth: 0.75)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A tap chooses and, a beat later, moves on. The button at the bottom
    /// moves on too, for a writer who came back and keeps their answer.
    /// Everything stays changeable in Settings.
    private func choose(_ apply: @escaping () -> Void) {
        guard !advancing else { return }
        advancing = true
        AnkyHaptics.selection()
        sound.pluck()
        withAnimation(.easeInOut(duration: 0.3)) { apply() }
        WritingPreferencesStore().save(preferences)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            advancing = false
            next()
        }
    }

    private func advance() {
        guard !advancing else { return }
        AnkyHaptics.light()
        next()
    }

    // MARK: - 2. The practice

    private var practice: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(welcomeText("anky works when it's daily."))
                .font(.fraunces(29, weight: .light, relativeTo: .title))
                .foregroundStyle(LoomPalette.thread)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(lineShown ? 1 : 0)
            Text(welcomeText("same time tomorrow? one quiet reminder a day."))
                .font(.fraunces(18, weight: .light, italic: true))
                .foregroundStyle(LoomPalette.threadSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .opacity(lineShown ? 1 : 0)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func scheduleReminder() async {
        let scheduler = LocalNotificationScheduler()
        if await scheduler.requestAuthorization() {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            try? await scheduler.scheduleDailyReminder(hour: parts.hour ?? 20, minute: parts.minute ?? 0)
        }
        next()
    }

    private func leaveWelcome() {
        onWelcomed()
        var subscribed = pro.access == .active
        #if DEBUG
        // A replayed welcome always ends at the door, so it can be reviewed
        // on a phone that is already subscribed.
        if ProcessInfo.processInfo.arguments.contains("-loomReplay") { subscribed = false }
        #endif
        if subscribed {
            enter(celebrating: false)
        } else {
            sound.settle()
            phase = .door
        }
    }

    // MARK: - 4. The door

    @ViewBuilder
    private func door(in size: CGSize) -> some View {
        if pro.access == .checking {
            // StoreKit has not answered yet; the night waits without a word.
            Color.clear
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Text(welcomeText("eight minutes a day, for yourself."))
                        .font(.fraunces(27, weight: .light, relativeTo: .title))
                        .foregroundStyle(LoomPalette.thread)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                        .padding(.top, max(48, size.height * 0.18))

                    Text("ANKY PRO")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(2.4)
                        .foregroundStyle(LoomPalette.threadSoft)
                        .padding(.top, 48)

                    Text(offerLine)
                        .font(.fraunces(19, weight: .regular))
                        .foregroundStyle(LoomPalette.thread)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)

                    ThreadButton(
                        title: pro.isEligibleForTrial
                            ? welcomeText("start my %d free days", pro.trialDays)
                            : welcomeText("subscribe"),
                        filled: true,
                        isWorking: pro.isWorking
                    ) {
                        AnkyHaptics.light()
                        Task { await purchase() }
                    }
                    .padding(.top, 16)

                    if let doorMessage {
                        Text(doorMessage)
                            .font(.fraunces(15, weight: .light, italic: true))
                            .foregroundStyle(LoomPalette.thread)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                            .padding(.horizontal, 32)
                            .transition(.opacity)
                    }

                    footer
                        .padding(.top, 28)

                    Text(welcomeText("Anky Pro renews automatically at %@ per month unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple ID. Manage or cancel in your App Store account settings.", pro.priceText))
                        .font(.system(size: 11))
                        .foregroundStyle(LoomPalette.threadFaint)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .task { await prepareExport() }
            .task { if pro.product == nil { await pro.loadProduct() } }
        }
    }

    private var offerLine: String {
        pro.isEligibleForTrial
            ? welcomeText("%d days free, then %@ a month", pro.trialDays, pro.priceText)
            : welcomeText("%@ a month", pro.priceText)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                footerLink(welcomeText("Restore")) {
                    Task {
                        if case .failed(let text) = await pro.restore() {
                            withAnimation { doorMessage = text }
                        }
                    }
                }
                footerLink(welcomeText("Terms")) { showsTerms = true }
                footerLink(welcomeText("Privacy")) { showsPrivacy = true }
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Text(welcomeText("take your writings with you"))
                        .font(.fraunces(14, weight: .light, italic: true))
                        .foregroundStyle(LoomPalette.threadSoft)
                        .underline(color: LoomPalette.threadFaint)
                }
            }
        }
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.fraunces(14, weight: .light))
                .foregroundStyle(LoomPalette.threadSoft)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func purchase() async {
        doorMessage = nil
        switch await pro.purchase() {
        case .activated:
            AnkyHaptics.success()
            enter(celebrating: true)
        case .pending:
            withAnimation {
                doorMessage = welcomeText("Waiting for the purchase to be approved. Anky opens the moment it is.")
            }
        case .failed(let text):
            withAnimation { doorMessage = text }
        case .cancelled:
            break
        }
    }

    /// Anyone who wrote here before keeps their writings, in every state:
    /// one plain text file, ready to go anywhere.
    private func prepareExport() async {
        guard exportURL == nil else { return }
        exportURL = await Task.detached(priority: .utility) { () -> URL? in
            let writings = LocalAnkyArchive().list().sorted { $0.createdAt < $1.createdAt }
            guard !writings.isEmpty else { return nil }
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            let body = writings.map { writing in
                "\(formatter.string(from: writing.createdAt))\n\n\(writing.reconstructedText)"
            }.joined(separator: "\n\n———\n\n")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("anky-writings.txt")
            do {
                try body.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - 5. In

    private func enter(celebrating: Bool) {
        guard phase != .entering else { return }
        sound.stop()
        guard celebrating else {
            onEnter()
            return
        }
        phase = .entering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onEnter() }
    }

}

/// The welcome's button: outlined while inviting, filled when it is
/// the one thing to do.
private struct ThreadButton: View {
    let title: String
    var filled = false
    var isWorking = false
    var tint: Color = LoomPalette.thread
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.fraunces(19, weight: filled ? .regular : .light))
                    .opacity(isWorking ? 0 : 1)
                if isWorking {
                    ProgressView()
                        .tint(filled ? LoomPalette.groundDeep : tint)
                }
            }
            .foregroundStyle(filled ? LoomPalette.groundDeep : tint)
            .frame(minWidth: 220, minHeight: 54)
            .padding(.horizontal, 24)
            .background {
                if filled {
                    Capsule().fill(tint)
                        .shadow(color: tint.opacity(0.35), radius: 18)
                } else {
                    Capsule().stroke(tint.opacity(0.38), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}


/// Quiet progress: one dot per step, the current one a little longer.
private struct ProgressDots: View {
    let count: Int
    let current: Int
    /// The dots sit on the night half of the day/night split.
    var onNight = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(index == current ? 0.75 : index < current ? 0.4 : 0.18))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("\(current + 1) / \(count)"))
    }

    private var color: Color {
        onNight ? Color(.displayP3, red: 0.925, green: 0.855, blue: 0.757) : LoomPalette.thread
    }
}

/// The welcome's words, in sentence case whatever the strings file holds:
/// the first letter of the line is a capital, the rest is left alone.
private func welcomeText(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AnkyLocalization.ui(key)
    let text = arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
    // Skip opening punctuation (¿, «), but a line that opens with a number
    // ("3 days free…") stays as it is.
    guard let first = text.firstIndex(where: { $0.isLetter || $0.isNumber }),
          text[first].isLetter else { return text }
    return text.replacingCharacters(in: first...first, with: String(text[first]).uppercased())
}
