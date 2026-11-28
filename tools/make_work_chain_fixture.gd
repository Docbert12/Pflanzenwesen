extends SceneTree
## Erzeugt einen ECHTEN Spielstand der Testszene Werkzeugkette MITTEN in einer Kette als Prüfling für
## Migrationstests (Alpha 1.1: Format 5 aus v0.6.1, erzeugt VOR jeder Codeänderung).
## godot --headless --path . -s res://tools/make_work_chain_fixture.gd -- <ziel.json> [ziel=bauen] [sekunden=40]

const DT := 1.0 / 60.0


func _initialize() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://saves/fixture_werkzeugkette.json"
	var goal := args[1] if args.size() > 1 else "bauen"
	var secs := float(args[2]) if args.size() > 2 else 40.0
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
	life.setup(sim, db, world, objs, AIService.disabled())
	var r := life.new_work_scene(int(db.config("world").get("seed", 12345)), false)
	print("Szene: ", r.get("message", r))
	var cr := WorkChainScene.actor(life)
	var tr := WorkChainScene.trigger(life, goal)
	print("Auslösen: ", tr.get("message", tr))
	for i in int(secs / DT):
		life.step(DT)
	var wc: WorkChain = life.ctx.work.active(cr)
	if wc == null:
		printerr("Keine laufende Kette nach %.0f s – Dauer anpassen" % secs)
		quit(1)
		return
	print("Kette läuft: Ziel %s, Status %s, Protokollzeilen %d" % [goal, str(wc.status), wc.log.size()])
	var s := SaveManager.save(life, out)
	print(s["message"])
	print("Format ", SaveSchema.FORMAT_VERSION, " | Version ", ProjectSettings.get_setting("application/config/version"))
	life.dispose()
	quit(0 if s["ok"] else 1)
