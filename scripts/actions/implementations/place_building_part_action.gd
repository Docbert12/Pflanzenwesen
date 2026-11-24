class_name PlaceBuildingPartAction
extends ActionImpl
## Prompt 6B (Name wie in Prompt 9 vorgesehen): Gehaltenes Stück an einer Baustelle (target = Bauwerk-ID)
## auf einen freien Platz setzen. Prüft Bauplan (Material, Form, Masse), Untergrund (vereinfachte
## Abstützung) und Platzbelegung. Ablauf: Anlauf → bücken → setzen (Verbauen genau einmal) → aufrichten.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("structures").get("place_s", 1.6)) + float(ctx.tc("motion").get("approach_budget_s", 2.5)) + 0.6


func _slot(a: GameAction, s: Structure) -> int:
	var i := int(a.params.get("slot", -1))
	return i if i >= 0 else StructureSystem.next_free_slot(s)


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var s: Structure = ctx.structures.get(a.target_id, null)
	if s == null:
		return ActionResult.fail("no_site", "Keine Baustelle #%d." % a.target_id)
	if cr.held_object_id == 0:
		return ActionResult.fail("nothing_held", "Hält kein Bauteil.")
	var i := _slot(a, s)
	if i < 0 or i >= s.slots.size():
		return ActionResult.fail("site_complete", "Baustelle #%d hat keinen freien Platz mehr." % s.id)
	if int(s.slots[i].get("part_id", 0)) != 0:
		return ActionResult.fail("slot_taken", "Platz %d ist bereits belegt." % (i + 1))
	var chk := StructureSystem.check_part(ctx, s, cr.held_object_id)
	if not chk.ok:
		return chk
	var g := StructureSystem.check_ground(ctx, StructureSystem.slot_world(s, i))
	if not g.ok:
		return g
	if ctx.distance_xz(cr.position, StructureSystem.slot_world(s, i)) > TechActionUtil.reach_m(ctx) + 0.3:
		return ActionResult.fail("out_of_reach", "Bauplatz außer Reichweite.")
	a.state["slot_i"] = i
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if not ctx.structures.has(a.target_id):
		return ActionResult.fail("no_site", "Baustelle existiert nicht mehr.")
	if ctx.creature(a.actor_id).held_object_id == 0 and not a.state.get("placed", false):
		return ActionResult.fail("nothing_held", "Bauteil ist nicht mehr in der Hand.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var s: Structure = ctx.structures[a.target_id]
	var i := int(a.state.get("slot_i", _slot(a, s)))
	var w := StructureSystem.slot_world(s, i)
	var mc := WorkMotion.mc(ctx)
	if not a.state.has("piece"):
		a.state["piece"] = cr.held_object_id
	var h := (ctx.material_pieces[int(a.state["piece"])] as MaterialPiece).dims_m.y if ctx.material_pieces.has(int(a.state["piece"])) else 0.05
	var tt := Vector3(w.x, w.y + h * 0.5 + 0.02, w.z)
	if not a.state.get("approached", false):
		var ap := WorkMotion.approach(a, ctx, dt, tt, "place", 0.0)
		if ap["blocked"]:
			return ActionResult.fail("blocked", str(ap["reason"]))
		if not ap["done"]:
			return ActionResult.success()
		a.state["approached"] = true
		a.state["t0"] = a.elapsed_s
	var work_s := float(ctx.tc("structures").get("place_s", 1.6))
	var ph := WorkMotion.phase_at(a.elapsed_s, float(a.state["t0"]), float(mc.get("prepare_s", 0.25)), work_s, float(mc.get("recover_s", 0.3)))
	WorkMotion.set_anim(a, "place_two" if cr.hold_mode == "two" and not a.state.get("placed", false) else "place", str(ph["phase"]), float(ph["u"]), tt, {"object": int(a.state["piece"]), "slot": i})
	a.progress = clampf((a.elapsed_s - float(a.state["t0"])) / (work_s + float(mc.get("prepare_s", 0.25))), 0.0, 1.0)
	if str(ph["phase"]) == "recover" and not a.state.get("placed", false):
		if int(s.slots[i].get("part_id", 0)) != 0:
			return ActionResult.fail("slot_taken", "Platz %d wurde inzwischen belegt." % (i + 1))
		var chk := StructureSystem.check_part(ctx, s, cr.held_object_id)
		if not chk.ok:
			return chk
		var pid := ToolUseSystem.release_at(ctx, cr, w, "verbaut in Bauwerk #%d" % s.id)
		StructureSystem.place(ctx, s, i, ctx.material_pieces[pid], cr.id)
		a.state["placed"] = true
		a.consumed = {"structure": s.id, "slot": i + 1, "piece": pid, "kg": (ctx.material_pieces[pid] as MaterialPiece).mass_kg, "status": s.status}
	if ph["done"]:
		return ActionResult.success("#%d auf Platz %d von Bauwerk #%d gesetzt (%s)." % [int(a.consumed.get("piece", 0)), i + 1, s.id, s.status], {"done": true})
	return ActionResult.success()
