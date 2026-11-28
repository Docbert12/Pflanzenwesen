# HANDOVER – zuerst lesen (für jede KI-Sitzung, jeden neuen Chat)

Dieses Dokument ist das **Gedächtnis des Projekts**. Es hängt nicht am Chatverlauf. Wer an Pflanzenwesen weiterarbeitet, liest es **vor** jeder Änderung und aktualisiert es **am Ende** jedes Prompts bzw. jeder Alpha-Version.

**Stand 28.11.2026: Alpha 1.1 ist geliefert. Nächste Version: Alpha 1.2 – Große Welt I** (Abschnitt 10 nennt die ersten Schritte und die übernommenen offenen Punkte).

**Ab 25.11.2026 gilt die Roadmap `docs/ROADMAP_ALPHA.md`:** Versionen heißen **Alpha 1.1, 1.2, …**; dort stehen die Entscheidungen des Nutzers (D1–D6), die Reihenfolge Alpha 1.1–1.21, der Zuschnitt jeder Version, die Zielarchitektur (Modularisierung, große Welten, Weltkarte) und das Versionsschema. Nach diesem Dokument **immer** die Roadmap lesen.

## 1. Projekt in einem Satz
Godot-4-Spiel „Pflanzenwesen“: 3D-Voxelwelt mit 50 individuellen Pflanzenwesen (Körper aus Teilen und Materialien, Stoffwechsel, Wahrnehmung, Gedächtnis, Lernen, Beziehungen, Gespräche), Lebensbaum, Göttermenü, optionale lokale KI über Ollama. Aufgebaut in **13 Prompts**, die der Nutzer nacheinander liefert. Datenbasis: Excel `design/Pflanzenwesen_Voxel_Datenbasis.xlsx` (wird nie verändert, nur importiert).

## 1a. Repository
- GitHub: **https://github.com/Docbert12/Pflanzenwesen** (seit 2026-11-24), Hauptzweig `main` = immer der neueste ausgelieferte Stand.
- **Umzug:** Bis v0.6.0 lag das Projekt in `Robert-JosepSubiranaSlotos/pflanzenwesen`. Der Stand v0.6.0 wurde unverändert übernommen (neues Repository: Zweig `version/v0.6.0`, Commit 2e60241). Der ältere Verlauf v0.1.0–v0.6.0 und die Versionszweige liegen weiter im alten Repository; die Commit-Nummern in der Tabelle unten bis v0.6.0 beziehen sich auf das alte Repository. Beide Repositorys heißen `pflanzenwesen` und lassen sich deshalb nicht in derselben Claude-Sitzung anbinden.
- **Versionsmarken sind Zweige `version/vX.Y.Z`**, ab Alpha **`version/alpha-1.N`** (die Claude-Arbeitsumgebung darf keine Git-Tags hochladen). Ein Versionszweig wird nach der Lieferung nicht mehr verändert. Versionsschema Alpha: `docs/ROADMAP_ALPHA.md` Abschnitt 4.
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
| alpha-1.1 | Zweig `version/alpha-1.1` (Commit-Nummer: `git log -1 origin/version/alpha-1.1`) – Fundament, 28.11.2026 |

**Arbeitszweige:** `wip/alpha-1.1` = Arbeitsverlauf von Alpha 1.1 (erster Commit: die Prüflinge Format 5 aus unverändertem v0.6.1-Code); abgeschlossen auf `main`. `wip/prompt-06b` = Arbeitsverlauf von Prompt 6B (Zwischenstände vom 24./25.11.2026); abgeschlossen und als v0.6.1 ausgeliefert. Der Zweig bleibt als Verlauf erhalten, weitergearbeitet wird auf `main`. Entscheidungen und Begründungen von 6B: `docs/plan_prompt_06b.md`.

