//
//  LandingStrataView.swift
//  Anky — the Axis Redesign (spec §7).
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
    @ObservedObject var axis: AxisState

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
    }

    // MARK: - The strata column

    private var strata: some View {
        ScrollView(.vertical, showsIndicators: false) {
            StrataColumn(axis: axis, entries: entries)
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
    }
}

// MARK: - The column (shared by the landing and the reflection settle)

/// The sediment column itself, without a scroll view of its own, so it can be
/// embedded beneath the reflection in one continuous scroll (spec §7).
struct StrataColumn: View {
    @ObservedObject var axis: AxisState
    let entries: [SavedAnky]

    var body: some View {
        VStack(spacing: 34) {
            // A little breath before the newest day.
            Color.clear.frame(height: 24)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                StrataEntryRow(entry: entry, ageOpacity: Self.ageOpacity(for: index))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AnkyHaptics.selection()
                        axis.openEntry(entry)
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
    }

    /// Entries grow fainter with age (spec §7). Newest is full presence; the
    /// column sinks toward the pigment. Floored so the oldest is still faintly
    /// legible, never fully gone.
    static func ageOpacity(for index: Int) -> Double {
        let step = 0.11
        return max(0.16, 1.0 - Double(index) * step)
    }
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

// MARK: - Opened entry (read in full)

/// A past day brightened back to full presence and opened to read (spec §7).
/// Phase 2 is the plain read; the copy / share-card / record affordances of
/// RevealView graft on here in a later phase (spec §12).
struct AxisEntryReadView: View {
    let entry: SavedAnky

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text(dateLine)
                    .font(.fraunces(13, weight: .light))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)

                Text(entry.reconstructedText)
                    .font(.fraunces(19, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dateLine: String {
        AxisEntryReadView.dateFormatter.string(from: entry.createdAt).lowercased()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMMM yyyy"
        return f
    }()
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
