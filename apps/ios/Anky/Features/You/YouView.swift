import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct YouView: View {
    @ObservedObject var viewModel: YouViewModel
    @Environment(\.openURL) private var openURL
    @AppStorage(MirrorConfiguration.userDefaultsKey) private var mirrorBaseURL = MirrorConfiguration.defaultBaseURL
    @AppStorage("anky.dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("anky.dailyReminderTime") private var dailyReminderTime = 9.0 * 60.0 * 60.0
    @AppStorage("anky.biometricIdentityConfirmation") private var biometricIdentityConfirmation = false
    @State private var confirmClearArchive = false
    @State private var confirmClearReflections = false
    @State private var confirmClearWritingData = false
    @State private var confirmResetIdentity = false
    @State private var copiedAnkyCA = false
    @State private var isImportingBackup = false
    @State private var isImportingRecoveryPhrase = false
    @State private var recoveryPhraseInput = ""

    var body: some View {
        NavigationStack {
            ZStack {
                YouCosmicBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        YouTitle(title: "you", subtitle: "your story. your uniqueness.")
                            .padding(.top, 18)

                        YouAvatar()

                        YouStatsPanel(
                            ankys: viewModel.completeAnkyCount,
                            minutes: viewModel.totalWritingMinutes,
                            streak: viewModel.currentStreak
                        )

                        statusMessages

                        YouPanel(spacing: 0) {
                            NavigationLink {
                                AccountPage(
                                    viewModel: viewModel,
                                    dailyReminderEnabled: $dailyReminderEnabled,
                                    dailyReminderTime: $dailyReminderTime,
                                    biometricIdentityConfirmation: $biometricIdentityConfirmation,
                                    isImportingRecoveryPhrase: $isImportingRecoveryPhrase,
                                    recoveryPhraseInput: $recoveryPhraseInput,
                                    reminderDate: reminderDate,
                                    reminderBinding: reminderBinding
                                )
                            } label: {
                                YouMenuRow(icon: "you-icon-account", title: "local identity", subtitle: "private to this device")
                            }

                            YouDivider()

                            NavigationLink {
                                PrivacyPolicyPage()
                            } label: {
                                YouMenuRow(icon: "you-icon-privacy", title: "privacy", subtitle: "local-first. private. sovereign.")
                            }

                            YouDivider()

                            NavigationLink {
                                ExportDataPage(
                                    viewModel: viewModel,
                                    isImportingBackup: $isImportingBackup,
                                    confirmClearWritingData: $confirmClearWritingData
                                )
                            } label: {
                                YouMenuRow(icon: "you-icon-export", title: "export data", subtitle: "back up and restore local writing")
                            }

                            YouDivider()

                            NavigationLink {
                                CreditsPage(viewModel: viewModel)
                            } label: {
                                YouMenuRow(icon: "you-icon-credits", title: "credits", subtitle: "reflections and trial credits")
                            }

                            YouDivider()

                            NavigationLink {
                                AnkyTokenPage(viewModel: viewModel, copiedAnkyCA: $copiedAnkyCA)
                            } label: {
                                YouMenuRow(icon: "you-icon-settings", title: "$ANKY", subtitle: "the memetic layer")
                            }

                            YouDivider()

                            if let whatsappURL = viewModel.freeCreditWhatsAppURL {
                                Button {
                                    openURL(whatsappURL)
                                } label: {
                                    YouMenuRow(icon: "you-icon-credits", title: "support", subtitle: "manual credit help")
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        #if DEBUG
                        NavigationLink {
                            DeveloperPage(
                                mirrorBaseURL: $mirrorBaseURL,
                                confirmClearArchive: $confirmClearArchive,
                                confirmClearReflections: $confirmClearReflections,
                                confirmResetIdentity: $confirmResetIdentity,
                                viewModel: viewModel
                            )
                        } label: {
                            YouPanel {
                                YouMenuRow(icon: "you-icon-settings", title: "developer", subtitle: "local tools")
                            }
                        }
                        #endif
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
                .safeAreaPadding(.top, 44)
            }
            .toolbar(.hidden, for: .navigationBar)
            .enableSwipeBackGesture()
            .confirmationDialog("delete local writing data?", isPresented: $confirmClearWritingData, titleVisibility: .visible) {
                Button("delete local writing data", role: .destructive) {
                    viewModel.clearLocalWritingData()
                }
            }
            .confirmationDialog("clear local .anky archive?", isPresented: $confirmClearArchive, titleVisibility: .visible) {
                Button("clear .anky archive", role: .destructive) {
                    viewModel.clearLocalArchive()
                }
            }
            .confirmationDialog("clear local reflections?", isPresented: $confirmClearReflections, titleVisibility: .visible) {
                Button("clear reflections", role: .destructive) {
                    viewModel.clearLocalReflections()
                }
            }
            .confirmationDialog("reset local identity?", isPresented: $confirmResetIdentity, titleVisibility: .visible) {
                Button("reset identity", role: .destructive) {
                    viewModel.resetIdentityForDevelopment()
                }
            }
            .sheet(isPresented: $isImportingRecoveryPhrase) {
                ImportRecoveryPhraseSheet(
                    viewModel: viewModel,
                    recoveryPhraseInput: $recoveryPhraseInput,
                    isPresented: $isImportingRecoveryPhrase
                )
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: Self.importableContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    _ = viewModel.importBackup(from: url)
                case .failure:
                    break
                }
            }
            .onAppear {
                viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let errorMessage = viewModel.errorMessage {
            YouPanel {
                Text(errorMessage.lowercased())
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(YouPalette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if let statusMessage = viewModel.statusMessage {
            YouPanel {
                Text(statusMessage.lowercased())
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(YouPalette.paperMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static var importableContentTypes: [UTType] {
        [
            UTType(filenameExtension: "zip"),
            UTType(filenameExtension: "anky"),
            .json
        ].compactMap { $0 }
    }

    private var reminderDate: Date {
        let start = Calendar.current.startOfDay(for: Date())
        return start.addingTimeInterval(dailyReminderTime)
    }

    private var reminderBinding: Binding<Date> {
        Binding {
            reminderDate
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dailyReminderTime = Double((components.hour ?? 9) * 3600 + (components.minute ?? 0) * 60)
            if dailyReminderEnabled {
                Task {
                    await viewModel.setDailyReminder(enabled: true, date: newValue)
                }
            }
        }
    }
}

private struct AccountPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var dailyReminderEnabled: Bool
    @Binding var dailyReminderTime: Double
    @Binding var biometricIdentityConfirmation: Bool
    @Binding var isImportingRecoveryPhrase: Bool
    @Binding var recoveryPhraseInput: String
    let reminderDate: Date
    let reminderBinding: Binding<Date>

    var body: some View {
        YouDetailShell(title: "local identity", subtitle: "private to this device") {
            YouPanel {
                Text("local identity")
                    .youCaption()
                Text("anky created a private identity for this device.")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(YouPalette.paper)
                Text("your writing and identity live here unless you choose to export or recover them elsewhere.")
                    .youBody()
            }

            YouPanel {
                Text("advanced recovery")
                    .youCaption()
                Text("anyone with this recovery key can restore this identity. keep it private.")
                    .youBody()

                YouDivider()

                Toggle("face id app lock", isOn: $biometricIdentityConfirmation)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 16, design: .serif))

                Text("your recovery key can only be shown after face id is enabled.")
                    .youBody()

                if viewModel.recoveryPhraseText.isEmpty {
                    YouActionButton("show recovery key") {
                        Task {
                            await viewModel.revealRecoveryPhrase()
                        }
                    }
                    .disabled(!biometricIdentityConfirmation)
                    .opacity(biometricIdentityConfirmation ? 1 : 0.45)
                } else {
                    Text(viewModel.recoveryPhraseText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(YouPalette.paper)
                        .textSelection(.enabled)

                    VStack(spacing: 10) {
                        YouActionButton("export recovery key") {
                            ClipboardClient().copy(viewModel.recoveryPhraseText)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        YouActionButton("hide") {
                            viewModel.hideRecoveryPhrase()
                        }
                    }
                }

                YouActionButton("recover identity") {
                    recoveryPhraseInput = ""
                    isImportingRecoveryPhrase = true
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("public identity")
                        .youCaption()
                    Text(viewModel.publicKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(YouPalette.paperMuted)
                        .textSelection(.enabled)
                }

                YouActionButton("copy public identity") {
                    ClipboardClient().copy(viewModel.publicKey)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }

            YouPanel {
                Toggle("daily reminder", isOn: $dailyReminderEnabled)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 16, design: .serif))
                    .onChange(of: dailyReminderEnabled) { isEnabled in
                        Task {
                            await viewModel.setDailyReminder(enabled: isEnabled, date: reminderDate)
                        }
                    }

                DatePicker("time", selection: reminderBinding, displayedComponents: .hourAndMinute)
                    .disabled(!dailyReminderEnabled)
                    .tint(YouPalette.gold)
                    .foregroundStyle(YouPalette.paper)
            }

            YouPanel {
                Text("ownership note")
                    .youCaption()
                Text("your writing belongs to this device unless you choose to export or recover it elsewhere.")
                    .youBody()
            }
        }
    }
}

private struct PrivacyPolicyPage: View {
    var body: some View {
        YouDetailShell(title: "privacy", subtitle: "local-first. private. sovereign.") {
            VStack(spacing: 12) {


                Text("privacy is the shape of anky, not a feature added later.")
                    .font(.custom("Georgia", size: 19).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(YouPalette.paper)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.policyCopy.indices, id: \.self) { index in
                    PrivacyCopyLine(Self.policyCopy[index])
                }
            }

            YouPanel {
                Text("questions, deletion requests, and privacy reports")
                    .youCaption()

                Text("jp@anky.app")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(YouPalette.paper)
                    .textSelection(.enabled)
            }
        }
    }

    private static let policyCopy: [PrivacyCopyItem] = [
        .caption("last updated: 2026-05-14"),
        .paragraph("anky is a local-first writing app. the core artifact is the `.anky` file on your device. the app should let you write, save, revisit, export, import, and delete your writing without making a server the owner of your interior life."),
        .heading("the private artifact"),
        .paragraph("your `.anky` writing is stored on your device by default. a saved `.anky` file contains the accepted writing stream and timing data for a session."),
        .paragraph("anky computes a SHA-256 hash of the exact `.anky` bytes. the hash is for integrity. it is not encryption. if someone has the same `.anky` bytes, they can compute the same hash."),
        .paragraph("the source is direct: [local archive](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/LocalAnkyArchive.swift), [protocol](https://github.com/jpfraneto/anky-seed/tree/main/apps/ios/Anky/Core/Protocol)."),
        .heading("local identity"),
        .paragraph("anky creates a local identity, stores its recovery key in device secure storage, and derives the writing identity locally. the recovery key is not sent to anky."),
        .paragraph("the relevant code is [writer identity](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/WriterIdentityStore.swift) and [keychain storage](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/KeychainClient.swift)."),
        .heading("when plaintext leaves"),
        .paragraph("writing, saving, hashing, reading the map, and keeping local backups do not require plaintext to leave your device."),
        .paragraph("plaintext can leave when you choose an action that sends it somewhere: asking anky for a reflection, exporting or sharing files, importing a backup from a place you chose, or contacting support with text you provide."),
        .paragraph("the processing and backup paths are [reflection client](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Mirror/MirrorClient.swift), [backup importer](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/BackupImporter.swift), and [you page model](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Features/You/YouViewModel.swift)."),
        .heading("reflections"),
        .paragraph("when you ask for a reflection, the app sends the saved `.anky` bytes to the configured mirror service. the mirror checks the hash, reconstructs readable text for processing, and returns a reflection."),
        .paragraph("the local app stores the returned reflection as a local sidecar. reflections are optional. writing is free and does not depend on reflections."),
        .heading("backups and deletion"),
        .paragraph("exports and backups can contain plaintext writing, reflections, and related local metadata. keep them somewhere private."),
        .paragraph("deleting local writing data removes local `.anky` files, local reflections, and the local session index from this app's storage area. it does not automatically delete backend records already created by optional processing."),
        .heading("what this does not claim"),
        .paragraph("anky does not claim that hashes encrypt writing. anky does not claim anonymity. timing, identity identifiers, processing requests, purchases, and support requests can be linkable."),
        .paragraph("anky does not claim optional processing is local-only. if you ask for a reflection, plaintext writing is sent for processing."),
        .paragraph("anky does claim the default direction of the app is local-first: the `.anky` file belongs first to the person who wrote it.")
    ]
}

private enum PrivacyCopyItem {
    case caption(String)
    case heading(String)
    case paragraph(String)
}

private struct PrivacyCopyLine: View {
    let item: PrivacyCopyItem

    init(_ item: PrivacyCopyItem) {
        self.item = item
    }

    var body: some View {
        switch item {
        case .caption(let text):
            Text(text)
                .youCaption()
        case .heading(let text):
            Text(text)
                .font(.custom("Georgia", size: 21).weight(.semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .paragraph(let text):
            MarkdownArticleText(text)
        }
    }
}

private struct ExportDataPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var isImportingBackup: Bool
    @Binding var confirmClearWritingData: Bool

    var body: some View {
        YouDetailShell(title: "export data", subtitle: "your archive is yours") {
            YouPanel {
                Text("\(viewModel.ankyFileURLs.count) local .anky files · \(viewModel.reflectionFileURLs.count) reflections")
                    .font(.custom("Georgia", size: 22).weight(.semibold))
                    .foregroundStyle(YouPalette.gold)

                Text("backups may include plaintext writing and reflections. keep them somewhere private.")
                    .youBody()
            }

            YouPanel {
                if let backupZipURL = viewModel.backupZipURL {
                    ShareLink(item: backupZipURL) {
                        YouActionLabel("export backup zip")
                    }
                } else {
                    YouDisabledRow("no local data to export yet")
                }

                YouActionButton("restore backup") {
                    isImportingBackup = true
                }
            }

            YouDangerPanel {
                Text("danger zone")
                    .font(.custom("Georgia", size: 18).weight(.semibold))
                    .foregroundStyle(YouPalette.danger)
                Text("this removes local .anky files, local reflections, and the local map index from this device. export a backup first if you want to keep them.")
                    .youBody()
                YouActionButton("delete local data", role: .destructive) {
                    confirmClearWritingData = true
                }
            }
        }
        .onAppear {
            viewModel.prepareBackupExport()
        }
    }
}

struct CreditsPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        YouDetailShell(title: "credits", subtitle: "reflection fuel") {
            YouPanel {
                Text(viewModel.creditBalance.map(String.init) ?? "...")
                    .font(.custom("Georgia", size: 62).weight(.bold))
                    .foregroundStyle(YouPalette.gold)
                    .shadow(color: YouPalette.gold.opacity(0.35), radius: 18)
                Text("credits")
                    .youCaption()
            }

            YouPanel {
                YouRuleRow("1 credit = reflection")
                YouRuleRow("ask anky spends one credit")
                YouRuleRow("writing is always free")
            }

            YouPanel {
                if viewModel.creditsLoading && viewModel.creditPackages.isEmpty {
                    YouDisabledRow("loading credit packs")
                } else if viewModel.creditPackages.isEmpty {
                    YouDisabledRow("no credit packs available")
                } else {
                    ForEach(viewModel.creditPackages) { creditPackage in
                        CreditPackageButton(
                            creditPackage: creditPackage,
                            isPurchasing: viewModel.purchasingCreditPackageID == creditPackage.id
                        ) {
                            Task {
                                await viewModel.purchaseCredits(creditPackage)
                            }
                        }
                    }
                }

                YouActionButton("refresh credits") {
                    Task {
                        await viewModel.refreshCredits()
                    }
                }
            }

            YouPanel {
                ShareLink(item: viewModel.freeCreditMessage) {
                    YouActionLabel("share support request")
                }

                if let whatsappURL = viewModel.freeCreditWhatsAppURL {
                    YouActionButton("contact jp / support") {
                        openURL(whatsappURL)
                    }
                }

                Text("support credit requests use your public identity only. no writing is included.")
                    .youBody()
            }
        }
    }
}

private struct CreditPackageButton: View {
    let creditPackage: RevenueCatCreditPackage
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(creditPackage.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(YouPalette.paper)
                    Text(creditPackage.subtitle)
                        .youCaption()
                }

                Spacer()

                Text(isPurchasing ? "..." : creditPackage.price)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(YouPalette.gold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(YouPalette.buttonFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(YouPalette.gold.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }
}

private struct AnkyTokenPage: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var copiedAnkyCA: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        YouDetailShell(title: "$ANKY", subtitle: "the memetic layer") {
            VStack(spacing: 14) {
                Image("you-ankycoin")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 136, height: 136)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(YouPalette.gold.opacity(0.5), lineWidth: 1))
                    .shadow(color: YouPalette.gold.opacity(0.24), radius: 18)
                    .frame(maxWidth: .infinity)


            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.tokenCopy.indices, id: \.self) { index in
                    TokenCopyLine(Self.tokenCopy[index])
                }
            }

            YouPanel {
                Text(viewModel.ankyCoinContractAddress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(YouPalette.paperMuted)
                    .textSelection(.enabled)

                YouActionButton(copiedAnkyCA ? "copied!" : "copy contract address") {
                    ClipboardClient().copy(viewModel.ankyCoinContractAddress)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copiedAnkyCA = true
                }
            }
        }
    }

    private static let tokenCopy: [TokenCopyItem] = [
        .paragraph("a memecoin is the simplest possible expression of an idea on the internet. no pitch deck, no roadmap, no Series A. just a name, a ticker, and a bet that enough people will recognize what it points to."),
        .paragraph("$ANKY was launched on pump.fun on Solana. that's it. no presale, no team allocation, no vesting schedule. the bonding curve did what bonding curves do."),
        .heading("what it points to"),
        .paragraph("anky is a writing practice. you sit down, you write for 8 minutes without stopping, and something emerges that your conscious mind didn't plan. the token doesn't change what the practice is. it doesn't unlock features or grant access. it's a flag planted in the ground that says: this idea exists, and the market gets to decide what it's worth."),
        .heading("memecoins and the new internet"),
        .paragraph("the old internet released ideas through products. you built something, charged for it, and hoped people would pay. the new internet releases ideas through tokens. the idea itself becomes tradeable the moment it has a name."),
        .paragraph("this is either profoundly stupid or profoundly honest. probably both. a memecoin strips away every pretension about what makes something valuable and reduces it to the only question that ever mattered: do people care about this?"),
        .paragraph("most memecoins are jokes. some jokes contain more truth than business plans. the cosmic joke of $ANKY is that a tool designed to bypass your conscious mind — to help you stop thinking and just write — now has a price feed that people watch with their conscious minds, thinking very hard about whether the number will go up."),
        .paragraph("the mirror doesn't care about the price. the practice remains free. write for 8 minutes. meet yourself. whether the token is worth a penny or a dollar, the words you wrote are still yours.")
    ]
}

private enum TokenCopyItem {
    case heading(String)
    case paragraph(String)
}

private struct TokenCopyLine: View {
    let item: TokenCopyItem

    init(_ item: TokenCopyItem) {
        self.item = item
    }

    var body: some View {
        switch item {
        case .heading(let text):
            Text(text)
                .font(.custom("Georgia", size: 21).weight(.semibold))
                .foregroundStyle(YouPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case .paragraph(let text):
            Text(text)
                .font(.custom("Georgia", size: 16))
                .lineSpacing(5)
                .foregroundStyle(YouPalette.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MarkdownArticleText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributedText)
            .font(.custom("Georgia", size: 16))
            .lineSpacing(5)
            .foregroundStyle(YouPalette.paper)
            .tint(YouPalette.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct DeveloperPage: View {
    @Binding var mirrorBaseURL: String
    @Binding var confirmClearArchive: Bool
    @Binding var confirmClearReflections: Bool
    @Binding var confirmResetIdentity: Bool
    @ObservedObject var viewModel: YouViewModel

    var body: some View {
        YouDetailShell(title: "developer", subtitle: "local tools") {
            YouPanel {
                TextField("mirror base url", text: $mirrorBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(YouPalette.paper)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(12)
                    .background(YouPalette.panelStrong, in: RoundedRectangle(cornerRadius: 12))

                Text("simulator local mirror: http://127.0.0.1:3000. physical devices need your mac's lan ip.")
                    .youBody()

                YouActionButton("repair map index") {
                    viewModel.rebuildSessionIndex()
                }
            }

            YouPanel {
                YouActionButton("clear local reflections", role: .destructive) {
                    confirmClearReflections = true
                }
                YouActionButton("clear local .anky archive", role: .destructive) {
                    confirmClearArchive = true
                }
                YouActionButton("reset local identity", role: .destructive) {
                    confirmResetIdentity = true
                }
            }
        }
    }
}

private struct ImportRecoveryPhraseSheet: View {
    @ObservedObject var viewModel: YouViewModel
    @Binding var recoveryPhraseInput: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                YouCosmicBackground()
                VStack(spacing: 16) {
                    TextEditor(text: $recoveryPhraseInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(YouPalette.paper)
                        .padding(12)
                        .frame(minHeight: 140)
                        .background(YouPalette.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(YouPalette.goldDim, lineWidth: 1))

                    Text("recovering replaces the local identity used for ask anky and future credit balances. local .anky files stay on this device.")
                        .youBody()

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("recover identity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("recover") {
                        Task {
                            if await viewModel.importRecoveryPhrase(recoveryPhraseInput) {
                                isPresented = false
                            }
                        }
                    }
                    .disabled(recoveryPhraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct YouDetailShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            YouCosmicBackground()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(YouPalette.gold)
                            .frame(width: 44, height: 44)
                            .background(YouPalette.panel, in: Circle())
                            .overlay(Circle().stroke(YouPalette.goldDim, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 3) {
                        Text(title)
                            .font(.custom("Georgia", size: 26).weight(.semibold))
                            .foregroundStyle(YouPalette.gold)
                        Text(subtitle)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(YouPalette.paperMuted)
                    }

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 18)
                .padding(.top, 64)
                .padding(.bottom, 14)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBackGesture()
    }
}

private struct YouCosmicBackground: View {
    var body: some View {
        ZStack {
            Image("you-bg-cosmos")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Color(red: 5 / 255, green: 5 / 255, blue: 14 / 255)
                .opacity(0.32)
                .ignoresSafeArea()
        }
    }
}

private struct YouTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.custom("Georgia", size: 34).weight(.semibold))
                .foregroundStyle(YouPalette.gold)
            Text(subtitle)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(YouPalette.paperMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct YouAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(YouPalette.gold.opacity(0.72), lineWidth: 1.5)
                .frame(width: 124, height: 124)
                .shadow(color: YouPalette.gold.opacity(0.24), radius: 16)

            Circle()
                .stroke(YouPalette.gold.opacity(0.42), lineWidth: 1)
                .frame(width: 116, height: 116)

            Image("you-avatar-anky")
                .resizable()
                .scaledToFill()
                .frame(width: 108, height: 108)
                .clipShape(Circle())

            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(YouPalette.gold)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
                    .offset(y: -68)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .frame(width: 144, height: 144)
    }
}

private struct YouStatsPanel: View {
    let ankys: Int
    let minutes: Int
    let streak: Int

    var body: some View {
        YouPanel(spacing: 0) {
            HStack(spacing: 0) {
                YouStatCell(icon: "you-icon-feather-stat", value: "\(ankys)", label: "ankys")
                YouVerticalDivider()
                YouStatCell(icon: "you-icon-clock-stat", value: "\(minutes)", label: "minutes")
                YouVerticalDivider()
                YouStatCell(icon: "you-icon-flame-stat", value: "\(streak)", label: "streak")
            }
        }
        .frame(height: 68)
    }
}

private struct YouStatCell: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(YouPalette.paper)
                Text(label)
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(YouPalette.paperMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct YouMenuRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(YouPalette.paper)
                Text(subtitle)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(YouPalette.paperMuted)
            }

            Spacer()

            Image("you-icon-chevron-right")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .opacity(0.82)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 14)
    }
}

private struct YouPanel<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YouPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(YouPalette.goldDim, lineWidth: 1)
        )
    }
}

private struct YouDangerPanel<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.18, green: 0.035, blue: 0.055).opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(YouPalette.danger.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct YouActionButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            YouActionLabel(title, destructive: role == .destructive)
        }
        .buttonStyle(.plain)
    }
}

private struct YouActionLabel: View {
    let title: String
    var destructive = false

    init(_ title: String, destructive: Bool = false) {
        self.title = title
        self.destructive = destructive
    }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(destructive ? YouPalette.danger : YouPalette.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(YouPalette.buttonFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke((destructive ? YouPalette.danger : YouPalette.gold).opacity(0.38), lineWidth: 1)
            )
    }
}

private struct YouDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .youCaption()
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(YouPalette.paper)
        }
    }
}

private struct YouRuleRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(YouPalette.gold.opacity(0.72))
                .frame(width: 5, height: 5)
            Text(text)
                .youBody()
        }
    }
}

