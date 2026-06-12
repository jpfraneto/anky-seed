package inc.anky.android.localization

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Element

class LocalizationResourceTest {
    @Test
    fun androidLocalesMatchIosLocalesAndLocaleConfig() {
        val root = repoRoot()
        val iosLocales = root
            .resolve("apps/ios/Anky")
            .listFiles { file -> file.isDirectory && file.name.endsWith(".lproj") }
            .orEmpty()
            .map { it.name.removeSuffix(".lproj") }
            .sorted()

        val androidRes = root.resolve("apps/android/app/src/main/res")
        val androidLocales = androidRes
            .listFiles { file -> file.isDirectory && file.name.startsWith("values") }
            .orEmpty()
            .mapNotNull { it.name.androidResourceLocale() }
            .sorted()

        val localeConfigLocales = androidRes
            .resolve("xml/locales_config.xml")
            .xmlElements("locale")
            .mapNotNull { it.getAttribute("android:name").ifBlank { null } }
            .map { it.androidLocaleTagToIosLocale() }
            .sorted()

        assertEquals(iosLocales, androidLocales)
        assertEquals(iosLocales, localeConfigLocales)
    }

    @Test
    fun translatedStringResourcesHaveNoMissingTranslatableStrings() {
        val valuesRoot = repoRoot().resolve("apps/android/app/src/main/res")
        val baseKeys = valuesRoot.resolve("values").translatableStringKeys()
        val translatedValuesDirs = valuesRoot
            .listFiles { file -> file.isDirectory && file.name.startsWith("values-") }
            .orEmpty()
            .sortedBy { it.name }

        translatedValuesDirs.forEach { dir ->
            assertEquals("Missing strings in ${dir.name}", emptySet<String>(), baseKeys - dir.translatableStringKeys())
            assertEquals("Extra strings in ${dir.name}", emptySet<String>(), dir.translatableStringKeys() - baseKeys)
        }
    }
}

private fun File.translatableStringKeys(): Set<String> =
    listFiles { file -> file.extension == "xml" }
        .orEmpty()
        .flatMap { file ->
            file.xmlElements("string")
                .filter { it.getAttribute("translatable") != "false" }
                .map { it.getAttribute("name") }
        }
        .toSet()

private fun File.xmlElements(tagName: String): List<Element> {
    val document = DocumentBuilderFactory
        .newInstance()
        .newDocumentBuilder()
        .parse(this)
    return (0 until document.getElementsByTagName(tagName).length)
        .map { document.getElementsByTagName(tagName).item(it) as Element }
}

private fun String.androidResourceLocale(): String? =
    when (this) {
        "values" -> "en"
        "values-zh-rCN" -> "zh-Hans"
        else -> removePrefix("values-").takeIf { it != this }
    }

private fun String.androidLocaleTagToIosLocale(): String =
    if (this == "zh-Hans") "zh-Hans" else this

private fun repoRoot(): File {
    var current = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
    while (!File(current, ".git").exists()) {
        current = current.parentFile ?: return current
    }
    return current
}
