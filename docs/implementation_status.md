# Implementierungsstand (0.6.1-prototype – Prompt 1 bis 6B)

Statuswerte: **fertig + getestet** · **fertig, Sichtprüfung** · **teilweise** · **nicht implementiert (bewusst)**

## Prompt 1 – Projektgrundlage und Physiklabor
Unverändert **fertig + getestet** (Details in Version 0.1.0). Alle bisherigen Physiktests bestehen weiterhin.
Änderungen: Labor hat einen Knopf zurück zum Startbildschirm; Materialanzahl jetzt 6 (neu: Erde); Wärme- und Phasensysteme überspringen nicht-physikalische Entitäten.

## Prompt 2 – Excel-Import
| Funktion | Status | Nachweis |
|---|---|---|
| Original nur lesen (Prüfsumme unverändert) | fertig + getestet | Python-Test `test_original_untouched…` |
| Spalten über Kopfzeile, unbekannte Spalten/Blätter melden | fertig | Code, Bericht |
| fehlend ≠ „-“ (nicht anwendbar) | fertig + getestet | `test_missing_vs_not_applicable` |
| Zahlen, Ja/Nein, Farben, Verweise, Zusammensetzungen prüfen | fertig + getestet | Tests: Text in Zahlenspalte, ungültiger Verweis mit Zelle |
| Doppelte IDs / falsches ID-Format | fertig + getestet | `test_duplicate_id_detected`, `test_invalid_id_format_detected` |
| Stabile IDs bei erneutem Import und Umsortieren | fertig + getestet | `test_reimport…`, `test_generated_ids_stable_after_row_reorder` |
| Unterschiede vor dem Ersetzen melden (ohne `--write` nichts schreiben) | fertig + getestet | `test_dry_run_writes_nothing_but_reports_diff` |
| Ungültige Zeilen nicht übernehmen (`rejected` mit Zelle) | fertig + getestet | 4 abgewiesene Zeilen im echten Import |
| Formeln ohne gespeichertes Ergebnis melden | fertig, **ungetestet** (die Excel enthält keine Formeln) | Code |
| Spielstatus nur aus Konfiguration | fertig + getestet | `test_status_comes_only_from_config`, Godot-Test |
| Spiel lädt erzeugte JSON ohne Python/Excel | fertig + getestet | `DefinitionDB`, Godot-Tests |

## Prompt 2 – Voxelwelt
| Funktion | Status | Dateien | Nachweis |
|---|---|---|---|
| Testkarte 64×32×64 à 0,5 m, Startbereich flach, Hügel, See, Platz für Baum | fertig, Sichtprüfung | `world_generator.gd`, `world.json` | Bilder `screenshot_world_*` |
| Gleicher Startwert → gleiche Terrain- und Wasserdaten | fertig + getestet | | SHA-256-Vergleich, anderer Startwert ≠ |
| Nur Außenflächen, ein Netz je Chunk, kein Node je Voxel | fertig + getestet | `voxel_mesher.gd`, `voxel_chunk.gd` | Flächenzählung = unabhängige Zählung |
| Nur veränderte Chunks neu, Nachbarn an Grenzen | fertig + getestet | `voxel_world.gd` | Rebuild-Zähler je Chunk |
| Keine fehlenden Flächen an Chunkgrenzen | fertig + getestet | | 40 zufällige Randänderungen, Summe = Erwartung |
| Kollision passt zur Geometrie und wird aktualisiert | fertig + getestet | `chunk_collision.gd` | echte Physik-Strahlabfrage vor/nach Hinzufügen/Entfernen |
| Auswählen, Hinzufügen, Entfernen, Material wählen, Zurücksetzen | fertig + getestet (Logik); **Maus von Hand ungeprüft** | `world_preview.gd` | Szenentest über `apply_tool` |
| Vereinfachte Abstützung, Bruchstücke ohne doppelte Materie | fertig + getestet | `support_system.gd` | Massenbilanz, Grenzen (Anzahl, Größe) |
| Wasser: Erhaltung, Barrieren, Untergrundänderung | fertig + getestet | `water_system.gd` | 4 Tests synthetisch + Kanaltest in der Welt |
| Wasser in Höhlen/mehrere Ebenen | **nicht implementiert (bewusst, dokumentiert)** | | |

## Prompt 2 – Prozedurale Modelle
| Funktion | Status | Nachweis |
|---|---|---|
| Zweibeiner: Rumpf, Kopf, Gesicht, 2 Arme, 2 Beine, 1–3 Kopfblätter, Gelenkpunkte | fertig, Sichtprüfung + Tests | Bilder `screenshot_creature_*`, Generatortests |
| Körperteile mit ID, Typ, Funktion, Material, Maßen, Elternteil, Masse, Status | fertig + getestet | `body_plan.gd` |
| Doppelte IDs, ungültige Verbindungen, Zyklen verhindert | fertig + getestet | 4 Tests |
| Gekoppelte Variation (Größe, Proportion, Glieder, Farbe, Blattform, Blattzahl) | fertig + getestet | 10 Varianten gültig, Farbtöne im Grünbereich |
| Unterarm entfernen, Holz-/Kupferprothese, Blätter ± | fertig + getestet | Masse, Status, Darstellung, Fähigkeiten |
| Entfernte Hand greift nicht weiter | fertig + getestet | keine Gelenke/Netze/Kollision für entfernte Teile; Animator nutzt sie nicht |
| Animationen Ruhe, Gehen, Greifen, Zum Mund | fertig, Sichtprüfung (Einzelbilder) | Animator-Tests; **Bewegungsablauf nur in Standbildern geprüft** |
| Ersatzverhalten (andere Hand, Hakengriff) / verständliche Ablehnung | fertig + getestet | 4 Tests |
| Hinken bei fehlendem Bein (Excel A002) | **nicht implementiert**; Gehen wird mit Hinweis abgelehnt | Test |
| Lebensbaum mit Wurzeln und Wurzelbeet | fertig, Sichtprüfung + Tests | `tree_generator.gd`, Bild `world_2` |
| 3 Pflanzen- und 2 Pilzvarianten aus der Excel | fertig + getestet | `plant_generator.gd` |
| Kreaturenvorschau: Kamera, Licht, 1-m-Maßstab, Regler, Prothesenmaterial, Animationsknöpfe, Teile + Masse, Startwert | fertig, Sichtprüfung | Bilder |
| 10 Varianten, 50 Figuren mit Messung | fertig + getestet | Szenentests, Messung unten |
| Körperkonfiguration speichern/laden (`user://`) | fertig + getestet | JSON-Rundlauf, manipulierte Dateien abgewiesen |
| Startbildschirm mit drei Bereichen | fertig + getestet | Szenentest, Bild `screenshot_world_0` |

