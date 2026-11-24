class_name PlaceInHeaterAction
extends ActionImpl
## Einen unterstützten Behälter (Tiegel) in die extern versorgte Testheizung (params.heater) setzen.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("heater").get("place_s", 1.5))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var hid := int(a.params.get("heater", 0))
	if not ctx.heaters.has(hid):
		return ActionResult.fail("no_heater", "Keine Heizung #%d bekannt." % hid)
	var h: TestHeater = ctx.heaters[hid]
	if h.slot_id != 0:
		return ActionResult.fail("heater_full", "Heizung #%d ist belegt." % hid)
	var top := ConstructionSystem.top_id(ctx, a.target_id)
	if top == 0:
		return ActionResult.fail("target_lost", "Behälter #%d fehlt." % a.target_id)
	a.target_id = top
	var has_cup := false
	for p in ConstructionSystem.parts_of(ctx, top):
		if (p as MaterialPiece).shape == "cup":
			has_cup = true
	if not has_cup:
		return ActionResult.fail("no_container", "Nur ein Tiegel darf in die Heizung.")
	if cr.held_object_id != top:
		var g := ToolUseSystem.check_grasp(ctx, cr, top)
		if not g.ok:
			return g
		var r0 := TechActionUtil.check_reach(ctx, cr, top)
		if not r0.ok:
			return r0
	if ctx.distance_xz(cr.position, h.position) > TechActionUtil.reach_m(ctx):
		return ActionResult.fail("out_of_reach", "Heizung #%d außer Reichweite." % hid)
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var cr := ctx.creature(a.actor_id)
	var g := ConstructionSystem.grip_piece(ctx, a.target_id)
	if g != null and g.temperature_k() > ToolUseSystem.safe_k(ctx):
		ToolUseSystem.touch_burn(ctx, cr, g, 0.25, "heißer Tiegelgriff")
		return ActionResult.fail("too_hot", "Griff zu heiß.")
	var r := ToolUseSystem.place_in_heater(ctx, cr, a.target_id, int(a.params["heater"]))
	if not r["ok"]:
		return ActionResult.fail(str(r["code"]), str(r["message"]))
	a.consumed = {"heater": int(a.params["heater"]), "object": a.target_id}
	return ActionResult.success(str(r["message"]), {"done": true})
