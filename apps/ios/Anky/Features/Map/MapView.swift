import SwiftUI
import UIKit

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()
    @Binding private var revealAfterWriting: SavedAnky?
    @State private var path: [MapRoute] = []
    private let onTryAgain: () -> Void
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(
        revealAfterWriting: Binding<SavedAnky?> = .constant(nil),
        onTryAgain: @escaping () -> Void = {}
    ) {
        _revealAfterWriting = revealAfterWriting
        self.onTryAgain = onTryAgain
    }

    var body: some View {
        NavigationStack(path: $path) {
            TrailMapView(
                days: viewModel.spatialDays,
                todayDate: viewModel.todayDate
            ) { day in
                path.append(.day(day))
            }
            .navigationDestination(for: MapRoute.self) { route in
                switch route {
                case .day(let day):
                    DayDetailView(day: viewModel.day(for: day.date) ?? day)
                case .session(let summary):
                    if let artifact = viewModel.artifact(for: summary) {
                        RevealView(
                            viewModel: RevealViewModel(artifact: artifact),
                            onDeleted: viewModel.refresh,
                            onTryAgain: tryAgain
                        )
                    } else {
                        ContentUnavailableView("Anky not found", systemImage: "doc.badge.questionmark")
                    }
                case .reveal(let artifact):
                    RevealView(
                        viewModel: RevealViewModel(artifact: artifact),
                        onDeleted: viewModel.refresh,
                        onTryAgain: tryAgain
                    )
                }
            }
            .onAppear {
                viewModel.refresh()
                openPendingRevealIfNeeded()
            }
            .onChange(of: revealAfterWriting) { _, _ in
                openPendingRevealIfNeeded()
            }
            .onReceive(refreshTimer) { _ in
                viewModel.refresh()
            }
        }
    }

    private func openPendingRevealIfNeeded() {
        guard let artifact = revealAfterWriting else {
            return
        }

        viewModel.refresh()
        path = [.reveal(artifact)]
        revealAfterWriting = nil
    }

    private func tryAgain() {
        path.removeAll()
        onTryAgain()
    }
}

private enum MapRoute: Hashable {
    case day(SessionDay)
    case session(SessionSummary)
    case reveal(SavedAnky)
}

private struct TrailMapView: View {
    let days: [SessionDay]
    let todayDate: Date
    let openDay: (SessionDay) -> Void

    @State private var centeredDayID: Date?
    @State private var todayY: CGFloat?

    private let rowHeight: CGFloat = 104
    private var displayDays: [SessionDay] {
        days.reversed()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            StraightTimeline(dayCount: displayDays.count, rowHeight: rowHeight)
                                .allowsHitTesting(false)

                            VStack(spacing: 0) {
                                ForEach(Array(displayDays.enumerated()), id: \.element.id) { index, day in
                                    TrailDayNode(
                                        day: day,
                                        index: index,
                                        rowHeight: rowHeight,
                                        openDay: openDay
                                    )
                                    .id(day.id)
                                    .background(
                                        GeometryReader { nodeGeometry in
                                            Color.clear.preference(
                                                key: DayCenterPreferenceKey.self,
                                                value: [day.id: nodeGeometry.frame(in: .named("trailViewport")).midY]
                                            )
                                        }
                                    )
                                }
                            }
                        }
                        .frame(minHeight: geometry.size.height)
                        .padding(.vertical, 48)
                    }
                    .background(trailBackground)
                    .coordinateSpace(name: "trailViewport")
                    .onPreferenceChange(DayCenterPreferenceKey.self) { centers in
                        updateCenteredDay(centers: centers, viewportHeight: geometry.size.height)
                    }
                    .onAppear {
                        focusToday(with: proxy)
                    }
                    .onChange(of: todayDate) { _, _ in
                        focusToday(with: proxy)
                    }
                    .onChange(of: days.count) { _, _ in
                        focusToday(with: proxy)
                    }

                    if shouldShowCurrentDayButton(viewportHeight: geometry.size.height) {
                        Button {
                            focusToday(with: proxy)
                        } label: {
                            Image(systemName: currentDayButtonIcon(viewportHeight: geometry.size.height))
                                .font(.title2.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 48, height: 48)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to current day")
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                    }
                }
            }
        }
    }

    private var trailBackground: some View {
        ZStack {
            Image("map-background")
                .resizable()
                .scaledToFill()

            Color.black.opacity(0.18)
        }
        .ignoresSafeArea()
    }

    private func updateCenteredDay(centers: [Date: CGFloat], viewportHeight: CGFloat) {
        guard !centers.isEmpty else {
            return
        }

        todayY = centers[todayDate]
        let viewportCenter = viewportHeight / 2
        centeredDayID = centers.min { left, right in
            abs(left.value - viewportCenter) < abs(right.value - viewportCenter)
        }?.key
    }

    private func focusToday(with proxy: ScrollViewProxy) {
        guard displayDays.contains(where: { $0.id == todayDate }) else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.45)) {
                proxy.scrollTo(todayDate, anchor: .center)
            }
            centeredDayID = todayDate
        }
    }

    private func shouldShowCurrentDayButton(viewportHeight: CGFloat) -> Bool {
        guard let todayY else {
            return false
        }

        return todayY < -rowHeight / 2 || todayY > viewportHeight + rowHeight / 2
    }

    private func currentDayButtonIcon(viewportHeight: CGFloat) -> String {
        guard let todayY else {
            return "arrow.down.circle.fill"
        }
        return todayY < viewportHeight / 2 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }
}

