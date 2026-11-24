class_name OfferFoodAction
extends ActionImpl
## Unaufgeforderte Portion anbieten: Portion wird reserviert und sichtbar hingehalten („food_offered“).
## Übergabe, sobald der Empfänger in ≤ 1,4 m ist und nach EIGENER Bewertung annimmt
## (SocialInteractionSystem.would_accept); sonst nach offer_timeout_s Fehlschlag „not_accepted“.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.m("social").get("offer_timeout_s", 10.0))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if cr.carried_item_id == 0 or not ctx.items.has(cr.carried_item_id):
		return ActionResult.fail("nothing_carried", "Trägt keine Nahrung.")
	var t := ctx.creature(a.target_id)
	if t == null or not t.alive or t.id == cr.id:
		return ActionResult.fail("target_lost", "Kein lebendes anderes Wesen als Ziel.")
	if ctx.distance_xz(cr.position, t.position) > float(ctx.m("social").get("request_range_m", 3.0)):
		return ActionResult.fail("out_of_reach", "Zu weit entfernt zum Anbieten.")
	return ActionResult.success()


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var res := ctx.executor.reserve_carried(cr.id, a.id, cr.carried_item_id)
	if res == 0:
		return ActionResult.fail("unavailable", "Portion ist bereits reserviert.")
	a.reservation_id = res
	a.state["item"] = cr.carried_item_id
	ctx.social.stats["offers"] += 1
	ctx.publish({"type": "food_offered", "actor": cr.id, "target": a.target_id, "position": cr.position,
		"consequences": {"kg": ctx.items[cr.carried_item_id].mass_kg}})
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var t := ctx.creature(a.target_id)
	if t == null or not t.alive:
		return ActionResult.fail("target_lost", "Empfänger nicht mehr verfügbar.")
	if cr.carried_item_id != int(a.state.get("item", -1)) or not ctx.items.has(cr.carried_item_id):
		return ActionResult.fail("target_lost", "Portion nicht mehr in der Hand.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var t := ctx.creature(a.target_id)
	a.progress = clampf(a.elapsed_s / estimate_s(a, ctx), 0.0, 1.0)
	if ctx.distance_xz(cr.position, t.position) <= float(ctx.m("social").get("give_range_m", 1.4)):
		var acc := SocialInteractionSystem.would_accept(t, cr.id, ctx)
		if acc["ok"]:
			ctx.social.stats["offers_accepted"] += 1
			return GiveFoodAction.transfer(a, ctx)
		a.state["last_refusal"] = acc["reason"]
	if a.elapsed_s >= estimate_s(a, ctx):
		ctx.publish({"type": "offer_not_accepted", "actor": cr.id, "target": t.id, "position": cr.position, "consequences": {}})
		return ActionResult.fail("not_accepted", "Angebot nicht angenommen (%s)." % str(a.state.get("last_refusal", "Empfänger kam nicht in Reichweite")))
	return ActionResult.success()