## Prompt 3 – Lebenssimulation
| Funktion | Status | Dateien | Nachweis |
|---|---|---|---|
| Gemeinsames Handlungssystem (move_to, pick_up, eat, drop, wait), 5 Zustände, Prüfung bei Start und je Schritt | fertig + getestet | `scripts/actions/` | Tests (4), (8), (9), Einzelwesen |
| Reservierung + atomare Entnahme, Freigabe bei Abbruch/Tod/Zeitlimit/Zielverlust/Ablauf | fertig + getestet | `action_executor.gd`, `food_source.gd` | (4), (8) |
| Unterbrechbares Essen mit korrekter Bilanz | fertig + getestet | `eat_action.gd` | Test „Unterbrochenes Essen“ |
| Strukturierte Ergebnisereignisse | fertig + getestet | `ActionExecutor.history`, EventLog | Test |
| Körper: Grundgene / aktueller Plan / Verletzungen / Prothesen / Fähigkeiten aus Teilfunktion | fertig + getestet | `body_capabilities.gd`, `health.gd`, `creature.gd` | (7), Einzelwesen |
| Stoffwechsel: Energie, Nährstoffe, Grundumsatz ∝ Masse, Bewegung, Handlungen, Mangel → Tod | fertig + getestet | `metabolism.gd` | Energiebilanz < 10⁻⁶ J in allen Tests |
| Nahrungsbilanz inkl. Abfall | fertig + getestet | `resource_ledger.gd` | (3), Dauerlauf |
| Photosynthese (Blattfläche × Licht × Verschattung × Blattzustand), kein Schlafzwang | fertig + getestet | `photosynthesis.gd`, `day_night_system.gd` | (5), (6) |
| Tod: Handlungsabbruch, Freigabe, Ablegen, Körper bleibt, kein Recycling | fertig + getestet | `creature.gd` | (10) |
| Endliche Nahrung aus Excel N001/N002, Restmenge sichtbar | fertig + getestet; Darstellung Sichtprüfung | `life_simulation.gd`, `living_world.gd` | Tests, Bilder |
| Nachfüllen nur als sichtbare Testoption | fertig + getestet | `LifeSimulation.refill_test` | Bilanzprüfung mit `refill_kg` |
| Wahrnehmung: Radius, Sichtprüfung, Merkliste, erneute Prüfung bei Ankunft | fertig + getestet | `perception.gd` | Einzelwesen |
| Verhalten: Bedarf → Auswahl → hingehen → aufnehmen → essen; Erkunden; Warten/Umhergehen; Hysterese, Verwerfen unerreichbarer Ziele | fertig + getestet | `basic_behavior.gd` | Einzelwesen, Dauerlauf |
| Navigation: Spaltenraster-A*, Stufen, Hindernisse, Spaltenaktualisierung, Blockade → begrenzte Neuplanung/erklärter Fehlschlag, Ausweichen | fertig + getestet | `navigation_service.gd`, `locomotion.gd` | (9) |
| Genau 50 Wesen, eindeutige IDs, reproduzierbar, gültige Startpositionen | fertig + getestet | `population_spawner.gd` | (1), (2) |
| Animation an Handlungen gekoppelt (Gehen ∝ Geschwindigkeit, Greifen nur mit Fähigkeit, Essen bei echtem Essen) | fertig + getestet (Zuordnung); **Bewegungsablauf nur als Standbild gesehen** | `living_world.gd` | Szenentest „Gehanimation nur bei Bewegung“ |
| Entwicklermodus: Unterarm, Holz-/Kupferprothese, Bein, Blatt, Töten, Verhalten anhalten | fertig + getestet | `living_world.gd`, `LifeSimulation.dev_body_change` | Tests, Bild `life_3` |
| Beobachtungsfenster, Population, Ereignisse, Leistung | fertig, Sichtprüfung + Szenentest | `scripts/ui/`, `scripts/debug/` | Bilder `life_1/2` |
| Menü: Neues Spiel, Fortsetzen/Laden, (Sicherung laden), drei Vorschaubereiche | fertig + getestet | `main_menu.gd` | Szenentest |
| Pause hält Simulation, Kamera/Oberfläche bleiben bedienbar | fertig + getestet | `living_world.gd` | (11) Logik + Szene |
| Speichern/Laden mit Temp-Datei, Sicherung, Prüfsumme, Formatversion, Definitionsfingerabdruck, Ladeverhalten | fertig + getestet | `scripts/persistence/` | (12)–(14) |
| Migrationsschnittstelle (ohne erfundene Migrationen) | fertig + getestet | `save_migrations.gd` | Test |
| Bruchstücke im Spielstand | **nicht implementiert** (in der Lebenswelt entstehen keine) | | dokumentiert |

## Prompt 4 – Bestandsprüfung (vor der Umsetzung)
| Bereich | Befund in v0.3.0 | Folge |
|---|---|---|
| Wahrnehmung | Nahrung mit Radius und Sichtlinie, Merkliste – getestet | erweitert: sichtbare Wesen, Ereignisverteilung |
| Einfaches Verhalten | `BasicBehavior.decide`, Hunger-Hysterese – getestet | ersetzt durch `DecisionSystem` (einziger Entscheider) |
| Handlungssystem | 5 Handlungen, Reservierungen – getestet | um 5 Handlungen und `reserve_carried` erweitert |
| Ereignisprotokoll | gemeinsam, begrenzt (1000), Routine gefiltert – getestet | weiterverwendet über `LifeContext.publish`; nicht als Wissensquelle der Wesen |
| Körperfunktionen | Fähigkeiten aus Teilfunktionen – getestet | um `gesture` (Oberarm) ergänzt |
| Speichern und Laden | Format 1, strenge Definitionsprüfung – getestet | Format 2 und Migration 1→2 |
| Beobachtungsoberfläche | Inspektor, Population, Ereignisse – Szenentest und Sichtprüfung | erweitert (Geist, Vergleich, Göttermenü) |

