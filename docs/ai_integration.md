# KI-Anbindung (Ollama) – Aufbau, Kontext, Prüfung, Ausfallverhalten

> Ollama **ergänzt** das Verhalten. Physik, Wahrnehmung, Erinnerungen, Lernen und Handlungsausführung bleiben die zuständigen Spielsysteme. Die Welt läuft vollständig ohne Ollama (Vorgabe: KI-Anbindung **aus**).
> **Verifikationsstand:** Struktur, Prüfung, Warteschlange, Fehlerfälle und Speichern sind mit dem **simulierten Testdienst** (MockOllama) und einer lokalen **HTTP-Attrappe** getestet. Mit einem **echten** Ollama-Modell ist bisher **nichts** geprüft (im Arbeitsbereich nicht erreichbar) → `tools/ollama_live_test.gd` auf dem eigenen Rechner.

## Bausteine

| Datei | Aufgabe |
|---|---|
| `scripts/ai/ai_settings.gd` | Anwendungseinstellungen (`data/settings/ai.json` + `user://ai_settings.json`), Typprüfung, nur lokale Adressen ohne `allow_remote`, Schlüssel nur aus Umgebungsvariable |
| `scripts/ai/http_transport.gd` | nicht blockierender HTTP-Transport (Godot `HTTPClient`, manuell gepollt, Größenlimit 256 KB) |
| `scripts/ai/mock_ollama.gd` | **SIMULIERTER** Testdienst mit derselben Schnittstelle – überall als SIMULIERT gekennzeichnet |
| `scripts/ai/ollama_client.gd` | nur **Abfragen**: `GET /api/version`, `GET /api/tags`, `GET /api/ps`, `POST /api/chat` (fest eingetragen; kein pull/delete/create) |
| `scripts/ai/ai_service.gd` | anwendungsweit: Zustand, Gesundheitsprüfung, Unterbrecher, Ratenbegrenzung, Statistik, begrenztes Protokoll; verteilt Antworten an die passende Welt-Sitzung |
| `scripts/ai/request_queue.gd` | Warteschlange (Priorität, Länge, Fairness, Duplikate, Ablauf, Wiederholung) |
| `scripts/ai/ai_system.gd` | Weltseite (ctx.ai): Anlässe, Versand, Anwenden, Sitzungsnummer, Tod/Laden/Pause |
| `scripts/ai/context_builder.gd` | Kontext nur aus Daten des fragenden Wesens |
| `scripts/ai/response_validator.gd` | 7-stufige Prüfung |
| `scripts/ai/plan_manager.gd` | Annahme, Schrittausführung über das Handlungssystem, Ergebnisprotokoll |
| `data/ai/decision_schema.json`, `conversation_schema.json` | JSON-Schemata (an Ollama im Feld `format` und im Systemtext) |
| `data/ai/prompts/*.txt` | Systemanweisungen (Plan/Deutung, Gespräch) |
| `scripts/ui/ai_status_panel.gd` | KI-Panel (Taste K) |

**Eine Entscheidungsinstanz:** Ollama liefert ausschließlich Vorschläge an `DecisionSystem`. Ein angenommener Plan erscheint dort als Option **`follow_plan`** mit begrenztem Nutzwert (`plans.follow_weight` 0,35 × (1 − 0,5 × Unsicherheit), bei Nahrungszielen + 0,5 × Nahrungsbedarf) und konkurriert mit allen lokalen Optionen. Vorschläge ohne Schritte gehen über die vorhandene Schnittstelle `GoalManager.suggest()` (Zuschlag ≤ 0,2). Kritischer Hunger (≥ 80 %) verdrängt jeden Plan, der nicht der Nahrung dient.

## Wann gefragt wird (`mind.json → ai_triggers`)

Nach jeder lokalen Entscheidung prüft `AISystem.consider()` – billig, ohne Netz – in dieser Reihenfolge:
1. **Wiederholtes Scheitern** (3 fehlgeschlagene Handlungen in Folge oder erfolglose Suche) → Plan, Priorität 3
2. **Auffälliges Ereignis** (neue Erinnerung mit Bedeutung ≥ 0,5 in den letzten 8 s) → Plan, Priorität 3
3. **Widersprüchliche Erfahrungen** (Vermutung mit Bestätigung und ≥ 2 Gegenbelegen) → Deutung, Priorität 2
4. **Knappe Wahl** (beste zwei Optionen ≤ 0,05 auseinander, Nutzwert ≥ 0,25) → Plan, Priorität 2
5. **Gesprächsgelegenheit** (Partner in Reichweite mit Thema; Zufall 5 % je Entscheidung) → Gespräch, Priorität 1

