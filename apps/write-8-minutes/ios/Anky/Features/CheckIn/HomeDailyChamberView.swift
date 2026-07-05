import SwiftUI

struct HomeDailyChamberView: View {
    let name: String
    let streak: Int
    let onCheckIn: () -> Void
    let onMap: () -> Void
    let onArchive: () -> Void
    let onArchiveDate: (Date) -> Void
    let onDeepWrite: () -> Void
    let onProfile: () -> Void

    @State private var latestReflection = ReflectionStore().list().first
    @State private var sessionDates = Set(
        SessionIndexStore().load().filter(\.isComplete).map {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
    )

    var body: some View {
        ZStack {
            CosmicBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HomeTopBar(
                        streak: streak,
                        initial: String(name.prefix(1)).uppercased(),
                        onProfile: onProfile
                    )
                    AnkyHeroHeader(name: name)
                    WeeklyCalendarStrip(
                        completedDates: sessionDates,
                        onSelectDate: onArchiveDate
                    )
                    PrimaryCheckInCard(action: onCheckIn)
                    LatestReflectionCard(reflection: latestReflection)
                    PortalRow(
                        onMap: onMap,
                        onArchive: onArchive,
                        onDeepWrite: onDeepWrite
                    )
                    PrivacyFooter()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            latestReflection = ReflectionStore().list().first
            sessionDates = Set(
                SessionIndexStore().load().filter(\.isComplete).map {
                    Calendar.current.startOfDay(for: $0.createdAt)
                }
            )
        }
    }
}

struct CosmicBackgroundView: View {
    var body: some View {
        LazureWall(mood: .dawn)
    }
}

struct HomeTopBar: View {
    // No streak counter anywhere in this app: days are told by the journey
    // map's lit tiles, in the product's own language.
    let streak: Int
    let initial: String
    let onProfile: () -> Void

    var body: some View {
        HStack {
            CircleIconButtonLabel(systemName: "sparkles", size: 48)

            Spacer()

            Button(action: onProfile) {
                Text(initial.isEmpty ? "J" : initial)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInk)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.ankyPaper.opacity(0.60)))
                    .overlay(Circle().stroke(HomePalette.border, lineWidth: 0.5))
                    .shadow(color: Color.ankyViolet.opacity(0.14), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AnkyHeroHeader: View {
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                HaloView()

                Image("check-in-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 146)
                    .offset(y: 57)
                    .clipShape(Circle())
                    .shadow(color: Color.ankyViolet.opacity(0.18), radius: 18, x: 0, y: 8)
            }
            .frame(height: 146)

            Text("Today is your day, \(name)")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(HomePalette.cream)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)
                .lineLimit(2)
        }
    }
}

private struct HaloView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ankyGold.opacity(0.30), lineWidth: 1)
                .frame(width: 182, height: 182)

            Circle()
                .stroke(Color.ankyViolet.opacity(0.12), lineWidth: 1)
                .frame(width: 150, height: 150)
        }
    }
}

struct WeeklyCalendarStrip: View {
    let completedDates: Set<Date>
    let onSelectDate: (Date) -> Void
    private let calendar = Calendar.current
    private let lookbackDays = 120

    private var days: [CalendarDay] {
        let today = calendar.startOfDay(for: Date())
        return stride(from: -lookbackDays, through: 0, by: 1).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            return CalendarDay(
                date: date,
                isSelected: offset == 0,
                isComplete: completedDates.contains(calendar.startOfDay(for: date))
            )
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(days) { day in
                        Button {
                            onSelectDate(day.date)
                        } label: {
                            CalendarDayView(day: day)
                        }
                        .buttonStyle(.plain)
                        .id(day.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.top, 2)
            .onAppear {
                if let todayID = days.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(todayID, anchor: .trailing)
                    }
                }
            }
        }
    }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let isSelected: Bool
    let isComplete: Bool
    var id: Date { date }
}

private struct CalendarDayView: View {
    let day: CalendarDay

    var body: some View {
        VStack(spacing: 8) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Color.ankyInkSoft)

