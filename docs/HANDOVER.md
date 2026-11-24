# HANDOVER – zuerst lesen (für jede KI-Sitzung, jeden neuen Chat)

Dieses Dokument ist das **Gedächtnis des Projekts**. Es hängt nicht am Chatverlauf. Wer an Pflanzenwesen weiterarbeitet, liest es **vor** jeder Änderung und aktualisiert es **am Ende** jedes Prompts.

## 1. Projekt in einem Satz
Godot-4-Spiel „Pflanzenwesen“: 3D-Voxelwelt mit 50 individuellen Pflanzenwesen (Körper aus Teilen und Materialien, Stoffwechsel, Wahrnehmung, Gedächtnis, Lernen, Beziehungen, Gespräche), Lebensbaum, Göttermenü, optionale lokale KI über Ollama. Aufgebaut in **13 Prompts**, die der Nutzer nacheinander liefert. Datenbasis: Excel `design/Pflanzenwesen_Voxel_Datenbasis.xlsx` (wird nie verändert, nur importiert).

## 1a. Repository
- GitHub: **https://github.com/Docbert12/Pflanzenwesen** (seit 2026-11-24), Hauptzweig `main` = immer der neueste ausgelieferte Stand.
- **Umzug:** Bis v0.6.0 lag das Projekt in `Robert-JosepSubiranaSlotos/pflanzenwesen`. Der Stand v0.6.0 wurde unverändert übernommen (neues Repository: Zweig `version/v0.6.0`, Commit 2e60241). Der ältere Verlauf v0.1.0–v0.6.0 und die Versionszweige liegen weiter im alten Repository; die Commit-Nummern in der Tabelle unten bis v0.6.0 beziehen sich auf das alte Repository. Beide Repositorys heißen `pflanzenwesen` und lassen sich deshalb nicht in derselben Claude-Sitzung anbinden.
- **Versionsmarken sind Zweige `version/vX.Y.Z`** (die Claude-Arbeitsumgebung darf keine Git-Tags hochladen). Ein Versionszweig wird nach der Lieferung nicht mehr verändert.
- Das ZIP für den Nutzer enthält **kein** `.git` (Befehl in Abschnitt 5; die Arbeitsumgebung klont flach, ein mitgeliefertes `.git` hätte nur einen unvollständigen Verlauf). Der vollständige Verlauf liegt auf GitHub. Tags `vX.Y.Z` entstehen nur lokal in der Arbeitsumgebung und können nicht hochgeladen werden; maßgeblich sind die Versionszweige.

| Version | Commit |
|---|---|
| v0.1.0 | 2034603 |
| v0.2.0 | 91aee27 |
| v0.3.0 | c7d0b98 |
| v0.4.0 | 26dc574 |
| v0.5.0 | 098a957 |
| v0.5.1 | 2668786 (+ Doku-Nachtrag Repository) |
| v0.6.0 | 50bc72c (+ Nachtrag Commit-Hash) – altes Repository |
| v0.6.0 (Übernahme) | 2e60241 – neues Repository `Docbert12/Pflanzenwesen`, inhaltlich identisch |

**Arbeitszweige:** `wip/prompt-06b` = laufende Arbeit an Prompt 6B (Pause am 2026-11-24; **kompiliert noch nicht vollständig**, nicht ausgeliefert). Fortsetzung: `docs/plan_prompt_06b.md` lesen (Stand, Entscheidungen, Reihenfolge der offenen Schritte).

**Neuer Chat:** Der Nutzer schreibt „Pflanzenwesen, Repository Docbert12/Pflanzenwesen, hier ist Prompt N“ bzw. „… weiter mit Prompt 6B (Zweig wip/prompt-06b)“. Dann: Repository anbinden, klonen, diese Datei lesen. Für den Versionsvergleich die letzte Version holen: `git fetch --depth=1 origin version/vX.Y.Z` und `python3 tools/compare_versions.py git:FETCH_HEAD .` (oder `git:origin/version/vX.Y.Z`).

