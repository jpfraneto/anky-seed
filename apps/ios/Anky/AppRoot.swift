import SwiftUI

struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("anky.biometricIdentityConfirmation") private var faceIDLockEnabled = false
    @State private var selectedTab = 0
    @State private var revealAfterWriting: SavedAnky?
    @State private var isUnlocked = false
    @State private var authFailed = false
    @State private var isAuthenticating = false
    @StateObject private var writeViewModel = WriteViewModel()
    @StateObject private var youViewModel = YouViewModel()

    private func showMap() {
        selectedTab = 1
    }

    private func revealOnMap(_ artifact: SavedAnky) {
        revealAfterWriting = artifact
        selectedTab = 1
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    WriteView(
                        viewModel: writeViewModel,
                        shouldFocus: selectedTab == 0 && (!faceIDLockEnabled || isUnlocked),
                        onCompleted: revealOnMap,
                        onCloseToMap: {
                            showMap()
                        }
                    )
                }
                .tabItem {
                    Label("Write", systemImage: "square.and.pencil")
                }
                .tag(0)

                MapView(revealAfterWriting: $revealAfterWriting)
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }
                    .tag(1)

                YouView(viewModel: youViewModel)
                    .tabItem {
                        Label("You", systemImage: "person.crop.circle")
                    }
                    .tag(2)
            }

            if faceIDLockEnabled && !isUnlocked {
                LockFailureView(authFailed: authFailed, isAuthenticating: isAuthenticating) {
                    Task {
                        await authenticateIfNeeded()
                    }
                }
            }

            AnkyPresenceOverlay(
                defaultSequence: presenceSequence,
                goldenGlow: selectedTab == 0 && writeViewModel.hasReachedRitualMark,
                transformToSigil: selectedTab == 0 && writeViewModel.hasStarted && !writeViewModel.hasReachedRitualMark
            )
                .zIndex(40)
        }
        .onAppear {
            AppOpenStore().loadOrCreate()
            let identityStore = WriterIdentityStore()
            _ = try? identityStore.loadOrCreateRecoveryPhrase()
            _ = try? identityStore.loadOrCreate()
            Task {
                await youViewModel.preloadCredits()
            }
            Task {
                await authenticateIfNeeded()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                if faceIDLockEnabled && !isUnlocked && !isAuthenticating {
                    Task {
                        await authenticateIfNeeded()
                    }
                }
            case .background:
                if faceIDLockEnabled {
                    isUnlocked = false
                    authFailed = false
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: faceIDLockEnabled) { enabled in
            if enabled {
                isUnlocked = false
                Task {
                    await authenticateIfNeeded()
                }
            } else {
                isUnlocked = true
                authFailed = false
            }
        }
    }

    private func authenticateIfNeeded() async {
        guard faceIDLockEnabled else {
            isUnlocked = true
            authFailed = false
            return
        }
        guard !isUnlocked, !isAuthenticating else {
            return
        }

        isAuthenticating = true
        isUnlocked = false
        authFailed = false
        let ok = await BiometricAuthClient().confirm(reason: "Unlock ANKY.")
        isUnlocked = ok
        authFailed = !ok
        isAuthenticating = false
    }

    private var presenceSequence: AnkySequenceName {
        switch selectedTab {
        case 0:
            return writeViewModel.hasReachedRitualMark ? .celebrate : .findingThread
        case 1:
            return .walkRight
        case 2:
            return .waveFront
        default:
            return .idleFront
        }
    }
}

private struct LockFailureView: View {
    let authFailed: Bool
    let isAuthenticating: Bool
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if authFailed {
                    Text("face id didn't work. you should not be here")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }

                Button("Try again") {
                    retry()
                }
                .buttonStyle(.bordered)
                .opacity(authFailed ? 1 : 0)
                .disabled(!authFailed)
            }
            .padding(24)
        }
    }
}
