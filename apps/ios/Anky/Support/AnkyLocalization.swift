import Foundation

enum AnkyLocalizedKey: String, CaseIterable {
    case tabWrite
    case tabMap
    case tabYou
    case faceIDPrompt
    case activateFaceID
    case notNow
    case protectFaceIDReason
    case unlockFaceIDReason
    case launchEmpty
    case launchCountFormat
    case writeAgain
    case writeMinutesFormat
    case stepWriteOneCharacter
    case stepKeepThreadAlive
    case stepLetSilenceCloseIt
    case creditGiftSummary
    case creditGiftCaption
    case creditGiftPrompt
    case writeEightMinutes
    case creditPacksLocked
    case creditGiftDetail
    case spendGiftBeforeBuying
}

enum AnkyLocalization {
    static func text(_ key: AnkyLocalizedKey, _ arguments: CVarArg...) -> String {
        let format = localizedFormat(for: key)
        guard !arguments.isEmpty else {
            return format
        }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func localizedFormat(for key: AnkyLocalizedKey) -> String {
        let code = preferredLanguageCode
        if let translation = translations[code]?[key] {
            return translation
        }
        return translations["en"]?[key] ?? key.rawValue
    }

    private static var preferredLanguageCode: String {
        Locale.preferredLanguages
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
            .map(normalizedLanguageCode)
            .first(where: { translations[$0] != nil })
            ?? "en"
    }

    private static func normalizedLanguageCode(_ code: String) -> String {
        switch code {
        case "es", "pt", "fr", "de", "it", "ja", "ko", "zh":
            return code
        default:
            return "en"
        }
    }

    private static let translations: [String: [AnkyLocalizedKey: String]] = [
        "en": [
            .tabWrite: "Write",
            .tabMap: "Map",
            .tabYou: "You",
            .faceIDPrompt: "Protect your Anky with your device lock. Your writing is local, and this keeps access private on this phone.",
            .activateFaceID: "Activate Device Lock",
            .notNow: "Not now",
            .protectFaceIDReason: "Protect ANKY with your device lock.",
            .unlockFaceIDReason: "Unlock ANKY.",
            .launchEmpty: "The living .anky string is the state of this session.",
            .launchCountFormat: "Ankys today: %d",
            .writeAgain: "Write again",
            .writeMinutesFormat: "Write %d minutes",
            .stepWriteOneCharacter: "Write one character",
            .stepKeepThreadAlive: "Keep the thread alive",
            .stepLetSilenceCloseIt: "Let silence close it",
            .creditGiftSummary: "2 reflections - This device",
            .creditGiftCaption: "device gift",
            .creditGiftPrompt: "This device has two free reflections from Anky. Use them before buying more credits.",
            .writeEightMinutes: "Write 8 minutes",
            .creditPacksLocked: "Credit packs unlock after this device spends its first two reflections",
            .creditGiftDetail: "Your first two reflections are tied to this device. After they are used, this screen will let you buy more credits.",
            .spendGiftBeforeBuying: "Use this device's first two reflections before buying more credits."
        ],
        "es": [
            .tabWrite: "Escribir",
            .tabMap: "Mapa",
            .tabYou: "Tu",
            .faceIDPrompt: "Protege tu Anky con el bloqueo de tu dispositivo. Tu escritura es local, y esto mantiene privado el acceso en este telefono.",
            .activateFaceID: "Activar bloqueo",
            .notNow: "Ahora no",
            .protectFaceIDReason: "Protege ANKY con el bloqueo de tu dispositivo.",
            .unlockFaceIDReason: "Desbloquea ANKY.",
            .launchEmpty: "La cadena .anky viva es el estado de esta sesion.",
            .launchCountFormat: "Ankys de hoy: %d",
            .writeAgain: "Escribir otra vez",
            .writeMinutesFormat: "Escribir %d minutos",
            .stepWriteOneCharacter: "Escribe un caracter",
            .stepKeepThreadAlive: "Mantiene vivo el hilo",
            .stepLetSilenceCloseIt: "Deja que el silencio lo cierre",
            .creditGiftSummary: "2 creditos - Regalo de Anky",
            .creditGiftCaption: "creditos - Regalo de Anky",
            .creditGiftPrompt: "Tienes 2 creditos - Regalo de Anky. Usa estas primeras reflexiones antes de comprar mas creditos.",
            .writeEightMinutes: "Escribir 8 minutos",
            .creditPacksLocked: "Los paquetes de creditos se desbloquean despues de usar tus dos regalos de Anky",
            .creditGiftDetail: "Tus primeras dos reflexiones estan cubiertas. Despues de usarlas, esta pantalla te dejara comprar mas creditos.",
            .spendGiftBeforeBuying: "Usa tus dos regalos de Anky antes de comprar mas creditos."
        ],
        "pt": [
            .tabWrite: "Escrever",
            .tabMap: "Mapa",
            .tabYou: "Voce",
            .faceIDPrompt: "Proteja seu Anky com o bloqueio do dispositivo. Sua escrita fica local, e isso mantem o acesso privado neste telefone.",
            .activateFaceID: "Ativar bloqueio",
            .notNow: "Agora nao",
            .protectFaceIDReason: "Proteja o ANKY com o bloqueio do dispositivo.",
            .unlockFaceIDReason: "Desbloqueie o ANKY.",
            .launchEmpty: "A string .anky viva e o estado desta sessao.",
            .launchCountFormat: "Ankys hoje: %d",
            .writeAgain: "Escrever de novo",
            .writeMinutesFormat: "Escrever %d minutos",
            .stepWriteOneCharacter: "Escreva um caractere",
            .stepKeepThreadAlive: "Mantenha o fio vivo",
            .stepLetSilenceCloseIt: "Deixe o silencio fechar",
            .creditGiftSummary: "2 creditos - Presente da Anky",
            .creditGiftCaption: "creditos - Presente da Anky",
            .creditGiftPrompt: "Voce tem 2 creditos - Presente da Anky. Use estas primeiras reflexoes antes de comprar mais creditos.",
            .writeEightMinutes: "Escrever 8 minutos",
            .creditPacksLocked: "Os pacotes de creditos desbloqueiam depois que voce usar seus dois presentes da Anky",
            .creditGiftDetail: "Suas duas primeiras reflexoes estao cobertas. Depois de usa-las, esta tela deixara voce comprar mais creditos.",
            .spendGiftBeforeBuying: "Use seus dois presentes da Anky antes de comprar mais creditos."
        ],
        "fr": [
            .tabWrite: "Ecrire",
            .tabMap: "Carte",
            .tabYou: "Vous",
            .faceIDPrompt: "Protegez votre Anky avec le verrouillage de l'appareil. Votre ecriture reste locale, et cela garde l'acces prive sur ce telephone.",
            .activateFaceID: "Activer le verrouillage",
            .notNow: "Pas maintenant",
            .protectFaceIDReason: "Proteger ANKY avec le verrouillage de l'appareil.",
            .unlockFaceIDReason: "Deverrouiller ANKY.",
            .launchEmpty: "La chaine .anky vivante est l'etat de cette session.",
            .launchCountFormat: "Ankys aujourd'hui : %d",
            .writeAgain: "Ecrire encore",
            .writeMinutesFormat: "Ecrire %d minutes",
            .stepWriteOneCharacter: "Ecrivez un caractere",
            .stepKeepThreadAlive: "Gardez le fil vivant",
            .stepLetSilenceCloseIt: "Laissez le silence le fermer",
            .creditGiftSummary: "1 credit - Cadeau d'Anky",
            .creditGiftCaption: "credit - Cadeau d'Anky",
            .creditGiftPrompt: "Vous avez 1 credit - Cadeau d'Anky. Utilisez cette premiere reflexion avant d'acheter plus de credits.",
            .writeEightMinutes: "Ecrire 8 minutes",
            .creditPacksLocked: "Les packs de credits se debloquent apres avoir utilise votre Cadeau d'Anky",
            .creditGiftDetail: "Votre premiere reflexion est couverte. Apres l'avoir utilisee, cet ecran vous permettra d'acheter plus de credits.",
            .spendGiftBeforeBuying: "Utilisez votre cadeau d'Anky avant d'acheter plus de credits."
        ],
        "de": [
            .tabWrite: "Schreiben",
            .tabMap: "Karte",
            .tabYou: "Du",
            .faceIDPrompt: "Schutze dein Anky mit der Geratesperre. Dein Schreiben bleibt lokal, und der Zugriff auf diesem Telefon bleibt privat.",
            .activateFaceID: "Geratesperre aktivieren",
            .notNow: "Nicht jetzt",
            .protectFaceIDReason: "ANKY mit der Geratesperre schutzen.",
            .unlockFaceIDReason: "ANKY entsperren.",
            .launchEmpty: "Der lebendige .anky-String ist der Zustand dieser Sitzung.",
            .launchCountFormat: "Ankys heute: %d",
            .writeAgain: "Noch einmal schreiben",
            .writeMinutesFormat: "%d Minuten schreiben",
            .stepWriteOneCharacter: "Schreibe ein Zeichen",
            .stepKeepThreadAlive: "Halte den Faden lebendig",
            .stepLetSilenceCloseIt: "Lass die Stille ihn schliessen",
            .creditGiftSummary: "1 Guthaben - Geschenk von Anky",
            .creditGiftCaption: "Guthaben - Geschenk von Anky",
            .creditGiftPrompt: "Du hast 1 Guthaben - Geschenk von Anky. Nutze diese erste Reflexion, bevor du mehr Guthaben kaufst.",
            .writeEightMinutes: "8 Minuten schreiben",
            .creditPacksLocked: "Guthabenpakete werden freigeschaltet, nachdem du dein Geschenk von Anky genutzt hast",
            .creditGiftDetail: "Deine erste Reflexion ist abgedeckt. Danach kannst du auf diesem Bildschirm mehr Guthaben kaufen.",
            .spendGiftBeforeBuying: "Nutze dein Geschenk von Anky, bevor du mehr Guthaben kaufst."
        ],
        "it": [
            .tabWrite: "Scrivi",
            .tabMap: "Mappa",
            .tabYou: "Tu",
            .faceIDPrompt: "Proteggi il tuo Anky con il blocco del dispositivo. La tua scrittura resta locale, e questo mantiene privato l'accesso su questo telefono.",
            .activateFaceID: "Attiva blocco",
            .notNow: "Non ora",
            .protectFaceIDReason: "Proteggi ANKY con il blocco del dispositivo.",
            .unlockFaceIDReason: "Sblocca ANKY.",
            .launchEmpty: "La stringa .anky viva e lo stato di questa sessione.",
            .launchCountFormat: "Anky oggi: %d",
            .writeAgain: "Scrivi ancora",
            .writeMinutesFormat: "Scrivi %d minuti",
            .stepWriteOneCharacter: "Scrivi un carattere",
            .stepKeepThreadAlive: "Tieni vivo il filo",
            .stepLetSilenceCloseIt: "Lascia che il silenzio lo chiuda",
            .creditGiftSummary: "1 credito - Regalo di Anky",
            .creditGiftCaption: "credito - Regalo di Anky",
            .creditGiftPrompt: "Hai 1 credito - Regalo di Anky. Usa questa prima riflessione prima di comprare altri crediti.",
            .writeEightMinutes: "Scrivi 8 minuti",
            .creditPacksLocked: "I pacchetti di crediti si sbloccano dopo aver usato il tuo Regalo di Anky",
            .creditGiftDetail: "La tua prima riflessione e coperta. Dopo averla usata, questa schermata ti permettera di comprare altri crediti.",
            .spendGiftBeforeBuying: "Usa il tuo regalo di Anky prima di comprare altri crediti."
        ],
        "ja": [
            .tabWrite: "書く",
            .tabMap: "マップ",
            .tabYou: "あなた",
            .faceIDPrompt: "端末のロックでAnkyを保護しましょう。書いた内容はこの端末に保存され、アクセスをこの電話内でプライベートに保てます。",
            .activateFaceID: "端末ロックを有効にする",
            .notNow: "今はしない",
            .protectFaceIDReason: "端末のロックでANKYを保護します。",
            .unlockFaceIDReason: "ANKYのロックを解除します。",
            .launchEmpty: "生きている.anky文字列が、このセッションの状態です。",
            .launchCountFormat: "今日のAnky: %d",
            .writeAgain: "もう一度書く",
            .writeMinutesFormat: "%d分書く",
            .stepWriteOneCharacter: "1文字を書く",
            .stepKeepThreadAlive: "流れを生かしておく",
            .stepLetSilenceCloseIt: "沈黙に閉じさせる",
            .creditGiftSummary: "1クレジット - Ankyからのギフト",
            .creditGiftCaption: "クレジット - Ankyからのギフト",
            .creditGiftPrompt: "1クレジット - Ankyからのギフトがあります。追加購入の前に、最初のリフレクションで使ってください。",
            .writeEightMinutes: "8分書く",
            .creditPacksLocked: "Ankyからのギフトを使うと、クレジットパックが購入できます",
            .creditGiftDetail: "最初のリフレクションはカバーされています。使った後、この画面で追加クレジットを購入できます。",
            .spendGiftBeforeBuying: "追加購入の前にAnkyからのギフトを使ってください。"
        ],
        "ko": [
            .tabWrite: "쓰기",
            .tabMap: "지도",
            .tabYou: "나",
            .faceIDPrompt: "기기 잠금으로 Anky를 보호하세요. 글은 이 기기에 로컬로 저장되고, 이 전화에서 접근을 비공개로 유지합니다.",
            .activateFaceID: "기기 잠금 켜기",
            .notNow: "나중에",
            .protectFaceIDReason: "기기 잠금으로 ANKY를 보호합니다.",
            .unlockFaceIDReason: "ANKY 잠금 해제.",
            .launchEmpty: "살아 있는 .anky 문자열이 이 세션의 상태입니다.",
            .launchCountFormat: "오늘의 Anky: %d",
            .writeAgain: "다시 쓰기",
            .writeMinutesFormat: "%d분 쓰기",
            .stepWriteOneCharacter: "한 글자 쓰기",
            .stepKeepThreadAlive: "흐름을 살려 두기",
            .stepLetSilenceCloseIt: "침묵이 닫게 두기",
            .creditGiftSummary: "1 크레딧 - Anky의 선물",
            .creditGiftCaption: "크레딧 - Anky의 선물",
            .creditGiftPrompt: "1 크레딧 - Anky의 선물이 있습니다. 추가 크레딧을 사기 전에 첫 리플렉션에 사용하세요.",
            .writeEightMinutes: "8분 쓰기",
            .creditPacksLocked: "Anky의 선물을 사용하면 크레딧 팩이 열립니다",
            .creditGiftDetail: "첫 리플렉션은 이미 제공됩니다. 사용한 뒤 이 화면에서 크레딧을 더 살 수 있습니다.",
            .spendGiftBeforeBuying: "크레딧을 더 사기 전에 Anky의 선물을 사용하세요."
        ],
        "zh": [
            .tabWrite: "书写",
            .tabMap: "地图",
            .tabYou: "你",
            .faceIDPrompt: "使用设备锁保护你的 Anky。你的书写保存在本机，这会让此手机上的访问保持私密。",
            .activateFaceID: "开启设备锁",
            .notNow: "暂时不要",
            .protectFaceIDReason: "使用设备锁保护 ANKY。",
            .unlockFaceIDReason: "解锁 ANKY。",
            .launchEmpty: "活着的 .anky 字符串就是本次会话的状态。",
            .launchCountFormat: "今天的 Anky：%d",
            .writeAgain: "再次书写",
            .writeMinutesFormat: "书写 %d 分钟",
            .stepWriteOneCharacter: "写下一个字符",
            .stepKeepThreadAlive: "让线索保持活着",
            .stepLetSilenceCloseIt: "让沉默完成收束",
            .creditGiftSummary: "1 个额度 - Anky 的礼物",
            .creditGiftCaption: "个额度 - Anky 的礼物",
            .creditGiftPrompt: "你有 1 个额度 - Anky 的礼物。请先用它完成第一次 reflection，再购买更多额度。",
            .writeEightMinutes: "书写 8 分钟",
            .creditPacksLocked: "使用 Anky 的礼物后，额度包才会解锁",
            .creditGiftDetail: "第一次 reflection 已经包含在内。使用之后，你就可以在这里购买更多额度。",
            .spendGiftBeforeBuying: "购买更多额度前，请先使用 Anky 的礼物。"
        ]
    ]
}
