import SwiftUI
import UIKit

struct AnkyPresenceOverlay: View {
    let defaultSequence: AnkySequenceName

    @AppStorage("ankyPresenceX") private var storedX = -1.0
    @AppStorage("ankyPresenceY") private var storedY = -1.0
    @State private var isVisible = true
    @State private var dragStart: CGPoint?
    @State private var breathing = false
    @State private var showMenu = false
    @State private var sequence: AnkySequenceName
    @State private var keyboardHeight: CGFloat = 0

    init(defaultSequence: AnkySequenceName = .idleFront) {
        self.defaultSequence = defaultSequence
        _sequence = State(initialValue: defaultSequence)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = presenceSize(for: geometry.size)
            let point = resolvedPoint(in: geometry.size, presenceSize: size)

            ZStack {
                AnkyWitnessView(mood: .warm, size: .companion, sequence: sequence)
                    .frame(width: size, height: size)
                    .scaleEffect(isVisible ? (breathing ? 1.025 : 0.985) : 0.86)
                    .opacity(isVisible ? 1 : 0)

                Image("AnkySigil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .scaleEffect(isVisible ? 0.72 : 1)
                    .opacity(isVisible ? 0 : 1)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .position(point)
            .gesture(dragGesture(in: geometry.size, presenceSize: size))
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isVisible.toggle()
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
                Button("Move Anky home") {
                    resetPosition(in: geometry.size, presenceSize: size)
                }
                Button("Change motion") {
                    sequence = sequence.next
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isVisible ? "drag anky anywhere" : "tap the sigil to bring anky back")
            }
            .onAppear {
                breathing = true
                sequence = defaultSequence
                if storedX < 0 || storedY < 0 {
                    resetPosition(in: geometry.size, presenceSize: size)
                }
            }
            .onChange(of: defaultSequence) { newSequence in
                sequence = newSequence
            }
            .onChange(of: keyboardHeight) { _ in
                let clamped = clamp(
                    resolvedPoint(in: geometry.size, presenceSize: size),
                    in: geometry.size,
                    presenceSize: size
                )
                storedX = clamped.x
                storedY = clamped.y
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

    private func dragGesture(in containerSize: CGSize, presenceSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = resolvedPoint(in: containerSize, presenceSize: presenceSize)
                }

                guard let dragStart else {
                    return
                }

                let next = clamp(
                    CGPoint(
                        x: dragStart.x + value.translation.width,
                        y: dragStart.y + value.translation.height
                    ),
                    in: containerSize,
                    presenceSize: presenceSize
                )

                storedX = next.x
                storedY = next.y
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private func resolvedPoint(in containerSize: CGSize, presenceSize: CGFloat) -> CGPoint {
        let fallback = defaultPoint(in: containerSize, presenceSize: presenceSize)
        let point = CGPoint(
            x: storedX < 0 ? fallback.x : storedX,
            y: storedY < 0 ? fallback.y : storedY
        )

        return clamp(point, in: containerSize, presenceSize: presenceSize)
    }

    private func resetPosition(in containerSize: CGSize, presenceSize: CGFloat) {
        let point = defaultPoint(in: containerSize, presenceSize: presenceSize)
        storedX = point.x
        storedY = point.y
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func defaultPoint(in containerSize: CGSize, presenceSize: CGFloat) -> CGPoint {
        CGPoint(
            x: max(presenceSize / 2 + 12, containerSize.width - presenceSize / 2 - 20),
            y: max(presenceSize / 2 + 12, containerSize.height - keyboardHeight - presenceSize / 2 - 110)
        )
    }

    private func clamp(_ point: CGPoint, in containerSize: CGSize, presenceSize: CGFloat) -> CGPoint {
        let radius = presenceSize / 2
        let bottomLimit = max(radius + 8, containerSize.height - keyboardHeight - radius - 12)
        return CGPoint(
            x: min(max(point.x, radius + 8), max(radius + 8, containerSize.width - radius - 8)),
            y: min(max(point.y, radius + 8), bottomLimit)
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
