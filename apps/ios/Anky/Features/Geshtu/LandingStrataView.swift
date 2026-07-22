//
//  LandingStrataView.swift
//  Anky — the Geshtu Redesign (spec §7).
//
//  The landing surface: everything "outside the writing." A single centered
//  column of past sessions rising from the Anchor — first line of the writing
//  and a small date, nothing else. Newest at top; entries grow progressively
//  fainter with age, absorbed into the pigment like sediment strata.
//
//  Doctrine: the column is made only of presence. No streaks, no gaps, no
//  counters, no grayed missed days. Absence is never rendered.
//
//  At the very bottom, beneath the oldest entry, a single quiet glyph — the
//  seed — opens settings, subscription, and account deletion. The user who
//  scrolls through their entire past arrives at their origin.
//

import SwiftUI

struct LandingStrataView<WritingPage: View>: View {
    @ObservedObject var axis: GeshtuState
    /// The real writing surface — the literal top of the vertical world. It
    /// lives INSIDE the world scroll (the unified-scroll refactor,
    /// 2026-07-17): moving between the geshtu and the strata is actual
    /// scrolling, with native physics, not a surface swap.
    @ViewBuilder let writingPage: () -> WritingPage
    /// True while a session is in progress (first keystroke landed): the
    /// world scroll is locked and only the silence sentinel closes the
    /// channel.
    let writingLocked: Bool
    /// The writing page scrolled out of the world (settled unsent, or a blank
    /// page abandoned): the owner resets the engine so the page above is
    /// blank again.
    let onWritingSettled: () -> Void

    /// The days, newest first. Loaded from the local archive — the same store
    /// the writing session seals into.
    @State private var entries: [SavedAnky] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The thread scrubber (user decision, 2026-07-16): a vertical thread on
    // the right edge, each writing a knot on it, surfacing while the strata
    // scrolls and fading once the movement rests.
    @State private var scrollFraction: CGFloat = 0
    @State private var scrubberVisible = false
    @State private var isScrubbing = false
    @State private var scrubberHideTask: Task<Void, Never>?

    // The writing approach (user decision, 2026-07-16): the top of the
    // vertical world, one screen above the newest day. Scrolling the page
    // fully into view locks it and opens the keyboard; the geshtu tap rides
    // the same scroll. Armed only after the initial rest, so the first
    // layout pass can never fire it.
    @State private var approachArmed = false
    @State private var approachLocked = false

    // The gravity pull (user idea, 2026-07-17): the grey geshtu at the base
    // of an unreflected day, taken. A small spiral falls from the exact dot
    // the writer touched into the real Anchor while the world scrolls to
    // connect the two; landing arms the late offering and the Anchor's
    // awaiting corona ignites. Screen-global coordinates.
    @State private var lateOfferFlightPoint: CGPoint?
    @State private var lateOfferFlightVisible = false
    @State private var lateOfferInFlight = false

    var body: some View {
        Group {
            if entries.isEmpty {
                // Day one: no strata to scroll through — the writing page is
                // the whole world until the first day settles.
                if axis.phase == .writing || axis.phase == .channelClosed {
                    dayOneWritingSurface
                } else {
                    emptyState
                }
            } else {
                strata
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear(perform: reload)
        // A channel just closed: the sealed session is in the archive now, so
        // the sediment below already contains today — scrolling away from the
        // sealed page re-encounters the same words as the newest stratum, and
        // the settle itself changes nothing visually. (Day one defers this to
        // the landing so the seal never remounts the page mid-beat.)
        .onChange(of: axis.phase) { phase in
            if phase == .channelClosed && !entries.isEmpty { reload() }
            if phase == .landing { reload() }
        }
        // Day one has no strata to scroll through — the geshtu tap opens the
        // page directly.
        .onChange(of: axis.approachTick) { _ in
            if entries.isEmpty { axis.openWriting() }
        }
        #if DEBUG
        .onChange(of: axis.debugReloadTick) { _ in reload() }
        #endif
    }

    /// The fullscreen writing page of day one. The world scroll doesn't exist
    /// yet, so the closed channel keeps the decisive flick-away it always had.
    private var dayOneWritingSurface: some View {
        writingPage()
            .highPriorityGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        if value.translation.height < -70 {
                            AnkyHaptics.light()
                            axis.settleToLanding()
                            onWritingSettled()
                        }
                    },
                including: axis.phase == .channelClosed ? .all : .subviews
            )
    }

