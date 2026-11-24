extends SceneTree
## Beobachtungslauf der Testwerkstatt OHNE gezielte Auslöser (eigenständiges Verhalten an).
## Misst, was die Wesen von sich aus tun – es gibt keine Erfolgspflicht.
##   godot --headless --path . -s res://tools/observe_workshop.gd -- 1800 [startwert]
## Ausgabe: Zwischenstände alle 300 s, am Ende Versuche nach Art/Herkunft/Status, Verfahren je Wesen,
## Zeitanteil der Versuche, gegessene Masse, Audit.

const DT := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := float(args[0]) if args.size() > 0 else 1800.0
	var db := DefinitionDB.new()
	db.load_all()
	var seed_v := int(args[1]) if args.size() > 1 else int(db.config("world").get("seed", 12345))
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	root.add_child(sim)
	root.add_child(world)
	root.add_child(objs)
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs)
	var r := life.new_workshop(seed_v, true)
	if not r.get("ok", false):
		printerr("Werkstatt: ", r.get("message", ""))
		quit(1)
		return
	var ctx := life.ctx
	var t := 0.0
	var next_report := 300.0
	var t0 := Time.get_ticks_msec()
	while t < secs:
		life.step(DT)
		t += DT
		if t >= next_report:
			next_report += 300.0
			print("t=%4.0f s  Versuche %s  Audit %d" % [t, str(ctx.experiments.stats), life.audit().size()])
	var kinds := {}
	for id in ctx.experiments.records:
		var rec: ExperimentRecord = ctx.experiments.records[id]
		var why := ""
		if not rec.failures.is_empty():
			var f: Dictionary = rec.failures[-1]
			why = " → %s: %s" % [str(f.get("code", "")), str(f.get("message", "")).substr(0, 90)]
		var who := "A" if rec.actor_id == int(life.workshop["a"]) else "B"
		var k := "%s | Wesen %s | %s | %s%s" % [rec.status, who, rec.source, rec.question.substr(0, 60), why]
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("== Ergebnis nach %.0f s Simulationszeit (%.1f s Rechenzeit), Startwert %d ==" % [secs, (Time.get_ticks_msec() - t0) / 1000.0, seed_v])
	print("Statistik: ", ctx.experiments.stats)
	for k in kinds:
		print("  %3d × %s" % [kinds[k], k])
	for role in ["a", "b"]:
		var cr: Creature = ctx.creature(int(life.workshop[role]))
		var share := 0.0
		for bb in cr.tech["budget"]:
			share += float(bb[1]) - float(bb[0])
		print("Wesen %s #%d: lebt %s, Neugier %.2f, Vorsicht %.2f, gegessen %.2f kg, Versuchszeit im letzten Fenster %.0f s, bekannte Gegenstände %d" % [role.to_upper(), cr.id, str(cr.alive),
			cr.personality.v("neugier"), cr.personality.v("vorsicht"), float(cr.metabolism.totals["eaten_kg"]), share, cr.tech["objects"].size()])
		for key in cr.tech["procedures"]:
			var e: Dictionary = cr.tech["procedures"][key]
			print("    Verfahren: %s – %s (eigene Versuche %d, Sicherheit %.2f)" % [ProceduralKnowledge.describe_key(key), str(e["level"]), int(e["own"]["attempts"]), float(e["confidence"])])
	print("Audit: ", life.audit())
	life.dispose()
	quit(0)
