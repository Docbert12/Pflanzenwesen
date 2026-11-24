class_name DeclineRequestAction
extends ActionImpl
## Eine Bitte sichtbar ablehnen (1 s). params.request_id. Erzeugt „request_declined“.
## Sichtbar ist dabei, ob der Ablehnende eine Portion trägt (had_food) – sonst nichts über Gründe.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.m("social").get("decline_duration_s", 1.0))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var t := ctx.creature(a.target_id)
	if t == null:
		return ActionResult.fail("target_lost", "Bittender existiert nicht.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var cr := ctx.creature(a.actor_id)
	var rid := int(a.params.get("request_id", 0))
	ctx.social.resolve(rid, "declined")
	ctx.publish({"type": "request_declined", "actor": cr.id, "target": a.target_id, "position": cr.position,
		"consequences": {"request_id": rid, "had_food": cr.carried_item_id != 0}})
	return ActionResult.success("Bitte von #%d abgelehnt." % a.target_id, {"done": true})
