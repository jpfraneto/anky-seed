import SwiftUI
import UIKit
import UserNotifications

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

/// Write Before You Scroll, as one plate on paper: a switch that says what it
/// does, and the apps it holds. Turning the switch on walks whatever is still
/// missing — Screen Time permission, then the choice of apps — so there is
/// never a second button to find.
struct GateSetupView: View {
    @ObservedObject var viewModel: WriteBeforeScrollSpikeViewModel

    @State private var confirmsGateOff = false
    /// The writer asked for the gate; keep walking the steps it still needs.
    @State private var isTurningOn = false
    /// iOS will not let a blocked app's screen open Anky itself: its Write
    /// button sends a notification, and the notification opens Anky. With
    /// notifications denied that button can do nothing, so say so here.
    @State private var notificationsDenied = false
    @Environment(\.scenePhase) private var scenePhase

    /// On means the chosen apps are gated by writing — including the hours
    /// they stand open because today's writing already earned them.
    private var isGateOn: Bool {
        viewModel.isScreenTimeAuthorized && viewModel.state.hasSelection && !viewModel.isGateOff
    }

    private var gateBinding: Binding<Bool> {
        Binding(
            get: { isGateOn },
            set: { wantsOn in
                AnkyHaptics.light()
                if wantsOn {
                    isTurningOn = true
                    continueTurningOn()
                } else {
                    confirmsGateOff = true
                }
            }
        )
    }

    private func continueTurningOn() {
        guard isTurningOn else { return }
        if !viewModel.isScreenTimeAuthorized {
            viewModel.requestAuthorization()
            return
        }
        if !viewModel.state.hasSelection {
            viewModel.isPickerPresented = true
            return
        }
        // Saving a selection already arms the gate; only the explicit
        // off-switch needs undoing.
        if viewModel.isGateOff {
            viewModel.forceLock()
        }
        isTurningOn = false
    }

    private func chooseApps() {
        AnkyHaptics.light()
        if viewModel.isScreenTimeAuthorized {
            viewModel.isPickerPresented = true
        } else {
            isTurningOn = true
            continueTurningOn()
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                Text(AnkyLocalization.ui("Blocked apps"))
                    .font(.fraunces(30, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .padding(.top, 34)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        rowGlyph("shield")
                        rowTitle("Block until I write")
                        Spacer(minLength: 8)
                        Toggle("", isOn: gateBinding)
                            .labelsHidden()
                            .tint(Color.ankyInk)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)

                    Rectangle()
                        .fill(Color.ankyInk.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.leading, 54)

                    Button(action: chooseApps) {
                        HStack(alignment: .top, spacing: 16) {
                            rowGlyph("square.grid.2x2")
                                .frame(height: 52)
                            appsSummary
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.ankyInkSoft.opacity(0.6))
                                .frame(height: 52)
                        }
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.ankyPaperDeep.opacity(0.6))
                )

                if isGateOn && notificationsDenied {
                    notificationsPlate
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Color.ankyPaper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            viewModel.refresh()
            refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { phase in
            // Coming back from the Settings app.
            if phase == .active {
                refreshNotificationStatus()
            }
        }
        .onChange(of: isGateOn) { _ in
            refreshNotificationStatus()
        }
        .onChange(of: viewModel.authorizationStatusText) { _ in
            if viewModel.isScreenTimeAuthorized {
                continueTurningOn()
            } else {
                isTurningOn = false
            }
        }
        .alert(
            AnkyLocalization.ui(AnkyCopyRegistry.gateOffConfirmTitle),
            isPresented: $confirmsGateOff
        ) {
            Button(AnkyLocalization.ui(AnkyCopyRegistry.gateOffConfirm), role: .destructive) {
                viewModel.turnGateOff()
            }
            Button(AnkyLocalization.ui(AnkyCopyRegistry.gateOffCancel), role: .cancel) {}
        } message: {
            Text(AnkyLocalization.ui(AnkyCopyRegistry.gateOffConfirmBody))
        }
        #if os(iOS) && canImport(FamilyControls)
        .familyActivityPicker(
            headerText: AnkyLocalization.ui("Pick the apps that pull you out of yourself."),
            footerText: AnkyLocalization.ui("Anky will put a writing gate before them."),
            isPresented: $viewModel.isPickerPresented,
            selection: $viewModel.selection
        )
        .onChange(of: viewModel.isPickerPresented) { isPresented in
            if !isPresented {
                viewModel.saveSelection()
                if viewModel.state.hasSelection {
                    continueTurningOn()
                } else {
                    isTurningOn = false
                }
            }
        }
        #endif
    }

    // MARK: - Notifications

    private var notificationsPlate: some View {
        Button {
            AnkyHaptics.light()
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    rowGlyph("bell.badge")
                    rowTitle("Allow notifications")
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ankyInkSoft.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)

                Text(AnkyLocalization.ui("Needed to open Anky from a blocked app."))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 54)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.ankyPaperDeep.opacity(0.6))
        )
    }

    private func refreshNotificationStatus() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                notificationsDenied = status == .denied
                // Never asked yet, and the gate needs it: ask now.
                if status == .notDetermined, isGateOn {
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        DispatchQueue.main.async { notificationsDenied = !granted }
                    }
                }
            }
        }
    }

    // MARK: - The apps

    /// The chosen apps as their own icons, or the invitation to choose.
    @ViewBuilder
    private var appsSummary: some View {
        #if os(iOS) && canImport(FamilyControls)
        if viewModel.state.hasSelection {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(Array(viewModel.selection.applicationTokens), id: \.self) { token in
                    tokenIcon { Label(token) }
                }
                ForEach(Array(viewModel.selection.categoryTokens), id: \.self) { token in
                    tokenIcon { Label(token) }
                }
                ForEach(Array(viewModel.selection.webDomainTokens), id: \.self) { token in
                    tokenIcon { Label(token) }
                }
            }
            .padding(.vertical, 10)
            .opacity(isGateOn ? 1 : 0.4)
        } else {
            rowTitle("Choose apps")
                .frame(height: 52)
        }
        #else
        rowTitle("Choose apps")
            .frame(height: 52)
        #endif
    }

    /// Screen Time hands back opaque tokens; only the system can draw what
    /// they stand for, and it draws them small.
    private func tokenIcon(@ViewBuilder _ label: () -> some View) -> some View {
        label()
            .labelStyle(.iconOnly)
            .scaleEffect(1.5)
            .frame(width: 36, height: 36)
    }

    private func rowGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Color.ankyInk)
            .frame(width: 22)
    }

    private func rowTitle(_ key: String) -> some View {
        Text(AnkyLocalization.ui(key))
            .font(.fraunces(17, weight: .regular))
            .foregroundStyle(Color.ankyInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}
