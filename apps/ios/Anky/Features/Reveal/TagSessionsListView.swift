import SwiftUI

struct TagSessionsListView: View {
    let tag: String
    private let sessionIndexStore: SessionIndexStore
    private let archive: LocalAnkyArchive
    @State private var sessions: [SessionSummary] = []

    init(
        tag: String,
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        archive: LocalAnkyArchive = LocalAnkyArchive()
    ) {
        self.tag = tag
        self.sessionIndexStore = sessionIndexStore
        self.archive = archive
    }

    var body: some View {
        ZStack {
            RevealPalette.ink.ignoresSafeArea()
            RevealBackgroundTexture()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tag)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(RevealPalette.markdownHeading)
                        .tracking(0)
                        .padding(.top, 18)

                    if sessions.isEmpty {
                        Text(AnkyLocalization.ui("no saved sessions with this tag."))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(RevealPalette.paper.opacity(0.68))
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sessions) { summary in
                                if let artifact = try? archive.load(url: summary.localFileURL) {
                                    NavigationLink {
                                        RevealView(viewModel: RevealViewModel(artifact: artifact))
                                    } label: {
                                        TagSessionRow(summary: summary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(RevealPalette.ink.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            sessions = sessionIndexStore.sessionsWithTag(tag)
        }
    }
}

private struct TagSessionRow: View {
    let summary: SessionSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.title)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(RevealPalette.gold.opacity(0.9))
                    .lineLimit(2)

                Text(summary.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(RevealPalette.paper.opacity(0.58))

                Text("\(summary.wordCount) \(AnkyLocalization.ui(summary.wordCount == 1 ? "word" : "words"))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(RevealPalette.paper.opacity(0.48))
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RevealPalette.gold.opacity(0.7))
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RevealPalette.gold.opacity(0.13))
                .frame(height: 1)
        }
    }
}
