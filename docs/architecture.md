# Architektur (Stand 0.6.0-prototype)

## Grundsätze
1. **Eine Quelle der Wahrheit je Größe.** Physikalische Materialeigenschaften kommen ausschließlich aus `data/materials/*.json` (MaterialRegistry). Die Excel-Materialien sind Designdaten und haben keine eigene Physik.
2. **Simulationsdaten, Darstellung, Kollision und Animation sind getrennt.**
3. **Erzeugte und handgeschriebene Daten sind getrennt:** `data/generated/excel/` (nur Importer) vs. `data/config/` und `data/materials/` (nur von Hand).
4. **Ein Excel-Eintrag aktiviert nichts.** Spielstatus steht in `data/config/implementation_status.json`.

| Größe | Quelle der Wahrheit | Darstellung | Kollision |
|---|---|---|---|
| Laborproben: Masse, Energie | `PhysicalObject` | `PhysicalBody` (Würfel/Schmelze) | Godot-RigidBody |
| Terrain | `VoxelData` (Byte je Zelle) | `VoxelChunk` (ein Netz je Chunk) | `ChunkCollision` (konkave Form aus denselben Dreiecken) |
| Wasser | `WaterSystem` (m³ je Spalte) | Wassernetz in `VoxelWorld` | keine |
| Bruchstücke | `PhysicalObject` je Material + entfernte Terrainzellen | Netz aus dem Teilgitter | konvexe Hülle (Näherung) |
| Lebensbaum, Pflanzen | `VoxelModel` + `PhysicalObject` je Material | ein Netz je Objekt | konkav aus Holzflächen (Baum), Busch/Pilz konkav, Gras/Farn keine |
| Wesen | `BodyPlan` | `CreatureView` (Gelenk + Netz je Teil) | `Area3D` + Quader je Teil |
| Animation | `CreatureAnimator` (bewegt nur vorhandene Gelenke) | – | – |
| Lebendes Wesen | `Creature` (Körperplan, Gesundheit, Stoffwechsel, Wahrnehmung, Verhalten) | `CreatureView` in `LivingWorld` | keine Godot-Physik; kinematisch über Spaltenraster (`Locomotion`) |
| Nahrung | `FoodSource` (Restmenge), `FoodItem` (Portion), `ResourceLedger` | Pflanzenmodell skaliert mit Restmenge; Kugel je Portion | – |
| Handlung | `GameAction` im `ActionExecutor` | Animation je Handlungstyp | – |
| Licht | `DayNightSystem` (aus Simulationszeit) | Sonne/Umgebung in `LivingWorld` | – |

## Ordner
```
scenes/main.tscn                       Startbildschirm
scenes/tests/physics_lab.tscn          Physiklabor (Prompt 1)
scenes/world_preview.tscn              Weltvorschau
scenes/tools/creature_preview.tscn     Kreaturenvorschau
scenes/living_world.tscn               Lebenssimulation (Neues Spiel / Laden)
scripts/core/                          Simulation, Uhr, Register, Ereignisse, Weltzustand, JSON
scripts/materials/                     MaterialDefinition, MaterialRegistry
scripts/physics/                       PhysicalObject, Wärme, Phasen, Schaden, Laboroperationen
scripts/lab/                           Laboraufbau
scripts/data/definition_db.gd          lädt data/generated/excel + data/config
scripts/world/                         voxel_palette, voxel_data, voxel_chunk, world_generator,
                                       chunk_collision, support_system, water_system, voxel_world, world_preview,
                                       world_objects (Baum/Pflanzen, gemeinsam für Vorschau und Spiel),
                                       life_context, life_simulation, living_world, population_spawner,
                                       navigation_service, day_night_system
scripts/rendering/                     voxel_mesher (Flächen + Kollisionsdreiecke), material_visuals
scripts/generation/                    voxel_model, tree_generator, plant_generator, creature_generator, creature_view
scripts/biology/                       body_plan, body_capabilities, health, metabolism, photosynthesis
scripts/actions/                       Handlungssystem (Definition, Validator, Executor, Ergebnis, Implementierungen)
scripts/agents/                        creature, perception, basic_behavior, locomotion
scripts/ecology/                       food_source, food_item, resource_ledger
scripts/persistence/                   save_manager, save_schema, save_migrations
scripts/debug/performance_monitor.gd   Leistungsanzeige
scripts/animation/creature_animator.gd Animationen
scripts/tools/creature_preview.gd      Kreaturenvorschau
scripts/ui/                            Kamera, Labor-UI, Startbildschirm, Nav-Hilfen,
                                       creature_inspector, population_panel, event_viewer
data/materials/                        Physikmaterialien (6, handgeschrieben, mit Quellen)
data/config/                           handgeschriebene Konfiguration (Welt, Palette, Wesen, Status, Zuordnung)
data/generated/excel/                  vom Importer erzeugt – nicht von Hand bearbeiten
design/                                Original-Excel (nur lesen)
tools/                                 Importer (Python), Importer-Tests, Bildschirmfoto-Werkzeuge
tests/                                 Godot-Tests (Physik, Welt, Wesen, Lebenssimulation, Szenen)
reports/import_report.md               Importbericht
docs/                                  Dokumentation, Testprotokolle, Bildschirmfotos (.gdignore)
```

