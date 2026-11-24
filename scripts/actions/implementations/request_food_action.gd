class_name RequestFoodAction
extends ActionImpl
## Um Nahrung bitten: sichtbare Geste (1,5 s) gegenüber einem lebenden Wesen in ≤ 3 m.
## Erzeugt nach Abschluss eine offene Bitte (SocialInteractionSystem) und das Ereignis „food_requested“.
## Eine Bitte ist kein Zwang: der Empfänger entscheidet selbst (DecisionSystem des Empfängers).
## Wartezeiten verhindern Bitte-Ablehnung-Schleifen (allgemein + je Ziel).

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.m("social").get("request_duration_s", 1.5))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var t := ctx.creature(a.target_id)
	if t == null or not t.alive or t.id == cr.id:
		return ActionResult.fail("target_lost", "Kein lebendes anderes Wesen als Ziel.")
	var now := ctx.now()
	if now < float(cr.social.get("next_request_t", 0.0)):
		return ActionResult.fail("cooldown", "Bittet erst wieder ab t=%.0f s." % float(cr.social["next_request_t"]))
	if now < float(cr.social["target_cooldown"].get(t.id, 0.0)):
		return ActionResult.fail("cooldown_target", "Bittet #%d erst wieder ab t=%.0f s." % [t.id, float(cr.social["target_cooldown"][t.id])])
	return _range(a, ctx)


func _range(a: GameAction, ctx: LifeContext) -> ActionResult:
	var r := float(ctx.m("social").get("request_range_m", 3.0))
	var d := ctx.distance_xz(ctx.creature(a.actor_id).position, ctx.creature(a.target_id).position)
	if d > r:
		return ActionResult.fail("out_of_reach", "Ziel %.1f m entfernt (Bitten nur bis %.1f m)." % [d, r])
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	var t := ctx.creature(a.target_id)
	if t == null or not t.alive:
		return ActionResult.fail("target_lost", "Ziel nicht mehr verfügbar.")
	return _range(a, ctx)


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var cr := ctx.creature(a.actor_id)
	var now := ctx.now()
	var sc: Dictionary = ctx.m("social")
	var rid := ctx.social.create_request(cr.id, a.target_id, now)
	cr.social["next_request_t"] = now + float(sc.get("request_cooldown_s", 15.0))
	a.consumed = {"request_id": rid}
	ctx.publish({"type": "food_requested", "actor": cr.id, "target": a.target_id, "position": cr.position,
		"consequences": {"request_id": rid}, "visibility_m": float(ctx.m("observation").get("gesture_visibility_m", 10.0))})
	return ActionResult.success("Bitte an #%d gestellt." % a.target_id, {"done": true})


func power_w(_a: GameAction, _ctx: LifeContext) -> float:
	return 1.0
