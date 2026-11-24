# Pflanzenwesen – 3D-Voxel-Zivilisationssimulation

**Stand: 0.6.0-prototype – Prompt 1 (Physiklabor) + 2 (Voxelwelt, Modelle, Excel-Import) + 3 (Lebenssimulation) + 4 (Persönlichkeit, Erinnerung, Lernen, Beziehungen, Göttermenü) + 5 (Ollama-Anbindung, Pläne, Gespräche, Hörensagen) + 6 (Experimente, Werkzeuge, praktisches Wissen)**

Spielbar ist eine **erste Lebenssimulation**: kleine Voxelwelt, Lebensbaum mit Wurzelbeet, genau 50 Pflanzenwesen, endliche Nahrung, Tag und Nacht. Die Wesen nehmen ihre Umgebung wahr, suchen Nahrung, gehen hin, greifen, essen, gewinnen Energie über ihre Blätter, verbrauchen Energie und Nährstoffe, reagieren auf Verletzungen und können sterben. Du kannst beobachten, einzelne Wesen untersuchen, pausieren, speichern und laden sowie im Entwicklermodus Körperveränderungen testen.

**Neu in 0.6.0 (Prompt 6):**
- **Gegenstände benutzen und Versuche:** Wesen untersuchen wahrgenommene Gegenstände, nehmen sie in die Hand, schlagen damit, verformen Kupfer und verbinden Holzstiel und Steinkopf mit Pflanzenfasern. Was dabei herauskommt, folgt nur aus Material, Geometrie, Energie und Körper; Namen haben keine Wirkung. Verbindungen können bei Überlast brechen, heiße Gegenstände verbrennen die Hand. Versuche sind begrenzt (Neugier, Hunger, Risiko, Zeitbudget). Es gibt **keinen Technologiebaum** und keine Garantie einer Entdeckung.
- **Praktisches Wissen:** jedes Wesen für sich, mit den Stufen *gehört < zugesehen < versucht < erfolgreich*, mit Herkunft, Sicherheit und Versionen. Wesen erklären Verfahren, führen sie vor, sehen zu und üben. Unterricht überträgt Information, keine Praxiserfahrung. Wissen geht beim Tod nicht auf andere über.
- **Testwerkstatt (Testbereich):** 2 Testwesen mit Testausrüstung (Steine, Stiele, Fasern, Kupferproben, Keramiktiegel, Form, extern versorgte Testheizung). 6 Versuche lassen sich gezielt auslösen, darunter Kupfer schmelzen und gießen. Ein Beobachtungslauf zeigt eigenständiges Verhalten. Im normalen Spiel gibt es keine Testausrüstung; Material (jetzt auch Fasern und Stäbe) kommt nur über das Göttermenü.
- **Ansichten:** Versuch/Gegenstand (**E**) und Wissen (**W**). Die Spielerdiagnose mit exakten Werten ist von der Wahrnehmung des Wesens getrennt. Modellvorschläge (Ollama) sind nur **ungeprüfte Hypothesen**; mit echtem Ollama ist auch das **nicht verifiziert**.
- Speicherformat 4 mit Migration aus v0.5.x (und weiter aus v0.4.0/v0.3.0).

**Aus 0.5.0 (Prompt 5):**
- **Ollama-Anbindung (optional, Vorgabe: aus):** Einzelne Wesen fragen bei ausgewählten Anlässen (wiederholtes Scheitern, auffälliges Ereignis, knappe Wahl, widersprüchliche Erfahrungen, Gesprächsgelegenheit) ein lokales Sprachmodell nach einem Vorschlag. Jede Antwort wird in 7 Stufen geprüft; ein Plan ist nur eine Option im einzigen Entscheider und jeder Schritt wird vor der Ausführung neu geprüft. Die Welt läuft vollständig ohne Ollama. **Mit einem echten Ollama-Modell ist das noch nicht verifiziert** (im Entwicklungsarbeitsbereich nicht erreichbar) – Einrichtung und Live-Test: `docs/ollama_setup.md`.
- **Gespräche:** Wesen weisen einander auf bekannte Nahrung hin, erzählen eigene Erlebnisse, äußern unsichere Vermutungen, bitten oder bieten an – auch ohne Ollama. Gehörtes bleibt **Hörensagen** mit Herkunft und Vertrauen, bis das Wesen es selbst prüft (bestätigt / veraltet / Fehler / widersprochen). Weitererzählen derselben Quelle zählt nicht als unabhängige Bestätigung. Strategische Täuschung ist nicht implementiert.
- **KI-Panel (Taste K)** und **Gesprächsansicht (Taste C)**; Wesenfenster mit Abschnitten MODELLVORSCHLAG und HÖRENSAGEN. Speicherformat 3 mit Migration aus v0.4.0 und v0.3.0.

