extends SceneTree
## Vergleichslauf (Alpha 1.1): neues Spiel mit festem Startwert, N Sekunden, dann Prüfsummen des
## Zustands je Bereich. Gleicher Code + gleicher Startwert → gleiche Prüfsummen. Dient dem Nachweis,
## dass ein Umbau das Verhalten nicht verändert (vorher/nachher vergleichen).
## godot --headless --path . -s res://tools/state_hash.gd -- [sekunden=120] [modus=spiel|werkstatt|kette]

const DT := 1.0 / 60.0
const KEYS := ["creatures", "foods", "items", "material_pieces", "assemblies", "storages", "structures", "ledger", "social", "work", "experiments", "communication", "interventions"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := float(args[0]) if args.size() > 0 else 120.0
	var mode := str(args[1]) if args.size() > 1 else "spiel"
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
	life.setup(sim, db, world, objs)
	var seed_v := int(db.config("world").get("seed", 12345))
	if mode == "werkstatt":
		life.new_workshop(seed_v, true)
	elif mode == "kette":
		life.new_work_scene(seed_v, true)
	else:
		life.new_game(seed_v)
	for i in int(secs / DT):
		life.step(DT)
	var snap: Dictionary = SaveManager.snapshot(life)
	var total := ""
	for k in KEYS:
		var h := SaveSchema.sha256_text(JSON.stringify(snap.get(k, null), "", true, true))
		total += h
		print("%-16s %s" % [k, h.substr(0, 16)])
	print("zeit_s          %s" % str(life.ctx.now()))
	print("gelände         %s" % life.world.data.hash_sha256().substr(0, 16))
	print("wasser_m3       %s" % str(life.world.water.total()))
	print("GESAMT          %s" % SaveSchema.sha256_text(total).substr(0, 24))
	life.dispose()
	quit(0)
