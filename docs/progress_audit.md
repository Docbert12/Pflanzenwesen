# Bestandsprüfung (Prompt 6)

Diese Prüfung stützt sich auf den **Code und ausgeführte Tests**, nicht auf Dokumentationsbehauptungen.
Statuswerte: **getestet** (automatischer Test besteht) · **implementiert, ungeprüft** (Code vorhanden, kein Test) · **teilweise** · **fehlend**.

## A. Ausgangsstand v0.5.1 (vor jeder Änderung geprüft)

Ausgangsbasis am 22.11.2026 bestätigt: `git` Stand `2937682` (= v0.5.1 + Doku-Nachtrag), `godot --headless --path . --import`, dann `tests/run_tests.gd`:
**354 von 354 bestanden auf Godot 4.7.2 und auf Godot 4.5** (Berichte `docs/test_reports/test_run_godot_4.7.2.txt`, `…_4.5.txt` aus v0.5.1). Python-Importertests 17/17.

| Funktion | Dateien | Status | Evidenz / Prüfverfahren | Blockierend für Prompt 6 |
|---|---|---|---|---|
| Materialphysik (Dichte, Wärmekapazität, Leitfähigkeit, Phasen, Bruch) | `scripts/physics/*`, `scripts/materials/*`, `data/materials/*.json` (6 Materialien) | getestet | Physiklabor-Tests: Energieerhaltung, Phasenwechsel mit latenter Wärme, Bruch mit Massenerhalt | Keine Bearbeitungskennwerte (Härte, Fließspannung, Verfestigung); kein Fasermaterial, kein Tiegelmaterial |
| Wärme: Kontakte, Heizungen, Senken, Bilanz | `thermal_system.gd` | getestet | Ledger-Bilanz geschlossen im Physiklabor | Kontakte nur über Fläche (kein Leitwert); **keine Wärmeübertragung auf Körper** (Verbrennungen nicht bilanzierbar) |
| Materialstücke in der Lebenswelt | `scripts/ecology/material_piece.gd` | teilweise | Göttermenü-Test: Würfel erscheint, Masse = Dichte × Volumen | **War `RefCounted` ohne Temperatur, Form, Maße**; nahm nicht an Wärme/Phasen teil; Wesen konnten es sehen, nicht benutzen |
| Veränderbare Voxelwelt | `scripts/world/voxel_*`, `support_system.gd`, `water_system.gd` | getestet | Flächenzählung, Kollision, Wasser- und Abstützungsbilanz | – |
| Körpergenerator und Körperfähigkeiten | `body_plan.gd`, `creature_generator.gd`, `creature.gd` (`caps`) | getestet | Generator- und Fähigkeitstests, Unterarm entfernen, Prothesen | Körper hatte keine Armlänge/Handmasse für einen Schwung; Greifen nur für Nahrung |
| Lebenssimulation 50 Wesen | `life_simulation.gd`, `life_context.gd` | getestet | 600-s-Dauerlauf, Audit leer, Stoffwechselbilanz | – |
| Handlungssystem, Reservierungen | `scripts/actions/*` (11 Typen) | getestet | Tests (4), (8), (9): Zustände, Abbruch, Reservierungen ohne Besitzer | Keine Handlungen für Gegenstände (untersuchen, ausrüsten, schlagen, verbinden, heizen, gießen, vorführen, üben); `pick_up` nur Nahrung |
| Erinnerungen, Lernen, Beziehungen | `scripts/mind/*` | getestet | Szenarien A–G, Beta-Überzeugungen, Vertrauen | Kein Verfahrenswissen (nur Überzeugungen über Ereignisse/Handlungen) |
| Entscheidung | `decision_system.gd` (einziger Entscheider) | getestet | Entscheidungsprotokoll je Wesen | Keine Optionen für Versuche/Unterricht |
| Göttermenü | `scripts/god/*`, `scripts/ui/god_menu.gd` | getestet | Szene + Logik, Material platzieren | Nur Würfelform; keine Fasern, keine Stäbe |
| Ollama-Anbindung, Antwortvalidierung | `scripts/ai/*` | **teilweise** | Getestet **nur** gegen SIMULIERTEN Testdienst und HTTP-Attrappe; echtes Ollama im Arbeitsbereich nicht erreichbar | Kein Schema für Versuchsvorschläge |
| Gespräche und Wissensquellen (Hörensagen) | `scripts/social/communication_system.gd` | getestet | Hörensagen mit Quelle, unabhängige Ursprünge | Keine Absicht „Verfahren erklären“/„Vorführung anbieten“ |
| Speichern/Laden | `scripts/persistence/*` (Format 3, Migration 1→2→3) | getestet | Rundlauf, echte Prüflinge v1/v2, beschädigte Dateien | Keine Wärmezustände von Stücken, keine Verbünde, kein Verfahrenswissen |
| Excel-Gegenstände I001 Steinbeil, I003 Holzspeer | `data/generated/excel/items.json` | fehlend (nur Daten) | `implementation_status.json` | Bleiben **Daten ohne Wirkung** (keine Freischaltung) |

