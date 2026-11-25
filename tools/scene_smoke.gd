extends SceneTree
## Startet jede Szene und lässt sie 240 Bilder laufen. Fehler erscheinen in der Konsolenausgabe
## (Aufrufer prüft auf "ERROR"/"SCRIPT ERROR").
## godot --headless --path . -s res://tools/scene_smoke.gd

const SCENES := ["res://scenes/main.tscn", "res://scenes/tests/physics_lab.tscn", "res://scenes/world_preview.tscn",
	"res://scenes/tools/creature_preview.tscn", "res://scenes/living_world.tscn", "res://scenes/tests/mind_lab.tscn"]
## Zusätzlich: Lebenssimulation im Modus Testwerkstatt (Prompt 6) und Testszene Werkzeugkette (Prompt 6B)
const WORKSHOP := "res://scenes/living_world.tscn"
const MODE_NAMES := {"workshop": " [Testwerkstatt]", "werkzeugkette": " [Testszene Werkzeugkette]"}


func _initialize() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var runs: Array = []
	for path in SCENES:
		runs.append([path, "new"])
	runs.append([WORKSHOP, "workshop"])
	runs.append([WORKSHOP, "werkzeugkette"])
	for run in runs:
		var path: String = run[0]
		LivingWorld.pending = {"mode": run[1]}
		var n: Node = load(path).instantiate()
		root.add_child(n)
		for i in 240:
			await process_frame
		print("SZENE OK: %s%s (240 Bilder)" % [path, str(MODE_NAMES.get(run[1], ""))])
		n.queue_free()
		await process_frame
		paused = false
	quit(0)
