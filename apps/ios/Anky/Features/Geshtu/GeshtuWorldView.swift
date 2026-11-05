//
//  GeshtuWorldView.swift
//  Anky
//
//  The whole app: one writing page, and a drawer of past writings beside it.
//  The page is always the writing surface — a live writing, or a finished one
//  standing exactly where it was written. Nothing here talks to a server.
//

import SwiftUI

struct GeshtuWorldView: View {
    @StateObject private var axis = GeshtuState()
    /// The one writing engine. The world only listens for the seal and hands
    /// it past writings to put on the page.
    @StateObject private var writeViewModel = WriteViewModel()
    @StateObject private var youViewModel = YouViewModel()
    @StateObject private var gateViewModel = WriteBeforeScrollSpikeViewModel()
    @State private var showsGateSetup = false
    /// One quiet line after the shield's emergency button opened the apps.
    @State private var gateLine: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsDeleteConfirmation = false

    /// The subscription: Anky opens with a trial, yearly or monthly.
    @ObservedObject private var pro = AnkyPro.shared
    /// The welcome is still owed (first launch only).
    @State private var needsWelcome = LoomLedger.needsWelcome()
    /// The welcome and the subscription door stand over the page until the
    /// writer is in. The world waits fully covered beneath.
    @State private var gateIsUp = LoomLedger.needsWelcome() || AnkyPro.shared.access != .active
    @AppStorage(AnkyAppearance.storageKey) private var appearance: AnkyAppearance = .paper

    /// The drawer follows the finger; released, it springs open or shut.
    @GestureState(reset: { _, transaction in
        transaction.animation = GeshtuState.drawerSpring
    }) private var drawerDrag: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(geometry.size.width * 0.82, 340)
            let progress = min(1, max(0, (axis.drawerIsOpen ? 1 : 0) + drawerDrag / drawerWidth))

            ZStack(alignment: .leading) {
                Color.ankyPaperDeep
                    .ignoresSafeArea()

                // Mounted only while it can be seen: the archive is not read
                // at launch, and never while the writer is writing.
                if progress > 0 {
                    SessionDrawerView(
                        axis: axis,
                        currentHash: writeViewModel.completedArtifact?.hash,
                        onNewWriting: startNewWriting
                    )
                    .frame(width: drawerWidth)
                    .offset(x: (progress - 1) * 44)
                    .opacity(Double(progress))
                    .simultaneousGesture(drawerCloseDrag(width: drawerWidth))
                }

                page
                    .simultaneousGesture(drawerOpenDrag(width: drawerWidth))
                    .overlay {
                        if progress > 0 {
                            // The page set aside: it dims, wears the corners
                            // of a card, and any touch on it brings it back.
                            ZStack {
                                Color.ankyInk.opacity(0.10 * Double(progress))
                                LeadingCornerCutouts(radius: 40 * min(1, progress * 2.5))
                                    .fill(Color.ankyPaperDeep)
                            }
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { axis.closeDrawer() }
                            .gesture(drawerCloseDrag(width: drawerWidth))
                            .accessibilityLabel(Text(AnkyLocalization.ui("Close menu")))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .offset(x: progress * drawerWidth)
            }
        }
        .environmentObject(axis)
        // Paper or night is the writer's choice, never the device's.
        .preferredColorScheme(appearance.colorScheme)
        .onChange(of: axis.drawerIsOpen) { isOpen in
            if isOpen { dismissKeyboard() }
        }
        .onChange(of: drawerDrag != 0) { dragging in
            if dragging {
                dismissKeyboard()
            } else {
                // A pull let go short of opening: the keyboard comes back.
                DispatchQueue.main.async {
                    if !axis.drawerIsOpen, writeViewModel.canAcceptInput {
                        writeViewModel.focusWritingKeyboard()
                    }
                }
            }
        }
        .onChange(of: axis.entryRequest?.hash) { _ in
            guard let entry = axis.consumeEntryRequest() else { return }
            writeViewModel.showFinishedSession(entry)
        }
    }

    /// The drawer can be pulled out from the leading edge whenever the menu
    /// button would be offered — never across a live writing.
    private var drawerAllowed: Bool {
        if gateIsUp { return false }
        return !writeViewModel.hasStarted || writeViewModel.completedArtifact != nil
    }

