extends SceneTree
## Entwicklerwerkzeug: Bildschirmfotos der Testszene Werkzeugkette (Prompt 6B, mit Grafik ausführen):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . -s res://tools/capture_work_chain.gd
## Löst die Kette „lagern“ GEZIELT aus und fotografiert die Phasen (Holen/Tragen, Binden, Hammer in der Hand,
## Ausholen, Kontakt, Tragen mit zwei Händen, Einlagern), danach eine fertige Steinreihe (Kette „bauen“
## in einer frischen Szene) und das Schmelzen im Testofen (Kette „schmelzen“: Tiegel füllen, Ofen bedienen,
## gießen, Guss in der Form). Bilder: user://screenshot_werkzeugkette_*.png. Ohne Ollama.

var _shots := {}


func _initialize() -> void:
	_run.call_deferred()


## Bild zum gemessenen Zeitpunkt: Simulation anhalten (Darstellung läuft weiter), aufnehmen, fortsetzen.
## Ohne Anhalten liefen bei geringer Bildrate zwischen Messung und Aufnahme mehrere Physiktakte.
var lw_cur: LivingWorld = null


func _shot(name: String) -> void:
	var paused := false
	if lw_cur != null and is_instance_valid(lw_cur) and not paused_tree():
		lw_cur.toggle_pause()
		paused = true
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := "user://screenshot_werkzeugkette_%s.png" % name
	img.save_png(path)
	_shots[name] = true
	print("gespeichert: ", ProjectSettings.globalize_path(path))
	if paused:
		lw_cur.toggle_pause()


func paused_tree() -> bool:
	return paused


func _look(lw: LivingWorld, p: Vector3, dist: float, pitch: float = -0.4, yaw: float = 0.6) -> void:
	lw.camera.target = p
	lw.camera.distance = dist
	lw.camera.pitch = pitch
	lw.camera.yaw = yaw
	lw.camera._apply()


