//
//  AxisWorldView.swift
//  Anky — the Axis Redesign (spec §1, §11).
//
//  The container of the vertical world: it renders whatever surface the
//  current AxisState.Phase calls for, with the Anchor overlaid above the
//  entire hierarchy at its fixed, eternal position. The registers switch here
//  — warm lazure for the human world, electric indigo only during the vigil.
//
//  Phase 1 note: the per-phase surfaces below are lazure scaffolds. Real
//  surfaces arrive in later phases — the strata (§2), the reveal keyboard-fall
//  (§3), the electric vigil (§4), the reflection descent (§5). The state
//  machine and the Anchor are permanent; only the surfaces get replaced.
//

import SwiftUI

struct AxisWorldView: View {
    @StateObject private var axis = AxisState()

    var body: some View {
        ZStack {
            register
                .ignoresSafeArea()

            surface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if axis.anchorIsVisible {
                AnchorView(axis: axis)
                    .zIndex(1000)
            }

            #if DEBUG
            DebugAxisStepper(axis: axis)
                .zIndex(2000)
            #endif
        }
        .environmentObject(axis)
        .preferredColorScheme(axis.isElectricRegister ? .dark : nil)
        .animation(.easeInOut(duration: 0.5), value: axis.isElectricRegister)
    }

    // MARK: - Register (the ground the world is painted on)

    @ViewBuilder
    private var register: some View {
        if axis.isElectricRegister {
            ElectricRegister()
        } else {
            LazureWall(mood: .dawn)
        }
    }

    // MARK: - Per-phase surface (scaffolds until later phases)

    @ViewBuilder
    private var surface: some View {
        switch axis.phase {
        case .writing:
            ScaffoldSurface(line: "the writing session lives here", detail: "keyboard up · fall silent to close the channel")
        case .channelClosed:
            ScaffoldSurface(line: "the channel is closed", detail: "hold the anchor to send · or walk away to keep the day")
        case .vigil:
            ScaffoldSurface(line: "the offering is carried", detail: "seven stations to the spiral ear", electric: true)
        case .reflection:
            ScaffoldSurface(line: "your words return, warmed", detail: "the reflection descends")
        case .landing:
            ScaffoldSurface(line: "your days, settled around the anchor", detail: "tap the anchor to write · scroll to remember")
        case .entryOpen:
            ScaffoldSurface(line: "a day, opened to read in full", detail: "copy · share · record live here")
        case .seed:
            ScaffoldSurface(line: "the seed", detail: "settings · subscription · the recovery phrase")
        }
    }
}

/// The electric register: the Geshtu interior as X-ray — deep indigo-black,
/// faint blue wood-grain density (spec §1, §10). Rendered fully in Phase 4;
/// this is the ground it sits on.
struct ElectricRegister: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.displayP3, red: 0.03, green: 0.04, blue: 0.10),
                Color(.displayP3, red: 0.05, green: 0.07, blue: 0.16),
                Color(.displayP3, red: 0.02, green: 0.03, blue: 0.08)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// A quiet lazure (or electric) placeholder for a phase whose real surface
/// arrives in a later phase. Deliberately spare — no chrome, in register.
private struct ScaffoldSurface: View {
    let line: String
    var detail: String = ""
    var electric: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            Text(line)
                .font(.fraunces(24, weight: .regular, italic: true))
                .foregroundStyle(electric ? Color(.displayP3, red: 0.70, green: 0.82, blue: 1.0) : Color.ankyInk)
                .multilineTextAlignment(.center)
            if !detail.isEmpty {
                Text(detail)
                    .font(.fraunces(14, weight: .light))
                    .foregroundStyle((electric ? Color.white : Color.ankyInkSoft).opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 160)
    }
}

#if DEBUG
/// Dev-only phase stepper so the whole machine is walkable while surfaces are
/// scaffolds (Phase 1). Removed in Phase 8.
private struct DebugAxisStepper: View {
    @ObservedObject var axis: AxisState

    private let order: [(String, AxisState.Phase)] = [
        ("write", .writing),
        ("closed", .channelClosed),
        ("vigil", .vigil),
        ("reflect", .reflection),
        ("land", .landing),
        ("entry", .entryOpen),
        ("seed", .seed)
    ]

    var body: some View {
        VStack {
            HStack(spacing: 6) {
                ForEach(order, id: \.0) { label, phase in
                    Button(label) { axis.debugSetPhase(phase) }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.vertical, 4).padding(.horizontal, 7)
                        .background(axis.phase == phase ? Color.ankyGold.opacity(0.9) : Color.ankyInk.opacity(0.35))
                        .foregroundStyle(axis.phase == phase ? Color.ankyInk : Color.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
            Spacer()
        }
    }
}
#endif
