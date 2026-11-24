class_name BasicBehavior
extends RefCounted
## Ausführungshilfen für Grundtätigkeiten (Prompt 3), seit Prompt 4 OHNE eigene Entscheidung.
## Einziger Entscheider ist DecisionSystem.decide; diese Funktionen setzen nur eine bereits
## gewählte Option in Handlungsanfragen um (Nahrung aufsuchen/aufnehmen/essen, erkunden, warten).
## Rückgabe jeweils {"ok": bool, "state": String, "reason": String}.


## Nahrung aufsuchen. purpose "eat" (selbst essen) oder "share" (aufnehmen und tragen, nicht essen).
static func pursue_food(cr: Creature, ctx: LifeContext, purpose: String = "eat", max_dist: float = INF) -> Dictionary:
	var reach := float(ctx.c("food").get("reach_m", 1.1))
	var target := choose_food(cr, ctx, max_dist)
	if target == 0:
		return {"ok": false, "state": "", "reason": "keine bekannte erreichbare Nahrung"}
	var pos = ctx.position_of(target)
	var dist := ctx.distance_xz(cr.position, pos)
	var mem: Dictionary = cr.food_memory.get(target, {})
	cr.goal = {"type": "food", "id": target}
	var use_hand: bool = float(cr.caps.get("grasp", 0.0)) > 0.0 and float(cr.caps.get("feeding", 0.0)) > 0.0
	if purpose == "share" and float(cr.caps.get("grasp", 0.0)) <= 0.0:
		return {"ok": false, "state": "", "reason": "kann nichts tragen"}
	if dist <= reach:
		var t := "pick_up" if (use_hand or purpose == "share") else "eat"
		var r2 := ctx.executor.request(cr.id, t, target)
		if r2["result"].ok:
			if purpose == "share":
				cr.social["holding_for_sharing"] = true
			return {"ok": true, "state": "nimmt_auf" if t == "pick_up" else "isst",
				"reason": "Nahrung #%d in Reichweite (%.2f m); %s." % [target, dist, ("nimmt eine Portion zum Tragen/Teilen" if purpose == "share" else ("nimmt einen Bissen auf" if use_hand else "isst direkt mit dem Mund (keine nutzbare Hand)"))]}
		mark_unusable(cr, ctx, target, r2["result"])
		return {"ok": false, "state": "ziel_verworfen", "reason": r2["result"].message}
	var r3 := ctx.executor.request(cr.id, "move_to", 0, Vector3(pos.x, pos.y, pos.z), {"arrive_radius_m": reach * 0.8})
	if r3["result"].ok:
		return {"ok": true, "state": "geht_zu_nahrung", "reason": "Nahrung #%d, %.1f m entfernt, gesehen vor %.0f s%s." % [target, dist, ctx.now() - float(mem.get("seen_t", ctx.now())), " (zum Teilen)" if purpose == "share" else ""]}
	mark_unusable(cr, ctx, target, r3["result"])
	return {"ok": false, "state": "ziel_verworfen", "reason": r3["result"].message}


static func choose_food(cr: Creature, ctx: LifeContext, max_dist: float = INF) -> int:
	var best := 0
	var best_score := INF
	for fid in cr.food_memory:
		if cr.unreachable.has(fid):
			continue
		var m: Dictionary = cr.food_memory[fid]
		if float(m["available_kg"]) <= 1e-6:
			continue
		var p := Vector3(m["pos"][0], m["pos"][1], m["pos"][2])
		var score := ctx.distance_xz(cr.position, p)
		if score < best_score and score <= max_dist:
			best_score = score
			best = fid
	return best


static func nearest_known_food_dist(cr: Creature, ctx: LifeContext) -> float:
	var f := choose_food(cr, ctx)
	if f == 0:
		return INF
	var m: Dictionary = cr.food_memory[f]
	return ctx.distance_xz(cr.position, Vector3(m["pos"][0], m["pos"][1], m["pos"][2]))


static func mark_unusable(cr: Creature, ctx: LifeContext, target: int, r: ActionResult) -> void:
	var until := ctx.now() + float(ctx.c("perception").get("unreachable_blacklist_s", 60.0))
	cr.unreachable[target] = until
	cr.behavior_reason = "Nahrung #%d verworfen bis t=%.0f s: %s" % [target, until, r.message]


static func explore(cr: Creature, ctx: LifeContext, radius: float) -> Dictionary:
	var p = random_walkable(cr, ctx, radius)
	if p == null:
		return {"ok": false, "state": "", "reason": "kein begehbarer Punkt gefunden"}
	var r := ctx.executor.request(cr.id, "move_to", 0, p)
	if r["result"].ok:
		cr.goal = {"type": "explore"}
		return {"ok": true, "state": "erkundet", "reason": "geht zu einem zufälligen begehbaren Punkt (%.1f m)" % ctx.distance_xz(cr.position, p)}
	return {"ok": false, "state": "", "reason": r["result"].message}


static func wait(cr: Creature, ctx: LifeContext, dur: float, state: String, reason: String) -> Dictionary:
	var r := ctx.executor.request(cr.id, "wait", 0, null, {"duration_s": dur})
	return {"ok": r["result"].ok, "state": state, "reason": reason}


static func random_walkable(cr: Creature, ctx: LifeContext, radius: float):
	for i in 8:
		var a := cr.rng.randf() * TAU
		var r := cr.rng.randf_range(radius * 0.4, radius)
		var p := cr.position + Vector3(cos(a) * r, 0, sin(a) * r)
		var col := ctx.nav.world_to_col(p)
		if ctx.nav.is_walkable(col):
			return Vector3(p.x, ctx.nav.ground_y(col), p.z)
	return null
