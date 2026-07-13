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
    case writeEightMinutes
}

enum AnkyLocalization {
    static func text(_ key: AnkyLocalizedKey, _ arguments: CVarArg...) -> String {
        let format = localizedFormat(for: key)
        return formatted(format, arguments)
    }

    static func ui(_ key: String, _ arguments: CVarArg...) -> String {
        let format = resourceLocalizedString(forKey: key)
            ?? key
        return formatted(format, arguments)
    }

    private static func formatted(_ format: String, _ arguments: [CVarArg]) -> String {
        guard !arguments.isEmpty else {
            return format
        }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func localizedFormat(for key: AnkyLocalizedKey) -> String {
        if let localized = resourceLocalizedString(forKey: key.rawValue) {
            return localized
        }

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
        case "es", "pt", "fr", "de", "it", "ja", "ko", "zh", "hi":
            return code
        default:
            return "en"
        }
    }

    private static func resourceLocalizedString(forKey key: String) -> String? {
        let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        guard localized != key else {
            return nil
        }
        return localized
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
            .writeEightMinutes: "Write 8 minutes"
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
            .writeEightMinutes: "Escribir 8 minutos"
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
            .writeEightMinutes: "Escrever 8 minutos"
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
            .writeEightMinutes: "Ecrire 8 minutes"
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
            .writeEightMinutes: "8 Minuten schreiben"
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
            .writeEightMinutes: "Scrivi 8 minuti"
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
            .writeEightMinutes: "8分書く"
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
            .writeEightMinutes: "8분 쓰기"
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
            .writeEightMinutes: "书写 8 分钟"
        ]
    ]
}