## 2. Stand
| Prompt | Inhalt | Version | Status |
|---|---|---|---|
| 1 | Physiklabor | v0.1.0 | fertig |
| 2 | Voxelwelt, Modelle, Excel-Import | v0.2.0 | fertig |
| 3 | Lebenssimulation (Hunger, Nahrung, Handlungen, Speichern) | v0.3.0 | fertig |
| 4 | Persönlichkeit, Erinnerung, Lernen, Beziehungen, Göttermenü | v0.4.0 | fertig |
| 5 | Ollama-Anbindung, Pläne, Gespräche, Hörensagen | v0.5.0 | fertig – **echte Ollama-Verbindung noch nicht verifiziert** |
| – | HANDOVER, Versionsvergleich, Git-Verlauf | v0.5.1 | fertig |
| 6 | Experimente, Werkzeugherstellung, praktisches Wissen, Testwerkstatt | v0.6.0 | fertig – Modellvorschläge für Versuche **mit echtem Ollama nicht verifiziert** |
| 6B | Excel-Abgleich, Arbeitsanimationen, eigenständige Herstellung + verbindlicher Zusatz Werkzeug- und Materialkette (Hammer bauen → schlagen → Bruchstücke sammeln → lagern / verbauen / schmelzen) | (v0.6.1 geplant) | **in Arbeit** – Zweig `wip/prompt-06b`, Plan und Zwischenstand: `docs/plan_prompt_06b.md`; Texte: `design/prompts/prompt_06b_*.txt` |
| Zusatz | Weltarchitektur: 20-fache Fläche, 0,25-m-Blöcke, Abbau und Bau mit Massenbilanz – `design/prompts/prompt_zusatz_weltarchitektur_abbau_bauen.txt` | – | offen, **Einordnung entscheidet der Nutzer** (Vorschlag: direkt nach 6B) |
| 7 | Lebensbaum, Fortpflanzung, Vererbung, Mutationen, weitere Bäume – `prompt_07_…` | – | offen (Text liegt vor) |
| 8 | Ökosystem, Wildtiere, Zähmung, Zucht, Landwirtschaft – `prompt_08_…` | – | offen (Text liegt vor) |
| 9 | Siedlungen, gemeinsames Bauen, Vorräte, Arbeitsteilung, Besitz, Handel – `prompt_09_…` | – | offen (Text liegt vor) |
| 10 | Gemeinschaften, Religion, Regeln, Führung, Konflikte, Gefangenschaft – `prompt_10_…` | – | offen (Text liegt vor) |
| 11 | Schrift, Bücher, Wissen – `prompt_11_schrift_buecher_wissen.txt` | – | **nach 6–10** (Entscheidung des Nutzers) |
| 12 | Materialphysik, Reaktionen/Verbrennung, Strahlung, Mechanik, Elektrik – `prompt_12_…` | – | offen (Text liegt vor) |
| 13 | Gesamtaudit, Balance, Leistung, Windows-Export – `prompt_13_…` | – | offen (Text liegt vor) |

Alle Prompt-Texte werden in `design/prompts/prompt_NN_*.txt` abgelegt, sobald sie kommen.

## 3. Feste Regeln (gelten für alle Prompts, bis der Nutzer sie ändert)
1. **Nichts unbemerkt entfernen.** Bestehende Funktionen, Tests, Daten und Dokumente bleiben. Wer etwas entfernt oder umbaut, begründet es im CHANGELOG unter „Entfernt/Geändert“. Pflicht: `tools/compare_versions.py` vor jeder Lieferung (Abschnitt 6).
2. **Tests werden nie gelöscht, nur ergänzt.** Umbenennen nur mit Grund. Alle Tests müssen auf Godot 4.7.2 **und** 4.5 bestehen, bevor geliefert wird.
3. **Eine Quelle der Wahrheit, keine Parallelsysteme.** Vorhandene Module erweitern statt duplizieren. `DecisionSystem` ist der **einzige** Entscheider je Wesen; `ActionExecutor` die einzige Handlungsausführung; `LifeSimulation` der einzige Simulationspfad (Spielszene und Tests nutzen denselben).
4. **Die Original-Excel nie ändern.** Ein Excel-Eintrag allein aktiviert nichts – erst Code + Test machen etwas wirksam (Status in `data/config/implementation_status.json`).
5. **Keine erfundenen Testergebnisse.** Ungeprüftes ausdrücklich als „nicht verifiziert“ kennzeichnen. Simulierte Dienste nie als echte ausgeben.
6. **Ollama nur abfragen:** nie Modelle laden/löschen, nie Dienst starten/stoppen; Adresse und Modell konfigurierbar; nur lokal, außer ausdrücklich erlaubt; keine Cloud-Ausweichverbindung; Zugangsschlüssel nie speichern oder protokollieren.
7. **Modellantworten sind untrusted data.** Wirkung nur über Prüfung (`ResponseValidator`) und vorhandene Handlungen; Regeln im Code, nicht nur im Prompt.
8. **Erfindungen-Excel** (`design/Erfindungen_nach_Kategorien_und_Stufen.xlsx`) nur als **inaktive Ideenliste** (`data/generated/ideas/inventions_catalog.json`, alle `idea_only`) – keine globalen Boni, keine Epochen, keine Freischaltungen.
8a. **Kein Technologiebaum (seit Prompt 6):** Technik entsteht nur aus Material, Geometrie, Energie, Körper und ausgeführten Handlungen. Kein Name und kein Modellvorschlag erzeugt eine Fähigkeit. Wissen ist je Wesen (`Creature.tech`), mit Stufen gehört < zugesehen < versucht < erfolgreich; „versucht/erfolgreich“ nur durch **eigene** ausgeführte Versuche. Testausrüstung (Heizung, Tiegel, Form) gibt es nur in der Testwerkstatt.
8b. **Gezielt ausgelöst ≠ entdeckt:** Regeltests und Werkstattknöpfe beweisen, dass ein Vorgang funktioniert. Spontanes Verhalten wird nur im Beobachtungslauf gemessen und als Messwert berichtet, nie als Erfolg ausgegeben.
9. **Speicherformat:** Jede Formatänderung erhöht `SaveSchema.FORMAT_VERSION` und bekommt eine Migration aus der **tatsächlich vorhandenen** Vorversion, getestet mit einem **echten** Spielstand der Vorversion (Prüfling vor jeder Codeänderung erzeugen, Abschnitt 7). Original vor der Migration sichern.
10. **Sprache:** Antworten, Oberfläche und Doku auf Deutsch.

