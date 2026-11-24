extends SceneTree
## Entwicklerwerkzeug: Bildschirmfotos der Testwerkstatt (mit Grafik ausführen, nicht --headless):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . -s res://tools/capture_workshop.gd
## Löst die Versuche 2 (Verbinden), 4 (Kupfer verformen) und 5 (Schmelzen und Gießen) GEZIELT aus –
## die Bilder zeigen Darstellung und Ansichten, keine spontane Entdeckung. Ohne Ollama.

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_werkstatt_%s.png" % name)
	print("gespeichert: ", ProjectSettings.globalize_path("user://screenshot_werkstatt_%s.png" % name))


func _look(lw: LivingWorld, p: Vector3, dist: float, pitch: float = -0.45) -> void:
	lw.camera.target = p
	lw.camera.distance = dist
	lw.camera.pitch = pitch
	lw.camera._apply()


func _wait_exp(lw: LivingWorld, cr: Creature, max_frames: int) -> void:
	for i in max_frames:
		await physics_frame
		if lw.life.ctx.experiments.active(cr) == null:
			return


func _run() -> void:
	root.size = Vector2i(1600, 900)
	LivingWorld.ai_service_override = AIService.disabled()
	LivingWorld.pending = {"mode": "workshop"}
	var lw: LivingWorld = load(LivingWorld.SCENE).instantiate()
	lw.save_path = "user://saves/_capture_werkstatt.json"
	root.add_child(lw)
	for i in 30:
		await physics_frame
	var ctx := lw.life.ctx
	var w: Dictionary = lw.life.workshop
	var a: Creature = ctx.creature(int(w["a"]))
	var center: Vector3 = ctx.position_of(int(w["copper_sample"]))
	_look(lw, center + Vector3(0, 0.3, 0), 3.2)
	await _shot("1_ausruestung")
	TestWorkshop.trigger(lw.life, 2)
	await _wait_exp(lw, a, 60 * 30)
	lw.select(a.id)
	_look(lw, a.position + Vector3(0, 0.45, 0), 1.6, -0.3)
	await _shot("2_werkzeug_in_der_hand")
	TestWorkshop.trigger(lw.life, 4)
	await _wait_exp(lw, a, 60 * 60)
	var cu: MaterialPiece = ctx.material_pieces[int(w["copper_sample"])]
	_look(lw, cu.position + Vector3(0, 0.1, 0), 0.8, -0.5)
	lw._exp.object_id = a.held_object_id
	lw._exp.visible = true
	lw._refresh_ui()
	await _shot("3_verformte_probe_und_versuchsansicht")
	lw._exp.visible = false
	lw._know.visible = true
	lw._refresh_ui()
	await _shot("4_wissensansicht")
	lw._know.visible = false
	TestWorkshop.trigger(lw.life, 5)
	var melt: MaterialPiece = ctx.material_pieces[int(w["melt"])]
	var shot_melt := false
	for i in 60 * 200:
		await physics_frame
		if not shot_melt and melt.liquid_fraction() >= 1.0:
			shot_melt = true
			_look(lw, ctx.position_of(int(w["crucible"])) + Vector3(0, -0.12, 0), 1.1, -0.55)
			await _shot("5_schmelze_im_tiegel")
		if ctx.experiments.active(a) == null:
			break
	_look(lw, ctx.position_of(int(w["mold"])) + Vector3(0, 0.02, 0), 0.45, -1.05)
	await _shot("6_guss_in_der_form")
	lw.queue_free()
	await process_frame
	quit(0)
