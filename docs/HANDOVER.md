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
| v0.6.1 | 3a968e9 (+ Nachtrag Commit-Hash) – Prompt 6B |

**Arbeitszweige:** `wip/prompt-06b` = Arbeitsverlauf von Prompt 6B (Zwischenstände vom 24./25.11.2026); abgeschlossen und als v0.6.1 ausgeliefert. Der Zweig bleibt als Verlauf erhalten, weitergearbeitet wird auf `main`. Entscheidungen und Begründungen von 6B: `docs/plan_prompt_06b.md`.

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
| 6B | Excel-Abgleich, Arbeitsanimationen, eigenständige Herstellung + verbindlicher Zusatz Werkzeug- und Materialkette (Hammer bauen → schlagen → Bruchstücke sammeln → lagern / verbauen / schmelzen) | v0.6.1 | fertig – Gegenstandsherstellung und **ein** einfaches Einzelbauwerk (Steinreihe); **Siedlungsbau nicht** (Prompt 9); Graben/Verdichten nur vorbereitet; Ollama-Anfrageart `work` **mit echtem Ollama nicht verifiziert**; Animationen nur als Standbilder geprüft. Texte: `design/prompts/prompt_06b_*.txt`, Doku: `docs/work_chains.md`, `docs/animations.md` |
| Leitlinie | Leitlinien-Excel „Steinzeit → Zukunft“ (Designdokument, kein Spielinhalt): `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx`, Quellen `design/leitlinie/`, Doku `docs/leitlinie.md` | – (Stand 0.6.1) | fertig (25.11.2026) – Entscheidungen zu Zwischenschritten **beim Nutzer** |
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
2. `python3 tools/compare_versions.py git:origin/version/vX.Y.Z . --md reports/versionsvergleiche/versionsvergleich_vX.Y.Z_zu_vNEU.md` – jede Entfernung begründen (CHANGELOG und `reports/versionsvergleiche/README.md`) oder rückgängig machen.
3. Definitionsfingerabdruck neu eintragen, falls `data/config/*.json` o. ä. geändert (`tools/print_definitions_fingerprint.gd`, Konstante in `save_migrations.gd`).
4. Doku: README, CHANGELOG (mit „Entfernt/Geändert“), `docs/architecture.md`, `docs/implementation_status.md`, `docs/test_results.md`, betroffene Fachdokumente, **dieses HANDOVER** (Stand-Tabelle, neue Regeln, offene Punkte).
4a. Leitlinie nachziehen: Verfahren und Materialien, die der Prompt tatsächlich spielbar macht, in `tools/leitlinie/vokabular.py` auf Spielstand `A` setzen (Texte in `STATUS_BESCHREIBUNG` anpassen), dann `python3 tools/build_leitlinie.py` und die Python-Tests (`docs/leitlinie.md`).
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
godot --headless --path . -s res://tests/run_tests.gd              # alles (ca. 10 min auf 2 Kernen, inkl. 10-min-Dauerlauf und Beobachtungsläufen)
godot --headless --path . -s res://tests/run_tests.gd -- --quick   # schneller (60-s-Dauerlauf)
godot --headless --path . -s res://tools/run_life_tests.gd -- 60   # nur Lebenssimulation
godot --headless --path . -s res://tools/run_mind_tests.gd         # nur Geist/Soziales/Migration
godot --headless --path . -s res://tools/run_ai_tests.gd           # nur KI/Gespräche (SIMULIERT)
godot --headless --path . -s res://tools/run_tech_tests.gd -- --quick [--only=_t07]   # nur Technik (Prompt 6)
godot --headless --path . -s res://tests/run_tests.gd -- --nur-werkstatt-szene          # nur Szenentest Werkstatt
godot --headless --path . -s res://tools/run_work_tests.gd -- [--quick] [--only=_t03]   # nur Werkzeug-/Materialkette (Prompt 6B)
godot --headless --path . -s res://tests/run_tests.gd -- --nur-werkzeugkette-szene      # nur Szenentest Testszene Werkzeugkette
godot --headless --path . -s res://tools/probe_work_chain.gd -- --goal=lagern|bauen|schmelzen [--case=material|weg|arm|schwer|unterbrechen|ungeeignet|ohne_ofen] [--auto] [--verbose] [--secs=N]   # eine Kette mit Protokoll
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . -s res://tools/capture_work_chain.gd   # Bildschirmfotos Testszene Werkzeugkette
python3 tools/import_definitions.py --write                        # Excel-Datenbasis neu importieren (liest design/import_config/datenbasis_korrekturen.json)
python3 tools/import_inventions_real.py                            # Erfindungskatalog aus Erfindungen_Echt_nach_Kategorien.xlsx
python3 tools/build_leitlinie.py [--pruefen]                       # Leitlinien-Excel aus design/leitlinie/*.txt prüfen und erzeugen
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
- Prompt 6B: `scripts/technology/work_system.gd` + `work_chain.gd` (Arbeitsketten lagern/bauen/schmelzen; Optionen `work:start/continue/model` im `DecisionSystem`; ohne Verhalten treibt `WorkSystem.tick`), `scripts/settlement/` (Lager, Baustelle „Steinreihe“ – Namen wie in Prompt 9, dort erweitern statt ersetzen), `scripts/actions/work_motion.gd` (Phasen Anlauf→Ausgangspose→Arbeit/Kontakt→Rückkehr, `a.state.anim`), `scripts/animation/work_pose.gd` (Geometrie: Schulter, Handgelenk, Griffwinkel 45°, Kontaktposen-Suche) + `creature_animator.gd` (liest nur), `scripts/lab/work_chain_scene.gd` (Testszene). Details: `docs/work_chains.md`, `docs/animations.md`.
- `scripts/persistence/` – Format 5, Migrationen 1→2→3→4→5 (nur die letzte Stufe vergleicht mit den aktuellen Definitionen, `V5_SHIPPED_DEFINITIONS`).
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
- Neue Materialien/Konfigurationsdateien ändern den Definitionsfingerabdruck → `V*_SHIPPED_DEFINITIONS` neu setzen, und die vorige Migrationsstufe darf dann nicht mehr gegen die aktuellen Definitionen prüfen. Das gilt auch für einen Neuimport der Excel (`data/generated/excel/*.json`).
- Werkstatt-/Szenenangaben in `life.workshop` werden als Ganzzahlen gespeichert → Kennzeichen wie `work_scene` als `1`, nicht als Text/Wahrheitswert.
- Bewegungsziel: Ankunftsradius nie größer als der Restweg (`WorkSystem._move_near`), sonst endlose Anlaufschleife.
- Bildschirmfotos von Bewegungen: Simulation während der Aufnahme anhalten (`capture_work_chain.gd`), sonst liegt das Bild Bilder hinter dem Zustand.
- Arbeitsposen: Winkel und Standpunkt kommen aus derselben `WorkPose`-Geometrie wie die Handlung – wer Körperproportionen, Griffwinkel oder Werkzeuglänge ändert, prüft `TestWorkChain._t01/_t09` (Kontaktabstand) und den Szenentest Werkzeugkette.

