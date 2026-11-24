# Versionsvergleich `git:origin/version/v0.5.1` → `.`

Dateien: **49 neu**, **0 entfernt**, **57 geändert** · Testprüfungen (Texte): 333 → 411

## Entfernt (bitte jede Zeile begründen)
- Testprüfung: „Migration: ausgelieferte Definitionen v0.5.0 entsprechen dem eingetragenen Fingerabdruck“
- Testprüfung: „Migrationsschnittstelle: aktuelles Format ohne Migration; nur die tatsächlich vorhandenen Stufen 1→2→3“

## Neu
- `data/ai/experiment_schema.json`
- `data/ai/prompts/experiment_system.txt`
- `data/config/technology.json`
- `data/materials/ceramic.json`
- `data/materials/plant_fiber.json`
- `design/prompts/prompt_06_experimente_werkzeuge_wissen.txt`
- `docs/experimentation.md`
- `docs/practical_knowledge.md`
- `docs/progress_audit.md`
- `docs/screenshots/screenshot_werkstatt_1_ausruestung.png`
- `docs/screenshots/screenshot_werkstatt_2_werkzeug_in_der_hand.png`
- `docs/screenshots/screenshot_werkstatt_3_verformte_probe_und_versuchsansicht.png`
- `docs/screenshots/screenshot_werkstatt_4_wissensansicht.png`
- `docs/screenshots/screenshot_werkstatt_5_schmelze_im_tiegel.png`
- `docs/screenshots/screenshot_werkstatt_6_guss_in_der_form.png`
- `docs/test_reports/werkstatt_beobachtung_1800s.txt`
- `docs/tools_and_construction.md`
- `reports/versionsvergleiche/versionsvergleich_v0.5.1_zu_v0.6.0.md`
- `scripts/actions/implementations/connect_parts_action.gd`
- `scripts/actions/implementations/deform_material_action.gd`
- `scripts/actions/implementations/demonstrate_procedure_action.gd`
- `scripts/actions/implementations/disconnect_parts_action.gd`
- `scripts/actions/implementations/equip_tool_action.gd`
- `scripts/actions/implementations/inspect_object_action.gd`
- `scripts/actions/implementations/place_in_heater_action.gd`
- `scripts/actions/implementations/pour_into_mold_action.gd`
- `scripts/actions/implementations/practice_procedure_action.gd`
- `scripts/actions/implementations/strike_target_action.gd`
- `scripts/actions/implementations/tech_action_util.gd`
- `scripts/generation/object_generator.gd`
- `scripts/lab/test_workshop.gd`
- `scripts/social/teaching_system.gd`
- `scripts/technology/assembly.gd`
- `scripts/technology/connection_definition.gd`
- `scripts/technology/construction_system.gd`
- `scripts/technology/experiment_record.gd`
- `scripts/technology/experiment_system.gd`
- `scripts/technology/object_evaluator.gd`
- `scripts/technology/procedural_knowledge.gd`
- `scripts/technology/test_heater.gd`
- `scripts/technology/tool_use_system.gd`
- `scripts/ui/experiment_inspector.gd`
- `scripts/ui/knowledge_viewer.gd`
- `tests/fixtures/save_v3_prompt05.json`
- `tests/test_technology.gd`
- `tools/capture_workshop.gd`
- `tools/check_scripts.gd`
- `tools/observe_workshop.gd`
- `tools/run_tech_tests.gd`

## Geändert
- `CHANGELOG.md`
- `README.md`
- `data/ai/conversation_schema.json`
- `data/config/implementation_status.json`
- `data/config/mind.json`
- `data/materials/copper.json`
- `data/materials/plant_tissue.json`
- `data/materials/soil.json`
- `data/materials/stone.json`
- `data/materials/water.json`
- `data/materials/wood.json`
- `docs/HANDOVER.md`
- `docs/architecture.md`
- `docs/god_interactions.md`
- `docs/implementation_status.md`
- `docs/save_format.md`
- `docs/test_reports/test_run_godot_4.5.txt`
- `docs/test_reports/test_run_godot_4.7.2.txt`
- `docs/test_results.md`
- `project.godot`
- `scripts/actions/action_definition.gd`
- `scripts/actions/action_executor.gd`
- `scripts/actions/implementations/drop_action.gd`
- `scripts/actions/implementations/pick_up_action.gd`
- `scripts/agents/creature.gd`
- `scripts/ai/ai_system.gd`
- `scripts/ai/context_builder.gd`
- `scripts/ai/mock_ollama.gd`
- `scripts/ai/response_validator.gd`
- `scripts/ecology/material_piece.gd`
- `scripts/god/god_commands.gd`
- `scripts/god/intervention_system.gd`
- `scripts/materials/material_definition.gd`
- `scripts/materials/material_registry.gd`
- `scripts/mind/decision_system.gd`
- `scripts/mind/learning_system.gd`
- `scripts/persistence/save_manager.gd`
- `scripts/persistence/save_migrations.gd`
- `scripts/persistence/save_schema.gd`
- `scripts/physics/damage_system.gd`
- `scripts/physics/material_process_system.gd`
- `scripts/physics/thermal_system.gd`
- `scripts/social/communication_system.gd`
- `scripts/ui/creature_inspector.gd`
- `scripts/ui/god_menu.gd`
- `scripts/ui/main_menu.gd`
- `scripts/world/life_context.gd`
- `scripts/world/life_simulation.gd`
- `scripts/world/living_world.gd`
- `tests/run_tests.gd`
- `tests/test_ai.gd`
- `tests/test_life.gd`
- `tests/test_mind.gd`
- `tests/test_suite.gd`
- `tests/test_world.gd`
- `tools/make_save_fixture.gd`
- `tools/scene_smoke.gd`

- `tools/scene_smoke.gd`

## Begründung der Einträge unter „Entfernt“
Beide Prüfungen wurden **umbenannt und angepasst**, nicht gestrichen (siehe CHANGELOG 0.6.0, „Entfernt/Geändert“):
- „Migration: ausgelieferte Definitionen v0.5.0 …“ heißt jetzt „Migration: ausgelieferte Definitionen v0.6.0 …“ und vergleicht mit `V4_SHIPPED_DEFINITIONS`. Die aktuellen Definitionen sind absichtlich nicht mehr die von v0.5.0 (neue Materialien, `technology.json`). Der v0.5.0-Fingerabdruck wird weiter geprüft: durch die Migration des echten v0.5.1-Spielstands und durch die Kette 2→3.
- „Migrationsschnittstelle: … Stufen 1→2→3“ heißt jetzt „… Stufen 1→2→3→4“ und erwartet die Stufen [1, 2, 3], weil die Stufe 3→4 neu ist.
