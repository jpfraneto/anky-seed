import SwiftUI
import UIKit

@MainActor
final class AnkyTabBarCTAController: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var title = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isEnabled = true
    @Published private(set) var accentColor = TabBarCTAPalette.gold
    @Published private(set) var isScrollHidden = false
    @Published private(set) var streamTick = 0
    @Published fileprivate var tabBarFrame: CGRect = .zero
    private var action: (() -> Void)?

    func show(
        title: String,
        isLoading: Bool,
        isEnabled: Bool,
        accentColor: Color = TabBarCTAPalette.gold,
        streamTick: Int = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.accentColor = accentColor
        self.streamTick = streamTick
        self.action = action
        isPresented = true
    }

    func hide(resetScrollHidden: Bool = true) {
        isPresented = false
        if resetScrollHidden {
            isScrollHidden = false
        }
        action = nil
    }

    func setScrollHidden(_ isHidden: Bool) {
        guard isScrollHidden != isHidden else {
            return
        }
        isScrollHidden = isHidden
    }

    func perform() {
        guard isPresented, isEnabled, !isLoading else {
            return
        }
        action?()
    }
}

struct AnkyTabBarCTAOverlay: View {
    @ObservedObject var controller: AnkyTabBarCTAController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var chunkPulse = false

    var body: some View {
        GeometryReader { geometry in
            if controller.isPresented {
                let frame = overlayFrame(in: geometry)
                Button {
                    controller.perform()
                } label: {
                    ZStack {
                        if controller.isLoading && !reduceMotion {
                            AnkyThreadSweep()
                                .clipShape(Capsule())
                                .opacity(0.9)
                        }

                        Text(AnkyLocalization.ui(controller.title))
                            .font(.system(size: 22, weight: .medium, design: .serif))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        TabBarCTAPalette.paperBright,
                                        TabBarCTAPalette.gold
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(
                                color: TabBarCTAPalette.glowGold.opacity(controller.isLoading ? 0.65 : 0.45),
                                radius: controller.isLoading ? 12 : 8
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.66)
                    }
                    .padding(.horizontal, 22)
                    .frame(width: frame.width, height: frame.height)
                    .contentShape(Capsule())
                    .background {
                        ZStack {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            TabBarCTAPalette.purpleTop.opacity(0.95),
                                            TabBarCTAPalette.purpleBottom.opacity(0.98)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Capsule()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            TabBarCTAPalette.violetGlow.opacity(0.25),
                                            Color.clear
                                        ],
                                        center: .top,
                                        startRadius: 0,
                                        endRadius: controller.isLoading ? 130 : 120
                                    )
                                )
                                .opacity(controller.isLoading ? 1.44 : 1)

                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            TabBarCTAPalette.borderGold,
                                            TabBarCTAPalette.borderViolet,
                                            TabBarCTAPalette.borderGoldDeep
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: controller.isLoading ? 2.2 : 1.8
                                )

                            if controller.isLoading {
                                Capsule()
                                    .strokeBorder(
                                        TabBarCTAPalette.glowGold.opacity(chunkPulse ? 0.9 : 0.35),
                                        lineWidth: 2.5
                                    )
                                    .blur(radius: chunkPulse ? 5 : 2)
                            }

                            Capsule()
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                .blur(radius: 0.6)
                        }
                    }
                    .shadow(
                        color: TabBarCTAPalette.glowGold.opacity(controller.isLoading ? 0.38 : (isBreathing ? 0.35 : 0.18)),
                        radius: controller.isLoading ? 28 : (isBreathing ? 24 : 12)
                    )
                    .shadow(
                        color: TabBarCTAPalette.glowViolet.opacity(controller.isLoading ? 0.38 : (isBreathing ? 0.35 : 0.18)),
                        radius: controller.isLoading ? 38 : (isBreathing ? 34 : 18),
                        y: 8
                    )
                    .scaleEffect(isBreathing && (controller.isEnabled || controller.isLoading) ? 1.005 : 1.0)
                    .opacity(controller.isEnabled || controller.isLoading ? 1 : 0.52)
                }
                .buttonStyle(.plain)
                .opacity(controller.isScrollHidden ? 0 : 1)
                .position(
                    x: frame.midX,
                    y: frame.midY + (controller.isScrollHidden ? frame.height + 26 : 0)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .accessibilityLabel(controller.title)
                .accessibilityHint(controller.isLoading ? "Your reflection is being received." : "")
            }
        }
        .onAppear {
            isBreathing = true
        }
        .onChange(of: controller.streamTick) { _, _ in
            guard controller.isLoading, !reduceMotion else {
                return
            }

            withAnimation(.easeOut(duration: 0.12)) {
                chunkPulse = true
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.easeIn(duration: 0.28)) {
                    chunkPulse = false
                }
            }
        }
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: isBreathing)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: controller.isPresented)
        .animation(.easeInOut(duration: 0.28), value: controller.isScrollHidden)
        .allowsHitTesting(controller.isPresented && !controller.isScrollHidden && controller.isEnabled && !controller.isLoading)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func overlayFrame(in geometry: GeometryProxy) -> CGRect {
        let measuredFrame = controller.tabBarFrame
        let fallbackWidth = min(max(0, geometry.size.width - 88), 360)
        let measuredWidth = measuredFrame.width > 0 ? measuredFrame.width : fallbackWidth
        let measuredHeight = measuredFrame.height > 0 ? measuredFrame.height : 74
        let width = min(max(measuredWidth, fallbackWidth), geometry.size.width - 40)
        let height = max(66, min(measuredHeight, 84))

        return CGRect(
            x: (geometry.size.width - width) / 2,
            y: geometry.size.height - height - 18,
            width: width,
            height: height
        )
    }

}