Zusätzlich lag ein heute Vormittag abgebrochener, nie ausgelieferter Entwurf zu Prompt 4 vor (Geist, Beziehungen, Bitten). Er wurde Datei für Datei geprüft, übernommen und um die fehlenden Teile ergänzt (Eingriffe, Göttermenü, Oberfläche, Speicherformat 2, Migration, Tests, Doku). Zwei Fehler des Entwurfs wurden dabei behoben: ein doppelter Variablenname und das Überschreiben einer gerade übergebenen Portion durch ein laufendes Aufnehmen.

## Prompt 4 – Geist, Soziales, Göttermenü
| Funktion | Status | Dateien | Nachweis |
|---|---|---|---|
| Persönlichkeit (5 Werte, reproduzierbar, begrenzt, fest, wirkt auf Bewertungen) | fertig und getestet | `mind/personality.gd` | Tests Persönlichkeit, Entscheidungen |
| Beobachtungen nur bei Wahrnehmung (Reichweite, Sichtlinie, Qualität, Quellenart) | fertig und getestet | `perception.gd`, `mind/observation.gd` | Szenario C |
| Erinnerungen (begrenzt, Verblassen, Verdichtung ohne Erfinden, Abruf) | fertig und getestet | `mind/memory_store.gd` | Tests Kapazität, Verdichtung, Protokoll geleert |
| Überzeugungen (Beta-Modell, Vergessen, Konfidenz getrennt von Wert, Grundhäufigkeit) | fertig und getestet | `mind/belief_store.gd`, `learning_system.gd` | Szenarien D und E |
| Gerichtete Beziehungen (Vertrautheit, Vertrauen, Hilfe, Ablehnung, Ähnlichkeit aus Sichtbarem) | fertig und getestet | `mind/relationship_store.gd` | Szenarien A, B und F |
| Soziale Handlungen (bitten, anbieten, geben, ablehnen) mit Reservierung und Wartezeiten | fertig und getestet; spontanes Auftreten gemessen | `actions/implementations/*`, `social/*` | Szenario B, Wartezeit-Test, Dauerlauf |
| Entscheidungssystem mit protokollierten Beiträgen, Zielbindung, Überlebensvorrang | fertig und getestet | `mind/decision_system.gd`, `goal_manager.gd` | Entscheidungstests |
| Schnittstelle für Zielvorschläge (Ollama vorbereitet, keine Verbindung) | fertig und getestet | `GoalManager.suggest` | Test |
| Göttermenü: Nahrung, Material, Heilung, Ereigniszuordnung, Vorschau, Prüfung, Bilanz, Protokoll | fertig und getestet | `god/*`, `ui/god_menu.gd` | Göttermenü-Tests (Logik und Szene) |
| Belohnungszuordnung (zeitgewichtet, begrenzt, Wert je Wesen, Beobachter mit anderer Erklärung) | fertig und getestet | `god/reward_association.gd` | Szenario D |
| „Arme heben“ (neutral, gelegentlich ausprobiert, Animation nur mit Oberarm) | fertig und getestet; Animation nur als Standbild gesehen | `raise_arms_action.gd`, `creature_animator.gd` | Szenario D, Bild |
| Beobachtungsfenster mit getrennten Ebenen, Vergleichsansicht | fertig, Szenentest und Sichtprüfung | `ui/creature_inspector.gd`, `living_world.gd` | Bilder `life_6–8` |
| Speicherformat 2 und Migration aus v0.3.0 mit Sicherung | fertig und getestet (echter v0.3.0-Spielstand) | `persistence/*` | Migrationstests |
| Testbereich „Geistlabor“ (Szenarien A–G sichtbar) | fertig, Szenenstart getestet | `lab/mind_*`, `scenes/tests/mind_lab.tscn` | Bild `life_9` |

## Prompt 5 – Bestands- und Verbindungsprüfung (vor der Umsetzung)
| Prüfpunkt | Ergebnis |
|---|---|
| Entscheidungssystem, Zielverwaltung | `DecisionSystem` einziger Entscheider; `GoalManager.suggest` (Zuschlag ≤ 0,2, Ablaufzeit) vorhanden und getestet → weiterverwendet |
| Handlungsschnittstelle | `ActionExecutor.request` mit Prüfung, Reservierung, Ladeverhalten → Planschritte nutzen sie unverändert |
| Wahrnehmung, Erinnerungen, Überzeugungen, Beziehungen | individuell (Prompt 4) → Grundlage des Kontexts und der Gesprächsthemen |
| Speichern/Laden | Format 2 mit Migration 1→2; Migrationskette musste für 2→3 angepasst werden (1→2 setzt jetzt den v0.4.0-Fingerabdruck) |
| Ollama lokal erreichbar? | **Nein** im Entwicklungsarbeitsbereich (`127.0.0.1:11434` → Verbindung abgelehnt; kein `ollama`-Programm) |
| Installierte Modelle | im Arbeitsbereich keine; auf deinem Rechner unbekannt → KI-Panel/Live-Test zeigen sie |
| Hardware zuverlässig ermittelbar | CPU-Name, Kerne, RAM über Godot; GPU im Kopflos-Modus **nicht**; Grafikspeicher-Nutzung eines geladenen Modells über `/api/ps` |
| API | nach offizieller Doku: `/api/version`, `/api/tags`, `/api/ps`, `/api/chat` mit `format` (JSON-Schema, seit 0.5), `stream`, `options`, `keep_alive`, `think` |
| Folge | alles unabhängig Umsetzbare gebaut; Tests mit SIMULIERTEM Dienst und HTTP-Attrappe; reale Integration **nicht verifiziert**; kein Download gestartet |

