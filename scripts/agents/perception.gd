class_name Perception
extends RefCounted
## Einfache Wahrnehmung (kein episodisches Gedächtnis):
## - Reichweite: perception.radius_m (Excel: Wahrnehmung 10 m) × Fähigkeit „perception“ (Kopf).
## - Sichtprüfung: Voxel-Strahl von Augenhöhe zum Ziel; feste Zelle dazwischen → nicht sichtbar.
## - Merkliste: Ziel-ID → Position, gesehene verfügbare Menge, Zeitpunkt; verfällt nach memory_s.
## - Ein Wesen kennt nur, was es gesehen hat – nie automatisch alle Quellen der Karte.
## - Ereignisse (Prompt 4): broadcast() verteilt einen Weltfakt als Observation nur an Wesen in
##   Reichweite mit Sichtlinie; Beteiligte nehmen ihre eigene Beteiligung immer wahr (Qualität 1).

static func scan(cr: Creature, ctx: LifeContext) -> void:
	var pc: Dictionary = ctx.c("perception")
	var radius := float(pc.get("radius_m", 10.0)) * float(cr.caps.get("perception", 1.0))
	var eye := cr.position + Vector3(0, float(pc.get("eye_height_m", 0.75)), 0)
	var now := ctx.now()
	cr.visible_food.clear()
	for fid in ctx.foods:
		var f: FoodSource = ctx.foods[fid]
		var dist := eye.distance_to(f.position + Vector3(0, 0.3, 0))
		if dist > radius:
			continue
		if not _line_of_sight(ctx, eye, f.position + Vector3(0, 0.3, 0), dist):
			continue
		cr.visible_food.append(fid)
		if f.amount_kg <= 1e-6:
			cr.food_memory.erase(fid)      # gesehen: leer
			continue
		cr.food_memory[fid] = {"pos": [f.position.x, f.position.y, f.position.z], "available_kg": f.available_kg(), "seen_t": now, "kind": f.kind}
	for iid in ctx.items:
		var it: FoodItem = ctx.items[iid]
		if it.carrier_id != 0:
			continue
		var dist2 := eye.distance_to(it.position)
		if dist2 <= radius and _line_of_sight(ctx, eye, it.position + Vector3(0, 0.1, 0), dist2):
			cr.visible_food.append(iid)
			cr.food_memory[iid] = {"pos": [it.position.x, it.position.y, it.position.z], "available_kg": it.mass_kg, "seen_t": now, "kind": "item"}
	# Sichtbare andere Wesen (nächste 8): Position, ob sie sichtbar etwas tragen; Vertrautheit wächst leicht
	cr.visible_creatures.clear()
	var vis: Array = []
	for oid in ctx.nearby_creatures(cr.position, radius):
		if oid == cr.id:
			continue
		var o: Creature = ctx.creatures[oid]
		var d := ctx.distance_xz(cr.position, o.position)
		if d > radius:
			continue
		vis.append({"id": oid, "d": d})
	vis.sort_custom(func(a, b): return a["d"] < b["d"])
	for v in vis.slice(0, 8):
		var o2: Creature = ctx.creatures[v["id"]]
		var tp := o2.position + Vector3(0, 0.5, 0)
		if not _line_of_sight(ctx, eye, tp, eye.distance_to(tp)):
			continue
		cr.visible_creatures.append({"id": o2.id, "d": v["d"], "alive": o2.alive, "carrying": o2.carried_item_id != 0})
		if o2.alive and ctx.mind_cfg.size() > 0:
			cr.relations.ensure(cr, o2, now, ctx.mind_cfg)
			cr.relations.touch(o2.id, 0.003, now, ctx.mind_cfg)
	var mem_s := float(pc.get("memory_s", 120.0))
	for k in cr.food_memory.keys():
		if now - float(cr.food_memory[k]["seen_t"]) > mem_s or (not ctx.foods.has(k) and not ctx.items.has(k)):
			cr.food_memory.erase(k)
	for k in cr.unreachable.keys():
		if now > float(cr.unreachable[k]):
			cr.unreachable.erase(k)


static func _line_of_sight(ctx: LifeContext, from: Vector3, to: Vector3, dist: float) -> bool:
	var hit := ctx.world.raycast(from, to - from, dist)
	return not hit["hit"] or float(hit["distance"]) >= dist - 0.35


## Verteilt ein Ereignis an alle Wesen, die es wahrnehmen können. Effizienz: nur Kandidaten aus dem
## räumlichen Raster im Sichtbarkeitsradius, je Kandidat höchstens ein Voxel-Strahl.
static func broadcast(ctx: LifeContext, ev: Dictionary) -> void:
	var oc: Dictionary = ctx.m("observation")
	var pos: Vector3 = ev.get("position", Vector3.ZERO)
	var vis := float(ev.get("visibility_m", oc.get("gesture_visibility_m", 10.0)))
	var qmin := float(oc.get("quality_min", 0.15))
	var radius_base := float(ctx.c("perception").get("radius_m", 10.0))
	var eye_h := float(ctx.c("perception").get("eye_height_m", 0.75))
	var actor := int(ev.get("actor", 0))
	var target := int(ev.get("target", 0))
	var stats: Dictionary = ctx.observation_stats
	stats["events"] = int(stats.get("events", 0)) + 1
	for oid in ctx.nearby_creatures(pos, vis):
		var cr: Creature = ctx.creatures[oid]
		if not cr.alive:
			continue
		var q := 0.0
		if oid == actor or oid == target:
			q = float(oc.get("self_quality", 1.0))
		else:
			var reach := minf(vis, radius_base * float(cr.caps.get("perception", 1.0)))
			var eye := cr.position + Vector3(0, eye_h, 0)
			var tp := pos + Vector3(0, 0.4, 0)
			var dist := eye.distance_to(tp)
			if dist > reach:
				continue
			stats["raycasts"] = int(stats.get("raycasts", 0)) + 1
			if not _line_of_sight(ctx, eye, tp, dist):
				continue
			q = clampf((1.0 - 0.6 * dist / maxf(reach, 0.1)) * float(cr.caps.get("perception", 1.0)), 0.0, 1.0)
		if q < qmin:
			continue
		var o := Observation.new()
		o.observer_id = oid
		o.t = ctx.now()
		o.event_type = str(ev["type"])
		o.actor_id = actor
		o.target_id = target
		o.participants = [actor, target].filter(func(x): return x != 0)
		o.position = pos
		o.consequences = ev.get("consequences", {}).duplicate(true)
		o.quality = q
		o.event_seq = int(ev.get("seq", 0))
		stats["observations"] = int(stats.get("observations", 0)) + 1
		ctx.last_observers.append({"id": oid, "q": snappedf(q, 0.01)})
		LearningSystem.on_observation(cr, o, ctx)
