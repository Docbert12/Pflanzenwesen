class_name TechActionUtil
extends RefCounted
## Gemeinsame Prüfungen und Teilabläufe der Technik-Handlungen (Prompt 6). Die eigentlichen
## Vorgänge (Schlag, Verbinden, Gießen) liegen in ToolUseSystem / ConstructionSystem /
## MaterialProcessSystem – Handlungen, Vorführung und Übung rufen DIESELBEN Funktionen auf.


static func reach_m(ctx: LifeContext) -> float:
	return float(ctx.tc("hands").get("reach_m", 1.1))


## Objekt (oder Verbund) in Reichweite? Gehaltenes zählt als erreichbar.
static func check_reach(ctx: LifeContext, cr: Creature, id: int) -> ActionResult:
	var top := ConstructionSystem.top_id(ctx, id)
	if top == 0 and not ctx.heaters.has(id):
		return ActionResult.fail("target_lost", "Gegenstand #%d existiert nicht." % id)
	if top != 0 and cr.held_object_id == top:
		return ActionResult.success()
	var p = ctx.position_of(id)
	if p == null:
		return ActionResult.fail("target_lost", "Gegenstand #%d hat keine Position." % id)
	var d := ctx.distance_xz(cr.position, p)
	if d > reach_m(ctx):
		return ActionResult.fail("out_of_reach", "#%d außer Reichweite (%.1f m > %.1f m)." % [id, d, reach_m(ctx)])
	return ActionResult.success()


## Werkzeugform für den Verfahrensschlüssel (aus der Struktur, nicht aus dem Namen).
static func tool_form(ctx: LifeContext, top_id: int) -> String:
	if top_id == 0:
		return "Hand"
	if ctx.assemblies.has(top_id):
		var a: Assembly = ctx.assemblies[top_id]
		return "Stiel+Kopf" if a.head_part_id != 0 else "Stab"
	var mp: MaterialPiece = ctx.material_pieces.get(top_id, null)
	if mp != null and mp.shape == "rod":
		return "Stab"
	return "Stück"


static func strike_key(ctx: LifeContext, cr: Creature, target: MaterialPiece) -> String:
	var sw := ToolUseSystem.swing(ctx, cr, cr.held_object_id)
	var contact := str(sw.get("contact_material", "Hand"))
	return ProceduralKnowledge.strike_key(contact, tool_form(ctx, cr.held_object_id), target.material_id)


