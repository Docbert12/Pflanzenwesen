extends SceneTree
## Entwicklerwerkzeug: Bildschirmfotos der Lebenssimulation (mit Grafik ausführen, nicht --headless).
## Misst zusätzlich die Bildzeit mit 50 Wesen in dieser Umgebung.

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_life_%s.png" % name)
	print("gespeichert: ", ProjectSettings.globalize_path("user://screenshot_life_%s.png" % name))


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	await _shot("0_menue")
	menu.queue_free()
	# KI-Anbindung für die Aufnahmen: SIMULIERTER Testdienst (kein Ollama) – im Panel deutlich gekennzeichnet
	var ais := AISettings.new()
	ais.user_path = ""
	ais.reload()
	for kv in [["enabled", true], ["use_mock", true], ["model", MockOllama.MODEL], ["eligible_share", 1.0], ["per_creature_min_interval_s", 30.0], ["global_rate_per_min", 30]]:
		ais.set_value(kv[0], kv[1])
	var svc := AIService.new(ais)
	(svc.client.transport as MockOllama).latency_ms = 800
	svc.test_connection()
	for i in 6:
		svc.poll()
		OS.delay_msec(900)
	LivingWorld.ai_service_override = svc
	LivingWorld.pending = {"mode": "new"}
	var lw: LivingWorld = load(LivingWorld.SCENE).instantiate()
	lw.save_path = "user://saves/_capture.json"
	root.add_child(lw)
	for i in 60 * 25:
		await physics_frame
	var frames: Array = []
	for i in 120:
		var t0 := Time.get_ticks_usec()
		await process_frame
		frames.append((Time.get_ticks_usec() - t0) / 1000.0)
	var s := 0.0
	for f in frames:
		s += f
	print("Bildzeit Ø %.1f ms über 120 Bilder (50 Wesen, Software-Rendering)" % (s / frames.size()))
	await _shot("1_uebersicht")
	# Ein Wesen auswählen, das gerade isst oder geht
	var pick := 0
	for id in lw.life.ctx.executor.running:
		var a: GameAction = lw.life.ctx.executor.running[id]
		if a.type in ["eat", "pick_up", "move_to"]:
			pick = id
			if a.type == "eat":
				break
	if pick == 0:
		pick = lw.life.ctx.creatures.keys()[0]
	lw.select(pick)
	var cr: Creature = lw.life.ctx.creatures[pick]
	lw.camera.target = cr.position + Vector3(0, 0.5, 0)
	lw.camera.distance = 4.5
	lw.camera.pitch = -0.35
	lw.camera._apply()
	await _shot("2_wesen_untersuchen")
	lw.life.ctx.dev_mode = true
	lw._side_opt.select(1)
	lw._dev("remove_forearm")
	lw._dev("attach_prosthesis", "copper")
	lw._side_opt.select(0)
	lw._dev("injure_leg")
	for i in 30:
		await physics_frame
	lw.camera.target = lw.life.ctx.creatures[pick].position + Vector3(0, 0.5, 0)
	lw.camera._apply()
	await _shot("3_entwicklermodus")
	lw.life.ctx.dev_mode = false
	# Göttermenü mit Vorschau und ausgeführter Gabe
	lw.toggle_god_menu()
	lw._god.set_kind("gift_food")
	lw._god._target_mode.select(0)
	var evs := lw.life.ctx.interventions.recent_events(300.0, 5, 0)
	lw._god._only_sel.button_pressed = false
	lw._god.refresh_events()
	if lw._god._events.item_count > 0:
		lw._god._events.select(0)
		lw._god._events.item_selected.emit(0)
	lw._god.refresh_preview()
	await _shot("6_goettermenue_vorschau")
	lw._god.execute()
	for i in 20:
		await physics_frame
	await _shot("7_goettermenue_gabe")
	lw.toggle_god_menu()
	var ids := lw.life.ctx.creatures.keys()
	ids.sort()
	lw.compare_id = ids[3] if ids[3] != pick else ids[4]
	lw.toggle_compare()
	await _shot("8_vergleich")
	lw.toggle_compare()
	# KI: gezielte Plananfrage (SIMULIERT), Panel, Wesenfenster mit Plan, Gespräche
	var who := 0
	for id in ids:
		var c2: Creature = lw.life.ctx.creatures[id]
		if c2.alive and not c2.food_memory.is_empty() and c2.metabolism.hunger() < 0.75 and not lw.life.ctx.ai.queue.has_actor(id):
			who = id
			break
	if who != 0:
		var cw: Creature = lw.life.ctx.creatures[who]
		print("KI-Anfrage: ", lw.life.ctx.ai.request_now(cw, "plan", "Aufnahme: gezielte Anfrage"))
		for i in 150:
			await physics_frame
		lw.select(who)
		lw.camera.target = cw.position + Vector3(0, 0.5, 0)
		lw.camera.distance = 6.0
		lw.camera._apply()
	lw.toggle_ai_panel()
	for i in 10:
		await process_frame
	await _shot("10_ki_panel_simuliert")
	lw.toggle_ai_panel()
	await _shot("11_wesen_modellplan")
	for i in 60 * 40:
		await physics_frame
	lw.toggle_conversations()
	for i in 10:
		await process_frame
	await _shot("12_gespraeche")
	lw.toggle_conversations()
	LivingWorld.ai_service_override = null
	lw.toggle_pause()
	lw.life.sim.clock.sim_time_s += 0.0
	await _shot("4_pause")
	lw.toggle_pause()
	# Nacht: Zeit bis zur Nacht vorspulen (nur Darstellungstest: Takte laufen normal)
	for i in 60 * 5:
		lw.life.step(1.0 / 60.0)
	var dn := lw.life.ctx.day_night
	while dn.light(lw.life.ctx.now()) > 0.0:
		lw.life.step(1.0 / 60.0)
	for i in 60 * 30:
		lw.life.step(1.0 / 60.0)
	lw.camera.target = lw.life.tree_node.position + Vector3(0, 1, 0)
	lw.camera.distance = 20.0
	lw.camera.pitch = -0.5
	lw.camera._apply()
	await _shot("5_nacht")
	print("Zustand Nacht: ", lw.life.population_summary())
	lw.queue_free()
	await process_frame
	var lab = load("res://scenes/tests/mind_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	lab._run("D", false)
	for i in 600:
		await process_frame
		if lab._out.text.find("Teilprüfungen bestanden") >= 0:
			break
	await _shot("9_geistlabor")
	for p in ["user://saves/_capture.json", "user://saves/_capture.json.bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	quit(0)