private struct AnkyThreadSweep: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let duration = 1.65
                let rawProgress = time.truncatingRemainder(dividingBy: duration) / duration
                let progress = CGFloat(rawProgress)

                let centerX = progress * (size.width + 180) - 90
                let midY = size.height * 0.52
                let amplitude = size.height * 0.09

                var path = Path()
                let startX = max(0, centerX - 120)
                let endX = min(size.width, centerX + 120)

                guard endX > startX else {
                    return
                }

                path.move(to: CGPoint(x: startX, y: midY))

                var x = startX
                while x <= endX {
                    let local = (x - centerX) / 120
                    let y = midY + sin(local * .pi * 3.2) * amplitude
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 4
                }

                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.clear,
                            TabBarCTAPalette.borderGold.opacity(0.9),
                            TabBarCTAPalette.glowGold,
                            Color.clear
                        ]),
                        startPoint: CGPoint(x: startX, y: midY),
                        endPoint: CGPoint(x: endX, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                )

                let orbRect = CGRect(
                    x: centerX - 5,
                    y: midY - 5,
                    width: 10,
                    height: 10
                )

                context.fill(
                    Path(ellipseIn: orbRect),
                    with: .color(TabBarCTAPalette.paperBright.opacity(0.95))
                )
            }
        }
        .blendMode(.screen)
    }
}

struct AnkyTabBarFrameReader: UIViewControllerRepresentable {
    @ObservedObject var controller: AnkyTabBarCTAController

    func makeUIViewController(context: Context) -> ReaderViewController {
        ReaderViewController(controller: controller)
    }

    func updateUIViewController(_ viewController: ReaderViewController, context: Context) {
        viewController.controller = controller
        viewController.updateFrame()
    }

    final class ReaderViewController: UIViewController {
        weak var controller: AnkyTabBarCTAController?

        init(controller: AnkyTabBarCTAController) {
            self.controller = controller
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            updateFrame()
        }

        func updateFrame() {
            guard let window = view.window,
                  let tabBar = findTabBarController(in: window.rootViewController)?.tabBar,
                  let tabWindow = tabBar.window else {
                return
            }

            let targetAlpha: CGFloat = controller?.isPresented == true || controller?.isScrollHidden == true ? 0 : 1
            if abs(tabBar.alpha - targetAlpha) > 0.01 {
                UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                    tabBar.alpha = targetAlpha
                }
            }
            let frame = visualFrame(for: tabBar, in: tabWindow)
            guard frame != controller?.tabBarFrame else {
                return
            }

            Task { @MainActor in
                controller?.tabBarFrame = frame
            }
        }

        private func findTabBarController(in controller: UIViewController?) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }

            if let navigationController = controller as? UINavigationController {
                return findTabBarController(in: navigationController.visibleViewController)
            }

            for child in controller?.children ?? [] {
                if let tabBarController = findTabBarController(in: child) {
                    return tabBarController
                }
            }

            if let presentedViewController = controller?.presentedViewController {
                return findTabBarController(in: presentedViewController)
            }

            return nil
        }

        private func visualFrame(for tabBar: UITabBar, in window: UIWindow) -> CGRect {
            let controlFrames = interactiveControlFrames(in: tabBar).map { frame in
                tabBar.convert(frame, to: window)
            }

            guard let firstFrame = controlFrames.first else {
                return tabBar.convert(tabBar.bounds, to: window)
            }

            let controlsUnion = controlFrames.dropFirst().reduce(firstFrame) { partialResult, frame in
                partialResult.union(frame)
            }
            let paddedFrame = controlsUnion.insetBy(dx: -18, dy: -8)
            let tabBarFrame = tabBar.convert(tabBar.bounds, to: window)
            return paddedFrame.intersection(tabBarFrame)
        }

        private func interactiveControlFrames(in root: UIView) -> [CGRect] {
            var frames = [CGRect]()

            func collect(from view: UIView) {
                guard !view.isHidden, view.alpha > 0.01 else {
                    return
                }

                if view is UIControl, view.bounds.width > 20, view.bounds.height > 20 {
                    frames.append(view.convert(view.bounds, to: root))
                }

                view.subviews.forEach(collect)
            }

            root.subviews.forEach(collect)
            return frames
        }
    }
}

private enum TabBarCTAPalette {
    static let purpleTop = Color(red: 74 / 255, green: 23 / 255, blue: 106 / 255)
    static let purpleBottom = Color(red: 37 / 255, green: 8 / 255, blue: 52 / 255)
    static let violetGlow = Color(red: 156 / 255, green: 92 / 255, blue: 255 / 255)
    static let glowViolet = Color(red: 127 / 255, green: 57 / 255, blue: 255 / 255)
    static let glowGold = Color(red: 255 / 255, green: 184 / 255, blue: 77 / 255)
    static let borderGold = Color(red: 255 / 255, green: 231 / 255, blue: 163 / 255)
    static let borderViolet = Color(red: 182 / 255, green: 104 / 255, blue: 255 / 255)
    static let borderGoldDeep = Color(red: 255 / 255, green: 202 / 255, blue: 100 / 255)
    static let gold = Color(red: 255 / 255, green: 211 / 255, blue: 122 / 255)
    static let paperBright = Color(red: 255 / 255, green: 246 / 255, blue: 213 / 255)
}
