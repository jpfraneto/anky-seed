//
//  LoomGateView.swift
//  Anky
//
//  The way into Anky, and the only door. The writer is here to write, not
//  to read, so the welcome is a line at a time, each one a setting:
//
//      paper or night?                       (the page appears as chosen)
//      choose your font.                     (the typeface)
//      how large?                            (the text size)
//      erase, or only forward?               (backspace)
//      the loom, the keyboard up             (every character lays stitches)
//      what you write never leaves this iPhone.
//      Anky Pro                              (3 days free, then monthly)
//
//  Nothing is asked for: no name, no goals, no permissions. Without an
//  active trial or subscription the app stays here; the writer's past
//  writings can always be taken with them.
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

struct LoomGateView: View {
    @ObservedObject var pro: AnkyPro
    /// Called once the welcome has been seen (the ledger is stamped here).
    let onWelcomed: () -> Void
    /// The writer is in: the gate fades and the page takes the keyboard.
    let onEnter: () -> Void

    private enum Phase: Equatable {
        case setting(Int)
        case weaving
        case cloth
        case door
        case entering
    }

    @State private var phase: Phase
    @State private var sound = LoomSound()

    @State private var warpStrung: Double = 0

    // Setting up the page
    private enum Setting: Int, CaseIterable {
        case appearance, typeface, size, erase
    }
    @AppStorage(AnkyAppearance.storageKey) private var appearance: AnkyAppearance = .paper
    @State private var preferences = WritingPreferencesStore().load()
    @State private var advancing = false

    // Weaving
    @State private var text = ""
    @State private var charactersWoven = 0
    @State private var lastKeystroke: Date?
    @State private var silence: Double = 0
    @FocusState private var writing: Bool
    @State private var stillnessWatch: Task<Void, Never>?

    // Cloth
    @State private var clothStep = 0

    // Door
    @State private var doorMessage: String?
    @State private var showsTerms = false
    @State private var showsPrivacy = false
    @State private var exportURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// A full carpet in about forty seconds of steady thumbs.
    private static let charactersForFullCarpet = 170
    private static let stillnessLimit: TimeInterval = 8

    init(pro: AnkyPro, needsWelcome: Bool, onWelcomed: @escaping () -> Void, onEnter: @escaping () -> Void) {
        self.pro = pro
        self.onWelcomed = onWelcomed
        self.onEnter = onEnter
        _phase = State(initialValue: needsWelcome ? .setting(0) : .door)
        _warpStrung = State(initialValue: needsWelcome ? 0 : 1)
        // A returning writer meets the finished cloth.
        _charactersWoven = State(initialValue: needsWelcome ? 0 : Self.charactersForFullCarpet)
    }

    private var woven: Double {
        let perCharacter = Double(LoomPattern.stitchCount) / Double(Self.charactersForFullCarpet)
        return min(Double(LoomPattern.stitchCount), Double(charactersWoven) * perCharacter)
    }

