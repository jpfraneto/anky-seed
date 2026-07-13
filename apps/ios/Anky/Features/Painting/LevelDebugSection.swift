import SwiftUI

#if DEBUG
/// DEBUG-only forcing controls for the level system: set totals, owe a
/// ceremony, clone the starter package to any level, reset everything.
/// Lives at the bottom of Settings in debug builds only.
struct LevelDebugSection: View {
    @State private var summary = ""
    @State private var showsTileAuthoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LEVEL DEBUG")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ankyMadder)

            Text(summary)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.ankyInkSoft)

            HStack(spacing: 8) {
                debugButton("+479s") { addSeconds(479) }
                debugButton("+480s") { addSeconds(480) }
                debugButton("+30s strokes") { addStrokes(30) }
            }
            HStack(spacing: 8) {
                debugButton("owe ceremony") { oweCeremony() }
                debugButton("clone pkg → next") { clonePackage() }
                debugButton("reset") { reset() }
            }
            HStack(spacing: 8) {
                debugButton("tile authoring") { showsTileAuthoring = true }
            }
        }
        .sheet(isPresented: $showsTileAuthoring) {
            TileAuthoringView()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ankyMadder.opacity(0.06))
        )
        .onAppear(perform: refresh)
    }

    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            refresh()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ankyInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.ankyPaper.opacity(0.7), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func refresh() {
        let store = LevelProgressStore()
        let snapshot = store.load()
        let progress = store.progress
        summary = "lvl \(progress.level) · \(progress.secondsIntoLevel)/\(progress.secondsRequired)s"
            + " · pending \(snapshot.pendingStrokeSeconds)s"
            + " · shown \(snapshot.lastCeremonyShownLevel ?? 1)"
            + " · pkgs \(PaintingAssetStore().installedLevels().map(String.init).joined(separator: ","))"
    }

    private func addSeconds(_ seconds: Int) {
        let store = LevelProgressStore()
        var snapshot = store.load()
        snapshot.totalSeconds += seconds
        snapshot.pendingStrokeSeconds += seconds
        store.save(snapshot)
    }

    private func addStrokes(_ seconds: Int) {
        let store = LevelProgressStore()
        var snapshot = store.load()
        snapshot.pendingStrokeSeconds += seconds
        store.save(snapshot)
    }

    private func oweCeremony() {
        // Push the total just past the next threshold so the ceremony fires
        // at the next unhurried open.
        let store = LevelProgressStore()
        var snapshot = store.load()
        let progress = store.progress
        let remaining = progress.secondsRequired - progress.secondsIntoLevel
        snapshot.totalSeconds += remaining
        snapshot.pendingStrokeSeconds += remaining
        store.save(snapshot)
    }

    private func clonePackage() {
        // Clone the newest installed package to the next level so the
        // ceremony's glimpse has something to bloom.
        let assetStore = PaintingAssetStore()
        assetStore.installStarterIfNeeded()
        let progress = LevelProgressStore().progress
        let target = progress.level + 1
        guard assetStore.installedPackage(forLevel: target) == nil,
              let sourceLevel = assetStore.installedLevels().last,
              let source = assetStore.installedPackage(forLevel: sourceLevel) else {
            return
        }
        let meta: [String: Any] = [
            "title": "The Glimpse",
            "palette": source.palette,
            "level": target,
            "thresholdSeconds": AnkyLevel.thresholdSeconds(forLevel: target),
        ]
        guard
            let metaData = try? JSONSerialization.data(withJSONObject: meta),
            let finalData = try? Data(contentsOf: source.finalURL),
            let underData = try? Data(contentsOf: source.underdrawingURL),
            let mapData = try? Data(contentsOf: source.revealMapURL)
        else {
            return
        }
        _ = try? assetStore.install(
            level: target,
            finalPng: finalData,
            underdrawingPng: underData,
            revealMapPng: mapData,
            metaJson: metaData
        )
    }

    private func reset() {
        LevelProgressStore().save(LevelProgressSnapshot())
        let assetStore = PaintingAssetStore()
        for level in assetStore.installedLevels() where level > 1 {
            try? FileManager.default.removeItem(at: assetStore.directory(forLevel: level))
        }
    }
}
#endif