## Schlagfolge: n Schläge auf target (Prompt 6B mit Bewegungsphasen):
##   approach: zum Standpunkt gehen, an dem der Werkzeugkopf (bzw. die Hand) beim Kontakt genau auf
##             dem Ziel liegt (WorkPose/WorkMotion) und zum Ziel drehen
##   work:     je Schlag Ausholen über die Schlagdauer; am Ende genau EIN Kontakt (Simulationsereignis)
##   recover:  nach dem letzten Schlag zurück in eine gültige Haltepose
## Jeder Schlag wirkt nur am Kontaktzeitpunkt (a.state.contacts zählt die Kontakte); die Animation
## liest die Phase nur und kann keinen zusätzlichen Schaden auslösen. Unterbrechbar: bereits
## ausgeführte Schläge bleiben wirksam, verbrauchte Energie wird nicht erstattet.
static func strike_series(a: GameAction, ctx: LifeContext, n: int, stop_on_break: bool, dt: float = 1.0 / 60.0) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var target: MaterialPiece = ctx.material_pieces.get(a.target_id, null)
	# Rückkehrphase nach dem letzten Kontakt
	if a.state.has("recover_until"):
		WorkMotion.set_anim(a, "strike", "recover", 1.0 - (float(a.state["recover_until"]) - a.elapsed_s) / maxf(1e-6, float(a.state.get("recover_s", 0.3))), null)
		if a.elapsed_s >= float(a.state["recover_until"]):
			return ActionResult.success(str(a.state.get("final_msg", "")), {"done": true})
		return ActionResult.success()
	if not a.state.get("approached", false):
		if target == null:
			return ActionResult.fail("target_lost", "Ziel existiert nicht mehr.")
		var tool_h := WorkPose.tool_reach(ctx, cr.held_object_id)
		var tt := WorkMotion.target_height(ctx, cr, a.target_id, target.position)
		var ap := WorkMotion.approach(a, ctx, dt, tt, "strike", tool_h)
		if ap["blocked"]:
			return ActionResult.fail("blocked", str(ap["reason"]))
		if not ap["done"]:
			return ActionResult.success()
		a.state["approached"] = true
		a.state["t0"] = a.elapsed_s
		a.state["tool_h"] = tool_h
		a.state["contacts"] = 0
	if not a.state.has("strikes_done"):
		a.state["strikes_done"] = 0
		a.state["log"] = []
		a.state["mech_j"] = 0.0
		a.state["thickness0"] = target.dims_m.y if target != null else 0.0
		a.state["strain0"] = target.strain if target != null else 0.0
		a.state["damage0"] = target.damage if target != null else 0.0
		a.state["tool0"] = cr.held_object_id
		var sw0 := ToolUseSystem.swing(ctx, cr, cr.held_object_id)
		if not sw0["ok"]:
			return ActionResult.fail(str(sw0["code"]), str(sw0["message"]))
		a.state["next_strike_at"] = float(a.state.get("t0", 0.0)) + float(sw0["duration_s"])
		a.state["swing_s"] = float(sw0["duration_s"])
		a.state["power_w"] = float(sw0["power_w"])
		a.state["key"] = strike_key(ctx, cr, target)
	if target == null:
		a.consumed["strikes"] = a.state["strikes_done"]
		if int(a.state["strikes_done"]) > 0:
			return _strike_recover(a, ctx, "Ziel zerbrochen nach %d Schlägen." % int(a.state["strikes_done"]))
		return ActionResult.fail("target_lost", "Ziel existiert nicht mehr.")
	a.progress = clampf(float(a.state["strikes_done"]) / maxf(1.0, n), 0.0, 1.0)
	var top_now := WorkMotion.target_height(ctx, cr, a.target_id, target.position)
	if a.elapsed_s < float(a.state["next_strike_at"]):
		var sws := float(a.state.get("swing_s", 1.0))
		WorkMotion.set_anim(a, "strike", "work", 1.0 - (float(a.state["next_strike_at"]) - a.elapsed_s) / maxf(1e-6, sws), top_now,
			{"tool_h": float(a.state.get("tool_h", 0.0)), "contacts": int(a.state.get("contacts", 0)), "tool": cr.held_object_id})
		return ActionResult.success()
	# ── Kontakt: genau ein Simulationsereignis je Schlag ──
	var r := ToolUseSystem.strike(ctx, cr, a.target_id)
	if not r["ok"]:
		return ActionResult.fail(str(r.get("code", "strike_failed")), str(r["message"]))
	a.state["contacts"] = int(a.state.get("contacts", 0)) + 1
	WorkMotion.set_anim(a, "strike", "contact", 1.0, top_now, {"contacts": a.state["contacts"], "tool": cr.held_object_id})
	a.state["strikes_done"] = int(a.state["strikes_done"]) + 1
	a.state["mech_j"] = float(a.state["mech_j"]) + float(r["energy_j"])
	var lg: Array = a.state["log"]
	lg.append({"n": a.state["strikes_done"], "work_j": snappedf(float(r["work_j"]), 0.001), "effect": str(r["effect"].get("kind", "")),
		"d_strain": snappedf(float(r["effect"].get("d_strain", 0.0)), 0.00001), "joint": r["joint"], "broke": r["broke"], "hand": r["hand_damage"]})
	while lg.size() > 40:
		lg.pop_front()
	a.consumed = {"strikes": a.state["strikes_done"], "mechanical_j": a.state["mech_j"], "key": a.state["key"],
		"thickness0_m": a.state["thickness0"], "strain0": a.state["strain0"], "damage0": a.state["damage0"], "log": lg.duplicate(true),
		"contacts": a.state["contacts"], "tool": int(a.state.get("tool0", 0))}
	if ctx.material_pieces.has(a.target_id):
		var t2: MaterialPiece = ctx.material_pieces[a.target_id]
		a.consumed["thickness_m"] = t2.dims_m.y
		a.consumed["strain"] = t2.strain
		a.consumed["damage"] = t2.damage
	else:
		a.consumed["fractured"] = true
		a.consumed["fragments"] = r["effect"].get("fragment_ids", [])
	if r["broke"]:
		a.consumed["tool_broke"] = true
		if stop_on_break:
			return _strike_recover(a, ctx, "Werkzeugverbindung gebrochen nach %d Schlägen." % int(a.state["strikes_done"]))
	if not ctx.material_pieces.has(a.target_id):
		return _strike_recover(a, ctx, "Ziel zerbrochen.")
	if int(a.state["strikes_done"]) >= n:
		return _strike_recover(a, ctx, "%d Schläge ausgeführt." % n)
	var sw := ToolUseSystem.swing(ctx, cr, cr.held_object_id)
	if not sw["ok"]:
		return ActionResult.fail(str(sw["code"]), str(sw["message"]))
	a.state["next_strike_at"] = a.elapsed_s + float(sw["duration_s"])
	a.state["swing_s"] = float(sw["duration_s"])
	a.state["power_w"] = float(sw["power_w"])
	return ActionResult.success()


