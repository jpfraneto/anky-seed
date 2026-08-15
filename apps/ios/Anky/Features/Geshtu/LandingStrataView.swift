//
//  LandingStrataView.swift
//  Anky — the landing surface: everything "outside the writing."
//
//  The great simplification (user decision, 2026-08-04): the past is a plain
//  list, like a notes app. A search bar on top, the writings raw beneath it —
//  full presence regardless of age — and the Anchor at the base to write
//  again. Tapping a day pushes a dedicated reading page, and the standard
//  navigation edge swipe returns to the list.
//
import SwiftUI

struct LandingStrataView: View {
    @ObservedObject var axis: GeshtuState
    var onRequestReflection: (SavedAnky) -> Void = { _ in }

    /// The days, newest first. Loaded from the local archive — the same store
    /// the writing session seals into.
    @State private var entries: [SavedAnky] = []
    @State private var searchText = ""
    @State private var path: [SavedAnky] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationDestination(for: SavedAnky.self) { entry in
                entryPage(entry)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            reload()
            syncPath(to: axis.openedEntry)
        }
        // A day just settled into the list: the archive already holds it —
        // re-read so the newest entry is standing when the device recedes.
        .onChange(of: axis.phase) { phase in
            if phase == .landing { reload() }
        }
        .onChange(of: axis.openedEntry) { entry in
            syncPath(to: entry)
        }
        .onChange(of: path) { newPath in
            if let entry = newPath.last {
                if axis.openedEntry?.id != entry.id { axis.openEntry(entry) }
            } else if axis.openedEntry != nil {
                axis.closeEntry()
            }
        }
        #if DEBUG
        .onChange(of: axis.debugReloadTick) { _ in reload() }
        #endif
    }

    // MARK: - The list

    private var filteredEntries: [SavedAnky] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.reconstructedText.localizedCaseInsensitiveContains(needle)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            searchBar
            ScrollView(.vertical) {
                StrataColumn(axis: axis, entries: filteredEntries)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.ankyInkSoft)
            TextField("search", text: $searchText)
                .font(.fraunces(16, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ankyInkSoft)
                }
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.ankyPaperDeep.opacity(0.6))
        )
        .padding(.leading, 20)
        // Clear the fixed top chrome riding the trailing edge.
        .padding(.trailing, 64)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - Empty state (day one)

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("nothing here yet")
                .font(.fraunces(19, weight: .light))
                .foregroundStyle(Color.ankyInkSoft)
            Spacer()
            // Clearance for the Anchor at the base.
            Color.clear.frame(height: 200)
        }
    }

    private func reload() {
        entries = LocalAnkyArchive().list()
    }

    private func syncPath(to entry: SavedAnky?) {
        let desired = entry.map { [$0] } ?? []
        if path != desired { path = desired }
    }

    private func entryPage(_ entry: SavedAnky) -> some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            ArchivedFinishedSessionView(
                artifact: entry,
                axis: axis,
                onLateOffer: ReflectionStore().load(hash: entry.hash) == nil ? {
                    AnkyHaptics.medium()
                    onRequestReflection(entry)
                } : nil
            )
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            if axis.openedEntry?.id != entry.id { axis.openEntry(entry) }
        }
    }

}

// MARK: - The column (shared by the landing and the reflection settle)

/// The sediment column itself, without a scroll view of its own, so it can be
/// embedded beneath the reflection in one continuous scroll (spec §7).
///
/// Rows stay compact here. Opening one updates the shared route; the landing
/// NavigationStack observes it and pushes the dedicated reading page.
struct StrataColumn: View {
    @ObservedObject var axis: GeshtuState
    let entries: [SavedAnky]

    /// The living edge — the scroll target for surfacing-to-now (addendum A1).
    static let topID = "axis.strata.top"

    /// The grey geshtu at an open day's base — the scroll target the gravity
    /// pull travels to.
    static let lateOfferID = "axis.strata.lateOffer"

    var body: some View {
        LazyVStack(spacing: 0) {
            // A little breath before the newest day.
            Color.clear.frame(height: 8)
                .id(Self.topID)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider()
                        .overlay(Color.ankyInkSoft.opacity(0.18))
                }
                StrataEntryRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AnkyHaptics.selection()
                        axis.openEntry(entry)
                    }
            }

            // Clearance so the last entry never hides behind the Anchor.
            Color.clear.frame(height: 180)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
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

// MARK: - A single row

/// One writing in the list, notes-app plain: the first line, then the date
/// and a snippet beneath. Full presence regardless of age. Tapping opens it
/// to read in full — handled by the parent.
private struct StrataEntryRow: View {
    let entry: SavedAnky

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(firstLine)
                .font(.fraunces(17, weight: .semibold))
                .foregroundStyle(Color.ankyInk)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 8) {
                Text(dateLine)
                    .font(.fraunces(13, weight: .light))
                    .foregroundStyle(Color.ankyInkSoft)
                Text(snippet)
                    .font(.fraunces(13, weight: .light))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
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

    /// What follows the first line, flattened to one quiet preview line.
    private var snippet: String {
        let lines = entry.reconstructedText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " ")
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
