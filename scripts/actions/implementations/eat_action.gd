class_name EatAction
extends ActionImpl
## Essen. Zwei Arten:
##  A) Getragene Portion essen (braucht Fähigkeit „feeding“: eine Hand führt zum Mund).
##  B) Ohne nutzbare Hand direkt an der Quelle mit dem Mund (Ersatzverhalten,
##     Rate × mouth_only_feeding, mit Reservierung eines Bissens).
## Pro Schritt wird eine tatsächliche Masse von Gegenstand bzw. Quelle abgezogen und dem
## Stoffwechsel zugeführt. Abbruch: Bereits Gegessenes bleibt bilanziert, der Rest bleibt
## im Gegenstand bzw. in der Quelle.

func estimate_s(a: GameAction, ctx: LifeContext) -> float:
	var rate := float(ctx.c("food").get("eat_rate_kg_per_s", 0.02)) * 0.25
	return float(ctx.c("food").get("bite_kg", 0.1)) / rate + 5.0


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var caps: Dictionary = cr.caps
	if cr.carried_item_id != 0 and (a.target_id == 0 or a.target_id == cr.carried_item_id):
		if float(caps.get("feeding", 0.0)) <= 0.0:
			return ActionResult.fail("no_feeding_hand", "Keine Hand, die Nahrung zum Mund führen kann.")
		if (ctx.items[cr.carried_item_id] as FoodItem).reserved_by != 0:
			return ActionResult.fail("item_offered", "Die getragene Portion ist gerade angeboten/zur Übergabe reserviert.")
		a.target_id = cr.carried_item_id
		a.state["mode"] = "carried"
		a.state["side"] = caps.get("feeding_side", "r")
		return ActionResult.success()
	if ctx.foods.has(a.target_id):
		if float(caps.get("feeding", 0.0)) > 0.0 and float(caps.get("grasp", 0.0)) > 0.0:
			return ActionResult.fail("use_pick_up", "Mit Hand: erst aufnehmen, dann essen.")
		var f: FoodSource = ctx.foods[a.target_id]
		var reach := float(ctx.c("food").get("reach_m", 1.1))
		if ctx.distance_xz(cr.position, f.position) > reach:
			return ActionResult.fail("out_of_reach", "Quelle außer Reichweite.")
		var kg := minf(float(ctx.c("food").get("bite_kg", 0.1)), f.available_kg())
		if kg <= 1e-9:
			return ActionResult.fail("unavailable", "Keine freie Menge mehr.")
		a.resource_needs = {"food_kg": kg}
		a.state["mode"] = "direct"
		return ActionResult.success()
	return ActionResult.fail("nothing_to_eat", "Nichts zu essen in der Hand oder als Ziel.")


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	if a.state.get("mode", "") == "direct":
		var res := ctx.executor.reserve(a.actor_id, a.id, a.target_id, float(a.resource_needs["food_kg"]))
		if res == 0:
			return ActionResult.fail("unavailable", "Reservierung nicht möglich.")
		a.reservation_id = res
		a.state["total_kg"] = float(a.resource_needs["food_kg"])
	else:
		a.state["total_kg"] = (ctx.items[a.target_id] as FoodItem).mass_kg
	a.state["eaten_kg"] = 0.0
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if a.state.get("mode", "") == "carried":
		if not ctx.items.has(a.target_id) or cr.carried_item_id != a.target_id:
			return ActionResult.fail("target_lost", "Getragene Nahrung ist nicht mehr vorhanden.")
		if (ctx.items[a.target_id] as FoodItem).reserved_by != 0:
			return ActionResult.fail("item_offered", "Portion ist zur Übergabe reserviert.")
		if float(cr.caps.get("feeding", 0.0)) <= 0.0:
			return ActionResult.fail("no_feeding_hand", "Hand zum Essen nicht mehr verfügbar.")
	else:
		if not ctx.foods.has(a.target_id) or not ctx.executor.reservations.has(a.reservation_id):
			return ActionResult.fail("target_lost", "Quelle oder Reservierung nicht mehr vorhanden.")
		if float(cr.caps.get("mouth", 0.0)) <= 0.0:
			return ActionResult.fail("no_mouth", "Mund nicht mehr funktionsfähig.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var fd: Dictionary = ctx.c("food")
	var rate := float(fd.get("eat_rate_kg_per_s", 0.02))
	var total := float(a.state["total_kg"])
	var eaten := float(a.state["eaten_kg"])
	var props: Dictionary
	var kg: float
	if a.state["mode"] == "carried":
		var it: FoodItem = ctx.items[a.target_id]
		rate *= float(cr.caps.get("feeding", 1.0))
		kg = minf(rate * dt, it.mass_kg)
		it.mass_kg -= kg
		props = it.props()
		if it.mass_kg <= 1e-9:
			kg += maxf(it.mass_kg, 0.0)
			it.mass_kg = 0.0
	else:
		var f: FoodSource = ctx.foods[a.target_id]
		rate *= float(ctx.c("capabilities").get("mouth_only_feeding", 0.25)) * float(cr.caps.get("mouth", 1.0))
		kg = f.take_reserved(a.reservation_id, minf(rate * dt, total - eaten))
		ctx.ledger.taken_from_sources_kg += kg
		props = f.props()
	cr.metabolism.ingest(kg, props, ctx.ledger)
	eaten += kg
	a.state["eaten_kg"] = eaten
	a.consumed = {"eaten_kg": eaten}
	a.progress = clampf(eaten / maxf(total, 1e-9), 0.0, 1.0)
	cr.stats["eaten_kg"] = float(cr.stats.get("eaten_kg", 0.0)) + kg
	if a.state["mode"] == "carried" and (ctx.items[a.target_id] as FoodItem).mass_kg <= 0.0:
		cr.carried_item_id = 0
		ctx.remove_item(a.target_id, "aufgegessen")
		ctx.publish({"type": "food_eaten", "actor": cr.id, "position": cr.position, "consequences": {"kg": eaten}})
		return ActionResult.success("", {"done": true})
	if a.state["mode"] == "direct" and eaten >= total - 1e-9:
		ctx.publish({"type": "food_eaten", "actor": cr.id, "position": cr.position, "consequences": {"kg": eaten, "direkt_an_quelle": true}})
		return ActionResult.success("", {"done": true})
	return ActionResult.success()
