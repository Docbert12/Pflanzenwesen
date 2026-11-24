extends SceneTree
## Entwicklerwerkzeug: Bildschirmfotos des Labors für die Sichtprüfung.
## Nicht Teil des Spiels. Aufruf mit Grafik (nicht --headless), z. B.:
##   godot --path . -s res://tools/capture_screenshots.gd
## Hinweis: Für Bild 2 wird der Schmelzzustand der Kupferprobe direkt gesetzt
## (Energie = halbe Schmelzwärme), damit nicht ~100 s Echtzeit gewartet werden muss.
## Das ist eine inszenierte Prüfaufnahme, kein Simulationsergebnis.

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := "user://screenshot_%s.png" % name
	img.save_png(path)
	print("gespeichert: ", ProjectSettings.globalize_path(path))


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var lab: PhysicsLab = load("res://scenes/tests/physics_lab.tscn").instantiate()
	root.add_child(lab)
	for i in 20:
		await physics_frame
	await _shot("1_uebersicht")
	lab.start_fall_test()
	lab.toggle_contact("Kupfer–Stein")
	lab.toggle_contact("Kupfer–Wasser")
	var melt: PhysicalObject = lab.sim.registry.get_entity(lab.roles["melt"])
	var m := melt.material()
	melt.thermal_energy_j = melt.mass_kg * (m.melt_start_h() + 0.5 * m.latent_heat_fusion)
	lab.toggle_heater()
	lab.selected_id = lab.roles["melt"]
	lab.selected_id = lab.roles["d_stone"]
	lab.load_j = 2000.0
	lab.apply_load_to_selection()
	lab.selected_id = lab.roles["melt"]
	for i in 90:
		await physics_frame
	await _shot("2_betrieb_uebersicht")
	lab.view_station("A")
	await _shot("3_station_A")
	lab.view_station("B")
	await _shot("4_station_B")
	lab.view_station("C")
	await _shot("5_station_C")
	lab.view_station("D")
	await _shot("6_station_D")
	lab.toggle_false_color()
	lab.view_station("B")
	await _shot("7_falschfarbe_B")
	quit(0)