private struct StraightTimeline: View {
    let dayCount: Int
    let rowHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard dayCount > 0 else {
                    return
                }

                let x = size.width / 2
                var path = Path()
                path.move(to: CGPoint(x: x, y: rowHeight / 2))
                path.addLine(to: CGPoint(x: x, y: rowHeight * CGFloat(dayCount - 1) + rowHeight / 2))

                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.13)),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(height: rowHeight * CGFloat(max(dayCount, 1)))
        }
        .frame(height: rowHeight * CGFloat(max(dayCount, 1)))
    }
}

private struct TrailDayNode: View {
    let day: SessionDay
    let index: Int
    let rowHeight: CGFloat
    let openDay: (SessionDay) -> Void

    var body: some View {
        GeometryReader { geometry in
            Button {
                openDay(day)
            } label: {
                ZStack {
                    nodeIcon
                        .frame(width: 86, height: 86)

                    if day.showsTrailCompletionMarker {
                        DayCompletionMarker()
                            .offset(x: 56)
                    }
                }
                .frame(width: 190, height: 86)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .position(
                x: geometry.size.width / 2,
                y: rowHeight / 2
            )
        }
        .frame(height: rowHeight)
    }

    private var accessibilityLabel: String {
        let date = day.isToday ? "Today" : formattedUTCDate(day.date, dateFormat: nil)
        return "\(date), \(day.trailActivitySummary)"
    }

    @ViewBuilder
    private var nodeIcon: some View {
        if day.isToday {
            if let image = UIImage(named: "today-anky-icon") {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 68, height: 68)
                        .clipShape(Circle())

                    Circle()
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 68, height: 68)

                    Text("\(day.ankyversePosition.dayIndex)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .overlay(
                    CurrentDayProgressRing()
                        .frame(width: 78, height: 78)
                )
                .shadow(color: nodeShadow, radius: 16, y: 6)
            } else {
                dayCircle(size: 68, fontSize: 22)
            }
        } else {
            dayCircle(size: 48, fontSize: 16)
        }
    }

    private func dayCircle(size: CGFloat, fontSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(day.hasAnky ? 0.76 : 0.58))
                .frame(width: size, height: size)

            Circle()
                .fill(nodeTexture)
                .frame(width: size, height: size)
                .opacity(day.isToday ? 0.30 : 0.22)

            CircleTextureLines()
                .stroke(Color.white.opacity(day.hasAnky ? 0.08 : 0.05), lineWidth: 1)
                .frame(width: size, height: size)
                .clipShape(Circle())

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(day.hasAnky ? 0.10 : 0.05),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size * 0.82
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(nodeStroke, lineWidth: day.isToday ? 3 : 2)
                )
                .shadow(color: nodeShadow, radius: day.isToday ? 10 : 3, y: 3)

            Text("\(day.ankyversePosition.dayIndex)")
                .font(.system(size: fontSize, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(nodeSymbolColor)
                .frame(width: size, height: size)
        }
    }

    private var nodeFill: Color {
        AnkyverseDayPalette.color(for: day.ankyversePosition.dayInRegion)
    }

    private var nodeTexture: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.10),
                Color.clear,
                Color.black.opacity(day.hasAnky ? 0.22 : 0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var nodeStroke: Color {
        if day.isToday {
            return nodeFill
        }
        return day.hasAnky ? nodeFill.opacity(0.76) : Color.white.opacity(0.18)
    }

    private var nodeShadow: Color {
        nodeFill.opacity(day.hasAnky || day.isToday ? 0.20 : 0.04)
    }

    private var nodeSymbolColor: Color {
        day.hasAnky ? Color.white.opacity(0.82) : Color.white.opacity(0.42)
    }
}

