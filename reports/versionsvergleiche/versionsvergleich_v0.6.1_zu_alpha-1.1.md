# Versionsvergleich `git:origin/main` → `.`

Dateien: **36 neu**, **0 entfernt**, **21 geändert** · Testprüfungen (Texte): 467 → 532

## Entfernt (bitte jede Zeile begründen)
- Funktionen in `scripts/persistence/save_manager.gd`: `_rng`, `_set_rng`, `_sorted`
- Testprüfung: „Migrationsschnittstelle: aktuelles Format ohne Migration; nur die tatsächlich vorhandenen Stufen 1→2→3→4→5“

## Neu
- `data/maps/lichtung.json`
- `data/maps/pruefkarte_schmal.json`
- `docs/plan_alpha_1_1.md`
- `docs/world_expansion.md`
- `export_presets.cfg`
- `scripts/core/module_registry.gd`
- `scripts/core/rng_streams.gd`
- `scripts/core/sim_module.gd`
- `scripts/modules/actions_module.gd`
- `scripts/modules/actors_module.gd`
- `scripts/modules/communication_module.gd`
- `scripts/modules/core_module.gd`
- `scripts/modules/decision_module.gd`
- `scripts/modules/food_module.gd`
- `scripts/modules/god_module.gd`
- `scripts/modules/life_module.gd`
- `scripts/modules/perception_module.gd`
- `scripts/modules/settlement_module.gd`
- `scripts/modules/social_module.gd`
- `scripts/modules/tech_perception_module.gd`
- `scripts/modules/technology_module.gd`
- `scripts/modules/time_module.gd`
- `scripts/modules/tool_use_module.gd`
- `scripts/modules/work_module.gd`
- `scripts/ui/main_menu_version.gd`
- `scripts/world/map_template.gd`
- `scripts/world/region_store.gd`
- `scripts/world/world_access.gd`
- `tests/fixtures/save_v5_v061.json`
- `tests/fixtures/save_v5_v061_werkstatt.json`
- `tests/fixtures/save_v5_v061_werkzeugkette.json`
- `tests/test_modules.gd`
- `tools/benchmark_world.gd`
- `tools/make_work_chain_fixture.gd`
- `tools/run_module_tests.gd`
- `tools/state_hash.gd`

## Geändert
- `CHANGELOG.md`
- `README.md`
- `docs/architecture.md`
- `docs/save_format.md`
- `project.godot`
- `scripts/agents/perception.gd`
- `scripts/debug/performance_monitor.gd`
- `scripts/god/god_commands.gd`
- `scripts/lab/mind_scenarios.gd`
- `scripts/persistence/save_manager.gd`
- `scripts/persistence/save_migrations.gd`
- `scripts/persistence/save_schema.gd`
- `scripts/settlement/structure_system.gd`
- `scripts/ui/main_menu.gd`
- `scripts/world/life_context.gd`
- `scripts/world/life_simulation.gd`
- `scripts/world/living_world.gd`
- `scripts/world/voxel_world.gd`
- `tests/run_tests.gd`
- `tests/test_life.gd`
- `tests/test_mind.gd`
