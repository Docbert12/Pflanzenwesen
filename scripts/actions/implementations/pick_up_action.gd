class_name PickUpAction
extends ActionImpl
## Eine Portion (Bissen) von einer Nahrungsquelle oder einen Gegenstand vom Boden aufnehmen.
## Ablauf: Reservierung beim Start → Greifbewegung (Dauer / Greiffähigkeit) →
## atomare Übergabe (Menge der Quelle sinkt, neuer getragener Gegenstand entsteht).

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.c("actions").get("pick_up_s", 1.0)) * 2.0


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if cr.carried_item_id != 0:
		return ActionResult.fail("hands_full", "Trägt bereits etwas.")
	if cr.held_object_id != 0 and ToolUseSystem.free_hands(cr) <= 0:
		return ActionResult.fail("hands_full", "Hält #%d – keine freie Hand für Nahrung." % cr.held_object_id)
	var r := _check_target(a, ctx)
	if not r.ok:
		return r
	var reach := float(ctx.c("food").get("reach_m", 1.1))
	if ctx.distance_xz(cr.position, ctx.position_of(a.target_id)) > reach:
		return ActionResult.fail("out_of_reach", "Ziel ist weiter als %.1f m entfernt." % reach)
	if ctx.foods.has(a.target_id):
		var f: FoodSource = ctx.foods[a.target_id]
		var kg := minf(float(ctx.c("food").get("bite_kg", 0.1)), f.available_kg())
		if kg <= 1e-9:
			return ActionResult.fail("unavailable", "Keine freie Menge mehr (aufgebraucht oder reserviert).")
		a.resource_needs = {"food_kg": kg}
	else:
		var it: FoodItem = ctx.items[a.target_id]
		if it.carrier_id != 0 or it.reserved_by != 0:
			return ActionResult.fail("unavailable", "Gegenstand wird bereits getragen oder ist reserviert.")
		a.resource_needs = {"food_kg": it.mass_kg}
	return ActionResult.success()


func _check_target(a: GameAction, ctx: LifeContext) -> ActionResult:
	if not ctx.foods.has(a.target_id) and not ctx.items.has(a.target_id):
		return ActionResult.fail("target_lost", "Ziel #%d existiert nicht (mehr)." % a.target_id)
	return ActionResult.success()


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var res := ctx.executor.reserve(a.actor_id, a.id, a.target_id, float(a.resource_needs["food_kg"]))
	if res == 0:
		return ActionResult.fail("unavailable", "Reservierung nicht möglich (Menge vergeben).")
	a.reservation_id = res
	var caps: Dictionary = ctx.creature(a.actor_id).caps
	a.state["side"] = caps.get("grasp_side", "r")
	a.state["duration_s"] = float(ctx.c("actions").get("pick_up_s", 1.0)) / maxf(0.2, float(caps.get("grasp", 1.0)))
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	var r := _check_target(a, ctx)
	if not r.ok:
		return r
	if not ctx.executor.reservations.has(a.reservation_id):
		return ActionResult.fail("reservation_lost", "Reservierung ist nicht mehr gültig.")
	var reach := float(ctx.c("food").get("reach_m", 1.1))
	if ctx.distance_xz(ctx.creature(a.actor_id).position, ctx.position_of(a.target_id)) > reach + 0.2:
		return ActionResult.fail("out_of_reach", "Ziel außer Reichweite geraten.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := float(a.state.get("duration_s", 1.0))
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var cr := ctx.creature(a.actor_id)
	if cr.carried_item_id != 0:
		# Hände inzwischen belegt (z. B. Portion während des Aufnehmens übergeben bekommen)
		return ActionResult.fail("hands_full", "Trägt inzwischen bereits eine Portion (#%d)." % cr.carried_item_id)
	if ctx.foods.has(a.target_id):
		var f: FoodSource = ctx.foods[a.target_id]
		var kg := f.take_reserved(a.reservation_id, float(a.resource_needs["food_kg"]))
		if kg <= 0.0:
			return ActionResult.fail("unavailable", "Menge war bei der Übergabe nicht mehr vorhanden.")
		var it := ctx.create_item(f.props(), kg, cr.id, cr.position, f.id)
		cr.carried_item_id = it.id
		ctx.ledger.taken_from_sources_kg += kg
		a.consumed = {"taken_kg": kg, "item_id": it.id, "source_remaining_kg": f.amount_kg}
		ctx.publish({"type": "food_taken", "actor": cr.id, "position": f.position, "consequences": {"kg": kg, "source": f.id, "item": it.id, "remaining_kg": f.amount_kg}})
	else:
		var it2: FoodItem = ctx.items[a.target_id]
		it2.carrier_id = cr.id
		it2.reserved_by = 0
		cr.carried_item_id = it2.id
		a.consumed = {"picked_item_kg": it2.mass_kg}
		ctx.publish({"type": "food_taken", "actor": cr.id, "position": cr.position, "consequences": {"kg": it2.mass_kg, "item": it2.id, "vom_boden": true}})
	return ActionResult.success("", {"done": true})