**Aus 0.4.0:**
- **Individuen:** Jedes Wesen hat eine eigene Persönlichkeit (Neugier, Geselligkeit, Hilfsbereitschaft, Vorsicht, Beharrlichkeit), eigene Erinnerungen an selbst Beobachtetes, überprüfbare Vermutungen und gerichtete Beziehungen.
- **Soziales:** Wesen bitten um Nahrung, teilen oder lehnen ab.
- **Göttermenü:** Du kannst Nahrung schenken, Material platzieren und Verletzungen heilen, auch gezielt als Reaktion auf eine beobachtete Handlung. Jedes Wesen, das den Eingriff sieht, deutet ihn nach seinen eigenen Erfahrungen. Ein einzelnes Geschenk erzeugt keine Gewissheit, und ausbleibende Bestätigung schwächt Erwartungen wieder ab.

Noch **nicht** enthalten: freie Sprache (nur strukturierte Mitteilungen), strategische Täuschung, Technologiebaum, Feuer und Öfen, weitere Werkzeugarten außer Schlagen, Schrift/Bücher, Religion, Fortpflanzung, Tiere, Landwirtschaft, Gesellschaft.

| Bereich (Startbildschirm) | Inhalt |
|---|---|
| **Neues Spiel** | Lebenssimulation mit 50 Wesen (siehe unten) |
| **Fortsetzen / Laden** | letzten Spielstand laden (`user://saves/spielstand.json`) |
| **Physiklabor** | Fall, Wärme, Schmelzen/Erstarren von Kupfer, Bruch, Teilen/Zusammenführen, Massen- und Energieerhaltung |
| **Weltvorschau** | Bearbeitbare Voxelwelt 64×32×64 Zellen, Wasser, abbrechende Teile, Lebensbaum mit Wurzeln und Wurzelbeet, Pflanzen, Pilze |
| **Kreaturenvorschau** | Pflanzenwesen erzeugen und variieren, Unterarm entfernen, Holz-/Kupferprothese, Blätter, Animationen, Speichern/Laden, 10 Varianten, 50-Figuren-Leistungstest |
| **Geistlabor (Testbereich)** | kontrollierte Versuche A–G (Erfahrung, Hilfe, verdecktes Ereignis, Belohnung, Widerspruch, Ähnlichkeit, Speichern) – Ereignisse werden dort gezielt ausgelöst |
| **Testwerkstatt (Testbereich)** | 2 Testwesen, Testausrüstung, 6 gezielt auslösbare Versuche (Stein als Werkzeug, Verbinden, Werkzeug testen, Kupfer verformen, Schmelzen und Gießen, Vorführen/Üben), Beobachtungslauf; eigener Spielstand (`docs/experimentation.md`) |

## Voraussetzungen
- **Godot 4** Standard (GDScript, nicht .NET). Geprüft mit **4.7.2** und **4.5**.
- Zum Spielen: nichts weiter. Python wird nur für den Excel-Import gebraucht (Entwicklungswerkzeug).

