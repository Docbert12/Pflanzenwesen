extends SceneTree
## Entwicklerwerkzeug: Bildschirmfotos der Weltvorschau (mit Grafik ausführen, nicht --headless).

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://screenshot_world_%s.png" % name)
	print("gespeichert: ", ProjectSettings.globalize_path("user://screenshot_world_%s.png" % name))


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var wp = load("res://scenes/world_preview.tscn").instantiate()
	root.add_child(wp)
	for i in 30:
		await physics_frame
	await _shot("1_uebersicht")
	# Nahansicht Lebensbaum
	var tp: Vector3 = wp.tree_info["position"]
	wp.camera.target = tp + Vector3(0, 3.0, 0)
	wp.camera.distance = 16.0
	wp.camera.pitch = -0.25
	wp.camera.yaw = 0.9
	wp.camera._apply()
	await _shot("2_lebensbaum")
	# Überhang bauen und abbrechen lassen
	var w: VoxelWorld = wp.world
	var base: Vector3i = w.generated["tree_cell"] + Vector3i(7, 0, 0)
	var soil := w.palette.id_of("soil")
	for y in 3:
		w.set_voxel(base + Vector3i(0, y, 0), soil)
	for x in range(1, 4):
		w.set_voxel(base + Vector3i(x, 2, 0), soil)
	w.flush_rebuilds()
	w.set_voxel(base + Vector3i(0, 1, 0), 0)   # Stütze entfernen
	w.flush_rebuilds()
	wp.camera.target = Vector3(base) * w.data.cell_size + Vector3(1.2, 1.2, 0)
	wp.camera.distance = 7.0
	wp.camera.pitch = -0.25
	wp.camera.yaw = -0.9
	wp.camera._apply()
	for i in 12:
		await physics_frame
	await _shot("3_bruchstueck")
	# See
	var lk: Array = w.cfg["lake"]["center"]
	wp.camera.target = Vector3(lk[0], 9, lk[1]) * w.data.cell_size
	wp.camera.distance = 14.0
	wp.camera.pitch = -0.55
	wp.camera.yaw = -0.6
	wp.camera._apply()
	await _shot("4_see")
	var menu = load("res://scenes/main.tscn").instantiate()
	wp.queue_free()
	root.add_child(menu)
	await _shot("0_startbildschirm")
	quit(0)