## Prompt 5 – Ollama-Anbindung, Pläne, Gespräche
| Funktion | Status | Dateien | Nachweis |
|---|---|---|---|
| Einstellungen (ein/aus, Adresse nur lokal, Modell, Zeitlimit, Antwortlänge, Warteschlange, gleichzeitig 1, Abstand je Wesen, globale Rate); Schlüssel nie gespeichert | fertig und getestet | `ai/ai_settings.gd`, `data/settings/ai.json` | KI-Tests Einstellungen |
| Client nur mit Abfragen, nicht blockierend | fertig; HTTP-Weg gegen **Attrappe** getestet, gegen echtes Ollama **nicht verifiziert** | `ai/ollama_client.gd`, `ai/http_transport.gd` | KI-Tests HTTP-Attrappe, geschlossener Port |
| Warteschlange (Priorität, Länge, Fairness, Duplikate, Ablauf, Wiederholung, Unterbrecher, Wiederaufnahme) | fertig und getestet (SIMULIERT) | `ai/request_queue.gd`, `ai/ai_service.gd` | KI-Tests Warteschlange, Ausfall |
| Sitzungsnummer; Laden/Neustart/Tod/Pause | fertig und getestet (SIMULIERT) | `ai/ai_system.gd` | KI-Tests (5)–(8) |
| Anlässe (Scheitern, Ereignis, knappe Wahl, Widerspruch, Gespräch); nie bei kritischem Hunger | fertig; Häufigkeit nur mit SIMULIERTEM Dienst gemessen | `ai/ai_system.gd`, `mind.json` | 50-Wesen-Lauf |
| Kontext nur aus eigenen Daten, begrenzt | fertig und getestet | `ai/context_builder.gd` | KI-Test (12) Kontext |
| Strukturierte Antworten + 7 Prüfstufen | fertig und getestet (SIMULIERT) | `ai/response_validator.gd`, `data/ai/*.json` | KI-Tests (2)–(4), Stufen 1–7 |
| Pläne: Annahme, Option im einzigen Entscheider, Schritt-Neuprüfung, kein Ersatzobjekt, Sperre gescheiterter Pläne | fertig und getestet (SIMULIERT) | `ai/plan_manager.gd`, `decision_system.gd` | KI-Tests (1), gegessenes Ziel |
| Deutung widersprüchlicher Erfahrungen (nur Notiz, kein Beleg) | fertig; nur mit SIMULIERTEM Dienst gesehen | `plan_manager.gd` | – |
| Gespräche (5 Absichten, Vorlagentext, Wartezeiten, Sichtlinie) – lokal und über Modell | fertig und getestet | `social/communication_system.gd`, `talk_action.gd` | KI-Tests Gespräch, 10-min-Lauf |
| Hörensagen, Herkunft, Weitererzählen ≠ unabhängig, Prüfung (bestätigt/veraltet/Fehler/widersprochen/nicht prüfbar), vorsichtiges Vertrauen | fertig und getestet | `social/claim_evaluator.gd` | KI-Tests (11), (12), Prüfstatus |
| Strategische Täuschung | **nicht implementiert** (Sprecher sagen nur, was sie selbst glauben) | – | Test „keine Täuschung“ |
| KI-Panel (K), Gesprächsansicht (C), Wesenfenster-Abschnitte | fertig; Szenentest, Bildschirmfotos (SIMULIERT) | `ui/ai_status_panel.gd`, `ui/conversation_viewer.gd`, `creature_inspector.gd` | Bilder `life_10–12` |
| Speicherformat 3, Migration 2→3 (echter v0.4.0-Stand), Kette 1→2→3 | fertig und getestet | `persistence/*` | Migrationstests |
| Live-Test mit echtem Ollama (Plan, Gespräch, 50 Wesen, Ausfall, Wiederkehr) | Werkzeug fertig, gegen Attrappe gelaufen; **mit Ollama nicht ausgeführt** | `tools/ollama_live_test.gd` | – |

## Prompt 6 – Bestandsprüfung (vor der Umsetzung)
Ausführlich, mit Dateien, Evidenz und Blockern: **`docs/progress_audit.md`**. Ausgangsbasis v0.5.1: 354/354 auf Godot 4.7.2 und 4.5.

## Prompt 6 – Experimente, Werkzeuge, praktisches Wissen
| Funktion | Status | Dateien | Nachweis |
|---|---|---|---|
| Vorhandenen Gegenstand als Werkzeug benutzen (Stein in der Hand) | fertig und getestet | `technology/tool_use_system.gd`, `equip_tool`, `strike_target`, `deform_material` | Technik (2) |
| Stiel und Kopf mit Fasern verbinden (Masse exakt, Fasern Teil des Verbunds) | fertig und getestet | `technology/construction_system.gd`, `connection_definition.gd`, `connect_parts` | Technik (3) |
| Werkzeug praktisch testen, funktionale Bewertung ohne Namen | fertig und getestet | `technology/object_evaluator.gd` | Technik (1), Versuch 3 |
| Überlast, Bruch, keine doppelten Teile | fertig und getestet | `tool_use_system.gd`, `ConstructionSystem.dissolve`/`audit` | Technik (4), (5) |
| Kupfer kalt verformen (Δε = W/(σV), Verfestigung, Risse) | fertig und getestet | `physics/material_process_system.gd` | Technik (6) |
| Kupfer mit Testheizung schmelzen und gießen (Masse/Energie exakt, Bilanz geschlossen) | fertig und getestet | `technology/test_heater.gd`, `place_in_heater`, `pour_into_mold`, `MaterialProcessSystem.pour` | Technik (7), (8) |
| Heiße Gegenstände (Temperaturkategorie, Verbrennung bilanziert, Reflex) | fertig und getestet | `ToolUseSystem.touch_burn`, `tick` | Technik (9) |
| Versuchsprotokoll, Abbruch mit Zwischenstand | fertig und getestet | `technology/experiment_record.gd`, `experiment_system.gd` | Technik (10) |
| Eigenständige, begrenzte Versuche (Neugier, Bedarf, Risiko, Zeitbudget, Weg, Gedächtnis für gescheiterte Versuche) | fertig; **spontanes Auftreten nur gemessen** | `ExperimentSystem.options`, `DecisionSystem` | Beobachtungslauf, `tools/observe_workshop.gd` |
| Teile zum Verbinden zusammentragen (aufnehmen → gehen → ablegen) | fertig und getestet | `ExperimentSystem._advance_bring` | Technik (3b) |
| Modellvorschläge nur als ungeprüfte Hypothese, Schritte über `dry_run` geprüft | fertig und getestet (**SIMULIERT**); echtes Ollama **nicht verifiziert** | `ai/response_validator.gd`, `data/ai/experiment_schema.json` | Technik (11) |
| Verfahrenswissen (gehört < zugesehen < versucht < erfolgreich), Quellen, Versionen | fertig und getestet | `technology/procedural_knowledge.gd` | Technik (12), (13) |
| Erklären, Vorführen, Zusehen, Üben | fertig und getestet | `social/teaching_system.gd`, `demonstrate_procedure`, `practice_procedure` | Technik (13) |
| Wissen individuell, kein Übergang beim Tod | fertig und getestet | `creature.gd`, `procedural_knowledge.gd` | Technik (12) |
| Testwerkstatt getrennt vom Spiel; normales Spiel ohne Testausrüstung | fertig und getestet | `lab/test_workshop.gd`, `main_menu.gd` | Technik (15), Szenentest |
| Sichtbare Modelle der Gegenstände (Teile, Formänderung, Bruch, Guss, Glühen, Halten) | fertig; Zuordnung Daten → Modell getestet; **Aussehen nur mit Software-Rendering gesehen** | `generation/object_generator.gd`, `living_world.gd` | Szenentest Werkstatt |
| Oberflächen: Versuch/Gegenstand (E), Wissen (W); Spielerdiagnose getrennt | fertig und getestet (Inhalt); **Bedienung von Hand ungeprüft** | `ui/experiment_inspector.gd`, `ui/knowledge_viewer.gd` | Szenentest Werkstatt |
| Göttermenü: Pflanzenfasern, Formen (kleiner Block, Stab, Faserbündel) | fertig und getestet | `god/god_commands.gd`, `ui/god_menu.gd` | Technik (15) |
| Speicherformat 4, Migration 3→4 (echter v0.5.1-Stand), Kette 1→2→3→4 | fertig und getestet | `persistence/*`, `tests/fixtures/save_v3_prompt05.json` | Technik (14) |

