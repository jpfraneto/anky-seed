# Anky-Datenschutzrichtlinie

Gültig und überarbeitet: 27. Oktober 2026

Anky (Anky: Gehmeditation) ist ein Ort zum Schreiben, Sprechen und Aufnehmen, während du gehst oder still bleibst. Was du ausdrückst, wird auf deinem iPhone gespeichert. Es gibt keine Anmeldung, keine Analysen, keine Werbung und kein Tracking, und Anky verwendet deinen Standort nicht.

## 1. Wer wir sind

Anky wird von **Anky, Inc.** betrieben, einer Gesellschaft aus Delaware. Du erreichst uns unter **[support@anky.app](mailto:support@anky.app)**.

Diese Richtlinie gilt für die Anky-App für iOS und die Website anky.app. Anky ist kein medizinisches, psychologisches, Krisen-, Rechts- oder Finanzangebot.

## 2. Was auf deinem iPhone bleibt

Anky speichert Folgendes ausschließlich auf deinem iPhone:

- Deine Sitzungen: Texte (als `.anky`-Dateien), Sprachaufnahmen, Videos und die Angaben zu jeder Sitzung (Beginn und Ende, welche Ausdrucksformen du gewählt hast und die optionale Angabe „gehen“ oder „still bleiben“)
- Reflexionen, die du angefragt hast, sobald sie auf deinem iPhone angekommen sind
- Einen unfertigen Entwurf und den Index, mit dem deine früheren Sitzungen aufgelistet werden
- Deine Einstellungen
- Wenn du die Bildschirmzeit-Sperre nutzt: die gewählten Apps (als undurchsichtige Apple-Kennungen), den Zustand der Sperre und deine Freischaltungen
- Eine zufällige, anonyme Kontokennung, gespeichert im iOS-Schlüsselbund (siehe Abschnitt 4)

Deine Texte, Sprachaufnahmen und Videos werden nicht an Anky gesendet. Wir können sie weder lesen noch hören noch ansehen, und wir haben keine Kopie davon.

## 3. Mikrofon und Kamera

Anky verwendet das Mikrofon nur, während du deine Stimme oder den Ton eines Videos aufnimmst, und die Kamera nur, während du ein Video aufnimmst. Die Aufnahme beginnt, wenn du auf Aufnehmen tippst, und endet, wenn du sie beendest. Eine Sprachaufnahme kann bei gesperrtem Bildschirm weiterlaufen, damit das iPhone beim Gehen in der Tasche bleiben kann; das ist der einzige Grund, warum Anky Audio im Hintergrund nutzt.

Aufnahmen werden auf deinem iPhone gespeichert. Sie werden nie hochgeladen und nie transkribiert, weder von Anky noch von anderen.

## 4. Was Ankys Server erhält

Es gibt kein Konto, das du anlegen musst. Beim ersten Start erzeugt die App auf deinem iPhone eine zufällige, anonyme Kontokennung. Sie ist weder dein Name noch deine E-Mail-Adresse, Telefonnummer oder Apple-ID und wird in der App nie angezeigt. Die App verwendet sie, um die wenigen Anfragen an Ankys Server zu authentifizieren:

- **Prüfung der kostenlosen Tage und des Abos.** Wenn du Anky öffnest, fragt die App den Server, ob deine kostenlosen Tage oder dein Abo aktiv sind. Diese Anfrage enthält keine Texte, Aufnahmen oder Sitzungsinhalte.
- **Eintrag zum kostenlosen Zugang.** Wenn du deine erste Sitzung beginnst, speichert der Server einen nicht umkehrbaren SHA-256-Hash deiner anonymen Kennung und den Zeitpunkt, zu dem deine sieben kostenlosen Tage begonnen haben. Dieser Eintrag enthält nichts, was du geschrieben, gesagt oder aufgenommen hast. **Er bleibt auch nach „Alle Daten löschen“ bestehen**, denn sein einziger Zweck ist, dass die sieben kostenlosen Tage pro Konto nur einmal beginnen und nicht neu gestartet werden können. Mit ihm lässt sich keiner deiner Inhalte wiederherstellen oder lesen.
- **Abo-Status.** Wenn du ein Abo abschließt, speichert der Server deine anonyme Kennung zusammen mit dem Status deines Abos (Produkt, ob es aktiv ist, wann es sich verlängert oder abläuft), den er von RevenueCat erfährt (Abschnitt 6).
- **Reflexionen**, nur wenn du eine anfragst (Abschnitt 5).

Damit der Dienst funktioniert und um Missbrauch zu verhindern, speichert der Server außerdem tägliche Anfragezähler und, bei Reflexionen, einen nicht umkehrbaren Hash des reflektierten Textes (nicht den Text selbst), damit dieselbe Anfrage nicht doppelt verarbeitet oder berechnet wird. Unser Hosting-Anbieter sieht deine IP-Adresse, um jede Anfrage zuzustellen; Anky nutzt sie nur kurz, um missbräuchlichen Verkehr zu begrenzen, und speichert sie nicht zusammen mit deiner Kennung.

## 5. KI-Reflexionen (optional, nur mit Abo)

„Mit Anky reflektieren“ ist optional und nur mit Abo verfügbar. Es wird nichts gesendet, solange du es nicht für einen bestimmten Text antippst und anschließend bestätigst.