    // MARK: - The strata column

    private static var space: String { "landingStrata" }

    private static var approachID: String { "axis.strata.approach" }

    private var strata: some View {
        GeometryReader { viewport in
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // The real writing surface, seen from below: the top of
                    // the whole vertical thing. Scrolling it fully in locks
                    // it and opens the keyboard; scrolling it away settles
                    // the day. One scroll space, native physics — never a
                    // surface swap (unified-scroll refactor, 2026-07-17).
                    writingPage()
                        .frame(height: viewport.size.height)
                        .id(Self.approachID)
                        .background(approachSentinel(viewportHeight: viewport.size.height))

                    StrataColumn(
                        axis: axis,
                        entries: entries,
                        onLateOffer: lateOfferInFlight ? nil : { entry, point in
                            beginLateOffer(entry, from: point, proxy: proxy)
                        }
                    )
                        // The column's own top offset in the scroll space tells us
                        // whether we rest at the living edge or are deep in memory
                        // (addendum A1). O(1) per scroll — it never touches a stratum.
                        .background(scrollSentinel)
                }
            }
            .coordinateSpace(name: Self.space)
            // A session in progress seals the world shut: nothing but the
            // silence sentinel closes the channel (user decision, 2026-07-17).
            .scrollDisabled(writingLocked)
            // Dragging down from the blank page lowers the keyboard with the
            // finger and continues into the archive — one native motion.
            .scrollDismissesKeyboard(.interactively)
            // The boundary is magnetic (iOS 17+): a drag ending inside the
            // approach zone settles fully on the page or fully on the strata,
            // never half-way.
            .approachSnap(pageHeight: viewport.size.height)
            // Arrive where the phase says we live: at the page when the
            // channel is open (or just closed), at the newest day otherwise.
            // Only after that rest does the lock arm.
            .onAppear {
                if axis.phase == .writing || axis.phase == .channelClosed {
                    proxy.scrollTo(Self.approachID, anchor: .top)
                    approachLocked = true
                } else {
                    proxy.scrollTo(StrataColumn.topID, anchor: .top)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    approachArmed = true
                }
            }
            // The geshtu was tapped at the living edge: carry the world up
            // into the approach — the lock sentinel opens the keyboard when
            // the footprint arrives.
            .onChange(of: axis.approachTick) { _ in
                withAnimation(reduceMotion
                    ? .easeOut(duration: 0.3)
                    : .easeInOut(duration: 0.5)) {
                    proxy.scrollTo(Self.approachID, anchor: .top)
                }
            }
            // Surface to now: come up for air — fast, a slight overshoot,
            // settling at the newest entry (addendum A1). Not scrollTo(0).
            .onChange(of: axis.surfaceTick) { _ in
                AnkyHaptics.light()
                withAnimation(reduceMotion
                    ? .easeOut(duration: 0.3)
                    : .spring(response: 0.34, dampingFraction: 0.62)) {
                    proxy.scrollTo(StrataColumn.topID, anchor: .top)
                }
            }
            // The thread on the right edge: the whole archive as a vertical
            // filament, one knot per writing, the bottom of the thread the
            // bottom of the archive. It surfaces while scrolling; dragging
            // it scrubs the strata, a date whispering beside the thumb.
            .overlay(lateOfferFlightOverlay)
            .overlay(alignment: .trailing) {
                StrataThreadScrubber(
                    entries: entries,
                    fraction: scrollFraction,
                    isVisible: scrubberVisible || isScrubbing,
                    onScrub: { entry, active in
                        isScrubbing = active
                        if active {
                            scrubberHideTask?.cancel()
                            scrubberVisible = true
                            proxy.scrollTo(entry.id, anchor: .top)
                        } else {
                            scheduleScrubberHide()
                        }
                    }
                )
            }
        }
        }
    }

    /// Watches the writing page in the world scroll, both directions of the
    /// same road. Arriving — the page standing fully in view — locks it and
    /// opens the keyboard; the writer's own scroll and the geshtu-tap scroll
    /// both end here. Leaving — the page mostly gone past the top — settles
    /// the day (unsent at a closed channel; simply abandoned from a blank
    /// page) and resets the engine so the page above is blank again.
    private func approachSentinel(viewportHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(Self.space)).minY
            Color.clear
                .onChange(of: minY) { y in
                    if approachArmed, !approachLocked,
                       axis.phase == .landing,
                       y >= -8 {
                        approachLocked = true
                        AnkyHaptics.light()
                        axis.openWriting()
                        return
                    }
                    if approachLocked,
                       axis.phase == .writing || axis.phase == .channelClosed,
                       y <= -viewportHeight * 0.6 {
                        approachLocked = false
                        // A fast flick can outrun the interactive dismissal:
                        // make sure the keyboard never floats over the strata.
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                        axis.settleToLanding()
                        onWritingSettled()
                    }
                }
        }
    }

    // MARK: - The late-offer gravity pull

    /// Where the Anchor's medallion rests, in screen-global coordinates — its
    /// eternal position: centered, `AnchorView.bottomInset` above the
    /// safe-area bottom.
    private var anchorGlobalCenter: CGPoint {
        let bounds = UIScreen.main.bounds
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
        return CGPoint(
            x: bounds.midX,
            y: bounds.height - bottomInset - AnchorView.bottomInset - AnchorView.diameter / 2
        )
    }

    /// The pull itself: the world scrolls the day's base toward the Anchor
    /// while the taken spiral falls — slow release, accelerating, gravity —
    /// from the exact dot the writer touched into the medallion. Landing arms
    /// the late offering; the Anchor's invitation ignites and the ordinary
    /// hold-to-send vigil takes over.
    private func beginLateOffer(_ entry: SavedAnky, from point: CGPoint, proxy: ScrollViewProxy) {
        guard !lateOfferInFlight else { return }
        AnkyHaptics.medium()
        if reduceMotion {
            axis.armReOffering(entry)
            return
        }
        lateOfferInFlight = true
        lateOfferFlightPoint = point
        lateOfferFlightVisible = true
        withAnimation(.easeInOut(duration: 0.55)) {
            proxy.scrollTo(StrataColumn.lateOfferID, anchor: UnitPoint(x: 0.5, y: 0.78))
        }
        withAnimation(.timingCurve(0.5, 0, 0.85, 0.4, duration: 0.7)) {
            lateOfferFlightPoint = anchorGlobalCenter
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 620_000_000)
            withAnimation(.easeOut(duration: 0.22)) { lateOfferFlightVisible = false }
            axis.armReOffering(entry)
            AnkyHaptics.success()
            try? await Task.sleep(nanoseconds: 260_000_000)
            lateOfferFlightPoint = nil
            lateOfferInFlight = false
        }
    }

    /// The falling spiral, drawn above the whole strata in screen space. It
    /// desaturates nothing and hits nothing — pure motion.
    private var lateOfferFlightOverlay: some View {
        GeometryReader { geo in
            if let point = lateOfferFlightPoint {
                let origin = geo.frame(in: .global).origin
                Image("GeshtuAnchor")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .saturation(0)
                    .opacity(lateOfferFlightVisible ? 0.75 : 0)
                    .scaleEffect(lateOfferFlightVisible ? 1 : 0.5)
                    .position(x: point.x - origin.x, y: point.y - origin.y)
            }
        }
        .allowsHitTesting(false)
    }

    /// Keep the thread visible while the strata moves; let it sink back into
    /// the pigment shortly after the movement rests.
    private func markScrolling() {
        scrubberVisible = true
        scheduleScrubberHide()
    }

    private func scheduleScrubberHide() {
        scrubberHideTask?.cancel()
        scrubberHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled, !isScrubbing else { return }
            withAnimation(.easeInOut(duration: 0.5)) { scrubberVisible = false }
        }
    }

    /// Reports whether the strata rests at (or within ~half a screen of) the
    /// top. Tolerance is deliberate — no pixel-hunting (addendum A1).
    private var scrollSentinel: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(Self.space)).minY
            Color.clear
                .onChange(of: minY) { y in
                    updateAtTop(minY: y, columnHeight: geo.size.height)
                    markScrolling()
                }
                .onAppear { updateAtTop(minY: minY, columnHeight: geo.size.height) }
        }
    }

    private func updateAtTop(minY: CGFloat, columnHeight: CGFloat) {
        let viewport = UIScreen.main.bounds.height
        let tolerance = viewport * 0.5
        let atTop = minY > -tolerance
        if axis.landingAtTop != atTop {
            axis.landingAtTop = atTop
        }
        let travel = max(1, columnHeight - viewport)
        scrollFraction = min(1, max(0, -minY / travel))
    }

    // MARK: - Empty state (day one)

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("nothing here yet.\neverything you write will rise.")
                .font(.fraunces(19, weight: .light, italic: true))
                .foregroundStyle(Color.ankyInkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 44)
            Spacer()
            // Clearance for the Anchor pulsing gently at the base.
            Color.clear.frame(height: 200)
        }
    }

    private func reload() {
        entries = LocalAnkyArchive().list()
        // Arriving fresh at the landing, we rest at the living edge.
        axis.landingAtTop = true
    }
}

