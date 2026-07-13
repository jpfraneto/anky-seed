# Anky-Datenschutzrichtlinie

Gültig und überarbeitet am 11. Juli 2026

Anky arbeitet lokal zuerst. Die grundlegende Schreibfunktion benötigt weder Anmeldung noch Abo. Deine Texte bleiben auf dem Gerät, außer du exportierst oder sicherst sie, kontaktierst den Support oder forderst ausdrücklich eine servergenerierte Funktion an.

## 1. Wer wir sind

Anky wird von **Anky, Inc.**, einer Gesellschaft aus Delaware, betrieben. Kontakt: **[support@anky.app](mailto:support@anky.app)**.

Diese Richtlinie gilt für die iOS-App, anky.app, das Anky-Backend, Käufe, Support und verbundene Dienste. Anky ist kein medizinischer, psychologischer oder Krisendienst und keine professionelle Beratung.

## 2. Kostenlose und Pro-Funktionen

Folgendes bleibt kostenlos und benötigt kein Anky Pro:

- Neue Schreibsitzungen beginnen und abschließen
- Lokale Texte erstellen, fortsetzen, speichern, durchsuchen, kopieren, exportieren und löschen
- Bereits gespeicherte Reflexionen lesen
- Ein lokaler Schreibimpuls ohne Server, wenn Pro inaktiv ist
- Bildschirmzeit-Sperre, Auswahl geschützter Apps und Schutz ein-/ausschalten
- Drei tägliche Schnellpässe nach der aktuellen Freigaberegel
- Notfallzugang und Notfallentsperrung
- Statische Gemälde bis einschließlich Level 8
- Bereits gelieferte personalisierte Gemälde
- Archiv und Schreibverlauf
- Einstellungen, lokale/iCloud-Sicherung, Import/Export, Kontolöschung, Support und Rechtstexte

Nur diese Bereiche erfordern die aktive kleingeschriebene Berechtigung `pro`:

1. Neue servergenerierte KI-Reflexionen für Texte ohne gespeicherte Reflexion, vorbehaltlich der Dienstlimits.
2. Servergenerierte KI-Schreibimpulse statt der kostenlosen lokalen Variante, vorbehaltlich der Limits.
3. Voller Zugriff auf die 96-tägige Schreibreise.
4. Automatische Bildschirmzeit-Entsperrung für den restlichen Tag nach Erreichen des festgelegten Tagesziels.
5. Adaptive Vorschläge für das Tagesziel.
6. Fortschritt nach Level 8, einschließlich personalisierter Gemälde und späterer Zeremonien, abhängig von Fortschritt, Schreiben sowie Sicherheits-, Kapazitäts- und Generierungslimits.

Generierte Dienste unterliegen stets angemessenen Dienst-, Sicherheits-, Kapazitäts- und Missbrauchsschutzlimits.

## 3. Lokal gespeicherte Informationen

Anky speichert auf dem Gerät oder in der gemeinsamen App-Gruppe:

- `.anky`-Dateien, aktive Entwürfe, lesbare Rekonstruktionen und Sitzungsindex
- Gespeicherte KI-Reflexionen und heruntergeladene Gemälde
- Schreibzeit, Level, Reise, Tagesziel, Pässe und Entsperrstatus
- Einstellungen, Erinnerungen, Bildschirmzeit-App-/Kategorie-Tokens und Sperrstatus
- Eine pseudonyme Anky-Autor-/App-Nutzerkennung und Signaturschlüssel im iOS-Schlüsselbund
- Eine Wiederherstellungsphrase, sofern du sie nicht freiwillig im iCloud-Schlüsselbund sicherst
- Einen nicht maßgeblichen Abo-Cache für die Anzeige; bezahlte Aktionen verlangen eine aktuelle Prüfung

Schreiben, Speichern, Fortsetzen, Durchsuchen, Kopieren, Exportieren, Löschen, Lesen vorhandener Reflexionen sowie Sperre, Schnellpässe und Notfallzugang senden deinen Text nicht an das Backend.

Bildschirmzeit-Auswahlen bleiben in Apple-Frameworks und lokalem Speicher. Anky sendet die Liste geschützter Apps nicht an das Backend.

## 4. Informationen bei generierten Diensten

### KI-Reflexionen