## Kern (aus Prompt 1, weiterverwendet)
`Simulation` initialisiert in fester Reihenfolge: Einstellungen → Uhr → Ereignisprotokoll → Register → Materialien → Systeme → Zufall. Eine zweite Initialisierung wird ignoriert. Alle drei Bereiche haben einen eigenen `Simulation`-Knoten und nutzen dieselben Materialien, Einheiten, Entitäts-IDs und Ereignisse.

**Änderung gegenüber Prompt 1 (Grund: Wesen und Weltobjekte im selben Register):**
- `Simulation.add_entity()` registriert nicht-physikalische Entitäten (z. B. `BodyPlan`) mit eindeutiger ID.
- `ThermalSystem`, `PhaseChangeSystem` und `Simulation.total_mass()` überspringen solche Entitäten.

Alle Physiktests aus Prompt 1 bestehen weiterhin.

## Excel-Import
`tools/import_definitions.py` (Python + openpyxl) → `data/generated/excel/*.json` mit `entries` (übernommen) und `rejected` (abgewiesen, mit Zelle) + `_manifest.json` (Prüfsumme) + `_id_registry.json` (stabile IDs). Ohne `--write` wird nur geprüft und es werden Unterschiede gemeldet. `DefinitionDB` lädt die erzeugten Dateien im Spiel. Details: `docs/excel_mapping.md`.

## Voxelwelt
```
data/config/world.json + voxel_palette.json ─► WorldGenerator (Startwert) ─► VoxelData + Wasser + Pflanzenorte
VoxelWorld.set_voxel(cell, typ)
   ├─ VoxelData ändern
   ├─ betroffenen Chunk + Nachbarchunks an Grenzen als „dirty“ markieren
   ├─ WaterSystem.update_column()
   ├─ bei Entfernen: SupportSystem.check_after_removal() → ggf. _detach()
   └─ Ereignis protokollieren
VoxelWorld._process: höchstens 4 Chunks pro Bild neu bauen (Netz + Kollision)
VoxelWorld._physics_process: Wasser alle 0,1 s; Bruchstücke über Godot-Physik
```
- Karte 64×32×64 Zellen à 0,5 m = 32×16×32 m. Chunk 16×32×16 Zellen → 16 Chunks.
- `VoxelMesher` erzeugt nur Außenflächen (Fläche nur, wenn der Nachbar nicht fest ist) und liefert dieselben Dreiecke für die Kollision. Nachbarn über Chunkgrenzen werden über die Weltdaten abgefragt.
- Auswahl und Bearbeitung nutzen eine Voxel-Strahlverfolgung direkt auf `VoxelData`. Die Physik-Kollision der Chunks wird davon unabhängig aktualisiert (im Szenentest mit echter Physik-Strahlabfrage geprüft).

## Wesen
```
DefinitionDB (KR002, Farben, Genetik) + creature_defaults.json
   └─ CreatureGenerator.make_genes(Startwert)   gekoppelte Variation
        └─ build_plan()  → BodyPlan (Teile, Material, Maße, Eltern, Status)
             └─ build_view() → CreatureView (Gelenke, Netz je Teil, Area3D je Teil)
                  └─ CreatureAnimator (nur vorhandene Gelenke)
```
Körperänderungen ändern nur den `BodyPlan`. Danach baut `CreatureView.rebuild()` Darstellung, Kollision und Gelenke neu auf, und der Animator prüft, ob die laufende Animation noch möglich ist. Netze werden pro Teilform zwischengespeichert.

