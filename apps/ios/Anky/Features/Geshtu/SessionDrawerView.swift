//
//  SessionDrawerView.swift
//  Anky — the drawer: everything "beside the writing."
//
//  One-surface shell (user decision, 2026-10-08): the page in front is always
//  the writing or one written session, and the history slides in from the
//  leading edge like the drawer of a chat app. Anky and search on the top
//  line, Settings and Stats beneath, then Recents — every written session,
//  newest first. Choosing one puts it on the page; nothing is pushed.
//
import SwiftUI
import UIKit

struct SessionDrawerView: View {
    @ObservedObject var axis: GeshtuState
    /// The session standing on the page, if the page is a session.
    let currentHash: String?
    let onNewWriting: () -> Void

    /// The sessions, newest first. Loaded from the local archive — the same
    /// store the writing session seals into.
    @State private var entries: [SavedAnky] = []
    /// Reflection titles by session hash; a session Anky has answered is
    /// listed by the name that answer gave it.
    @State private var titles: [String: String] = [:]
    @State private var searchText = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !isSearching {
                        destinationRow(icon: "gearshape", label: "Settings") {
                            axis.settingsIsOpen = true
                        }
                        destinationRow(icon: "chart.bar", label: "Stats") {
                            axis.statsIsOpen = true
                        }

                        Text(AnkyLocalization.ui("Recents"))
                            .font(.fraunces(14, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                            .padding(.horizontal, 24)
                            .padding(.top, 22)
                            .padding(.bottom, 8)
                    }

                    if filteredEntries.isEmpty {
                        Text(AnkyLocalization.ui(entries.isEmpty ? "nothing here yet" : "nothing found"))
                            .font(.fraunces(15, weight: .light, italic: true))
                            .foregroundStyle(Color.ankyInkSoft)
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                    }

                    ForEach(filteredEntries) { entry in
                        SessionDrawerRow(
                            title: titles[entry.hash] ?? Self.firstLine(of: entry),
                            date: entry.createdAt,
                            isCurrent: entry.hash == currentHash
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { open(entry) }
                    }

                    // Clearance so the last session never hides behind the
                    // floating new-writing button.
                    Color.clear.frame(height: 110)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if !isSearching {
                newWritingButton
                    .padding(.trailing, 18)
                    .padding(.bottom, 10)
            }
        }
        .onAppear(perform: reload)
        // A sealed or deleted session changes the list; re-read whenever the
        // page changes and whenever the drawer is about to be looked at.
        .onChange(of: axis.phase) { _ in reload() }
        .onChange(of: axis.drawerIsOpen) { isOpen in
            if isOpen {
                reload()
            } else {
                endSearch()
            }
        }
    }

    // MARK: - The top line

    private var header: some View {
        HStack(spacing: 10) {
            if isSearching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.ankyInkSoft)
                    TextField(AnkyLocalization.ui("search"), text: $searchText)
                        .font(.fraunces(17, weight: .regular))
                        .foregroundStyle(Color.ankyInk)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .ankyGlass(in: Capsule(), interactive: false)

                glassButton(systemName: "xmark", label: "Close search") {
                    withAnimation(.easeInOut(duration: 0.2)) { endSearch() }
                }
            } else {
                Text("Anky")
                    .font(.fraunces(30, weight: .regular))
                    .foregroundStyle(Color.ankyInk)

                Spacer(minLength: 0)

                glassButton(systemName: "magnifyingglass", label: "Search") {
                    withAnimation(.easeInOut(duration: 0.2)) { isSearching = true }
                    searchFocused = true
                }
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func glassButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ankyInk)
                .frame(width: 44, height: 44)
                .ankyGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(AnkyLocalization.ui(label)))
    }

    // MARK: - Rows

    private func destinationRow(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AnkyHaptics.light()
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .frame(width: 26)
                Text(AnkyLocalization.ui(label))
                    .font(.fraunces(19, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newWritingButton: some View {
        Button {
            AnkyHaptics.light()
            onNewWriting()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text(AnkyLocalization.ui("New writing"))
                    .font(.fraunces(16, weight: .regular))
            }
            .foregroundStyle(Color.ankyInk)
            .padding(.horizontal, 20)
            .frame(height: 50)
            .ankyGlass(in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private var filteredEntries: [SavedAnky] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.reconstructedText.localizedCaseInsensitiveContains(needle)
                || (titles[$0.hash]?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    private func open(_ entry: SavedAnky) {
        AnkyHaptics.light()
        if entry.hash != currentHash {
            axis.openEntry(entry)
        }
        axis.closeDrawer()
    }

    private func endSearch() {
        searchFocused = false
        isSearching = false
        searchText = ""
    }

    private func reload() {
        entries = LocalAnkyArchive().list()
        titles = SessionIndexStore().load().reduce(into: [:]) { result, summary in
            if let title = summary.reflectionTitle, !title.isEmpty {
                result[summary.hash] = title
            }
        }
    }

    private static func firstLine(of entry: SavedAnky) -> String {
        for line in entry.reconstructedText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "—"
    }
}

// MARK: - A single session

/// One written session in Recents: its name on one line, the day beneath.
private struct SessionDrawerRow: View {
    let title: String
    let date: Date
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.fraunces(18, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(Self.dateFormatter.string(from: date).lowercased())
                .font(.fraunces(12, weight: .light))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.ankyInk.opacity(0.07))
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy · HH:mm"
        return f
    }()
}

// MARK: - Stats

/// What the archive adds up to. Everything here is counted on the device from
/// the sealed sessions themselves — nothing is fetched.
///
/// Read top to bottom: the streak standing now, the month it stands in, then
/// the totals.
struct WritingStatsView: View {
    @State private var stats = WritingStats.empty

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                Text(AnkyLocalization.ui("Stats"))
                    .font(.fraunces(30, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .padding(.top, 34)

                HStack(alignment: .lastTextBaseline) {
                    figure("\(stats.currentStreak)", "day streak", size: 76)
                    Spacer(minLength: 16)
                    figure("\(stats.longestStreak)", "longest streak", size: 26, alignment: .trailing)
                }

                WritingCalendar(writtenDays: stats.writtenDays, completeDays: stats.completeDays)

                VStack(spacing: 0) {
                    totalsRow(
                        ("\(stats.sessions)", "writings"),
                        ("\(stats.completeAnkys)", "full ankys")
                    )
                    hairline
                    totalsRow(
                        (stats.totalTimeText, "time written"),
                        ("\(stats.daysWritten)", "days written")
                    )
                    hairline
                    totalsRow(
                        (stats.words.formatted(), "words"),
                        ("\(stats.wordsPerMinute)", "words per minute")
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.ankyPaperDeep.opacity(0.6))
                )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ankyPaper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
        .onAppear { stats = WritingStats(sessions: LocalAnkyArchive().list()) }
    }

    private func figure(
        _ value: String,
        _ label: String,
        size: CGFloat,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: size > 40 ? 0 : 4) {
            Text(value)
                .font(.fraunces(size, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(AnkyLocalization.ui(label))
                .font(.fraunces(13, weight: .light))
                .foregroundStyle(Color.ankyInkSoft)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func totalsRow(_ leading: (String, String), _ trailing: (String, String)) -> some View {
        HStack(spacing: 0) {
            figure(leading.0, leading.1, size: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            Rectangle()
                .fill(Color.ankyInk.opacity(0.08))
                .frame(width: 0.5)
            figure(trailing.0, trailing.1, size: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.ankyInk.opacity(0.08))
            .frame(height: 0.5)
    }
}

/// A month on the wall: every day by its number, the days with writing
/// marked, the days with a full anky filled. Today wears a ring. The arrows
/// walk back as far as the first writing.
private struct WritingCalendar: View {
    let writtenDays: Set<Date>
    let completeDays: Set<Date>

    /// Months back from the current one; never positive.
    @State private var monthOffset = 0

    private let calendar = Calendar.current
    private static let writtenInk = 0.14
    private static let daySize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                Text(monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(.fraunces(17, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                Spacer(minLength: 8)
                stepButton("chevron.left", by: -1, enabled: monthOffset > earliestOffset)
                stepButton("chevron.right", by: 1, enabled: monthOffset < 0)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.fraunces(11, weight: .light))
                        .foregroundStyle(Color.ankyInkSoft)
                        .frame(height: 18)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: Self.daySize + 6)
                    }
                }
            }

            HStack(spacing: 16) {
                legend(Color.ankyInk.opacity(Self.writtenInk), "written")
                legend(Color.ankyInk, "full anky")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.ankyPaperDeep.opacity(0.6))
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let isComplete = completeDays.contains(day)
        let isWritten = writtenDays.contains(day)
        let isAhead = day > today
        return Text("\(calendar.component(.day, from: day))")
            .font(.fraunces(15, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(
                isComplete
                    ? Color.ankyPaper
                    : (isWritten ? Color.ankyInk : Color.ankyInkSoft.opacity(isAhead ? 0.35 : 0.8))
            )
            .frame(width: Self.daySize, height: Self.daySize)
            .background {
                Circle().fill(
                    isComplete
                        ? Color.ankyInk
                        : (isWritten ? Color.ankyInk.opacity(Self.writtenInk) : Color.clear)
                )
            }
            .overlay {
                if day == today {
                    Circle()
                        .strokeBorder(Color.ankyInk, lineWidth: 1)
                        .padding(isComplete ? -3 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.daySize + 6)
    }

    private func stepButton(_ systemName: String, by step: Int, enabled: Bool) -> some View {
        Button {
            AnkyHaptics.selection()
            monthOffset += step
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ankyInk.opacity(enabled ? 1 : 0.2))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(AnkyLocalization.ui(label))
                .font(.fraunces(12, weight: .light))
                .foregroundStyle(Color.ankyInkSoft)
        }
    }

    // MARK: Days

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private var monthStart: Date {
        let current = startOfMonth(today)
        return calendar.date(byAdding: .month, value: monthOffset, to: current) ?? current
    }

    /// The month of the first writing, as an offset from this one.
    private var earliestOffset: Int {
        guard let first = writtenDays.min() else { return 0 }
        let months = calendar.dateComponents([.month], from: startOfMonth(first), to: startOfMonth(today)).month ?? 0
        return min(0, -months)
    }

    /// The month laid out in weeks; nil for the blanks before its first day.
    private var cells: [Date?] {
        let start = monthStart
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let days: [Date?] = (0..<count).map { index in
            calendar.date(byAdding: .day, value: index, to: start).map { calendar.startOfDay(for: $0) }
        }
        return Array(repeating: nil, count: lead) + days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

struct WritingStats: Equatable {
    var sessions = 0
    var completeAnkys = 0
    var words = 0
    var totalMs: Int64 = 0
    var daysWritten = 0
    var currentStreak = 0
    var longestStreak = 0
    /// The days with any writing, and those among them that hold a full
    /// anky — each as the start of its day.
    var writtenDays: Set<Date> = []
    var completeDays: Set<Date> = []

    static let empty = WritingStats()

    init() {}

    init(sessions list: [SavedAnky], now: Date = Date(), calendar: Calendar = .current) {
        sessions = list.count
        completeAnkys = list.filter(\.isComplete).count
        words = list.reduce(0) {
            $0 + $1.reconstructedText.split { $0.isWhitespace || $0.isNewline }.count
        }
        totalMs = list.reduce(0) { $0 + $1.durationMs }

        for session in list {
            let day = calendar.startOfDay(for: session.createdAt)
            writtenDays.insert(day)
            if session.isComplete {
                completeDays.insert(day)
            }
        }
        let days = writtenDays
        daysWritten = days.count

        // Longest run of consecutive days anywhere in the archive.
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous,
               let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            longestStreak = max(longestStreak, run)
            previous = day
        }

        // The current run still stands until a whole day passes unwritten:
        // it may end today or yesterday.
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        while days.contains(cursor) {
            currentStreak += 1
            guard let earlier = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = earlier
        }
    }

    var wordsPerMinute: Int {
        guard totalMs > 0 else { return 0 }
        return Int((Double(words) / (Double(totalMs) / 60_000)).rounded())
    }

    var totalTimeText: String {
        let minutes = Int(totalMs / 60_000)
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