Nie: Bewegung, Nahrungssuche, Hunger, Ausweichen, Gesundheitsänderungen; nie bei kritischem Hunger; nie mit aktivem Plan oder offener Anfrage. Nur „KI-fähige“ Wesen fragen (fest je Wesen aus dem Körper-Startwert, Anteil `eligible_share` 50 %). Entwicklermodus: „KI: Plan anfragen (Test)“ / „KI: Gespräch anfragen (Test)“ fragt für das ausgewählte Wesen sofort (alle übrigen Regeln gelten).

## Einstellungen (`data/settings/ai.json`, eigene Werte in `user://ai_settings.json`)

| Schlüssel | Vorgabe | Bedeutung |
|---|---|---|
| `enabled` | false | Anbindung ein/aus |
| `base_url` | http://127.0.0.1:11434 | nur Rechner:Port; nicht lokal nur mit `allow_remote` |
| `model` | "" | aus `/api/tags` im Panel wählen |
| `timeout_s` | 90 | Zeitlimit einer Chat-Anfrage (Echtzeit) |
| `max_response_chars` | 3000 | längere Antworten werden verworfen |
| `max_context_chars` | 7000 | Kontext wird bis darunter gekürzt |
| `num_predict`, `temperature`, `num_ctx`, `keep_alive`, `think` | 320, 0,4, 4096, 15m, false | an Ollama übergeben |
| `max_queue` | 16 | Warteschlangenlänge |
| `max_concurrent` | 1 | gleichzeitig laufende Anfragen (konservativ) |
| `per_creature_min_interval_s` | 90 | Mindestabstand je Wesen (Simulationszeit) |
| `global_rate_per_min` | 8 | höchstens so viele Sendungen in jedem 60-s-Fenster |
| `request_ttl_s` / `max_state_age_s` | 60 / 45 | Ablauf vor dem Senden / zulässiges Alter des abgefragten Zustands beim Anwenden |
| `max_retries`, `retry_backoff_s` | 1, 6 | Wiederholung nur bei Transportfehlern/leerer Antwort |
| `breaker_failures`, `health_check_interval_s` | 3, 15 | Unterbrecher und Prüfabstand |
| `eligible_share` | 0,5 | Anteil KI-fähiger Wesen |
| `diagnostic_mode` | false | volle Kontexte/Rohantworten ins (begrenzte) Protokoll |
| `use_mock` | false | SIMULIERTER Testdienst (Entwicklung) |

Die gemessenen Grenzen auf deiner Hardware liefert der Live-Test; danach `max_concurrent`/`global_rate_per_min` anpassen.

## Individueller Kontext (`ContextBuilder`)

Enthält nur: Identität · Fähigkeiten (gehen, greifen, essen, Gesten, Sehweite) · Bedürfnisse (Hunger, Energie, verletzte Teile, trägt Nahrung) · Persönlichkeit · eigene Wahrnehmung (sichtbare Nahrung/Wesen: nur ID, Abstand, lebt, trägt sichtbar etwas) · bis zu 6 eigene Erinnerungen (Relevanz) · Vermutungen mit Häufigkeit und Konfidenz · bis zu 4 Beziehungen (eigene Einschätzung) · Gehörtes **strukturiert** und als Hörensagen markiert · aktuelles Ziel, letztes Ergebnis · erlaubte Handlungen/Zieltypen · **Kandidaten**: bekannte Nahrung (≤ 6), sichtbare Wesen (≤ 5), Erinnerungs-IDs, bei Gesprächen nummerierte Themen aus dem eigenen Wissen.

Nie enthalten: Weltzustand, Persönlichkeit/Hunger/Gedächtnis anderer, Spielerabsichten, nicht Beobachtetes, Technologiekatalog, freie Modelltexte anderer Wesen (verhindert, dass eingeschleuste Anweisungen weitergereicht werden). Der Kontext wird als JSON in der Benutzernachricht gesendet; Systemanweisung + Schema stehen in der Systemnachricht; zusätzlich `format` = Schema, `stream: false`.

## Prüfung (`ResponseValidator`)

