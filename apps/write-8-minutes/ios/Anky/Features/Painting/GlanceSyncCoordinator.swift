import UIKit
import WidgetKit

/// Phase-2 §4: mirrors the current level painting into the App Group as a
/// flat pre-rendered composite at true progress, then wakes the widget.
/// Called after every sealed session, ceremony, and foreground refresh —
/// the same beats that already refresh the quick action.
enum GlanceSyncCoordinator {
    private static var lastSyncedKey: String?

    @MainActor
    static func sync(
        progressStore: LevelProgressStore = LevelProgressStore(),
        assetStore: PaintingAssetStore = PaintingAssetStore(),
        entitled: Bool = EntitlementStore.lastKnownEntitledForGating
    ) {
        // Phase-3: the widget mirrors the presented (boundary-held) progress,
        // never a level the writer hasn't been shown.
        let progress = progressStore.presentedProgress(entitled: entitled)
        let atBoundary = progressStore.isAtBoundary(entitled: entitled)
        let percent = Int((progress.percent * 100).rounded())
        let key = "\(progress.level)-\(percent)-\(atBoundary)"
        guard key != lastSyncedKey else { return }

        let package = assetStore.installedPackage(forLevel: progress.level)
            ?? assetStore.installStarterIfNeeded()
        guard let package, let assets = PaintingRevealAssets(package: package) else { return }
        let isPlaceholder = package.level == 1 && progress.level != 1

        Task.detached(priority: .utility) {
            guard let composite = FallbackRevealRenderer.shared.render(
                assets: assets,
                progress: Double(percent) / 100.0
            ) else { return }
            guard let imageData = downscaled(composite, to: 600)?.pngData() else { return }
            let thumbData = downscaled(assets.underdrawing, to: 200)?.pngData()

            let snapshot = GlanceSnapshot(
                level: progress.level,
                percent: percent,
                updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                imageFile: GlanceSharedState.imageFileName(level: progress.level, percent: percent),
                isPlaceholder: isPlaceholder,
                isAtBoundary: atBoundary
            )
            do {
                try GlanceSharedState.write(snapshot: snapshot, imageData: imageData)
                if let thumbData {
                    try GlanceSharedState.writeTrialThumb(thumbData)
                }
            } catch {
                return
            }
            await MainActor.run {
                lastSyncedKey = key
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private static func downscaled(_ image: UIImage, to side: CGFloat) -> UIImage? {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