// MARK: - The approach snap (unified-scroll refactor, 2026-07-17)

/// The magnetic boundary between the writing page and the strata: a drag
/// that ends inside the approach zone settles fully on the page (which locks
/// and opens the keyboard) or fully on the newest day — never half-way. The
/// strata itself scrolls freely; the behavior only touches the first
/// viewport of the world.
@available(iOS 17.0, *)
private struct ApproachSnapBehavior: ScrollTargetBehavior {
    let pageHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let y = target.rect.origin.y
        guard y > 0, y < pageHeight else { return }
        // Velocity carries intent: a real flick commits to its direction
        // even before the midpoint.
        let bias = max(-1, min(1, context.velocity.dy / 900)) * pageHeight * 0.25
        target.rect.origin.y = (y + bias) < pageHeight / 2 ? 0 : pageHeight
    }
}

private extension View {
    /// Applies the approach snap where the API exists; iOS 16 keeps plain
    /// scrolling (the sentinels still lock and settle, just without the
    /// magnetic rest).
    @ViewBuilder
    func approachSnap(pageHeight: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            scrollTargetBehavior(ApproachSnapBehavior(pageHeight: pageHeight))
        } else {
            self
        }
    }
}

// MARK: - The thread scrubber (user decision, 2026-07-16)

/// The archive as a thread on the right edge of the screen: a faint gold
/// filament, one knot per writing, newest at the top — the bottom of the
/// thread is the bottom of the archive. It surfaces while the strata scrolls
/// and sinks back into the pigment at rest. Dragging it scrubs the strata
/// directly; the date of the day under the thumb whispers beside the thread.
private struct StrataThreadScrubber: View {
    let entries: [SavedAnky]
    /// Current scroll position, 0 = newest (top) … 1 = oldest (bottom).
    let fraction: CGFloat
    let isVisible: Bool
    /// Fired while scrubbing (`active: true` per move, `false` on release).
    let onScrub: (SavedAnky, Bool) -> Void

