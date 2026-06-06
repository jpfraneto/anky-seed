import SwiftUI
import UIKit

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()
    @Binding private var revealAfterWriting: SavedAnky?
    @EnvironmentObject private var ankyCompanion: AnkyCompanionStore
    @State private var path: [MapRoute] = []
    @State private var pendingReflectionReadyArtifact: SavedAnky?
    private let onTryAgain: () -> Void
    private let onBackupRequested: () -> Void
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(
        revealAfterWriting: Binding<SavedAnky?> = .constant(nil),
        onTryAgain: @escaping () -> Void = {},
        onBackupRequested: @escaping () -> Void = {}
    ) {
        _revealAfterWriting = revealAfterWriting
        self.onTryAgain = onTryAgain
        self.onBackupRequested = onBackupRequested
    }

    var body: some View {
        NavigationStack(path: $path) {
            TrailMapView(
                days: viewModel.spatialDays,
                todayDate: viewModel.todayDate,
                ankys: viewModel.completeAnkyCount,
                minutes: viewModel.totalWritingMinutes,
                streak: viewModel.currentStreak,
                openAllAnkys: {
                    AnkyHaptics.light()
                    path.append(.allAnkys)
                }
            ) { day in
                path.append(.day(day))
            }
            .navigationDestination(for: MapRoute.self) { route in
                switch route {
                case .day(let day):
                    DayDetailView(
                        day: viewModel.day(for: day.date) ?? day,
                        createTestAnky: {
                            try viewModel.createTestAnky(on: day.date)
                        }
                    )
                case .allAnkys:
                    MapAllAnkysHistoryView(
                        sessions: viewModel.completeAnkySessions,
                        refresh: viewModel.refresh
                    )
                case .session(let summary):
                    if let artifact = viewModel.artifact(for: summary) {
                        RevealView(
                            viewModel: RevealViewModel(artifact: artifact),
                            onDeleted: viewModel.refresh,
                            onTryAgain: tryAgain,
                            onReflectionReady: {
                                onBackupRequested()
                                showReflectionReadyBubble(for: artifact)
                            }
                        )
                    } else {
                        ContentUnavailableView("Anky not found", systemImage: "doc.badge.questionmark")
                    }
                case .reveal(let artifact):
                    RevealView(
                        viewModel: RevealViewModel(artifact: artifact),
                        onDeleted: viewModel.refresh,
                        onTryAgain: tryAgain,
                        onReflectionReady: {
                            onBackupRequested()
                            showReflectionReadyBubble(for: artifact)
                        }
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
            .onChange(of: path) { _, newPath in
                guard newPath.isEmpty, let artifact = pendingReflectionReadyArtifact else {
                    return
                }
                pendingReflectionReadyArtifact = nil
                presentReflectionReadyBubble(for: artifact)
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

    private func showReflectionReadyBubble(for artifact: SavedAnky) {
        viewModel.refresh()
        guard path.isEmpty else {
            pendingReflectionReadyArtifact = artifact
            return
        }
        presentReflectionReadyBubble(for: artifact)
    }

    private func presentReflectionReadyBubble(for artifact: SavedAnky) {
        ankyCompanion.witness(
            mood: .guiding,
            sequence: .waveFront,
            bubble: AnkyBubble(
                text: "your reflection is ready.",
                actions: [
                    AnkyChatAction("open reflection", isPrimary: true) {
                        path = [.reveal(artifact)]
                        ankyCompanion.hideBubble()
                    }
                ]
            )
        )
    }
}

private enum MapRoute: Hashable {
    case day(SessionDay)
    case allAnkys
    case session(SessionSummary)
    case reveal(SavedAnky)
}

private struct TrailMapView: View {
    let days: [SessionDay]
    let todayDate: Date
    let ankys: Int
    let minutes: Int
    let streak: Int
    let openAllAnkys: () -> Void
    let openDay: (SessionDay) -> Void

    @State private var centeredDayID: Date?
    @State private var todayY: CGFloat?
    @State private var didInitialFocusToday = false

    private let rowHeight: CGFloat = 104
    private let statsPanelHeight: CGFloat = 68
    private let topChromeSpacing: CGFloat = 14
    private let horizontalInset: CGFloat = 20

    private var displayDays: [SessionDay] {
        days.reversed()
    }

    var body: some View {
        GeometryReader { geometry in
            let reservedTopSpace = geometry.safeAreaInsets.top + topChromeSpacing + statsPanelHeight + 26
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: reservedTopSpace)

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
                            .frame(minHeight: max(0, geometry.size.height - reservedTopSpace))
                            .padding(.vertical, 48)
                        }
                    }
                    .background(trailBackground)
                    .coordinateSpace(name: "trailViewport")
                    .onPreferenceChange(DayCenterPreferenceKey.self) { centers in
                        updateCenteredDay(centers: centers, viewportHeight: geometry.size.height)
                    }
                    .onAppear {
                        focusTodayIfNeeded(with: proxy)
                    }
                    .onChange(of: todayDate) { _, _ in
                        focusTodayIfNeeded(with: proxy)
                    }
                    .onChange(of: days.count) { _, _ in
                        focusTodayIfNeeded(with: proxy)
                    }

                    VStack(spacing: 0) {
                        MapStatsPanel(
                            ankys: ankys,
                            minutes: minutes,
                            streak: streak,
                            action: openAllAnkys
                        )
                        .frame(height: statsPanelHeight)
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, geometry.safeAreaInsets.top + topChromeSpacing)

                        Spacer()

                        HStack {
                            Spacer()

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
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .top)
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

    private func focusTodayIfNeeded(with proxy: ScrollViewProxy) {
        guard !didInitialFocusToday else {
            return
        }
        didInitialFocusToday = true
        focusToday(with: proxy)
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
                AnkyHaptics.light()
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

private struct MapStatsPanel: View {
    let ankys: Int
    let minutes: Int
    let streak: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                MapStatCell(icon: "you-icon-feather-stat", value: "\(ankys)", label: "Ankys")
                MapStatsDivider()
                MapStatCell(icon: "you-icon-clock-stat", value: "\(minutes)", label: "Minutes")
                MapStatsDivider()
                MapStatCell(icon: "you-icon-flame-stat", value: "\(streak)", label: "Streak")
            }
            .frame(height: 68)
            .frame(maxWidth: .infinity)
            .background(MapDayPalette.ink.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(MapDayPalette.gold.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open all ankys")
    }
}

private struct MapStatCell: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MapDayPalette.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MapDayPalette.paper.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }
}

private struct MapStatsDivider: View {
    var body: some View {
        Rectangle()
            .fill(MapDayPalette.gold.opacity(0.18))
            .frame(width: 1, height: 34)
    }
}

private struct MapAllAnkysHistoryView: View {
    let sessions: [SessionSummary]
    let refresh: () -> Void

    private let bottomNavigationReserve: CGFloat = 152

    private var title: String {
        "\(sessions.count) \(sessions.count == 1 ? "anky" : "ankys")"
    }

    var body: some View {
        ZStack {
            MapDayBackground()

            GeometryReader { geometry in
                let viewportWidth = min(geometry.size.width, UIScreen.main.bounds.width)
                let contentWidth = max(0, viewportWidth * 0.87)
                let horizontalPadding = max(0, (viewportWidth - contentWidth) / 2)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        if sessions.isEmpty {
                            Color.clear
                                .frame(width: contentWidth, height: 180)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(sessions) { session in
                                    NavigationLink(value: MapRoute.session(session)) {
                                        SessionRow(
                                            session: session,
                                            rowWidth: contentWidth,
                                            showsDayInHeader: true
                                        )
                                        .frame(width: contentWidth, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        AnkyHaptics.light()
                                    })
                                }
                            }
                            .frame(width: contentWidth, alignment: .leading)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, bottomNavigationReserve)
                }
                .frame(width: viewportWidth, alignment: .leading)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(MapDayPalette.ink.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: refresh)
    }
}

private struct DayDetailView: View {
    let day: SessionDay
    let createTestAnky: () throws -> SavedAnky
    @State private var isCreatingTestAnky = false
    @State private var testAnkyErrorMessage: String?
    private let bottomNavigationReserve: CGFloat = 152

    private var title: String {
        formattedUTCDate(day.date, dateFormat: "MMMM d, yyyy")
    }

    private var displaySessions: [SessionSummary] {
        day.sessions.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            MapDayBackground()

            GeometryReader { geometry in
                let viewportWidth = min(geometry.size.width, UIScreen.main.bounds.width)
                let contentWidth = max(0, viewportWidth * 0.87)
                let horizontalPadding = max(0, (viewportWidth - contentWidth) / 2)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        if day.sessions.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 0) {
                                ForEach(displaySessions) { session in
                                    NavigationLink(value: MapRoute.session(session)) {
                                        SessionRow(session: session, rowWidth: contentWidth)
                                            .frame(width: contentWidth, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        AnkyHaptics.light()
                                    })
                                }
                            }
                            .frame(width: contentWidth, alignment: .leading)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, bottomNavigationReserve)
                }
                .frame(width: viewportWidth, alignment: .leading)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(MapDayPalette.ink.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createTestAnkyFromToolbar()
                } label: {
                    if isCreatingTestAnky {
                        ProgressView()
                            .tint(MapDayPalette.gold)
                    } else {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MapDayPalette.gold)
                    }
                }
                .disabled(isCreatingTestAnky)
                .accessibilityLabel("Create test .anky")
            }
        }
        .alert("Could not create test .anky", isPresented: testAnkyErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testAnkyErrorMessage ?? "The test fixture could not be imported.")
        }
    }

    private var emptyState: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 180)
    }

    private func createTestAnkyFromToolbar() {
        guard !isCreatingTestAnky else {
            return
        }

        isCreatingTestAnky = true
        do {
            _ = try createTestAnky()
            testAnkyErrorMessage = nil
            AnkyHaptics.medium()
        } catch {
            testAnkyErrorMessage = "The test fixture could not be imported."
            AnkyHaptics.warning()
        }
        isCreatingTestAnky = false
    }

    private var testAnkyErrorBinding: Binding<Bool> {
        Binding {
            testAnkyErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                testAnkyErrorMessage = nil
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let rowWidth: CGFloat
    var showsDayInHeader = false

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
        return title
    }

    private var timeText: String {
        if showsDayInHeader {
            return "\(session.createdAt.formatted(date: .omitted, time: .shortened)) · \(formattedUTCDate(session.createdAt, dateFormat: "MMMM d, yyyy"))"
        }
        return session.createdAt.formatted(date: .omitted, time: .shortened)
    }

    private var wordText: String {
        "\(session.wordCount) \(session.wordCount == 1 ? "word" : "words")"
    }

    private var metadataText: String {
        let items = [
            AnkyDuration.formatted(session.durationMs),
            wordText
        ]
        return items.joined(separator: " · ")
    }

    private var displayTags: [String] {
        session.tags
            .map(Self.hashtag)
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataHeader

            if let reflectedTitle {
                Text(reflectedTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(MapDayPalette.gold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: rowWidth, alignment: .leading)
                    .clipped()
            }

            Text(session.preview)
                .font(.system(size: isAnky ? 17 : 16, weight: reflectedTitle == nil && isAnky ? .semibold : .regular))
                .lineSpacing(4)
                .foregroundStyle(isAnky ? MapDayPalette.paper : MapDayPalette.paperMuted)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: rowWidth, alignment: .leading)
                .clipped()

            if !displayTags.isEmpty {
                FlowLayout(spacing: 7, rowSpacing: 6) {
                    ForEach(displayTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MapDayPalette.gold.opacity(0.92))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
                .frame(width: rowWidth, alignment: .leading)
                .clipped()
            }
        }
        .frame(width: rowWidth, alignment: .leading)
        .padding(.vertical, 18)
        .clipped()
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

    private var metadataHeader: some View {
        let spacing: CGFloat = 10
        let timeWidth: CGFloat = showsDayInHeader ? min(max(190, rowWidth * 0.58), rowWidth * 0.68) : 112
        let metadataWidth = max(0, rowWidth - timeWidth - spacing)

        return HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(timeText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(MapDayPalette.gold.opacity(0.82))
                .lineLimit(1)
                .frame(width: timeWidth, alignment: .leading)

            Text(metadataText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MapDayPalette.paperMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
                .frame(width: metadataWidth, alignment: .trailing)
                .clipped()
        }
        .frame(width: rowWidth, alignment: .leading)
    }

    private static func hashtag(_ tag: String) -> String {
        let cleaned = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)
            .lowercased()
        return cleaned.isEmpty ? "" : "#\(cleaned)"
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .greatestFiniteMagnitude)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [FlowRow] {
        var rows = [FlowRow]()
        var currentItems = [FlowItem]()
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var y: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextX = currentItems.isEmpty ? 0 : currentWidth + spacing
            if !currentItems.isEmpty, nextX + size.width > maxWidth {
                rows.append(FlowRow(items: currentItems, y: y, width: currentWidth, height: currentHeight))
                y += currentHeight + rowSpacing
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            let x = currentItems.isEmpty ? 0 : currentWidth + spacing
            currentItems.append(FlowItem(index: index, x: x, size: size))
            currentWidth = x + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, y: y, width: currentWidth, height: currentHeight))
        }

        return rows
    }

    private struct FlowRow {
        let items: [FlowItem]
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private struct FlowItem {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }
}

private struct MapDayMetadataDot: View {
    var body: some View {
        Circle()
            .fill(MapDayPalette.gold.opacity(0.44))
            .frame(width: 3, height: 3)
    }
}

struct MapDayBackground: View {
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

enum MapDayPalette {
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

func formattedUTCDate(_ date: Date, dateFormat: String?) -> String {
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