## 10. Offene Punkte (Stand v0.6.1, 2026-11-25)
- **Nächster Schritt:** Prompt 7 (Lebensbaum, Fortpflanzung, Vererbung) – **oder** zuerst der Zusatz Weltarchitektur (Vorschlag: direkt nach 6B, weil 6B Graben/Verdichten nur vorbereitet; würde v0.6.2). **Entscheidung beim Nutzer.** Vor Prompt 7: Prüflinge Format 5 aus v0.6.1 erzeugen (`tools/make_save_fixture.gd`, `tools/make_workshop_fixture.gd`; zusätzlich ein Spielstand der Testszene Werkzeugkette mitten in einer Kette).
- **Leitlinie Steinzeit → Zukunft (Wunsch des Nutzers):** Die Wesen sollen sich selbst entwickeln (Steinhammer → Schmelzen → Legieren → Abbauwerkzeuge). **Leitlinien-Excel gebaut (25.11.2026):** `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx`, 24 Zeitalter, 2.680 Erfindungen (je 54–192) mit physikalischer Kette, Vorläufern, Spielstand und Lücke; Quellen `design/leitlinie/*.txt`, Werkzeug `tools/build_leitlinie.py`, Doku `docs/leitlinie.md`. Ergebnis: heute 95 möglich, bis Prompt 12 473 (17,6 %), Lücke 2.207. Größte Zwischenschritte: Licht/Messen/Zeit/Zeichen, Erz und Legierungen, Elektronik, Feuer/Ton/Ofen, Chemie, Werkzeugformen (gezieltes Abschlagen fehlt schon ab der Frühen Steinzeit). Mit den beiden Vorschlägen „Feuer, Ton und eigener Ofen“ + „Erz und Legierungen“ wären 788 (29,4 %) möglich. **Entscheidung beim Nutzer** (Zwischenschritte, Jahreszeiten im Weltmodell, ob die Leitlinie je ins Spiel einfließt). Die Excel ist nur Designdokument, nichts davon ist im Spiel aktiv.
- Erfindungs-Excel `design/Erfindungen_Echt_nach_Kategorien.xlsx` ist seit v0.6.1 als **Katalog** importiert (`data/generated/ideas/inventions_real_catalog.json`, 2.785 Einträge, Stufe nur Metadatum, Effekte nie angewendet). Aktiv sind nur die 8 Verfahren in `data/config/inventions_activated.json`. Die alte Datei `Erfindungen_nach_Kategorien_und_Stufen.xlsx` und ihr Katalog bleiben erhalten.
- Prompt 6B, Grenzen: Wesen schmelzen nur im **Testofen** der Testszene (eigener Ofen braucht Feuer/Ton); eigenständig beobachtet wurde bisher nur „bauen“ (nach einer gezielt ausgelösten Kette, siehe `docs/test_results.md`); eine Kette je Wesen; Lager/Baustelle nur durch Wesen oder Testaufbau; kein gemeinsames Bauen; Animationen headless und als Standbilder geprüft, **nicht** als bewegte Bilder auf einer Grafikkarte.
- **Echte Ollama-Tests** (Plan, Gespräch, 50 Wesen, Ausfall, Wiederkehr, **Versuchsvorschläge**, **Arbeitsvorschläge `work`**) beim Nutzer ausstehend → danach Rate/Zeitlimit/Modellempfehlung anpassen und hier eintragen.
- Prompt 6, Grenzen: nur Schlagwerkzeuge, nur Umwickeln, Gießen nur Tiegel → offene Form, keine Schmelzströmung, eine Temperatur je Teil, Zusammentragen nur vor dem Verbinden, Fasern nur Werkstatt/Göttermenü. Versuchsgewicht 0,6 ist kalibriert an 2 Werkstattwesen; im 50-Wesen-Spiel mit Göttermaterial beobachten.
- Strategische Täuschung bewusst nicht implementiert.
- Manuelle Prüfschritte für den Nutzer: `docs/implementation_status.md`.