Wenn du ausdrücklich eine neue Reflexion anforderst, sendet die App die exakten `.anky`-Bytes über eine authentifizierte Verbindung an das Anky-Backend. Es prüft Datei und Hash, rekonstruiert den Text und sendet ihn mit Anweisungen an den konfigurierten KI-Anbieter. Die Reflexion kehrt zum Gerät zurück und wird lokal gespeichert.

### KI-Schreibimpulse

Wenn Pro aktuell verifiziert ist und du einen Serverimpuls anforderst, wird der aktuelle `.anky`-Text über denselben Weg verarbeitet. Ist Pro inaktiv oder nicht prüfbar, nutzt die App die lokale Variante und sendet dafür keinen Text.

### Personalisierte Gemälde nach Level 8

Ist personalisierter Fortschritt verfügbar, sendet die App den Text seit dem vorherigen Level an das Backend. Ein Modell verdichtet visuelle Themen; der abgeleitete Prompt geht an einen Bildanbieter. Der Rohtext wird nur vorübergehend verarbeitet und nicht in der Datenbank gespeichert. Gemäldedateien und kontobezogene Metadaten werden für erneute Zustellung gespeichert, bis das Konto gelöscht wird oder betriebliche/rechtliche Pflichten etwas anderes erfordern.

Der Dienst nutzt **OpenRouter** für die Modellweiterleitung. Der aktuelle Code kann Textmodelle von Anthropic, Google und DeepSeek sowie Bildmodelle von OpenAI einsetzen. Bankr- oder Poiesis-Endpunkte werden nur bei Konfiguration genutzt; datenschutzsensible Wege werden ohne Bestätigung der verlangten Nullspeicherung übersprungen. Anbieter verarbeiten Inhalte nach eigenen Bedingungen.

Anky fordert, soweit verfügbar, Einstellungen ohne Training und mit Nullspeicherung an, kann aber keine identischen Drittanbieterpraktiken garantieren. Sende nichts, das du für die gewünschte Funktion nicht verarbeiten lassen möchtest.

## 5. Backend- und Betriebsdaten

Das Backend verwendet eine pseudonyme Kennung aus dem lokalen kryptografischen Profil, kein klassisches Passwortkonto. Signierte Anfragen beweisen deren Kontrolle, ohne die Wiederherstellungsphrase zu senden.

Für Betrieb und Schutz können gespeichert werden:

- Pseudonyme Kennung
- Sitzungshashes, Dauer und Zeitpunkte für den Fortschritt, niemals der Text
- Level-/Zeremonienstatus, Gemäldedateien und -metadaten, Generierungs- und Idempotenzstatus
- Kontingente und Missbrauchsschutzzähler
- Produkt, Transaktion, Store, Zeitraum, Ablauf und `pro`-Status von RevenueCat
- Eigene Ereignisse wie Einführung, Paywall, Kauf, Ablauf und Notfallentsperrung mit gehashter oder pseudonymer Kennung
- Bereinigte Diagnosen: Zeit, App-Version, Plattform, Anfragehash, Route, Anbieter, Status-/Fehlerkategorie und Latenz

Das Backend ist so gebaut, dass Rohtext, rekonstruierter Text sowie Reflexions- oder Impulstext nach der Antwort nicht gespeichert werden. Anky trainiert keine eigenen Modelle mit deinen Texten. Inhalt kann nur aufbewahrt werden, wenn du ihn bewusst dem Support sendest, zur Untersuchung eines von dir gemeldeten Vorfalls oder aufgrund einer Rechtspflicht.

Anky enthält keine Werbung und kein appübergreifendes Tracking. Daten werden nicht verkauft und Texte nicht für Werbung genutzt. Eigene Ereignisse und Diagnosen dienen Funktion, Zuverlässigkeit, Kapazität, Sicherheit, Missbrauchsschutz und begrenzter Produktanalyse.

## 6. Apple, RevenueCat und Abos

Anky bietet optionale automatisch verlängerbare Monats- und Jahresabos über den App Store. Beide schalten dieselben Pro-Funktionen frei. Maßgeblich sind der lokalisierte Preis und die Bedingungen, die Apple beim Kauf anzeigt.

Das Jahresabo kann nur für berechtigte Personen und nur bei Anzeige durch Apple einen dreitägigen Test enthalten. Das Monatsabo hat derzeit keinen Einführungstest. Abos verlängern sich automatisch, sofern sie nicht in Apples Abo-Einstellungen gekündigt werden.

