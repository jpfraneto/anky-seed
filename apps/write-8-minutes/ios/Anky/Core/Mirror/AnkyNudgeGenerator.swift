import Foundation

struct AnkyNudgeGenerator {
    static func generateNudge(from writing: String, timeWritten: TimeInterval, wordCount: Int, offset: Int = 0) -> String {
        let language = detectLanguage(in: writing)
        let theme = detectTheme(in: writing, timeWritten: timeWritten, wordCount: wordCount)
        let messages = messagesByLanguage[language]?[theme]
            ?? messagesByLanguage[language]?["default"]
            ?? messagesByLanguage["en"]?["default"]
            ?? ["keep writing."]
        let index = stableIndex(from: writing, count: messages.count, offset: offset)
        return messages[index]
    }

    private static func detectLanguage(in text: String) -> String {
        let lower = text.lowercased()
        let spanishMarkers = matches(
            [" que ", " el ", " la ", " de ", " en ", " con ", " por ", " para ", " pero ", " siento ", " tengo ", " quiero ", " estoy ", " porque "],
            in: " \(lower) "
        )
        let hasSpanishCharacters = lower.range(of: #"[áéíóúñ¿¡]"#, options: .regularExpression) != nil
        return spanishMarkers >= 2 || hasSpanishCharacters ? "es" : "en"
    }

    private static func detectTheme(in text: String, timeWritten: TimeInterval, wordCount: Int) -> String {
        let lower = text.lowercased()
        if matches(["fear", "scared", "anxious", "worried", "terrified", "panic", "afraid", "miedo", "ansiedad", "asustado", "preocupado"], in: lower) > 0 {
            return "fear"
        }
        if matches(["love", "child", "family", "kid", "baby", "daughter", "son", "partner", "amor", "familia", "hija", "hijo", "pareja"], in: lower) > 0 {
            return "love"
        }
        if matches(["work", "code", "project", "build", "startup", "company", "product", "trabajo", "codigo", "proyecto", "empresa", "producto"], in: lower) > 0 {
            return "work"
        }
        if matches(["stuck", "can't", "dont know", "don't know", "lost", "confused", "blocked", "atascado", "perdido", "confundido", "bloqueado", "no se"], in: lower) > 0 {
            return "stuck"
        }
        if matches(["angry", "frustrated", "tired", "exhausted", "drained", "burnt", "enojado", "frustrado", "cansado", "agotado", "quemado"], in: lower) > 0 {
            return "exhaustion"
        }
        if matches(["dream", "vision", "idea", "want", "hope", "wish", "imagine", "sueno", "vision", "idea", "quiero", "espero", "imagino"], in: lower) > 0 {
            return "aspiration"
        }
        if timeWritten < 240 {
            return "early"
        }
        if wordCount < 50 {
            return "brief"
        }
        return "default"
    }

    private static func matches(_ needles: [String], in text: String) -> Int {
        needles.reduce(0) { count, needle in
            text.contains(needle) ? count + 1 : count
        }
    }

    private static func stableIndex(from writing: String, count: Int, offset: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        let seed = writing.prefix(240).unicodeScalars.reduce(5381) { partial, scalar in
            ((partial << 5) &+ partial) &+ Int(scalar.value)
        }
        return abs(seed + offset) % count
    }

    private static let messagesByLanguage: [String: [String: [String]]] = [
        "en": [
            "fear": [
                "I see you circling something that keeps you awake. Keep writing; the shape will reveal itself.",
                "There's a fear here you've been carrying. You do not have to name it yet.",
                "The thing you're afraid of is already in these words. Stay close to it."
            ],
            "love": [
                "Something tender is surfacing here. Do not protect it; let it be messy.",
                "There's love in these words that does not know what to do with itself.",
                "The way you write about this tells me enough. Keep going."
            ],
            "work": [
                "Behind the work, there's a hunger. What is it really asking for?",
                "You're building something, but I'm hearing the person behind the builder.",
                "The project is a container. What is trying to break through it?"
            ],
            "stuck": [
                "The not-knowing is the doorway. Stay in it.",
                "You do not need to know where this is going. Keep walking.",
                "Being stuck is the writing. This is the session."
            ],
            "exhaustion": [
                "The exhaustion is data. What is it pointing toward?",
                "You're tired. The ritual can hold that without fixing it.",
                "I hear the weight in these words. Let them carry it for a moment."
            ],
            "aspiration": [
                "That want has a pulse. Follow it.",
                "There's a future self in these words trying to reach you.",
                "The dream you're circling is already closer than it feels."
            ],
            "early": [
                "You're just getting started. The thread is forming.",
                "Give it a few more minutes. The real material is still coming.",
                "I'm here. The first words are always the hardest."
            ],
            "brief": [
                "Every word counts. Keep them coming.",
                "The silence between words is part of the writing too.",
                "You do not need to fill the space. Just be honest in it."
            ],
            "default": [
                "I'm here. Keep going; the thread is forming.",
                "Something is trying to surface. Do not rush it.",
                "Every word you write changes what comes next.",
                "You're doing the work. I'm witnessing it.",
                "The writing knows where it's going. Trust it."
            ]
        ],
        "es": [
            "fear": [
                "Veo que rodeas algo que no te deja dormir. Sigue escribiendo; va a tomar forma.",
                "Hay un miedo aqui que vienes cargando. Todavia no tienes que nombrarlo.",
                "Eso que temes ya esta en estas palabras. Quedate cerca."
            ],
            "love": [
                "Algo tierno esta saliendo aqui. No lo protejas; dejalo ser desordenado.",
                "Hay amor en estas palabras y todavia no sabe donde ponerse.",
                "La forma en que escribes sobre esto ya dice bastante. Sigue."
            ],
            "work": [
                "Detras del trabajo hay un hambre. Que esta pidiendo de verdad?",
                "Estas construyendo algo, pero escucho a la persona detras de quien construye.",
                "El proyecto es un contenedor. Que quiere atravesarlo?"
            ],
            "stuck": [
                "El no saber es la puerta. Quedate ahi.",
                "No necesitas saber hacia donde va esto. Sigue caminando.",
                "Estar bloqueado tambien es escritura. Esta es la sesion."
            ],
            "exhaustion": [
                "El cansancio es informacion. Hacia donde esta apuntando?",
                "Estas cansado. El ritual puede sostener eso sin arreglarlo.",
                "Escucho el peso en estas palabras. Deja que lo carguen un momento."
            ],
            "aspiration": [
                "Ese deseo tiene pulso. Siguelo.",
                "Hay un yo futuro en estas palabras intentando alcanzarte.",
                "El sueno que rodeas ya esta mas cerca de lo que parece."
            ],
            "early": [
                "Apenas estas entrando. El hilo se esta formando.",
                "Dale unos minutos mas. Lo verdadero todavia viene en camino.",
                "Estoy aqui. Las primeras palabras siempre cuestan mas."
            ],
            "brief": [
                "Cada palabra cuenta. Dejalas seguir llegando.",
                "El silencio entre palabras tambien es parte de la escritura.",
                "No tienes que llenar el espacio. Solo se honesto ahi."
            ],
            "default": [
                "Estoy aqui. Sigue; el hilo se esta formando.",
                "Algo quiere salir a la superficie. No lo apures.",
                "Cada palabra que escribes cambia lo que viene despues.",
                "Estas haciendo el trabajo. Lo estoy presenciando.",
                "La escritura sabe hacia donde va. Confia."
            ]
        ]
    ]
}
