import SwiftUI

// Dead legacy surfaces removed 2026-07-08 (perf pass): HomeDailyChamberView,
// HomeTopBar, AnkyHeroHeader, WeeklyCalendarStrip, PrimaryCheckInCard,
// LatestReflectionCard, PortalRow/PortalCard, PrivacyFooter,
// InnerConstellationMapView — none were reachable from AppRoot anymore.

struct CosmicBackgroundView: View {
    var body: some View {
        LazureWall(mood: .dawn)
    }
}


struct ArchiveChamberView: View {
    let selectedDate: Date?
    let onOpenAnky: (SavedAnky) -> Void
    let onBack: (() -> Void)?
    /// True when an `InteractiveBackSwipeContainer` above owns the
    /// finger-tracked back-swipe.
    let handlesBackSwipeExternally: Bool

    @State private var ankys = LocalAnkyArchive().list()
    @State private var searchableText: [String: String] = [:]
    @State private var levelByHash: [String: Int] = [:]
    @State private var dateFilter: Date?
    @State private var searchQuery = ""
    @State private var showsStats = false

    init(
        selectedDate: Date? = nil,
        onOpenAnky: @escaping (SavedAnky) -> Void = { _ in },
        onBack: (() -> Void)? = nil,
        handlesBackSwipeExternally: Bool = false
    ) {
        self.selectedDate = selectedDate
        self.onOpenAnky = onOpenAnky
        self.onBack = onBack
        self.handlesBackSwipeExternally = handlesBackSwipeExternally
        _dateFilter = State(initialValue: selectedDate)
    }

    private var visibleAnkys: [SavedAnky] {
        var visible = ankys
        if let dateFilter {
            visible = visible.filter {
                Calendar.current.isDate($0.createdAt, inSameDayAs: dateFilter)
            }
        }
        let query = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !query.isEmpty {
            visible = visible.filter {
                searchableText[$0.hash]?.contains(query) == true
            }
        }
        return visible
    }