## Szenenwechsel
`Nav.go()` setzt vor jedem Wechsel `SceneTree.paused = false`, damit eine Pause nicht in den nächsten Bereich übernommen wird.

# Ergänzungen aus Prompt 3 – Lebenssimulation

Details: `docs/life_simulation.md` (Systeme, Annahmen, Bedienung) und `docs/save_format.md`.

## Ein Simulationspfad
`LifeSimulation` (RefCounted) enthält die gesamte Logik der Lebenssimulation. Die Szene `LivingWorld` stellt nur dar und leitet Eingaben weiter. Die Tests benutzen exakt dieselbe Klasse. Es gibt keinen zweiten, abweichenden Simulationspfad.

```
LivingWorld._physics_process(Δt fest) ─► LifeSimulation.step(Δt)
    Simulation.step ─► (Pause → 0, Ende)
    Nachbarraster · Wegsuchbudget
    ActionExecutor.step ─► MoveTo/PickUp/Eat/Drop/Wait ─► Locomotion · FoodSource.take_reserved · Metabolism.ingest
    je Wesen: Photosynthesis → Metabolism.step → Health → ggf. Creature.die
    je Wesen versetzt: Perception.scan (1 s) · BasicBehavior.decide (0,5 s) ─► ActionExecutor.request
LivingWorld._process ─► Darstellung (Position, Animation je Handlung, Restmenge, Portionen, Licht), Oberfläche alle 0,25 s
```

- **Takt:** Der Simulationsknoten tickt in der Lebenswelt nicht selbst (`set_physics_process(false)`); der Takt kommt nur über `LifeSimulation.step`. So läuft jede Größe genau einmal je Takt.
- **Pause:** `Simulation.set_paused` hält Uhr und SceneTree an. `LivingWorld`, Kamera und Oberfläche laufen mit `PROCESS_MODE_ALWAYS` weiter. Wasser und Bruchstücke (`PROCESS_MODE_PAUSABLE`) stehen.

## Wiederverwendete Systeme (keine Parallelimplementierungen)
| Bedarf | verwendet |
|---|---|
| IDs | `EntityRegistry` über `Simulation.add_entity` (neu: `ensure_next_id`, `next_id` für das Laden) |
| Zeit, Pause | `SimulationClock`, `Simulation.set_paused` |
| Material/Masse | `MaterialRegistry`, `BodyPlan.total_mass` (Prothesen über ihr Material) |
| Körper | `BodyPlan`, `CreatureGenerator`, `CreatureView`, `CreatureAnimator` |
| Gelände, Sicht | `VoxelData`, `VoxelWorld.raycast`, Signal `terrain_changed` |
| Baum, Pflanzen | `WorldObjects.spawn` (aus `world_preview.gd` herausgelöst; die Weltvorschau nutzt dieselbe Funktion) |
| Ereignisse | `EventLog` (Routineereignisse gefiltert, Länge 1000) |
| Konfiguration | `DefinitionDB.config("life")`; Startanzahl nur aus `simulation.json → initial_population` |

## Änderungen an bestehendem Code (mit Grund)
- **`world_preview.gd`:** Der Aufbau von Baum und Pflanzen steckt jetzt in `WorldObjects.spawn`. Grund: Lebenswelt und Vorschau sollen denselben Code nutzen.
- **`EntityRegistry`:** neu sind `ensure_next_id()` und `next_id()`. Grund: IDs beim Laden fortsetzen.
- **`simulation.json`:**
  - `event_log_max_entries` steigt von 300 auf 1000. Grund: 50 Wesen.
  - Hinweis zu `initial_population` aktualisiert.
- **`implementation_status.json`:** aktualisiert, danach Import mit `--write` neu erzeugt, damit `game_status` in den erzeugten Dateien stimmt. Die Excel selbst ist unverändert.
- **`main_menu.gd`:** neue Einträge „Neues Spiel“ und „Fortsetzen / Laden“ (bei beschädigtem Spielstand ggf. „Sicherung laden“); die drei Vorschaubereiche bleiben.

# Ergänzungen aus Prompt 4 – Geist, Soziales, Göttermenü

Details: `docs/mind_and_learning.md`, `docs/god_interactions.md`.

