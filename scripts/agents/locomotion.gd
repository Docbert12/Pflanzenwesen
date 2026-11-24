class_name Locomotion
extends RefCounted
## Bewegung entlang eines Spaltenwegs im festen Physiktakt.
## Kollisionsprüfung gegen die Voxeldaten: Vor dem Betreten jeder Spalte werden Begehbarkeit und
## Stufenhöhe erneut geprüft (Terrain kann sich geändert haben) → sonst „blockiert“.
## Die Höhe folgt dem Boden der aktuellen Spalte (geglättet). Animationen verändern die Position nie.
## Einfache Ausweichregel: Abstoßung von Wesen im Radius avoid_radius_m, nur in begehbare Spalten.

static func assign_path(cr: Creature, path: Array, final_target: Vector3, _ctx: LifeContext) -> void:
	cr.path = path
	cr.path_i = 0
	cr.path_target = final_target
	cr.moving = path.size() > 0


static func stop(cr: Creature) -> void:
	cr.path = []
	cr.path_i = 0
	cr.moving = false
	cr.speed_now = 0.0


## Rückgabe {"moved_m", "blocked", "reason", "arrived_path_end"}
static func step(cr: Creature, ctx: LifeContext, dt: float) -> Dictionary:
	var res := {"moved_m": 0.0, "blocked": false, "reason": "", "arrived_path_end": false}
	var nav := ctx.nav
	var speed := cr.speed_m_s(ctx)
	if speed <= 0.0:
		res["blocked"] = true
		res["reason"] = "keine Fortbewegung möglich"
		return res
	var remaining := speed * dt
	var moved := 0.0
	while remaining > 1e-6 and cr.path_i < cr.path.size():
		var col: Vector2i = cr.path[cr.path_i]
		var cur := nav.world_to_col(cr.position)
		if col != cur:
			if not nav.is_walkable(col):
				res["blocked"] = true
				res["reason"] = "Spalte %s: %s" % [str(col), nav.why_not_walkable(col)]
				break
			if not nav.can_step(cur, col):
				res["blocked"] = true
				res["reason"] = "Stufe zu hoch zwischen %s und %s" % [str(cur), str(col)]
				break
		var tp := nav.col_center(col)
		if cr.path_i == cr.path.size() - 1 and cr.path_target != null and nav.world_to_col(cr.path_target) == col:
			tp = Vector3(cr.path_target.x, tp.y, cr.path_target.z)
		var to := Vector2(tp.x - cr.position.x, tp.z - cr.position.z)
		var dist := to.length()
		if dist <= remaining:
			cr.position.x = tp.x
			cr.position.z = tp.z
			remaining -= dist
			moved += dist
			cr.path_i += 1
		else:
			var stepv := to / dist * remaining
			cr.position.x += stepv.x
			cr.position.z += stepv.y
			moved += remaining
			remaining = 0.0
		if dist > 1e-4:
			cr.heading = atan2(to.x, to.y)
	if cr.path_i >= cr.path.size():
		res["arrived_path_end"] = true
	_avoid(cr, ctx, dt)
	var gy := nav.ground_y(nav.world_to_col(cr.position))
	cr.position.y = move_toward(cr.position.y, gy, maxf(2.5 * dt, absf(gy - cr.position.y) * 0.25))
	res["moved_m"] = moved
	cr.tick_moved_m += moved
	cr.speed_now = moved / maxf(dt, 1e-9)
	cr.stats["distance_m"] = float(cr.stats.get("distance_m", 0.0)) + moved
	return res


static func _avoid(cr: Creature, ctx: LifeContext, dt: float) -> void:
	var r := float(ctx.c("locomotion").get("avoid_radius_m", 0.45))
	var push := Vector2.ZERO
	for other_id in ctx.nearby_creatures(cr.position, r):
		if other_id == cr.id:
			continue
		var o: Creature = ctx.creatures[other_id]
		if not o.alive:
			continue
		var dv := Vector2(cr.position.x - o.position.x, cr.position.z - o.position.z)
		var dl := dv.length()
		if dl < r:
			push += (dv / maxf(dl, 0.01)) * (r - dl) if dl > 0.001 else Vector2(cos(cr.id), sin(cr.id)) * r
	if push == Vector2.ZERO:
		return
	var off := push.limit_length(0.6 * dt)
	var np := cr.position + Vector3(off.x, 0, off.y)
	var nc := ctx.nav.world_to_col(np)
	if ctx.nav.is_walkable(nc) and ctx.nav.can_step(ctx.nav.world_to_col(cr.position), nc):
		cr.position = np