## B. Behobene Grundlagen (für diesen Auftrag nötig, ohne Parallelsysteme)

| Grundlage | Umsetzung | Status | Evidenz |
|---|---|---|---|
| Materialstück als physikalisches Objekt | `MaterialPiece extends PhysicalObject` (Masse und Wärmeenergie als Quelle der Wahrheit, Form, Maße, Hohlraum, Behälter, Träger, Verbund, Verformung, Verschleiß) | getestet | Technik-Tests (3)(6)(8)(14) |
| Bearbeitungskennwerte | optionaler Abschnitt `working` in Materialdateien (Härte, Fließspannung, Verfestigung, Grenze der Kaltverformung, Bindeenergie) | getestet | Registry-Prüfung, (6) |
| Pflanzenfasern, Keramik | `data/materials/plant_fiber.json`, `ceramic.json` – nur Testwerkstatt / Göttermenü | getestet | (3), (15) |
| Wärme auf Körper, Leitwert-Kontakte | `ThermalSystem.transfer_to_body`, `add_contact_g`, Bilanzposten `body_j` | getestet | (8) Bilanz, (9) Verbrennung |
| Gegenstand halten | `Creature.held_object_id` (getrennt von Nahrung `carried_item_id`) | getestet | (2)(9)(14) |
| Bruchanteile wiederverwendbar | `DamageSystem.fragment_shares` | getestet | (5) Steinbruch |

## C. Stand v0.6.0 (Prompt 6)

