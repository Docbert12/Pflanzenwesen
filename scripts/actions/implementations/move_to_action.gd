class_name MoveToAction
extends ActionImpl
## Zu einer Position gehen. Weg über NavigationService (Raster-A* auf Terrainspalten,
## begrenzte Knotenzahl), Bewegung über Locomotion im festen Physiktakt.
## params.arrive_radius_m: Ziel gilt als erreicht innerhalb dieses Abstands (Standard 0,15 m).
## Blockierter Weg → begrenzte Neuplanung (navigation.max_replans), danach erklärter Fehlschlag.

func estimate_s(a: GameAction, ctx: LifeContext) -> float:
	var cr := ctx.creature(a.actor_id)
	var spd := maxf(0.1, cr.speed_m_s(ctx))
	return ctx.distance_xz(cr.position, a.target_pos) * 1.6 / spd + 3.0


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	if a.target_pos == null:
		return ActionResult.fail("no_target", "Keine Zielposition.")
	var col := ctx.nav.world_to_col(a.target_pos)
	if not ctx.nav.in_bounds(col):
		return ActionResult.fail("out_of_world", "Ziel liegt außerhalb der Welt.")
	return ActionResult.success()


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	a.state["replans"] = 0
	a.state["need_path"] = true
	var cr := ctx.creature(a.actor_id)
	a.state["start_dist"] = maxf(0.01, ctx.distance_xz(cr.position, a.target_pos))
	return ActionResult.success()


func _plan(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if not ctx.nav.take_request_budget():
		return ActionResult.success("", {"deferred": true})   # nächster Takt
	var r := ctx.nav.find_path(ctx.nav.world_to_col(cr.position), ctx.nav.world_to_col(a.target_pos), float(a.params.get("arrive_radius_m", 0.0)))
	a.state["need_path"] = false
	a.state["expansions"] = int(a.state.get("expansions", 0)) + int(r["expansions"])
	if not r["ok"]:
		return ActionResult.fail(r["code"], r["reason"])
	Locomotion.assign_path(cr, r["path"], a.target_pos, ctx)
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var arrive := maxf(float(ctx.c("locomotion").get("arrive_m", 0.15)), float(a.params.get("arrive_radius_m", 0.0)))
	if ctx.distance_xz(cr.position, a.target_pos) <= arrive:
		a.progress = 1.0
		Locomotion.stop(cr)
		return ActionResult.success("", {"done": true})
	if a.state.get("need_path", false):
		var pr := _plan(a, ctx)
		if not pr.ok:
			return pr
		if pr.data.get("deferred", false):
			return ActionResult.success()
	var mr := Locomotion.step(cr, ctx, dt)
	if mr["blocked"]:
		var n := int(a.state.get("replans", 0)) + 1
		a.state["replans"] = n
		ctx.log_event("path_blocked", [cr.id], {"replan": n, "reason": mr["reason"]}, "warning")
		if n > int(ctx.c("navigation").get("max_replans", 2)):
			return ActionResult.fail("path_blocked", "Weg mehrfach blockiert (%s); %d Neuplanungen erfolglos." % [mr["reason"], n - 1])
		a.state["need_path"] = true
		return ActionResult.success()
	if mr["arrived_path_end"] and ctx.distance_xz(cr.position, a.target_pos) > arrive:
		# Wegende erreicht, Ziel selbst nicht betretbar (z. B. Nahrung auf Nachbarspalte)
		if ctx.distance_xz(cr.position, a.target_pos) <= float(a.params.get("arrive_radius_m", 0.0)) + 0.6:
			Locomotion.stop(cr)
			a.progress = 1.0
			return ActionResult.success("", {"done": true})
		return ActionResult.fail("target_not_reached", "Wegende erreicht, Ziel aber nicht (%.2f m entfernt)." % ctx.distance_xz(cr.position, a.target_pos))
	var sd := float(a.state.get("start_dist", 1.0))
	a.progress = clampf(1.0 - ctx.distance_xz(cr.position, a.target_pos) / sd, 0.0, 1.0)
	return ActionResult.success()


func cleanup(a: GameAction, ctx: LifeContext) -> void:
	var cr := ctx.creature(a.actor_id)
	if cr != null:
		Locomotion.stop(cr)
