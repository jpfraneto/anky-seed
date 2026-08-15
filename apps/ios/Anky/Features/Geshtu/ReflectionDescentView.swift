//
//  ReflectionDescentView.swift
//  Anky — the Geshtu Redesign (spec §6).
//
//  Anky's reflection descends: 4–6 short lines settling top-to-bottom onto the
//  lazure ground, the topmost line slightly more luminous. The writer's own
//  words, returned and warmed. Once the first reflection has arrived, the same
//  surface opens into a private conversation rooted in that writing.
//
//  Latency hiding (spec §12): the reflection request fires the instant the
//  vigil press begins (the writer's first explicit outward gesture), so the
//  0.9–30 s descent wait covers most of the generation. If it is not ready on
//  arrival, the cooled gold spiral tracery lingers, pulsing very slowly — no
//  spinner, no "Anky is thinking" copy. The ear is simply still listening.
//
//  Privacy reorder (outwards pivot §4.1): nothing leaves the device at the
//  sentinel anymore. `prepare(for:)` only constructs the view model at
//  channel close; the actual POST /anky starts in `beginUpload()`, called
//  from the Anchor's press — never earlier. This makes the privacy policy's
//  "sent on explicit request" sentence true.
//

import SwiftUI

// MARK: - Coordinator

/// Owns the reflection request for the pending session. Prepared (no network)
/// at channel close; the upload fires only at the writer's outward gesture —
/// the vigil press. Discarded when the writer walks away unsent.
@MainActor
final class GeshtuReflectionCoordinator: ObservableObject {
    @Published private(set) var viewModel: RevealViewModel?
    /// Fires when a reflection for a sent vigil actually reaches the store —
    /// the only moment the free vigil may be marked spent (a vigil whose
    /// reflection never arrives keeps the credit).
    var onPersisted: (() -> Void)?

    private var task: Task<Void, Never>?
    private var currentHash: String?

    /// Stand the view model up for a just-sealed session — memory only, no
    /// network. Idempotent per hash. The writing has NOT left the device when
    /// this returns; that is the whole point (outwards pivot §4.1).
    func prepare(for session: SavedAnky) {
        if currentHash == session.hash, viewModel != nil { return }
        cancelTask()
        let vm = RevealViewModel(artifact: session)
        vm.reflectionSurface = "axis"
        // Hold the result in memory only; it reaches the store only if the
        // vigil sends (addendum A3 / verification Q4). An unsent session's
        // reflection is never attached to its entry as if it had been received.
        vm.persistsReflection = false
        vm.onReflectionPersisted = { [weak self] in self?.onPersisted?() }
        viewModel = vm
        currentHash = session.hash
    }

    /// The writer pressed the Anchor: the first explicit outward gesture.
    /// Only now do the exact writing bytes leave the device. Safe to call on
    /// every press — the view model dedupes an in-flight request, and a
    /// re-press after a failure is exactly the retry path.
    func beginUpload() {
        guard let vm = viewModel else { return }
        // Already answered, or a request is still on the wire: nothing to
        // start. (An errored request has isAskingAnky == false, so a re-press
        // after a failure is exactly the retry.)
        if vm.reflection != nil || vm.isAskingAnky { return }
        task = Task { await vm.askAnkyForSealedSession() }
    }

    /// The vigil completed: the offering was carried. Commit the held reflection
    /// to the store so the sent day owns it in the strata (addendum A3 / Q4).
    func commit() {
        viewModel?.persistPendingReflection()
    }

    /// The day settled unsent, or a new session began: drop the in-flight
    /// result without ever persisting it (unsent ≠ sent — Q4).
    func discard() {
        cancelTask()
        viewModel = nil
        currentHash = nil
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
    }
}

// MARK: - The canonical finished-session screen

enum FinishedSessionStage: Equatable {
    /// The writing has sealed and the writer has not yet chosen whether to
    /// continue it, ask Anky, or leave it on device.
    case awaitingChoice
    /// The reflection is in flight or has arrived; its conversation follows
    /// directly beneath the sealed writing.
    case conversation
    /// The exact same screen reached from the separate archive list.
    case archived
}

