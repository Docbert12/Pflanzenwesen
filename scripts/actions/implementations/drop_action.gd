class_name DropAction
extends ActionImpl
## Getragenen Gegenstand am eigenen Standort ablegen. Ohne getragene Nahrung (oder mit
## params.object = true) wird der gehaltene Gegenstand/das Werkzeug abgelegt (Prompt 6).
## Prompt 6B: Gegenstände werden sichtbar abgelegt (bücken → absetzen → aufrichten); der Ablagepunkt
## ist der Kontaktpunkt der Ablegebewegung vor dem Wesen (WorkPose), nicht ein Sprung an die Füße.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.c("actions").get("drop_s", 0.5)) + float(ctx.tc("motion").get("put_down_s", 0.7)) + 0.6


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


## Ablagepunkt der Ablegebewegung (Boden vor der Hand) – dieselbe Geometrie wie die Animation.
static func put_down_point(ctx: LifeContext, cr: Creature, obj_id: int) -> Vector3:
	var h := 0.0
	for p in ConstructionSystem.parts_of(ctx, obj_id):
		h = maxf(h, (p as MaterialPiece).dims_m.y)
	var side := cr.hold_side if cr.hold_side != "" else str(cr.caps.get("grasp_side", "r"))
	var b := WorkPose.body(cr.plan, side)
	var pose := WorkPose.contact(b, 0.0, h * 0.5 + 0.02, "place")
	var local := Vector3(0.0 if cr.hold_mode == "two" else float(b["sx"]), 0.0, maxf(0.15, float(pose.get("reach_z", 0.25))))
	var w := WorkPose.to_world(cr.position, cr.heading, local)
	var gy := cr.position.y
	if ctx.nav != null and ctx.nav.in_bounds(ctx.nav.world_to_col(w)) and ctx.nav.is_walkable(ctx.nav.world_to_col(w)):
		gy = ctx.nav.ground_y(ctx.nav.world_to_col(w))
	return Vector3(w.x, gy + 0.01, w.z)


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if a.state.get("object", false):
		var mc := WorkMotion.mc(ctx)
		var work_s := float(mc.get("put_down_s", 0.7))
		var ph := WorkMotion.phase_at(a.elapsed_s, 0.0, float(mc.get("prepare_s", 0.25)), work_s, float(mc.get("recover_s", 0.3)))
		var pt: Vector3 = put_down_point(ctx, cr, a.target_id) if not a.state.has("pt") else Vector3(a.state["pt"][0], a.state["pt"][1], a.state["pt"][2])
		a.state["pt"] = [pt.x, pt.y, pt.z]
		WorkMotion.set_anim(a, "put_down" if cr.hold_mode != "two" or a.state.get("released", false) else "put_down_two", str(ph["phase"]), float(ph["u"]), pt, {"object": a.target_id})
		a.progress = clampf(a.elapsed_s / (work_s + float(mc.get("prepare_s", 0.25)) + float(mc.get("recover_s", 0.3))), 0.0, 1.0)
		if str(ph["phase"]) == "recover" and not a.state.get("released", false):
			var oid := ToolUseSystem.release_at(ctx, cr, pt, "abgelegt")
			a.state["released"] = true
			a.consumed = {"dropped_object": oid, "position": a.state["pt"]}
		if ph["done"]:
			return ActionResult.success("#%d abgelegt." % int(a.consumed.get("dropped_object", a.target_id)), {"done": true})
		return ActionResult.success()
	var d := float(ctx.c("actions").get("drop_s", 0.5))
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var it: FoodItem = ctx.items[a.target_id]
	it.carrier_id = 0
	it.position = cr.position + Vector3(0, 0.05, 0)
	cr.carried_item_id = 0
	a.consumed = {"dropped_kg": it.mass_kg}
	return ActionResult.success("", {"done": true})
