//
//  ReflectionSheet.swift
//  Anky
//
//  AI, on the outer layer. A reflection exists only when a subscriber asks
//  for one, for one writing, after being told exactly what happens:
//  the writing is sent to Anky's server, an AI model reflects on it, the
//  server keeps no copy, and the reflection is saved on this iPhone.
//
//  The server checks the subscription independently (HTTP 402 otherwise);
//  hiding the button is not the security, it is the courtesy.
//

import SwiftUI

struct ReflectionSheet: View {
    let writing: SavedAnky
    let onSubscribe: () -> Void

    @ObservedObject private var access = AccessController.shared
    @Environment(\.dismiss) private var dismiss

    @State private var reflection: LocalReflection?
    @State private var isAsking = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let reflection {
                        Text(reflection.title)
                            .font(.fraunces(26, weight: .regular))
                            .foregroundStyle(Color.ankyInk)
                        Text(Self.attributed(reflection.reflection))
                            .font(.fraunces(17, weight: .light))
                            .foregroundStyle(Color.ankyInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if access.can(.requestAI) {
                        consent
                    } else {
                        subscriberOnly
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.fraunces(15, weight: .light, italic: true))
                            .foregroundStyle(Color.ankyMadder)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ankyPaper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AnkyLocalization.ui("Close")) { dismiss() }
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            reflection = ReflectionStore().load(hash: writing.hash)
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AnkyLocalization.ui("Ask Anky to reflect"))
                .font(.fraunces(26, weight: .regular))
                .foregroundStyle(Color.ankyInk)
            Text(AnkyLocalization.ui("This sends this one writing to Anky's server, where an AI model reads it and writes a reflection. The server does not keep your writing. The reflection is saved here, on this iPhone."))
                .font(.fraunces(17, weight: .light))
                .foregroundStyle(Color.ankyInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text(AnkyLocalization.ui("Voice and video are never sent."))
                .font(.fraunces(15, weight: .light, italic: true))
                .foregroundStyle(Color.ankyInkSoft)
            AnkyPrimaryButton(AnkyLocalization.ui("Send and reflect"), isLoading: isAsking) {
                Task { await ask() }
            }
            .padding(.top, 6)
        }
    }

    private var subscriberOnly: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AnkyLocalization.ui("Reflections are part of the subscription."))
                .font(.fraunces(24, weight: .regular))
                .foregroundStyle(Color.ankyInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(AnkyLocalization.ui("Anky's core — writing, speaking, recording, your memories — never needs AI. Subscribers can ask for a reflection on any writing, whenever they choose."))
                .font(.fraunces(17, weight: .light))
                .foregroundStyle(Color.ankyInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            AnkyPrimaryButton(AnkyLocalization.ui("See the subscription")) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onSubscribe() }
            }
        }
    }

    private func ask() async {
        guard access.can(.requestAI) else { return }
        isAsking = true
        errorText = nil
        defer { isAsking = false }
        guard let identity = await access.signingIdentity() else {
            errorText = AnkyLocalization.ui("Anky couldn't reach your account key on this iPhone.")
            return
        }
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let result = try await AnkyServerClient().reflect(
                ankyBytes: Data(writing.text.utf8),
                identity: identity,
                appVersion: version
            )
            let saved = LocalReflection(
                hash: writing.hash,
                title: Self.title(from: result.markdown),
                reflection: Self.body(from: result.markdown),
                createdAt: Date()
            )
            try? ReflectionStore().save(saved)
            withAnimation(.easeInOut(duration: 0.3)) { reflection = saved }
        } catch AnkyServerError.entitlementRequired {
            errorText = AnkyLocalization.ui("Anky's server couldn't confirm your subscription yet. Try Restore purchases, then ask again.")
            await access.refresh()
        } catch AnkyServerError.offline {
            errorText = AnkyLocalization.ui("You're offline. Your writing wasn't sent.")
        } catch AnkyServerError.rateLimited {
            errorText = AnkyLocalization.ui("Anky has reflected a lot today. Try again later.")
        } catch {
            errorText = AnkyLocalization.ui("The reflection didn't come through. Nothing was saved or charged.")
        }
    }

    /// The first markdown heading (the prompt asks for a short title on top).
    static func title(from markdown: String) -> String {
        for line in markdown.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            }
            if !trimmed.isEmpty { return String(trimmed.prefix(48)) }
        }
        return AnkyLocalization.ui("Reflection")
    }

    static func body(from markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            lines.remove(at: first)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}