    @State private var dragFraction: CGFloat?
    @State private var lastIndex: Int?

    /// Room above for the top chrome, below for the Anchor at the base.
    private static let topInset: CGFloat = 96
    private static let bottomInset: CGFloat = 118
    /// Past this many days the knots sample evenly — the thread stays a
    /// thread, never a rope.
    private static let maxKnots = 48

    var body: some View {
        GeometryReader { geo in
            let threadHeight = max(1, geo.size.height - Self.topInset - Self.bottomInset)
            let thumbFraction = dragFraction ?? fraction
            // The thread's centerline, riding the right edge.
            let x = geo.size.width - 20

            ZStack {
                // The filament.
                Capsule()
                    .fill(Color.ankyGold.opacity(0.35))
                    .frame(width: 1.5, height: threadHeight)
                    .position(x: x, y: Self.topInset + threadHeight / 2)

                // The knots — each writing a knot on the thread.
                ForEach(knotFractions, id: \.self) { knot in
                    Circle()
                        .fill(Color.ankyGold.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .position(x: x, y: Self.topInset + knot * threadHeight)
                }

                // Where you are on the thread now.
                Circle()
                    .fill(Color.ankyGold)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.ankyPaper.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: Color.ankyGold.opacity(0.5), radius: 4)
                    .position(x: x, y: Self.topInset + thumbFraction * threadHeight)

                // The date under the thumb, whispered while scrubbing.
                if dragFraction != nil, let entry = entry(at: thumbFraction) {
                    Text(Self.dateFormatter.string(from: entry.createdAt).lowercased())
                        .font(.fraunces(13, weight: .regular))
                        .foregroundStyle(Color.ankyInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            Capsule()
                                .fill(Color.ankyPaper.opacity(0.92))
                                .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.35), lineWidth: 0.5))
                                .shadow(color: Color.ankyViolet.opacity(0.18), radius: 8, y: 2)
                        }
                        .fixedSize()
                        .position(x: x - 82, y: Self.topInset + thumbFraction * threadHeight)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                // The touchable strip: generous, invisible, anchored on the
                // thread itself — never on the full-screen container (the
                // AnchorView hit-shape lesson).
                Color.clear
                    .frame(width: 44, height: threadHeight + 40)
                    .contentShape(Rectangle())
                    .position(x: x, y: Self.topInset + threadHeight / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // The gesture's y is local to the strip:
                                // 20pt of grace above the thread's crown.
                                let f = min(1, max(0, (value.location.y - 20) / threadHeight))
                                dragFraction = f
                                guard let entry = entry(at: f) else { return }
                                let index = index(at: f)
                                if index != lastIndex {
                                    lastIndex = index
                                    AnkyHaptics.selection()
                                }
                                onScrub(entry, true)
                            }
                            .onEnded { _ in
                                if let f = dragFraction, let entry = entry(at: f) {
                                    onScrub(entry, false)
                                }
                                withAnimation(.easeOut(duration: 0.25)) { dragFraction = nil }
                                lastIndex = nil
                            }
                    )
            }
        }
        .opacity(isVisible && entries.count > 1 ? 1 : 0)
        .allowsHitTesting(isVisible && entries.count > 1)
        .animation(.easeInOut(duration: 0.35), value: isVisible)
        .accessibilityElement()
        .accessibilityLabel(Text("Archive thread"))
        .accessibilityHint(Text("Drag to move through your writings."))
    }

    /// Knot positions as fractions of the thread, evenly spaced; sampled when
    /// the archive outgrows the thread's resolution.
    private var knotFractions: [CGFloat] {
        let count = entries.count
        guard count > 1 else { return [0] }
        let shown = min(count, Self.maxKnots)
        return (0..<shown).map { CGFloat($0) / CGFloat(shown - 1) }
    }

    private func index(at fraction: CGFloat) -> Int {
        guard entries.count > 1 else { return 0 }
        return Int(round(fraction * CGFloat(entries.count - 1)))
    }

    private func entry(at fraction: CGFloat) -> SavedAnky? {
        guard !entries.isEmpty else { return nil }
        return entries[index(at: fraction)]
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()
}