## 4. Hardware und Umgebung des Nutzers
- Entwicklung/Spielen auf PC mit **GTX 1660 Ti** (6 GB) → Modelle 3–4 Mrd. Parameter; zweiter PC mit **RTX 3080** (10 GB) → 7–9 Mrd.
- Ollama ist auf dem Nutzer-PC installiert. Die Cloud-Arbeitsumgebung der KI hat **kein** Ollama und **keine** GPU: Modelltests laufen beim Nutzer (`tools/ollama_live_test.gd`, Bericht `user://ollama_live_report.txt`) oder, falls die Claude-Desktop-App den Ordner freigibt, über diese.
- Godot-Versionen für Tests: 4.7.2 und 4.5 (Arbeitsumgebung: `/home/claude/tools/godot/`).

## 5. Ablauf eines Prompts (Checkliste)
**Beginn**
1. Repository klonen/aktualisieren; `docs/HANDOVER.md` (dieses Dokument) lesen, danach die im Prompt genannten Dokumente.
2. Prompt-Text nach `design/prompts/prompt_NN_*.txt` legen.
3. Bestandsprüfung wie vom Prompt verlangt; bei Formatänderung **zuerst** Prüfling der Vorversion erzeugen.
4. Vor dem Bauen: `godot --headless --path . --import`, dann vollständige Tests laufen lassen (Ausgangsbasis bestätigen).

**Ende**
1. Vollständige Tests auf 4.7.2 und 4.5, Szenenstart (`tools/scene_smoke.gd`), Python-Tests (`python3 -m unittest discover -s tools/tests`).
2. `python3 tools/compare_versions.py git:vX.Y.Z . --md reports/versionsvergleich_vX.Y.Z_zu_neu.md` – jede Entfernung begründen oder rückgängig machen.
3. Definitionsfingerabdruck neu eintragen, falls `data/config/*.json` o. ä. geändert (`tools/print_definitions_fingerprint.gd`, Konstante in `save_migrations.gd`).
4. Doku: README, CHANGELOG (mit „Entfernt/Geändert“), `docs/architecture.md`, `docs/implementation_status.md`, `docs/test_results.md`, betroffene Fachdokumente, **dieses HANDOVER** (Stand-Tabelle, neue Regeln, offene Punkte).
5. Version in `project.godot` erhöhen; Commit mit Nachricht „vX.Y.Z – Prompt N“; lokal Tag `vX.Y.Z`; Push nach `main` **und** als Versionszweig: `git push origin HEAD:main` und `git push origin HEAD:refs/heads/version/vX.Y.Z`; Commit-Tabelle in Abschnitt 1a ergänzen.
6. ZIP für den Nutzer: `zip -qr ../Pflanzenwesen_vX.Y.Z_promptNN.zip . -x ".git/*" ".godot/*" "*/__pycache__/*" "*.tmp"`, in frischem Ordner entpacken, importieren, Schnelltests – dann senden.
7. Schlussnachricht auf Deutsch: was spielbar ist, wie man es prüft, welche Tests bestanden, was nicht verifiziert ist.