## Zuordnung der Zielmodule
| Vorschlag im Auftrag | umgesetzt in | Bemerkung |
|---|---|---|
| `scripts/mind/personality.gd` | ebenda | neu |
| `scripts/mind/observation.gd` | ebenda | neu; erzeugt von `Perception.broadcast` (bestehende Wahrnehmung erweitert, keine zweite) |
| `scripts/mind/memory_store.gd`, `belief_store.gd`, `relationship_store.gd` | ebenda | neu, je Wesen ein Objekt (`Creature.memory/beliefs/relations`) |
| `scripts/mind/learning_system.gd` | ebenda | einzige Stelle, die Beobachtungen und eigene Handlungsergebnisse in Geistesdaten umsetzt |
| `scripts/mind/goal_manager.gd`, `decision_system.gd` | ebenda | **einziger Entscheider**; `BasicBehavior.decide` entfernt, `BasicBehavior` enthält nur noch Ausführungshilfen |
| `scripts/social/social_interaction_system.gd` | ebenda | Weltseite der Bitten; die Handlungen liegen im **bestehenden** Handlungssystem (`request_food`, `offer_food`, `give_food`, `decline_request`, `raise_arms`) |
| `scripts/god/god_commands.gd`, `intervention_system.gd`, `reward_association.gd` | ebenda | neu |
| `scripts/ui/god_menu.gd` | ebenda | neu; Vergleichsansicht in `living_world.gd`, Geistanzeige in `creature_inspector.gd` |
| Testbereich | `scripts/lab/mind_scenarios.gd`, `scenes/tests/mind_lab.tscn`, `tests/test_mind.gd` | dieselben Szenarien für Tests und sichtbaren Testbereich |
| Ereignisse | **bestehendes** `EventLog` über `LifeContext.publish` | kein zweites Ereignissystem |

## Datenfluss eines Ereignisses
```
Handlung/Eingriff ──► LifeContext.publish(ev) ──► EventLog.add (Weltfakt, Spieler/Diagnose)
                                          └──► Perception.broadcast: Raster-Kandidaten → Reichweite → Sichtlinie → Qualität
                                                     └──► je Beobachter: Observation ──► LearningSystem.on_observation
                                                                                         ├─ MemoryStore.remember
                                                                                         ├─ RelationshipStore (Vertrautheit/Vertrauen)
                                                                                         ├─ BeliefStore (Hypothesen)
                                                                                         └─ RewardAssociation (nur Eingriffe)
Ende eigener Handlung ──► Creature.on_action_finished ──► LearningSystem.on_own_action (Selbstwissen)
1-s-Takt je Wesen    ──► LearningSystem.tick (ausgebliebene Folgen, Grundhäufigkeit, Verfall von Bitten)
0,5-s-Takt je Wesen  ──► DecisionSystem.decide ──► ActionExecutor.request
```

## Änderungen an bestehendem Code (mit Grund)
- **`Perception`:**
  - erfasst sichtbare Wesen: die nächsten 8, mit Sichtlinie;
  - verteilt Ereignisse (`broadcast`) – Erweiterung statt neuer Wahrnehmung.
- **`ActionExecutor`:**
  - `reserve_carried` reserviert getragene Portionen beim Anbieten und Geben;
  - fünf neue Handlungstypen.
- **Handlungen:**
  - `EatAction` verweigert reservierte Portionen;
  - `PickUpAction` bricht ab, wenn die Hände inzwischen belegt sind. Das verhindert das Überschreiben einer gerade erhaltenen Gabe; der Fehler wurde im 10-Minuten-Lauf durch die Konsistenzprüfung gefunden.
- **Körper und Darstellung:**
  - `BodyCapabilities` hat die Fähigkeit `gesture` (Oberarm, Funktion `arm`);
  - `CreatureAnimator` hat die Animation `raise_arms`.
- **`ResourceLedger`:** `god_kg` für externe Zufuhr.
- **`LifeSimulation`:** Takt um `LearningSystem.tick`, `DecisionSystem.decide`, `social.tick` und `interventions.tick` erweitert, `audit` um Geistes- und Reservierungsprüfungen.
- **Speichern:** `SaveSchema` bekommt Format 2 und `mind.json` im Fingerabdruck; `SaveMigrations` die Stufe 1→2; `SaveManager` sichert vor der Migration.
- **Startbildschirm:** zusätzlicher Eintrag „Geistlabor (Testbereich)“.


# Ergänzungen aus Prompt 5 – Ollama-Anbindung, Pläne, Gespräche

