extends SceneTree
## Entwicklerprobe (Prompt 6B): Testszene Werkzeugkette aufbauen, eine Kette gezielt auslösen und den
## Ablauf protokollieren. godot --headless --path . -s res://tools/probe_work_chain.gd -- --goal=lagern [--secs=400]

const DT := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var goal := "lagern"
	var secs := 400.0
	var case := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--goal="):
			goal = a.substr(7)
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a.begins_with("--case="):
			case = a.substr(7)
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
	print("Wesen #%d Masse %.1f kg, Tragegrenze eine Hand %.2f kg, zwei Hände %.2f kg, Hände %d" % [cr.id, cr.mass_kg, ToolUseSystem.carry_limit_kg(cr, life.ctx), ToolUseSystem.carry_limit_two_kg(cr, life.ctx), ToolUseSystem.grasp_hands(cr)])
	for k in life.workshop:
		var id := int(life.workshop[k])
		var p: MaterialPiece = life.ctx.material_pieces.get(id, null)
		if p != null:
			print("  %s #%d %s %.3f kg bei %s (Abstand %.2f m)" % [k, id, p.material_id, p.mass_kg, str(p.position), life.ctx.distance_xz(cr.position, p.position)])
	print("Bekannt: ", cr.tech.get("objects", {}).keys())
	var tr: Dictionary
	if "--auto" in OS.get_cmdline_user_args():
		# Vorgeschichte gezielt (bauen), dann neues Material und eigenes Verhalten an
		WorkChainScene.trigger(life, "bauen")
		for i in int(400.0 / DT):
			life.step(DT)
			if life.ctx.work.active(cr) == null:
				break
		print("Vorgeschichte: ", life.ctx.work.of_creature(cr.id)[0].status, " Verfahren: ", cr.tech["procedures"].keys())
		var amb := life.ctx.sim.thermal.ambient_temperature_k
		ConstructionSystem.new_piece(life.ctx, "stone", "block", Vector3(0.1, 0.1, 0.1), amb, TestWorkshop._ground(life, cr.position + Vector3(1.2, 0, -1.6)), "test_equipment", "Großer Stein (neu)", true)
		ConstructionSystem.new_piece(life.ctx, "stone", "block", Vector3(0.07, 0.07, 0.07), amb, TestWorkshop._ground(life, cr.position + Vector3(-1.4, 0, 1.2)), "test_equipment", "Stein (neu)", true)
		WorkChainScene.look_around(life)
		cr.behavior_enabled = true
		print("Persönlichkeit: ", cr.personality.describe(life.ctx.mind_cfg))
		for k in life.ctx.assemblies:
			print("Verbund #%d Kopf %d Verbindungen %s" % [k, (life.ctx.assemblies[k] as Assembly).head_part_id, str((life.ctx.assemblies[k] as Assembly).connections)])
		tr = {"message": "autonom"}
	elif case != "":
		tr = WorkChainScene.trigger_case(life, case)
	else:
		tr = WorkChainScene.trigger(life, goal)
	print("Auslösen: ", tr.get("message", tr))
	var t := 0.0
	var last_log := 0
	var last_print := -10.0
	var wc: WorkChain = null
	var last_res := ""
	while t < secs:
		life.step(DT)
		t += DT
		var lr := JSON.stringify(cr.last_result)
		if lr != last_res and "--verbose" in OS.get_cmdline_user_args():
			last_res = lr
			print("    · %.2f Handlung: %s %s (%s) %s | Pos %s" % [t, str(cr.last_result.get("type")), str(cr.last_result.get("status")), str(cr.last_result.get("code")), str(cr.last_result.get("message")), str(cr.position)])
		wc = life.ctx.work.active(cr)
		var all := life.ctx.work.of_creature(cr.id)
		var w: WorkChain = all[0] if not all.is_empty() else null
		if w != null:
			while last_log < w.log.size():
				print("  [%.1f] %s" % [float(w.log[last_log]["t"]), str(w.log[last_log]["text"])])
				last_log += 1
		if t - last_print >= 10.0:
			last_print = t
			var v := life.ctx.work.status_view(cr, life.ctx)
			if not v.is_empty():
				print("t=%.0f %s | %s | Schritt %s | Werkzeug %d | Ziel %d | getragen %.2f | transportiert %.2f | %s" % [t, v["status"], v["handlung"], v["schritt"], int(v["werkzeug"]), int(v["zielobjekt"]), float(v["getragen_kg"]), float(v["transportiert_kg"]), v["abbruchgrund"]])
		if wc == null and w != null and not w.is_open() and not cr.behavior_enabled:
			print("Kette beendet: %s – %s (t=%.1f)" % [w.status, w.abort_reason, t])
			print("Ergebnis: ", JSON.stringify(w.result))
			break
		if cr.behavior_enabled and int(t / DT) % 600 == 0:
			print("    t=%.0f Entscheidung: %s · %s · Hunger %.0f %%" % [t, str(cr.decision.get("chosen", "")), str(cr.decision.get("options", []).slice(0, 4)), cr.metabolism.hunger() * 100])
	var audit := life.audit()
	print("Prüfung: ", "ok" if audit.is_empty() else str(audit))
	life.dispose()
	quit(0)
