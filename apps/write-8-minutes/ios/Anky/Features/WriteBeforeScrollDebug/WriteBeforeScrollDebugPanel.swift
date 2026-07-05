import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

struct WriteBeforeScrollDebugPanel: View {
    @ObservedObject var viewModel: WriteBeforeScrollSpikeViewModel
    let sessionMetrics: WriteBeforeScrollSessionMetrics
    let availableUnlockGrant: UnlockGrant?
    let onUnlock: () -> Void
    let onWrite: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Text(isExpanded ? "WBS debug" : "WBS")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.82), in: Capsule())
                    .foregroundStyle(.white)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    debugRow("next", viewModel.nextStepText)
                    debugRow("auth", viewModel.authorizationStatusText)
                    debugRow("token", viewModel.selectedExistsText)
                    debugRow("selected", viewModel.selectedStatusText)
                    debugRow("tier", viewModel.unlockTierText)
                    debugRow("until", viewModel.unlockExpirationText)
                    debugRow("shield", viewModel.shieldStatusText)
                    debugRow("pending", viewModel.pendingShieldActionText)
                    debugRow("threshold", sessionMetrics.currentThresholdStateText)
                    debugRow("golden", sessionMetrics.goldenMetricText)
                    debugRow("error", viewModel.lastErrorText)

                    HStack(spacing: 8) {
                        debugButton("authorize", action: viewModel.requestAuthorization)
                        debugButton("select X", action: {
                            #if os(iOS) && canImport(FamilyControls)
                            viewModel.isPickerPresented = true
                            #endif
                        })
                    }

                    HStack(spacing: 8) {
                        debugButton("force lock", action: viewModel.forceLock)
                        debugButton("unlock 60s", action: viewModel.forceUnlockForTesting)
                    }

                    if let availableUnlockGrant {
                        debugButton("unlock \(availableUnlockGrant.tier.displayName)", action: onUnlock)
                    }

                    debugButton("write an anky", action: onWrite)

                    Divider()
                        .background(.white.opacity(0.22))

                    Text("last 20 events")
                        .foregroundStyle(.white.opacity(0.58))
                    ForEach(viewModel.recentEvents) { event in
                        Text(eventLine(event))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .font(.caption2)
                .padding(10)
                .frame(maxWidth: 320, maxHeight: 520, alignment: .leading)
                .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
            }
        }
        .padding(.leading, 12)
        .padding(.top, 54)
        #if os(iOS) && canImport(FamilyControls)
        .familyActivityPicker(
            headerText: "Select X only for this spike.",
            footerText: "Hardcoding X is not available through Screen Time tokens.",
            isPresented: $viewModel.isPickerPresented,
            selection: $viewModel.selection
        )
        .onChange(of: viewModel.isPickerPresented) { isPresented in
            if !isPresented {
                viewModel.saveSelection()
            }
        }
        #endif
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text(label)
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 56, alignment: .leading)
            Text(value)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }

    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func eventLine(_ event: WriteBeforeScrollEvent) -> String {
        let tier = event.tierRawValue.map { " \($0)" } ?? ""
        let message = event.message.map { " - \($0)" } ?? ""
        return "\(event.timestamp.formatted(date: .omitted, time: .standard)) \(event.name.rawValue)\(tier)\(message)"
    }
}