Ausführlich: `docs/ai_integration.md`, `docs/communication.md`, `docs/ollama_setup.md`.

## Zuordnung der Zielmodule
| Vorgabe | Umsetzung |
|---|---|
| `scripts/ai/ollama_client.gd` | Abfragen version/tags/ps/chat; Transport `http_transport.gd` (echt) oder `mock_ollama.gd` (SIMULIERT) |
| `scripts/ai/request_queue.gd` | Warteschlange |
| `scripts/ai/context_builder.gd` | Kontext nur aus eigenen Daten |
| `scripts/ai/response_validator.gd` | 7 Prüfstufen |
| `scripts/ai/plan_manager.gd` | Annahme, schrittweise Ausführung über `ActionExecutor`, Ergebnis |
| `scripts/ai/ai_settings.gd` | Anwendungseinstellungen |
| zusätzlich `scripts/ai/ai_service.gd` | anwendungsweiter Zustand (überlebt Laden/Neustart), Unterbrecher, Statistik |
| zusätzlich `scripts/ai/ai_system.gd` | Weltseite (`ctx.ai`), Anlässe, Sitzungsnummer |
| `scripts/social/communication_system.gd` | Gesprächsthemen aus eigenem Wissen, Äußerungen, Zustellung (`ctx.comm`) |
| `scripts/social/claim_evaluator.gd` | Hörensagen, Herkunft, Prüfung, Vertrauen |
| `scripts/ui/ai_status_panel.gd`, `conversation_viewer.gd` | KI-Panel (K), Gesprächsansicht (C) |
| `data/ai/*.json`, `data/ai/prompts/`, `data/settings/ai.json` | Schemata, Systemanweisungen, Einstellungen |

## Wiederverwendet statt dupliziert
- **Eine Entscheidungsinstanz:** `DecisionSystem` bleibt der einzige Entscheider. Modellpläne sind die Option `follow_plan`, Zielvorschläge laufen über die vorhandene Schnittstelle `GoalManager.suggest`.
- **Handlungen:** Planschritte werden ausschließlich als vorhandene Handlungen (`move_to`, `pick_up`, `eat`, `give_food`, `request_food`, `offer_food`, `wait`, `raise_arms`) oder die neue Handlung `talk` ausgeführt – mit allen bisherigen Prüfungen und Reservierungen.
- **Gespräche:** „Nahrung erbitten“ und „Hilfe anbieten“ nutzen die vorhandenen sozialen Handlungen aus Prompt 4; nur Hinweis/Erfahrung/Vermutung brauchen `talk`.
- **Vertrauen:** vorhandenes Beta-Vertrauen der `RelationshipStore` (`trust_update`).
- **Wahrnehmung:** Prüfung von Hörensagen nur über die vorhandene `Perception.scan` (`ClaimEvaluator.on_perception`).

## Datenfluss einer Modellanfrage
`DecisionSystem.decide` → `AISystem.consider` (Anlass?) → `RequestQueue` → `AISystem._dispatch_one` (`ContextBuilder` frisch) → `AIService.send_chat` → `OllamaClient`/Transport (nicht blockierend) → `AIService.poll` verteilt nach Sitzung → `AISystem._apply` (nur wenn nicht pausiert) → `ResponseValidator` (1–7) → `PlanManager.accept` → beim nächsten `decide`: Option `follow_plan` → `PlanManager.execute_next` prüft den Schritt neu → `ActionExecutor` → Ergebnis über `Creature.on_action_finished` → `PlanManager.on_action_finished`.

## Änderungen an bestehendem Code (mit Grund)
- `Creature`: Feld `ai` (Plan, Hörensagen, Wartezeiten), `ai_eligible`, Fehlschlagserie in `on_action_finished`, Abbruch bei Tod.
- `DecisionSystem`: Optionen `follow_plan`, `talk`, `check_hint`; Quelle der Entscheidung; Aufruf `consider`.
- `GoalManager.GOAL_TYPES`: `plan`, `talk`, `check_hint`.
- `LearningSystem`: markiert bedeutsame neue Erinnerungen als möglichen Anlass.
- `LifeSimulation`: erzeugt `ctx.comm`, `ctx.ai`; Takt ruft `ClaimEvaluator.on_perception` und `ctx.ai.update` (auch in der Pause, dann nur Netzwerk); `dispose` beendet die Sitzung.
- `ActionDefinition`/`ActionExecutor`: Handlung `talk` (`on_load: cancel`).
- Speichern: Format 3, Migration 2→3; Kette 1→2→3.
- `LivingWorld`: Tasten K und C, Entwicklerknöpfe „KI: … anfragen (Test)“, Pause-Abfrage des Netzwerks, `ai_service_override` für Tests.
- `mind.json`: Abschnitte `plans`, `ai_triggers`, `communication`, `hearsay`.


