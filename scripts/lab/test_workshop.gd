class_name TestWorkshop
extends RefCounted
## Testwerkstatt (Prompt 6) – getrennt vom normalen Spiel. Sie stellt AUSDRÜCKLICH platzierte
## Testausrüstung bereit (Steine, Holzstiele, Pflanzenfasern, Kupferproben, Tiegel mit Griff,
## Gussform, extern versorgte Testheizung) und zwei Testwesen. Im normalen Spiel gibt es nichts davon
## (keine versteckten Materialgeschenke, keine verpflichtenden Entdeckungen); dort können Materialien
## nur über das Göttermenü platziert werden.
##
## Versuche 1–6 werden hier GEZIELT AUSGELÖST (Herkunft „Testwerkstatt (gezielt ausgelöst)“). Ein
## gezielt ausgelöster Versuch beweist, dass der Vorgang funktioniert – nicht, dass die Wesen ihn von
## selbst entdecken würden. Für eigenständiges Verhalten gibt es den Beobachtungslauf (Verhalten an).

const SOURCE := "Testwerkstatt (gezielt ausgelöst)"
const LABELS := {
	1: "1 Stein als Werkzeug: Kupferprobe schlagen",
	2: "2 Stiel + Steinkopf mit Fasern verbinden",
	3: "3 Verbundwerkzeug praktisch testen",
	4: "4 Kupferprobe kalt verformen (16 Schläge)",
	5: "5 Kupfer im Tiegel erhitzen und gießen",
	6: "6 Wesen A führt das Verbinden vor, B sieht zu und übt",
}