| Funktion | Dateien | Status | Evidenz |
|---|---|---|---|
| Gegenstand als Werkzeug (Stein) | `tool_use_system.gd`, `equip_tool_action.gd`, `strike_target_action.gd`, `deform_material_action.gd` | getestet | (2): Stein ε 0,037 nach 16 Schlägen; bloße Hand 0,008 und Handschaden |
| Stiel + Kopf verbinden (Umwickeln mit Fasern) | `construction_system.gd`, `connection_definition.gd`, `connect_parts_action.gd` | getestet | (3): Masse exakt erhalten, Fasern Teil des Verbunds, falsches Bindemittel/Methode abgewiesen |
| Werkzeug praktisch testen | Versuch 3, `object_evaluator.gd` | getestet | (1), (4), Versuch 3 in (14) |
| Funktionale Bewertung ohne Namen | `object_evaluator.gd` | getestet | (1): „Hammer“ = „Unbenannt“, Zerfall des weichen Kopfes vorhergesagt und eingetreten |
| Verbindung versagt bei Überlast | `tool_use_system.gd` (Rückprall), `ConstructionSystem.dissolve` | getestet | (4)(5): Bruch beim 1. Schlag, alle Teile genau einmal, Fasern zerrissen |
| Kaltverformung Kupfer, Verfestigung, Risse | `material_process_system.gd` (`work_piece`, `flow_stress_pa`) | getestet | (6): Δε = W/(σ·V) exakt; Risse jenseits ε 1,6 |
| Heizen und Gießen mit Testheizung | `test_heater.gd`, `place_in_heater_action.gd`, `pour_into_mold_action.gd`, `MaterialProcessSystem.pour` | getestet | (7)(8): 40 W schmilzt nicht; Masse/Energie beim Gießen exakt; Gesamtbilanz geschlossen; Guss erstarrt |
| Heiße Gegenstände | `ToolUseSystem.touch_burn`, `check_grasp`, Reflex in `tick` | getestet | (9) |
| Abbruch erhält Zwischenstand | alle Technik-Handlungen | getestet | (10) |
| Versuchsprotokoll (Simulation ↔ Wahrnehmung getrennt) | `experiment_record.gd`, `experiment_system.gd` | getestet | (2)(11)(14) |
| Eigenständige Versuche, begrenzt | `ExperimentSystem.options/blocked_reason`, `DecisionSystem` | getestet (Beobachtungslauf, Messwert) | Beobachtungslauf: Budget eingehalten, Wesen essen, Audit leer; 30-min-Lauf `tools/observe_workshop.gd`: Wesen verbinden von selbst (Messwert, keine Pflicht) |
| Teile zusammentragen vor dem Verbinden | `ExperimentSystem._gather_steps/_advance_bring` | getestet | Technik (3b) |
| Modellvorschläge als Hypothese | `response_validator.gd` (`validate_experiment`), `ai_system.gd`, `experiment_schema.json` | getestet **nur mit SIMULIERTEM Testdienst** | (11); **echte Ollama-Verbindung ungeprüft** |
| Verfahrenswissen mit Stufen | `procedural_knowledge.gd` | getestet | (12)(13) |
| Erklären, Vorführen, Zusehen, Üben | `teaching_system.gd`, `communication_system.gd`, `demonstrate_procedure_action.gd`, `practice_procedure_action.gd` | getestet | (13) |
| Wissen individuell, kein Übergang beim Tod | `creature.gd` (`die`), `procedural_knowledge.gd` | getestet | (12) |
| Testwerkstatt getrennt vom Spiel | `scripts/lab/test_workshop.gd`, Startmenü „Testwerkstatt“ | getestet | (15), Szenentest Werkstatt |
| Sichtbare Modelle (Teile, Verbindungen, Formänderung, Bruch, Guss, Halten) | `scripts/generation/object_generator.gd`, `living_world.gd` | getestet (Zuordnung Daten → Modell im Szenentest); Aussehen nur per Bildschirmfoto mit Software-Rendering | Szenentest Werkstatt |
| Oberflächen: Versuch, Gegenstand, Wissen | `scripts/ui/experiment_inspector.gd`, `knowledge_viewer.gd` | getestet (Inhalt, Kennzeichnung) | Szenentest Werkstatt; **Bedienung von Hand ungeprüft** |
| Speicherformat 4 + Migration 3→4 | `save_schema.gd`, `save_manager.gd`, `save_migrations.gd`, Prüfling `tests/fixtures/save_v3_prompt05.json` | getestet | (14), echter v0.5.1-Spielstand |

## D. Verbleibende Grenzen
- **Echte Ollama-Verbindung** für Versuchsvorschläge ungeprüft (wie in Prompt 5).
- Nur **ein** Werkzeugtyp (Schlagwerkzeug), **eine** Verbindungsmethode für Wesen (Umwickeln), **ein** Gießvorgang (Tiegel → offene Form).
- Zusammentragen nur für das Verbinden: Kopf und Fasern werden einzeln zum Stiel getragen (aufnehmen → gehen → ablegen). Für Schlagen, Heizen und Gießen gibt es das nicht; liegen die Gegenstände dort zu weit auseinander, schlägt der Schritt nach 3 Annäherungen fehl.
- Griff und Teile haben je **eine** Temperatur (keine Temperaturverteilung entlang des Stiels).
- Keine Schmelzströmung; Gießen = Masse wechselt vollständig in die Form.
- Fasern gibt es nur in der Testwerkstatt und über das Göttermenü (keine Landwirtschaft).