    private var carpetIsComplete: Bool {
        charactersWoven >= Self.charactersForFullCarpet
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                night

                switch phase {
                case .setting(let index):
                    settingStep(Setting(rawValue: index) ?? .appearance)
                        .id(index)
                        .transition(.opacity)
                case .weaving:
                    weaving(in: geometry.size)
                        .transition(.opacity)
                case .cloth:
                    cloth(in: geometry.size)
                        .transition(.opacity)
                case .door:
                    door(in: geometry.size)
                        .transition(.opacity)
                case .entering:
                    entering
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.9), value: phase)
        .onAppear(perform: appear)
        .onDisappear {
            stillnessWatch?.cancel()
            sound.stop(over: 0.3)
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

    private var night: some View {
        ZStack {
            LoomPalette.groundDeep
            RadialGradient(
                colors: [LoomPalette.ground.opacity(1), LoomPalette.groundDeep.opacity(0)],
                center: .center, startRadius: 10, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private func appear() {
        if case .setting = phase {
            sound.start()
        } else if phase == .door, pro.access == .active {
            enter(celebrating: false)
        }
    }

    // MARK: - 1. The page, set up one line at a time

    private func settingStep(_ setting: Setting) -> some View {
        VStack(spacing: 40) {
            Spacer()
            Text(AnkyLocalization.ui(line(for: setting)))
                .font(.fraunces(27, weight: .light, relativeTo: .title))
                .foregroundStyle(LoomPalette.thread)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            control(for: setting)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func line(for setting: Setting) -> String {
        switch setting {
        case .appearance: return "paper or night?"
        case .typeface: return "choose your font."
        case .size: return "how large?"
        case .erase: return "erase, or only forward?"
        }
    }

    @ViewBuilder
    private func control(for setting: Setting) -> some View {
        switch setting {
        case .appearance:
            HStack(spacing: 16) {
                ForEach(AnkyAppearance.allCases, id: \.self) { choice in
                    appearanceSwatch(choice)
                }
            }
        case .typeface:
            VStack(spacing: 10) {
                ForEach(AnkyWritingFontChoice.allCases, id: \.self) { choice in
                    choiceChip(isSelected: preferences.fontChoice == choice, height: 54) {
                        Text(AnkyLocalization.ui(choice.displayName)).font(choice.font(size: 21))
                    } choose: {
                        preferences.fontChoice = choice
                    }
                }
            }
            .frame(maxWidth: 280)
        case .size:
            HStack(spacing: 8) {
                ForEach(AnkyWritingTextSize.allCases, id: \.self) { size in
                    choiceChip(isSelected: preferences.textSize == size, height: 72) {
                        Text("Aa").font(preferences.fontChoice.font(size: size.pointSize))
                    } choose: {
                        preferences.textSize = size
                    }
                    .accessibilityLabel(Text(AnkyLocalization.ui(size.displayName)))
                }
            }
        case .erase:
            VStack(spacing: 10) {
                choiceChip(isSelected: !preferences.backspaceAllowed, height: 54) {
                    Text(AnkyLocalization.ui("only forward")).font(.fraunces(18, weight: .light))
                } choose: {
                    preferences.backspaceAllowed = false
                }
                choiceChip(isSelected: preferences.backspaceAllowed, height: 54) {
                    Text(AnkyLocalization.ui("erase")).font(.fraunces(18, weight: .light))
                } choose: {
                    preferences.backspaceAllowed = true
                }
            }
            .frame(maxWidth: 280)
        }
    }

    /// A small page in each appearance; tapping one turns the whole app to it.
    private func appearanceSwatch(_ choice: AnkyAppearance) -> some View {
        let isSelected = appearance == choice
        let paper = choice == .paper
        let ground = paper
            ? Color(.displayP3, red: 0.965, green: 0.937, blue: 0.894)
            : Color(.displayP3, red: 0.082, green: 0.075, blue: 0.114)
        let ink = paper
            ? Color(.displayP3, red: 0.310, green: 0.243, blue: 0.180)
            : Color(.displayP3, red: 0.925, green: 0.855, blue: 0.757)
        return Button {
            choose { appearance = choice }
        } label: {
            VStack(spacing: 10) {
                Text("Aa")
                    .font(preferences.fontChoice.font(size: 30))
                    .foregroundStyle(ink)
                    .frame(width: 120, height: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? LoomPalette.thread : LoomPalette.threadFaint.opacity(0.5),
                                    lineWidth: isSelected ? 1.5 : 0.75)
                    )
                Text(AnkyLocalization.ui(paper ? "paper" : "night"))
                    .font(.fraunces(16, weight: .light))
                    .foregroundStyle(isSelected ? LoomPalette.thread : LoomPalette.threadSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    /// One tap sets it and moves on; everything stays changeable in Settings.
    private func choose(_ apply: @escaping () -> Void) {
        guard !advancing, case .setting(let index) = phase else { return }
        advancing = true
        AnkyHaptics.selection()
        sound.pluck()
        withAnimation(.easeInOut(duration: 0.5)) { apply() }
        WritingPreferencesStore().save(preferences)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            advancing = false
            if index + 1 < Setting.allCases.count {
                phase = .setting(index + 1)
            } else {
                beginWeaving()
            }
        }
    }

    // MARK: - 2. The first thread

    private func weaving(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    finishWeaving()
                } label: {
                    Text(AnkyLocalization.ui("loom: skip"))
                        .font(.fraunces(15, weight: .light))
                        .foregroundStyle(LoomPalette.threadFaint)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            LoomCarpetView(woven: woven, weaving: true, warpStrung: warpStrung)
                .animation(.easeOut(duration: 0.35), value: woven)
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .layoutPriority(1)

            // The silence, made visible: the thread thins as stillness
            // gathers, and the next character restores it.
            Capsule()
                .fill(LoomPalette.thread)
                .frame(height: 1.5)
                .scaleEffect(x: max(0, 1 - silence), anchor: .center)
                .opacity(silence > 0.3 ? 0.9 : 0)
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .animation(.linear(duration: 0.12), value: silence)

            TextField("", text: $text, prompt: Text(AnkyLocalization.ui("loom: write")).foregroundColor(LoomPalette.threadFaint), axis: .vertical)
                .font(preferences.fontChoice.font(size: preferences.textSize.pointSize))
                .foregroundStyle(LoomPalette.thread)
                .tint(LoomPalette.thread)
                .lineLimit(1...3)
                .multilineTextAlignment(.center)
                .focused($writing)
                .autocorrectionDisabled()
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .onChange(of: text) { [previous = text] next in
                    received(previous: previous, next: next)
                }
                .accessibilityLabel(AnkyLocalization.ui("Your first thread"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func beginWeaving() {
        phase = .weaving
        // The warp strings itself while the keyboard rises.
        if reduceMotion {
            warpStrung = 1
        } else {
            withAnimation(.easeInOut(duration: 2.4)) { warpStrung = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { writing = true }
        stillnessWatch?.cancel()
        stillnessWatch = Task { @MainActor in
            while !Task.isCancelled, phase == .weaving {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let lastKeystroke else { continue }
                let still = Date().timeIntervalSince(lastKeystroke)
                silence = max(0, (still - 3) / (Self.stillnessLimit - 3))
                if still >= Self.stillnessLimit {
                    finishWeaving()
                }
            }
        }
    }

    private func received(previous: String, next: String) {
        guard phase == .weaving else { return }
        lastKeystroke = Date()
        silence = 0
        let added = next.count - previous.count
        guard added > 0 else { return }
        // A paste weaves a little, not the whole carpet.
        charactersWoven = min(Self.charactersForFullCarpet, charactersWoven + min(added, 6))
        sound.pluck()
        if carpetIsComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finishWeaving() }
        }
    }

    private func finishWeaving() {
        guard phase == .weaving else { return }
        stillnessWatch?.cancel()
        writing = false
        silence = 0
        phase = .cloth
        if reduceMotion {
            clothStep = 2
        } else {
            reveal([(1, 0.9), (2, 2.4)]) { clothStep = max(clothStep, $0) }
        }
    }

    // MARK: - 3. The cloth

    private func cloth(in size: CGSize) -> some View {
        let side = min(size.width - 56, size.height * 0.5)
        return VStack(spacing: 0) {
            Spacer(minLength: 20)

            LoomCarpetView(woven: woven)
                .frame(width: side, height: side)

            Spacer(minLength: 28)

            Text(AnkyLocalization.ui("what you write never leaves this iPhone."))
                .font(.fraunces(20, weight: .light, italic: true))
                .foregroundStyle(LoomPalette.thread)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .opacity(clothStep >= 1 ? 1 : 0)
                .animation(.easeInOut(duration: 1.1), value: clothStep)

            Spacer(minLength: 28)

            ThreadButton(title: AnkyLocalization.ui("continue")) {
                AnkyHaptics.light()
                leaveWelcome()
            }
            .opacity(clothStep >= 2 ? 1 : 0)
            .allowsHitTesting(clothStep >= 2)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity)
    }

    private func leaveWelcome() {
        onWelcomed()
        if pro.access == .active {
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
                    LoomCarpetView(woven: woven)
                        .frame(width: min(size.width * 0.52, 230), height: min(size.width * 0.52, 230))
                        .padding(.top, 28)

                    Text("ANKY PRO")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(2.4)
                        .foregroundStyle(LoomPalette.threadSoft)
                        .padding(.top, 36)

                    Text(offerLine)
                        .font(.fraunces(19, weight: .regular))
                        .foregroundStyle(LoomPalette.thread)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)

                    ThreadButton(
                        title: pro.isEligibleForTrial
                            ? AnkyLocalization.ui("start my %d free days", pro.trialDays)
                            : AnkyLocalization.ui("subscribe"),
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

                    Text(AnkyLocalization.ui("Anky Pro renews automatically at %@ per month unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple ID. Manage or cancel in your App Store account settings.", pro.priceText))
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
            ? AnkyLocalization.ui("%d days free, then %@ a month", pro.trialDays, pro.priceText)
            : AnkyLocalization.ui("%@ a month", pro.priceText)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                footerLink(AnkyLocalization.ui("Restore")) {
                    Task {
                        if case .failed(let text) = await pro.restore() {
                            withAnimation { doorMessage = text }
                        }
                    }
                }
                footerLink(AnkyLocalization.ui("Terms")) { showsTerms = true }
                footerLink(AnkyLocalization.ui("Privacy")) { showsPrivacy = true }
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Text(AnkyLocalization.ui("take your writings with you"))
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
                doorMessage = AnkyLocalization.ui("Waiting for the purchase to be approved. The loom opens the moment it is.")
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

    private var entering: some View {
        Color.clear
    }

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

    // MARK: - Pacing

    /// Each line arrives on its own breath.
    private func reveal(_ steps: [(Int, Double)], apply: @escaping (Int) -> Void) {
        for (value, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 1.1)) { apply(value) }
            }
        }
    }
}

/// A gold thread of a button: outlined while inviting, filled when it is
/// the one thing to do.
private struct ThreadButton: View {
    let title: String
    var filled = false
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.fraunces(19, weight: filled ? .regular : .light))
                    .opacity(isWorking ? 0 : 1)
                if isWorking {
                    ProgressView()
                        .tint(filled ? LoomPalette.groundDeep : LoomPalette.thread)
                }
            }
            .foregroundStyle(filled ? LoomPalette.groundDeep : LoomPalette.thread)
            .frame(minWidth: 220, minHeight: 54)
            .padding(.horizontal, 24)
            .background {
                if filled {
                    Capsule().fill(LoomPalette.thread)
                        .shadow(color: LoomPalette.thread.opacity(0.35), radius: 18)
                } else {
                    Capsule().stroke(LoomPalette.threadFaint, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}