- **Was gesendet wird:** die `.anky`-Datei dieses einen Textes, also sein Wortlaut und der zeitliche Verlauf der Tastenanschläge, zusammen mit deiner anonymen Kennung und der App-Version. Sprachaufnahmen und Videos werden nie gesendet.
- **Wer ihn verarbeitet:** Ankys Server gibt den Text an einen KI-Inferenz-Anbieter weiter, der ein großes Sprachmodell ausführt (derzeit die Claude-Modelle von Anthropic, erreicht über KI-Gateway-Dienste), um die Reflexion zu schreiben. Anky nutzt nur Anbieter, die für Zero Data Retention konfiguriert sind, ohne Protokollierung der Inhalte und ohne Training mit ihnen; ist kein solcher Anbieter verfügbar, wird keine Reflexion erstellt.
- **Aufbewahrung:** Ankys Server speichert weder deinen Text noch die Reflexion. Der Modellanbieter verarbeitet den Text nur, um die Reflexion zu erzeugen. Die Reflexion wird an dein iPhone zurückgeschickt und dort gespeichert.

Nichts sonst in Anky nutzt KI.

## 6. Abos und Zahlung

Anky bietet sieben kostenlose Tage seines Kernangebots, ab deiner ersten Sitzung. Es werden keine Zahlungsdaten erfasst, und wenn sie enden, wird nichts abgebucht.

Das Abo ist ein sich automatisch verlängerndes Monatsabo, das Apple über den App Store verkauft. Apple wickelt die Zahlung ab; Anky erhält nie deine Karten- oder Rechnungsdaten. Anky verwendet **RevenueCat** zur Verwaltung von Abos: RevenueCat erhält deine anonyme Kontokennung sowie deine App-Store-Kauf- und Abo-Datensätze, um der App sagen zu können, ob du ein Abo hast. Die Datenschutzerklärung von RevenueCat findest du unter [revenuecat.com/privacy](https://www.revenuecat.com/privacy). Kündige oder verwalte dein Abo in den Abo-Einstellungen deines Apple Accounts.

Wenn deine kostenlosen Tage enden und du kein Abo abschließt, bleibt alles, was du bereits erstellt hast, auf deinem iPhone – lesbar und exportierbar.

## 7. Was Anky nicht tut

- Anky lädt deine Texte, deine Stimme oder deine Videos weder hoch noch transkribiert sie. Der einzige Inhalt, der dein iPhone je verlässt, ist ein einzelner Text, den du für eine Reflexion senden möchtest.
- Anky verwendet deinen Standort nicht.
- Anky enthält keine SDKs für Analysen, Absturzberichte, Werbung oder Tracking und verfolgt dich nicht über Apps oder Websites hinweg.
- Anky verkauft oder teilt deine Daten nicht und nutzt sie nicht zum Training von KI-Modellen.

## 8. Apple-Dienste, die du nutzen kannst

- **iCloud-Backup:** Wenn du es aktivierst, verschlüsselt Anky deine Texte und Reflexionen mit AES-GCM und speichert die verschlüsselte Datei in deinem eigenen iCloud Drive. Sprachaufnahmen und Videos sind nicht enthalten. Was zum Entschlüsseln des Backups nötig ist, wird in deinem iCloud-Schlüsselbund gespeichert, damit du es auf einem neuen iPhone wiederherstellen kannst. Apple betreibt iCloud; Anky sieht das Backup nie.
- **Bildschirmzeit:** Wenn du die Sperre aktivierst, übernehmen Apples Bildschirmzeit-Frameworks die Berechtigung und die App-Auswahl. Deine App-Liste bleibt auf dem Gerät.
- **Mitteilungen:** Erinnerungen und die Mitteilungen der Sperre werden lokal von iOS geplant.
- **Face ID:** wird nur verwendet, um zu bestätigen, dass du es bist, bevor das iCloud-Backup aktiviert wird. Apple führt die Prüfung durch; Anky erfährt nur Ja oder Nein.

Die Geräte-Backups deines iPhones, falls du sie nutzt, verwaltet Apple nach eigenen Bedingungen.

## 9. Export

**Einstellungen → Meine Erinnerungen exportieren** erstellt eine einzige .zip-Datei mit den Angaben zu jeder Sitzung, den Original-Audio- und -Videodateien, deinen Texten als `.anky` und als reinem Text sowie deinen Reflexionen als Markdown. Der Export funktioniert mit oder ohne Abo. Wohin die Datei danach geht, entscheidest du.

## 10. Deine Daten löschen

Lösche eine einzelne Sitzung oder einen Text über das jeweilige Menü. **Einstellungen → Alle Daten löschen** entfernt jede Sitzung, jeden Text, jede Sprachaufnahme, jedes Video, jede Reflexion und jede Einstellung von deinem iPhone, zusammen mit der anonymen Kennung und deinem Anky-iCloud-Backup. Wenn du die App löschst, werden ihre lokalen Daten ebenfalls entfernt.

„Alle Daten löschen“ kündigt kein Abo; kündige es bei Apple. Der in Abschnitt 4 beschriebene anonyme Eintrag zum kostenlosen Zugang bleibt bestehen, damit die kostenlosen Tage nicht neu beginnen können. Der Abo-Status auf Ankys Server und der Kundeneintrag bei RevenueCat sind nur mit der anonymen Kennung verknüpft; sobald sie von deinem iPhone gelöscht ist, lassen sich diese Einträge weder dir noch etwas, das du erstellt hast, zuordnen. Für jede andere Löschanfrage schreib an **[support@anky.app](mailto:support@anky.app)**.

## 11. Support

Die Einstellungen können deine Mail-App oder einen Chat-Link öffnen. Es wird nichts gesendet, solange du es nicht sendest, und dann erhalten wir, was du schreiben wolltest.

## 12. Kinder, Änderungen und Kontakt

Anky ist nicht für Kinder unter 13 Jahren gedacht. Wenn sich diese Richtlinie ändert, aktualisieren wir sie hier und passen das Datum oben an.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