// MARK: - The column (shared by the landing and the reflection settle)

/// The sediment column itself, without a scroll view of its own, so it can be
/// embedded beneath the reflection in one continuous scroll (spec §7).
///
/// Tapping a stub decompresses the day in place — inline, within the column,
/// pushing its neighbours apart (addendum A2). There is no pushed screen, no
/// sheet, no modal: the map never stops being a map. While a day is open its
/// date header pins to the top; tapping the pinned header compresses it back.
/// One day open at a time — opening another seals the current one first.
struct StrataColumn: View {
    @ObservedObject var axis: GeshtuState
    let entries: [SavedAnky]
    /// The gravity pull's first half (user idea, 2026-07-17): an unreflected
    /// open day carries a grey geshtu at its base; taking it hands the entry
    /// and the touched dot (screen-global) to the landing surface, which
    /// scrolls-and-falls the spiral into the Anchor. Nil (the default, and
    /// the reflection-settle canvas) shows no glyph.
    var onLateOffer: ((SavedAnky, CGPoint) -> Void)? = nil

    /// The living edge — the scroll target for surfacing-to-now (addendum A1).
    static let topID = "axis.strata.top"

    /// The grey geshtu at an open day's base — the scroll target the gravity
    /// pull travels to.
    static let lateOfferID = "axis.strata.lateOffer"