            ZStack(alignment: .topTrailing) {
                Text(day.date.formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(day.isSelected ? HomePalette.cream : Color.ankyInkSoft)
                    .frame(width: 42, height: 42)
                    .background {
                        if day.isSelected {
                            Circle()
                                .stroke(Color.ankyViolet, lineWidth: 2)
                                .shadow(color: Color.ankyViolet.opacity(0.30), radius: 10)
                        }
                    }

                if day.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ankyPaper)
                        .frame(width: 22, height: 22)
                        .background(Color.ankyViolet)
                        .clipShape(Circle())
                        .offset(x: 5, y: -4)
                }
            }
        }
        .frame(width: 48)
        .contentShape(Rectangle())
    }
}

struct PrimaryCheckInCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                CircleIconButtonLabel(systemName: "sparkle", size: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Check in again")
                    .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("Write, Talk, Image or Deep Write")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.ankyViolet)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.ankyInk)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.ankyGoldLight, Color.ankyGold],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.ankyGold.opacity(0.35), radius: 12)
                    )
            }
            .padding(14)
            .frame(minHeight: 82)
            .glassCard(cornerRadius: 30)
        }
        .buttonStyle(.plain)
    }
}

struct LatestReflectionCard: View {
    let reflection: LocalReflection?

    private var quote: String {
        guard let reflection else {
            return """
            You are here.

            Start with what is alive today.
            """
        }

        let cleaned = reflection.reflection
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? reflection.title : cleaned
    }

    private var savedLabel: String {
        reflection == nil ? "Ready when you are" : "Saved just now"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Latest reflection", systemImage: "sparkle")
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(Color.ankyInk)

                Spacer()

                Text(savedLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ankyViolet)
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 10) {
                    Text("\"")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(Color.ankyViolet)

                    MarkdownPreviewText(quote)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(HomePalette.cream)
                        .lineLimit(4)
                        .minimumScaleFactor(0.74)

                    Spacer(minLength: 0)
                }

                Divider()
                    .background(Color.ankyInk.opacity(0.08))

                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(Color.ankyViolet)

                    Text("3:12")
                    Text("•")
                    Text(reflection?.createdAt.formatted(.dateTime.month(.abbreviated).day().year()) ?? Date().formatted(.dateTime.month(.abbreviated).day().year()))
                    Text("•")
                    Text(reflection?.createdAt.formatted(.dateTime.hour().minute()) ?? Date().formatted(.dateTime.hour().minute()))

                    Spacer()

                    Button { } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.ankyInkSoft)
                            .frame(width: 44, height: 44)
                            .background(Color.ankyInk.opacity(0.05))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.ankyInkSoft)
            }
            .padding(16)
            .glassCard(cornerRadius: 28)
        }
        .padding(14)
        .glassCard(cornerRadius: 32)
    }
}

struct PortalRow: View {
    let onMap: () -> Void
    let onArchive: () -> Void
    let onDeepWrite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PortalCard(
                title: "Map",
                subtitle: "Patterns Anky\nis noticing.",
                systemName: "point.3.connected.trianglepath.dotted",
                action: onMap
            )

            PortalCard(
                title: "Archive",
                subtitle: "Your past\nreflections.",
                systemName: "book.closed",
                action: onArchive
            )

            PortalCard(
                title: "Deep Write",
                subtitle: "8 minutes.\nNo distractions.",
                systemName: "hourglass",
                action: onDeepWrite
            )
        }
    }
}

struct PortalCard: View {
    let title: String
    let subtitle: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.ankyViolet)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.ankyViolet.opacity(0.10)))
                    .overlay(Circle().stroke(Color.ankyViolet.opacity(0.22), lineWidth: 1))

                Text(title)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(HomePalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ankyInkSoft)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ankyViolet)
                    .frame(width: 40, height: 40)
                    .background(Color.ankyInk.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .glassCard(cornerRadius: 26)
        }
        .buttonStyle(.plain)
    }
}

struct PrivacyFooter: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
            Text("Only you can see this.")
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.ankyViolet)
        .padding(.top, 2)
    }
}

struct InnerConstellationMapView: View {
    @StateObject private var viewModel = MapViewModel()