## Prompt 6B – Bestandsprüfung (vor der Umsetzung)
Aus dem Code gelesen (nicht aus der Doku), Ausgangsbasis v0.6.0: 432/432 auf Godot 4.7.2 und 4.5. Befund
(ausführlich in `docs/plan_prompt_06b.md`, Abschnitt 3): Technikhandlungen zeigten nur die Ruhehaltung; gehaltene
Gegenstände saßen an einem festen Punkt vor dem Körper; Schaden kam am Ende der Schwungdauer ohne sichtbare
Kontaktphase, 1,1 m Reichweite erlaubte „Hämmern neben dem Ziel“; nur einhändiges Halten; kein Lager, keine Baustelle,
keine Arbeitskette aus Bedarf; Bruchstücke verloren Testausrüstungs-Kennzeichen; Heizung hätte Stein/Holz „erhitzt“.

## Prompt 6B – Excel-Abgleich, Arbeitsanimationen, Werkzeug- und Materialkette
| Funktion | Status | Dateien | Nachweis |
|---|---|---|---|
| Hammer aus vorhandenen Teilen binden; eigene eindeutige ID; Ausrüsten ohne Kopie | fertig und getestet | `technology/work_system.gd`, `connect_parts`, `equip_tool` | Arbeit (lagern) |
| Sichtbarer Griffpunkt (Gegenstand an der animierten Hand, zweihändig mittig) | fertig und getestet (Zahlen); **Aussehen nur mit Software-Rendering gesehen** | `living_world.gd` `_place_held`, `creature_animator.gd` `grip_frame` | Szenentests Werkstatt + Werkzeugkette, Bildschirmfotos |
| Schlag synchron mit sichtbarem Kontakt, genau ein Schaden je Schlag, Kopf trifft das Ziel | fertig und getestet (Abweichung ≈ 2 cm) | `work_pose.gd`, `work_motion.gd`, `tech_action_util.gd` | Arbeit (lagern), Schlag-Kontakt, Szenentest |
| Bruchstücke mit Masse, Material, Wärme; Verformung statt Bruch bei Kupfer | fertig und getestet | `material_process_system.gd` | Arbeit (lagern), (schmelzen) |
| Aufnehmen, Tragen (eine/zwei Hände), Ablegen | fertig und getestet | `tool_use_system.gd`, `equip_tool`, `drop` | Arbeit (lagern), Fehlerfälle |
| Realer Lagerplatz (Kapazität, Platzraster, Temperaturgrenze) | fertig und getestet | `settlement/storage_*` | Arbeit (lagern) |
| Einfaches Einzelbauwerk „Steinreihe“ mit messbarer Funktion | fertig und getestet | `settlement/structure_*` | Arbeit (bauen) |
| Schmelzen im Testofen, ungeeignete Materialien abgewiesen, gleichartige Schmelzen vereinigt | fertig und getestet; **nur mit Testausrüstung** | `MaterialProcessSystem.melt_support/merge_melts`, `put_into_container` | Arbeit (schmelzen), Fehlerfall ungeeignet |
| Arbeitsanimationen: Tragen, Ablegen, Hämmern, Zusammenfügen (auch einarmig), Einsetzen, Erhitzen bedienen, Gießen, Anlauf | fertig; Geometrie getestet; **Bewegung nur als Standbilder gesehen** | `creature_animator.gd`, `work_pose.gd` | Arbeitsposen-Tests, `docs/animations.md` |
| Graben / Erde verdichten | **vorbereitet, abgewiesen** (keine Abbau-Mengenbilanz) | `creature_animator.gd` | Test Körpergrenzen |
| Fehlender Arm: einarmige Variante oder Ablehnung; keine Animation nutzt entfernte Teile | fertig und getestet | `creature_animator.gd`, `work_motion.gd` | Test Körpergrenzen, Fehlerfall Arm |
| Arbeitsketten aus eigenem Bedarf (eigenes Wissen, Pause bei Hunger, Umplanen) | fertig; **eigenständige Wahl beobachtet** (nach gezielter Vorgeschichte) | `WorkSystem.needs/options`, `DecisionSystem` | Beobachtungslauf Arbeit |
| Ollama-Anfrageart `work` (nur geprüfter Vorschlag, Ausführung über Handlungen) | fertig und getestet (**SIMULIERT**); echtes Ollama **nicht verifiziert** | `ai/*`, `data/ai/work_schema.json` | Arbeit (Modellanfrage) |
| Testszene Werkzeugkette mit Anzeige (Ziel, Handlung, Werkzeug-ID, Zielobjekt, Masse, Fortschritt, Abbruchgrund) und 7 Fehlerfällen | fertig und getestet; **Bedienung von Hand ungeprüft** | `lab/work_chain_scene.gd`, `living_world.gd`, `creature_inspector.gd` | Szenentest Werkzeugkette, Fehlerfälle |
| Unterbrechung, Speichern/Laden während der Herstellung | fertig und getestet | `WorkSystem.pause/after_load`, Format 5 | Arbeit (Unterbrechung, Speichern/Laden) |
| Normaler Spielmodus nutzt denselben Code | fertig und getestet | – | Arbeit (Normales Spiel) |
| Excel-Importkonfiguration (Korrekturen, Projektentscheidungen) | fertig und getestet | `design/import_config/`, `tools/import_definitions.py` | Arbeit (Excel-Abgleich), `reports/import_report.md` |
| Erfindungskatalog „echte Namen“ (nur Katalog, kein Startwissen) + aktivierte Definitionen | fertig und getestet | `tools/import_inventions_real.py`, `data/config/inventions_activated.json` | Arbeit (Erfindungen), `reports/inventions_real_import_report.md` |
| Speicherformat 5, Migration 4→5 (echte v0.6.0-Stände) | fertig und getestet | `persistence/*`, `tests/fixtures/save_v4_prompt06*.json` | Arbeit (Migration) |
| Gemeinsames Siedlungsbauen | **nicht implementiert** (Prompt 9) | – | – |