## Starten
1. ZIP entpacken, z. B. nach `C:\Pflanzenwesen\`.
2. Godot → **Importieren** → `project.godot` wählen → **Importieren und bearbeiten**.
3. **F5** startet den Startbildschirm. **Neues Spiel** startet die Lebenssimulation; die drei Vorschaubereiche sind weiter erreichbar. Jeder Bereich hat oben links einen Knopf zurück zum Startbildschirm.

## Bedienung

**Überall (Kamera):** rechte Maustaste ziehen = drehen · mittlere Maustaste oder Umschalt + rechts = verschieben · Mausrad = zoomen · W A S D / Q E = bewegen.

**Lebenssimulation (Neues Spiel / Fortsetzen)**
| Eingabe | Wirkung |
|---|---|
| Linksklick auf ein Wesen oder Eintrag in der Liste links | Wesen untersuchen (Fenster rechts, farbig getrennt: WELTFAKT – Körper, Energie, Gesundheit, Persönlichkeit; ENTSCHEIDUNG – Zustand, Bewertungsbeiträge, Ziel, Handlung; BEOBACHTUNG – sichtbare Wesen, Bitten; ERINNERUNG; VERMUTUNG – Überzeugungen mit Konfidenz und Belegen, Beziehungen, wahrgenommene Eingriffe) |
| **G** / „Göttermenü“ | Nahrung schenken, Material platzieren, Verletzung heilen; optional als Reaktion auf ein ausgewähltes Ereignis; Vorschau vor der Ausführung (`docs/god_interactions.md`) |
| **K** / „KI“ | KI-Panel: ein/aus, Adresse, installierte Modelle, Modellwahl, Verbindungstest, ECHT/SIMULIERT/AUS, Warteschlange, Antwortzeiten, Fehlerquote, Protokoll (`docs/ai_integration.md`) |
| **C** / „Gespräche“ | letzte Äußerungen mit Quelle, Sicherheit, Herkunft (lokal/Ollama/SIMULIERT) und Prüfstatus beim Zuhörer (`docs/communication.md`) |
| **V** / „Vergleich“ | zwei Wesen nebeneinander (A merken, B = ausgewählt), inkl. gerichteter Beziehung A→B und B→A |
| **E** / „Versuche“ | Versuchsansicht: Protokolle des ausgewählten Wesens (Frage, Erwartung, Schritte, Aufwand, Ergebnis), dazu der angeklickte Gegenstand mit Bauteilen, Verbindungen und funktionaler Bewertung (`docs/experimentation.md`, `docs/tools_and_construction.md`) |
| **W** / „Wissen“ | Wissensansicht: Verfahren mit Stufe, Herkunft, Sicherheit, Versionen; Hypothesen; bekannte Gegenstände (`docs/practical_knowledge.md`) |
| Linksklick auf einen Gegenstand | Gegenstand auswählen (Versuchsansicht) |
| **F** | Kamera zum ausgewählten Wesen |
| **Leertaste** | Pause / Weiter (Kamera und Oberfläche bleiben bedienbar) |
| **F5** / „Speichern“ | Spielstand speichern (vorheriger bleibt als `.bak`) |
| **F9** / „Laden“ | gespeicherten Stand laden |
| „Entwicklermodus“ | rot markiertes Testfeld: Unterarm entfernen, Holz-/Kupferprothese, Bein verletzen, Blatt entfernen, Wesen töten, Verhalten anhalten, TESTOPTION Nahrung nachfüllen, **KI: Plan/Gespräch für das ausgewählte Wesen anfragen (Test)** |
| „◀ Menü“ | zurück zum Startbildschirm |

Unten: Ereignisse (Häkchen „nur ausgewähltes Wesen“), unten rechts: Leistung. Ausführlich: `docs/life_simulation.md`.

**Weltvorschau**
| Eingabe | Wirkung |
|---|---|
| **1** / Knopf „Entfernen“ | Linksklick entfernt die getroffene Zelle |
| **2** / „Hinzufügen“ | Linksklick setzt eine Zelle aus dem gewählten Material auf die getroffene Fläche |
| **3** / „Auswählen“ | Linksklick zeigt Typ, Material, Zellmasse, Bodenhöhe und Wassertiefe |
| Material-Auswahl | Erde, Gras, Stein, Holz, Pflanzenfaser, Kupfer, Wurzelbeet |
| **R** / „Zurücksetzen“ | Welt mit demselben Startwert neu erzeugen |
| Startwert + „Erzeugen“ | Welt mit anderem Startwert |
| Leertaste | Pause (Wasser, Bruchstücke) |

Gelbe Markierung = Zelle unter der Maus. Wird eine Stütze unter einem kleinen Überhang entfernt, fällt der nicht verankerte Teil als Bruchstück herunter.

**Kreaturenvorschau**
- Ansicht: **Einzeln**, **10 Varianten**, **50 Figuren (Test)**. Startwert eingeben + „Erzeugen“ oder „Zufall“.
- Regler: Größe, Rumpfproportion, Arm- und Beinlänge (beim Loslassen wird neu erzeugt); Körperfarbe (Excel F001/F002/F005); Blattform.
- Körperveränderungen: Seite wählen → „Unterarm entfernen“; Prothesenmaterial (Holz/Kupfer) → „Anbringen“; „Blatt +“/„Blatt −“; „Körper zurücksetzen“.
- Animation: Ruhe, Gehen, Greifen, Zum Mund. Fehlt die Hand auf der gewählten Seite, nimmt das Wesen die andere Hand oder lehnt verständlich ab.
- „Speichern“/„Laden“: Körperkonfiguration im Benutzerdatenordner (`user://creature_configs/kreatur.json`).
- Rechts: alle Körperteile mit Masse, Modell- und Voxelvolumen, Material, Status; Gesamtmasse.

**Physiklabor:** siehe Hinweise im Labor (Tasten 0–4 Stationen, Leertaste Pause, R Zurücksetzen, F Falschfarbe).

## Excel-Import (Entwicklungswerkzeug)
```
python -m pip install -r tools/requirements.txt
python tools/import_definitions.py            # nur prüfen, Unterschiede melden
python tools/import_definitions.py --write    # prüfen und data/generated/excel/ schreiben
```
Bericht: `reports/import_report.md`. Zuordnung und Unklarheiten: `docs/excel_mapping.md`.
Die Excel liegt unter `design/` und wird nie verändert.