## Baut Welt, Nahrung, 2 Testwesen und die Testausrüstung. Rückgabe {ok, ids, center, a, b, message}.
static func setup(life: LifeSimulation, world_seed: int, behavior: bool = false) -> Dictionary:
	life.build_world(world_seed)
	life._create_food_sources(world_seed)
	var ctx := life.ctx
	var center := _walkable(life, life.tree_node.position + Vector3(6, 0, 0), 0.0)
	var sr := PopulationSpawner.spawn(ctx, 2, world_seed + 777, center)
	if not sr["ok"]:
		return sr
	var ids := ctx.creatures.keys()
	ids.sort()
	var a: Creature = ctx.creatures[ids[0]]
	var b: Creature = ctx.creatures[ids[1]]
	a.position = center
	b.position = _walkable(life, center + Vector3(-1.6, 0, 0.6), 0.0)
	for cr in [a, b]:
		cr.behavior_enabled = behavior
		cr.heading = 0.0
	var amb := ctx.sim.thermal.ambient_temperature_k
	var o := {}
	var items := [
		["stone_head", "stone", "block", Vector3(0.042, 0.042, 0.042), Vector3(0.45, 0, 0.0), "Stein (faustgroß)"],
		["stone_head2", "stone", "block", Vector3(0.042, 0.042, 0.042), Vector3(-0.9, 0, 0.9), "Stein (faustgroß)"],
		["stone_heavy", "stone", "block", Vector3(0.06, 0.06, 0.06), Vector3(0.6, 0, 0.6), "Stein (schwer)"],
		["stick_a", "wood", "rod", Vector3(0.4, 0.025, 0.025), Vector3(0.3, 0, -0.45), "Holzstiel"],
		["stick_b", "wood", "rod", Vector3(0.4, 0.025, 0.025), Vector3(-1.2, 0, 1.2), "Holzstiel"],
		["fiber", "plant_fiber", "bundle", Vector3(0.12, 0.04, 0.06), Vector3(-0.1, 0, -0.5), "Pflanzenfasern"],
		["fiber2", "plant_fiber", "bundle", Vector3(0.1, 0.035, 0.05), Vector3(-1.4, 0, 0.7), "Pflanzenfasern"],
		["copper_sample", "copper", "block", Vector3(0.02, 0.02, 0.02), Vector3(0.55, 0, -0.25), "Kupferprobe"],
		["copper_sample2", "copper", "block", Vector3(0.02, 0.02, 0.02), Vector3(0.7, 0, 0.15), "Kupferprobe"],
		["copper_sample3", "copper", "block", Vector3(0.02, 0.02, 0.02), Vector3(-1.0, 0, 1.4), "Kupferprobe"],
	]
	for it in items:
		var p := _ground(life, center + (it[4] as Vector3))
		var r := ConstructionSystem.new_piece(ctx, it[1], it[2], it[3], amb, p, "test_equipment", it[5], true)
		if not r["ok"]:
			return {"ok": false, "message": "%s: %s" % [it[0], r["message"]]}
		o[it[0]] = int(r["id"])
	# Tiegel (Keramik) mit Holzgriff – fest montierte Testausrüstung
	var hp := _ground(life, center + Vector3(-0.2, 0, 0.75))
	var cup := ConstructionSystem.new_piece(ctx, "ceramic", "cup", Vector3(0.06, 0.05, 0.06), amb, hp, "test_equipment", "Schmelztiegel", true, 0.04 * 0.04 * 0.04)
	var handle := ConstructionSystem.new_piece(ctx, "wood", "rod", Vector3(0.3, 0.02, 0.02), amb, hp, "test_equipment", "Tiegelgriff", true)
	if not cup["ok"] or not handle["ok"]:
		return {"ok": false, "message": "Tiegel: %s %s" % [cup.get("message", ""), handle.get("message", "")]}
	var fx := ConstructionSystem.connect_fixture(ctx, int(handle["id"]), int(cup["id"]), "Tiegel mit Griff (Testausrüstung)")
	o["crucible"] = int(fx["id"])
	o["cup"] = int(cup["id"])
	var melt := ConstructionSystem.new_piece(ctx, "copper", "block", Vector3(0.025, 0.025, 0.025), amb, hp, "test_equipment", "Kupfer zum Schmelzen", true)
	var mp: MaterialPiece = melt["piece"]
	mp.container_id = int(cup["id"])
	o["melt"] = mp.id
	ctx.sim.thermal.add_contact_g(mp, cup["piece"], float(ctx.tc("heater").get("container_sample_conductance_w_k", 3.0)), "Tiegel #%d↔Probe" % int(cup["id"]), true)
	# Gussform (Keramik) mit Hohlraum 48 × 36 mm Grundfläche, 25 mm tief
	var mold := ConstructionSystem.new_piece(ctx, "ceramic", "mold", Vector3(0.08, 0.04, 0.06), amb, _ground(life, center + Vector3(-0.75, 0, 0.35)),
		"test_equipment", "Gussform", true, 0.048 * 0.036 * 0.025)
	o["mold"] = int(mold["id"])
	# Testheizung (extern versorgt)
	var h := TestHeater.new()
	h.position = _ground(life, center + Vector3(-0.5, 0, 1.0))
	h.power_w = float(ctx.tc("heater").get("power_w", 3500.0))
	ctx.sim.add_entity(h, "test_heater")
	ctx.heaters[h.id] = h
	ctx.sim.thermal.add_heater(h.heater_name(), 0, h.power_w)
	o["heater"] = h.id
	ConstructionSystem.sync_positions(ctx)
	life.next_refill_t = ctx.now() + float(ctx.c("food").get("refill_interval_s", 60.0))
	life.game_ready = true
	life.workshop = o.duplicate()
	life.workshop["a"] = a.id
	life.workshop["b"] = b.id
	ctx.log_event("workshop_created", [a.id, b.id], {"objects": o, "note": "Testausrüstung – nicht im normalen Spiel"}, "warning")
	return {"ok": true, "ids": o, "center": center, "a": a.id, "b": b.id,
		"message": "Testwerkstatt: 2 Testwesen (#%d, #%d), %d Gegenstände, Testheizung #%d." % [a.id, b.id, ctx.material_pieces.size(), h.id]}


