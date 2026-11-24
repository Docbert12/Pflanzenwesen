class_name ConnectPartsAction
extends ActionImpl
## Stiel (target) und Arbeitskopf (params.head) mit Pflanzenfasern (params.fiber) verbinden.
## Methode: ConnectionDefinition „lashing“. Das Ergebnis entsteht erst am Ende der Arbeitszeit;
## ein Abbruch davor verbraucht keine Fasern (die Arbeitsenergie des Wesens ist verbraucht).
## Die Umwicklungsqualität hängt vom eigenen Erfahrungsstand mit diesem Verfahren ab.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("connection").get("lashing", {}).get("duration_s", 6.0)) * float(ctx.tc("motion").get("one_arm_lashing_time_factor", 1.8)) \
		+ float(ctx.tc("motion").get("approach_budget_s", 2.5))


## Arbeitszeit: zweihändig wie in Prompt 6; einarmige Variante (Prompt 6B) langsamer.
func _work_s(a: GameAction, ctx: LifeContext) -> float:
	var d := float(ctx.tc("connection").get("lashing", {}).get("duration_s", 6.0))
	if str(a.state.get("variant", "")) == "einarmig":
		d *= float(ctx.tc("motion").get("one_arm_lashing_time_factor", 1.8))
	return d


func _ids(a: GameAction) -> Array:
	return [a.target_id, int(a.params.get("head", 0)), int(a.params.get("fiber", 0))]


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var method := str(a.params.get("method", "lashing"))
	if not ConnectionDefinition.is_supported(method) or not ConnectionDefinition.creature_usable(method):
		return ActionResult.fail("unsupported_connection", "Verbindungsmethode „%s“ ist nicht unterstützt." % method)
	for id in _ids(a):
		if not ctx.material_pieces.has(id):
			return ActionResult.fail("target_lost", "Teil #%d ist kein Materialstück." % id)
		var mp: MaterialPiece = ctx.material_pieces[id]
		if mp.carrier_id != 0 and mp.carrier_id != cr.id:
			return ActionResult.fail("held_by_other", "#%d wird von #%d gehalten." % [id, mp.carrier_id])
		var r := TechActionUtil.check_reach(ctx, cr, id)
		if not r.ok:
			return r
	var ids := _ids(a)
	var chk := ConnectionDefinition.check_lashing(ctx, ctx.material_pieces[ids[0]], ctx.material_pieces[ids[1]], ctx.material_pieces[ids[2]], "none")
	if not chk["ok"]:
		return ActionResult.fail(str(chk["code"]), str(chk["message"]))
	if cr.held_object_id != 0 and not (cr.held_object_id in ids):
		return ActionResult.fail("hands_full", "Beide Hände werden zum Umwickeln gebraucht (hält #%d)." % cr.held_object_id)
	# Prompt 6B: Körper berücksichtigen – zweihändig, sonst ausdrücklich unterstützte einarmige Variante
	var hc := WorkMotion.check_hands(cr, 2, true, "Umwickeln")
	if not hc.ok:
		return hc
	a.state["variant"] = str(hc.data.get("variant", "zweihändig"))
	return ActionResult.success()


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	return TechActionUtil.reserve_objects(ctx, a, _ids(a))


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	for id in _ids(a):
		if not ctx.material_pieces.has(id):
			return ActionResult.fail("target_lost", "Teil #%d existiert nicht mehr." % id)
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var ids := _ids(a)
	var hp: MaterialPiece = ctx.material_pieces[ids[0]]
	var tt := WorkMotion.target_height(ctx, cr, ids[0], hp.position)
	if not a.state.get("approached", false):
		if hp.carrier_id == cr.id:
			a.state["approached"] = true
			a.state["t0"] = a.elapsed_s
		else:
			var ap := WorkMotion.approach(a, ctx, dt, tt, "place", 0.0)
			if ap["blocked"]:
				return ActionResult.fail("blocked", str(ap["reason"]))
			if not ap["done"]:
				return ActionResult.success()
			a.state["approached"] = true
			a.state["t0"] = a.elapsed_s
	var d := _work_s(a, ctx)
	var el := a.elapsed_s - float(a.state["t0"])
	a.progress = clampf(el / d, 0.0, 1.0)
	WorkMotion.set_anim(a, "assemble" if str(a.state.get("variant", "")) != "einarmig" else "assemble_one", "work", el / d, tt,
		{"handle": ids[0], "head": ids[1], "fiber": ids[2], "variant": str(a.state.get("variant", ""))})
	if el < d:
		return ActionResult.success()
	var handle: MaterialPiece = ctx.material_pieces[ids[0]]
	var head: MaterialPiece = ctx.material_pieces[ids[1]]
	var key := ProceduralKnowledge.lashing_key(handle.material_id, head.material_id)
	TechActionUtil.release_objects(ctx, a)
	if cr.held_object_id in ids:
		ToolUseSystem.release(ctx, cr, "zum Umwickeln abgelegt")
	var q := float(ctx.tc("motion").get("one_arm_lashing_fit_factor", 0.8)) if str(a.state.get("variant", "")) == "einarmig" else 1.0
	var r := ConstructionSystem.connect_lashing(ctx, cr.id, ids[0], ids[1], ids[2], TechActionUtil.skill_level(cr, key), str(a.params.get("label", "")), q)
	if not r["ok"]:
		return ActionResult.fail(str(r["code"]), str(r["message"]))
	var asm: Assembly = r["assembly"]
	ToolUseSystem.hold(ctx, cr, asm.id)
	a.consumed = {"assembly": asm.id, "fiber_kg": float(r["check"]["fiber_use_kg"]), "capacity_j": float(r["check"]["capacity_j"]),
		"fit": float(r["check"]["fit"]), "skill": float(r["check"]["skill"]), "rest_piece": int(r["rest_piece"]), "key": key,
		"mass_kg": ConstructionSystem.mass_of(ctx, asm.id), "variant": str(a.state.get("variant", "zweihändig"))}
	ctx.publish({"type": "parts_connected", "actor": cr.id, "target": 0, "position": cr.position,
		"consequences": {"assembly": asm.id, "verfahren": key, "teile": asm.part_ids.duplicate()},
		"visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})
	return ActionResult.success(str(r["message"]), {"done": true})


func cleanup(a: GameAction, ctx: LifeContext) -> void:
	TechActionUtil.release_objects(ctx, a)