## Tests
```
godot --headless --path . -s res://tests/run_tests.gd               # alle Godot-Prüfungen inkl. 10-Minuten-Dauerlauf (≈ 2 min)
godot --headless --path . -s res://tests/run_tests.gd -- --quick    # Dauerlauf nur 60 s
godot --headless --path . -s res://tools/run_life_tests.gd -- 0     # nur Lebenssimulation, ohne Dauerlauf
godot --headless --path . -s res://tools/run_mind_tests.gd          # nur Geist/Soziales/Göttermenü/Migration (Szenarien A–G über 3 Startwerte)
godot --headless --path . -s res://tools/run_ai_tests.gd            # nur KI/Gespräche/Hörensagen/Format 3 – SIMULIERTER Testdienst, kein Ollama
godot --headless --path . -s res://tools/run_tech_tests.gd -- [--quick] [--only=_t07]   # nur Technik-Abnahmetests (1)–(15) + Werkstattbeobachtung
godot --headless --path . -s res://tests/run_tests.gd -- --nur-werkstatt-szene   # nur Szenentest der Testwerkstatt
godot --headless --path . -s res://tools/ollama_live_test.gd -- --model=NAME [--minutes=3] [--unterbrechung]   # ECHTER Ollama-Live-Test (eigener Rechner)
python -m unittest discover -s tools/tests -v                         # 17 Python-Prüfungen (Importer, Erfindungskatalog, Versionsvergleich)
godot --headless --path . -s res://tools/scene_smoke.gd              # alle 6 Szenen + Testwerkstatt je 240 Bilder starten
godot --headless --path . -s res://tools/smoke_life.gd -- 120        # Lebenssimulation 120 s ohne Grafik, mit Zwischenständen
```
Ergebnisse und Messwerte: `docs/test_results.md`, Protokolle in `docs/test_reports/`.

## Dokumentation
- `docs/HANDOVER.md` – **zuerst lesen** bei Weiterentwicklung: Stand, feste Regeln, Ablauf je Prompt, Schutz vor Verlust (Git, `tools/compare_versions.py`)
- `docs/progress_audit.md` – Bestandsprüfung vor Prompt 6 (Code und Tests, nicht Doku) und Stand danach
- `docs/experimentation.md` – Versuche: Protokoll, Vorgänge, Bearbeiten, Heizen und Gießen, Begrenzung, Modellvorschläge, Testwerkstatt
- `docs/tools_and_construction.md` – Greifen, Schlagmodell, Verbindungen, Bruch, funktionale Bewertung, Modelle
- `docs/practical_knowledge.md` – Verfahrenswissen, Stufen, Unterricht, Tod, Unterricht beobachten
- `docs/ollama_setup.md` – Ollama einrichten (GTX 1660 Ti / RTX 3080), Modellwahl, Verbindungstest, Live-Test, Meldungen
- `docs/ai_integration.md` – KI-Anbindung: Bausteine, Anlässe, Einstellungen, Kontext, 7 Prüfstufen, Ausfallverhalten, Diagnose
- `docs/communication.md` – Gespräche, Hörensagen, Prüfstatus, Vertrauen
- `docs/mind_and_learning.md` – Persönlichkeit, Beobachtung, Erinnerung, Lernmodell, Beziehungen, Entscheidungen, Grenzen kausalen Schließens
- `docs/god_interactions.md` – Göttermenü: Bedienung, Prüfungen, Bilanz, Deutung durch Wesen
- `docs/inventions_catalog.md` – Ideenkatalog aus der Erfindungs-Excel (nichts aktiv)
- `docs/life_simulation.md` – Lebenssimulation: Handlungen, Körper, Stoffwechsel, Licht, Wahrnehmung, Verhalten, Navigation, Bedienung
- `docs/save_format.md` – Spielstand: Inhalt, Schreiben/Laden, Ladeverhalten, Definitionsänderungen, Migrationen
- `docs/test_results.md` – tatsächlich ausgeführte Prüfungen, Dauerlauf, Leistungsmessung
- `docs/architecture.md` – Systeme, Datenfluss, Zuständigkeiten, Ordnerstruktur
- `docs/physics_model.md` – Gleichungen, Einheiten, Modellgrenzen, Quellen (Labor, Welt, Wasser, Abstützung, Körpermassen)
- `docs/implementation_status.md` – Funktionsstand, ausgeführte Prüfungen, offene Punkte, manuelle Prüfschritte
- `docs/excel_mapping.md` – Excel-Blätter, Zuordnung, Fehler, Annahmen
- `CHANGELOG.md`
