# Plan Alpha 1.1 – Fundament: modulare Architektur

**Auftrag:** `docs/ROADMAP_ALPHA.md` Abschnitt 6 „Alpha 1.1“ (Muss 1–9), Abschnitt 8 (Zielarchitektur); Zusatz Weltarchitektur §2, §5, §13, §15 (vorbereitend).
**Ziel:** Das Projekt so umbauen, dass große und mehrere Karten, viele neue Simulationsmodule und ein modularer Spielstand möglich werden – **ohne Funktionsverlust und ohne sichtbare Verhaltensänderung**.
**Beginn / Ende:** 28.11.2026 (ein Chat, Gruppe 1.1–1.3 nach D7).

## 1. Bestandsprüfung (aus Code und Tests, nicht aus der Doku)
| Punkt | Befund v0.6.1 |
|---|---|
| Ausgangstests | `tests/run_tests.gd -- --quick` auf Godot 4.7.2: **491/491** (372,7 s), vor jeder Änderung |
| Simulationspfad | `LifeSimulation.step` rief 12 Systeme in fest verdrahteter Reihenfolge; die Schleife je Wesen mischte Stoffwechsel, Wahrnehmung (vier Systeme) und Entscheidung |
| Geländezugriff | direkte Zugriffe auf `VoxelData` außerhalb von `scripts/world`: `god_commands.gd`, `structure_system.gd`, `save_manager.gd`; `Perception` und `mind_scenarios` riefen `world.raycast` |
| Feste Kartengröße | Generatorwerte (Startgebiet, See) als Zellkoordinaten in `data/config/world.json`; Navigation, Wasser und Chunks lasen die Größe schon aus den Weltdaten – eine andere Größe war nie getestet |
| Spielstand | Format 5: eine flache JSON-Datei; Terrainänderungen als Liste `[globaler Index, Typ]`; strenge Definitionsprüfung (jede Änderung an `data/` macht alte Stände unladbar, außer über eine Migrationsstufe) |
| Zufall | `Simulation.rng` (Bruchstücke, Gespräche), Nahrungs-Zufall, ein Strom je Wesen, feste Zuschläge auf den Weltstartwert im Generator |
| Leistung | `LifeSimulation.perf` (Gesamtzeit je Takt), keine Aufschlüsselung |
| Prüflinge | Format 5 fehlte in `tests/fixtures/` |

## 2. Entscheidungen (mit Grund)
| Nr | Entscheidung | Grund |
|---|---|---|
| E1 | **Erst einhüllen, dann umziehen:** Die Module rufen die vorhandenen Systeme auf; die Systeme selbst (`ActionExecutor`, `DecisionSystem`, `ExperimentSystem` …) bleiben unverändert an ihrem Ort. | Roadmap-Risiko „Umbau bricht Verhalten“. Nachweis über bitgleiche Zustandsprüfsummen (Abschnitt 4). Das Verschieben von Dateien bringt in 1.1 keinen Nutzen und würde den Versionsvergleich mit Scheinänderungen füllen. |
| E2 | **Modulvertrag um `actor_tick` erweitert** (Roadmap 8.3 nannte nur `tick`). Aufeinander folgende Akteur-Module bilden eine Gruppe und laufen **je Wesen** nacheinander. | Nur so bleibt die Reihenfolge „Körper → Wahrnehmung → Entscheidung je Wesen“ erhalten. Eine Schleife je Modul über alle Wesen hätte das Verhalten verändert (Wesen 2 hätte die Entscheidung von Wesen 1 im selben Takt schon gesehen). |
| E3 | **Vorhandene Zufallsströme bleiben unverändert**; die neuen Ströme je Modul (`RngStreams`) gelten für neue Module. | Würden die alten Systeme umgestellt, wäre kein bitgleicher Vergleich mit v0.6.1 möglich. Das Ziel („neue Module verschieben bestehende Abläufe nicht“) ist erreicht und getestet. |
| E4 | **Format 6 als eine Datei** mit Kopf (`meta`), Abschnitten je Modul (`modules`) und Regionen (`regions`) – nicht als Ordner mit einzelnen Dateien (Roadmap 8.8). | Der logische Aufbau ist derselbe. Getrennte Dateien je Region und Chunk lohnen erst mit gestreamten Chunks (Alpha 1.2); bis dahin blieben Sicherung (.bak), Prüfsumme und das Menü unnötig kompliziert. Abweichung im Änderungsprotokoll der Roadmap vermerkt, offen für 1.2. |
| E5 | **Definitionsprüfung bleibt streng, kennt aber ausgelieferte Vorversionen** (`SaveSchema.SHIPPED_DEFINITIONS`). | Jede Alpha-Version ändert Definitionen. Ein Spielstand mit den Definitionen einer ausgelieferten Version wird geladen und je Modul angehoben; von Hand veränderte Definitionen werden weiter abgewiesen. |
| E6 | **Kartenvorlage überschreibt nur einzelne Generatorwerte** aus `data/config/world.json` (`generator_params`); „lichtung“ überschreibt nichts. | Eine Quelle der Wahrheit für die Werte von v0.6.1; das Gelände bleibt bitgleich (SHA-256 `b54f3496…`). Die Pipeline Höhe → Biome → Gewässer kommt mit 1.2. |
| E7 | **Prüfkarte nicht gelistet** (`pruefkarte_schmal`, 48 × 32 × 80 Zellen). | Sie beweist nur, dass keine feste Kartengröße angenommen wird; größere, spielbare Karten sind Auftrag von 1.2. |
| E8 | **Flache Sicht bleibt** (`SaveManager.snapshot` = `flat(document)`). | Tests, Vergleichswerkzeuge und das Menü lesen weiter `creatures`, `foods` … ohne den Aufbau der Datei zu kennen. |

