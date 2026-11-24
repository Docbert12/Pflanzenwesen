extends SceneTree
## Erzeugt einen ECHTEN Spielstand der Testwerkstatt mit dem aktuellen Code als Prüfling für
## Migrationstests: Verbundwerkzeug (Versuch 2 abgeschlossen), Verfahrenswissen, laufender
## Heizversuch (Versuch 5, Kupfer im Tiegel wird gerade erhitzt). Wird VOR einer Formatänderung
## ausgeführt, damit der Prüfling wirklich vom alten Programmstand stammt (Prompt 6B: Format 4).
## godot --headless --path . -s res://tools/make_workshop_fixture.gd -- <ziel.json> [heizsekunden]

func _initialize() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://saves/fixture_werkstatt.json"
	var heat_s := float(args[1]) if args.size() > 1 else 15.0
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
	var r := life.new_workshop(int(db.config("world").get("seed", 12345)), false)
	if not r.get("ok", false):
		printerr(r)
		quit(1)
		return
	var dt := 1.0 / 60.0
	var a := life.ctx.creature(int(life.workshop["a"]))
	var t2 := TestWorkshop.trigger(life, 2)
	print("Versuch 2: ", t2.get("message", ""))
	for i in int(120.0 / dt):
		life.step(dt)
		if life.ctx.experiments.active(a) == null:
			break
	print("Verbünde: ", life.ctx.assemblies.size())
	var t5 := TestWorkshop.trigger(life, 5)
	print("Versuch 5: ", t5.get("message", ""))
	for i in int(heat_s / dt):
		life.step(dt)
	var s := SaveManager.save(life, out)
	print(s["message"])
	print("Format ", SaveSchema.FORMAT_VERSION, " | Definitionen ", SaveSchema.definitions_fingerprint()["hash"], " | Version ", ProjectSettings.get_setting("application/config/version"))
	life.dispose()
	quit(0 if s["ok"] else 1)
