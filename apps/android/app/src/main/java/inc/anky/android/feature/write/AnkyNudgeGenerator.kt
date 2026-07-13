package inc.anky.android.feature.write

/**
 * Local, zero-network nudges for free sessions — port of
 * ios/Anky/Core/Mirror/AnkyNudgeGenerator.swift (EN/ES, themed, with a
 * writing-stable message index so the same page keeps the same voice).
 */
object AnkyNudgeGenerator {
    fun generateNudge(writing: String, timeWrittenSeconds: Double, wordCount: Int, offset: Int = 0): String {
        val language = detectLanguage(writing)
        val theme = detectTheme(writing, timeWrittenSeconds, wordCount)
        val messages = messagesByLanguage[language]?.get(theme)
            ?: messagesByLanguage[language]?.get("default")
            ?: messagesByLanguage["en"]?.get("default")
            ?: listOf("keep writing.")
        return messages[stableIndex(writing, messages.size, offset)]
    }

    internal fun detectLanguage(text: String): String {
        val lower = text.lowercase()
        val spanishMarkers = matches(
            listOf(
                " que ", " el ", " la ", " de ", " en ", " con ", " por ", " para ",
                " pero ", " siento ", " tengo ", " quiero ", " estoy ", " porque ",
            ),
            " $lower ",
        )
        val hasSpanishCharacters = lower.any { it in "áéíóúñ¿¡" }
        return if (spanishMarkers >= 2 || hasSpanishCharacters) "es" else "en"
    }

    internal fun detectTheme(text: String, timeWrittenSeconds: Double, wordCount: Int): String {
        val lower = text.lowercase()
        if (matches(listOf("fear", "scared", "anxious", "worried", "terrified", "panic", "afraid", "miedo", "ansiedad", "asustado", "preocupado"), lower) > 0) {
            return "fear"
        }
        if (matches(listOf("love", "child", "family", "kid", "baby", "daughter", "son", "partner", "amor", "familia", "hija", "hijo", "pareja"), lower) > 0) {
            return "love"
        }
        if (matches(listOf("work", "code", "project", "build", "startup", "company", "product", "trabajo", "codigo", "proyecto", "empresa", "producto"), lower) > 0) {
            return "work"
        }
        if (matches(listOf("stuck", "can't", "dont know", "don't know", "lost", "confused", "blocked", "atascado", "perdido", "confundido", "bloqueado", "no se"), lower) > 0) {
            return "stuck"
        }
        if (matches(listOf("angry", "frustrated", "tired", "exhausted", "drained", "burnt", "enojado", "frustrado", "cansado", "agotado", "quemado"), lower) > 0) {
            return "exhaustion"
        }
        if (matches(listOf("dream", "vision", "idea", "want", "hope", "wish", "imagine", "sueno", "vision", "idea", "quiero", "espero", "imagino"), lower) > 0) {
            return "aspiration"
        }
        if (timeWrittenSeconds < 240) {
            return "early"
        }
        if (wordCount < 50) {
            return "brief"
        }
        return "default"
    }

    private fun matches(needles: List<String>, text: String): Int =
        needles.count { text.contains(it) }

    internal fun stableIndex(writing: String, count: Int, offset: Int): Int {
        if (count <= 0) return 0
        // djb2 over the first 240 unicode scalars, exactly like the Swift port.
        var seed = 5381L
        var scalars = 0
        var index = 0
        while (index < writing.length && scalars < 240) {
            val codePoint = writing.codePointAt(index)
            seed = (seed shl 5) + seed + codePoint
            index += Character.charCount(codePoint)
            scalars += 1
        }
        val shifted = seed + offset
        return (if (shifted < 0) -shifted else shifted).mod(count.toLong()).toInt()
    }