## 3. Aufgabenliste mit Nachweis
Status: erledigt / teilweise / offen. „Erledigt“ nur mit Nachweis.

| Nr | Aufgabe (Roadmap Alpha 1.1) | Status | Nachweis | Bemerkung |
|---|---|---|---|---|
| 1a | Vermessung: Karten-, Chunk-, Zellgröße | erledigt | `docs/world_expansion.md` Abschnitt 2; `tools/benchmark_world.gd` | |
| 1b | Vermessung: Simulationszeit je System, Speicherbedarf | erledigt | `world_expansion.md` Abschnitt 3 (Zeit je Modul, 111 MB) | |
| 1c | Vermessung: Mesh- und Kollisionsdauer, Navigationskosten | erledigt | `world_expansion.md` Abschnitt 3 (9,6 ms je Chunk; Wegsuche Ø 8,5 ms) | ohne Grafikkarte gemessen |
| 1d | Vermessung: **Bildzeiten** je System | **offen – nicht verifiziert, Test beim Nutzer** | – | Die Arbeitsumgebung hat keine Grafikkarte. Der Nutzer kann `benchmark_world.gd` ohne `--headless` starten; die Messszene mit Bildzeiten kommt in 1.2. Übernommen nach Alpha 1.2. |
| 2a | `SimModule` + `ModuleRegistry`, Reihenfolge aus Abhängigkeiten | erledigt | `scripts/core/sim_module.gd`, `module_registry.gd`; Tests `[Module]` _t01, _t02 | |
| 2b | Vorhandene Systeme als Module: Leben, Geist, Soziales, Kommunikation/KI, Technik, Arbeit, Lager und Bauwerke, Tag/Nacht, Nahrung, Göttermenü | erledigt | 16 Module in `scripts/modules/`; Test _t01 (Reihenfolge = Taktreihenfolge v0.6.1) | Geist = `mind.perception` + `mind.decision`; Technik = `technology.tools` + `technology.perception` + `technology` |
| 2c | Modul **Wasser** | teilweise | Wasser läuft weiter in `VoxelWorld._physics_process` (Welt-Schicht) und ist über `WorldAccess` abfragbar | Kein eigenes `SimModule`: Wasser tickt in der Spielszene am Szenenbaum, in den Tests gar nicht. Ein Umzug in den Simulationspfad hätte das Verhalten der Tests verändert. Übernommen nach Alpha 1.2 (aktive Spalten, Zonen). |
| 2d | Jedes Modul hat Takt, Messwerte und Speicherabschnitt | erledigt | `tick`/`actor_tick`, `metrics()`, `save_section()`; Tests _t07, _t13 | 10 Module haben Zustand und Abschnitt, 6 sind zustandslos |
| 2e | Verhalten bleibt gleich; ein Entscheider, eine Ausführung | erledigt | Zustandsprüfsummen vorher/nachher identisch (Abschnitt 4); `DecisionModule` ruft nur `DecisionSystem.decide` | |
| 3a | `WorldAccess` als einzige Geländeschnittstelle | erledigt | `scripts/world/world_access.gd`, `ctx.terrain`; Tests _t04, _t12 | |
| 3b | Alle direkten Zugriffe von außerhalb der Welt-Schicht umgestellt | erledigt | Test _t12 durchsucht `scripts/` außer `scripts/world` | Die Testszenen setzen Mauern weiter über `VoxelWorld.set_voxel` (derselbe Schreibweg, den `set_material` benutzt) |
| 3c | Testfall nicht-quadratische Karte | erledigt | Test _t06 (48 × 32 × 80, 60 s, 50 Wesen, Speichern/Laden) | |
| 4a | Kartenvorlagen `data/maps/*.json` mit ID, Name, Größe, Zellgröße, Startwert, Generatorversion, Biomen, Startgebiet, Breite, Meer | erledigt | `scripts/world/map_template.gd`, `data/maps/lichtung.json`; Test _t05 | Biome, Startgebiet, Breite, Meer und Geologieprofil sind eingetragen und werden ab 1.2–1.4 ausgewertet |
| 4b | Heutige Welt = „Lichtung (klein, wie v0.6)“ | erledigt | Test _t05: Gelände bitgleich `b54f3496…` | |
| 4c | Neues-Spiel-Dialog mit Kartenwahl und Startwert | erledigt | `scripts/ui/main_menu.gd`; Szenentest „Startbildschirm (Alpha 1.1)“ | **Bedienung mit der Maus nicht verifiziert** (Szenentest ruft dieselben Funktionen) |
| 5a | Format 6: Kopf + Abschnitt je Modul mit eigener Version | erledigt | `SaveManager.document`, `ModuleRegistry.save_sections/prepare_sections/load_sections`; Tests _t07, _t11 | eine Datei statt Ordner (E4) |
| 5b | Weltänderungen als Chunk-Deltas gegenüber dem Generator | erledigt | `scripts/world/region_store.gd`; Tests _t07, _t08 | |
| 5c | Migration 5 → 6 mit **echten** v0.6.1-Spielständen (vor jeder Änderung erzeugt), auch Werkzeugkette mitten in einer Kette | erledigt | `tests/fixtures/save_v5_v061*.json` (Commit vor allen Änderungen); Test _t09 (3 Prüflinge, 16 Prüfungen) | Die übernommene Kette wird nach dem Laden zu Ende geführt |
| 5d | Original vor der Migration sichern | erledigt | Test _t09 (`….v5.vor_migration` = Original) | |
| 6 | Zufallsströme je Modul (Weltstartwert + Modul-ID) | erledigt | `scripts/core/rng_streams.gd`; Test _t03 | bestehende Ströme unverändert (E3) |
| 7a | `PerformanceMonitor` erweitert | erledigt | Zeile „Module (ms je Takt)“; Szenentest Lebenswelt | |
| 7b | `tools/benchmark_world.gd` mit Bericht (Simulationszeit je Modul, Speicher, Objektzahlen) | erledigt | Bericht `user://benchmark_report.txt`, Werte in `world_expansion.md` | Bildzeit: siehe 1d |
| 8 | Versionsumstellung `alpha-1.1`, Startbildschirm „Alpha 1.1“, Versionszweig | erledigt | `project.godot`; Test _t14; Zweig `version/alpha-1.1` | |
| 9 | Windows-Exportprofil, Build falls Vorlagen ladbar | erledigt (Build erzeugt), **Start unter Windows nicht verifiziert** | `export_presets.cfg`; `Pflanzenwesen_alpha-1.1_windows.zip`; das Spielpaket (.pck) startet mit der Linux-Engine: neues Spiel, 10 s, Speichern | Test beim Nutzer: ZIP entpacken, `Pflanzenwesen.exe` starten |
| A1 | Alle bisherigen Tests auf 4.7.2 und 4.5 grün | erledigt | `docs/test_results.md` | 3 Prüfungen an Format 6 angepasst (CHANGELOG „Geändert“) |
| A2 | Neue Tests: Modulreihenfolge, Abhängigkeitsfehler | erledigt | _t01, _t02 | |
| A3 | Neue Tests: Speicherabschnitte im Rundlauf | erledigt | _t07, _t11 | |
| A4 | Neue Tests: Migration 5 → 6 mit echtem Spielstand | erledigt | _t09 | |
| A5 | Neue Tests: Kartenvorlage lädt, nicht-quadratische Karte | erledigt | _t05, _t06 | |
| A6 | Neue Tests: Determinismus je Modul | erledigt | _t10 (zwei Läufe: Zustand und Messwerte je Modul gleich) | |
| A7 | Beobachtungslauf vor und nach dem Umbau, vergleichbare Messwerte | erledigt | Abschnitt 4 | Messwerte nicht nur vergleichbar, sondern identisch |
| A8 | `world_expansion.md` vorhanden | erledigt | `docs/world_expansion.md` | |
| W §2 | Weltarchitektur §2: Welt zuerst vermessen | erledigt | wie 1a–1c | 1d offen |
| W §5 | Weltarchitektur §5 (vorbereitend): Chunk-Struktur, Zugriffsschicht | erledigt (Vorbereitung) | `WorldAccess`, Chunk-Deltas | Streaming selbst ist Alpha 1.2 |
| W §13 | Weltarchitektur §13 (vorbereitend): Kartenwahl, Startgebiet | erledigt (Vorbereitung) | Kartenvorlagen mit `start_area` | Auswertung in 1.2 |
| W §15 | Weltarchitektur §15 (vorbereitend): Spielstände, alte Welten behalten ihre Größe | erledigt | Region speichert Vorlage, Größe und Generatorversion; Laden prüft Größe und Grundgelände | |
| P13 §4 | Prompt 13 §4 Fehlerprioritäten | erledigt | keine bekannten Fehler der Stufen „Absturz“ oder „Datenverlust“; Audit in allen Läufen ohne Befund | |
| D | Doku: README, CHANGELOG, HANDOVER, Roadmap-Status, `architecture.md`, `save_format.md`, `test_results.md`, `implementation_status.md` | erledigt | diese Lieferung | |
| L | Leitlinie nachziehen (HANDOVER 4a) | erledigt (nichts zu ändern) | Alpha 1.1 macht laut Alpha-Plan +0 Erfindungen möglich; `python3 tools/build_leitlinie.py --pruefen` ohne Befund | |