# Ergänzungen aus Prompt 6 – Experimente, Werkzeuge, praktisches Wissen
Fachdokumente:
- `docs/experimentation.md`;
- `docs/tools_and_construction.md`;
- `docs/practical_knowledge.md`;
- Bestandsprüfung `docs/progress_audit.md`.

## Zuordnung der Zielmodule
| Modul | Aufgabe |
|---|---|
| `scripts/technology/experiment_system.gd` | Versuche aus eigenem Wissen, Ablauf über `ActionExecutor`, Auswertung, Begrenzung (`ctx.experiments`) |
| `scripts/technology/experiment_record.gd` | Protokoll: Simulation und Wahrnehmung getrennt |
| `scripts/technology/procedural_knowledge.gd` | Verfahrenswissen je Wesen (`Creature.tech`), Stufen, Quellen, Versionen, Hypothesen |
| `scripts/technology/construction_system.gd` | Weltgegenstände: Stücke, Verbünde, Träger, Behälter, Verbinden/Lösen/Bruch, Prüfung |
| `scripts/technology/connection_definition.gd` | unterstützte Verbindungsmethoden und ihre Prüfung |
| `scripts/technology/object_evaluator.gd` | funktionale Bewertung als Schlagwerkzeug (ohne Namen) |
| `scripts/technology/tool_use_system.gd` | Greifen, Halten, Schwung, Schlag, Temperaturkategorien, Verbrennung, Heizung |
| zusätzlich `assembly.gd`, `test_heater.gd` | Datenklassen Verbund, Testheizung |
| `scripts/social/teaching_system.gd` | Erklären, Vorführung anbieten/beobachten, Üben |
| `scripts/ui/experiment_inspector.gd`, `knowledge_viewer.gd` | Versuchs-/Gegenstandsansicht (E), Wissensansicht (W) |
| `scripts/lab/test_workshop.gd` | getrennte Testwerkstatt mit Testausrüstung |
| `scripts/generation/object_generator.gd` | Voxelmodelle der Gegenstände aus den Daten |
| `scripts/actions/implementations/*` | 10 neue Handlungen + `tech_action_util.gd` |

## Wiederverwendet statt dupliziert
- **Physik:** Materialstücke sind `PhysicalObject`. Es gelten dieselbe Wärmebilanz (`ThermalSystem`), dasselbe Phasenmodell (`PhaseChangeSystem`) und dieselbe Bruchaufteilung (`DamageSystem.fragment_shares`). Die Bearbeitung erweitert `MaterialProcessSystem`.
- **Ein Entscheider:** Versuche, Unterricht und Üben sind Optionen `tech:*` in `DecisionSystem`. Wählt ein Wesen etwas anderes, endet ein laufender Versuch.
- **Eine Handlungsausführung:** Versuchsschritte und Modellvorschläge laufen nur über `ActionExecutor`. `dry_run` prüft ohne Seiteneffekte; der Validator nutzt es für jeden Modellschritt.
- **Wahrnehmung:** Gegenstände über den Wahrnehmungstakt (`ExperimentSystem.perceive_objects`, Sichtlinie wie `Perception`). Vorführungen und Schläge sind Ereignisse über das vorhandene `publish` → Beobachtung → `LearningSystem` → `TeachingSystem.on_observation`.
- **Gespräche:** neue Absichten im vorhandenen `CommunicationSystem`; Hörensagen mit Ursprung wie in Prompt 5.
- **Göttermenü:** vorhandener Eingriff „Material platzieren“, erweitert um Formen und Pflanzenfasern.
- **Lebenssimulation:** Die Testwerkstatt nutzt denselben `LifeSimulation`-Pfad (`new_workshop`) und dieselbe Spielszene (`LivingWorld`, Modus `workshop`).