**Neuer Chat** (seit 28.11.2026 etwa alle 3 Versionen, Gruppen in `docs/ROADMAP_ALPHA.md` Abschnitt 4): Der Nutzer schreibt „Pflanzenwesen, Repository Docbert12/Pflanzenwesen, weiter mit Alpha 1.N“ (früher: „hier ist Prompt N“). Dann: Repository anbinden, klonen, diese Datei und `docs/ROADMAP_ALPHA.md` lesen, den Abschnitt der Version und die dort genannten Prompt-Abschnitte lesen, `docs/plan_alpha_1_N.md` anlegen. Für den Versionsvergleich die letzte Version holen: `git fetch --depth=1 origin version/vX.Y.Z` und `python3 tools/compare_versions.py git:FETCH_HEAD .` (oder `git:origin/version/vX.Y.Z`).

## 2. Stand
Testzahlen: **564 Prüfungen** (Godot 4.7.2 und 4.5), 8 Szenenstarts, 39 Python-Tests – Stand Alpha 1.1 (`docs/test_results.md`).

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
| Leitlinie | Leitlinien-Excel „Steinzeit → Zukunft“ (Designdokument, kein Spielinhalt): `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx`, Quellen `design/leitlinie/`, Doku `docs/leitlinie.md`; mit **Alpha-Plan** (ab welcher Alpha-Version jede Erfindung physikalisch möglich sein soll) | – (Stand 0.6.1) | fertig (25.11.2026) |
| Roadmap | **Plan Alpha 1.1 – 1.21** nach den Entscheidungen des Nutzers vom 25.11.2026 – `docs/ROADMAP_ALPHA.md` | – (Stand 0.6.1) | fertig (25.11.2026) |
| **Alpha 1.1** | **Fundament:** 16 Simulationsmodule (`SimModule`, `ModuleRegistry`), `WorldAccess`, Kartenvorlagen `data/maps`, Neues-Spiel-Dialog, Speicherformat 6 (Abschnitte je Modul, Chunk-Deltas, Migration 5 → 6), Zufallsströme je Modul, Vermessung, Windows-Exportprofil. Keine neuen Spielinhalte, Verhalten bitgleich zu v0.6.1. Plan und Aufgabenliste: `docs/plan_alpha_1_1.md` | alpha-1.1 | **fertig (28.11.2026)**, 564/564 auf 4.7.2 und 4.5. Nicht verifiziert: Bildzeiten auf Grafikkarte, Windows-Build unter Windows, Dialog von Hand. **Nächste Version: Alpha 1.2** |
| Zusatz | Weltarchitektur: 20-fache Fläche, 0,25-m-Blöcke, Abbau und Bau mit Massenbilanz – `design/prompts/prompt_zusatz_weltarchitektur_abbau_bauen.txt` | → Alpha 1.1 (Vorbereitung, **erledigt**), **1.2** (große Welt), **1.4** (Abbau, Bau, Geologie) | 1.1-Anteil fertig; 1.2 und 1.4 geplant |
| 7 | Lebensbaum, Fortpflanzung, Vererbung, Mutationen, weitere Bäume – `prompt_07_…` | → Alpha **1.6** (Nachwuchs) und **1.7** (Vererbung) | geplant |
| 8 | Ökosystem, Wildtiere, Zähmung, Zucht, Landwirtschaft – `prompt_08_…` | → Alpha **1.5** (Pflanzen), **1.9** (Tiere), **1.11** (Zähmung, Landwirtschaft) | geplant |
| 9 | Siedlungen, gemeinsames Bauen, Vorräte, Arbeitsteilung, Besitz, Handel – `prompt_09_…` | → Alpha **1.12** | geplant |
| 10 | Gemeinschaften, Religion, Regeln, Führung, Konflikte, Gefangenschaft – `prompt_10_…` | → Alpha **1.14** | geplant |
| 11 | Schrift, Bücher, Wissen – `prompt_11_schrift_buecher_wissen.txt` | → Alpha **1.16** (nach 9 und 10, Entscheidung des Nutzers) | geplant |
| 12 | Materialphysik, Reaktionen/Verbrennung, Strahlung, Mechanik, Elektrik – `prompt_12_…` | → **vorgezogen**: Verbrennung Alpha 1.10, Hebel 1.12, Reduktion/Legieren 1.15; Rest 1.18 (Mechanik II) und 1.20 (Strahlung, Elektrik) | geplant |
| 13 | Gesamtaudit, Balance, Leistung, Windows-Export – `prompt_13_…` | → Alpha **1.21** (Windows-Build wird ab 1.1 versucht) | geplant |
| Neu | Zwischenschritte aus der Leitlinie: Zeit/Himmel/Klima **1.3**, Steinwerkzeuge/Fasern/Werfen **1.8**, Feuer **1.10**, Ton/Keramik/eigener Ofen **1.13**, Erz/Bronze **1.15**, Weltkarte mit Regionen **1.17**, Eisen **1.19** | Alpha 1.x | geplant (Entscheidung D1: Claude ordnet organisch) |

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
3. Bestandsprüfung wie vom Prompt verlangt; bei Formatänderung **zuerst** Prüfling der Vorversion erzeugen. Ab Alpha: `docs/plan_alpha_1_N.md` mit **Aufgabenliste mit Nachweis** (jeder Muss-Punkt und jeder Prompt-Abschnitt; offene Punkte der Vorversion übernehmen) – Roadmap Abschnitt 4. Nach einer automatischen Kürzung des Chats: HANDOVER, Roadmap und diese Liste neu lesen.
4. Vor dem Bauen: `godot --headless --path . --import`, dann vollständige Tests laufen lassen (Ausgangsbasis bestätigen).