    private val messagesByLanguage: Map<String, Map<String, List<String>>> = mapOf(
        "en" to mapOf(
            "fear" to listOf(
                "I see you circling something that keeps you awake. Keep writing; the shape will reveal itself.",
                "There's a fear here you've been carrying. You do not have to name it yet.",
                "The thing you're afraid of is already in these words. Stay close to it.",
            ),
            "love" to listOf(
                "Something tender is surfacing here. Do not protect it; let it be messy.",
                "There's love in these words that does not know what to do with itself.",
                "The way you write about this tells me enough. Keep going.",
            ),
            "work" to listOf(
                "Behind the work, there's a hunger. What is it really asking for?",
                "You're building something, but I'm hearing the person behind the builder.",
                "The project is a container. What is trying to break through it?",
            ),
            "stuck" to listOf(
                "The not-knowing is the doorway. Stay in it.",
                "You do not need to know where this is going. Keep walking.",
                "Being stuck is the writing. This is the session.",
            ),
            "exhaustion" to listOf(
                "The exhaustion is data. What is it pointing toward?",
                "You're tired. The ritual can hold that without fixing it.",
                "I hear the weight in these words. Let them carry it for a moment.",
            ),
            "aspiration" to listOf(
                "That want has a pulse. Follow it.",
                "There's a future self in these words trying to reach you.",
                "The dream you're circling is already closer than it feels.",
            ),
            "early" to listOf(
                "You're just getting started. The thread is forming.",
                "Give it a few more minutes. The real material is still coming.",
                "I'm here. The first words are always the hardest.",
            ),
            "brief" to listOf(
                "Every word counts. Keep them coming.",
                "The silence between words is part of the writing too.",
                "You do not need to fill the space. Just be honest in it.",
            ),
            "default" to listOf(
                "I'm here. Keep going; the thread is forming.",
                "Something is trying to surface. Do not rush it.",
                "Every word you write changes what comes next.",
                "You're doing the work. I'm witnessing it.",
                "The writing knows where it's going. Trust it.",
            ),
        ),
        "es" to mapOf(
            "fear" to listOf(
                "Veo que rodeas algo que no te deja dormir. Sigue escribiendo; va a tomar forma.",
                "Hay un miedo aqui que vienes cargando. Todavia no tienes que nombrarlo.",
                "Eso que temes ya esta en estas palabras. Quedate cerca.",
            ),
            "love" to listOf(
                "Algo tierno esta saliendo aqui. No lo protejas; dejalo ser desordenado.",
                "Hay amor en estas palabras y todavia no sabe donde ponerse.",
                "La forma en que escribes sobre esto ya dice bastante. Sigue.",
            ),
            "work" to listOf(
                "Detras del trabajo hay un hambre. Que esta pidiendo de verdad?",
                "Estas construyendo algo, pero escucho a la persona detras de quien construye.",
                "El proyecto es un contenedor. Que quiere atravesarlo?",
            ),
            "stuck" to listOf(
                "El no saber es la puerta. Quedate ahi.",
                "No necesitas saber hacia donde va esto. Sigue caminando.",
                "Estar bloqueado tambien es escritura. Esta es la sesion.",
            ),
            "exhaustion" to listOf(
                "El cansancio es informacion. Hacia donde esta apuntando?",
                "Estas cansado. El ritual puede sostener eso sin arreglarlo.",
                "Escucho el peso en estas palabras. Deja que lo carguen un momento.",
            ),
            "aspiration" to listOf(
                "Ese deseo tiene pulso. Siguelo.",
                "Hay un yo futuro en estas palabras intentando alcanzarte.",
                "El sueno que rodeas ya esta mas cerca de lo que parece.",
            ),
            "early" to listOf(
                "Apenas estas entrando. El hilo se esta formando.",
                "Dale unos minutos mas. Lo verdadero todavia viene en camino.",
                "Estoy aqui. Las primeras palabras siempre cuestan mas.",
            ),
            "brief" to listOf(
                "Cada palabra cuenta. Dejalas seguir llegando.",
                "El silencio entre palabras tambien es parte de la escritura.",
                "No tienes que llenar el espacio. Solo se honesto ahi.",
            ),
            "default" to listOf(
                "Estoy aqui. Sigue; el hilo se esta formando.",
                "Algo quiere salir a la superficie. No lo apures.",
                "Cada palabra que escribes cambia lo que viene despues.",
                "Estas haciendo el trabajo. Lo estoy presenciando.",
                "La escritura sabe hacia donde va. Confia.",
            ),
        ),
    )
}