    private func drawerOpenDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                guard !axis.drawerIsOpen, drawerAllowed, value.startLocation.x < 30 else { return }
                guard state > 0 || value.translation.width > abs(value.translation.height) else { return }
                state = max(0, value.translation.width)
            }
            .onEnded { value in
                guard !axis.drawerIsOpen, drawerAllowed, value.startLocation.x < 30,
                      value.translation.width > abs(value.translation.height) else { return }
                if value.translation.width > width * 0.3
                    || value.predictedEndTranslation.width > width * 0.6 {
                    AnkyHaptics.light()
                    axis.openDrawer()
                }
            }
    }

    private func drawerCloseDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                guard axis.drawerIsOpen else { return }
                guard state < 0 || -value.translation.width > abs(value.translation.height) else { return }
                state = min(0, value.translation.width)
            }
            .onEnded { value in
                guard axis.drawerIsOpen,
                      -value.translation.width > abs(value.translation.height) else { return }
                if value.translation.width < -width * 0.25
                    || value.predictedEndTranslation.width < -width * 0.5 {
                    axis.closeDrawer()
                }
            }
    }

    /// A fresh page, unless the page already is a blank one.
    private func startNewWriting() {
        if writeViewModel.hasStarted || writeViewModel.completedArtifact != nil {
            writeViewModel.beginBlankSessionFromWriteTab()
        }
        axis.closeDrawer()
        writeViewModel.focusWritingKeyboard()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private var page: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            WriteView(
                viewModel: writeViewModel,
                shouldFocus: !gateIsUp && !axis.drawerIsOpen,
                onCompleted: { _ in grantWriteBeforeScrollUnlock() },
                onOpenMenu: { axis.openDrawer() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let finished = writeViewModel.completedArtifact {
                FinishedWritingChrome(
                    writing: finished.reconstructedText,
                    startsOpen: writeViewModel.finishedJustNow,
                    onNewWriting: startNewWriting,
                    onDelete: {
                        AnkyHaptics.warning()
                        showsDeleteConfirmation = true
                    }
                )
                .id(finished.hash)
                .transition(.opacity)
                .zIndex(1500)
            }

            if let gateLine {
                Text(gateLine)
                    .font(.fraunces(14, weight: .light, italic: true))
                    .foregroundStyle(Color.ankyInkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .ankyGlass(in: Capsule(), interactive: false)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(1600)
            }

            if gateIsUp {
                LoomGateView(
                    pro: pro,
                    needsWelcome: needsWelcome,
                    onWelcomed: {
                        LoomLedger.markDone()
                        needsWelcome = false
                    },
                    onEnter: {
                        // The welcome may have just set the writing up.
                        writeViewModel.refreshPreferences()
                        withAnimation(.easeInOut(duration: 1.2)) {
                            gateIsUp = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                            writeViewModel.focusWritingKeyboard()
                        }
                    }
                )
                .zIndex(3000)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: writeViewModel.completedArtifact?.hash)
        .animation(.easeInOut(duration: 0.4), value: gateLine)
        .onAppear(perform: startWriteBeforeScroll)
        .onChange(of: pro.access) { access in
            // The trial or subscription ended while the app was open: the
            // writing in progress is sealed and the door closes over it.
            if access == .inactive, !gateIsUp {
                if writeViewModel.hasStarted, writeViewModel.completedArtifact == nil {
                    writeViewModel.endWriting()
                }
                dismissKeyboard()
                withAnimation(.easeInOut(duration: 0.8)) { gateIsUp = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .writeBeforeScrollNotificationTapped)) { _ in
            routeFromShield()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                Task { await pro.refresh() }
                gateViewModel.reconcileOnAppActive(hasCurrentVerifiedPro: true)
                gateViewModel.handlePendingInterventionIfNeeded(showWrite: openWritingFromShield)
                routeFromShield()
            case .background:
                // A Quick Pass's minutes belong to the app the writer was
                // reaching for, so its window starts on the way out — and a
                // pass earned mid-sentence seals the writing as they leave.
                gateViewModel.startPendingQuickPassWindowIfNeeded()
                writeViewModel.sealIfLeftInMotion()
            default:
                break
            }
        }
        #if DEBUG
        .onAppear {
            if ScreenshotMode.isActive {
                ScreenshotStage.apply(axis: axis, writeViewModel: writeViewModel)
            }
        }
        #endif
        .sheet(isPresented: $axis.settingsIsOpen) {
            AnkySettingsView(
                viewModel: youViewModel,
                onGateSetupRequested: { showsGateSetup = true }
            )
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showsGateSetup) {
                GateSetupView(viewModel: gateViewModel)
            }
        }
        .sheet(isPresented: $axis.statsIsOpen) {
            WritingStatsView()
        }
        .alert(
            AnkyLocalization.ui("Delete writing session?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(AnkyLocalization.ui("Delete"), role: .destructive) { deleteFinishedWriting() }
            Button(AnkyLocalization.ui("Cancel"), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui("This permanently deletes this writing session. This cannot be undone."))
        }
    }

    // MARK: - Write before you scroll

    /// The gate listens to the writing: a finished sentence from the shield
    /// opens a Quick Pass, reaching the day's minutes opens the day. Both
    /// apply the moment they are earned, with no button.
    private func startWriteBeforeScroll() {
        writeViewModel.bindWriteBeforeScrollUnlockAvailabilityHandler { _ in
            gateViewModel.refresh()
        }
        writeViewModel.bindWriteBeforeScrollPassiveUnlockHandler { grant in
            gateViewModel.applyUnlock(grant, startsCountingOnExit: grant.tier == .quick)
            if writeViewModel.isGateOriginatedSession {
                FirstGateStore().markFirstGateCompleted()
            }
        }
        gateViewModel.reconcileOnAppActive(hasCurrentVerifiedPro: true)
        gateViewModel.handlePendingInterventionIfNeeded(showWrite: openWritingFromShield)
        routeFromShield()
    }

    /// A sealed writing hands over whatever unlock it earned and was not
    /// already applied mid-session.
    private func grantWriteBeforeScrollUnlock() {
        guard let grant = writeViewModel.consumeWriteBeforeScrollAvailableUnlockGrant() else { return }
        if writeViewModel.isGateOriginatedSession {
            FirstGateStore().markFirstGateCompleted()
        }
        if grant.tier == .quick, writeViewModel.hasAppliedPassiveQuickUnlock { return }
        if grant.tier == .daily, writeViewModel.hasAppliedPassiveDailyUnlockUpgrade { return }
        gateViewModel.applyUnlock(grant)
    }

    /// The shield's two buttons each leave a notification; tapping it lands
    /// here. "Write" opens a blank page; "Emergency unlock" opens the apps
    /// for the rest of the day, no writing asked.
    private func routeFromShield() {
        guard let route = WriteBeforeScrollAppRouteResolver().pendingRoute() else { return }
        let bridge = WriteBeforeScrollLaunchBridgeStore()
        switch route {
        case .emergencyBreathFromShield(let intentID):
            let now = Date()
            let endOfDay = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
            ) ?? now.addingTimeInterval(24 * 60 * 60)
            gateViewModel.applyUnlock(
                UnlockGrant(tier: .daily, unlockedUntil: endOfDay, grantedAt: now),
                source: .emergency
            )
            bridge.markConsumed(intentID: intentID)
            showGateLine(AnkyLocalization.ui("Your apps are unlocked."))
        case .writeBeforeScrollFromShield(let intentID):
            guard pro.access == .active else {
                // No loom to write on: the shield never traps anyone behind
                // the subscription. The apps open for the rest of the day.
                let now = Date()
                let endOfDay = Calendar.current.date(
                    byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
                ) ?? now.addingTimeInterval(24 * 60 * 60)
                gateViewModel.applyUnlock(
                    UnlockGrant(tier: .daily, unlockedUntil: endOfDay, grantedAt: now),
                    source: .emergency
                )
                bridge.markConsumed(intentID: intentID)
                return
            }
            openWritingFromShield()
            writeViewModel.markGateOriginatedSession(appDisplayName: bridge.lastAttemptedAppDisplayName())
            bridge.markConsumed(intentID: intentID)
        }
    }

    /// The writer came from a blocked app: the page is in front, ready.
    private func openWritingFromShield() {
        axis.settingsIsOpen = false
        axis.statsIsOpen = false
        axis.closeDrawer()
        if writeViewModel.completedArtifact != nil {
            writeViewModel.beginBlankSessionFromWriteTab()
        }
        writeViewModel.openWritingPortal()
    }

    private func showGateLine(_ line: String) {
        gateLine = line
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if gateLine == line { gateLine = nil }
        }
    }

    /// Deleting leaves nothing to stand on: the page becomes a blank writing.
    private func deleteFinishedWriting() {
        guard let finished = writeViewModel.completedArtifact else { return }
        do {
            try LocalAnkyArchive().delete(finished)
            try? ReflectionStore().delete(hash: finished.hash)
            try? SessionIndexStore().delete(hash: finished.hash)
        } catch {
            return
        }
        writeViewModel.beginBlankSessionFromWriteTab()
    }
}