## Weitere Ergänzungen in 0.4.0
- **Ideenkatalog aus der Erfindungs-Excel:** `docs/inventions_catalog.md`. 5498 Einträge und 96 Grundbegriffe, **nichts davon aktiv**, keine globalen Boni.
- **Prompt 11** (Schrift, Bücher, Wissen) ist unter `design/prompts/` aufbewahrt. Er setzt Prompt 5–10 voraus und wird erst danach umgesetzt.

## Bewusst nicht implementiert (Stand Prompt 6B)
- Freie Sprache (nur strukturierte Mitteilungen), Bücher/Schrift, Religion, politische Institutionen.
- Strategische Täuschung/Lügen (Sprecher können nur eigenes Wissen mitteilen).
- Ausführung generierten Codes, neue Physik oder Technik aus Modellbehauptungen, Modelltraining/Fine-Tuning.
- Persönlichkeitsentwicklung über die Zeit. Fertigkeiten gibt es nur als Verfahrenswissen aus Prompt 6 (Stufe wirkt auf das Geschick beim Umwickeln).
- Kausales Schließen über zeitliche Häufigkeiten hinaus (siehe `docs/mind_and_learning.md`).
- Fortpflanzung, Baumgründung, Kriege, Institutionen.
- Technologiebaum, Freischaltungen, weitere Werkzeugtypen (Schneiden, Bohren …), weitere Verbindungsmethoden für Wesen, Feuer, selbst gebaute Öfen (nur Testofen), Erzabbau, Legierungen, Schmelzströmung, Temperaturverteilung in einem Gegenstand.
- Graben/Abbau aus dem Gelände und Erde verdichten (Posen vorbereitet, abgewiesen); gemeinsames Bauen, Siedlungen, Aufgabenverteilung (Prompt 9); Ellbogenbeugung in Arbeitsposen; Hinken.
- Fasern gewinnen (Pflanzen zerlegen). Fasern gibt es nur in der Testwerkstatt und über das Göttermenü.
- Weitere Eingriffe (Wetter, Strafe); Fliehen (KI003), Durst (KI002).
- Aus Prompt 3 weiterhin: Regeneration, Pflanzenwachstum, Hinken, mehrere Spielstände, Zeitbeschleunigung.

## Tatsächlich ausgeführte Prüfungen
Umgebung: Linux-Container, Xeon 2,1 GHz (2 Kerne), **keine GPU**.

| Prüfung | Godot 4.7.2 | Godot 4.5 |
|---|---|---|
| `tests/run_tests.gd` (inkl. 10-Minuten-Dauerlauf, Szenarien A–G, Migrationen 1→2→3→4→5 mit echten Spielständen, KI-Prüfungen mit SIMULIERTEM Dienst, Technik-Abnahmetests (1)–(15), 10-Minuten-Werkstattbeobachtung, Arbeitsketten und Arbeitsposen, 10-Minuten-Arbeitsbeobachtung, Szenentests Werkstatt und Werkzeugkette) | **491/491** | **491/491** |
| Ausgangsbasis v0.6.0 vor Prompt 6B | 432/432 | 432/432 |
| Start aller 6 Szenen + Testwerkstatt + Testszene Werkzeugkette (headless, je 240 Bilder) | 0 Fehler/Warnungen | 0 Fehler/Warnungen |
| Python-Tests (Importer, Importkonfiguration, Erfindungskataloge, Versionsvergleich) | **23/23** | – |
| Grafik mit Software-Rendering: 13 Bildschirmfotos (KI-Panel SIMULIERT) + 6 Werkstattbilder (Prompt 6) + Bildschirmfotos Testszene Werkzeugkette (Prompt 6B) | durchgeführt | – |
| Live-Tests mit **echtem Ollama** | **nicht ausgeführt** (nicht erreichbar) | – |
| 30-Minuten-Lauf (Prompt 4) | durchgeführt | – |

Einzelheiten: **`docs/test_results.md`**.

