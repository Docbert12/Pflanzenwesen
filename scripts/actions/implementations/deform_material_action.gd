class_name DeformMaterialAction
extends ActionImpl
## Ein Materialstück durch mehrere Schläge verformen (params.strikes, Standard aus technology.json).
## Unterbrechbar: jeder ausgeführte Schlag bleibt wirksam; nach Abbruch bleibt der Zwischenzustand.

func _n(a: GameAction, ctx: LifeContext) -> int:
	return clampi(int(a.params.get("strikes", ctx.tc("strike").get("deform_default_strikes", 12))), 1, int(ctx.tc("strike").get("max_strikes_per_action", 30)))


func estimate_s(a: GameAction, ctx: LifeContext) -> float:
	var sw := ToolUseSystem.swing(ctx, ctx.creature(a.actor_id), ctx.creature(a.actor_id).held_object_id)
	return float(sw.get("duration_s", 1.0)) * _n(a, ctx) + 0.5


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if not ctx.material_pieces.has(a.target_id):
		return ActionResult.fail("target_lost", "Ziel #%d ist kein Materialstück." % a.target_id)
	var t: MaterialPiece = ctx.material_pieces[a.target_id]
	if a.target_id == cr.held_object_id or (t.assembly_id != 0 and t.assembly_id == cr.held_object_id):
		return ActionResult.fail("self_target", "Kann nicht das gehaltene Werkzeug bearbeiten.")
	if t.liquid_fraction() > 0.0:
		return ActionResult.fail("liquid", "Flüssiges Material lässt sich nicht schlagend verformen.")
	if t.carrier_id != 0:
		return ActionResult.fail("held_by_other", "Ziel wird gehalten.")
	var r := TechActionUtil.check_reach(ctx, cr, a.target_id)
	if not r.ok:
		return r
	var sw := ToolUseSystem.swing(ctx, cr, cr.held_object_id)
	if not sw["ok"]:
		return ActionResult.fail(str(sw["code"]), str(sw["message"]))
	return ActionResult.success()


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	return TechActionUtil.reserve_objects(ctx, a, [a.target_id])


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	return TechActionUtil.strike_series(a, ctx, _n(a, ctx), true, dt)


func cleanup(a: GameAction, ctx: LifeContext) -> void:
	TechActionUtil.release_objects(ctx, a)


func power_w(a: GameAction, _ctx: LifeContext) -> float:
	return TechActionUtil.strike_power(a)
