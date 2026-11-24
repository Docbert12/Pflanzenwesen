class_name DemonstrateProcedureAction
extends ActionImpl
## Ein selbst erfolgreich ausgeführtes Verfahren sichtbar vorführen (target = angesprochenes Wesen
## oder 0). Der Kernvorgang wird TATSÄCHLICH ausgeführt (dieselben Funktionen wie bei
## deform_material/connect_parts) – mit echten Gegenständen und echten Folgen. Zuschauer erhalten
## nur, was sie wahrnehmen (Ereignis „procedure_demonstrated“ mit strukturiertem Verfahren),
## nie die internen Daten des Vorführenden.
## params: key, target_piece (schlagen) | handle, head, fiber (verbinden)

func _kind(a: GameAction) -> String:
	return ProceduralKnowledge.kind_of(str(a.params.get("key", "")))


func estimate_s(a: GameAction, ctx: LifeContext) -> float:
	if _kind(a) == "verbinden":
		return float(ctx.tc("connection").get("lashing", {}).get("duration_s", 6.0)) + 1.0
	var cr := ctx.creature(a.actor_id)
	return float(ToolUseSystem.swing(ctx, cr, cr.held_object_id).get("duration_s", 1.0)) * int(ctx.tc("teaching").get("demo_strikes", 4)) + 1.0


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var key := str(a.params.get("key", ""))
	if ProceduralKnowledge.level(cr, key) != "erfolgreich":
		return ActionResult.fail("not_mastered", "Nur selbst erfolgreich ausgeführte Verfahren können vorgeführt werden.")
	if a.target_id != 0 and ctx.creature(a.target_id) == null:
		return ActionResult.fail("target_lost", "Zuschauer #%d fehlt." % a.target_id)
	match _kind(a):
		"schlagen":
			var t := int(a.params.get("target_piece", 0))
			if not ctx.material_pieces.has(t):
				return ActionResult.fail("target_lost", "Kein Werkstück für die Vorführung.")
			if TechActionUtil.strike_key(ctx, cr, ctx.material_pieces[t]) != key:
				return ActionResult.fail("wrong_setup", "Werkzeug in der Hand oder Werkstück passt nicht zum Verfahren.")
			return TechActionUtil.check_reach(ctx, cr, t)
		"verbinden":
			var ids := [int(a.params.get("handle", 0)), int(a.params.get("head", 0)), int(a.params.get("fiber", 0))]
			for id in ids:
				if not ctx.material_pieces.has(id):
					return ActionResult.fail("target_lost", "Teil #%d fehlt." % id)
				var r := TechActionUtil.check_reach(ctx, cr, id)
				if not r.ok:
					return r
			var chk := ConnectionDefinition.check_lashing(ctx, ctx.material_pieces[ids[0]], ctx.material_pieces[ids[1]], ctx.material_pieces[ids[2]], "erfolgreich")
			if not chk["ok"]:
				return ActionResult.fail(str(chk["code"]), str(chk["message"]))
			if ProceduralKnowledge.lashing_key(ctx.material_pieces[ids[0]].material_id, ctx.material_pieces[ids[1]].material_id) != key:
				return ActionResult.fail("wrong_setup", "Teile passen nicht zum Verfahren.")
			return ActionResult.success()
	return ActionResult.fail("unsupported_procedure", "Dieses Verfahren kann (noch) nicht vorgeführt werden.")


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	ctx.publish({"type": "demonstration_started", "actor": cr.id, "target": a.target_id, "position": cr.position,
		"consequences": {"verfahren": str(a.params["key"]), "geste": "zeigt her"},
		"visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var r: ActionResult
	match _kind(a):
		"schlagen":
			var saved := a.target_id
			a.target_id = int(a.params["target_piece"])
			r = TechActionUtil.strike_series(a, ctx, int(ctx.tc("teaching").get("demo_strikes", 4)), true)
			a.target_id = saved
		"verbinden":
			var d := float(ctx.tc("connection").get("lashing", {}).get("duration_s", 6.0))
			a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
			if a.elapsed_s < d:
				return ActionResult.success()
			if cr.held_object_id != 0:
				ToolUseSystem.release(ctx, cr, "für Vorführung abgelegt")
			var cr2 := ConstructionSystem.connect_lashing(ctx, cr.id, int(a.params["handle"]), int(a.params["head"]), int(a.params["fiber"]), "erfolgreich", "")
			if not cr2["ok"]:
				return ActionResult.fail(str(cr2["code"]), str(cr2["message"]))
			ToolUseSystem.hold(ctx, cr, int(cr2["id"]))
			a.consumed = {"assembly": int(cr2["id"]), "key": str(a.params["key"])}
			r = ActionResult.success(str(cr2["message"]), {"done": true})
		_:
			return ActionResult.fail("unsupported_procedure", "Unbekanntes Verfahren.")
	if r.ok and r.data.get("done", false):
		var visible := _visible_result(a, ctx)
		a.consumed["visible_result"] = visible
		ctx.publish({"type": "procedure_demonstrated", "actor": cr.id, "target": a.target_id, "position": cr.position,
			"consequences": {"verfahren": str(a.params["key"]), "schritte": ProceduralKnowledge.template_steps(str(a.params["key"])),
				"sichtbares_ergebnis": visible, "erfolg": visible != "keine sichtbare Wirkung"},
			"visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})
	return r


## Das sichtbare Ergebnis (wie es auch Zuschauer sehen können).
func _visible_result(a: GameAction, ctx: LifeContext) -> String:
	if _kind(a) == "verbinden":
		return "Kopf sitzt fest am Stiel"
	if a.consumed.get("fractured", false):
		return "Werkstück zerbrochen"
	var t0 := float(a.consumed.get("thickness0_m", 0.0))
	var t1 := float(a.consumed.get("thickness_m", t0))
	if t0 > 0.0 and (t0 - t1) / t0 >= float(ctx.tc("perception").get("visible_thickness_change", 0.05)) * 0.5:
		return "Werkstück sichtbar flacher"
	return "keine sichtbare Wirkung"


func power_w(a: GameAction, _ctx: LifeContext) -> float:
	return TechActionUtil.strike_power(a)