    // A tapped paragraph leaving as a share card. Surface-level share and
    // record live in the world's fixed top chrome (product decision,
    // 2026-07-15) — nothing rides the bottom of an opened day anymore.
    @State private var shareRequest: GeshtuShareRequest?

    var body: some View {
        LazyVStack(spacing: 22) {
            // A little breath before the newest day.
            Color.clear.frame(height: 24)
                .id(Self.topID)

            let openedIndex = axis.openedEntry.flatMap { opened in
                entries.firstIndex(where: { $0.id == opened.id })
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                // The garment between days (user request, 2026-07-17): the
                // sash Anky wears, laid flat — a violet thread with the gold
                // diamond chain at its heart. It fades into the pigment with
                // the day beneath it, so the deep past stays quiet. The two
                // garments embracing an OPEN day come to full presence — they
                // are what marks the day open, not a panel (user decision,
                // 2026-07-17, superseding the raised-panel treatment).
                if index > 0 {
                    let embracesOpened = openedIndex.map { index == $0 || index == $0 + 1 } ?? false
                    StrataGarment(emphasized: embracesOpened)
                        .opacity(embracesOpened ? 1 : StrataColumn.ageOpacity(for: index) * 0.85)
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: embracesOpened)
                }
                if entry.id == axis.openedEntry?.id {
                    // The day, decompressed in place — the panel and nothing
                    // else (user decision, 2026-07-16: no pinned header, no
                    // extra element riding on top of the writing).
                    OpenedStrataEntry(
                        entry: entry,
                        // Hidden once armed: the Anchor holds the offering now.
                        onLateOffer: axis.reOffering ? nil : onLateOffer.map { handler in
                            { point in handler(entry, point) }
                        },
                        onClose: { axis.closeEntry() },
                        onShare: { quote in
                            shareRequest = GeshtuShareRequest(quote: quote, voice: .you)
                        },
                        onSelectionChange: {
                            axis.selectedQuote = $0
                            axis.selectedQuoteIsAnky = false
                        },
                        onShareReflection: { quote in
                            shareRequest = GeshtuShareRequest(quote: quote, voice: .anky)
                        },
                        onReflectionSelectionChange: {
                            axis.selectedQuote = $0
                            axis.selectedQuoteIsAnky = $0 != nil
                        }
                    )
                    .transition(.opacity)
                } else {
                    StrataEntryRow(entry: entry, ageOpacity: Self.ageOpacity(for: index))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            AnkyHaptics.selection()
                            axis.openEntry(entry)
                        }
                }
            }

            // Beneath the oldest entry: the seed.
            SeedGlyph { axis.openSeed() }
                .padding(.top, 26)

            // Clearance so the last strata never hides behind the Anchor.
            Color.clear.frame(height: 220)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        // The share card inherits RevealView's renderer — quiet, in register.
        .sheet(item: $shareRequest) { request in
            ShareCardPreviewView(quote: request.quote, voice: request.voice)
        }
    }

    /// Entries grow fainter with age (spec §7). Newest is full presence; the
    /// column sinks toward the pigment. Floored so the oldest is still faintly
    /// legible, never fully gone.
    static func ageOpacity(for index: Int) -> Double {
        let step = 0.11
        return max(0.16, 1.0 - Double(index) * step)
    }
}

/// A quote leaving the world as a share card, signed by whoever's words they
/// are: the reflection is ANKY, the writing is YOU. Shared with the
/// channel-closed surface (GeshtuWorldView).
struct GeshtuShareRequest: Identifiable {
    let id = UUID()
    let quote: String
    var voice: ShareCardVoice = .anky
}

// MARK: - A single stratum