## Messung aus Prompt 2: 50 Vorschaufiguren
| Größe | Wert | Bedingung |
|---|---|---|
| Aufbau 50 Figuren | 257–344 ms | GDScript, Xeon 2,1 GHz |
| Netze / Kollisionsquader | 795 / 795 | |
| Voxel gesamt | 104 092 (je Figur ≈ 2 100, 2 cm) | |
| Bildzeit Mittel / schlechtestes Bild | 133 ms / 149 ms (≈ 7,5 FPS) | **Software-Rendering llvmpipe, keine GPU**, 1600×900, Schatten an |
| Draw Calls / Primitive | 3 880 / 1,14 Mio. | inkl. Schattenpass |
| Statischer Speicher | 66 MB | |

**Bewertung:** Die Zahlen gelten nur für Software-Rendering ohne Grafikkarte. Sie sagen nichts darüber, wie es auf deiner GTX 1660 Ti läuft. Daraus lässt sich **keine** Unterstützung für 1000 Wesen ableiten.

Erkennbare Engpässe für später:
- 17 Netze je Figur ergeben viele Draw Calls.
- Ungezusammengefasste Voxelflächen ergeben viele Dreiecke. Abhilfe wäre Greedy-Meshing, also gleichfarbige Flächen zusammenfassen.
- Detailstufen für weit entfernte Figuren fehlen.

Messdatei: `docs/test_reports/perf_50_figuren_llvmpipe.json`. Auf deinem PC schreibt die Vorschau die Messung nach `user://perf_50_figuren.json`.

## Offen / ungeprüft
- **Echte Ollama-Verbindung:** im Arbeitsbereich nicht erreichbar → Plan, Gespräch, 50-Wesen-Rate, Ausfall und Wiederkehr mit echtem Modell **nicht verifiziert**; Antwortzeiten, Schema-Treue und Annahmequote eines echten Modells unbekannt.
- **Modellqualität:** Ob ein kleines Modell sinnvolle Pläne liefert, ist ungeprüft; die Prüfstufen verhindern nur Unzulässiges.
- **Windows-HTTP-Weg:** der Transport wurde unter Linux gegen eine Python-Attrappe getestet.
- **Windows und echte Grafikkarte:** nicht gestartet. Alle Bildzeiten stammen aus Software-Rendering.
- **Bedienung:** Maus und Tastatur wurden nicht von Hand geprüft (Göttermenü-Klick nur über denselben Strahlaufruf).
- **Animationen** („Arme heben“, Gehen, Greifen und alle Arbeitsanimationen aus Prompt 6B): nur als Standbilder mit Software-Rendering gesehen; Geometrie (Griffpunkt, Kontaktabstand) ist durch Tests gemessen, der **Bewegungseindruck nicht**.
- **Prompt 6B, Eigenständigkeit:** Eigenständig gewählt wurde in den Messläufen nur „bauen“ (nach einer gezielt ausgelösten ersten Steinreihe). Eigenständiges Lagern und Schmelzen wurde nicht beobachtet; im normalen Spiel (ohne Testofen) gibt es kein Schmelzen.
- **Spielgefühl:** Ob die Entscheidungen „natürlich“ wirken, ist ungeprüft. Gemessen sind Regeln und Häufigkeiten.
- **Ökologie:** Nach etwa 20 Minuten ist die Nahrung aufgebraucht, dann verhungern Wesen (wie in Prompt 3).
- **Spontanes Teilen:** Es ist selten (in 10 Minuten 2 Gaben auf Bitte und 6 angenommene Angebote), weil reichlich Nahrung in der Nähe liegt.

## Manuelle Prüfschritte Prompt 6B auf deinem PC (ca. 20 Minuten)
1. **Startbildschirm → „Testszene Werkzeugkette (Testbereich)“.** Ein Testwesen steht zwischen Holzstiel, Steinkopf, Fasern, zwei großen Steinen, Kupferstücken, einem Lager (Bodenrahmen), einer Baustelle „Steinreihe“ (drei Platzmarken) und dem Testofen (Heizung, Tiegel, Form).
2. **Wesen anklicken.** Im Wesenfenster steht der Abschnitt **ARBEIT**: Ziel, laufende Handlung mit Phase, Werkzeug-ID, Zielobjekt, getragene Masse, Fortschritt, Abbruch-/Pausegrund, Herkunft.
3. **Linke Knopfspalte, oben: „… Stücke einlagern“.** Beobachten:
   - Teile werden zum Stiel getragen, der Hammer wird gebunden und bekommt eine eigene ID (steht im Wesenfenster).
   - Der Hammer sitzt **in der Hand** (nicht vor dem Körper). Beim Schlagen holt das Wesen aus, neigt sich vor, der Hammerkopf trifft den Stein; je Schlag genau ein Treffer im Ereignisprotokoll.
   - Bruchstücke liegen sichtbar da; das Wesen legt den Hammer ab, trägt das kleinere Stück mit einer Hand, das größere mit **beiden** Händen ins Lager. Die Belegung erscheint am Lager.
4. **„… Steinreihe bauen“** (danach oder in einer neuen Testszene): der große Stein wird zerschlagen, dann werden drei Steine nacheinander auf die Platzmarken gelegt; am Ende hat die Baustelle den Status „fertig“.
5. **„… Testofen → gießen“**: Kupfer wird mit dem Hammer bearbeitet (verformt, nicht zerbrochen), in den Tiegel gelegt, im Testofen geschmolzen (dauert ca. 3 Minuten Spielzeit) und in die Form gegossen.
6. **Rechte Spalte (Fehlerfälle), je in einer frischen Testszene:** fehlendes Material, blockierter Weg, fehlender Arm, zu schwer, Unterbrechung, ungeeignetes Schmelzgut, fehlende Wärmequelle. Jeder Fall muss im Wesenfenster einen **verständlichen Grund** zeigen; „Unterbrechung“ pausiert und setzt nach ca. 2 s fort.
7. **Speichern/Laden mitten in einer Kette:** F5, kurz warten, F9 → die Kette läuft beim nächsten offenen Schritt weiter (kein doppelter Schritt, kein zweiter Hammer).
8. **„Beobachtungslauf: eigenes Verhalten an/aus (autonom)“:** Danach entstehen Ketten nur noch aus eigenem Bedarf (Anzeige „autonom“). Es gibt **keine** Pflicht, dass in kurzer Zeit etwas passiert – ein Messwert, kein Fehler.
9. **Kreaturen-Werkzeug** (Startbildschirm): Knöpfe für die Arbeitsposen (Tragen, Hämmern, Zusammenfügen, Gießen …) und ein Wesen ohne Unterarm ausprobieren.
10. Bitte melde: ob die Bewegungen auf deiner Grafikkarte flüssig und glaubwürdig aussehen (bisher nur als Standbilder geprüft), ob der Hammer sichtbar in der Hand sitzt, und ob die Knöpfe/Texte lesbar sind.