**Ende**
1. Vollständige Tests auf 4.7.2 und 4.5, Szenenstart (`tools/scene_smoke.gd`), Python-Tests (`python3 -m unittest discover -s tools/tests`).
2. `python3 tools/compare_versions.py git:origin/version/vX.Y.Z . --md reports/versionsvergleiche/versionsvergleich_vX.Y.Z_zu_vNEU.md` – jede Entfernung begründen (CHANGELOG und `reports/versionsvergleiche/README.md`) oder rückgängig machen.
3. Definitionsfingerabdruck neu eintragen, falls `data/config/*.json`, `data/materials`, `data/maps` o. ä. geändert: `tools/print_definitions_fingerprint.gd` ausführen und den Wert unter der neuen Version in **`SaveSchema.SHIPPED_DEFINITIONS`** (`scripts/persistence/save_schema.gd`) eintragen – die Einträge der Vorversionen bleiben stehen, damit deren Spielstände ladbar sind. Der Test „Ausgelieferte Definitionen dieser Version sind eingetragen“ schlägt fehl, solange der Eintrag fehlt. (Bis v0.6.1: Konstanten in `save_migrations.gd`.)
4. Doku: README, CHANGELOG (mit „Entfernt/Geändert“), `docs/architecture.md`, `docs/implementation_status.md`, `docs/test_results.md`, betroffene Fachdokumente, **dieses HANDOVER** (Stand-Tabelle, neue Regeln, offene Punkte).
4a. Leitlinie nachziehen: Verfahren und Materialien, die der Prompt bzw. die Alpha-Version tatsächlich spielbar macht, in `tools/leitlinie/vokabular.py` auf Spielstand `A` setzen (Texte in `STATUS_BESCHREIBUNG` anpassen), Abweichungen vom Alpha-Plan (`ALPHA_PLAN_*`) im Änderungsprotokoll der Roadmap festhalten, dann `python3 tools/build_leitlinie.py` und die Python-Tests (`docs/leitlinie.md`, Roadmap Abschnitt 10).
5. Version in `project.godot` erhöhen (ab Alpha: `alpha-1.N`); Commit mit Nachricht „Alpha 1.N – Titel“ (früher „vX.Y.Z – Prompt N“); lokal Tag `alpha-1.N`; Push nach `main` **und** als Versionszweig: `git push origin HEAD:main` und `git push origin HEAD:refs/heads/version/alpha-1.N`; Commit-Tabelle in Abschnitt 1a und Statustabelle in `docs/ROADMAP_ALPHA.md` Abschnitt 11 ergänzen.
6. ZIP für den Nutzer: `zip -qr ../Pflanzenwesen_alpha-1.N.zip . -x ".git/*" ".godot/*" "*/__pycache__/*" "*.tmp"` (früher `Pflanzenwesen_vX.Y.Z_promptNN.zip`), in frischem Ordner entpacken, importieren, Schnelltests – dann senden.
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
godot --headless --path . -s res://tools/run_module_tests.gd -- [--only=_t09]          # nur Alpha 1.1 (Module, Karten, Format 6, Migration 5→6), ca. 2 min
godot --headless --path . -s res://tools/state_hash.gd -- 120 [spiel|werkstatt|kette]  # Zustandsprüfsummen: VOR und NACH einem Umbau vergleichen
godot --headless --path . -s res://tools/benchmark_world.gd -- [--map=ID] [--secs=120] # Vermessung → user://benchmark_report.txt
godot --headless --path . -s res://tools/make_work_chain_fixture.gd -- user://saves/fx.json bauen 40   # Prüfling: Testszene Werkzeugkette mitten in einer Kette
godot --headless --path . --export-release "Windows Desktop" ../Pflanzenwesen_windows/Pflanzenwesen.exe   # Windows-Build (Exportvorlagen nötig, siehe Abschnitt 9)
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
- **Alpha 1.1 – Module:** `scripts/core/sim_module.gd` (Vertrag: `tick`, `actor_tick`, `save_section`, `load_section`, `migrate_section`, `after_load`, `metrics`, `audit`), `module_registry.gd` (Reihenfolge aus `depends_on`, Zeitmessung, Abschnitte), `rng_streams.gd`; 16 Module in `scripts/modules/`, angemeldet in `LifeSimulation._register_modules`. Die Module hüllen die Systeme oben nur ein. Tabelle Modul → System → Abschnitt: `docs/architecture.md` („Ergänzungen aus Alpha 1.1“).
- **Alpha 1.1 – Welt-Schicht:** `scripts/world/world_access.gd` (`ctx.terrain`, einziger Geländezugriff außerhalb `scripts/world`; ein Test durchsucht die Skripte), `map_template.gd` + `data/maps/*.json` (Kartenvorlagen; „lichtung“ = Welt von v0.6.x), `region_store.gd` (Region im Spielstand mit Chunk-Deltas).
- **Alpha 1.1 – Spielstand:** Format 6 = `meta` + `modules` (je Modul `"v"`) + `regions`; `SaveManager.document()` schreibt, `SaveManager.snapshot()`/`flat()` liefert die flache Sicht mit den alten Schlüsseln; Migrationen 1→…→6 (`docs/save_format.md`).
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