    /// The visible writings, newest first, bucketed by local day —
    /// "Today", "Yesterday", then dated headers, as in the design.
    private var daySections: [(title: String, ankys: [SavedAnky])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [SavedAnky]] = [:]
        for anky in visibleAnkys {
            let day = calendar.startOfDay(for: anky.createdAt)
            if buckets[day] == nil {
                order.append(day)
            }
            buckets[day, default: []].append(anky)
        }
        return order.map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = "Today"
            } else if calendar.isDateInYesterday(day) {
                title = "Yesterday"
            } else {
                title = day.formatted(.dateTime.month(.abbreviated).day().year())
            }
            return (title, buckets[day] ?? [])
        }
    }

    var body: some View {
        ZStack {
            CosmicBackgroundView()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Color.ankyInk)
                                .frame(width: 38, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AnkyLocalization.ui("Back to today"))
                        .padding(.leading, -10)
                    }

                    Text(AnkyLocalization.ui("Your Writings"))
                        .font(.system(size: 36, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer()

                    Button {
                        showsStats = true
                    } label: {
                        AnkySunGlyph(size: 20, color: .ankyGold)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.ankyGold.opacity(0.14)))
                            .overlay(Circle().stroke(Color.ankyGold.opacity(0.30), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AnkyLocalization.ui("Your writing stats"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                if dateFilter != nil {
                    Button {
                        dateFilter = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                            Text(dateFilter?.formatted(.dateTime.month(.wide).day().year()) ?? "")
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ankyViolet)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }

                if visibleAnkys.isEmpty {
                    Spacer()
                    Text(emptyLine)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(daySections, id: \.title) { section in
                                Text(AnkyLocalization.ui(section.title))
                                    .font(.system(size: 21, weight: .regular, design: .serif))
                                    .foregroundStyle(Color.ankyInkSoft)
                                    .padding(.top, 22)
                                    .padding(.bottom, 4)

                                ForEach(Array(section.ankys.enumerated()), id: \.element.id) { index, anky in
                                    Button {
                                        onOpenAnky(anky)
                                    } label: {
                                        ArchiveListRow(
                                            anky: anky,
                                            levelArt: SessionLevelArt.thumbnail(forLevel: levelByHash[anky.hash] ?? 1)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if index < section.ankys.count - 1 {
                                        Divider()
                                            .background(Color.ankyInk.opacity(0.08))
                                            .padding(.leading, 68)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            reload()
        }
        .onChange(of: selectedDate) { newValue in
            dateFilter = newValue
            reload()
        }
        .sheet(isPresented: $showsStats) {
            WritingStatsSheet(makeExportURL: makeWritingExportURL)
        }
        // The native back gesture: a swipe in from the left edge leaves the
        // archive the same way the chevron does. Inert when a parent
        // interactive container owns the swipe.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard !handlesBackSwipeExternally else {
                        return
                    }
                    let isHorizontalBackSwipe = value.translation.width > 80
                        && value.startLocation.x < 44
                        && abs(value.translation.height) < 60
                    if isHorizontalBackSwipe, let onBack {
                        onBack()
                    }
                }
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.ankyInkSoft.opacity(0.8))

            TextField(AnkyLocalization.ui("Search"), text: $searchQuery)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassCard(cornerRadius: 14)
    }

    private var emptyLine: String {
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return AnkyLocalization.ui("Nothing you've written contains that yet.")
        }
        if dateFilter != nil {
            return AnkyLocalization.ui("Nothing written on this day.")
        }
        return AnkyLocalization.ui("What you write collects here.")
    }

    private func reload() {
        let loaded = LocalAnkyArchive().list()
        ankys = loaded
        levelByHash = SessionLevelArt.levels(forArtifacts: loaded)
        // Reconstructing text is not free — do it once per load, not on
        // every keystroke of the search field.
        searchableText = Dictionary(
            uniqueKeysWithValues: loaded.map {
                ($0.hash, $0.reconstructedText.lowercased())
            }
        )
    }

    private func makeWritingExportURL() -> URL? {
        let all = ankys.sorted { $0.createdAt > $1.createdAt }
        guard !all.isEmpty else { return nil }
        let body = all.map { anky in
            let date = anky.createdAt.formatted(.dateTime.year().month(.wide).day().hour().minute())
            let writing = anky.reconstructedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(date)\n\n\(writing)"
        }
        .joined(separator: "\n\n----\n\n")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anky-writings-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// The sun's chamber: a quiet summary of the whole practice, with the
/// export door at the bottom.
private struct WritingStatsSheet: View {
    let makeExportURL: () -> URL?
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [SessionSummary] = []
    @State private var exportURL: URL?

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        AnkySunGlyph(size: 26, color: .ankyGold)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ankyInkSoft)
                                .frame(width: 34, height: 34)
                                .background(Color.ankyPaper.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AnkyLocalization.ui("Close"))
                    }

                    Text(AnkyLocalization.ui("Your practice"))
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        WritingStatTile(value: "\(sessions.count)", label: AnkyLocalization.ui("writings"))
                        WritingStatTile(value: totalTimeText, label: AnkyLocalization.ui("time written"))
                        WritingStatTile(value: "\(totalWords)", label: AnkyLocalization.ui("words"))
                        WritingStatTile(value: "\(distinctDayCount)", label: AnkyLocalization.ui("days with writing"))
                        WritingStatTile(value: "\(currentStreak)", label: AnkyLocalization.ui("day streak"))
                        WritingStatTile(value: longestSessionText, label: AnkyLocalization.ui("longest session"))
                    }

                    AnkyPrimaryButton(
                        "Export all writings",
                        systemImage: "square.and.arrow.up"
                    ) {
                        exportURL = makeExportURL()
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        // One detent, tall enough for everything: the stats and the export
        // door are all visible the moment the sheet opens — no scrolling.
        .presentationDetents([.large])
        .onAppear {
            sessions = SessionIndexStore().load()
        }
        .sheet(
            isPresented: Binding(
                get: { exportURL != nil },
                set: { isPresented in
                    if !isPresented {
                        exportURL = nil
                    }
                }
            )
        ) {
            if let exportURL {
                ActivityShareSheet(items: [exportURL])
            }
        }
    }

    private var totalTimeText: String {
        let totalSeconds = sessions.reduce(Int64(0)) { $0 + $1.durationMs } / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var totalWords: Int {
        sessions.reduce(0) { $0 + $1.wordCount }
    }

    private var writingDays: Set<Date> {
        Set(sessions.map { Calendar.current.startOfDay(for: $0.createdAt) })
    }

    private var distinctDayCount: Int {
        writingDays.count
    }

    /// Consecutive days with writing, counting back from today — or from
    /// yesterday, so an unwritten morning doesn't read as a broken streak.
    private var currentStreak: Int {
        let calendar = Calendar.current
        let days = writingDays
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }
        return streak
    }

    private var longestSessionText: String {
        AnkyDuration.clock(sessions.map(\.durationMs).max() ?? 0)
    }
}

private struct WritingStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ankyInkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .glassCard(cornerRadius: 22)
    }
}

/// One archived writing: the painting anky was working on at the time of
/// that writing, two lines of the words themselves, the time underneath,
/// and the session length with a chevron on the right.
private struct ArchiveListRow: View {
    let anky: SavedAnky
    let levelArt: UIImage?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let levelArt {
                    Image(uiImage: levelArt)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.ankyGold.opacity(0.28), lineWidth: 0.7))
                } else {
                    Image("AnkySigil")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color.ankyGold.opacity(0.14)))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(preview)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInk)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(anky.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.9))
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                Text(AnkyDuration.clock(anky.durationMs))
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInk.opacity(0.85))
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft.opacity(0.7))
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var preview: String {
        let text = anky.reconstructedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return text.isEmpty ? "···" : text
    }
}

private struct MarkdownPreviewText: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}

private struct CircleIconButtonLabel: View {
    let systemName: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(HomePalette.cream)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.ankyPaper.opacity(0.60)))
            .overlay(Circle().stroke(HomePalette.border, lineWidth: 0.5))
            .shadow(color: Color.ankyViolet.opacity(0.14), radius: 16, y: 6)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.ankyPaper.opacity(0.78),
                            Color.ankyPaperDeep.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.28))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.ankyViolet.opacity(0.14), radius: 16, x: 0, y: 6)
    }
}

private enum HomePalette {
    static let cream = Color.ankyInk
    static let border = Color.ankyInk.opacity(0.10)
}