private struct YouDisabledRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .youBody()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(YouPalette.panelStrong.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct YouDivider: View {
    var body: some View {
        Rectangle()
            .fill(YouPalette.gold.opacity(0.13))
            .frame(height: 1)
    }
}

private struct YouVerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(YouPalette.gold.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}

private enum YouPalette {
    static let ink = Color(red: 0.031, green: 0.027, blue: 0.071)
    static let panel = Color(red: 0.08, green: 0.055, blue: 0.15).opacity(0.72)
    static let panelStrong = Color(red: 0.075, green: 0.061, blue: 0.13).opacity(0.82)
    static let buttonFill = Color(red: 0.19, green: 0.13, blue: 0.09).opacity(0.74)
    static let gold = Color(red: 0.91, green: 0.79, blue: 0.48)
    static let goldDim = gold.opacity(0.32)
    static let paper = Color(red: 1, green: 0.94, blue: 0.79)
    static let paperMuted = Color(red: 0.86, green: 0.81, blue: 0.92).opacity(0.72)
    static let danger = Color(red: 0.97, green: 0.44, blue: 0.44)
}

private extension Text {
    func youBody() -> some View {
        self
            .font(.system(size: 14, design: .serif))
            .lineSpacing(3)
            .foregroundStyle(YouPalette.paperMuted)
    }

    func youCaption() -> some View {
        self
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .foregroundStyle(YouPalette.gold.opacity(0.88))
            .textCase(.lowercase)
    }
}

private extension View {
    func enableSwipeBackGesture() -> some View {
        background(SwipeBackGestureEnabler().frame(width: 0, height: 0))
    }
}

private struct SwipeBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            enableGesture(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            enableGesture(from: uiViewController)
        }
    }

    private func enableGesture(from controller: UIViewController) {
        guard let navigationController = controller.navigationController else { return }
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = nil
    }
}
