import SwiftUI
import UIKit

/// The small material vocabulary of the writing machine. It deliberately stays
/// close to pale beech and fired clay so the wood reads as manufactured, not as
/// a theme pasted over the app.
enum GeshtuWoodPalette {
    static let light = Color(.displayP3, red: 0.84, green: 0.75, blue: 0.64)
    static let mid = Color(.displayP3, red: 0.74, green: 0.63, blue: 0.52)
    static let deep = Color(.displayP3, red: 0.61, green: 0.51, blue: 0.42)
    static let detail = Color(.displayP3, red: 0.29, green: 0.24, blue: 0.21)
    static let labelInk = Color(.displayP3, red: 0.12, green: 0.09, blue: 0.07)
    static let highlight = Color(.displayP3, red: 0.95, green: 0.89, blue: 0.81)
}

/// Procedural wood: a soft directional wash and a handful of stable, imperfect
/// fibres. There is no bitmap to scale, shimmer, or make the controls feel fake.
struct GeshtuWoodMaterial: View {
    var grainOpacity: Double = 0.035

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    GeshtuWoodPalette.light,
                    GeshtuWoodPalette.mid,
                    GeshtuWoodPalette.deep.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [GeshtuWoodPalette.highlight.opacity(0.24), .clear],
                center: UnitPoint(x: 0.20, y: 0.04),
                startRadius: 0,
                endRadius: 180
            )

            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }

                var random = LazureSeededRandom(seed: 1938)
                let spacing = max(13, size.height / 4)
                var y: CGFloat = -spacing

                while y < size.height + spacing {
                    let amplitude = 0.8 + random.next() * 1.7
                    let phase = random.next() * .pi * 2
                    var fibre = Path()
                    fibre.move(to: CGPoint(x: -8, y: y))

                    let segments = max(3, Int(size.width / 28))
                    for segment in 0...segments {
                        let x = CGFloat(segment) / CGFloat(segments) * (size.width + 16) - 8
                        let wave = sin(CGFloat(segment) * 0.92 + phase) * amplitude
                        fibre.addLine(to: CGPoint(x: x, y: y + wave))
                    }

                    context.stroke(
                        fibre,
                        with: .color(GeshtuWoodPalette.detail.opacity(grainOpacity)),
                        style: StrokeStyle(lineWidth: 0.55, lineCap: .round)
                    )
                    y += spacing + (random.next() - 0.5) * 3
                }
            }
            .blendMode(.multiply)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The luminous display is the low point in the object. Soft side falloff and
/// a shallow upper recess establish depth without drawing a card around the page.
struct GeshtuWritingSurface: View {
    let progress: Double

    var body: some View {
        let settledLight = min(1, max(0, progress))

        ZStack {
            Color.ankyPaper

            // A warm display, not a moving illustration. Over the ritual the
            // rose settles almost imperceptibly toward cream, once per minute.
            LinearGradient(
                colors: [
                    Color.ankyPaper,
                    Color.ankyRose.opacity(0.15 - settledLight * 0.04),
                    Color.ankyPaperDeep.opacity(0.46)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.20 + settledLight * 0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.78, y: 0.14),
                startRadius: 0,
                endRadius: 410
            )

            RadialGradient(
                colors: [Color.ankyRose.opacity(0.075), .clear],
                center: UnitPoint(x: 0.18, y: 0.82),
                startRadius: 0,
                endRadius: 480
            )

            PaperGrain()
                .opacity(0.32)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [GeshtuWoodPalette.detail.opacity(0.085), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 7)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.clear, GeshtuWoodPalette.detail.opacity(0.075)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 7)
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [GeshtuWoodPalette.detail.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 11)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GeshtuRaisedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed && !reduceMotion ? 1.25 : 0)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .shadow(
                color: GeshtuWoodPalette.detail.opacity(configuration.isPressed ? 0.10 : 0.19),
                radius: configuration.isPressed ? 0.8 : 2.2,
                y: configuration.isPressed ? 0.4 : 1.8
            )
            .animation(
                reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.15, dampingFraction: 0.76),
                value: configuration.isPressed
            )
    }
}

private struct GeshtuMenuControlFace: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(GeshtuWoodPalette.deep.opacity(0.44))
                .frame(width: 48, height: 48)

            Circle()
                .fill(GeshtuWoodPalette.mid)
                .overlay(GeshtuWoodMaterial(grainOpacity: 0.040).clipShape(Circle()))
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [GeshtuWoodPalette.highlight.opacity(0.72), GeshtuWoodPalette.detail.opacity(0.22)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                }
                .frame(width: 42, height: 42)

            // Two-tone engraving: the dim upper cut and the hair of reflected
            // light below it are enough to read as carved at screenshot scale.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GeshtuWoodPalette.highlight.opacity(0.24))
                .offset(y: 0.8)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GeshtuWoodPalette.detail.opacity(0.78))
                .offset(y: -0.35)
        }
        .frame(width: 48, height: 48)
        .contentShape(Circle())
    }
}

