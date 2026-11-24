class_name PracticeProcedureAction
extends ActionImpl
## Ein bekanntes (gehörtes oder gesehenes) Verfahren selbst üben. Führt den Kernvorgang mit echten
## Gegenständen aus; Ergebnis und Qualität hängen von Material, Körper und eigener Erfahrung ab
## (Umwicklung: Geschick nach Erfahrungsstand). Das Ergebnis wird als EIGENER Versuch verbucht
## (ExperimentSystem) – erst ein tatsächlicher Erfolg ergibt „selbst erfolgreich“.
## params: key, target_piece (schlagen) | handle, head, fiber (verbinden), strikes

func _kind(a: GameAction) -> String:
	return ProceduralKnowledge.kind_of(str(a.params.get("key", "")))


func estimate_s(a: GameAction, ctx: LifeContext) -> float:
	if _kind(a) == "verbinden":
		return float(ctx.tc("connection").get("lashing", {}).get("duration_s", 6.0)) + 1.0
	var cr := ctx.creature(a.actor_id)
	return float(ToolUseSystem.swing(ctx, cr, cr.held_object_id).get("duration_s", 1.0)) * int(a.params.get("strikes", 6)) + 1.0


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var key := str(a.params.get("key", ""))
	if not ProceduralKnowledge.knows(cr, key):
		return ActionResult.fail("unknown_procedure", "Verfahren ist diesem Wesen nicht bekannt.")
	match _kind(a):
		"schlagen":
			var t := int(a.params.get("target_piece", 0))
			if not ctx.material_pieces.has(t):
				return ActionResult.fail("target_lost", "Kein Werkstück.")
			var sw := ToolUseSystem.swing(ctx, cr, cr.held_object_id)
			if not sw["ok"]:
				return ActionResult.fail(str(sw["code"]), str(sw["message"]))
			return TechActionUtil.check_reach(ctx, cr, t)
		"verbinden":
			var ids := [int(a.params.get("handle", 0)), int(a.params.get("head", 0)), int(a.params.get("fiber", 0))]
			for id in ids:
				if not ctx.material_pieces.has(id):
					return ActionResult.fail("target_lost", "Teil #%d fehlt." % id)
				var r := TechActionUtil.check_reach(ctx, cr, id)
				if not r.ok:
					return r
			var chk := ConnectionDefinition.check_lashing(ctx, ctx.material_pieces[ids[0]], ctx.material_pieces[ids[1]], ctx.material_pieces[ids[2]], "none")
			if not chk["ok"]:
				return ActionResult.fail(str(chk["code"]), str(chk["message"]))
			return ActionResult.success()
	return ActionResult.fail("unsupported_procedure", "Dieses Verfahren kann (noch) nicht geübt werden.")


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	match _kind(a):
		"schlagen":
			var saved := a.target_id
			a.target_id = int(a.params["target_piece"])
			var r := TechActionUtil.strike_series(a, ctx, clampi(int(a.params.get("strikes", 6)), 1, 20), true)
			a.target_id = saved
			if r.ok and r.data.get("done", false):
				a.consumed["practiced_key"] = TechActionUtil.strike_key(ctx, cr, ctx.material_pieces[int(a.params["target_piece"])]) if ctx.material_pieces.has(int(a.params["target_piece"])) else str(a.params["key"])
			return r
		"verbinden":
			var d := float(ctx.tc("connection").get("lashing", {}).get("duration_s", 6.0))
			a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
			if a.elapsed_s < d:
				return ActionResult.success()
			if cr.held_object_id != 0:
				ToolUseSystem.release(ctx, cr, "zum Üben abgelegt")
			var key := str(a.params["key"])
			var r2 := ConstructionSystem.connect_lashing(ctx, cr.id, int(a.params["handle"]), int(a.params["head"]), int(a.params["fiber"]), TechActionUtil.skill_level(cr, key), "")
			if not r2["ok"]:
				return ActionResult.fail(str(r2["code"]), str(r2["message"]))
			ToolUseSystem.hold(ctx, cr, int(r2["id"]))
			a.consumed = {"assembly": int(r2["id"]), "key": key, "capacity_j": float(r2["check"]["capacity_j"]), "skill": float(r2["check"]["skill"]),
				"practiced_key": ProceduralKnowledge.lashing_key(ctx.material_pieces[int(a.params["handle"])].material_id, ctx.material_pieces[int(a.params["head"])].material_id)}
			return ActionResult.success(str(r2["message"]), {"done": true})
	return ActionResult.fail("unsupported_procedure", "Unbekanntes Verfahren.")


func power_w(a: GameAction, _ctx: LifeContext) -> float:
	return TechActionUtil.strike_power(a)
