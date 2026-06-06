import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct AnkyOnboardingView: View {
    let startWriting: () -> Void

    @State private var page = 0

    private let imageNames = [
        "onboarding-1",
        "onboarding-2",
        "onboarding-3"
    ]

    private let lines = [
        "You don't need another prompt.",
        "Write forward. 8 seconds of silence ends it.",
        "Tell me who you are."
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TabView(selection: $page) {
                    ForEach(imageNames.indices, id: \.self) { index in
                        ZStack {
                            Image(imageNames[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()

                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.18),
                                    Color.black.opacity(0.02),
                                    Color.black.opacity(0.34),
                                    Color.black.opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    Text(lines[page])
                        .font(.system(size: 27, weight: .medium, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(hex: "FFF6D5"),
                                    Color(hex: "FFD37A")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.black.opacity(0.72), radius: 16, x: 0, y: 8)
                        .shadow(color: Color(hex: "FFB84D").opacity(0.24), radius: 10, x: 0, y: 0)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 28)
                        .animation(.easeInOut(duration: 0.25), value: page)

                    AnkyOnboardingFooter(page: $page, startWriting: startWriting)
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

struct AnkyCTAButton: View {
    let title: String
    var action: () -> Void

    @State private var isBreathing = false

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif

            action()
        } label: {
            Text(title)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "FFF6D5"),
                            Color(hex: "FFD37A")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(hex: "FFB84D").opacity(0.45), radius: 8, x: 0, y: 0)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 74)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "4A176A").opacity(0.95),
                                Color(hex: "250834").opacity(0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "9C5CFF").opacity(0.25),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )

                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(hex: "FFE7A3"),
                                Color(hex: "B668FF"),
                                Color(hex: "FFCA64")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.8
                    )

                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    .blur(radius: 0.6)
            }
        }
        .shadow(
            color: Color(hex: "FFB84D").opacity(isBreathing ? 0.35 : 0.18),
            radius: isBreathing ? 24 : 12,
            x: 0,
            y: 0
        )
        .shadow(
            color: Color(hex: "7F39FF").opacity(isBreathing ? 0.35 : 0.18),
            radius: isBreathing ? 34 : 18,
            x: 0,
            y: 8
        )
        .scaleEffect(isBreathing ? 1.005 : 1.0)
        .animation(
            .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
            value: isBreathing
        )
        .onAppear {
            isBreathing = true
        }
        .padding(.horizontal, 28)
    }
}

struct AnkyOnboardingDots: View {
    let currentIndex: Int
    let total: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(
                        index == currentIndex
                        ? Color(hex: "FFD37A")
                        : Color(hex: "7A5A9A").opacity(0.55)
                    )
                    .frame(width: index == currentIndex ? 10 : 8,
                           height: index == currentIndex ? 10 : 8)
                    .shadow(
                        color: index == currentIndex
                        ? Color(hex: "FFB84D").opacity(0.7)
                        : .clear,
                        radius: 8
                    )
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
            }
        }
        .padding(.top, 18)
    }
}

struct AnkyOnboardingFooter: View {
    @Binding var page: Int
    let startWriting: () -> Void

    private let ctas = [
        "Be with what is here",
        "No backspace. Just write.",
        "Write 8 minutes"
    ]

    var body: some View {
        VStack(spacing: 0) {
            AnkyCTAButton(title: ctas[page]) {
                if page < 2 {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        page += 1
                    }
                } else {
                    startWriting()
                }
            }

            AnkyOnboardingDots(currentIndex: page, total: 3)
        }
        .padding(.bottom, 34)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64

        switch hex.count {
        case 6:
            r = (int >> 16) & 0xFF
            g = (int >> 8) & 0xFF
            b = int & 0xFF
        default:
            r = 255
            g = 255
            b = 255
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