## 6. Schutz vor Verlust
- **Git:** jeder Prompt = Commit + Versionszweig `version/vX.Y.Z` (lokal zusätzlich Tag). Ältere Stände auf GitHub: Zweig-Auswahl oben links → `version/v0.4.0`; lokal `git checkout v0.4.0` oder `git diff v0.4.0 v0.5.0 -- pfad`.
- **Versionsvergleich:** `tools/compare_versions.py ALT NEU` (Ordner, ZIP oder `git:TAG`) listet entfernte Dateien, Klassen, Funktionen, Testprüfungen und Konfigurationsschlüssel; Rückgabe 1, sobald etwas entfernt wurde.
- **Tests** sind das Funktionsregister: jede wichtige Funktion hat mindestens eine Prüfung.
- **ZIPs** beim Nutzer nie überschreiben (Versionsnummer im Namen).

## 7. Wichtige Werkzeuge und Befehle
```
godot --headless --path . --import                                 # nach neuen class_name-Skripten nötig
godot --headless --path . -s res://tests/run_tests.gd              # alles (ca. 6 min, inkl. 10-min-Dauerlauf)
godot --headless --path . -s res://tests/run_tests.gd -- --quick   # schneller (60-s-Dauerlauf)
godot --headless --path . -s res://tools/run_life_tests.gd -- 60   # nur Lebenssimulation
godot --headless --path . -s res://tools/run_mind_tests.gd         # nur Geist/Soziales/Migration
godot --headless --path . -s res://tools/run_ai_tests.gd           # nur KI/Gespräche (SIMULIERT)
godot --headless --path . -s res://tools/run_tech_tests.gd -- --quick [--only=_t07]   # nur Technik (Prompt 6)
godot --headless --path . -s res://tests/run_tests.gd -- --nur-werkstatt-szene          # nur Szenentest Werkstatt
godot --headless --path . -s res://tools/check_scripts.gd          # alle Skripte kompilieren (schnell, vor Testläufen)
godot --headless --path . -s res://tools/observe_workshop.gd -- 1800   # Werkstatt 30 min eigenständig beobachten (Messwerte)
godot --headless --path . -s res://tools/scene_smoke.gd            # alle 6 Szenen + Testwerkstatt starten
godot --headless --path . -s res://tools/smoke_life.gd -- 600      # 10 min Simulation, Messwerte
godot --headless --path . -s res://tools/make_save_fixture.gd -- user://saves/fixture.json 90 [--mit-material]   # echter Spielstand als Prüfling
godot --headless --path . -s res://tools/print_definitions_fingerprint.gd
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . -s res://tools/capture_living.gd   # Bildschirmfotos
python3 tools/compare_versions.py git:v0.5.1 .                     # oder git:origin/version/v0.5.1
python3 tools/ollama_attrappe.py --port 11999                      # HTTP-ATTRAPPE (kein Ollama), nur für Transporttests
```
Benutzerdaten von Godot (Linux): `~/.local/share/godot/app_userdata/Pflanzenwesen/` (Testbericht `test_report.txt`, `saves/`, Bilder). Windows: `%APPDATA%\Godot\app_userdata\Pflanzenwesen\`.

## 8. Architektur-Kurzüberblick (Details: `docs/architecture.md`)
- `scripts/world/life_simulation.gd` – Simulationspfad; `life_context.gd` – Dienste (`executor`, `social`, `interventions`, `comm`, `ai`, `nav`, `ledger` …).
- `scripts/agents/creature.gd` – Wesen (Körper, Geist, `ai`-Daten); `perception.gd`; `locomotion.gd`.
- `scripts/mind/` – Persönlichkeit, Gedächtnis, Überzeugungen (Beta), Beziehungen, Lernen, `goal_manager.gd` (`suggest`), `decision_system.gd`.
- `scripts/actions/` – `action_definition.gd` (Typen, Ladeverhalten), `action_executor.gd`, Implementierungen.
- `scripts/social/` – Bitten/Geben (Prompt 4), Gespräche, Hörensagen (Prompt 5).
- `scripts/ai/` – Ollama-Anbindung (Prompt 5); `scripts/god/` – Göttermenü.
- `scripts/technology/` – Gegenstände, Verbünde, Werkzeuggebrauch, Bewertung, Versuche, Verfahrenswissen (Prompt 6); `scripts/social/teaching_system.gd`; `scripts/lab/test_workshop.gd`; `scripts/generation/object_generator.gd`; Parameter `data/config/technology.json`, Materialabschnitt `working`.
- `scripts/persistence/` – Format 4, Migrationen 1→2→3→4 (nur die letzte Stufe vergleicht mit den aktuellen Definitionen).
- Konfiguration: `data/config/*.json` (Spieldefinitionen, Fingerabdruck), `data/settings/*.json` (Anwendungseinstellungen; `simulation.json` gehört zum Fingerabdruck, `ai.json` nicht).

## 9. Bekannte Stolperfallen (GDScript/Godot)
- Kein `:=` bei Werten aus Dictionaries/Arrays (Variant) → explizit typisieren, sonst Parse-Fehler (Warnungen gelten als Fehler).
- `PackedByteArray`/`PackedStringArray` sind Werttypen: nach dem Ändern zurückschreiben.
- Namen wie `_set`, `set_path` kollidieren mit Engine-Methoden.
- Godot 4.5 liest manche 17-stellige Gleitkommazahlen um 1 ulp anders → Vergleiche mit relativer Toleranz 1e-12.
- RefCounted-Zyklen (LifeContext ↔ Systeme) → `LifeSimulation.dispose()` aufrufen.
- Nach neuen `class_name`-Dateien `--import` ausführen.
- `HTTPClient`: im Antwortzustand vor `poll()` lesen (schließende Server).
- Ein freigegebenes Objekt vergleicht als `null` (auch `!=` mit einem neuen Objekt) → in Tests `get_instance_id()` vor dem Freigeben merken.
- `String %` kennt kein `%e` → `str(x)` verwenden.
- `JSON.stringify`-Vergleich hängt von der Schlüsselreihenfolge ab → inhaltlich vergleichen (`TestTechnology.first_diff`).
- Testläufe auf 4.7.2 und 4.5 **nacheinander**, nie parallel: beide nutzen denselben `user://`-Ordner (Spielstände, Bericht).
- Neue Materialien/Konfigurationsdateien ändern den Definitionsfingerabdruck → `V*_SHIPPED_DEFINITIONS` neu setzen, und die vorige Migrationsstufe darf dann nicht mehr gegen die aktuellen Definitionen prüfen.

## 10. Offene Punkte (Stand v0.6.0, ergänzt 2026-11-24)
- **Prompt 6B in Arbeit** (Zweig `wip/prompt-06b`): Fortsetzung nach `docs/plan_prompt_06b.md` Abschnitt 5. Ausgangsbasis v0.6.0 am 2026-11-24 bestätigt: 432/432 auf 4.7.2 und 4.5; Prüflinge Format 4 liegen in `tests/fixtures/save_v4_prompt06*.json` (vor jeder Codeänderung erzeugt).
- **Leitlinie Steinzeit → Zukunft (Wunsch des Nutzers):** Die Wesen sollen sich selbst entwickeln (Steinhammer → Schmelzen → Legieren → Abbauwerkzeuge). Abgleich aller Prompts in `docs/plan_prompt_06b.md` Abschnitt 8: **Feuer erst in Prompt 12; Holzkohle/Luftzufuhr, Ton brennen/eigener Ofen, Erz im Gelände, Zinn/Legierungen fehlen in allen Prompts.** Vorschlag an den Nutzer: Zwischenschritte „Feuer, Ton und eigener Ofen“ sowie „Erz und Legierungen“. Leitlinien-Excel (physikalische Ketten statt Bonus-Effekte) nach 6B bauen.
- Neue Erfindungs-Excel des Nutzers liegt unverändert in `design/Erfindungen_Echt_nach_Kategorien.xlsx` (noch nicht importiert; Befund in `docs/plan_prompt_06b.md` Abschnitt 3). Die alte Datei `Erfindungen_nach_Kategorien_und_Stufen.xlsx` bleibt erhalten.
- **Echte Ollama-Tests** (Plan, Gespräch, 50 Wesen, Ausfall, Wiederkehr, **Versuchsvorschläge**) beim Nutzer ausstehend → danach Rate/Zeitlimit/Modellempfehlung anpassen und hier eintragen.
- Prompt 6, Grenzen: nur Schlagwerkzeuge, nur Umwickeln, Gießen nur Tiegel → offene Form, keine Schmelzströmung, eine Temperatur je Teil, Zusammentragen nur vor dem Verbinden, Fasern nur Werkstatt/Göttermenü. Versuchsgewicht 0,6 ist kalibriert an 2 Werkstattwesen; im 50-Wesen-Spiel mit Göttermaterial beobachten.
- Strategische Täuschung bewusst nicht implementiert.
- Manuelle Prüfschritte für den Nutzer: `docs/implementation_status.md`.
