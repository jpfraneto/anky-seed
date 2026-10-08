//
//  ReflectionDescentView.swift
//  Anky — the Geshtu Redesign (spec §6).
//
//  Anky's Markdown reflection settles beneath the writing on the lazure
//  ground. The surface ends with the reflection itself.
//
//  The reflection request fires only after the three-second vigil completes.
//  If it is not ready on arrival, only the quiet status text remains — no icon
//  or spinner between the sealed writing and the reflection.
//
//  Privacy reorder (outwards pivot §4.1): nothing leaves the device at the
//  sentinel anymore. `prepare(for:)` only constructs the view model at
//  channel close; the actual POST /anky starts in `beginUpload()`, called
//  from the Anchor's completed hold — never earlier. This makes the privacy
//  policy's "sent on explicit request" sentence true.
//

import SwiftUI

// MARK: - Coordinator

/// Owns the reflection request for the pending session. Prepared (no network)
/// at channel close; the upload fires only at the writer's outward gesture —
/// the vigil press. Discarded when the writer walks away unsent.
@MainActor
final class GeshtuReflectionCoordinator: ObservableObject {
    @Published private(set) var viewModel: RevealViewModel?
    @Published private(set) var channelState: GeshtuReflectionChannelState = .none
    /// Fires when a reflection for a sent vigil actually reaches the store —
    /// the only moment the free vigil may be marked spent (a vigil whose
    /// reflection never arrives keeps the credit).
    var onPersisted: (() -> Void)?

    private var task: Task<Void, Never>?
    private var currentHash: String?
    private var uploadWasSent = false
    private let requestStarter: @MainActor (RevealViewModel) -> Task<Void, Never>

    init(
        requestStarter: @escaping @MainActor (RevealViewModel) -> Task<Void, Never> = { vm in
            Task { await vm.askAnkyForSealedSession() }
        }
    ) {
        self.requestStarter = requestStarter
    }

    /// Stand the view model up for a just-sealed session — memory only, no
    /// network. Idempotent per hash. The writing has NOT left the device when
    /// this returns; that is the whole point (outwards pivot §4.1).
    func prepare(for session: SavedAnky) {
        if currentHash == session.hash, viewModel != nil { return }
        releaseCurrentRequest()
        let vm = RevealViewModel(artifact: session)
        // Hold the result in memory only; it reaches the store only if the
        // vigil sends (addendum A3 / verification Q4). An unsent session's
        // reflection is never attached to its entry as if it had been received.
        vm.persistsReflection = false
        vm.onReflectionPersisted = { [weak self] in self?.onPersisted?() }
        viewModel = vm
        currentHash = session.hash
        channelState = ReflectionStore().load(hash: session.hash) == nil ? .incomplete : .complete
    }

    /// The writer completed the three-second hold: the explicit outward act.
    /// Only now do the exact writing bytes leave the device. Safe to call on
    /// every completed hold — the view model dedupes an in-flight request,
    /// and another hold after a failure is exactly the retry path.
    func beginUpload() {
        guard let vm = viewModel else { return }
        // Already answered, or a request is still on the wire: nothing to
        // start. (An errored request has isAskingAnky == false, so a re-press
        // after a failure is exactly the retry.)
        if vm.reflection != nil || vm.isAskingAnky { return }
        // The explicit ask is the commit point. From here the result belongs
        // to this writing even if the writer returns to the strata while a
        // slow provider is answering. The backend deliberately does not keep
        // reflection text, so cancelling a sent request on navigation would
        // make a successful server response unrecoverable.
        vm.persistPendingReflection()
        uploadWasSent = true
        channelState = .listening
        let request = requestStarter(vm)
        task = Task { [weak self, weak vm] in
            await request.value
            guard let self, let vm, self.currentHash == vm.hash else { return }
            self.channelState = vm.reflection == nil ? .incomplete : .complete
        }
    }

    /// The vigil completed: the offering was carried. Commit the held reflection
    /// to the store so the sent day owns it in the strata (addendum A3 / Q4).
    func commit() {
        viewModel?.persistPendingReflection()
        if viewModel?.reflection != nil { channelState = .complete }
    }

    /// The day settled unsent, or a new session began: drop the in-flight
    /// result without ever persisting it (unsent ≠ sent — Q4).
    func discard() {
        releaseCurrentRequest()
        viewModel = nil
        currentHash = nil
        channelState = .none
    }

    /// Prepared-but-unsent work is disposable. Once the writer explicitly
    /// sent it, release the UI's handle without cancelling the request: the
    /// task retains its view model long enough to persist the returned result.
    private func releaseCurrentRequest() {
        if uploadWasSent {
            task = nil
        } else {
            cancelTask()
        }
        uploadWasSent = false
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
    }
}