1. **Größe/Format** – Länge, gültiges JSON-Objekt
2. **Schema/Typen** – Pflichtfelder, keine unbekannten Felder (auch nicht im Schritt), Aufzählungen, ≤ 5 Schritte
3. **IDs** – jedes Ziel muss eine angebotene Kandidaten-ID passender Art sein; Erinnerungs-IDs nur angebotene
4. **Wesen/Sitzung** – Anfrage-ID, Wesen, Welt-Sitzung, Wesen lebt
5. **Erlaubte Handlungen** – nur `go_to, pick_up, eat, give_food, request_food, offer_food, wait, explore, raise_arms, talk` und nur die für dieses Wesen erlaubten
6. **Wissen/Fähigkeiten** – Nahrung muss im eigenen Nahrungsgedächtnis sein; Körperfähigkeiten jetzt; mögliche Abfolge (nicht zweimal aufnehmen, nicht essen/geben ohne zu tragen)
7. **Aktuelle Voraussetzungen** – Zustandsalter ≤ 45 s, Zielwesen lebt, Plan nicht kürzlich gescheitert

Danach Abgleich mit Bedürfnis/Ziel (`PlanManager.accept`). **Jeder Schritt wird bei der Ausführung erneut geprüft**; ist das Ziel weg, scheitert der Plan – kein Ersatzobjekt. Gescheiterte Pläne (Signatur) sind 600 s gesperrt. `short_explanation` und Gesprächstext werden bereinigt (keine Steuerzeichen/Formatierungsklammern) und nur angezeigt.

Schutz der Spielregeln liegt im Code: Der Client kennt nur vier Abfragepfade; es gibt keine Handlung „erschaffen“, „bauen“ o. ä.; Modelltext wird nirgends ausgewertet; Systemanweisungen kommen aus Dateien, nie aus Antworten; Netzwerkziel nur aus den Einstellungen. Ein erwähnter Generator oder ein Fahrzeug erzeugt nichts.

## Asynchronität, Pause, Tod, Laden

- Senden und Empfangen laufen im Takt über `poll()`, ohne zu warten. Das Wesen handelt währenddessen lokal weiter.
- **Pause:** keine neuen Sendungen; eintreffende Antworten bleiben im Eingang und werden nach dem Fortsetzen gegen den dann aktuellen Zustand geprüft (Anzeige „traf während der Pause ein, danach geprüft“).
- **Tod:** offene Anfrage abgebrochen, Plan abgebrochen.
- **Laden/Neues Spiel:** neue Sitzungsnummer; offene Anfragen der alten Welt abgebrochen; späte Antworten mit alter Sitzungsnummer verworfen und gezählt.

## Fehlerverhalten

| Fall | Reaktion |
|---|---|
| nicht erreichbar / Zeitüberschreitung / Verbindung verloren | eine Wiederholung nach Wartezeit; nach 3 Fehlern in Folge Unterbrecher („nicht erreichbar“), Prüfung alle 15 s, danach automatische Wiederaufnahme (Zähler „Wiederherstellungen“) |
| Modell fehlt (404) | Zustand „Modell nicht installiert“ mit Liste; keine Sendungen; kein Download |
| leere Antwort, ungültiges JSON | einmal wiederholt bzw. abgelehnt (Stufe 1) |
| Schemafehler, unbekannte IDs, verbotene/unmögliche Handlung, veralteter Zustand | abgelehnt mit Stufe und Grund, keine Wiederholung |
| Warteschlange voll | Anfrage nicht angenommen (oder niedriger priorisierte verdrängt) |

In keinem Fall wird eine Ersatzentscheidung „im Namen des Modells“ erzeugt; das Wesen handelt lokal.

## Diagnose

- **Wesenfenster:** Quelle der Entscheidung (lokal / lokal + Modellvorschlag / modellplan), Abschnitt MODELLVORSCHLAG: Anbindung, KI-fähig, wartende/laufende Anfrage mit Anlass und Zustandsalter, letzte Anfrage mit Ergebnis, Prüfgrund, Antwortzeit, Modellbegründung, aktiver Plan mit Schritten (○ ▶ ✓ ✗) und Ergebnissen, frühere Pläne, Modelldeutungen.
- **KI-Panel (K):** ECHT/SIMULIERT/AUS, Zustand, Modellliste, Verbindungstest, Warteschlange, laufend, Antwortzeiten (Ø/letzte/max), Fehlerquote, Ablehnungen je Stufe, verworfene veraltete Antworten, Wiederherstellungen, geladene Modelle (`/api/ps`), begrenztes Protokoll.
- **Ereignisse:** `ai_plan_done`, `ai_plan_failed`, `utterance`.
