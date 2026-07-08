import SwiftUI
import UIKit

/// The gallery: every finished Anky, permanent. Completed paintings render
/// at 100%; the current level's shows at its true progress; the static
/// levels still ahead (through level 8) show their underdrawing behind a
/// lock — visible, waiting, unpainted.
struct GalleryView: View {
    /// Mirrors STATIC_LEVEL_MAX in backend/painting/config.ts: levels 2–8
    /// are shared default paintings, so their unpainted state is public.
    static let staticLevelMax = 8

    let currentLevel: Int
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [GalleryEntry] = []
    @State private var lockedLevels: [Int] = []
    @State private var selected: GalleryEntry?

    struct GalleryEntry: Identifiable {
        let package: PaintingPackage
        let assets: PaintingRevealAssets
        let progress: Double
        var id: Int { package.level }
    }

    var body: some View {
        ZStack {
            LazureWall(mood: .dusk)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    Text(AnkyLocalization.ui("Gallery"))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .tracking(4)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.ankyInk)
                        .padding(.top, 28)

                    if entries.isEmpty {
                        Text(AnkyLocalization.ui("Your first painting is still arriving, stroke by stroke."))
                            .font(.ankyProse)
                            .foregroundStyle(Color.ankyInkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 60)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                        spacing: 22
                    ) {
                        ForEach(entries) { entry in
                            Button {
                                selected = entry
                            } label: {
                                VStack(spacing: 8) {
                                    PaintingView(
                                        assets: entry.assets,
                                        progress: entry.progress,
                                        glowStrength: 0.5
                                    )
                                    Text("\(entry.package.title.lowercased()) · lvl \(entry.package.level)")
                                        .font(.ankyCaption)
                                        .foregroundStyle(Color.ankyInkSoft)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(lockedLevels, id: \.self) { level in
                            LockedPaintingTile(level: level)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ankyInkSoft)
                            .frame(width: 38, height: 38)
                            .background(Color.ankyPaper.opacity(0.55), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.top, 14)
                }
                Spacer()
            }
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $selected) { entry in
            GalleryDetailView(entry: entry)
        }
    }

    private func load() {
        let store = PaintingAssetStore()
        store.installStarterIfNeeded()
        entries = store.installedLevels().compactMap { level in
            guard
                let package = store.installedPackage(forLevel: level),
                let assets = PaintingRevealAssets(package: package)
            else {
                return nil
            }
            let progress: Double
            if level < currentLevel {
                progress = 1
            } else if level == currentLevel {
                progress = LevelProgressStore().progress.percent
            } else {
                return nil // future paintings stay unseen until their glimpse
            }
            return GalleryEntry(package: package, assets: assets, progress: progress)
        }
        // The static levels still ahead are visible but locked: their shared
        // underdrawing shows what is waiting; the paint stays in the future.
        let firstLocked = max(currentLevel + 1, 2)
        lockedLevels = firstLocked <= Self.staticLevelMax
            ? Array(firstLocked...Self.staticLevelMax)
            : []
    }
}

// MARK: - Locked future levels

/// Immutable webp underdrawings of the shared default levels (2–8), served
/// from the public CDN and cached on disk forever — the locked tiles render
/// instantly on every open after the first.
enum StaticPaintingCDN {
    static let baseURL = URL(string: "https://anky-gallery.fairchat.workers.dev/gallery/paintings/defaults")!

    static func underdrawingURL(level: Int) -> URL {
        baseURL.appendingPathComponent("level-\(level)/underdrawing.webp")
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StaticPaintings")
    }

    private static func cacheFile(level: Int) -> URL {
        cacheDirectory.appendingPathComponent("level-\(level)-underdrawing.webp")
    }

    static func loadUnderdrawing(level: Int) async -> UIImage? {
        if let cached = UIImage(contentsOfFile: cacheFile(level: level).path) {
            return cached
        }
        guard
            let (data, response) = try? await URLSession.shared.data(from: underdrawingURL(level: level)),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let image = UIImage(data: data)
        else {
            return nil
        }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheFile(level: level))
        return image
    }
}

/// A future level's frame: the underdrawing alone — parchment waiting for
/// paint — behind a quiet lock. No title; the painting keeps its secret.
private struct LockedPaintingTile: View {
    let level: Int
    @State private var underdrawing: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Group {
                    if let underdrawing {
                        Image(uiImage: underdrawing)
                            .resizable()
                    } else {
                        Color.ankyPaper
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.ankyGold.opacity(0.45), lineWidth: PaintingFrameMetrics.borderWidth)
                )

                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.ankyInkSoft)
                    .frame(width: 44, height: 44)
                    .background(Color.ankyPaper.opacity(0.72), in: Circle())
            }
            Text("lvl \(level)")
                .font(.ankyCaption)
                .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
        }
        .task(id: level) {
            underdrawing = await StaticPaintingCDN.loadUnderdrawing(level: level)
        }
    }
}

private struct GalleryDetailView: View {
    let entry: GalleryView.GalleryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LazureWall(mood: .kingdom(LevelTheme(package: entry.package).glowTint))

            VStack(spacing: 22) {
                Spacer()

                PaintingView(
                    assets: entry.assets,
                    progress: entry.progress,
                    glowTint: LevelTheme(package: entry.package).glowTint
                )
                .padding(.horizontal, PaintingFrameMetrics.horizontalInset)

                VStack(spacing: 8) {
                    Text("“\(entry.package.title)”")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)

                    if entry.progress >= 1, entry.package.thresholdSeconds > 0 {
                        // "revealed by", not "painted from": true for the
                        // static default levels (1–8) and the generated ones
                        // alike — the reveal is always the writer's seconds.
                        Text("revealed by \(entry.package.thresholdSeconds.formatted()) seconds of your writing")
                            .font(.ankyCaption)
                            .foregroundStyle(Color.ankyInkSoft)
                    }
                }

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }
}
