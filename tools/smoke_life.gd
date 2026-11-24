extends SceneTree
## Entwicklerwerkzeug: schneller Durchlauf der Lebenssimulation ohne Oberfläche.
## Aufruf: godot --headless --path . -s res://tools/smoke_life.gd -- [Sekunden]

func _initialize() -> void:
	create_timer(1500.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var secs := 30.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		secs = float(args[0])
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var sim := Simulation.new()
	root3d.add_child(sim)
	sim.initialize()
	sim.set_physics_process(false)
	var world := VoxelWorld.new()
	root3d.add_child(world)
	var objs := Node3D.new()
	root3d.add_child(objs)
	var db := DefinitionDB.new()
	db.load_all()
	var life := LifeSimulation.new()
	if not life.setup(sim, db, world, objs):
		print("SETUP FEHLER ", life.errors)
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var r := life.new_game(int(db.config("world").get("seed", 12345)))
	print("new_game: ", r.get("message"), " in ", Time.get_ticks_msec() - t0, " ms; foods=", life.ctx.foods.size(), " kg=", life.ctx.ledger.initial_kg)
	var c0: Creature = life.ctx.creatures.values()[0]
	print("Wesen0 Masse ", c0.mass_kg, " caps loco ", c0.caps["locomotion"], " leaf ", c0.caps["leaf_area_m2"], " E ", c0.metabolism.energy_j, "/", c0.metabolism.energy_capacity_j)
	var ticks := int(secs * 60)
	t0 = Time.get_ticks_msec()
	for i in ticks:
		life.step(1.0 / 60.0)
		if i % 1800 == 0:
			var s := life.population_summary()
			var memn := 0
			var beln := 0
			for cid in life.ctx.creatures:
				memn += life.ctx.creatures[cid].memory.entries.size()
				beln += life.ctx.creatures[cid].beliefs.items.size()
			print("t=%.0f lebend=%d tot=%d hunger=%.2f nahrung=%.2f speicher=%.1fMB objekte=%d erinnerungen=%d ueberzeugungen=%d states=%s audit=%s" % [s["time_s"], s["alive"], s["dead"], s["avg_hunger"], s["food_kg"],
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_COUNT)), memn, beln, str(s["states"]), str(life.audit().slice(0, 3))])
	var ms := Time.get_ticks_msec() - t0
	print("Ticks ", ticks, " in ", ms, " ms → ", float(ms) / ticks, " ms/Takt; max ", life.perf["max_us"], " µs")
	print("Executor ", life.ctx.executor.stats, " nav ", life.ctx.nav.stats)
	print("Audit: ", life.audit())
	print("Soziales ", life.ctx.social.stats, " Beobachtungen ", life.ctx.observation_stats)
	var hs := {}
	for cid in life.ctx.creatures:
		for c in life.ctx.creatures[cid].ai["hearsay"]:
			hs[c["status"]] = int(hs.get(c["status"], 0)) + 1
	print("Gespräche ", life.ctx.comm.stats, " Hörensagen nach Status ", hs, " KI ", life.ctx.ai.local, " (Anbindung: ", life.ctx.ai.service.status_text(), ")")
	for u in life.ctx.comm.recent(5):
		print("  #%d → #%d [%s, %s] %s" % [u["speaker"], u["listener"], u["intent"], u["status"], u["text"]])
	life.dispose()
	quit(0)