/// One settled day: the first line of the writing, and a small date beneath.
/// Nothing else (spec §7). Tapping brightens it back to full presence and
/// opens it to read in full — handled by the parent.
private struct StrataEntryRow: View {
    let entry: SavedAnky
    let ageOpacity: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(firstLine)
                .font(.fraunces(20, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(dateLine)
                .font(.fraunces(12, weight: .light))
                .foregroundStyle(Color.ankyInkSoft)
        }
        .frame(maxWidth: .infinity)
        .opacity(ageOpacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(firstLine), \(dateLine)"))
        .accessibilityHint(Text("Opens this day to read in full."))
    }

    private var firstLine: String {
        for line in entry.reconstructedText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "—"
    }

    private var dateLine: String {
        StrataEntryRow.dateFormatter.string(from: entry.createdAt).lowercased()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()
}

// MARK: - Opened entry (decompressed in place — addendum A2)

/// The body of an opened day, in its original orientation (addendum A2.2): the
/// user's writing first, in full, at the top; then — after a quiet seam — Anky's
/// reflection, reached only by scrolling down through one's own words. There is
/// no control, chip, or tab that shows the reflection directly; it is never
/// separately addressable. An unsent day contains the writing only and ends
/// where the writing ends (addendum A3.2).
private struct OpenedStrataEntry: View {
    let entry: SavedAnky
    /// Present only while this unreflected day may still be offered: the grey
    /// geshtu at the day's base hands the touched dot up for the gravity pull.
    var onLateOffer: ((CGPoint) -> Void)? = nil
    let onClose: () -> Void
    let onShare: (String) -> Void
    let onSelectionChange: (String?) -> Void
    let onShareReflection: (String) -> Void
    let onReflectionSelectionChange: (String?) -> Void

    var body: some View {
        // One disk read per open; the opened day re-renders rarely.
        let reflection = ReflectionStore().load(hash: entry.hash)?.reflection
        let hasReflection = !(reflection ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 0) {
            // The day's date, inside the panel — tap it to close the day.
            Text(Self.dateFormatter.string(from: entry.createdAt).lowercased())
                .font(.fraunces(13, weight: .light))
                .foregroundStyle(Color.ankyInkSoft)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    AnkyHaptics.selection()
                    onClose()
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text("\(Self.dateFormatter.string(from: entry.createdAt)). Close this day."))

            // The writing — ore (addendum A4). Tap a paragraph to choose it;
            // the corner blob shares it, and the fixed top chrome honors the
            // choice too.
            TappableOreText(
                text: entry.reconstructedText,
                onShare: onShare,
                onSelectionChange: onSelectionChange
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if !hasReflection, let onLateOffer {
                // An unreflected day still holds its offering (user idea,
                // 2026-07-17): a grey geshtu rests where the reflection would
                // begin — the medallion without its warmth. Taking it starts
                // the gravity pull down to the real Anchor.
                LateOfferGlyph(onTake: onLateOffer)
                    .id(StrataColumn.lateOfferID)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34)
            }

            if hasReflection, let reflection {
                // A quiet seam, then the reflection — glaze (retrofit in A4).
                Seam()
                    .padding(.vertical, 34)

                // Anky's reflection at rest — glaze, markdown honored in the
                // accent pigments, each paragraph choosable and shareable as
                // an ANKY-signed card (same act as the writing above).
                TappableGlazeText(
                    text: reflection,
                    onShare: onShareReflection,
                    onSelectionChange: onReflectionSelectionChange
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        // No panel (user decision, 2026-07-17, superseding the raised-panel
        // treatment of 2026-07-16): the open day lies in the sediment like
        // every other, held only by its two garments at full presence. The
        // words themselves — full instead of a single line — are the
        // openness.
        //
        // Clearance below so the day's tail is never hidden behind the
        // Anchor.
        .padding(.bottom, 34)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMMM yyyy"
        return f
    }()
}

/// The garment between settled days (user request, 2026-07-17): Anky's sash,
/// laid flat between the strata. Studied from the reference sprite — a woven
/// violet band embroidered with a chain of gold diamonds, cinched at the
/// center by the square gold buckle. Here it is a whisper of that: a violet
/// thread tapering into the pigment at both ends, three diamonds riding it,
/// the middle one belted like the buckle. Drawn, not typeset; it fades with
/// age like the days it separates.
struct StrataGarment: View {
    /// True on the two garments embracing an open day: the sash comes to
    /// full presence — stronger pigments, a touch of gold light — because IT
    /// is what marks the day open (user decision, 2026-07-17; there is no
    /// panel).
    var emphasized: Bool = false

    private var gold: Color { Color.ankyGold }
    private var violet: Color { Color.ankyViolet }
    private var threadOpacity: Double { emphasized ? 0.62 : 0.38 }
    private var goldStroke: Double { emphasized ? 0.95 : 0.60 }
    private var goldFill: Double { emphasized ? 0.85 : 0.50 }

    var body: some View {
        HStack(spacing: 9) {
            thread(fadeEdge: .leading)
            diamond(size: 4.5)
            thread(fadeEdge: .none)
            // The buckle: an open gold diamond holding a smaller heart.
            ZStack {
                Rectangle()
                    .rotation(.degrees(45))
                    .stroke(gold.opacity(goldStroke), lineWidth: 1)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .rotation(.degrees(45))
                    .fill(gold.opacity(goldFill * 0.9))
                    .frame(width: 3, height: 3)
            }
            .frame(width: 12, height: 12)
            thread(fadeEdge: .none)
            diamond(size: 4.5)
            thread(fadeEdge: .trailing)
        }
        .frame(width: 190, height: 14)
        .frame(maxWidth: .infinity)
        .shadow(color: gold.opacity(emphasized ? 0.35 : 0), radius: 4)
        .animation(.easeInOut(duration: 0.25), value: emphasized)
        .accessibilityHidden(true)
    }

    private enum FadeEdge { case leading, trailing, none }

    /// A strand of the sash: violet, sinking into the pigment at the world's
    /// outer edges, full where it meets the gold.
    private func thread(fadeEdge: FadeEdge) -> some View {
        let full = violet.opacity(threadOpacity)
        let colors: [Color]
        switch fadeEdge {
        case .leading:  colors = [violet.opacity(0), full]
        case .trailing: colors = [full, violet.opacity(0)]
        case .none:     colors = [full, full]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func diamond(size: CGFloat) -> some View {
        Rectangle()
            .rotation(.degrees(45))
            .fill(gold.opacity(goldFill))
            .frame(width: size, height: size)
    }
}

/// The quiet break between the writing and the reflection — a short gold
/// hairline, centered. Never labelled; typography and this seam carry the shift
/// from one voice to the other (addendum A2.2, A4).
private struct Seam: View {
    var body: some View {
        Capsule()
            .fill(Color.ankyGold.opacity(0.30))
            .frame(width: 46, height: 1.5)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - The late-offer glyph (user idea, 2026-07-17)

/// The geshtu medallion in scales of grey, resting at the base of an
/// unreflected day: the offering that was never carried. Not an ornament — a
/// button. Taking it reports the exact dot touched (screen-global) so gravity
/// can pull from that point into the Anchor.
private struct LateOfferGlyph: View {
    let onTake: (CGPoint) -> Void

    @State private var globalCenter: CGPoint = .zero

    var body: some View {
        Button {
            onTake(globalCenter)
        } label: {
            Image("GeshtuAnchor")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .saturation(0)
                .opacity(0.55)
                .background {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.ankyInk.opacity(0.10), .clear],
                                center: .center, startRadius: 2, endRadius: 30
                            )
                        )
                        .frame(width: 62, height: 62)
                }
                .padding(14)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { globalCenter = CGPoint(x: frame.midX, y: frame.midY) }
                    .onChange(of: frame) { new in
                        globalCenter = CGPoint(x: new.midX, y: new.midY)
                    }
            }
        }
        .accessibilityLabel(Text("Offer this day to Anky."))
        .accessibilityHint(Text("Carries this writing to the Anchor; hold the Anchor to send it."))
    }
}

// MARK: - The seed

/// The single quiet glyph at the base of the past (spec §7). The small spiral
/// sun — no gear icon, no label. Opens the seed (settings / subscription /
/// account). Faint, at rest; it is not an invitation, only an origin.
struct SeedGlyph: View {
    let onOpen: () -> Void

    var body: some View {
        Button {
            AnkyHaptics.light()
            onOpen()
        } label: {
            AnkySunGlyph(size: 22, color: .ankyGold)
                .opacity(0.5)
                .padding(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("The seed. Settings and account."))
    }
}
