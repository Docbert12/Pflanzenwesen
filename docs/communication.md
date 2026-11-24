# Gespräche, Hörensagen, Vertrauen (Prompt 5)

## Gesprächsmodell

Kurze, direkte Mitteilungen zwischen nahen Wesen (`scripts/social/communication_system.gd`, Handlung `talk`, `scripts/social/claim_evaluator.gd`). Gespräche funktionieren **ohne Ollama** (lokale Auswahl) und **mit Ollama** (das Modell wählt Absicht und Thema aus angebotenen Themen).

**Voraussetzungen:** Sprecher und Zuhörer leben, Abstand ≤ 4 m, der Zuhörer hat Sichtlinie zum Sprecher und reicht mit seiner Wahrnehmung hin, Sprecher nicht kritisch hungrig, Anlass (Thema aus eigenem Wissen), Wartezeiten: 25 s je Sprecher, 90 s je Paar.

**Absichten**
| Absicht | Umsetzung |
|---|---|
| Nahrung erbitten (`ask_food`) | vorhandene Handlung `request_food` (Prompt 4) – kein zweites System |
| Hilfe anbieten (`offer_help`) | vorhandene Handlung `offer_food`, wenn eine eigene Portion getragen wird |
| Auf Nahrung hinweisen (`point_food`) | Handlung `talk` (1,5 s), Inhalt: Quelle, Ort, Art, Menge, Beobachtungszeit |
| Eigene Erfahrung mitteilen (`share_experience`) | `talk`, Inhalt: eigene Erinnerung (z. B. „Bei mir erschien plötzlich Nahrung“) |
| Unsichere Vermutung (`share_guess`) | `talk`, Inhalt: eigene Vermutung (z. B. nach „Arme heben“ kam etwas) mit Häufigkeit und Konfidenz |

**Jede Äußerung** hat: Sprecher-ID, Zuhörer-ID, Absicht (Inhaltstyp), strukturierte Aussage, referenzierte Entitäten, Quelle (eigene Beobachtung / eigenes Erlebnis / Vermutung / Hörensagen mit Ursprung und Erzählkette), geäußerte Sicherheit, Text **aus Vorlage** und optional einen bereinigten Modelltext (nur grau angezeigt, ohne Wirkung).

**Was gesagt werden kann:** nur Themen aus `CommunicationSystem.topics()` – also eigenes Nahrungsgedächtnis (≤ 90 s alt), eigene Erinnerungen, eigene Vermutungen oder Weitererzählen von Gehörtem (bleibt Hörensagen, Ursprung bleibt erhalten). Ein Modell kann nur eine angebotene Themen-ID wählen; die geäußerte Sicherheit wird auf die eigene begrenzt. **Strategische Täuschung ist nicht implementiert** – Wesen können nichts behaupten, was sie nicht selbst glauben.

**Lokale Auswahl (ohne Modell):** Option „talk“ in der Entscheidung, vor allem wenn ein nahes Wesen kürzlich um Nahrung bat oder abgewiesen wurde (dann Hinweis auf bekannte Nahrung); Erlebnisse/Vermutungen gelegentlich. Umstehende sehen nur, **dass** gesprochen wurde (Ereignis `talk`), nicht den Inhalt.

## Hörensagen (`cr.ai.hearsay`, höchstens 24 Einträge)

Gespeichert: Sprecher, Zeitpunkt, Gegenstand, ursprüngliche Quelle (Wesen + Zeit), Erzählkette, geäußerte Sicherheit, **Vertrauen in den Sprecher beim Hören**, unabhängige Quellen, Zahl der Weitererzählungen, Status, widersprechende Beobachtungen, Notiz.

- Gehörtes geht **nicht** ins Nahrungsgedächtnis und **nicht** als Beleg in Vermutungen.
- **Weitererzählen derselben Quelle** (gleicher Ursprungsschlüssel: Ursprungswesen + Gegenstand + Beobachtungszeit) erhöht nur „weitererzählt“, **nicht** „unabhängig“. Eine andere Ursprungsbeobachtung zählt als unabhängige Quelle.
- Hungrige Wesen ohne bessere Möglichkeit können einen Hinweis **selbst prüfen** (Option `check_hint`: Bedarf × Sicherheit, Vertrauen, Weg) – die Prüfung erfolgt ausschließlich durch eigene Wahrnehmung.

## Prüfstatus

| Status | Wann | Vertrauen in den Sprecher |
|---|---|---|
| ungeprüft / wird geprüft | gehört, noch nicht selbst gesehen | – |
| **bestätigt** | Quelle selbst gesehen, mit Nahrung | steigt vorsichtig (Gewicht 0,3) |
| **veraltet** | Quelle selbst gesehen, jetzt leer, Hinweis war älter als 10 s – vermutlich inzwischen gegessen, **keine Lüge** | unverändert |
| **Fehler** | gesehene Quelle passt nicht zur Angabe (Art/Ort) – Irrtum | sinkt vorsichtig (0,4) |
| **widersprochen** | eigene Beobachtung zur selben Zeit (±10 s) sagt „leer“ | sinkt vorsichtig (0,4) |
| selbst beobachtet | Zuhörer kannte es schon selbst | – |
| nicht prüfbar | Erlebnisse/Vermutungen anderer; oder Ort erreicht, Quelle nicht zu sehen | – |

Vertrauen ist der vorhandene Beta-Mittelwert der Beziehung (Prompt 4); die Gewichte stehen in `mind.json → hearsay`.

## Beobachten

- **Gesprächsansicht (Taste C):** letzte Äußerungen mit Absicht, Herkunft (lokal / Ollama / SIMULIERT), Quelle, Ursprung, Kette, Sicherheit und dem **aktuellen Status beim Zuhörer**; Häkchen „nur ausgewähltes Wesen“.
- **Wesenfenster:** Abschnitt HÖRENSAGEN (letzte 4 Einträge mit Status und Notiz) und letzte Gespräche.

## Speichern

Hörensagen, Gesprächsprotokoll (≤ 200), Wartezeiten und leer gesehene Quellen werden gespeichert (Format 3, `docs/save_format.md`). Laufende `talk`-Handlungen werden beim Laden abgebrochen (`on_load: cancel`).