## Manuelle Prüfschritte Prompt 5 auf deinem PC (ca. 20 Minuten)
1. **Ollama prüfen:** PowerShell `ollama list` und `Invoke-RestMethod http://127.0.0.1:11434/api/version`.
2. **Live-Test:** `godot --headless --path . -s res://tools/ollama_live_test.gd -- --model=<Name aus ollama list> --minutes=3` → Bericht `ollama_live_report.txt` (Pfad wird ausgegeben). Optional `--unterbrechung` (Ollama beenden/wieder starten, wenn aufgefordert).
3. **Im Spiel:** Neues Spiel → **K** → „KI-Anbindung einschalten“, „Verbindung testen“, Modell wählen, „Übernehmen + speichern“. Kopfzeile muss **ECHT – Ollama …** zeigen (nicht SIMULIERT).
4. **Plan beobachten:** ein Wesen anklicken → Entwicklermodus → „KI: Plan anfragen (Test)“. Im Wesenfenster unter MODELLVORSCHLAG: „läuft“ → „angenommen“/„abgelehnt“ mit Prüfgrund und Antwortzeit; bei Annahme die Schritte (○ ▶ ✓ ✗) und unter ENTSCHEIDUNG „Quelle: modellplan“.
5. **Gespräch beobachten:** zwei Wesen nahe beieinander, eines kennt Nahrung → „KI: Gespräch anfragen (Test)“ (oder abwarten: lokale Gespräche entstehen von selbst). **C** öffnet die Gesprächsansicht: Absicht, Herkunft (lokal/Ollama), Quelle, Sicherheit und „beim Zuhörer jetzt: …“. Beim Zuhörer unter HÖRENSAGEN den Status verfolgen (ungeprüft → bestätigt/veraltet …).
6. **Ausfall:** Ollama während des Spiels beenden → KI-Panel zeigt nach drei Fehlern „nicht erreichbar“, die Welt läuft weiter. Ollama starten → nach spätestens 15 s „verbunden“, Zähler „Wiederherstellungen“ +1.
7. **Speichern/Laden** mit aktivem Plan: F5, F9 → Plan wird neu geprüft; eine beim Speichern offene Anfrage erscheint als „beim Laden verworfen“.
8. Bitte schick mir den Live-Bericht und die Werte aus dem KI-Panel (Ø Antwortzeit, Fehlerquote, Ablehnungen nach Stufe).

## Manuelle Prüfschritte Prompt 4 auf deinem PC (ca. 20 Minuten)
1. **Startbildschirm:** „Neues Spiel“ starten. Alles aus Prompt 3 sollte weiter gehen: 50 Wesen, Uhr, Nahrung.
2. **Ein Wesen anklicken:**
   - Rechts erscheinen die farbigen Abschnitte WELTFAKT, ENTSCHEIDUNG, BEOBACHTUNG, ERINNERUNG und VERMUTUNG.
   - Unter ENTSCHEIDUNG stehen die Bewertungsbeiträge, z. B. „explore 0.21: neugier +0.21“.
3. **V (Vergleich):**
   - „Ausgewähltes als A“, dann ein anderes Wesen anklicken.
   - Beide Persönlichkeiten und die gerichteten Beziehungen stehen nebeneinander.
4. **G (Göttermenü):**
   - Ein Wesen wählen, das gerade „Arme heben“ macht (Symbol über dem Kopf, Ereignis in der Liste).
   - „als Reaktion auf ausgewähltes Ereignis“, „Nahrung schenken“, Vorschau lesen, „Eingriff ausführen“.
   - Es leuchtet, und eine Portion liegt vor dem Wesen.
5. **Wissen prüfen:**
   - Beim Wesen erscheint unter „Wahrgenommene Eingriffe“ die eigene Erklärung.
   - Ein weit entferntes Wesen weiß nichts davon (im Vergleich prüfen).
6. **Wiederholen:**
   - Das Ganze 4–6 Mal wiederholen. Unter VERMUTUNG steigen Häufigkeit und Konfidenz von „Nach eigenem „Arme heben“ …“.
   - Wenn das Wesen versorgt ist, kann es später `repeat:raise_arms` wählen.
   - Danach keine Gaben mehr geben: Die Häufigkeit sinkt wieder.
7. **Heilen:**
   - Im Entwicklermodus ein Bein verletzen, dann im Göttermenü „Verletzung heilen“: Das Wesen geht wieder schneller.
   - Ein entfernter Unterarm bleibt entfernt.
8. **Speichern und Laden:**
   - **F5**, später **F9**: Erinnerungen, Überzeugungen und Beziehungen sind wieder da.
   - Ein alter Spielstand aus v0.3.0 wird beim Laden migriert. Das Original bleibt als `…v1.vor_migration` erhalten.
9. **Geistlabor:** Im Startbildschirm „Alle (3 Startwerte)“ ausführen. Es sollte melden: alle Teilprüfungen bestanden.
10. **Leistung:** Bitte schick mir die Werte unten rechts (FPS, „Sim-Takt Ø“).
- **Prompt 6, Versuchsvorschläge eines echten Modells:** Schema-Treue und Nützlichkeit sind ungeprüft; getestet wurde nur mit dem SIMULIERTEN Testdienst.
- **Prompt 6, spontane Entdeckungen:** Die Häufigkeit ist nur aus Beobachtungsläufen (Testwerkstatt, 2 Wesen) bekannt. In der normalen 50-Wesen-Welt gibt es ohne Göttermenü keine Materialstücke und daher keine Versuche.
- **Prompt 6, Bedienung der Werkstatt:** Knöpfe, Klick auf Gegenstände und die Tasten E/W sind über Szenentests (Aufrufe) und Software-Rendering geprüft, nicht von Hand.
