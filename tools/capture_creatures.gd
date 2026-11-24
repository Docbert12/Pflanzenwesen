extends SceneTree
## Entwicklerwerkzeug: Bildschirmfotos der Kreaturenvorschau + 50-Figuren-Messung
## (mit Grafik ausführen, nicht --headless).

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String, frames: int = 3) -> void:
	for i in frames:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_creature_%s.png" % name)
	print("gespeichert: ", ProjectSettings.globalize_path("user://screenshot_creature_%s.png" % name))


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var cp = load("res://scenes/tools/creature_preview.tscn").instantiate()
	root.add_child(cp)
	await _shot("1_einzeln", 10)
	cp.camera.target = Vector3(0, 0.62, 0)
	cp.camera.distance = 1.0
	cp.camera.yaw = 0.0
	cp.camera.pitch = -0.05
	cp.camera._apply()
	await _shot("2_gesicht")
	cp.side = "l"
	cp.remove_forearm()
	cp.prosthesis_material = "copper"
	cp.attach_prosthesis()
	cp.add_leaf()
	cp.side = "l"
	cp.play("eat")
	cp.camera.target = Vector3(0, 0.45, 0)
	cp.camera.distance = 1.8
	cp.camera.yaw = -0.5
	cp.camera._apply()
	await _shot("3_prothese_essen", 40)
	cp.play("grasp")
	await _shot("4_hakengriff", 40)
	cp.show_variants(10)
	await _shot("5_zehn_varianten", 10)
	cp.show_variants(50)
	for i in 200:
		await process_frame
	await _shot("6_fuenfzig", 2)
	print("PERF ", JSON.stringify(cp.perf))
	quit(0)
