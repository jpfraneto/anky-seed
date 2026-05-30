import SwiftUI
import UIKit

struct AnkyPresenceOverlay: View {
    @ObservedObject var companion: AnkyCompanionStore
    let defaultSequence: AnkySequenceName
    let goldenGlow: Bool
    let transformToSigil: Bool
    let onTap: (() -> Bool)?

    @State private var isVisible = true
    @State private var breathing = false
    @State private var showMenu = false
    @State private var sequence: AnkySequenceName
    @State private var keyboardHeight: CGFloat = 0

    init(
        companion: AnkyCompanionStore,
        defaultSequence: AnkySequenceName = .idleFront,
        goldenGlow: Bool = false,
        transformToSigil: Bool = false,
        onTap: (() -> Bool)? = nil
    ) {
        self.companion = companion
        self.defaultSequence = defaultSequence
        self.goldenGlow = goldenGlow
        self.transformToSigil = transformToSigil
        self.onTap = onTap
        _sequence = State(initialValue: defaultSequence)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = presenceSize(for: geometry.size)
            let point = resolvedPoint(in: geometry.size, presenceSize: size)
            let effectiveSequence = companion.sequenceOverride ?? sequence

            ZStack {
                if let bubble = companion.bubble {
                    VStack {
                        Spacer()

                        AnkyBubbleView(
                            bubble: bubble,
                            close: {
                                companion.hideBubble()
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 8 : 18)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(2)
                }

                ZStack {
                    if showsCompanion && goldenGlow {
                        TimelineView(.animation) { timeline in
                            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 3.0) + 1) / 2
                            Circle()
                                .fill(AnkyTheme.gold.opacity(0.12 + pulse * 0.08))
                                .frame(width: size * 1.18, height: size * 1.18)
                                .blur(radius: 7 + pulse * 4)
                        }
                        .transition(.opacity)
                    }

                    AnkyWitnessView(mood: companion.mood.witnessMood, size: .companion, sequence: effectiveSequence)
                        .frame(width: size, height: size)
                        .scaleEffect(showsCompanion ? (breathing ? 1.025 : 0.985) : 0.86)
                        .opacity(showsCompanion ? 1 : 0)

                    Image("AnkySigil")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .scaleEffect(showsCompanion ? 0.72 : 1)
                        .opacity(showsCompanion ? 0 : 1)
                }
                    .frame(width: size, height: size)
                    .animation(.easeInOut(duration: 0.4), value: goldenGlow)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: transformToSigil)
                    .contentShape(Circle())
                    .position(point)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if onTap?() == true {
                            return
                        }
                    }
                    .onLongPressGesture(minimumDuration: 3) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showMenu = true
                    }
                    .confirmationDialog("Anky", isPresented: $showMenu, titleVisibility: .visible) {
                        if isVisible {
                            Button("Keep Anky here") {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            Button("Hide Anky") {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                    isVisible = false
                                }
                            }
                        } else {
                            Button("Show Anky") {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                    isVisible = true
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        Button("Change motion") {
                            sequence = sequence.next
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(isVisible ? "anky stays beside the writing" : "tap the sigil to bring anky back")
                    }
                    .zIndex(3)
            }
            .onAppear {
                breathing = true
                sequence = defaultSequence
            }
            .onChange(of: defaultSequence) { _, newSequence in
                sequence = newSequence
            }
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathing)
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardHeight = keyboardOverlap(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .ignoresSafeArea(.keyboard)
    }

    private var showsCompanion: Bool {
        isVisible && !transformToSigil
    }

    private func resolvedPoint(in containerSize: CGSize, presenceSize: CGFloat) -> CGPoint {
        clamp(defaultPoint(in: containerSize, presenceSize: presenceSize), in: containerSize, presenceSize: presenceSize)
    }

    private func defaultPoint(in containerSize: CGSize, presenceSize: CGFloat) -> CGPoint {
        CGPoint(
            x: containerSize.width - presenceSize / 2 - 20,
            y: containerSize.height / 2
        )
    }

    private func clamp(_ point: CGPoint, in containerSize: CGSize, presenceSize: CGFloat) -> CGPoint {
        let radius = presenceSize / 2
        return CGPoint(
            x: min(max(point.x, radius + 8), max(radius + 8, containerSize.width - radius - 8)),
            y: min(max(point.y, radius + 8), max(radius + 8, containerSize.height - radius - 8))
        )
    }

    private func presenceSize(for containerSize: CGSize) -> CGFloat {
        max(76, min(96, containerSize.width * 0.22))
    }

    private func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }

        return max(0, UIScreen.main.bounds.maxY - frame.minY)
    }
}
