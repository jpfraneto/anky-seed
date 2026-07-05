import ActivityKit
import WidgetKit
import SwiftUI

/// Phase-2 §5: the lock-screen trial presence. A small thumbnail of the
/// writer's own underdrawing and two quiet lines. No countdown, no timer,
/// no scarcity — the copy was fixed when the activity started.
struct TrialLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrialActivityAttributes.self) { context in
            TrialLockScreenView(
                headline: context.attributes.headline,
                trialLine: context.attributes.trialLine
            )
            .activityBackgroundTint(GlancePalette.paper)
            .activitySystemActionForegroundColor(GlancePalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    trialThumb(size: 40)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.headline)
                            .font(.system(size: 14, weight: .medium, design: .serif))
                        Text(context.attributes.trialLine)
                            .font(.system(size: 12, weight: .regular))
                            .opacity(0.75)
                    }
                }
            } compactLeading: {
                Image(systemName: "hurricane")
                    .foregroundStyle(GlancePalette.gold)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "hurricane")
                    .foregroundStyle(GlancePalette.gold)
            }
        }
    }

    @ViewBuilder
    private func trialThumb(size: CGFloat) -> some View {
        if let url = GlanceSharedState.imageURL(named: GlanceSharedState.trialThumbFileName),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(GlancePalette.gold.opacity(0.7), lineWidth: 0.5)
                )
        }
    }
}

private struct TrialLockScreenView: View {
    let headline: String
    let trialLine: String

    var body: some View {
        HStack(spacing: 12) {
            if let url = GlanceSharedState.imageURL(named: GlanceSharedState.trialThumbFileName),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(GlancePalette.gold.opacity(0.75), lineWidth: 0.5)
                    )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(GlancePalette.ink)
                Text(trialLine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(GlancePalette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
