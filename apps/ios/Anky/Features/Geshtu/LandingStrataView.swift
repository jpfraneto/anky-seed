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

struct LandingStrataView: View {
    @ObservedObject var axis: GeshtuState

    /// The days, newest first. Loaded from the local archive — the same store
    /// the writing session seals into.
    @State private var entries: [SavedAnky] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                strata
            }
        }
        .onAppear(perform: reload)
        #if DEBUG
        .onChange(of: axis.debugReloadTick) { _ in reload() }
        #endif
    }

    // MARK: - The strata column

    private static let space = "landingStrata"

    private var strata: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                StrataColumn(axis: axis, entries: entries)
                    // The column's own top offset in the scroll space tells us
                    // whether we rest at the living edge or are deep in memory
                    // (addendum A1). O(1) per scroll — it never touches a stratum.
                    .background(scrollSentinel)
            }
            .coordinateSpace(name: Self.space)
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
        }
    }

    /// Reports whether the strata rests at (or within ~half a screen of) the
    /// top. Tolerance is deliberate — no pixel-hunting (addendum A1).
    private var scrollSentinel: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(Self.space)).minY
            Color.clear
                .onChange(of: minY) { y in
                    updateAtTop(minY: y)
                }
                .onAppear { updateAtTop(minY: minY) }
        }
    }

    private func updateAtTop(minY: CGFloat) {
        let tolerance = UIScreen.main.bounds.height * 0.5
        let atTop = minY > -tolerance
        if axis.landingAtTop != atTop {
            axis.landingAtTop = atTop
        }
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

    /// The living edge — the scroll target for surfacing-to-now (addendum A1).
    static let topID = "axis.strata.top"

    // The opened day's quiet affordances (addendum A2.5): share the day's
    // reflection as a card, or record it. Nothing floats over the writing —
    // these are reached from the bottom of the opened day.
    @State private var recordRequest: GeshtuRecordRequest?
    @State private var shareRequest: GeshtuShareRequest?

    var body: some View {
        LazyVStack(spacing: 34, pinnedViews: axis.openedEntry != nil ? [.sectionHeaders] : []) {
            // A little breath before the newest day.
            Color.clear.frame(height: 24)
                .id(Self.topID)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if entry.id == axis.openedEntry?.id {
                    // The day, decompressed in place. Its date header is the
                    // pinned section header (sticky, tap-to-close).
                    Section {
                        OpenedStrataEntry(
                            entry: entry,
                            onRecord: { recordRequest = GeshtuRecordRequest(text: $0) },
                            onShare: { shareRequest = GeshtuShareRequest(quote: $0) }
                        )
                        .transition(.opacity)
                    } header: {
                        OpenedStrataHeader(entry: entry) { axis.closeEntry() }
                    }
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
        // AnkyRecordingView is reached only from here (spec §12); the share card
        // inherits RevealView's renderer. Both quiet, in the lazure register.
        .fullScreenCover(item: $recordRequest) { request in
            AnkyRecordingView(reflectionText: request.text) { recordRequest = nil }
        }
        .sheet(item: $shareRequest) { request in
            ShareCardPreviewView(quote: request.quote)
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

private struct GeshtuRecordRequest: Identifiable { let id = UUID(); let text: String }
private struct GeshtuShareRequest: Identifiable { let id = UUID(); let quote: String }

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

/// The pinned date header of an opened day. Sticky at the top of the screen
/// while the day is open; tapping it compresses the day back into its stub,
/// neighbours closing around it (addendum A2.3). A soft paper scrim keeps it
/// legible as the writing scrolls beneath — no bar, no chrome, in register.
private struct OpenedStrataHeader: View {
    let entry: SavedAnky
    let onClose: () -> Void

    var body: some View {
        Text(Self.dateFormatter.string(from: entry.createdAt).lowercased())
            .font(.fraunces(13, weight: .light))
            .foregroundStyle(Color.ankyInkSoft)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .background(
                LinearGradient(
                    colors: [Color.ankyPaper, Color.ankyPaper.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom
                )
                .padding(.top, -40)
                .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                AnkyHaptics.selection()
                onClose()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("\(Self.dateFormatter.string(from: entry.createdAt)). Close this day."))
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMMM yyyy"
        return f
    }()
}

/// The body of an opened day, in its original orientation (addendum A2.2): the
/// user's writing first, in full, at the top; then — after a quiet seam — Anky's
/// reflection, reached only by scrolling down through one's own words. There is
/// no control, chip, or tab that shows the reflection directly; it is never
/// separately addressable. An unsent day contains the writing only and ends
/// where the writing ends (addendum A3.2).
private struct OpenedStrataEntry: View {
    let entry: SavedAnky
    let onRecord: (String) -> Void
    let onShare: (String) -> Void

    var body: some View {
        // One disk read per open; the opened day re-renders rarely.
        let reflection = ReflectionStore().load(hash: entry.hash)?.reflection
        let hasReflection = !(reflection ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 0) {
            // The writing — ore (addendum A4).
            Text(entry.reconstructedText)
                .oreVoice()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

            if hasReflection, let reflection {
                // A quiet seam, then the reflection — glaze (retrofit in A4).
                Seam()
                    .padding(.vertical, 34)

                Text(reflection)
                    // Anky's reflection at rest — glaze (addendum A4).
                    .glazeVoice()
                    .frame(maxWidth: .infinity, alignment: .leading)

                OpenedEntryAffordances(
                    onRecord: { onRecord(reflection) },
                    onShare: { onShare(reflection) }
                )
                .padding(.top, 44)
            }
            // Clearance so the day's tail is never hidden behind the Anchor.
            Color.clear.frame(height: 40)
        }
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

/// The share / record affordances at the bottom of an opened, sent day
/// (addendum A2.5). Quiet, lowercase, in the lazure register; nothing floats.
private struct OpenedEntryAffordances: View {
    let onRecord: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 30) {
            affordance("share", action: onShare)
            affordance("record", action: onRecord)
        }
        .frame(maxWidth: .infinity)
    }

    private func affordance(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            Text(title)
                .font(.fraunces(15, weight: .regular, italic: true))
                .foregroundStyle(Color.ankyInkSoft)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
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