## 4. Vergleichsläufe vorher / nachher
`tools/state_hash.gd`, je 120 s, Startwert 12345, Godot 4.7.2. „Vorher“ ist der unveränderte Stand v0.6.1 (gemessen vor der ersten Codeänderung).

| Lauf | Gesamtprüfsumme vorher | nachher |
|---|---|---|
| normales Spiel (50 Wesen) | `8a47aa1594d43d4b77048e00` | identisch |
| Testwerkstatt, Verhalten an | `590346b6a35bfeae34110cce` | identisch |
| Testszene Werkzeugkette, Verhalten an | `dfcaaad48d16ffd95d1ff9b5` | identisch |

Taktzeit (50 Wesen, headless): vorher Ø 2,89 ms (300 s), nachher Ø 2,95 ms (120 s) – innerhalb der Messschwankung; die Zeitmessung je Modul kostet rund 500 Zeitabfragen je Takt.

## 5. Offene Punkte → Aufgabenliste Alpha 1.2
1. **Bildzeiten auf Grafikkarten** (GTX 1660 Ti, RTX 3080): nicht verifiziert – Messszene in 1.2, Messung beim Nutzer.
2. **Wasser als Modul** mit aktiven Spalten und im Simulationspfad (heute Welt-Schicht am Szenenbaum).
3. **Spielstand als Ordner** je Region/Chunk (Roadmap 8.8), sobald Chunks gestreamt werden.
4. **Windows-Build:** erzeugt, aber unter Windows nicht gestartet – Rückmeldung des Nutzers abwarten.
5. **Neues-Spiel-Dialog:** Bedienung von Hand nicht geprüft.
6. Weiter offen aus v0.6.1 (unverändert): echte Ollama-Tests beim Nutzer; Animationen als bewegte Bilder auf einer Grafikkarte.