## Nach dem letzten Kontakt: kurze Rückkehrphase, danach erfolgreich beendet.
static func _strike_recover(a: GameAction, ctx: LifeContext, msg: String) -> ActionResult:
	var rs := float(ctx.tc("motion").get("recover_s", 0.3))
	a.state["recover_s"] = rs
	a.state["recover_until"] = a.elapsed_s + rs
	a.state["final_msg"] = msg
	a.state["power_w"] = 0.0
	a.progress = 1.0
	if rs <= 0.0:
		return ActionResult.success(msg, {"done": true})
	return ActionResult.success()


static func strike_power(a: GameAction) -> float:
	return float(a.state.get("power_w", 0.0))


## Reserviert Objekte für die Dauer der Handlung (Schutz vor gleichzeitiger Nutzung).
static func reserve_objects(ctx: LifeContext, a: GameAction, ids: Array) -> ActionResult:
	for id in ids:
		var top := ConstructionSystem.top_id(ctx, id)
		var o = ctx.assemblies.get(top, ctx.material_pieces.get(top, null))
		if o == null:
			return ActionResult.fail("target_lost", "#%d fehlt." % id)
		if int(o.reserved_by) != 0 and int(o.reserved_by) != a.actor_id:
			return ActionResult.fail("reserved", "#%d wird von #%d benutzt." % [top, int(o.reserved_by)])
	var held: Array = []
	for id in ids:
		var top2 := ConstructionSystem.top_id(ctx, id)
		var o2 = ctx.assemblies.get(top2, ctx.material_pieces.get(top2, null))
		o2.reserved_by = a.actor_id
		held.append(top2)
	a.state["reserved_objects"] = held
	return ActionResult.success()


static func release_objects(ctx: LifeContext, a: GameAction) -> void:
	for top in a.state.get("reserved_objects", []):
		var o = ctx.assemblies.get(int(top), ctx.material_pieces.get(int(top), null))
		if o != null and int(o.reserved_by) == a.actor_id:
			o.reserved_by = 0
	a.state.erase("reserved_objects")


## Fertigkeitsstufe eines Wesens für ein Verfahren (für die Umwicklungsqualität).
static func skill_level(cr: Creature, key: String) -> String:
	var lv := ProceduralKnowledge.level(cr, key)
	return lv if lv != "" else "none"