static func _walkable(life: LifeSimulation, p: Vector3, min_r: float) -> Vector3:
	var nav := life.ctx.nav
	for r in [min_r, min_r + 0.3, min_r + 0.6, min_r + 1.0, min_r + 1.5, min_r + 2.5]:
		for k in 16:
			var a := k * TAU / 16.0
			var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
			var c := nav.world_to_col(q)
			if nav.in_bounds(c) and nav.is_walkable(c):
				return Vector3(q.x, nav.ground_y(c), q.z)
	return p


static func _ground(life: LifeSimulation, p: Vector3) -> Vector3:
	var nav := life.ctx.nav
	var c := nav.world_to_col(p)
	if nav.in_bounds(c):
		return Vector3(p.x, nav.ground_y(c) + 0.01, p.z)
	return p


## Plan für Versuch n (1–6) aus den Werkstatt-IDs. Rückgabe {} wenn nicht möglich.
static func plan_for(life: LifeSimulation, n: int) -> Dictionary:
	var w: Dictionary = life.workshop
	var ctx := life.ctx
	match n:
		1:
			return {"kind": "deform", "question": "Verformt ein faustgroßer Stein die Kupferprobe?", "expected": "Kupferprobe wird flacher",
				"steps": [{"op": "inspect", "obj": int(w["stone_head"])}, {"op": "equip", "obj": int(w["stone_head"])},
					{"op": "deform", "target": int(w["copper_sample"]), "params": {"strikes": 8}}], "source": SOURCE}
		2:
			return {"kind": "connect", "question": "Hält der Stein am Stiel, wenn ich Fasern darum wickle?", "expected": "Ein Werkzeug aus Stiel und Kopf",
				"steps": [{"op": "release"}, {"op": "connect", "obj": int(w["stick_a"]), "head": int(w["stone_head"]), "fiber": int(w["fiber"])}], "source": SOURCE}
		3:
			var tool := _assembly_with(ctx, int(w["stick_a"]))
			if tool == 0:
				return {}
			return {"kind": "test_tool", "question": "Wirkt das Verbundwerkzeug auf Kupfer?", "expected": "Kupferprobe wird flacher",
				"steps": [{"op": "equip", "obj": tool}, {"op": "deform", "target": int(w["copper_sample2"]), "params": {"strikes": 6}}], "source": SOURCE}
		4:
			var tool2 := _assembly_with(ctx, int(w["stick_a"]))
			var st := [{"op": "deform", "target": int(w["copper_sample"]), "params": {"strikes": 16}}]
			if tool2 != 0:
				st.push_front({"op": "equip", "obj": tool2})
			else:
				st.push_front({"op": "equip", "obj": int(w["stone_head"])})
			return {"kind": "deform", "question": "Wie stark lässt sich die Kupferprobe kalt verformen?", "expected": "deutlich flacher, ohne Schmelzen",
				"steps": st, "source": SOURCE}
		5:
			return {"kind": "cast", "question": "Schmilzt das Kupfer im Tiegel in der Testheizung, und lässt es sich gießen?", "expected": "Gussstück in der Form",
				"steps": [{"op": "release"}, {"op": "heat", "obj": int(w["crucible"]), "heater": int(w["heater"])}, {"op": "wait_molten", "obj": int(w["crucible"])},
					{"op": "pour", "obj": int(w["crucible"]), "mold": int(w["mold"])}], "source": SOURCE}
		6:
			var key := ProceduralKnowledge.lashing_key("wood", "stone")
			return {"kind": "demonstrate", "question": "Kann #%d sehen, wie das Verbinden geht?" % int(w["b"]), "expected": "Zuschauer sieht das Verfahren",
				"steps": [{"op": "offer_demo", "learner": int(w["b"]), "key": key}, {"op": "release"},
					{"op": "demonstrate", "learner": int(w["b"]), "key": key, "handle": int(w["stick_b"]), "head": int(w["stone_head2"]), "fiber": int(w["fiber2"])}],
				"source": SOURCE, "procedure_key": key, "learner": int(w["b"])}
	return {}