/// The page's leading corners while it stands aside for the drawer: the two
/// slivers outside a rounded card, painted in the drawer's own ground.
private struct LeadingCornerCutouts: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard radius > 0 else { return path }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true
        )
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

/// The top-right of a finished writing, where the clock stood: one glass
/// capsule with "new writing" and ⋯. The ⋯ list (copy prompt + writing,
/// copy writing, delete) opens on its own right after a writing ends, so
/// taking it to an AI is one tap.
private struct FinishedWritingChrome: View {
    let writing: String
    let startsOpen: Bool
    let onNewWriting: () -> Void
    let onDelete: () -> Void

    @State private var isOpen: Bool
    @State private var didCopy = false

    init(writing: String, startsOpen: Bool, onNewWriting: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.writing = writing
        self.startsOpen = startsOpen
        self.onNewWriting = onNewWriting
        self.onDelete = onDelete
        _isOpen = State(initialValue: startsOpen)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isOpen {
                // A tap anywhere else closes the list.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { setOpen(false) }
            }

            VStack(alignment: .trailing, spacing: 8) {
                capsule
                if isOpen {
                    list
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var capsule: some View {
        HStack(spacing: 0) {
            Button {
                AnkyHaptics.light()
                onNewWriting()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("New writing"))

            Button {
                AnkyHaptics.light()
                setOpen(!isOpen)
            } label: {
                Image(systemName: didCopy ? "checkmark" : "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(didCopy ? Color.ankySage : Color.ankyInkSoft)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AnkyLocalization.ui("More"))
        }
        .padding(.horizontal, 4)
        .ankyGlass(in: Capsule(), interactive: false)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(AnkyLocalization.ui("Copy prompt + writing"), systemImage: "text.badge.plus") {
                performCopy(AnkyReflectionPrompt.build(from: writing))
            }
            Divider().opacity(0.5)
            row(AnkyLocalization.ui("Copy writing"), systemImage: "doc.on.doc") {
                performCopy(writing)
            }
            Divider().opacity(0.5)
            row(AnkyLocalization.ui("Delete"), systemImage: "trash", isDestructive: true) {
                setOpen(false)
                onDelete()
            }
        }
        .frame(width: 250)
        .ankyGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
    }

    private func row(
        _ title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Image(systemName: systemImage)
            }
            .font(.system(size: 16))
            .foregroundStyle(isDestructive ? Color.red : Color.ankyInk)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.easeOut(duration: 0.18)) { isOpen = open }
    }

    private func performCopy(_ text: String) {
        ClipboardClient().copy(text)
        AnkyHaptics.light()
        setOpen(false)
        withAnimation(.easeInOut(duration: 0.2)) { didCopy = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { didCopy = false }
        }
    }
}

/// The reflection prompt the menu wraps a writing in, for any AI the writer
/// chooses to take it to.
enum AnkyReflectionPrompt {
    static func build(from reconstructedText: String) -> String {
        """
        Take a look at this stream-of-consciousness journal entry.

        Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

        Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

        Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

        Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

        Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

        Write in the same language and vibe as the entry.

        Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.

        ---

        \(reconstructedText)
        """
    }
}