func _scene() -> LivingWorld:
	LivingWorld.ai_service_override = AIService.disabled()
	LivingWorld.pending = {"mode": "werkzeugkette"}
	var lw: LivingWorld = load(LivingWorld.SCENE).instantiate()
	lw.save_path = "user://saves/_capture_werkzeugkette.json"
	root.add_child(lw)
	lw_cur = lw
	return lw


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var lw := _scene()
	for i in 20:
		await physics_frame
	var ctx := lw.life.ctx
	var a := WorkChainScene.actor(lw.life)
	lw.select(a.id)
	_look(lw, a.position + Vector3(-0.2, 0.2, 0.4), 5.2, -0.62, 0.35)
	await _shot("1_ausgangslage")
	WorkChainScene.trigger(lw.life, "lagern")
	var big := int(lw.life.workshop["big_stone"])
	for i in 60 * 140:
		await physics_frame
		var ra: GameAction = ctx.executor.running.get(a.id, null)
		var an: Dictionary = ra.state.get("anim", {}) if ra != null else {}
		var pose := str(an.get("pose", ""))
		var ph := str(an.get("phase", ""))
		var cam_p := a.position + Vector3(0, 0.35, 0)
		if not _shots.has("2_traegt_steinkopf") and a.held_object_id == int(lw.life.workshop["head"]) and ra != null and ra.type == "move_to":
			_look(lw, cam_p, 1.7, -0.3, a.heading + 2.2)
			await _shot("2_traegt_steinkopf")
		elif not _shots.has("3_bindet_hammer") and pose == "assemble" and ph == "work" and float(an.get("u", 0.0)) > 0.4:
			_look(lw, cam_p, 1.4, -0.45, a.heading + 2.4)
			await _shot("3_bindet_hammer")
		elif not _shots.has("4_ausholen") and pose == "strike" and ph == "work" and float(an.get("u", 0.0)) > 0.5 and float(an.get("u", 0.0)) < 0.62:
			var mid: Vector3 = (a.position + ctx.material_pieces[big].position) * 0.5 + Vector3(0, 0.3, 0) if ctx.material_pieces.has(big) else cam_p
			_look(lw, mid, 1.5, -0.12, a.heading + PI * 0.5)
			await _shot("4_ausholen")
		elif not _shots.has("5_kontakt") and _shots.has("4_ausholen") and pose == "strike" and ph == "contact":
			var mid2: Vector3 = (a.position + ctx.material_pieces[big].position) * 0.5 + Vector3(0, 0.2, 0) if ctx.material_pieces.has(big) else cam_p
			_look(lw, mid2, 1.2, -0.12, a.heading + PI * 0.5)
			await _shot("5_kontakt")
		elif not _shots.has("6_bruchstuecke") and not ctx.material_pieces.has(big) and ra != null and ra.type == "deform_material" and ph == "recover":
			_look(lw, a.position + Vector3(0, 0.2, 0), 1.6, -0.55, a.heading + 2.0)
			await _shot("6_bruchstuecke")
		elif not _shots.has("7_traegt_zweihaendig") and a.hold_mode == "two" and ra != null and ra.type == "move_to":
			_look(lw, cam_p, 1.6, -0.2, a.heading + 0.9)
			await _shot("7_traegt_zweihaendig")
		elif not _shots.has("8_lagert_ein") and ra != null and ra.type == "deposit_in_storage" and ph == "work" and float(an.get("u", 0.0)) > 0.5:
			_look(lw, cam_p, 1.6, -0.5, a.heading + 2.3)
			await _shot("8_lagert_ein")
		if ctx.work.active(a) == null and i > 60:
			break
	var st: StoragePlace = ctx.storages[int(lw.life.workshop["storage"])]
	_look(lw, st.position + Vector3(0, 0.15, 0), 1.6, -0.75, 0.5)
	lw._refresh_ui()
	await _shot("9_lager_mit_bruchstuecken")
	lw.queue_free()
	await process_frame
	# Steinreihe (frische Szene, Kette „bauen“)
	var lw2 := _scene()
	for i in 20:
		await physics_frame
	var ctx2 := lw2.life.ctx
	var a2 := WorkChainScene.actor(lw2.life)
	lw2.select(a2.id)
	WorkChainScene.trigger(lw2.life, "bauen")
	for i in 60 * 140:
		await physics_frame
		var ra2: GameAction = ctx2.executor.running.get(a2.id, null)
		if not _shots.has("10_setzt_stein") and ra2 != null and ra2.type == "place_building_part" and str(ra2.state.get("anim", {}).get("phase", "")) == "work":
			_look(lw2, a2.position + Vector3(0, 0.3, 0), 1.5, -0.3, a2.heading + PI * 0.5)
			await _shot("10_setzt_stein")
		if ctx2.work.active(a2) == null and i > 60:
			break
	var site: Structure = ctx2.structures[int(lw2.life.workshop["site"])]
	_look(lw2, StructureSystem.slot_world(site, 1) + Vector3(0, 0.05, 0), 1.0, -1.05, site.heading + 0.35)
	lw2._refresh_ui()
	await _shot("11_steinreihe_fertig")
	lw2.queue_free()
	await process_frame
	# Schmelzen im Testofen (frische Szene, Kette „schmelzen“): in den Tiegel, Ofen bedienen, gießen, Guss
	var lw3 := _scene()
	for i in 20:
		await physics_frame
	var ctx3 := lw3.life.ctx
	var a3 := WorkChainScene.actor(lw3.life)
	lw3.select(a3.id)
	WorkChainScene.trigger(lw3.life, "schmelzen")
	var heater_pos: Vector3 = (ctx3.heaters[int(lw3.life.workshop["heater"])] as TestHeater).position
	var mold_id := int(lw3.life.workshop["mold"])
	for i in 60 * 260:
		await physics_frame
		var ra3: GameAction = ctx3.executor.running.get(a3.id, null)
		if ra3 == null:
			if ctx3.work.active(a3) == null and i > 60:
				break
			continue
		var an3: Dictionary = ra3.state.get("anim", {})
		var ph3 := str(an3.get("phase", ""))
		var u3 := float(an3.get("u", 0.0))
		if not _shots.has("12_kupfer_in_den_tiegel") and ra3.type == "put_into_container" and ph3 == "work" and u3 > 0.5:
			_look(lw3, a3.position + Vector3(0, 0.3, 0), 1.5, -0.35, a3.heading + PI * 0.5)
			await _shot("12_kupfer_in_den_tiegel")
		elif not _shots.has("13_testofen_bedienen") and ra3.type == "place_in_heater" and ph3 == "work" and u3 > 0.5:
			_look(lw3, (a3.position + heater_pos) * 0.5 + Vector3(0, 0.3, 0), 1.8, -0.35, a3.heading + PI * 0.5)
			await _shot("13_testofen_bedienen")
		elif not _shots.has("14_giesst") and ra3.type == "pour_into_mold" and ph3 == "work" and u3 > 0.5:
			_look(lw3, a3.position + Vector3(0, 0.3, 0), 1.5, -0.35, a3.heading + PI * 0.5)
			await _shot("14_giesst")
	var mold: MaterialPiece = ctx3.material_pieces.get(mold_id, null)
	if mold != null:
		_look(lw3, mold.position + Vector3(0, 0.05, 0), 0.9, -0.9, 0.5)
	lw3._refresh_ui()
	await _shot("15_guss_in_der_form")
	lw3.queue_free()
	await process_frame
	LivingWorld.pending = {}
	quit(0)