- **Module (Alpha 1.1):** Wer die Reihenfolge der Module oder den Inhalt der Schleife je Wesen ändert, ändert das Verhalten. Vorher und nachher `tools/state_hash.gd` laufen lassen; ungewollte Abweichungen fallen dort sofort auf. Neue Module nur über `depends_on` einhängen und Zufall nur über `ctx.rng_streams.stream(id)` ziehen (nie `sim.rng`), dann bleiben die Prüfsummen der alten Systeme gleich.
- **Neues Modul mit Zustand:** `has_section = true` und – weil ältere Spielstände den Abschnitt nicht haben – `section_optional = true`. Ohne das wird jeder ältere Spielstand als unvollständig abgewiesen.
- **Untypisierte Schleifenvariablen** (`for m in _by(...)`, `for m in order`) liefern Variant: `var r := m.load_section(…)` ist dann ein Parse-Fehler. Vorher typisieren (`var m: SimModule = mm`).
- **Tests und flache Sicht:** `SaveManager.snapshot()` hat die alten Schlüssel; die **Datei** hat sie nicht mehr (`modules.<id>.…`, `regions.main.…`, `meta.definitions`). Tests, die die Datei von Hand verändern, müssen den neuen Aufbau benutzen.
- **Ladeverhalten ist nicht Migration:** Beim Laden werden laufende Handlungen ggf. abgebrochen und laufende Versuche als „unterbrochen“ beendet (seit v0.6.0). Vergleiche „Datei vor dem Laden ↔ Zustand danach“ müssen `last_result`, `next_decision_t`, `mind.tech.experiment_id` und laufende Versuche ausnehmen.
- **JSON-Schlüsselreihenfolge:** Die Datei wird mit sortierten Schlüsseln geschrieben; Listen von Abschnitten vor dem Vergleich sortieren.
- **Windows-Export in der Arbeitsumgebung:** Exportvorlagen von `github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz` (1,3 GB) laden und `windows_release_x86_64.exe`, `windows_debug_x86_64.exe` (+ `_console`) und `version.txt` nach `~/.local/share/godot/export_templates/4.7.2.stable/` legen. Das Paket lässt sich mit der Linux-Engine prüfen: `godot --headless --main-pack Pflanzenwesen.pck -s /pfad/pruefskript.gd`. Godot selbst: `…/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` und `…/4.5-stable/…` (die Arbeitsumgebung ist in jedem Chat neu und leer).
- **Vollständiger Testlauf dauert jetzt etwa 10 Minuten je Godot-Version** (564 Prüfungen); `--quick` etwa 8 Minuten. Befehle mit langem Zeitlimit oder im Hintergrund starten und währenddessen keine Skripte ändern.