Apple bearbeitet Zahlung, Verlängerung, Kündigung, Abrechnung, Verlauf und Erstattung. Anky erhält oder speichert keine vollständigen Kartendaten.

RevenueCat validiert Käufe und liefert Berechtigungen. Apple und RevenueCat stellen Produkt-, Kauf-, Transaktions-, Abo-, Store-, Ablauf-, Test- und Berechtigungsdaten bereit, die mit der pseudonymen Kennung verknüpft sind. Kauf und Wiederherstellung aktualisieren den Status. Werbe- oder unbefristete Freigaben können Pro ebenfalls aktivieren.

Anky verkauft oder verwendet keine Reflexions-Credits, Credit-Pakete oder Credit-Guthaben.

## 7. Optionale Dienste und Entscheidungen

- **Verschlüsselte iCloud-Sicherung:** Bei Aktivierung speichert Anky ein AES-GCM-verschlüsseltes Archiv deiner Texte und Reflexionen in iCloud Documents. Die Wiederherstellungsphrase kann auf Wunsch separat im iCloud-Schlüsselbund liegen.
- **Import/Export/Teilen:** Dateien gehen zum gewählten Ziel. Exportierte Kopien kann Anky nicht kontrollieren.
- **Mitteilungen:** iOS speichert Erlaubnis und Zeitplan. Eine Testende-Erinnerung entsteht nur aus einem aktuell verifizierten Test.
- **Sprache und Fotos:** Wählst du diese Check-ins, gelten Apple-Berechtigungen. Das aktuelle Check-in-Bild wird weder zum Backend hochgeladen noch als personalisierte Gemäldeeingabe gespeichert.
- **Optionales Profilbild:** Ein beim Onboarding gewähltes Selfie/Avatar bleibt in den lokalen App-Dokumenten und wird nicht zum Backend hochgeladen. Es kann in aktivierten Apple-Gerätebackups enthalten sein.
- **Support:** Die App öffnet dein Mailprogramm. Du entscheidest, ob du Adresse, pseudonyme Support-ID, Version, Text, Bilder oder Anhänge sendest.

## 8. Aufbewahrung und Löschung

Lokale Daten bleiben bis zur Einzellöschung, In-App-Löschung, Entfernung passender Sicherungen oder App-Löschung. App-Löschung kündigt kein Abo.

**Konto und Daten löschen** sendet eine authentifizierte Anfrage zur Löschung backendbezogener Daten und entfernt anschließend Texte, Reflexionen, Einstellungen, Kennungen, Wiederherstellungsmaterial, Cache und die erreichbare Anky-iCloud-Sicherung. Das Backend löscht Sitzungs-/Leveldaten, Ereignisse, Kontingente, Generierungen und personalisierte Gemälde unter Ankys Kontrolle.

Anky kann Apple-Kaufverlauf, rechtlich oder zur Validierung nötige RevenueCat-Daten, legitim aufbewahrte Supportnachrichten, exportierte Dateien oder Apple-Sicherungen nicht löschen. Ein späterer RevenueCat-Webhook kann minimalen Abo-Status neu anlegen.

Betriebsdaten bleiben nur so lange, wie für diese Zwecke, Rechtspflichten, Sicherheit, Betrug/Missbrauch, Streitfälle und Buchhaltung angemessen nötig. Kontakt: **[support@anky.app](mailto:support@anky.app)**.

## 9. Sicherheit, internationale Verarbeitung und Rechte

Wir nutzen angemessene Maßnahmen wie verschlüsselte Übertragung, signierte Anfragen, Schlüsselbund und verschlüsselte optionale Sicherungen. Kein System ist vollkommen sicher. Schütze Gerät, Apple-ID, Wiederherstellungsphrase und Exporte.

Anky, Inc. sitzt in den USA. Freiwillig gesendete Daten können dort oder in anderen Ländern der Anbieter verarbeitet werden.

Je nach Wohnort hast du Rechte auf Auskunft, Berichtigung, Löschung, Export, Einschränkung oder Widerspruch. Viele Daten sind lokal und direkt unter deiner Kontrolle.

## 10. Kinder, Änderungen und Kontakt

Anky richtet sich nicht an Kinder unter 13 Jahren. Unter 18 sollte Anky nur mit Erlaubnis einer erziehungsberechtigten Person genutzt werden.

Wir können diese Richtlinie aktualisieren und ändern dann das Revisionsdatum.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
