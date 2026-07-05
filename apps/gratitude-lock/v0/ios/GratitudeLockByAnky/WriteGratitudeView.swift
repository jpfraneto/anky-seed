import SwiftUI

struct WriteGratitudeView: View {
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .padding(14)
                        .frame(minHeight: 170)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if text.isEmpty {
                        Text("I'm grateful for...")
                            .font(.system(size: 21, weight: .regular, design: .serif))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                    }
                }

                Button {
                    onSubmit(trimmedText)
                } label: {
                    Text("Submit")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            trimmedText.isEmpty
                            ? Color.gray.opacity(0.35)
                            : Color(red: 0.05, green: 0.07, blue: 0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(trimmedText.isEmpty)
            }
            .padding(22)
            .navigationTitle("Write")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}