## 10. Offene Punkte (Stand Alpha 1.1, 2026-11-28)
- **Nächster Schritt: Alpha 1.2 – Große Welt I** (Chunk-Streaming, große Karte mit etwa 20-facher Fläche, Biome, Kartenvorlagen zur Wahl, hierarchische Navigation, Erkundungswissen, Simulationszonen A/B/C, Messszene) nach `docs/ROADMAP_ALPHA.md` Abschnitt 6. Der Nutzer schreibt „weiter mit Alpha 1.2“ (derselbe Chat wie 1.1, Gruppe 1.1–1.3 nach D7; nach einer Pause oder Kürzung zuerst dieses Dokument, die Roadmap und `docs/plan_alpha_1_1.md` neu lesen).
  **Erste Schritte in 1.2:**
  1. `docs/plan_alpha_1_2.md` mit Aufgabenliste anlegen (Muss 1–12 aus der Roadmap, Weltarchitektur §3–5, §12–13, §15–17) und die offenen Punkte unten übernehmen.
  2. `docs/world_expansion.md` Abschnitt 4 lesen: die drei gemessenen Engpässe sind **Wasser über alle Spalten** (2,5 ms je Schritt bei 4.096 Spalten), **Wegsuche** (Ø 8,5 ms quer über die Karte, Knotenlimit 2.500) und **Netz + Kollision** (9,6 ms je Chunk).
  3. Ausgangswerte sichern, bevor Code geändert wird: `tools/state_hash.gd` (Karte „lichtung“ muss nach 1.2 dieselben Prüfsummen liefern, solange die Vorlage `lichtung_v0` benutzt wird) und `tools/benchmark_world.gd`.
  4. Prüflinge Format 6 aus Alpha 1.1 erzeugen (`make_save_fixture.gd`, `make_workshop_fixture.gd`, `make_work_chain_fixture.gd`), **bevor** sich Abschnitte oder die Region ändern.
  5. Neuer Generator als eigene Generator-ID (z. B. `landschaft_v1`) neben `lichtung_v0` – alte Welten behalten ihren Generator (Weltarchitektur §15).
- **Aus Alpha 1.1 übernommen (Aufgabenliste 1.2):**
  - **Bildzeiten auf Grafikkarten nicht gemessen** – Messszene in 1.2, Messung beim Nutzer (GTX 1660 Ti, RTX 3080).
  - **Wasser ist noch kein Modul** (läuft in `VoxelWorld._physics_process`, also nur in der Spielszene, nicht in den Tests) – in 1.2 in den Simulationspfad holen, mit aktiven Spalten.
  - **Spielstand als Ordner** je Region und Chunk (Roadmap 8.8) – heute eine Datei mit demselben logischen Aufbau.
  - **Windows-Build** `Pflanzenwesen_alpha-1.1_windows.zip` wurde dem Nutzer geschickt, **unter Windows nicht gestartet** – Rückmeldung abwarten und hier eintragen.
  - **Neues-Spiel-Dialog von Hand** nicht geprüft.
- **Entscheidungen des Nutzers:** D1–D6 vom 25.11.2026, **D7** vom 28.11.2026 (neuer Chat etwa alle 3 Versionen) – Wortlaut in der Roadmap Abschnitt 1. **28.11.2026, 19:10:** Nach Alpha 1.1 Pause; Alpha 1.2 am Folgetag im selben Chat.

