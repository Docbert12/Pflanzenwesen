extends SceneTree
## Erzeugt einen ECHTEN Spielstand mit dem aktuellen Code (Neues Spiel, 50 Wesen, kurze Laufzeit)
## als Prüfling für spätere Migrationstests. Wird VOR einer Formatänderung ausgeführt, damit der
## Prüfling wirklich vom alten Programmstand stammt.
## godot --headless --path . -s res://tools/make_save_fixture.gd -- <ziel.json> [sekunden] [--mit-material]
## --mit-material: legt nach 10 s über das vorhandene Göttermenü je ein Stein-, Holz- und Kupferstück ab
## (normaler Spielweg), damit der Prüfling auch Materialstücke enthält.

func _initialize() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://saves/fixture.json"
	var secs := float(args[1]) if args.size() > 1 else 90.0
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
	if not life.setup(sim, db, world, objs):
		printerr(life.errors)
		quit(1)
		return
	var r := life.new_game(int(db.config("world").get("seed", 12345)))
	if not r.get("ok", false):
		printerr(r)
		quit(1)
		return
	var dt := 1.0 / 60.0
	var with_material := "--mit-material" in args
	for i in int(secs / dt):
		life.step(dt)
		if with_material and i == int(10.0 / dt):
			var ids: Array = life.ctx.creatures.keys()
			ids.sort()
			var k := 0
			for mat in ["stone", "wood", "copper"]:
				var gr := life.ctx.interventions.execute({"kind": "place_material", "target_id": int(ids[k]), "material_id": mat, "size_m": 0.08})
				print("Göttermenü: ", gr["message"])
				k += 7
	var s := SaveManager.save(life, out)
	print(s["message"])
	print("Format ", SaveSchema.FORMAT_VERSION, " | Definitionen ", SaveSchema.definitions_fingerprint()["hash"], " | Version ", ProjectSettings.get_setting("application/config/version"))
	life.dispose()
	quit(0 if s["ok"] else 1)