## Datenfluss eines Versuchs
`DecisionSystem.decide` → Option `tech:start` (aus `ExperimentSystem.candidates`) → `ExperimentSystem.start` (Protokoll, Ausgangslage) → `advance`: `dry_run` → ggf. `move_to`/`drop` → `ActionExecutor.request` → Handlung (z. B. `deform_material` → `ToolUseSystem.strike` → `MaterialProcessSystem.work_piece`) → `Creature.on_action_finished` → `ExperimentSystem.on_action_finished` → nächster Schritt … → `_evaluate` (Wahrnehmungsschwellen) → `ProceduralKnowledge.record_own` → Ereignis für Beobachter.

## Änderungen an bestehendem Code (mit Grund)
- `MaterialPiece`: erbt `PhysicalObject` statt `RefCounted` (Wärme, Phase, Form, Verformung). Alte Felder bleiben, `from_dict` liest auch Format 3.
- `MaterialDefinition`/`MaterialRegistry`: optionaler Abschnitt `working`.
- `ThermalSystem`: Körperenergie als Bilanzposten, `add_contact_g`, `remove_contact`, `remove_heater`, `transfer_to_body`.
- `DamageSystem`: Bruchaufteilung als statische Funktion herausgelöst (Verhalten unverändert, Tests bestehen).
- `Creature`: `held_object_id`, `tech`; Tod bricht den Versuch ab und lässt den Gegenstand fallen (das Wissen geht nicht über).
- `pick_up`/`drop`: freie Hand prüfen bzw. gehaltenen Gegenstand ablegen.
- `ActionExecutor`: `dry_run`, 10 Handlungen.
- `LifeContext`/`LifeSimulation`: `assemblies`, `heaters`, `experiments`, `tech_cfg`; Takt mit `ToolUseSystem.tick`, Gegenstandswahrnehmung, `experiments.tick`; `new_workshop`.
- `ContextBuilder`/`ResponseValidator`/`AISystem`/`MockOllama`: Art `experiment`.
- `CommunicationSystem`: Absichten `explain_procedure`, `offer_demo`.
- `GodCommands`/`InterventionSystem`/`god_menu.gd`: Formen, Pflanzenfasern.
- `LivingWorld`/`main_menu.gd`: Modus Testwerkstatt, Gegenstandsdarstellung, Auswahl per Klick, Tasten E/W.
- Speichern: Format 4, Migration 3→4; Kette 1→2→3→4.

---

# Prompt 6B – Arbeitsposen und Werkzeug-/Materialkette (v0.6.1)

## Zuordnung der Zielmodule
| Modul | Aufgabe |
|---|---|
| `scripts/animation/work_pose.gd` | Geometrie der Arbeitsbewegung aus Körperplan und gehaltenem Werkzeug (Schulter, Arm bis Handgelenk, Griff, Griffwinkel 45°, Kopfabstand); Kontaktpose (Arm-/Werkzeugwinkel, Rumpfneigung, Hocke), Standpunkt, Körper↔Welt, Werkzeugrahmen |
| `scripts/animation/creature_animator.gd` | antriebsgesteuerte Arbeitsposen aus `a.state["anim"]` (nur lesend), Zweihand-/Einarmprüfung, vorbereitete abgewiesene Posen, weiches Zurückblenden, Vorführung ohne Handlung, `grip_frame` |
| `scripts/actions/work_motion.gd` | Phasen approach → prepare → work/contact → recover, Anlauf mit Voxelprüfung, Animationsangabe, Händeprüfung |
| `scripts/technology/work_chain.gd`, `work_system.gd` | Arbeitsketten (`ctx.work`): Planung, Bedarf, Optionen, Ausführung, Rückmeldungen, Anzeige, Modellvorschläge, Speichern |
| `scripts/settlement/storage_place.gd`, `storage_system.gd` | reale Lagerplätze (`ctx.storages`) |
| `scripts/settlement/structure.gd`, `structure_system.gd` | Baustellen/Einzelbauwerke (`ctx.structures`), Bauplan Steinreihe |
| `scripts/actions/implementations/deposit_in_storage_action.gd`, `place_building_part_action.gd`, `put_into_container_action.gd` | 3 neue Handlungen |
| `scripts/lab/work_chain_scene.gd` | Testszene Werkzeugkette (Modus `werkzeugkette` in `LivingWorld`) |
| `data/ai/work_schema.json`, `data/ai/prompts/work_system.txt`, `ResponseValidator.validate_work` | Anfrageart `work` (nur geprüfter Vorschlag) |
| `design/import_config/datenbasis_korrekturen.json`, `tools/import_inventions_real.py`, `data/config/inventions_activated.json` | Excel-Abgleich: Korrekturen, Erfindungskatalog, aktivierte Definitionen |

