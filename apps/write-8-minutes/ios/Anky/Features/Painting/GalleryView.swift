import SwiftUI

/// The gallery: every finished Anky, permanent. Completed paintings render
/// at 100%; the current level's shows at its true progress.
struct GalleryView: View {
    let currentLevel: Int
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [GalleryEntry] = []
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
                        .foregroundStyle(Color.ankyGold)
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
                        Text("painted from \(entry.package.thresholdSeconds.formatted()) seconds of your writing")
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
