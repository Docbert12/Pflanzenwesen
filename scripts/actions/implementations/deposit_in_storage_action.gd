class_name DepositInStorageAction
extends ActionImpl
## Prompt 6B: Gehaltenes Stück in einem realen Lager (target = Lager-ID) ablegen. Ablauf: Anlauf zum
## nächsten freien Ablageplatz → bücken → absetzen (Einlagern genau einmal) → aufrichten.
## Kapazität (Masse, Volumen, Platz), Temperatur und Zustand werden geprüft; das Stück bleibt
## dasselbe Weltobjekt mit eigener Temperatur (kein Zusammenführen, keine Teleportation).

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("storage").get("deposit_s", 1.2)) + float(ctx.tc("motion").get("approach_budget_s", 2.5)) + 0.6


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var s: StoragePlace = ctx.storages.get(a.target_id, null)
	if s == null:
		return ActionResult.fail("no_storage", "Kein Lager #%d." % a.target_id)
	if cr.held_object_id == 0:
		return ActionResult.fail("nothing_held", "Hält nichts zum Einlagern.")
	var acc := StorageSystem.check_accept(ctx, s, cr.held_object_id)
	if not acc.ok:
		return acc
	var reach := TechActionUtil.reach_m(ctx) + maxf(s.size_m.x, s.size_m.y) * 0.5
	if ctx.distance_xz(cr.position, s.position) > reach:
		return ActionResult.fail("out_of_reach", "Lager #%d außer Reichweite (%.1f m)." % [s.id, ctx.distance_xz(cr.position, s.position)])
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if not ctx.storages.has(a.target_id):
		return ActionResult.fail("no_storage", "Lager existiert nicht mehr.")
	if ctx.creature(a.actor_id).held_object_id == 0 and not a.state.get("done_put", false):
		return ActionResult.fail("nothing_held", "Stück ist nicht mehr in der Hand.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var s: StoragePlace = ctx.storages[a.target_id]
	var mc := WorkMotion.mc(ctx)
	if not a.state.has("slot"):
		var sl = StorageSystem.free_slot(ctx, s)
		if sl == null:
			return ActionResult.fail("storage_full", "Kein freier Platz mehr in Lager #%d." % s.id)
		a.state["slot"] = [sl.x, sl.y, sl.z]
		a.state["piece"] = cr.held_object_id
	var slot := Vector3(a.state["slot"][0], a.state["slot"][1], a.state["slot"][2])
	var h := (ctx.material_pieces[int(a.state["piece"])] as MaterialPiece).dims_m.y if ctx.material_pieces.has(int(a.state["piece"])) else 0.05
	var tt := Vector3(slot.x, s.position.y + h * 0.5 + 0.02, slot.z)
	if not a.state.get("approached", false):
		var ap := WorkMotion.approach(a, ctx, dt, tt, "place", 0.0)
		if ap["blocked"]:
			return ActionResult.fail("blocked", str(ap["reason"]))
		if not ap["done"]:
			return ActionResult.success()
		a.state["approached"] = true
		a.state["t0"] = a.elapsed_s
	var work_s := float(ctx.tc("storage").get("deposit_s", 1.2))
	var ph := WorkMotion.phase_at(a.elapsed_s, float(a.state["t0"]), float(mc.get("prepare_s", 0.25)), work_s, float(mc.get("recover_s", 0.3)))
	WorkMotion.set_anim(a, "place_two" if cr.hold_mode == "two" and not a.state.get("done_put", false) else "place", str(ph["phase"]), float(ph["u"]), tt, {"object": int(a.state["piece"])})
	a.progress = clampf((a.elapsed_s - float(a.state["t0"])) / (work_s + float(mc.get("prepare_s", 0.25))), 0.0, 1.0)
	if str(ph["phase"]) == "recover" and not a.state.get("done_put", false):
		var acc := StorageSystem.check_accept(ctx, s, cr.held_object_id)
		if not acc.ok:
			return acc
		var pid := ToolUseSystem.release_at(ctx, cr, slot, "eingelagert in Lager #%d" % s.id)
		StorageSystem.put_in(ctx, s, ctx.material_pieces[pid], slot, cr.id)
		a.state["done_put"] = true
		a.consumed = {"storage": s.id, "piece": pid, "kg": (ctx.material_pieces[pid] as MaterialPiece).mass_kg, "material": (ctx.material_pieces[pid] as MaterialPiece).material_id}
	if ph["done"]:
		return ActionResult.success("#%d in Lager #%d eingelagert." % [int(a.consumed.get("piece", 0)), s.id], {"done": true})
	return ActionResult.success()
