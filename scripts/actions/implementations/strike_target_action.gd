class_name StrikeTargetAction
extends ActionImpl
## Ein einzelner Schlag mit dem gehaltenen Gegenstand (oder der bloßen Hand) auf ein Materialstück.
## Wirkung, Verschleiß und Verbindungsbelastung berechnet ToolUseSystem.strike.

func estimate_s(a: GameAction, ctx: LifeContext) -> float:
	var sw := ToolUseSystem.swing(ctx, ctx.creature(a.actor_id), ctx.creature(a.actor_id).held_object_id)
	return float(sw.get("duration_s", 1.0)) + 0.1


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if not ctx.material_pieces.has(a.target_id):
		return ActionResult.fail("target_lost", "Ziel #%d ist kein Materialstück." % a.target_id)
	var t: MaterialPiece = ctx.material_pieces[a.target_id]
	if t.assembly_id != 0 and t.assembly_id == cr.held_object_id:
		return ActionResult.fail("self_target", "Kann nicht auf das eigene Werkzeug schlagen.")
	if a.target_id == cr.held_object_id:
		return ActionResult.fail("self_target", "Kann nicht auf den gehaltenen Gegenstand schlagen.")
	var r := TechActionUtil.check_reach(ctx, cr, a.target_id)
	if not r.ok:
		return r
	var sw := ToolUseSystem.swing(ctx, cr, cr.held_object_id)
	if not sw["ok"]:
		return ActionResult.fail(str(sw["code"]), str(sw["message"]))
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	return TechActionUtil.strike_series(a, ctx, 1, true)


func power_w(a: GameAction, _ctx: LifeContext) -> float:
	return TechActionUtil.strike_power(a)