// MARK: - The canonical finished-session screen

enum FinishedSessionStage: Equatable {
    /// The reflection is in flight or has arrived; its conversation follows
    /// directly beneath the sealed writing.
    ///
    /// There is no "awaiting choice" stage any more (in-place completion,
    /// 2026-08-18): a writing that has just ended never leaves the writing
    /// surface, and its two ways forward stand in the keyboard's own place.
    /// This screen is reached when the reflection channel opens, before or
    /// after the writer explicitly asks Anky, or from the archive.
    case conversation
    /// The exact same screen reached from the separate archive list.
    case archived
}

private struct FinishedSessionScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
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
    var onRequestReflection: () -> Void = {}
    /// The menu: slides the drawer in beside this document.
    var onOpenMenu: (() -> Void)?
    var onLateOffer: (() -> Void)?
    /// A legacy or custom server can still deny reflection access: in that
    /// case the error line's tap raises the gate instead of a doomed retry.
    var onNeedsGate: () -> Void = {}

    @State private var preferences = WritingPreferencesStore().load()
    @State private var didPrepare = false
    @State private var observedScrollOffset: CGFloat = 0
    @State private var scrollDirectionExtreme: CGFloat = 0
    @State private var tracksScrollDirection = false
    @State private var contentFrame: CGRect = .zero
    @State private var seamY: CGFloat = 0

    private static let keyboardLineID = "finishedSession.keyboardLine"
    private static let writingStartID = "finishedSession.writingStart"
    private static let topID = "finishedSession.top"
    private static let scrollSpace = "finishedSession.scrollSpace"

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
                        Color.clear
                            .frame(height: 0)
                            .id(Self.topID)
                            .background {
                                GeometryReader { marker in
                                    Color.clear.preference(
                                        key: FinishedSessionScrollOffsetKey.self,
                                        value: marker.frame(in: .named(Self.scrollSpace)).minY
                                    )
                                }
                            }

                        // The day, quietly, under the back button — never a
                        // centered title over the writing.
                        Text(Self.dateFormatter.string(from: artifact.createdAt))
                            .font(.fraunces(12, weight: .light))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 58)

                        // The writing, in the writer's own writing font,
                        // bottom-anchored to the keyboard line — the same
                        // resting place WriteView held it at (its text bottom
                        // inset was keyboard overlap + 24).
                        SelectableOreText(
                            text: artifact.reconstructedText,
                            font: writingFont,
                            ink: Color.ankyUmber.opacity(0.88),
                            lineSpacing: writingLineSpacing,
                            // The fixed top chrome's copy honors this choice.
                            onSelectionChange: { axis.selectedQuote = $0 }
                        )
                        .id(Self.writingStartID)
                        .padding(.horizontal, 24)
                        .padding(.top, 34)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: keyboardLineY.map { max(1, $0 - 58) },
                            alignment: .bottomLeading
                        )

                        Color.clear.frame(height: 1).id(Self.keyboardLineID)
                            .background {
                                GeometryReader { marker in
                                    let y = marker.frame(in: .named(Self.scrollSpace)).minY
                                    Color.clear
                                        .onAppear { seamY = y }
                                        .onChange(of: y) { seamY = $0 }
                                }
                            }

                        finishedSessionTail
                            .padding(.top, 23)
                            .padding(.bottom, 120)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: keyboardLineY.map { max(1, outer.size.height - $0) },
                                alignment: .top
                            )
                    }
                    .background {
                        GeometryReader { content in
                            let frame = content.frame(in: .named(Self.scrollSpace))
                            Color.clear
                                .onAppear { contentFrame = frame }
                                .onChange(of: frame) { contentFrame = $0 }
                        }
                    }
                }
                .coordinateSpace(name: Self.scrollSpace)
                .onPreferenceChange(FinishedSessionScrollOffsetKey.self, perform: observeScrollOffset)
                .overlay(alignment: .trailing) {
                    if showsDocumentRail {
                        documentRail(viewportHeight: outer.size.height) { toAnky in
                            AnkyHaptics.selection()
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(toAnky ? Self.keyboardLineID : Self.topID, anchor: .top)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .onAppear {
                    tracksScrollDirection = false
                    axis.setRevealChromeVisible(true)
                    preferences = WritingPreferencesStore().load()
                    if let keyboardLineY {
                        // A newly sealed session keeps the last line exactly
                        // where it was when the keyboard withdrew.
                        let fraction = max(0.05, min(0.95, (keyboardLineY - 24) / max(1, outer.size.height)))
                        proxy.scrollTo(Self.keyboardLineID, anchor: UnitPoint(x: 0.5, y: fraction))
                    }
                }
                .onChange(of: axis.responseStartRequest) { _ in
                    withAnimation(.easeInOut(duration: 0.58)) {
                        proxy.scrollTo(Self.keyboardLineID, anchor: .top)
                    }
                }
            }
        }
        // The same paper every other surface stands on, so the list, this
        // document, and the writing page never read as three apps.
        .background(Color.ankyPaper.ignoresSafeArea())
        // Scrolled text must not run under the clock: paper stands solid
        // behind the status bar and thins out beneath the floating controls.
        .overlay(alignment: .top) {
            // The fade is a background of a strip that touches the top edge,
            // which is what lets it reach up behind the status bar.
            Color.clear
                .frame(height: 48)
                .background {
                    LinearGradient(
                        stops: [
                            .init(color: Color.ankyPaper, location: 0),
                            .init(color: Color.ankyPaper, location: 0.5),
                            .init(color: Color.ankyPaper.opacity(0), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                }
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                if let onOpenMenu {
                    // The same menu, in the same place, as on the writing
                    // page — a session is not somewhere else.
                    finishedSessionChromeButton(
                        systemName: "line.3.horizontal",
                        accessibilityLabel: "Your writings"
                    ) {
                        AnkyHaptics.light()
                        onOpenMenu()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .opacity(axis.revealChromeIsVisible ? 1 : 0)
            .offset(y: axis.revealChromeIsVisible ? 0 : -7)
            .allowsHitTesting(axis.revealChromeIsVisible)
            .animation(.easeInOut(duration: 0.24), value: axis.revealChromeIsVisible)
        }
        .task {
            await viewModel.prepareAfterFirstRender()
            didPrepare = true
            do {
                // Ignore initial/programmatic positioning; only the reader's
                // subsequent movement should make the controls recede.
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                return
            }
            scrollDirectionExtreme = observedScrollOffset
            tracksScrollDirection = true
        }
        .onDisappear {
            axis.setRevealChromeVisible(true)
        }
    }

    // MARK: The rail

    /// The rail appears once Anky has answered and the document is longer
    /// than the screen — the only time there is somewhere else to be.
    private var showsDocumentRail: Bool {
        let hasReply = viewModel.reflection != nil || !viewModel.streamingReflectionMarkdown.isEmpty
        return hasReply && contentFrame.height > 1
    }

    /// The whole document as one thin line down the trailing edge: the
    /// writer's part in umber, Anky's in violet, a gold bead on the seam, and
    /// a thumb showing what is on screen. Touch a part to go to its start.
    private func documentRail(
        viewportHeight: CGFloat,
        onJump: @escaping (_ toAnky: Bool) -> Void
    ) -> some View {
        let railHeight = max(1, viewportHeight - 190)
        let total = max(contentFrame.height, viewportHeight)
        let seamFraction = min(1, max(0, (seamY - contentFrame.minY) / total))
        let offsetFraction = min(1, max(0, -contentFrame.minY / total))
        let thumbFraction = min(1, viewportHeight / total)
        let seamAt = railHeight * seamFraction
        let thumbHeight = max(18, railHeight * thumbFraction)
        let thumbAt = min(railHeight - thumbHeight, railHeight * offsetFraction)

        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Capsule().fill(Color.ankyUmber.opacity(0.20))
                    .frame(height: max(0, seamAt - 5))
                Color.clear.frame(height: 10)
                Capsule().fill(Color.ankyViolet.opacity(0.42))
            }
            .frame(width: 3, height: railHeight)

            // A document that fits the screen has no position to show.
            if thumbFraction < 0.98 {
                Capsule()
                    .fill(Color.ankyInk.opacity(0.55))
                    .frame(width: 5, height: thumbHeight)
                    .offset(y: thumbAt)
            }

            Circle()
                .fill(Color.ankyGold)
                .frame(width: 8, height: 8)
                .offset(y: seamAt - 4)
        }
        .frame(width: 30, height: railHeight)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { tap in
                onJump(tap.location.y >= seamAt - 16)
            }
        )
        .padding(.top, 70)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement()
        .accessibilityLabel(Text(AnkyLocalization.ui("Go to Anky's reply")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onJump(true) }
    }

    // MARK: The writing's own clothes

    private var writingFont: UIFont {
        preferences.fontChoice.uiFont(size: preferences.textSize.pointSize)
    }

    private var writingLineSpacing: CGFloat {
        preferences.textSize.pointSize * 0.42
    }

    /// A small dead zone prevents jitter from flickering the controls. While
    /// visible we remember the highest offset and hide after moving 18pt into
    /// the document; while hidden we remember the lowest offset and reveal
    /// after moving 12pt back toward the top.
    private func observeScrollOffset(_ offset: CGFloat) {
        observedScrollOffset = offset
        guard tracksScrollDirection else {
            scrollDirectionExtreme = offset
            return
        }

        if axis.revealChromeIsVisible {
            scrollDirectionExtreme = max(scrollDirectionExtreme, offset)
            if offset < scrollDirectionExtreme - 18 {
                scrollDirectionExtreme = offset
                axis.setRevealChromeVisible(false)
            }
        } else {
            scrollDirectionExtreme = min(scrollDirectionExtreme, offset)
            if offset > scrollDirectionExtreme + 12 {
                scrollDirectionExtreme = offset
                axis.setRevealChromeVisible(true)
            }
        }
    }

    private func finishedSessionChromeButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ankyInkSoft)
                .frame(width: 44, height: 44)
                .ankyGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isDeleting)
        .accessibilityLabel(Text(AnkyLocalization.ui(accessibilityLabel)))
    }

    // MARK: The rest of the session

    @ViewBuilder
    private var finishedSessionTail: some View {
        if stage == .archived,
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

    private var archivedWithoutReflection: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.ankyGold.opacity(0.30))
                .frame(width: 46, height: 1.5)
            if let onLateOffer {
                Button {
                    onLateOffer()
                } label: {
                    Text(AnkyLocalization.ui("ask anky for reflection"))
                        .font(.fraunces(17, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInk)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Color.ankyPaper.opacity(0.92))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(Color.ankyGold.opacity(0.55), lineWidth: 1)
                                )
                                .shadow(color: Color.ankyViolet.opacity(0.10), radius: 5, y: 2)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            } else {
                Text(AnkyLocalization.ui("This writing stayed on this device."))
                    .font(.fraunces(14, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: The response

    @ViewBuilder
    private var reflectionBlock: some View {
        // Markdown renders as prose: quiet purple body text with Anky-palette
        // color on headings, emphasis, list ornaments, and other semantics.
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
                // Still listening: just say so. No Geshtu/spiral icon stands
                // between the sealed writing and the words coming back.
                VStack {
                    Text(viewModel.reflectionStatusMessage.isEmpty
                         ? AnkyLocalization.ui("i am preparing your reflection.")
                         : viewModel.reflectionStatusMessage)
                        .font(.fraunces(13, weight: .light, italic: true))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
            } else {
                // Native selection chooses any exact range; the fixed copy
                // control above follows that range.
                SelectableGlazeText(
                    text: source,
                    onSelectionChange: { axis.selectedQuote = $0 }
                )
                .padding(.horizontal, 30)
                .animation(.easeOut(duration: 0.6), value: source)

                if let receipt = viewModel.reflection?.inference {
                    VStack(alignment: .leading, spacing: 12) {
                        InferenceReceiptView(receipt: receipt)
                        if receipt.access == .free {
                            Button {
                                AnkyHaptics.light()
                                onNeedsGate()
                            } label: {
                                Text(AnkyLocalization.ui("Unlock better reflections with Anky Pro"))
                                    .font(.fraunces(14, weight: .regular))
                                    .foregroundStyle(Color.ankyViolet)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Color.ankyPaper.opacity(0.72), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.45), lineWidth: 0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
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
    private let onOpenMenu: (() -> Void)?
    private let onLateOffer: ((SavedAnky, RevealViewModel) -> Void)?

    init(
        artifact: SavedAnky,
        axis: GeshtuState,
        onOpenMenu: (() -> Void)? = nil,
        onLateOffer: ((SavedAnky, RevealViewModel) -> Void)? = nil
    ) {
        self.artifact = artifact
        self.axis = axis
        self.onOpenMenu = onOpenMenu
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
            onOpenMenu: onOpenMenu,
            onLateOffer: onLateOffer.map { request in
                { request(artifact, viewModel) }
            }
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

/// The pure text descent: 4–6 lines settling top-to-bottom, topmost most
/// luminous (spec §6). The pre-reflection Geshtu icon was deliberately removed.
struct ReflectionLinesView: View {
    let lines: [String]

    var body: some View {
        Group {
            if !lines.isEmpty {
                VStack(spacing: 22) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            // Glaze, applied identically to every line; the
                            // topmost stays slightly more luminous (§6).
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
