import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

/// User-facing Write Before Scroll setup: authorize Screen Time, choose the
/// apps that pull you out of yourself, and turn the writing gate on.
/// This is the productized surface for what previously lived only in the
/// WBS debug panel.
struct GateSetupView: View {
    @ObservedObject var viewModel: WriteBeforeScrollSpikeViewModel
    let onDone: () -> Void

    private enum SetupStep {
        case authorize
        case chooseApps
        case turnOn
        case done
    }

    private var currentStep: SetupStep {
        if !viewModel.isScreenTimeAuthorized { return .authorize }
        if !viewModel.state.hasSelection { return .chooseApps }
        if !viewModel.state.shieldActive { return .turnOn }
        return .done
    }

    private var stepCaption: String {
        switch currentStep {
        case .authorize:
            return "anky needs screen time permission to hold the door."
        case .chooseApps:
            return "pick the apps that pull you out of yourself."
        case .turnOn:
            return "from now on, those apps wait until you have written."
        case .done:
            return "the door is standing. write, and it opens."
        }
    }

    private var stepButtonTitle: String {
        switch currentStep {
        case .authorize: return "Allow Screen Time"
        case .chooseApps: return "Choose apps"
        case .turnOn: return "Turn on the gate"
        case .done: return "Done"
        }
    }

    private func stepAction() {
        switch currentStep {
        case .authorize:
            viewModel.requestAuthorization()
        case .chooseApps:
            #if os(iOS) && canImport(FamilyControls)
            viewModel.isPickerPresented = true
            #endif
        case .turnOn:
            viewModel.forceLock()
        case .done:
            onDone()
        }
    }

    // One line, one image, one action. The single button always does the
    // next needed step; nothing is overexplained.
    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)

            VStack(spacing: 26) {
                Spacer()

                AnkySpriteView(sequence: .idleFront, size: 150)

                Text(AnkyLocalization.ui("Put a door before the noise."))
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ankyInk)
                    .multilineTextAlignment(.center)

                Text(AnkyLocalization.ui(stepCaption))
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ankyInkSoft)
                    .multilineTextAlignment(.center)

                Button(action: stepAction) {
                    Text(AnkyLocalization.ui(stepButtonTitle))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ThreadButtonStyle())
                .padding(.top, 6)

                if currentStep != .done {
                    Button(action: onDone) {
                        Text(AnkyLocalization.ui("later"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            viewModel.refresh()
        }
        #if os(iOS) && canImport(FamilyControls)
        .familyActivityPicker(
            headerText: "Pick the apps that pull you out of yourself.",
            footerText: "Anky will put a writing gate before them.",
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

}