static func _assembly_with(ctx: LifeContext, part_id: int) -> int:
	return (ctx.material_pieces[part_id] as MaterialPiece).assembly_id if ctx.material_pieces.has(part_id) else 0


## Löst Versuch n bei Wesen A (6: A führt vor) aus. Wesen B wird für 6 nahe gebracht.
static func trigger(life: LifeSimulation, n: int) -> Dictionary:
	var w: Dictionary = life.workshop
	if w.is_empty():
		return {"ok": false, "message": "Keine Testwerkstatt."}
	var ctx := life.ctx
	var a := ctx.creature(int(w["a"]))
	if a == null or not a.alive:
		return {"ok": false, "message": "Testwesen A fehlt."}
	if ctx.experiments.active(a) != null:
		return {"ok": false, "message": "Wesen A führt noch Versuch #%d durch." % ctx.experiments.active(a).id}
	var plan := plan_for(life, n)
	if plan.is_empty():
		return {"ok": false, "message": "Versuch %d ist jetzt nicht möglich (erst Versuch 2: Werkzeug bauen)." % n}
	if n == 6:
		var b := ctx.creature(int(w["b"]))
		var lk := str(plan["procedure_key"])
		if ProceduralKnowledge.level(a, lk) != "erfolgreich":
			return {"ok": false, "message": "Vorführen setzt eigenen Erfolg voraus – erst Versuch 2 ausführen."}
		if b != null:
			b.position = _walkable(life, a.position + Vector3(-1.2, 0, 0.4), 0.0)
			b.heading = PI * 0.5
			ctx.rebuild_spatial_hash()
			Perception.scan(b, ctx)
			Perception.scan(a, ctx)
	return ctx.experiments.start(a, plan, ctx)


## B übt das Verfahren (nach Versuch 6). Gezielt ausgelöst.
static func trigger_practice(life: LifeSimulation) -> Dictionary:
	var w: Dictionary = life.workshop
	var ctx := life.ctx
	var b := ctx.creature(int(w["b"]))
	var key := ProceduralKnowledge.lashing_key("wood", "stone")
	if b == null or not ProceduralKnowledge.knows(b, key):
		return {"ok": false, "message": "Wesen B kennt das Verfahren noch nicht (erst Versuch 6)."}
	# freie Teile für B: zerlegtes Vorführwerkzeug oder Reste
	var handle := 0
	var free: Array = []
	for id in ctx.material_pieces:
		var p: MaterialPiece = ctx.material_pieces[id]
		if p.assembly_id != 0 or p.carrier_id != 0 or p.container_id != 0:
			continue
		free.append(id)
		if handle == 0 and p.shape == "rod" and p.material_id == "wood" and p.dims_m.x >= 0.35:
			handle = id
	# Kopf und Fasern: jeweils das dem Stiel nächstgelegene passende Teil
	var head := 0
	var fiber := 0
	var dh := INF
	var df := INF
	if handle != 0:
		var hp: Vector3 = ctx.material_pieces[handle].position
		for id in free:
			var p: MaterialPiece = ctx.material_pieces[id]
			var d := hp.distance_to(p.position)
			if p.material_id == "stone" and p.shape == "block" and p.mass_kg < 0.4 and d < dh:
				head = id
				dh = d
			elif p.material_id == "plant_fiber" and p.damage < 1.0 and p.mass_kg >= 0.01 and d < df:
				fiber = id
				df = d
	if handle == 0 or head == 0 or fiber == 0:
		return {"ok": false, "message": "Keine freien Teile zum Üben (Stiel %d, Kopf %d, Fasern %d)." % [handle, head, fiber]}
	b.position = _walkable(life, ctx.material_pieces[handle].position + Vector3(-0.4, 0, 0), 0.0)
	return ctx.experiments.start(b, {"kind": "practice", "question": "Gelingt mir das Verbinden selbst?", "expected": "Kopf hält am Stiel",
		"steps": [{"op": "release"}, {"op": "practice", "key": key, "handle": handle, "head": head, "fiber": fiber}], "source": SOURCE, "procedure_key": key}, ctx)