/// The one finished-session screen used both immediately after writing and
/// when an archived session is opened. Its first block is always the sealed
/// `.anky` reconstructed into the writing surface; everything that happened
/// with Anky continues below it as one thread. The archive list is deliberately
/// absent from this view.
struct FinishedSessionView: View {
    @ObservedObject var viewModel: RevealViewModel
    @ObservedObject var axis: GeshtuState
    let artifact: SavedAnky
    /// The global y of the keyboard's top edge during the session: the line
    /// the writing rests on and the response descends from. Archived sessions
    /// use their natural document height instead.
    var keyboardTop: CGFloat?
    let stage: FinishedSessionStage
    var onKeepWriting: () -> Void = {}
    var onRequestReflection: () -> Void = {}
    var onClose: (() -> Void)?
    var onLateOffer: (() -> Void)?
    /// A legacy or custom server can still deny reflection access: in that
    /// case the error line's tap raises the gate instead of a doomed retry.
    var onNeedsGate: () -> Void = {}

    @State private var preferences = WritingPreferencesStore().load()
    @State private var didPrepare = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let keyboardLineID = "finishedSession.keyboardLine"

    var body: some View {
        GeometryReader { outer in
            let outerFrame = outer.frame(in: .global)
            // The keyboard line in this canvas's coordinates, clamped so a
            // stale reading can never pin the writing off-screen.
            let keyboardLineY = keyboardTop.map {
                min(max(160, $0 - outerFrame.minY), max(160, outer.size.height - 96))
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text(Self.dateFormatter.string(from: artifact.createdAt).lowercased())
                            .font(.fraunces(14, weight: .light))
                            .foregroundStyle(Color.ankyInkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 22)

                        // The writing, in the writer's own writing font,
                        // bottom-anchored to the keyboard line — the same
                        // resting place WriteView held it at (its text bottom
                        // inset was keyboard overlap + 24).
                        SelectableOreText(
                            text: artifact.reconstructedText,
                            font: writingFont,
                            ink: Color.ankyUmber.opacity(0.88),
                            lineSpacing: writingLineSpacing,
                            // The fixed top chrome's share honors this choice.
                            onSelectionChange: { axis.selectedQuote = $0 }
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 80)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: keyboardLineY.map { max(1, $0 - 58) },
                            alignment: .bottomLeading
                        )

                        Color.clear.frame(height: 1).id(Self.keyboardLineID)

                        finishedSessionTail
                            .padding(.top, 23)
                            .padding(.bottom, 120)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: keyboardLineY.map { max(1, outer.size.height - $0) },
                                alignment: .top
                            )
                    }
                }
                .onAppear {
                    preferences = WritingPreferencesStore().load()
                    if let keyboardLineY {
                        // A newly sealed session keeps the last line exactly
                        // where it was when the keyboard withdrew.
                        let fraction = max(0.05, min(0.95, (keyboardLineY - 24) / max(1, outer.size.height)))
                        proxy.scrollTo(Self.keyboardLineID, anchor: UnitPoint(x: 0.5, y: fraction))
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ankyInkSoft)
                        .frame(width: 42, height: 42)
                        .background(Color.ankyPaper.opacity(0.58), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .padding(.top, 8)
                .accessibilityLabel(Text(AnkyLocalization.ui("Back to archive")))
            }
        }
        .task {
            await viewModel.prepareAfterFirstRender()
            didPrepare = true
        }
    }

    // MARK: The writing's own clothes

    private var writingFont: UIFont {
        preferences.fontChoice.uiFont(size: preferences.textSize.pointSize)
    }

    private var writingLineSpacing: CGFloat {
        preferences.textSize.pointSize * 0.42
    }

    // MARK: The rest of the session

    @ViewBuilder
    private var finishedSessionTail: some View {
        if stage == .awaitingChoice {
            sessionChoices
        } else if stage == .archived,
                  didPrepare,
                  viewModel.reflection == nil,
                  !viewModel.isAskingAnky,
                  viewModel.streamingReflectionMarkdown.isEmpty,
                  viewModel.errorMessage == nil {
            archivedWithoutReflection
        } else {
            reflectionBlock
        }
    }

    private var sessionChoices: some View {
        VStack(spacing: 12) {
            sessionAction(
                label: "keep writing",
                icon: "pencil.line",
                hint: "Reopen this session and keep going.",
                action: onKeepWriting
            )
            sessionAction(
                label: "get anky's reflection",
                icon: "sparkles",
                prominent: true,
                hint: "Send this writing to Anky and begin the conversation.",
                action: onRequestReflection
            )
            if let onClose {
                sessionAction(
                    label: "just leave",
                    icon: "arrow.down",
                    hint: "Return to the archive. Your writing stays on this device.",
                    action: onClose
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var archivedWithoutReflection: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.ankyGold.opacity(0.30))
                .frame(width: 46, height: 1.5)
            if let onLateOffer {
                sessionAction(
                    label: "get anky's reflection",
                    icon: "sparkles",
                    prominent: true,
                    hint: "Begin a conversation rooted in this writing.",
                    action: onLateOffer
                )
            } else {
                Text(AnkyLocalization.ui("This writing stayed on this device."))
                    .font(.fraunces(14, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func sessionAction(
        label: String,
        icon: String,
        prominent: Bool = false,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .light))
                Text(AnkyLocalization.ui(label))
                    .font(.fraunces(prominent ? 16 : 14, weight: .light, italic: true))
            }
            .foregroundStyle(prominent ? Color.ankyInk : Color.ankyInkSoft)
            .padding(.horizontal, prominent ? 20 : 16)
            .padding(.vertical, prominent ? 11 : 9)
            .background(
                Capsule()
                    .fill(Color.ankyPaper.opacity(prominent ? 0.88 : 0.72))
                    .overlay(Capsule().stroke(Color.ankyGold.opacity(prominent ? 0.6 : 0.35), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(AnkyLocalization.ui(hint)))
    }

    // MARK: The response

    @ViewBuilder
    private var reflectionBlock: some View {
        // The raw markdown is honored by the selectable glaze renderer (violet
        // headings, gold strong text, slate emphasis).
        let source = (viewModel.reflection?.reflection ?? viewModel.streamingReflectionMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 0) {
            // The seam between the two voices — same hairline as the strata.
            Capsule()
                .fill(Color.ankyGold.opacity(0.30))
                .frame(width: 46, height: 1.5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)

            if viewModel.reflection == nil, viewModel.errorMessage != nil {
                // The request failed: say so, in register — and say WHAT
                // failed. An entitlement denial is not a lost thread: its
                // tap raises the gate, because asking again without the
                // subscription can never succeed (finding 2026-07-24). A
                // genuinely lost request keeps the retry path. The spiral
                // must never pulse forever over a dead request.
                let entitlementDenied = viewModel.errorIsEntitlementDenied
                Button {
                    if entitlementDenied {
                        onNeedsGate()
                    } else {
                        Task { await viewModel.askAnkyForSealedSession() }
                    }
                } label: {
                    VStack(spacing: 10) {
                        Text(entitlementDenied
                            ? (viewModel.errorMessage ?? AnkyLocalization.ui("the reflection was lost on the way"))
                            : AnkyLocalization.ui("the reflection was lost on the way"))
                            .font(.fraunces(16, weight: .light, italic: true))
                            .foregroundStyle(Color.ankyInkSoft)
                        Text(AnkyLocalization.ui(entitlementDenied ? "tap to open the gate" : "tap to ask again"))
                            .font(.fraunces(13, weight: .light))
                            .foregroundStyle(Color.ankyInk.opacity(0.8))
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(AnkyLocalization.ui(entitlementDenied ? "tap to open the gate" : "tap to ask again")))
            } else if source.isEmpty {
                // Still listening: the cooled gold tracery, pulsing slowly —
                // no spinner, no "thinking" copy.
                SpiralTracery(reduceMotion: reduceMotion, listening: true)
                    .frame(width: 96, height: 96)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            } else {
                // Native selection chooses any exact range; the fixed share
                // control above follows that range.
                SelectableGlazeText(
                    text: source,
                    onSelectionChange: {
                        axis.selectedQuote = $0
                        axis.selectedQuoteIsAnky = $0 != nil
                    }
                )
                .padding(.horizontal, 30)
                .animation(.easeOut(duration: 0.6), value: source)

                if let receipt = viewModel.reflection?.inference {
                    InferenceReceiptView(receipt: receipt)
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                }

                if let reflection = viewModel.reflection,
                   !artifact.hash.isEmpty {
                    AnkyConversationView(
                        hash: artifact.hash,
                        writing: artifact.reconstructedText,
                        reflection: reflection.reflection,
                        onWillSend: { viewModel.persistPendingReflection() },
                        onSelectionChange: {
                            axis.selectedQuote = $0
                            axis.selectedQuoteIsAnky = $0 != nil
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMMM yyyy"
        return formatter
    }()

}

/// Owns the reveal model for an archive navigation destination, then renders
/// the exact same finished-session screen used at the end of a live session.
struct ArchivedFinishedSessionView: View {
    @StateObject private var viewModel: RevealViewModel
    @ObservedObject var axis: GeshtuState
    private let artifact: SavedAnky
    private let onLateOffer: (() -> Void)?

    init(
        artifact: SavedAnky,
        axis: GeshtuState,
        onLateOffer: (() -> Void)? = nil
    ) {
        self.artifact = artifact
        self.axis = axis
        self.onLateOffer = onLateOffer
        _viewModel = StateObject(wrappedValue: RevealViewModel(artifact: artifact))
    }

    var body: some View {
        FinishedSessionView(
            viewModel: viewModel,
            axis: axis,
            artifact: artifact,
            keyboardTop: nil,
            stage: .archived,
            onClose: nil,
            onLateOffer: onLateOffer
        )
    }
}

struct InferenceReceiptView: View {
    let receipt: AnkyInferenceReceipt

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: receipt.access == .free ? "leaf" : "sparkles")
            Text(receipt.disclosureLine)
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(Color.ankyInkSoft.opacity(0.72))
        .textSelection(.enabled)
        .accessibilityLabel(AnkyLocalization.ui("Inference receipt: %@", receipt.disclosureLine))
    }
}

// MARK: - Conversation after the reflection

@MainActor
final class AnkyConversationViewModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [AnkyConversationMessage]
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private let hash: String
    private let writing: String
    private let reflection: String
    private let reflectionStore: ReflectionStore
    private let identityStore = WriterIdentityStore()

    init(hash: String, writing: String, reflection: String, reflectionStore: ReflectionStore = ReflectionStore()) {
        self.hash = hash
        self.writing = writing
        self.reflection = reflection
        self.reflectionStore = reflectionStore
        self.messages = reflectionStore.load(hash: hash)?.conversation ?? []
    }

    var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send(onWillSend: () -> Void) async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        draft = ""
        errorMessage = nil
        isSending = true
        onWillSend()

        let userMessage = AnkyConversationMessage(role: .user, content: String(content.prefix(4_000)))
        messages.append(userMessage)
        persist()

        do {
            let identity = try identityStore.loadOrCreate()
            let baseURL = try MirrorConfiguration.normalizedBaseURL(from: MirrorConfiguration.currentBaseURL())
            let requestMessages = Array(messages.suffix(24))
            let reply = try await AnkyConversationClient(baseURL: baseURL).reply(
                writing: writing,
                reflection: reflection,
                messages: requestMessages,
                identity: identity,
                ageYears: WriterProfileStore().ageYears()
            )
            messages.append(AnkyConversationMessage(
                role: .assistant,
                content: reply.message,
                inference: reply.inference
            ))
            persist()
            AnkyHaptics.success()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AnkyLocalization.ui("Anky could not answer right now.")
            AnkyHaptics.warning()
        }
        isSending = false
    }

    func retryLast(onWillSend: () -> Void) async {
        guard !isSending, messages.last?.role == .user else { return }
        errorMessage = nil
        isSending = true
        onWillSend()
        do {
            let identity = try identityStore.loadOrCreate()
            let baseURL = try MirrorConfiguration.normalizedBaseURL(from: MirrorConfiguration.currentBaseURL())
            let reply = try await AnkyConversationClient(baseURL: baseURL).reply(
                writing: writing,
                reflection: reflection,
                messages: Array(messages.suffix(24)),
                identity: identity,
                ageYears: WriterProfileStore().ageYears()
            )
            messages.append(AnkyConversationMessage(
                role: .assistant,
                content: reply.message,
                inference: reply.inference
            ))
            persist()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AnkyLocalization.ui("Anky could not answer right now.")
        }
        isSending = false
    }

    private func persist() {
        try? reflectionStore.saveConversation(messages, hash: hash)
    }
}

struct AnkyConversationView: View {
    @StateObject private var model: AnkyConversationViewModel
    let onWillSend: () -> Void
    var onSelectionChange: ((String?) -> Void)?
    @FocusState private var isComposerFocused: Bool

    init(
        hash: String,
        writing: String,
        reflection: String,
        onWillSend: @escaping () -> Void = {},
        onSelectionChange: ((String?) -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: AnkyConversationViewModel(hash: hash, writing: writing, reflection: reflection))
        self.onWillSend = onWillSend
        self.onSelectionChange = onSelectionChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Capsule()
                    .fill(Color.ankyGold.opacity(0.30))
                    .frame(height: 1)
                Text(AnkyLocalization.ui("stay with anky"))
                    .font(.fraunces(13, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
                    .fixedSize()
                Capsule()
                    .fill(Color.ankyGold.opacity(0.30))
                    .frame(height: 1)
            }

            ForEach(model.messages) { message in
                conversationMessage(message)
            }

            if model.isSending {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(Color.ankyGold)
                    Text(AnkyLocalization.ui("anky is here…"))
                        .font(.fraunces(14, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft)
                }
                .padding(.leading, 4)
            }

            if let errorMessage = model.errorMessage {
                Button {
                    Task { await model.retryLast(onWillSend: onWillSend) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(errorMessage)
                        Text(AnkyLocalization.ui("tap to try once more"))
                            .opacity(0.72)
                    }
                    .font(.fraunces(13, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyUmber)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    AnkyLocalization.ui("what wants to be said back?"),
                    text: $model.draft,
                    axis: .vertical
                )
                .font(.fraunces(16, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.ankyPaper.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.7)
                }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(model.canSend ? Color.ankyPaper : Color.ankyInkSoft)
                        .frame(width: 38, height: 38)
                        .background(model.canSend ? Color.ankyViolet : Color.ankyInk.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .accessibilityLabel(AnkyLocalization.ui("Send to Anky"))
            }
        }
    }

    @ViewBuilder
    private func conversationMessage(_ message: AnkyConversationMessage) -> some View {
        switch message.role {
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                SelectableGlazeText(text: message.content, onSelectionChange: onSelectionChange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let inference = message.inference {
                    InferenceReceiptView(receipt: inference)
                }
            }
        case .user:
            SelectableOreText(text: message.content, onSelectionChange: onSelectionChange)
                .padding(.leading, 34)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func send() {
        guard model.canSend else { return }
        Task { await model.send(onWillSend: onWillSend) }
    }
}

/// The pure descent layout — the gold spiral tracery at the crown and the
/// 4–6 lines settling top-to-bottom, topmost most luminous (spec §6).
struct ReflectionLinesView: View {
    let lines: [String]
    var reduceMotion: Bool = false

    var body: some View {
        ZStack {
            SpiralTracery(reduceMotion: reduceMotion, listening: lines.isEmpty)
                .frame(width: 96, height: 96)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 96)
                .frame(maxHeight: .infinity, alignment: .top)

            if !lines.isEmpty {
                VStack(spacing: 22) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            // Glaze, applied identically to every line (addendum
                            // A4); the topmost stays slightly more luminous (§6).
                            .glazeVoice()
                            .opacity(index == 0 ? 1.0 : 0.82)
                            .multilineTextAlignment(.center)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8)),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .animation(.easeOut(duration: 0.6), value: lines.count)
    }
}

/// The gold spiral tracery at the crown of the descent — the cooled ear. It
/// pulses slowly while still listening, then settles once the words arrive.
private struct SpiralTracery: View {
    var reduceMotion: Bool
    var listening: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let breath = reduceMotion ? 0.5 : AnkyBreath.phase(at: context.date)
            let glow = listening ? (0.28 + 0.30 * breath) : 0.22
            AnchorSpiral()
                .stroke(Color.ankyGold.opacity(glow),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .shadow(color: Color.ankyGoldLight.opacity(0.4 * glow), radius: 8)
        }
    }
}
