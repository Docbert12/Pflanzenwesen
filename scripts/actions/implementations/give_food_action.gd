class_name GiveFoodAction
extends ActionImpl
## Getragene Portion übergeben (1 s), Empfänger ≤ 1,4 m. Die Portion ist während der Übergabe
## reserviert (nicht essbar, nicht anderweitig vergebbar). Übertragung atomar: Träger wechselt,
## beim Geber abgezogen. Der Empfänger muss annehmen können (freie Hand) und wollen (eigene Bewertung).
## params.request_id: beantwortete Bitte (optional).

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.m("social").get("give_duration_s", 1.0))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if cr.carried_item_id == 0 or not ctx.items.has(cr.carried_item_id):
		return ActionResult.fail("nothing_carried", "Trägt keine Nahrung.")
	return _check(a, ctx)


func _check(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var t := ctx.creature(a.target_id)
	if t == null or not t.alive or t.id == cr.id:
		return ActionResult.fail("target_lost", "Empfänger nicht verfügbar.")
	var r := float(ctx.m("social").get("give_range_m", 1.4))
	var d := ctx.distance_xz(cr.position, t.position)
	if d > r:
		return ActionResult.fail("out_of_reach", "Empfänger %.1f m entfernt (Übergabe bis %.1f m)." % [d, r])
	var acc := SocialInteractionSystem.would_accept(t, cr.id, ctx)
	if not acc["ok"]:
		return ActionResult.fail("not_accepted", "Empfänger nimmt nicht an: %s." % acc["reason"])
	return ActionResult.success()


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var res := ctx.executor.reserve_carried(cr.id, a.id, cr.carried_item_id)
	if res == 0:
		return ActionResult.fail("unavailable", "Portion ist bereits reserviert.")
	a.reservation_id = res
	a.state["item"] = cr.carried_item_id
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if cr.carried_item_id != int(a.state.get("item", -1)) or not ctx.items.has(cr.carried_item_id):
		return ActionResult.fail("target_lost", "Portion nicht mehr in der Hand.")
	return _check(a, ctx)


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	return transfer(a, ctx)


## Gemeinsame atomare Übergabe (auch von OfferFoodAction genutzt).
static func transfer(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var t := ctx.creature(a.target_id)
	var it: FoodItem = ctx.items[cr.carried_item_id]
	ctx.executor.release(a.reservation_id, "übergeben")
	a.reservation_id = 0
	it.carrier_id = t.id
	cr.carried_item_id = 0
	t.carried_item_id = it.id
	cr.social["holding_for_sharing"] = false
	a.consumed = {"given_kg": it.mass_kg, "item_id": it.id, "to": t.id}
	var rid := int(a.params.get("request_id", 0))
	if rid != 0:
		ctx.social.resolve(rid, "given")
	ctx.publish({"type": "food_given", "actor": cr.id, "target": t.id, "position": cr.position,
		"consequences": {"kg": it.mass_kg, "item": it.id, "request_id": rid}})
	return ActionResult.success("Portion %.2f kg an #%d übergeben." % [it.mass_kg, t.id], {"done": true})