    var body: some View {
        ZStack {
            CosmicBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 42, weight: .regular))
                            .foregroundStyle(Color.ankyViolet)
                            .frame(width: 82, height: 82)
                            .background(Circle().fill(Color.ankyViolet.opacity(0.12)))
                            .overlay(Circle().stroke(Color.ankyViolet.opacity(0.30), lineWidth: 1))

                        Text("Inner constellation")
                            .font(.system(size: 38, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ankyInk)
                            .multilineTextAlignment(.center)

                        Text("A living summary of the patterns Anky is noticing from your check-ins.")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 18)
                    }
                    .padding(.top, 84)

                    HStack(spacing: 12) {
                        ConstellationMetric(value: "\(viewModel.completeAnkyCount)", label: "ankys")
                        ConstellationMetric(value: "\(viewModel.totalWritingMinutes)", label: "minutes")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Current pattern")
                            .font(.system(size: 23, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ankyInk)

                        Text(currentPatternText)
                            .font(.system(size: 25, weight: .regular, design: .serif))
                            .lineSpacing(7)
                            .foregroundStyle(Color.ankyInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                            .background(Color.ankyInk.opacity(0.08))

                        Text("The visual constellation will become richer as the reflection endpoint learns from raw write, talk, image, and deep write sessions.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.ankyInkSoft)
                            .lineSpacing(4)
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 28)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recent stars")
                            .font(.system(size: 23, weight: .regular, design: .serif))
                            .foregroundStyle(Color.ankyInk)

                        ForEach(viewModel.completeAnkySessions.prefix(4)) { session in
                            HStack(spacing: 12) {
                                Image(systemName: "sparkle")
                                    .foregroundStyle(Color.ankyViolet)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.ankyViolet.opacity(0.12)))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.reflectionTitle ?? session.preview)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.ankyInk)
                                        .lineLimit(1)
                                    Text(session.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
                                }
                                Spacer()
                            }
                        }

                        if viewModel.completeAnkySessions.isEmpty {
                            Text("No completed deep writes yet. Your constellation begins with the next honest check-in.")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.ankyInkSoft)
                                .lineSpacing(4)
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 28)

                    PrivacyFooter()
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var currentPatternText: String {
        if viewModel.completeAnkyCount == 0 {
            return "There is not enough signal yet. Start by checking in with what is alive."
        }
        if viewModel.currentStreak > 1 {
            return "You are building continuity. The shape is becoming easier to see because you keep returning."
        }
        return "There is a thread here. The archive holds it; the constellation is where it starts becoming pattern."
    }
}

private struct ConstellationMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInk)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.ankyInkSoft)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .glassCard(cornerRadius: 22)
    }
}

struct ArchiveChamberView: View {
    let selectedDate: Date?
    let onOpenAnky: (SavedAnky) -> Void
    let onBack: (() -> Void)?

    @State private var ankys = LocalAnkyArchive().list()
    @State private var searchableText: [String: String] = [:]
    @State private var dateFilter: Date?
    @State private var searchQuery = ""

    init(
        selectedDate: Date? = nil,
        onOpenAnky: @escaping (SavedAnky) -> Void = { _ in },
        onBack: (() -> Void)? = nil
    ) {
        self.selectedDate = selectedDate
        self.onOpenAnky = onOpenAnky
        self.onBack = onBack
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

                    AnkySunGlyph(size: 20, color: .ankyGold)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.ankyGold.opacity(0.14)))
                }
                .padding(.horizontal, 20)
                .padding(.top, 68)
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
                                        ArchiveListRow(anky: anky)
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
            return "Nothing you've written contains that yet."
        }
        if dateFilter != nil {
            return "Nothing written on this day."
        }
        return "What you write collects here."
    }

    private func reload() {
        let loaded = LocalAnkyArchive().list()
        ankys = loaded
        // Reconstructing text is not free — do it once per load, not on
        // every keystroke of the search field.
        searchableText = Dictionary(
            uniqueKeysWithValues: loaded.map {
                ($0.hash, $0.reconstructedText.lowercased())
            }
        )
    }
}

/// One archived writing, matching the design: sigil in a soft gold
/// circle, two lines of the words themselves, the time underneath,
/// and the session length with a chevron on the right.
private struct ArchiveListRow: View {
    let anky: SavedAnky

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("AnkySigil")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.ankyGold.opacity(0.14)))

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