## Wiederverwendet statt dupliziert
- **Ein Entscheider:** Arbeitsketten sind Optionen `work:start` / `work:continue` / `work:model` im `DecisionSystem`. Andere Ziele pausieren eine Kette (nicht abbrechen). Gezielt ausgelöste Ketten (Testszene) treibt `WorkSystem.tick` nur bei Wesen mit abgeschaltetem Verhalten – wie beim Versuchssystem.
- **Eine Handlungsausführung:** jeder Kettenschritt ist eine normale Handlung über `ActionExecutor` (`dry_run` vor dem Anfordern). Schlag, Bruch und Gießen nutzen die vorhandenen `ToolUseSystem.strike`, `MaterialProcessSystem.work_piece/fracture_piece/pour`.
- **Eine Geometrie:** `WorkPose` bestimmt Standpunkt (Handlung) und Gelenkwinkel (Animation). Die Darstellung setzt gehaltene Gegenstände an den Griffrahmen der animierten Hand.
- **Wahrnehmung:** Lager und Baustellen über den Wahrnehmungstakt (`StorageSystem.perceive`, `StructureSystem.perceive`) in dasselbe `cr.tech.objects`.
- **Wissen:** Ergebnisse über `ProceduralKnowledge.record_own` (Schlüssel `lagern:stone`, `bauen:steinreihe:stone`, vorhandene Verbinde-/Schlag-/Gießschlüssel).

## Datenfluss einer Arbeitskette
Bedarf (`WorkSystem.needs`) → `DecisionSystem` wählt `work:start` → `WorkSystem.plan` → `start` → `advance` → `_step` (zustandsbasiert: erledigt? sonst Teilhandlung) → `_request_with_prep` (`dry_run`, ggf. `move_to`/`drop`) → `ActionExecutor.request` → Handlung (z. B. `deform_material` mit Anlauf, Ausholen, genau einem Kontakt je Schlag) → `Creature.on_action_finished` → `WorkSystem.on_action_finished` (Werkzeug-ID, Bruchstücke, Gießen) → nächster Schritt … → `_check` (messen, Wissen verbuchen) → `_finish`. Darstellung: `LivingWorld._sync_views` liest `a.state.anim`, `CreatureAnimator` setzt Gelenke, `_place_held` setzt den Gegenstand an den Griffpunkt.

## Änderungen an bestehendem Code (mit Grund)
- `Creature`: `hold_mode` ("" / "one" / "two"), `hold_side`; Tod bricht die Arbeitskette ab.
- `MaterialPiece`: `storage_id`, `structure_id`; `is_free()` berücksichtigt Verbautes.
- `ToolUseSystem`: Zweihandtragen (`check_carry`, `carry_limit_two_kg`, `carry_two_max_width_m`), `release_at`, verbaute Stücke nicht greifbar, Heizung prüft Schmelzeignung.
- `MaterialProcessSystem`: `melt_support` (Schmelzen ist keine Recyclingaktion), `merge_melts` (gleichartige Schmelzen vereinigen sich vor dem Gießen; Masse/Energie exakt), Bruch überträgt Testausrüstung/Behälter/Verlauf.
- `tech_action_util.strike_series`, `equip_tool`, `drop`, `connect_parts` (einarmige Variante), `place_in_heater`, `pour_into_mold`: Bewegungsphasen und Animationsangaben; Wirkung weiterhin genau einmal in der Handlung.
- `LifeSimulation.after_body_change`: prüft auch die haltende Seite bzw. die zweite Hand beim Zweihandtragen.
- `LivingWorld`: Animation aus `a.state.anim`, gehaltene Gegenstände am Griffpunkt, Lager/Baustellen, Arbeitsanzeige, Modus und Bedienfeld Werkzeugkette.
- `CreatureInspector`: Abschnitt ARBEIT; Gegenstände/Lager/Bauwerke als Zielobjekt lesbar.
- `ContextBuilder`/`ResponseValidator`/`AISystem`/`MockOllama`: Art `work`.
- `tools/import_definitions.py`: liest die Importkonfiguration.
- Speichern: Format 5 (Lager, Bauwerke, Arbeitsketten, Haltemodus), Migration 4→5; Kette 1→2→3→4→5.