/// A real menu, rather than a newly-permitted escape from an active session.
/// The settings action is always safe; putting the machine down remains present
/// only while the existing writing rules allow it.
struct GeshtuMenuButton: View {
    let canPutDown: Bool
    let onPutDown: () -> Void
    let onOpenSettings: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Menu {
            Button(action: onOpenSettings) {
                Label(
                    AnkyLocalization.ui("Writing settings"),
                    systemImage: "slider.horizontal.3"
                )
            }

            if canPutDown {
                Button(action: onPutDown) {
                    Label(
                        AnkyLocalization.ui("Put down writing machine"),
                        systemImage: "chevron.down"
                    )
                }
            }
        } label: {
            GeshtuMenuControlFace()
                .scaleEffect(isPressed ? 0.97 : 1)
                .offset(y: isPressed && !reduceMotion ? 1.25 : 0)
                .brightness(isPressed ? -0.035 : 0)
                .shadow(
                    color: GeshtuWoodPalette.detail.opacity(isPressed ? 0.10 : 0.19),
                    radius: isPressed ? 0.8 : 2.2,
                    y: isPressed ? 0.4 : 1.8
                )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, pressed, _ in pressed = true }
        )
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.15, dampingFraction: 0.76),
            value: isPressed
        )
        .accessibilityLabel(AnkyLocalization.ui("Writing machine menu"))
        .accessibilityHint(canPutDown
            ? AnkyLocalization.ui("Writing settings or put down the machine")
            : AnkyLocalization.ui("Writing settings"))
    }
}

/// The session's primary control: a quiet wooden puck with a recessed progress
/// groove. It opens the same settings sheet the former text-only timer opened.
struct GeshtuTimerDial: View {
    let timeText: String
    let caption: String
    let progress: Double
    let action: () -> Void

    var body: some View {
        let localizedCaption = AnkyLocalization.ui(caption)

        Button(action: action) {
            ZStack {
                Circle()
                    .fill(GeshtuWoodPalette.deep.opacity(0.46))
                    .frame(width: 82, height: 82)

                Circle()
                    .fill(GeshtuWoodPalette.mid)
                    .overlay(GeshtuWoodMaterial(grainOpacity: 0.035).clipShape(Circle()))
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [GeshtuWoodPalette.highlight.opacity(0.80), GeshtuWoodPalette.detail.opacity(0.30)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    }
                    .frame(width: 76, height: 76)

                Circle()
                    .stroke(GeshtuWoodPalette.detail.opacity(0.18), lineWidth: 1.2)
                    .frame(width: 66, height: 66)

                Circle()
                    .trim(from: 0, to: max(0.006, min(1, progress)))
                    .stroke(
                        GeshtuWoodPalette.detail.opacity(0.52),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 66, height: 66)

                Capsule()
                    .fill(GeshtuWoodPalette.detail.opacity(0.72))
                    .frame(width: 1.5, height: 5)
                    .offset(y: -34.5)

                VStack(spacing: -1) {
                    Text(timeText)
                        .font(.system(.title2, design: .serif, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(GeshtuWoodPalette.detail.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .contentTransition(.numericText())
                    Text(localizedCaption)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(GeshtuWoodPalette.labelInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .dynamicTypeSize(.xSmall ... .accessibility1)
            }
            .frame(width: 82, height: 82)
            .contentShape(Circle())
        }
        .buttonStyle(GeshtuRaisedButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AnkyLocalization.ui("Writing time %@", "\(timeText) \(localizedCaption)"))
        .accessibilityHint(AnkyLocalization.ui("Opens writing settings"))
    }
}

/// A full-width lower chassis. Its only content is Anky's engraved spiral; the
/// restraint is what keeps this from turning into a generic keyboard toolbar.
struct GeshtuKeyboardDock: View {
    static let height: CGFloat = 54

    var body: some View {
        ZStack {
            GeshtuTopRoundedRectangle(radius: 11)
                .fill(GeshtuWoodPalette.mid)
                .overlay(
                    GeshtuWoodMaterial(grainOpacity: 0.026)
                        .clipShape(GeshtuTopRoundedRectangle(radius: 11))
                )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(GeshtuWoodPalette.highlight.opacity(0.70))
                    .frame(height: 1)
                Rectangle()
                    .fill(GeshtuWoodPalette.detail.opacity(0.22))
                    .frame(height: 1)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, GeshtuWoodPalette.detail.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5)
            }
            .clipShape(GeshtuTopRoundedRectangle(radius: 11))

            HStack {
                GeshtuDockMortise()
                Spacer(minLength: 0)
                ZStack {
                    AnchorSpiral()
                        .stroke(GeshtuWoodPalette.highlight.opacity(0.30), lineWidth: 1.1)
                        .offset(y: 0.8)
                    AnchorSpiral()
                        .stroke(GeshtuWoodPalette.detail.opacity(0.58), lineWidth: 1.1)
                        .offset(y: -0.3)
                }
                .frame(width: 19, height: 19)
                Spacer(minLength: 0)
                GeshtuDockMortise()
            }
            .padding(.horizontal, 27)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .shadow(color: GeshtuWoodPalette.detail.opacity(0.14), radius: 1.5, y: 1.5)
        .accessibilityHidden(true)
    }
}

private struct GeshtuDockMortise: View {
    var body: some View {
        Capsule()
            .fill(GeshtuWoodPalette.detail.opacity(0.22))
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(GeshtuWoodPalette.highlight.opacity(0.28))
                    .frame(height: 0.7)
            }
            .frame(width: 20, height: 3)
    }
}

private struct GeshtuTopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// UIKit owns the accessory so it follows interactive keyboard motion exactly.
/// The SwiftUI dock is mounted once and retained for the life of the text view;
/// ticker updates never replace either object or touch keyboard composition.
final class GeshtuKeyboardAccessoryView: UIInputView {
    private let host: UIHostingController<GeshtuKeyboardDock>

    init() {
        host = UIHostingController(rootView: GeshtuKeyboardDock())
        super.init(
            frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: GeshtuKeyboardDock.height),
            inputViewStyle: .keyboard
        )

        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        clipsToBounds = false

        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: GeshtuKeyboardDock.height)
    }
}
