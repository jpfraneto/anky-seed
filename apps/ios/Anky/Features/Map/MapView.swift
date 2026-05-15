import SwiftUI
import UIKit

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()
    @Binding private var revealAfterWriting: SavedAnky?
    @State private var path: [MapRoute] = []

    init(revealAfterWriting: Binding<SavedAnky?> = .constant(nil)) {
        _revealAfterWriting = revealAfterWriting
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
                    DayDetailView(day: day)
                case .session(let summary):
                    if let artifact = viewModel.artifact(for: summary) {
                        RevealView(viewModel: RevealViewModel(artifact: artifact))
                    } else {
                        ContentUnavailableView("Anky not found", systemImage: "doc.badge.questionmark")
                    }
                case .reveal(let artifact):
                    RevealView(viewModel: RevealViewModel(artifact: artifact))
                }
            }
            .onAppear {
                viewModel.refresh()
                openPendingRevealIfNeeded()
            }
            .onChange(of: revealAfterWriting) { _ in
                openPendingRevealIfNeeded()
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

    private let rowHeight: CGFloat = 124
    private var displayDays: [SessionDay] {
        days.reversed()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            TrailRibbon(dayCount: displayDays.count, rowHeight: rowHeight)
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
                    .onChange(of: todayDate) { _ in
                        focusToday(with: proxy)
                    }
                    .onChange(of: days.count) { _ in
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

private struct TrailRibbon: View {
    let dayCount: Int
    let rowHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard dayCount > 0 else {
                    return
                }

                var path = Path()
                for index in 0..<dayCount {
                    let point = CGPoint(
                        x: trailX(index: index, width: size.width),
                        y: rowHeight * CGFloat(index) + rowHeight / 2
                    )
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                context.stroke(
                    path,
                    with: .color(Color(.tertiaryLabel).opacity(0.18)),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    path,
                    with: .color(Color.accentColor.opacity(0.24)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [1, 18])
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
                VStack(spacing: 7) {
                    ZStack(alignment: .topTrailing) {
                        nodeIcon

                        ActivityPips(ankyCount: day.ankyCount, fragmentCount: day.writingSessionCount)
                            .offset(x: 20, y: -8)
                    }

                    VStack(spacing: 2) {
                        Text(day.isToday ? "Today" : day.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption.weight(day.isToday ? .semibold : .medium))
                            .foregroundStyle(.primary)

                        Text(day.trailActivitySummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                }
                .frame(width: 150)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .position(
                x: trailX(index: index, width: geometry.size.width),
                y: rowHeight / 2
            )
        }
        .frame(height: rowHeight)
    }

    private var accessibilityLabel: String {
        let date = day.isToday ? "Today" : day.date.formatted(date: .abbreviated, time: .omitted)
        return "\(date), \(day.trailActivitySummary)"
    }

    @ViewBuilder
    private var nodeIcon: some View {
        if day.isToday {
            if let image = UIImage(named: "today-anky-icon") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(nodeStroke, lineWidth: 2)
                    )
                    .shadow(color: nodeShadow, radius: 14, y: 5)
            } else {
                dayCircle(size: 64, symbolSize: 21)
            }
        } else {
            dayCircle(size: 48, symbolSize: 17)
        }
    }

    private func dayCircle(size: CGFloat, symbolSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(nodeFill)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(nodeStroke, lineWidth: day.isToday ? 3 : 1.5)
                )
                .shadow(color: nodeShadow, radius: day.isToday ? 12 : 5, y: 4)

            Image(systemName: nodeSymbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(nodeSymbolColor)
                .frame(width: size, height: size)
        }
    }

    private var nodeFill: Color {
        AnkyverseDayPalette.color(for: day.ankyversePosition.dayInRegion)
    }

    private var nodeStroke: Color {
        day.isToday ? nodeFill : nodeFill.opacity(0.72)
    }

    private var nodeShadow: Color {
        nodeFill.opacity(day.isToday ? 0.32 : 0.16)
    }

    private var nodeSymbol: String {
        if day.isToday { return "location.fill" }
        if day.ankyCount > 0 { return "sparkle" }
        if day.writingSessionCount > 0 { return "leaf" }
        return "circle"
    }

    private var nodeSymbolColor: Color {
        AnkyverseDayPalette.symbolColor(for: day.ankyversePosition.dayInRegion)
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

private struct ActivityPips: View {
    let ankyCount: Int
    let fragmentCount: Int

    var body: some View {
        HStack(spacing: 3) {
            if ankyCount == 0 && fragmentCount == 0 {
                Circle()
                    .stroke(Color.secondary.opacity(0.34), lineWidth: 1)
                    .frame(width: 6, height: 6)
            } else {
                ForEach(0..<min(ankyCount, 3), id: \.self) { _ in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }

                ForEach(0..<min(fragmentCount, 3), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }

                if ankyCount + fragmentCount > 6 {
                    Text("+\(ankyCount + fragmentCount - 6)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct DayDetailView: View {
    let day: SessionDay

    private var ankys: [SessionSummary] {
        day.sessions.filter(\.isComplete)
    }

    private var fragments: [SessionSummary] {
        day.sessions.filter { !$0.isComplete }
    }

    private var title: String {
        day.date.formatted(.dateTime.month(.wide).day().year()).lowercased()
    }

    var body: some View {
        ZStack {
            MapDayBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    if day.sessions.isEmpty {
                        emptyState
                    } else {
                        if !ankys.isEmpty {
                            MapDaySessionSection(title: "ankys", sessions: ankys)
                        }

                        if !fragments.isEmpty {
                            MapDaySessionSection(title: "fragments", sessions: fragments)
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

private struct MapDaySessionSection: View {
    let title: String
    let sessions: [SessionSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom("Georgia", size: 24).weight(.bold))
                .foregroundStyle(MapDayPalette.gold)
                .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    NavigationLink(value: MapRoute.session(session)) {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionSummary

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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let reflectedTitle {
                Text(reflectedTitle)
                    .font(.custom("Georgia", size: 19).weight(.semibold))
                    .foregroundStyle(MapDayPalette.gold)
                    .lineLimit(2)
            }

            Text(session.preview)
                .font(.custom("Georgia", size: 16))
                .lineSpacing(4)
                .foregroundStyle(MapDayPalette.paper)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(timeText)
                MapDayMetadataDot()
                Text(AnkyDuration.formatted(session.durationMs))
                MapDayMetadataDot()
                Text(wordText)
            }
            .font(.system(size: 12, weight: .medium, design: .serif))
            .foregroundStyle(MapDayPalette.paperMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MapDayPalette.gold.opacity(0.16))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            reflectedTitle,
            session.preview,
            timeText,
            AnkyDuration.formatted(session.durationMs),
            wordText
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

            GeometryReader { geometry in
                ForEach([0.18, 0.54, 0.82], id: \.self) { position in
                    MapDayPalette.gold.opacity(0.10)
                        .frame(height: 1)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * position
                        )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
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

private func trailX(index: Int, width: CGFloat) -> CGFloat {
    let pattern: [CGFloat] = [-0.28, 0.04, 0.31, 0.17, -0.12, -0.35, -0.08, 0.24]
    let usableWidth = max(120, width - 108)
    let center = width / 2
    let offset = pattern[index % pattern.count] * usableWidth
    return min(max(center + offset, 76), width - 76)
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
