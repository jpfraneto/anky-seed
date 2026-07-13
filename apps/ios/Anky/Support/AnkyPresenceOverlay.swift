import SwiftUI
import UIKit

enum AnkyPresencePlacement: Equatable {
    case trailingCenter
    case topTrailing
    /// The writing surface once words are flowing: the companion drifts to
    /// the top-left corner — the spot the back button vacates — and stays
    /// there in true form, witnessing (feedback 2026-07-08).
    case topLeading
}

enum AnkyBubblePlacement: Equatable {
    case top
    case bottom
}

struct AnkyPresenceOverlay: View {
    @ObservedObject var companion: AnkyCompanionStore
    let defaultSequence: AnkySequenceName
    let goldenGlow: Bool
    let transformToSigil: Bool
    let showsPresence: Bool
    let placement: AnkyPresencePlacement
    let bubblePlacement: AnkyBubblePlacement

    @State private var isVisible = true
    @State private var revealsThreadingCompanion = false
    @State private var breathing = false
    @State private var sequence: AnkySequenceName
    @State private var keyboardHeight: CGFloat = 0
    @State private var storedPoint: CGPoint?
    @GestureState private var dragTranslation: CGSize = .zero

    init(
        companion: AnkyCompanionStore,
        defaultSequence: AnkySequenceName = .idleFront,
        goldenGlow: Bool = false,
        transformToSigil: Bool = false,
        showsPresence: Bool = true,
        placement: AnkyPresencePlacement = .trailingCenter,
        bubblePlacement: AnkyBubblePlacement = .bottom
    ) {
        self.companion = companion
        self.defaultSequence = defaultSequence
        self.goldenGlow = goldenGlow
        self.transformToSigil = transformToSigil
        self.showsPresence = showsPresence
        self.placement = placement
        self.bubblePlacement = bubblePlacement
        _sequence = State(initialValue: defaultSequence)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = presenceSize(for: geometry.size)
            let point = resolvedPoint(in: geometry, presenceSize: size)
            let draggedPoint = clamp(
                CGPoint(x: point.x + dragTranslation.width, y: point.y + dragTranslation.height),
                in: geometry.size,
                presenceSize: size
            )
            let effectiveSequence = companion.sequenceOverride ?? sequence

            ZStack {
                if let bubble = companion.bubble {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissBubble(bubble)
                        }
                        .zIndex(1)

                    bubbleView(bubble)
                        .zIndex(2)
                }

                if showsPresence {
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
                            .scaleEffect(showsCompanion ? (breathing ? 1.018 : 0.992) : 0.82)
                            // The breath animates ONLY this scale. Attached any
                            // higher, the repeatForever transaction captures the
                            // companion's .position too and he bobs across the
                            // screen forever.
                            .animation(
                                .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                                value: breathing
                            )
                            .opacity(showsCompanion ? 1 : 0)

                        Image("AnkySigil")
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .scaleEffect(showsCompanion ? 0.78 : 1)
                            .opacity(showsCompanion ? 0 : 1)
                    }
                        .frame(width: size, height: size)
                        .animation(.easeInOut(duration: 0.8), value: goldenGlow)
                        .animation(.easeInOut(duration: 1.15), value: transformToSigil)
                        .animation(.easeInOut(duration: 0.85), value: revealsThreadingCompanion)
                        .contentShape(Circle())
                        .position(draggedPoint)
                        // The move between corners is a slow drift, never a
                        // teleport. Scoped to placement changes only — a
                        // repeatForever must never live at this level.
                        .animation(.easeInOut(duration: 1.5), value: placement)
                        .onTapGesture {
                            AnkyHaptics.light()
                            withAnimation(.easeInOut(duration: transformToSigil ? 0.85 : 0.34)) {
                                if transformToSigil {
                                    revealsThreadingCompanion.toggle()
                                } else {
                                    isVisible.toggle()
                                }
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 3)
                                .updating($dragTranslation) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    storedPoint = clamp(
                                        CGPoint(x: point.x + value.translation.width, y: point.y + value.translation.height),
                                        in: geometry.size,
                                        presenceSize: size
                                    )
                                }
                        )
                        .zIndex(3)
                }
            }
            .onAppear {
                breathing = true
                sequence = defaultSequence
            }
            .onChange(of: defaultSequence) { newSequence in
                sequence = newSequence
            }
            .onChange(of: placement) { _ in
                storedPoint = nil
            }
            .onChange(of: transformToSigil) { shouldTransform in
                if shouldTransform {
                    revealsThreadingCompanion = false
                    isVisible = true
                }
            }
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
        isVisible && (!transformToSigil || revealsThreadingCompanion)
    }

    private func resolvedPoint(in geometry: GeometryProxy, presenceSize: CGFloat) -> CGPoint {
        clamp(
            storedPoint ?? defaultPoint(in: geometry, presenceSize: presenceSize),
            in: geometry.size,
            presenceSize: presenceSize
        )
    }

    private func defaultPoint(in geometry: GeometryProxy, presenceSize: CGFloat) -> CGPoint {
        let containerSize = geometry.size
        switch placement {
        case .topTrailing:
            return CGPoint(
                x: containerSize.width - presenceSize / 2 - 16,
                y: geometry.safeAreaInsets.top + presenceSize / 2 + 10
            )
        case .topLeading:
            return CGPoint(
                x: presenceSize / 2 + 16,
                y: geometry.safeAreaInsets.top + presenceSize / 2 + 10
            )
        case .trailingCenter:
            return CGPoint(
                x: containerSize.width - presenceSize / 2 - 20,
                y: containerSize.height / 2
            )
        }
    }

    @ViewBuilder
    private func bubbleView(_ bubble: AnkyBubble) -> some View {
        switch bubblePlacement {
        case .top:
            VStack {
                AnkyBubbleView(
                    bubble: bubble,
                    close: {
                        dismissBubble(bubble)
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        case .bottom:
            VStack {
                Spacer()

                AnkyBubbleView(
                    bubble: bubble,
                    close: {
                        dismissBubble(bubble)
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 8 : 18)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func dismissBubble(_ bubble: AnkyBubble) {
        if let close = bubble.close {
            close()
        } else {
            companion.hideBubble()
        }
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
