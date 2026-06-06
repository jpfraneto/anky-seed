import SwiftUI

struct AnkyReflectionCreditsSheet: View {
    let availableCredits: Int?
    let packs: [RevenueCatCreditPackage]
    let isRefreshing: Bool
    let purchasingPackId: String?
    let onRefresh: () -> Void
    let onSelectPack: (RevenueCatCreditPackage) -> Void

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                dragHandle
                    .padding(.top, 10)
                    .padding(.bottom, 20)

                header
                    .padding(.horizontal, 24)

                availableCreditsCard
                    .padding(.horizontal, 24)
                    .padding(.top, 26)

                VStack(spacing: 12) {
                    if packs.isEmpty {
                        AnkyReflectionCreditEmptyRow(text: isRefreshing ? "loading credit packs" : "no credit packs available")
                    } else {
                        ForEach(packs.prefix(3)) { pack in
                            AnkyReflectionCreditPackRow(
                                pack: pack,
                                isRecommended: isRecommended(pack),
                                isPurchasing: purchasingPackId == pack.id
                            ) {
                                onSelectPack(pack)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                footer
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 610)
            .background(sheetBackground)
            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .overlay(sheetBorder)
            .shadow(color: Color.black.opacity(0.55), radius: 40, x: 0, y: -10)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.42))
            .frame(width: 42, height: 5)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sparkle")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(AnkyReflectionCreditsPalette.gold)

            VStack(alignment: .leading, spacing: 6) {
                Text("Anky reflection credits")
                    .font(.system(size: 34, weight: .medium, design: .serif))
                    .foregroundStyle(AnkyReflectionCreditsPalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("Your space to be seen, held, and mirrored.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AnkyReflectionCreditsPalette.cream.opacity(0.68))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onRefresh()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(AnkyReflectionCreditsPalette.gold.opacity(0.42), lineWidth: 1.2)
                        .background(
                            Circle()
                                .fill(AnkyReflectionCreditsPalette.purpleDeep.opacity(0.55))
                        )
                        .frame(width: 54, height: 54)

                    if isRefreshing {
                        ProgressView()
                            .tint(AnkyReflectionCreditsPalette.gold)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AnkyReflectionCreditsPalette.gold)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .accessibilityLabel("Refresh reflection credits")
        }
    }

    private var availableCreditsCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AnkyReflectionCreditsPalette.almostBlack.opacity(0.58))

            Image("credits-thread-background")
                .resizable()
                .scaledToFill()
                .opacity(0.72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            LinearGradient(
                colors: [
                    AnkyReflectionCreditsPalette.almostBlack.opacity(0.9),
                    AnkyReflectionCreditsPalette.almostBlack.opacity(0.38),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(alignment: .center, spacing: 22) {
                Text(availableCredits.map(String.init) ?? "...")
                    .font(.system(size: 72, weight: .bold, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AnkyReflectionCreditsPalette.cream,
                                AnkyReflectionCreditsPalette.gold
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: AnkyReflectionCreditsPalette.gold.opacity(0.35), radius: 14)
                    .minimumScaleFactor(0.62)

                Text("available\ncredits")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundStyle(AnkyReflectionCreditsPalette.cream.opacity(0.78))
                    .lineSpacing(4)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AnkyReflectionCreditsPalette.gold.opacity(0.45),
                            AnkyReflectionCreditsPalette.violet.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 13))
                .foregroundStyle(AnkyReflectionCreditsPalette.gold.opacity(0.78))

            Text("Writing is free. One credit = one reflection.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AnkyReflectionCreditsPalette.cream.opacity(0.68))
                .multilineTextAlignment(.center)

            Image(systemName: "sparkle")
                .font(.system(size: 13))
                .foregroundStyle(AnkyReflectionCreditsPalette.gold.opacity(0.78))
        }
        .frame(maxWidth: .infinity)
    }

    private var sheetBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hexString: "1A0D28"),
                    Color(hexString: "080610"),
                    Color(hexString: "05040B")
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color(hexString: "6D35A8").opacity(0.28),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    AnkyReflectionCreditsPalette.gold.opacity(0.08),
                    Color.clear
                ],
                center: .bottom,
                startRadius: 0,
                endRadius: 400
            )
        }
    }

    private var sheetBorder: some View {
        RoundedRectangle(cornerRadius: 38, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        AnkyReflectionCreditsPalette.gold.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }

    private func isRecommended(_ pack: RevenueCatCreditPackage) -> Bool {
        pack.title == "11 reflections" || pack.id == "inc.anky.credits.11" || pack.id.hasSuffix(".credits.11")
    }
}

