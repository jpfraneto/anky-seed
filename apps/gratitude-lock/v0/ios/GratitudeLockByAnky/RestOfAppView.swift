import SwiftUI

struct RestOfAppView: View {
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.95)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("Unlocked")
                    .font(.system(size: 34, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.10))

                Text("Carry that with you.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
