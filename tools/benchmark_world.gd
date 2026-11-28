extends SceneTree
## Vermessung der Welt (Alpha 1.1, Zusatz Weltarchitektur §2): misst Karten- und Chunkgröße, Dauer von
## Erzeugung, Netzen und Kollision, Navigationskosten, Simulationszeit je Modul, Speicher, Objektzahlen
## und Spielstandgröße. Schreibt einen Bericht nach user://benchmark_report.txt und auf die Konsole.
##   godot --headless --path . -s res://tools/benchmark_world.gd -- [--map=lichtung] [--secs=120] [--seed=N]
## Ohne --headless läuft dieselbe Messung mit Grafikkarte (Bildzeiten kommen ab Alpha 1.2 aus der Messszene).
## Es wird nur gemessen – nichts an der Simulation verändert.

const DT := 1.0 / 60.0


func _initialize() -> void:
	create_timer(3000.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var map_id := MapTemplate.DEFAULT_ID
	var secs := 120.0
	var seed_v := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = a.substr(6)
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a.begins_with("--seed="):
			seed_v = int(a.substr(7))
	var lines: Array = []
	var db := DefinitionDB.new()
	db.load_all()
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	root.add_child(sim)
	root.add_child(world)
	root.add_child(objs)
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	var life := LifeSimulation.new()
	if not life.setup(sim, db, world, objs, AIService.disabled()):
		printerr(life.errors)
		quit(1)
		return
	var tmpl := MapTemplate.load_id(map_id)
	if not tmpl.errors.is_empty():
		printerr(tmpl.errors)
		quit(1)
		return
	if seed_v < 0:
		seed_v = tmpl.default_seed
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var t0 := Time.get_ticks_usec()
	var r := life.new_game(seed_v, map_id)
	var t_new := (Time.get_ticks_usec() - t0) / 1000.0
	if not r.get("ok", false):
		printerr(r)
		quit(1)
		return
	var ter := life.ctx.terrain
	var size := ter.size_cells()
	var cd := world.chunk_dims
	lines.append("Pflanzenwesen – Vermessung der Welt")
	lines.append("Version %s · Godot %s · %s · %s · %d Prozessorkerne · %s" % [str(ProjectSettings.get_setting("application/config/version")), Engine.get_version_info()["string"], OS.get_name(),
		Time.get_datetime_string_from_system(), OS.get_processor_count(), "ohne Grafik (headless)" if DisplayServer.get_name() == "headless" else "mit Grafik: " + RenderingServer.get_video_adapter_name()])
	lines.append("")
	lines.append("Karte: %s (%s), Startwert %d, Generator %s Version %d" % [tmpl.name, tmpl.id, seed_v, tmpl.generator, tmpl.generator_version])
	lines.append("  Größe: %d × %d × %d Zellen à %.2f m = %.0f × %.0f × %.0f m; Fläche %.0f m²; %d Zellen (%.1f MB als Byte je Zelle)" % [size.x, size.y, size.z, ter.cell_size(), size.x * ter.cell_size(),
		size.y * ter.cell_size(), size.z * ter.cell_size(), size.x * size.z * ter.cell_size() * ter.cell_size(), size.x * size.y * size.z, size.x * size.y * size.z / 1048576.0])
	lines.append("  Chunks: %d Stück à %d × %d × %d Zellen" % [world.chunks.size(), cd.x, cd.y, cd.z])
	lines.append("  Neues Spiel gesamt (Gelände, Netze, Kollision, Baum, Pflanzen, Navigation, 50 Wesen): %.0f ms" % t_new)
	# Einzelmessungen der Welt-Schicht
	t0 = Time.get_ticks_usec()
	var gen := WorldGenerator.generate(world.cfg, world.palette, seed_v)
	var t_gen := (Time.get_ticks_usec() - t0) / 1000.0
	lines.append("  Geländeerzeugung (nur Daten): %.1f ms; SHA-256 %s…" % [t_gen, (gen["data"] as VoxelData).hash_sha256().substr(0, 16)])
	world.mark_all_dirty()
	t0 = Time.get_ticks_usec()
	var n := world.flush_rebuilds()
	var t_mesh := (Time.get_ticks_usec() - t0) / 1000.0
	lines.append("  Netz + Kollision aller %d Chunks: %.0f ms (Ø %.1f ms je Chunk)" % [n, t_mesh, t_mesh / maxf(n, 1)])
	var tc: Vector3i = world.generated["tree_cell"]
	var probe := Vector3i(clampi(tc.x + 9, 1, size.x - 2), 0, clampi(tc.z + 3, 1, size.z - 2))
	probe.y = ter.surface_height(probe.x, probe.z)
	var stone := ter.type_id("stone")
	t0 = Time.get_ticks_usec()
	var edits := 0
	for i in 20:
		var c := probe + Vector3i(i % 5, 0, i / 5)
		c.y = ter.surface_height(c.x, c.z)
		if ter.set_material(c, stone, "Vermessung")["ok"]:
			edits += 1
	var t_edit := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var rebuilt := world.flush_rebuilds()
	var t_re := (Time.get_ticks_usec() - t0) / 1000.0
	lines.append("  %d Geländeänderungen: %.2f ms (Daten, Wasser, Abstützung, Navigation), danach %d Chunk(s) neu: %.1f ms" % [edits, t_edit, rebuilt, t_re])
	for i in 20:
		var c2 := probe + Vector3i(i % 5, 0, i / 5)
		c2.y = ter.surface_height(c2.x, c2.z) - 1
		ter.set_material(c2, 0, "Vermessung (zurück)")
	world.flush_rebuilds()
	t0 = Time.get_ticks_usec()
	life.ctx.nav.setup(world, life.ctx.cfg, life.footprint)
	lines.append("  Navigation aufbauen (%d Spalten): %.1f ms" % [size.x * size.z, (Time.get_ticks_usec() - t0) / 1000.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var nav := life.ctx.nav
	var walk: Array = []
	var tries := 0
	while walk.size() < 200 and tries < 20000:
		tries += 1
		var col := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.z - 1))
		if nav.is_walkable(col):
			walk.append(col)
	var found := 0
	var exp0 := int(nav.stats["expansions"])
	var worst := 0
	t0 = Time.get_ticks_usec()
	for i in range(0, walk.size() - 1, 2):
		var t1 := Time.get_ticks_usec()
		if nav.find_path(walk[i], walk[i + 1]).get("ok", false):
			found += 1
		worst = maxi(worst, Time.get_ticks_usec() - t1)
	var pairs := walk.size() / 2
	var t_nav := (Time.get_ticks_usec() - t0) / 1000.0
	lines.append("  Wegsuche: %d zufällige Strecken quer über die Karte, %d gefunden, Ø %.2f ms, längste %.2f ms, Ø %d Knoten" % [pairs, found, t_nav / maxf(pairs, 1), worst / 1000.0, (int(nav.stats["expansions"]) - exp0) / maxi(pairs, 1)])
	t0 = Time.get_ticks_usec()
	for i in 100:
		world.water.step(0.1)
	lines.append("  Wasser: 100 Schritte %.1f ms (Ø %.3f ms), %.1f m³" % [(Time.get_ticks_usec() - t0) / 1000.0, (Time.get_ticks_usec() - t0) / 100000.0, world.water.total()])
	# Simulation
	life.modules.reset_timing()
	life.perf = {"ticks": 0, "last_tick_us": 0, "sum_us": 0, "max_us": 0, "window": []}
	var ticks: Array = []
	var w0 := Time.get_ticks_msec()
	for i in int(secs / DT):
		life.step(DT)
		ticks.append(int(life.perf["last_tick_us"]))
	var wall := (Time.get_ticks_msec() - w0) / 1000.0
	ticks.sort()
	var p50 := float(ticks[ticks.size() / 2]) / 1000.0
	var p99 := float(ticks[int(ticks.size() * 0.99)]) / 1000.0
	var avg := float(life.perf["sum_us"]) / maxf(float(life.perf["ticks"]), 1.0) / 1000.0
	lines.append("")
	lines.append("Simulation: %.0f s Spielzeit mit %d Wesen in %.1f s Rechenzeit (%.1f-fach Echtzeit auf einem Kern)" % [secs, life.ctx.creatures.size(), wall, secs / maxf(wall, 0.001)])
	lines.append("  Takt (1/60 s): Ø %.2f ms · Median %.2f ms · 99 %% %.2f ms · längster %.2f ms · Ziel ≤ 8 ms (Roadmap 8.9)" % [avg, p50, p99, float(life.perf["max_us"]) / 1000.0])
	var rep := life.modules.timing_report()
	var mods: Dictionary = rep["modules"]
	var mm := life.modules.metrics_all()
	lines.append("  Zeit je Modul (Ø je Takt, längster Takt, Anteil, Messwerte):")
	var keys: Array = mods.keys()
	keys.sort_custom(func(a, b): return float(mods[a]["avg_ms"]) > float(mods[b]["avg_ms"]))
	for mid in keys:
		var m: Dictionary = mods[mid]
		lines.append("    %-22s Ø %7.3f ms · max %7.2f ms · %5.1f %% · %s" % [mid, float(m["avg_ms"]), float(m["max_ms"]), float(m["share"]) * 100.0, JSON.stringify(mm.get(mid, {}))])
	lines.append("  Außerhalb der Module (Uhr, Wärme/Phasen der Weltmassen): Ø %.3f ms je Takt" % maxf(0.0, avg - float(rep["total_ms"]) / maxf(float(life.perf["ticks"]), 1.0)))
	var ps := life.population_summary()
	lines.append("  Zustand danach: %d lebend, %d tot, Hunger Ø %.0f %%, Nahrung %.1f kg, Prüfung: %s" % [int(ps["alive"]), int(ps["dead"]), float(ps["avg_hunger"]) * 100.0, float(ps["food_kg"]), "ohne Befund" if life.audit().is_empty() else str(life.audit().slice(0, 3))])
	lines.append("")
	lines.append("Speicher und Objekte: Arbeitsspeicher (statisch) %.0f MB (vor der Welt %.0f MB), Objekte %d, Knoten %d, Entitäten %d" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, mem0 / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), sim.registry.count()])
	var path := "user://saves/_benchmark.json"
	t0 = Time.get_ticks_usec()
	var sv := SaveManager.save(life, path)
	var t_save := (Time.get_ticks_usec() - t0) / 1000.0
	var bytes := FileAccess.get_file_as_bytes(path).size()
	t0 = Time.get_ticks_usec()
	var rf := SaveManager.read_file(path)
	var t_read := (Time.get_ticks_usec() - t0) / 1000.0
	lines.append("Spielstand (Format %d): %.0f kB, Speichern %.0f ms (mit Kontrolllesen), Lesen und Prüfen %.0f ms – %s" % [SaveSchema.FORMAT_VERSION, bytes / 1024.0, t_save, t_read, "in Ordnung" if sv["ok"] and rf["ok"] else "FEHLER"])
	for ext in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
	var text := "\n".join(lines)
	print(text)
	var out := "user://benchmark_report.txt"
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(text + "\n")
		f.close()
	print("\nBericht: ", ProjectSettings.globalize_path(out))
	life.dispose()
	quit(0)