private struct AnkyReflectionCreditPackRow: View {
    let pack: RevenueCatCreditPackage
    let isRecommended: Bool
    let isPurchasing: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            guard !isPurchasing else {
                return
            }
            action()
        } label: {
            HStack(spacing: 16) {
                icon

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(pack.title)
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .foregroundStyle(AnkyReflectionCreditsPalette.cream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)

                        if isRecommended {
                            Text("recommended")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AnkyReflectionCreditsPalette.almostBlack)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AnkyReflectionCreditsPalette.gold, in: Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }

                    Text(pack.subtitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AnkyReflectionCreditsPalette.cream.opacity(0.58))
                }

                Spacer()

                if isPurchasing {
                    ProgressView()
                        .tint(AnkyReflectionCreditsPalette.gold)
                        .scaleEffect(1.05)
                } else {
                    Text(pack.price)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(AnkyReflectionCreditsPalette.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 92)
            .background(rowBackground)
            .overlay(rowBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        isPressed = false
                    }
                }
        )
        .accessibilityLabel("\(pack.title), \(pack.subtitle), \(pack.price)")
        .accessibilityHint("Double tap to buy.")
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AnkyReflectionCreditsPalette.gold.opacity(0.24),
                            AnkyReflectionCreditsPalette.purpleDeep.opacity(0.42),
                            AnkyReflectionCreditsPalette.almostBlack.opacity(0.5)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 42
                    )
                )
                .frame(width: 56, height: 56)

            Circle()
                .strokeBorder(AnkyReflectionCreditsPalette.gold.opacity(0.24), lineWidth: 1)

            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AnkyReflectionCreditsPalette.gold)
                .shadow(color: AnkyReflectionCreditsPalette.gold.opacity(0.55), radius: 8)
        }
    }

    private var rowBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hexString: "150B20").opacity(0.95),
                            Color(hexString: "07050D").opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if isRecommended {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                AnkyReflectionCreditsPalette.gold.opacity(0.18),
                                Color.clear
                            ],
                            center: .leading,
                            startRadius: 0,
                            endRadius: 240
                        )
                    )
            }
        }
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: isRecommended
                    ? [
                        AnkyReflectionCreditsPalette.gold.opacity(0.95),
                        AnkyReflectionCreditsPalette.gold.opacity(0.38),
                        AnkyReflectionCreditsPalette.violet.opacity(0.36)
                    ]
                    : [
                        AnkyReflectionCreditsPalette.gold.opacity(0.32),
                        AnkyReflectionCreditsPalette.violet.opacity(0.24)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isRecommended ? 1.5 : 1
            )
            .shadow(
                color: isRecommended ? AnkyReflectionCreditsPalette.gold.opacity(0.35) : .clear,
                radius: 12
            )
    }
}

private struct AnkyReflectionCreditEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AnkyReflectionCreditsPalette.cream.opacity(0.58))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(height: 68)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AnkyReflectionCreditsPalette.gold.opacity(0.22), lineWidth: 1)
            )
    }
}

struct AnkyReflectionCreditsSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool

    let availableCredits: Int?
    let packs: [RevenueCatCreditPackage]
    let isRefreshing: Bool
    let purchasingPackId: String?
    let onRefresh: () -> Void
    let onSelectPack: (RevenueCatCreditPackage) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                AnkyReflectionCreditsSheet(
                    availableCredits: availableCredits,
                    packs: packs,
                    isRefreshing: isRefreshing,
                    purchasingPackId: purchasingPackId,
                    onRefresh: onRefresh,
                    onSelectPack: onSelectPack
                )
                .presentationDetents([.height(650), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(38)
                .presentationBackground(.clear)
            }
    }
}

extension View {
    func ankyReflectionCreditsSheet(
        isPresented: Binding<Bool>,
        availableCredits: Int?,
        packs: [RevenueCatCreditPackage],
        isRefreshing: Bool = false,
        purchasingPackId: String? = nil,
        onRefresh: @escaping () -> Void,
        onSelectPack: @escaping (RevenueCatCreditPackage) -> Void
    ) -> some View {
        modifier(
            AnkyReflectionCreditsSheetPresenter(
                isPresented: isPresented,
                availableCredits: availableCredits,
                packs: packs,
                isRefreshing: isRefreshing,
                purchasingPackId: purchasingPackId,
                onRefresh: onRefresh,
                onSelectPack: onSelectPack
            )
        )
    }
}

private enum AnkyReflectionCreditsPalette {
    static let almostBlack = Color(hexString: "05040B")
    static let purpleDeep = Color(hexString: "250834")
    static let violet = Color(hexString: "8F4DFF")
    static let gold = Color(hexString: "F4D374")
    static let cream = Color(hexString: "FFF2C6")
}

private extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