private struct CurrentDayProgressRing: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let progress = AnkyDuration.utcDayProgress(at: timeline.date)

            ZStack {
                Circle()
                    .stroke(
                        Color.black.opacity(0.68),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AnkyTheme.gold.opacity(0.54),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .accessibilityLabel("UTC day progress")
    }
}

private struct DayCompletionMarker: View {
    var body: some View {
        Circle()
            .fill(MapDayPalette.gold.opacity(0.88))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.62), lineWidth: 3)
            )
            .shadow(color: MapDayPalette.gold.opacity(0.38), radius: 6)
            .accessibilityLabel("showed up")
    }
}

private struct CircleTextureLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = max(7, rect.width / 7)
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

private enum AnkyverseDayPalette {
    static func color(for dayInRegion: Int) -> Color {
        switch normalized(dayInRegion) {
        case 1: Color(hex: 0xE5484D)
        case 2: Color(hex: 0xF97316)
        case 3: Color(hex: 0xFACC15)
        case 4: Color(hex: 0x22C55E)
        case 5: Color(hex: 0x2563EB)
        case 6: Color(hex: 0x4F46E5)
        case 7: Color(hex: 0xA855F7)
        default: Color(hex: 0xFFF7E0)
        }
    }

    static func symbolColor(for dayInRegion: Int) -> Color {
        switch normalized(dayInRegion) {
        case 3, 8: Color.black.opacity(0.76)
        default: .white
        }
    }

    private static func normalized(_ dayInRegion: Int) -> Int {
        ((max(dayInRegion, 1) - 1) % 8) + 1
    }
}

private struct DayDetailView: View {
    let day: SessionDay

    private var title: String {
        formattedUTCDate(day.date, dateFormat: "MMMM d, yyyy").lowercased()
    }

    var body: some View {
        ZStack {
            MapDayBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    if day.sessions.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(day.sessions) { session in
                                NavigationLink(value: MapRoute.session(session)) {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 72)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(MapDayPalette.ink.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var emptyState: some View {
        Text("no writing saved")
            .font(.custom("Georgia", size: 20))
            .foregroundStyle(MapDayPalette.paperMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 96)
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    private var isAnky: Bool {
        session.isComplete
    }

    private var reflectedTitle: String? {
        guard session.hasReflection,
              let title = session.reflectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else {
            return nil
        }
        return title.lowercased()
    }

    private var timeText: String {
        session.createdAt.formatted(date: .omitted, time: .shortened).lowercased()
    }

    private var wordText: String {
        "\(session.wordCount) \(session.wordCount == 1 ? "word" : "words")"
    }

    private var metadataText: String {
        var items = [
            timeText,
            AnkyDuration.formatted(session.durationMs),
            wordText
        ]
        if isAnky {
            items.append("anky")
        }
        if session.hasReflection {
            items.append("reflected")
        }
        return items.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reflectedTitle {
                Text(reflectedTitle)
                    .font(.custom("Georgia", size: 19).weight(.semibold))
                    .foregroundStyle(MapDayPalette.gold)
                    .lineLimit(2)
            }

            Text(session.preview)
                .font(.custom("Georgia", size: isAnky ? 17 : 16).weight(reflectedTitle == nil && isAnky ? .semibold : .regular))
                .lineSpacing(4)
                .foregroundStyle(isAnky ? MapDayPalette.paper : MapDayPalette.paperMuted)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MapDayPalette.gold.opacity(0.34))
                .frame(height: 1.5)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            reflectedTitle,
            session.preview,
            metadataText
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct MapDayMetadataDot: View {
    var body: some View {
        Circle()
            .fill(MapDayPalette.gold.opacity(0.44))
            .frame(width: 3, height: 3)
    }
}

private struct MapDayBackground: View {
    var body: some View {
        ZStack {
            Image("map-background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            MapDayPalette.ink
                .opacity(0.76)
                .ignoresSafeArea()

        }
    }
}

private enum MapDayPalette {
    static let ink = Color(hex: 0x080713)
    static let gold = Color(hex: 0xE8C879)
    static let paper = Color(hex: 0xFFF0C9)
    static let paperMuted = Color(hex: 0xFFF0C9).opacity(0.62)
}

private struct DayCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]

    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private func formattedUTCDate(_ date: Date, dateFormat: String?) -> String {
    let formatter = DateFormatter()
    formatter.calendar = .ankyUTC
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    if let dateFormat {
        formatter.dateFormat = dateFormat
    } else {
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
    }
    return formatter.string(from: date)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
