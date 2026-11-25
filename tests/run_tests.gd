extends SceneTree
## Kommandozeilen-Testlauf:
##   godot --headless --path . -s res://tests/run_tests.gd
## Führt die Logiktests (TestSuite) und Szenentests am echten Physiklabor aus.
## Exit-Code 0 = alle bestanden. Bericht: user://test_report.txt

var results: Array = []
var notes: Array = []


func _initialize() -> void:
	# Wächter: bricht ab, falls ein Skriptfehler den Testlauf anhält
	create_timer(2400.0, true, false, true).timeout.connect(func():
		printerr("ABBRUCH: Zeitlimit des Testlaufs überschritten.")
		quit(3))
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	if "--nur-werkzeugkette-szene" in OS.get_cmdline_user_args():
		await _scene_tests_work_chain()
		for r in results:
			print("%s %s%s" % ["PASS" if r["ok"] else "FAIL", r["name"], (" | " + str(r["detail"])) if str(r["detail"]) != "" else ""])
		quit(0 if results.all(func(r): return r["ok"]) else 1)
		return
	if "--nur-werkstatt-szene" in OS.get_cmdline_user_args():
		# Entwicklerschalter: nur der Szenentest der Testwerkstatt (kein vollständiger Lauf, kein Bericht)
		await _scene_tests_workshop()
		var ok := results.all(func(r): return r["ok"])
		for r in results:
			print("%s %s%s" % ["PASS" if r["ok"] else "FAIL", r["name"], (" | " + str(r["detail"])) if str(r["detail"]) != "" else ""])
		quit(0 if ok else 1)
		return
	print("== Logiktests Physik ==")
	var suite := TestSuite.new()
	results.append_array(suite.run_all())
	notes.append_array(suite.notes)
	print("== Logiktests Welt ==")
	var tw := TestWorld.new()
	results.append_array(tw.run_all())
	notes.append_array(tw.notes)
	print("== Logiktests Wesen ==")
	var tc := TestCreatures.new()
	results.append_array(tc.run_all())
	notes.append_array(tc.notes)
	print("== Logiktests Lebenssimulation ==")
	var long_s := 600.0
	if "--quick" in OS.get_cmdline_user_args():
		long_s = 60.0
	var tl := TestLife.new()
	results.append_array(tl.run_all(long_s))
	notes.append_array(tl.notes)
	print("== Logiktests Geist, Soziales, Göttermenü, Migration ==")
	var tm := TestMind.new()
	results.append_array(tm.run_all())
	notes.append_array(tm.notes)
	print("== KI-Anbindung, Pläne, Gespräche (SIMULIERTER Testdienst – kein Ollama) ==")
	var ta := TestAI.new()
	results.append_array(ta.run_all())
	notes.append_array(ta.notes)
	print("== Experimente, Werkzeuge, praktisches Wissen (Testwerkstatt; Modell nur SIMULIERT) ==")
	var tt := TestTechnology.new()
	results.append_array(tt.run_all("--quick" in OS.get_cmdline_user_args()))
	notes.append_array(tt.notes)
	print("== Arbeitsketten und Arbeitsposen (Prompt 6B, Testszene Werkzeugkette; Modell nur SIMULIERT) ==")
	var twc := TestWorkChain.new()
	results.append_array(twc.run_all("--quick" in OS.get_cmdline_user_args()))
	notes.append_array(twc.notes)
	print("== Szenentests (Physiklabor) ==")
	await _scene_tests()
	print("== Szenentests (Startbildschirm, Welt, Kreaturen) ==")
	await _scene_tests_step2()
	print("== Szenentests (Lebenssimulation) ==")
	await _scene_tests_living()
	print("== Szenentests (Testwerkstatt) ==")
	await _scene_tests_workshop()
	print("== Szenentests (Testszene Werkzeugkette) ==")
	await _scene_tests_work_chain()
	var passed := 0
	var lines: Array = []
	lines.append("Pflanzenwesen – Testbericht")
	lines.append("Godot %s · %s · %s" % [Engine.get_version_info()["string"], OS.get_name(), Time.get_datetime_string_from_system()])
	for r in results:
		if r["ok"]:
			passed += 1
		lines.append("%s %s%s" % ["PASS" if r["ok"] else "FAIL", r["name"], (" | " + r["detail"]) if r["detail"] != "" else ""])
	lines.append("")
	lines.append("Messwerte:")
	for n in notes:
		lines.append("- " + n)
	lines.append("")
	lines.append("ERGEBNIS: %d von %d bestanden (%.1f s)" % [passed, results.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	var text := "\n".join(lines)
	print(text)
	var f := FileAccess.open("user://test_report.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	quit(0 if passed == results.size() else 1)


func _check(name: String, cond: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": cond, "detail": detail})


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _scene_tests() -> void:
	var scene: PackedScene = load("res://scenes/tests/physics_lab.tscn")
	_check("Physiklabor-Szene lädt", scene != null)
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	var lab: PhysicsLab = main
	var sim := lab.sim
	_check("Labor initialisiert ohne Fehler", sim.is_ready(), str(sim.init_errors))
	var n0 := sim.registry.count()
	_check("Labor enthält Testobjekte (erwartet 11)", n0 == 11 and lab.bodies.size() == n0, "Objekte %d, Körper %d" % [n0, lab.bodies.size()])
	_check("Physiklabor erzeugt keine Wesen (initial_population gilt nur für „Neues Spiel“)", int(sim.settings["initial_population"]) == 50 and n0 == 11)
	sim.initialize()
	_check("Doppelte Initialisierung wird ignoriert", sim.registry.count() == n0 and sim.init_order.size() == 7, "Reihenfolge %s" % str(sim.init_order))

	# Masse des Godot-Körpers = physikalische Masse
	var mass_ok := true
	for id in lab.bodies:
		if not is_equal_approx(lab.bodies[id].mass, sim.registry.get_entity(id).mass_kg):
			mass_ok = false
	_check("Godot-Körpermasse synchron mit physikalischer Masse", mass_ok)

	# Falltest
	lab.start_fall_test()
	await _frames(90)
	var times: Array = []
	for mid in PhysicsLab.FALL_MATERIALS:
		var b: PhysicalBody = lab.bodies[lab.roles["fall_" + mid]]
		times.append(b.fall_time_s)
	var expected := lab.expected_fall_time()
	var tick := 1.0 / Engine.physics_ticks_per_second
	var all_landed: bool = times.min() > 0.0
	var spread: float = float(times.max()) - float(times.min())
	_check("A Alle Würfel gelandet, gleiche Fallzeit unabhängig von der Masse", all_landed and spread <= tick + 1e-9, "Zeiten %s s, erwartet %.4f s" % [str(times), expected])
	_check("A Fallzeit entspricht √(2h/g) innerhalb von 2 Ticks", all_landed and absf(times[0] - expected) <= 2.0 * tick, "gemessen %.4f s, erwartet %.4f s" % [times[0], expected])
	notes.append("Falltest: gemessene Fallzeiten %s s, erwartet %.4f s, Tick %.4f s" % [str(times), expected, tick])

	# Pause stoppt Godot-Physik und eigene Simulation
	lab.reset_lab()
	await _frames(5)
	lab.start_fall_test()
	lab.toggle_heater()
	await _frames(10)
	lab.toggle_pause()
	await _frames(1)
	var t_p := sim.clock.sim_time_s
	var b_fall: PhysicalBody = lab.bodies[lab.roles["fall_copper"]]
	var pos_p := b_fall.global_position
	var e_p: float = sim.registry.get_entity(lab.roles["melt"]).thermal_energy_j
	await _frames(30)
	var paused_ok: bool = sim.clock.sim_time_s == t_p and b_fall.global_position.is_equal_approx(pos_p) and sim.registry.get_entity(lab.roles["melt"]).thermal_energy_j == e_p
	_check("9 Pause stoppt Godot-Körperphysik, Simulationszeit und Heizung", paused_ok and paused and sim.is_paused(), "t %.4f→%.4f, y %.4f→%.4f" % [t_p, sim.clock.sim_time_s, pos_p.y, b_fall.global_position.y])
	_check("9 Kamera/Oberfläche bleiben aktiv (PROCESS_MODE_ALWAYS)", lab.camera.can_process() and lab.ui.can_process() and not lab.samples_root.can_process())
	lab.toggle_pause()
	await _frames(5)
	_check("9 Fortsetzen: Zeit und Fall laufen weiter", sim.clock.sim_time_s > t_p and b_fall.global_position.y < pos_p.y)

	# Zurücksetzen: keine doppelten Objekte, keine fortlaufenden alten Berechnungen
	lab.toggle_contact("Kupfer–Stein")
	lab.selected_id = lab.roles["d_stone"]
	lab.load_j = 2000.0
	lab.apply_load_to_selection()
	await _frames(5)
	_check("D Bruch im Labor erzeugt Fragmente", sim.registry.count() > n0, "Objekte %d" % sim.registry.count())
	for i in 3:
		lab.reset_lab()
		await _frames(3)
	var proben := lab.samples_root.get_children().filter(func(c): return c is PhysicalBody and not c.is_queued_for_deletion())
	var ids := sim.registry.ids()
	var unique := true
	var seen := {}
	for id in ids:
		if seen.has(id):
			unique = false
		seen[id] = true
	_check("10 Zurücksetzen: gleiche Objektanzahl, keine doppelten Körper", sim.registry.count() == n0 and lab.bodies.size() == n0 and proben.size() == n0 and unique, "Objekte %d, Körper %d, Knoten %d" % [sim.registry.count(), lab.bodies.size(), proben.size()])
	_check("10 Zurücksetzen: IDs beginnen neu (1..%d)" % n0, ids == range(1, n0 + 1))
	var heater: Dictionary = sim.thermal.heaters[PhysicsLab.HEATER]
	var melt: PhysicalObject = sim.registry.get_entity(lab.roles["melt"])
	_check("10 Zurücksetzen: Heizung aus, keine alte Energiezufuhr", not heater["enabled"] and heater["supplied_j"] == 0.0 and absf(melt.temperature_k() - 293.15) < 1e-6)
	_check("10 Zurücksetzen: Kontakte frisch und deaktiviert", sim.thermal.contacts.size() == 2 and not lab.contact_enabled("Kupfer–Stein"))
	_check("10 Zurücksetzen: Uhr neu", sim.clock.sim_time_s < 0.1 and sim.generation >= 4)
	_check("10 Zurücksetzen: Startwert wiederhergestellt", sim.rng.seed == int(sim.settings["random_seed"]))

	# Bedienkette Schmelztest im Labor (kurz)
	lab.set_heater_power(3000.0)
	lab.toggle_heater()
	var t_on := sim.clock.sim_time_s
	await _frames(60)
	var supplied: float = sim.thermal.heaters[PhysicsLab.HEATER]["supplied_j"]
	var p_t := 3000.0 * (sim.clock.sim_time_s - t_on)
	_check("C Heizung im Labor: Leistung · Simulationszeit seit Einschalten", absf(supplied - p_t) < 1e-6, "zugeführt %.3f J, P·t %.3f J" % [supplied, p_t])
	lab.toggle_heater()

	# Zielobjekt entfernen → kontrolliertes Verhalten
	lab.selected_id = lab.roles["melt"]
	lab.split_selection(0.5)
	await _frames(3)
	lab.toggle_heater()
	await _frames(5)
	_check("Fehlerfall: Heizungsziel entfernt → Heizung meldet es, kein Absturz", sim.thermal.heaters[PhysicsLab.HEATER]["status"] == "Ziel entfernt")
	var path := lab.write_snapshot()
	var snap = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	_check("Schnappschuss als reines JSON lesbar", typeof(snap) == TYPE_DICTIONARY and snap["objects"].size() == sim.registry.count())

	main.queue_free()
	await process_frame
	paused = false


func _scene_tests_step2() -> void:
	# Startbildschirm
	var menu: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var buttons := menu.find_children("*", "Button", true, false)
	var all_exist := ResourceLoader.exists(Nav.LAB) and ResourceLoader.exists(Nav.WORLD) and ResourceLoader.exists(Nav.CREATURES) and ResourceLoader.exists(Nav.LIVING)
	var texts := []
	for b in buttons:
		texts.append(b.text.get_slice("\n", 0))
	_check("Startbildschirm: Neues Spiel, Fortsetzen/Laden, Vorschau-/Testbereiche (inkl. Geistlabor), Beenden", all_exist and "Neues Spiel" in texts and "Fortsetzen / Laden" in texts and "Physiklabor" in texts and "Weltvorschau" in texts and "Kreaturenvorschau" in texts and "Geistlabor (Testbereich)" in texts and "Beenden" in texts, str(texts))
	menu.queue_free()
	await process_frame
	# Weltvorschau: Bearbeitung aktualisiert Kollision (echte Physik-Strahlabfrage)
	var wp: WorldPreview = load("res://scenes/world_preview.tscn").instantiate()
	root.add_child(wp)
	await process_frame
	_check("Weltvorschau startet ohne Fehler", wp.errors.is_empty() and wp.world.data != null and wp.plant_count > 0 and wp.tree_info.get("height_m", 0.0) == 8.0)
	var w := wp.world
	var x := 10
	var z := 50
	var top := w.data.column_top(x, z, w.palette.solid)
	var cs := w.data.cell_size
	var from := Vector3((x + 0.5) * cs, 30.0, (z + 0.5) * cs)
	await physics_frame
	await physics_frame
	var space := wp.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0)
	var h0 = space.intersect_ray(q)
	wp.mode = "add"
	wp.place_type = w.palette.id_of("stone")
	wp.apply_tool(from, Vector3.DOWN)
	w.flush_rebuilds()
	await physics_frame
	await physics_frame
	var h1 = space.intersect_ray(q)
	wp.mode = "remove"
	wp.apply_tool(from, Vector3.DOWN)
	wp.apply_tool(from, Vector3.DOWN)
	w.flush_rebuilds()
	await physics_frame
	await physics_frame
	var h2 = space.intersect_ray(q)
	_check("Weltbearbeitung aktualisiert die Kollision (Physik-Strahl)", not h0.is_empty() and absf(h0["position"].y - top * cs) < 1e-3
		and absf(h1["position"].y - (top + 1) * cs) < 1e-3 and absf(h2["position"].y - (top - 1) * cs) < 1e-3,
		"Treffer y: %.2f → %.2f → %.2f m (erwartet %.2f / %.2f / %.2f)" % [h0.get("position", Vector3.ZERO).y, h1.get("position", Vector3.ZERO).y, h2.get("position", Vector3.ZERO).y, top * cs, (top + 1) * cs, (top - 1) * cs])
	var seed_before := w.data.hash_sha256()
	wp.regenerate(w.world_seed)
	_check("Welt zurücksetzen mit gleichem Startwert stellt Ursprungszustand her", w.data.hash_sha256() != seed_before and w.fragments.is_empty())
	var fresh := w.data.hash_sha256()
	wp.regenerate(w.world_seed)
	_check("Erneutes Zurücksetzen liefert identische Daten, keine doppelten Weltobjekte", w.data.hash_sha256() == fresh and wp.object_entities.size() == wp.sim.registry.count())
	wp.queue_free()
	await process_frame
	paused = false
	# Kreaturenvorschau
	var cp: CreaturePreview = load("res://scenes/tools/creature_preview.tscn").instantiate()
	root.add_child(cp)
	await process_frame
	_check("Kreaturenvorschau startet mit einem Wesen", cp.views.size() == 1 and cp.sim.registry.count() == 1)
	cp.show_variants(10)
	_check("10 Varianten nebeneinander", cp.views.size() == 10 and cp.sim.registry.count() == 10)
	var t0 := Time.get_ticks_msec()
	cp.show_variants(50)
	var ms := Time.get_ticks_msec() - t0
	for i in 10:
		await process_frame
	_check("50 Figuren erzeugt, alte Entitäten entfernt", cp.views.size() == 50 and cp.sim.registry.count() == 50, "Aufbau %d ms" % ms)
	notes.append("50 Figuren (headless, ohne Grafik): Aufbau %d ms, %d Netze, %d Voxel" % [ms, cp.perf.get("mesh_instances", 0), cp.perf.get("voxels_total", 0)])
	cp.show_single(1001)
	cp.side = "l"
	cp.remove_forearm()
	cp.prosthesis_material = "copper"
	var pr := cp.attach_prosthesis()
	var saved := cp.save_config("user://test_preview_config.json")
	var mass_saved := cp.plan.total_mass(cp.sim.materials)
	cp.show_single(42)
	var loaded := cp.load_config("user://test_preview_config.json")
	_check("Vorschau: Konfiguration mit Prothese speichern und wiederherstellen", pr["ok"] and saved and loaded and absf(cp.plan.total_mass(cp.sim.materials) - mass_saved) < 1e-12 and cp.views[0].meshes.has(pr["id"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_preview_config.json"))
	cp.queue_free()
	await process_frame


func _scene_tests_living() -> void:
	const TEST_PATH := "user://saves/_test_szene.json"
	LivingWorld.ai_service_override = AIService.disabled()     # Szenentests nie mit echtem Dienst
	var calls0 := PopulationSpawner.spawn_calls
	LivingWorld.pending = {"mode": "new"}
	var lw: LivingWorld = load(Nav.LIVING).instantiate()
	lw.save_path = TEST_PATH
	root.add_child(lw)
	await process_frame
	await process_frame
	var ctx := lw.life.ctx
	_check("Lebenswelt: Neues Spiel startet ohne Fehler mit 50 Wesen und 50 Darstellungen", lw.start_ok and ctx.creatures.size() == 50 and lw.views.size() == 50 and PopulationSpawner.spawn_calls == calls0 + 1,
		str(lw.errors))
	if not lw.start_ok:
		lw.queue_free()
		return
	var t0 := ctx.now()
	var walk_seen := false
	var walk_ok := true
	for i in 240:
		await physics_frame
		for id in lw.views:
			var e: Dictionary = lw.views[id]
			var cr: Creature = ctx.creatures[id]
			if e["anim"] == "walk":
				walk_seen = true
				# geprüft wird die Zuordnung im selben Bild (Handlung, aus der die Animation abgeleitet wurde);
				# zwischen Physiktakt und Bild kann eine Handlung bereits gewechselt haben
				if str(e.get("anim_src", "")) != "move_to":
					walk_ok = false
	_check("Lebenswelt: Simulation läuft im festen Physiktakt", ctx.now() > t0 + 3.0, "%.2f s → %.2f s" % [t0, ctx.now()])
	_check("Gehanimation nur bei tatsächlicher Bewegung (move_to)", walk_seen and walk_ok)
	var any_id: int = ctx.creatures.keys()[0]
	lw.select(any_id)
	await process_frame
	_check("Beobachtungsfenster zeigt ausgewähltes Wesen aus Systemdaten", lw._inspector.text.text.find("#%d" % any_id) >= 0 and lw._inspector.text.text.find("Energie") >= 0 and lw._inspector.text.text.find("Zustand") >= 0)
	_check("Populationsanzeige: lebend, gestorben, Nahrung, Zeit, Tagesphase", lw._population.summary.text.find("lebend") >= 0 and lw._population.summary.text.find("Nahrung") >= 0 and lw._population.summary.text.find("Zeit") >= 0)
	lw.toggle_ai_panel()
	lw.toggle_conversations()
	for i in 12:
		await process_frame
	_check("KI-Panel und Gesprächsansicht öffnen sich; Anzeige „AUS – Welt läuft lokal“, kein Dienst nötig", lw._ai_panel.visible and lw._conv.visible and lw._ai_panel._mode.text.begins_with("AUS")
		and lw._inspector.text.text.find("MODELLVORSCHLAG") >= 0 and lw._inspector.text.text.find("HÖRENSAGEN") >= 0, lw._ai_panel._mode.text)
	lw.toggle_ai_panel()
	lw.toggle_conversations()
	# Pause
	lw.toggle_pause()
	await physics_frame
	var tp := ctx.now()
	var pos: Vector3 = ctx.creatures[any_id].position
	var ui0 := lw._ui_accum
	var cam_yaw := lw.camera.yaw
	for i in 30:
		await physics_frame
	await process_frame
	_check("(11) Pause in der Szene: Zeit und Wesen stehen, Kamera/Oberfläche laufen weiter", ctx.now() == tp and ctx.creatures[any_id].position == pos and paused and lw.camera.can_process() and lw._inspector.can_process() and lw.can_process(),
		"t %.3f → %.3f" % [tp, ctx.now()])
	lw.toggle_pause()
	await physics_frame
	# Entwicklermodus: Unterarm entfernen → Darstellung neu aufgebaut
	ctx.dev_mode = true
	lw._side_opt.select(1)
	lw._dev("remove_forearm")
	await process_frame
	await process_frame
	var view: CreatureView = lw.views[any_id]["view"]
	_check("Entwicklermodus: Unterarm entfernt → Darstellung und Fähigkeiten aktualisiert", not view.meshes.has("hand_r") and float(ctx.creatures[any_id].caps["grasp_by_side"]["r"]) == 0.0, lw._msg.text)
	# Göttermenü: Nahrung beim ausgewählten Wesen, Material an angeklickter Position
	lw.toggle_god_menu()
	lw._god.set_kind("gift_food")
	lw._god._target_mode.select(0)
	var god0 := ctx.ledger.god_kg
	lw._god.execute()
	for i in 3:
		await process_frame
	_check("Göttermenü in der Szene: Gabe beim Wesen ausgeführt, bilanziert, sichtbar (Leuchten)", ctx.interventions.history.size() == 1 and ctx.ledger.god_kg > god0 and lw.effect_nodes.size() >= 1 and lw._god._status.text.begins_with("Eingriff #1"),
		lw._god._status.text)
	lw._god.set_kind("place_material")
	lw._god._pick_btn.button_pressed = true
	var tgt: Vector3 = ctx.creatures[any_id].position + Vector3(2.0, 0, 0)
	var colp := ctx.nav.world_to_col(tgt)
	lw._on_pick(Vector3(tgt.x, 30.0, tgt.z), Vector3.DOWN, false)
	var picked_ok: bool = lw._god.picked_position != null and absf((lw._god.picked_position as Vector3).y - ctx.nav.ground_y(colp)) < 0.6
	lw._god.execute()
	for i in 3:
		await process_frame
	_check("Göttermenü: Position per Klick (Strahl auf Gelände), Materialstück erscheint", picked_ok and ctx.material_pieces.size() == 1 and lw.piece_nodes.size() == 1, lw._god._status.text)
	lw.toggle_god_menu()
	# Vergleichsansicht
	var other_id: int = ctx.creatures.keys()[1]
	lw.compare_id = other_id
	lw.toggle_compare()
	lw.select(any_id)
	await process_frame
	_check("Vergleichsansicht zeigt zwei Wesen mit gerichteten Beziehungen", lw._compare.visible and lw._compare_a.text.find("#%d" % other_id) >= 0 and lw._compare_b.text.find("#%d" % any_id) >= 0 and lw._compare_a.text.find("→ #%d" % any_id) >= 0)
	lw.toggle_compare()
	_check("Beobachtungsfenster trennt Weltfakt, Beobachtung, Erinnerung, Vermutung, Entscheidung", lw._inspector.text.text.find("WELTFAKT") >= 0 and lw._inspector.text.text.find("BEOBACHTUNG") >= 0 and lw._inspector.text.text.find("ERINNERUNG") >= 0 and lw._inspector.text.text.find("VERMUTUNG") >= 0 and lw._inspector.text.text.find("ENTSCHEIDUNG") >= 0)
	# Speichern und Laden über die Szene
	for i in 30:
		await physics_frame
	lw.do_save()
	var saved_t := ctx.now()
	var saved_alive: int = lw.life.population_summary()["alive"]
	_check("Speichern aus der Szene", FileAccess.file_exists(TEST_PATH) and lw._msg.text.begins_with("Gespeichert"), lw._msg.text)
	lw.queue_free()
	await process_frame
	var calls1 := PopulationSpawner.spawn_calls
	LivingWorld.pending = {"mode": "load", "path": TEST_PATH}
	var lw2: LivingWorld = load(Nav.LIVING).instantiate()
	root.add_child(lw2)
	await process_frame
	await process_frame
	_check("(12) Laden über die Szene: gleiche Wesen, keine zusätzlichen, Spawner nicht aufgerufen", lw2.start_ok and lw2.life.ctx.creatures.size() == 50 and PopulationSpawner.spawn_calls == calls1 and lw2.views.size() == 50 and lw2.life.population_summary()["alive"] == saved_alive,
		str(lw2.errors))
	_check("Keine Offline-Zeit beim Laden über die Szene", lw2.start_ok and absf(lw2.loaded_time_s - saved_t) < 1e-9, "%.4f / %.4f" % [lw2.loaded_time_s, saved_t])
	var hand_gone: bool = lw2.start_ok and not lw2.life.ctx.creatures[any_id].plan.is_present("hand_r") and not lw2.views[any_id]["view"].meshes.has("hand_r")
	_check("Körperveränderung übersteht Speichern/Laden (Darstellung)", hand_gone)
	_check("Eingriffe und Materialstück überstehen Speichern/Laden (Szene)", lw2.start_ok and lw2.life.ctx.interventions.history.size() == 2 and lw2.life.ctx.material_pieces.size() == 1)
	lw2.queue_free()
	await process_frame
	# Beschädigter Spielstand: Szene meldet verständlich, startet nicht
	var f := FileAccess.open(TEST_PATH, FileAccess.READ_WRITE)
	f.seek(200)
	f.store_string("XXXX")
	f.close()
	LivingWorld.pending = {"mode": "load", "path": TEST_PATH}
	var lw3: LivingWorld = load(Nav.LIVING).instantiate()
	root.add_child(lw3)
	await process_frame
	_check("(14) Beschädigter Spielstand: Szene meldet Fehler verständlich, keine Wesen erzeugt", not lw3.start_ok and lw3.life.ctx.creatures.is_empty() and str(lw3.errors).find("beschädigt") >= 0,
		str(lw3.errors).substr(0, 120))
	lw3.queue_free()
	await process_frame
	paused = false
	for p2 in [TEST_PATH, TEST_PATH + ".bak", "user://saves/_test_spielstand.json", "user://saves/_test_spielstand.json.bak"]:
		if FileAccess.file_exists(p2):
			DirAccess.remove_absolute(p2)


## Testwerkstatt in der echten Spielszene (Prompt 6): Darstellung aus den Daten, Oberflächen,
## getrennte Spielerdiagnose, keine „Erfindung“ durch bloße Modellhypothesen.
func _scene_tests_workshop() -> void:
	LivingWorld.ai_service_override = AIService.disabled()
	LivingWorld.pending = {"mode": "workshop"}
	var lw: LivingWorld = load(Nav.LIVING).instantiate()
	lw.save_path = "user://saves/_test_werkstatt.json"
	root.add_child(lw)
	await process_frame
	await process_frame
	var ctx := lw.life.ctx
	var tops := 0
	for pid in ctx.material_pieces:
		if (ctx.material_pieces[pid] as MaterialPiece).assembly_id == 0:
			tops += 1
	tops += ctx.assemblies.size()
	_check("Werkstatt-Szene: startet mit 2 Testwesen, Testausrüstung, Heizung und Werkstattfeld", lw.start_ok and ctx.creatures.size() == 2 and not lw.life.workshop.is_empty()
		and lw.heater_nodes.size() == 1 and lw._ws_panel.visible, str(lw.errors))
	if not lw.start_ok:
		lw.queue_free()
		return
	_check("Werkstatt-Szene: jedes Weltobjekt (Stück oder Verbund) hat genau ein Modell aus dem Generator", lw.piece_nodes.size() == tops and tops >= 12, "%d Modelle / %d Objekte" % [lw.piece_nodes.size(), tops])
	var a: Creature = ctx.creature(int(lw.life.workshop["a"]))
	var r := TestWorkshop.trigger(lw.life, 2)
	for i in 600:
		await physics_frame
		if ctx.experiments.active(a) == null:
			break
	for i in 3:
		await process_frame
	var aid := a.held_object_id
	var asm_node: Node3D = lw.piece_nodes.get(aid, null)
	var parts_drawn := 0
	if asm_node != null:
		parts_drawn = asm_node.get_child_count()
	var hp = ctx.position_of(aid)
	# Prompt 6B: Modell sitzt am Griffpunkt der tatsächlich animierten Hand (nicht an einem festen Punkt)
	var va: CreatureView = lw.views[a.id]["view"] if lw.views.has(a.id) else null
	var gf := va.animator.grip_frame(a.hold_side if a.hold_side != "" else "r") if va != null else {"ok": false}
	var grip_w: Vector3 = (va.global_transform * (gf["xform"] as Transform3D)).origin if gf["ok"] else Vector3(INF, INF, INF)
	_check("Werkstatt-Szene: Verbund aus Stiel, Kopf und Fasern wird mit allen Teilen gezeichnet und am Griffpunkt der Hand gehalten",
		r["ok"] and ctx.assemblies.has(aid) and parts_drawn >= 3 and hp != null and asm_node != null and asm_node.global_position.distance_to(grip_w) < 1e-3 and grip_w.distance_to(a.position) < 1.5,
		"Teile gezeichnet %d, Halter #%d, Abstand Griff %.4f m" % [parts_drawn, ConstructionSystem.carrier_of(ctx, aid), asm_node.global_position.distance_to(grip_w) if asm_node != null else -1.0])
	# Formänderung sichtbar: Signatur ändert sich, Modell wird neu aufgebaut
	var cu: MaterialPiece = ctx.material_pieces[int(lw.life.workshop["copper_sample3"])]
	var n0: Node3D = lw.piece_nodes.get(cu.id, null)
	var id0 := n0.get_instance_id() if n0 != null else 0
	var sig0 := str(n0.get_meta("signature", "")) if n0 != null else ""
	MaterialProcessSystem.work_piece(ctx, cu, 40.0)
	for i in 3:
		await process_frame
	var n1: Node3D = lw.piece_nodes.get(cu.id, null)
	_check("Werkstatt-Szene: Formänderung der Kupferprobe baut deren Modell neu auf (Darstellung folgt Daten)", id0 != 0 and is_instance_valid(n1) and n1.get_instance_id() != id0
		and str(n1.get_meta("signature", "")) == ObjectGenerator.signature(cu) and sig0 != ObjectGenerator.signature(cu),
		"ε %.3f, Signatur vorher %s, jetzt %s" % [cu.strain, sig0, ObjectGenerator.signature(cu)])
	lw.select(a.id)
	lw._exp.object_id = aid
	lw._exp.visible = true
	lw._know.visible = true
	ProceduralKnowledge.add_hypothesis(ctx, a, {"question": "Wird Kupfer flacher, wenn ich mit dem Stein darauf schlage?", "steps": [], "source": "Modell (SIMULIERT)", "status": "ungeprüft"})
	lw._refresh_ui()
	await process_frame
	var et: String = lw._exp.text.text
	var kt: String = lw._know.text.text
	_check("Werkstatt-Szene: Versuchsansicht zeigt Ausgangslage, Schritte, Ergebnis, Bauteile/Verbindungen und Bewertung",
		et.find("Versuch #") >= 0 and et.find("Schritte") >= 0 and et.find("Erwartung") >= 0 and et.find("Verbindung") >= 0 and et.find("Funktionale Bewertung") >= 0, et.substr(0, 200))
	_check("Werkstatt-Szene: Spielerdiagnose und Wahrnehmung des Wesens getrennt gekennzeichnet", et.find("SPIELERDIAGNOSE") >= 0 and et.find("WAHRNEHMUNG DES WESENS") >= 0)
	_check("Werkstatt-Szene: Wissensansicht zeigt Verfahren mit Stufe und Herkunft; Hypothese als ungeprüft, nirgends „erfunden“",
		kt.find("Praktisches Wissen") >= 0 and kt.find("Herkunft") >= 0 and kt.find("ungeprüft") >= 0 and et.find("HYPOTHESE") >= 0
		and et.find("erfunden") < 0 and kt.find("erfunden") < 0, kt.substr(0, 200))
	lw.queue_free()
	await process_frame
	LivingWorld.pending = {}


## Testszene Werkzeugkette in der echten Spielszene (Prompt 6B): Bedienfeld, Lager/Baustelle sichtbar,
## Hammer am Griffpunkt, sichtbarer Kontakt am Ziel, Arbeitsanzeige im Wesenfenster und über dem Wesen.
func _scene_tests_work_chain() -> void:
	LivingWorld.ai_service_override = AIService.disabled()
	LivingWorld.pending = {"mode": "werkzeugkette"}
	var lw: LivingWorld = load(Nav.LIVING).instantiate()
	lw.save_path = "user://saves/_test_werkzeugkette.json"
	root.add_child(lw)
	await process_frame
	await process_frame
	var ctx := lw.life.ctx
	_check("Werkzeugkette-Szene: startet mit einem Testwesen, Lager, Baustelle, Testofen und Bedienfeld", lw.start_ok and ctx.creatures.size() == 1
		and lw.life.workshop.has("work_scene") and lw._work_panel.visible and not lw._ws_panel.visible and lw.storage_nodes.size() == 1 and lw.site_nodes.size() == 1
		and lw.heater_nodes.size() == 1, str(lw.errors))
	if not lw.start_ok:
		lw.queue_free()
		return
	var a := WorkChainScene.actor(lw.life)
	lw.select(a.id)
	var r := WorkChainScene.trigger(lw.life, "lagern")
	var grip_err := -1.0
	var head_errs: Array = []
	var poses := {}
	var hud_ok := false
	var label_ok := false
	for i in 4800:
		await physics_frame
		var ra: GameAction = ctx.executor.running.get(a.id, null)
		var an: Dictionary = ra.state.get("anim", {}) if ra != null else {}
		if not an.is_empty():
			poses[str(an.get("pose", ""))] = true
		if a.held_object_id != 0 and ctx.assemblies.has(a.held_object_id) and str(an.get("phase", "")) == "contact" and head_errs.size() < 3:
			await process_frame
			var asm: Assembly = ctx.assemblies.get(a.held_object_id, null)
			var node: Node3D = lw.piece_nodes.get(a.held_object_id, null)
			var view: CreatureView = lw.views[a.id]["view"]
			var gf := view.animator.grip_frame(a.hold_side if a.hold_side != "" else "r")
			if asm != null and node != null and gf["ok"]:
				grip_err = node.global_position.distance_to((view.global_transform * (gf["xform"] as Transform3D)).origin)
				var head_w := node.global_transform * Vector3(float(asm.offsets.get(asm.head_part_id, 0.0)), 0.0, 0.0)
				var tg: Array = an["target"]
				head_errs.append(head_w.distance_to(Vector3(float(tg[0]), float(tg[1]), float(tg[2]))))
			lw._refresh_ui()
			var it: String = lw._inspector.text.text
			hud_ok = it.find("ARBEIT") >= 0 and it.find("Werkzeug:") >= 0 and it.find("#%d" % a.held_object_id) >= 0 and it.find("Fortschritt") >= 0
			label_ok = lw.work_labels.has(a.id)
		if head_errs.size() >= 3:
			break
	var worst := 0.0
	for e in head_errs:
		worst = maxf(worst, float(e))
	_check("Werkzeugkette-Szene: Hammer-Modell sitzt am Griffpunkt der animierten Hand; Hammerkopf trifft beim Kontakt das Ziel (≤ 8 cm)",
		r["ok"] and grip_err >= 0.0 and grip_err < 1e-3 and head_errs.size() == 3 and worst <= 0.08, "Griff %.4f m, Kopf %s" % [grip_err, str(head_errs)])
	_check("Werkzeugkette-Szene: Arbeitsposen aus der Handlung (Anlauf, Tragen/Ablegen, Verbinden, Greifen, Schlagen)",
		poses.has("walk_short") and poses.has("assemble") and poses.has("strike") and (poses.has("grasp") or poses.has("carry_two")), str(poses.keys()))
	_check("Werkzeugkette-Szene: Wesenfenster zeigt ARBEIT (Ziel, Handlung, Werkzeug-ID, Fortschritt); Arbeitsanzeige über dem Wesen", hud_ok and label_ok,
		lw._inspector.text.text.substr(lw._inspector.text.text.find("ARBEIT"), 200))
	lw.queue_free()
	await process_frame
	LivingWorld.pending = {}
