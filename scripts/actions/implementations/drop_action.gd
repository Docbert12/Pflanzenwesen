class_name DropAction
extends ActionImpl
## Getragenen Gegenstand am eigenen Standort ablegen. Ohne getragene Nahrung (oder mit
## params.object = true) wird der gehaltene Gegenstand/das Werkzeug abgelegt (Prompt 6).

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.c("actions").get("drop_s", 0.5))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if (bool(a.params.get("object", false)) or cr.carried_item_id == 0) and cr.held_object_id != 0:
		a.state["object"] = true
		a.target_id = cr.held_object_id
		return ActionResult.success()
	if cr.carried_item_id == 0 or not ctx.items.has(cr.carried_item_id):
		return ActionResult.fail("nothing_carried", "Trägt nichts.")
	a.target_id = cr.carried_item_id
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if a.state.get("object", false):
		return ActionResult.success() if ConstructionSystem.is_object(ctx, a.target_id) else ActionResult.fail("target_lost", "Gegenstand existiert nicht mehr.")
	if not ctx.items.has(a.target_id):
		return ActionResult.fail("target_lost", "Gegenstand existiert nicht mehr.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var cr := ctx.creature(a.actor_id)
	if a.state.get("object", false):
		var oid := ToolUseSystem.release(ctx, cr, "abgelegt")
		a.consumed = {"dropped_object": oid}
		return ActionResult.success("", {"done": true})
	var it: FoodItem = ctx.items[a.target_id]
	it.carrier_id = 0
	it.position = cr.position + Vector3(0, 0.05, 0)
	cr.carried_item_id = 0
	a.consumed = {"dropped_kg": it.mass_kg}
	return ActionResult.success("", {"done": true})