### Weiter offen aus v0.6.1 (unverändert)
- **Entscheidungen des Nutzers vom 25.11.2026 (D1–D6), Kurzfassung:** Ökosystem und Entwicklung aus den Prompts umsetzen, lebendige Welt, Claude ordnet organisch, Excel nur zum Sortieren, eigene Erfindungen der Wesen erwünscht (D1); Jahreszeiten/Mond/Sterne ja (D2); Spiel modularisieren für größere Karten und Weltkarten (D3); Leitlinie im Spiel als Ideenquelle ohne Freischaltung (D4); Versionen Alpha 1.1 … (D5); ausführliche Plandatei auf GitHub (D6) – Wortlaut und Auslegung in `docs/ROADMAP_ALPHA.md` Abschnitt 1.
- **Leitlinie Steinzeit → Zukunft (Wunsch des Nutzers):** Die Wesen sollen sich selbst entwickeln (Steinhammer → Schmelzen → Legieren → Abbauwerkzeuge). **Leitlinien-Excel gebaut (25.11.2026):** `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx`, 24 Zeitalter, 2.680 Erfindungen (je 54–192) mit physikalischer Kette, Vorläufern, Spielstand und Lücke; Quellen `design/leitlinie/*.txt`, Werkzeug `tools/build_leitlinie.py`, Doku `docs/leitlinie.md`. Ergebnis: heute 95 möglich, bis Prompt 12 473 (17,6 %), Lücke 2.207. Die Zwischenschritte sind seit 25.11.2026 **in den Alpha-Plan eingeordnet** (Roadmap Abschnitt 5 und 10; Excel-Blätter „Alpha-Plan“ und „Alpha-Zeitalter“, Spalte „geplant möglich ab“): nach Alpha 1.16 wären 989 (36,9 %), nach 1.21 1.248 (46,6 %) physikalisch möglich – Möglichkeiten, keine Ziele. Die Excel ist nur Designdokument, nichts davon ist im Spiel aktiv; ab Alpha 1.8 dient sie im Spiel als Erfindungs-Chronik und Ideenkatalog ohne Freischaltung (D4).
- Erfindungs-Excel `design/Erfindungen_Echt_nach_Kategorien.xlsx` ist seit v0.6.1 als **Katalog** importiert (`data/generated/ideas/inventions_real_catalog.json`, 2.785 Einträge, Stufe nur Metadatum, Effekte nie angewendet). Aktiv sind nur die 8 Verfahren in `data/config/inventions_activated.json`. Die alte Datei `Erfindungen_nach_Kategorien_und_Stufen.xlsx` und ihr Katalog bleiben erhalten.
- Prompt 6B, Grenzen: Wesen schmelzen nur im **Testofen** der Testszene (eigener Ofen braucht Feuer/Ton); eigenständig beobachtet wurde bisher nur „bauen“ (nach einer gezielt ausgelösten Kette, siehe `docs/test_results.md`); eine Kette je Wesen; Lager/Baustelle nur durch Wesen oder Testaufbau; kein gemeinsames Bauen; Animationen headless und als Standbilder geprüft, **nicht** als bewegte Bilder auf einer Grafikkarte.
- **Echte Ollama-Tests** (Plan, Gespräch, 50 Wesen, Ausfall, Wiederkehr, **Versuchsvorschläge**, **Arbeitsvorschläge `work`**) beim Nutzer ausstehend → danach Rate/Zeitlimit/Modellempfehlung anpassen und hier eintragen.
- Prompt 6, Grenzen: nur Schlagwerkzeuge, nur Umwickeln, Gießen nur Tiegel → offene Form, keine Schmelzströmung, eine Temperatur je Teil, Zusammentragen nur vor dem Verbinden, Fasern nur Werkstatt/Göttermenü. Versuchsgewicht 0,6 ist kalibriert an 2 Werkstattwesen; im 50-Wesen-Spiel mit Göttermaterial beobachten.
- Strategische Täuschung bewusst nicht implementiert.
- Manuelle Prüfschritte für den Nutzer: `docs/implementation_status.md`.
