class_name EquipToolAction
extends ActionImpl
## Einen Gegenstand (Stück oder Verbund) in die Greifhand nehmen. Prüft Reichweite, Greifbarkeit,
## Masse, freie Hand, Reservierung und Temperatur am Griff. Ein zu heißer Griff wird kurz berührt
## (Verbrennung, Wärme in die Hand bilanziert) und nicht genommen.
## Prompt 6B: Bewegungsphasen (Anlauf bis Greifabstand → bücken/greifen → aufnehmen → aufrichten).
## params.carry = true: Aufnehmen zum TRAGEN – ein Stück, das für eine Hand zu schwer ist, wird mit
## beiden freien Händen genommen (hold_mode "two"); mit nur einer Hand wird nachvollziehbar abgelehnt.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("hands").get("equip_s", 1.0)) + float(ctx.tc("motion").get("approach_budget_s", 2.5)) + float(ctx.tc("motion").get("recover_s", 0.3))


func _mode_check(a: GameAction, ctx: LifeContext, cr: Creature) -> Dictionary:
	if bool(a.params.get("carry", false)):
		return ToolUseSystem.check_carry(ctx, cr, a.target_id)
	var g := ToolUseSystem.check_grasp(ctx, cr, a.target_id)
	return {"ok": g.ok, "mode": "one", "code": g.code, "message": g.message}


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var r := TechActionUtil.check_reach(ctx, cr, a.target_id)
	if not r.ok:
		return r
	var g := _mode_check(a, ctx, cr)
	if not g["ok"] and str(g["code"]) == "too_hot":
		var grip := ConstructionSystem.grip_piece(ctx, ConstructionSystem.top_id(ctx, a.target_id))
		ToolUseSystem.touch_burn(ctx, cr, grip, float(ctx.tc("temperature").get("touch_s", 0.25)), "zu heißen Griff angefasst")
		ProceduralKnowledge.see_object(ctx, cr, a.target_id, 0.5)
		cr.tech["objects"][ConstructionSystem.top_id(ctx, a.target_id)]["temperatur"] = ToolUseSystem.object_temperature_category(ctx, a.target_id)
	if not g["ok"]:
		return ActionResult.fail(str(g["code"]), str(g["message"]))
	a.state["mode"] = str(g["mode"])
	return ActionResult.success(str(g["message"]))


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if not ConstructionSystem.is_object(ctx, a.target_id):
		return ActionResult.fail("target_lost", "Gegenstand existiert nicht mehr.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var top := ConstructionSystem.top_id(ctx, a.target_id)
	var mc := WorkMotion.mc(ctx)
	var already := cr.held_object_id == top and top != 0
	var pose := "carry_two" if str(a.state.get("mode", "one")) == "two" else "grasp"
	if not a.state.get("approached", false):
		if already:
			a.state["approached"] = true
			a.state["t0"] = a.elapsed_s
		else:
			var tp = ctx.position_of(top)
			var tt := WorkMotion.target_height(ctx, cr, top, tp)
			var ap := WorkMotion.approach(a, ctx, dt, tt, "place", 0.0, str(a.state.get("mode", "one")) == "two")
			if ap["blocked"]:
				return ActionResult.fail("blocked", str(ap["reason"]))
			if not ap["done"]:
				return ActionResult.success()
			a.state["approached"] = true
			a.state["t0"] = a.elapsed_s
	var work_s := float(ctx.tc("hands").get("equip_s", 1.0))
	var ph := WorkMotion.phase_at(a.elapsed_s, float(a.state["t0"]), float(mc.get("prepare_s", 0.25)), work_s, float(mc.get("recover_s", 0.3)))
	# Animationsziel = Griffpunkt (Oberkante des Gegenstands); nach der Übernahme liegt er in der Hand
	if not a.state.has("grip_target"):
		var gt := WorkMotion.target_height(ctx, cr, top, ctx.position_of(top) if ctx.position_of(top) != null else cr.position)
		a.state["grip_target"] = [gt.x, gt.y, gt.z]
	var gta: Array = a.state["grip_target"]
	WorkMotion.set_anim(a, pose, str(ph["phase"]), float(ph["u"]), Vector3(float(gta[0]), float(gta[1]), float(gta[2])), {"object": top})
	a.progress = clampf((a.elapsed_s - float(a.state["t0"])) / (work_s + float(mc.get("prepare_s", 0.25))), 0.0, 1.0)
	if str(ph["phase"]) != "recover":
		return ActionResult.success()
	if not a.state.get("taken", false):
		# Übergabe in die Hand genau einmal (Ende der Greifphase)
		if cr.held_object_id != top:
			var g := _mode_check(a, ctx, cr)
			if not g["ok"]:
				return ActionResult.fail(str(g["code"]), str(g["message"]))
			var hid := ToolUseSystem.heater_of(ctx, top)
			if hid != 0:
				ToolUseSystem.remove_from_heater(ctx, hid)
			ToolUseSystem.hold(ctx, cr, top, str(g["mode"]))
			ProceduralKnowledge.see_object(ctx, cr, top, 0.0)
		a.state["taken"] = true
		a.consumed = {"held": top, "mass_kg": ConstructionSystem.mass_of(ctx, top), "mode": cr.hold_mode, "side": cr.hold_side}
	if not ph["done"]:
		return ActionResult.success()
	return ActionResult.success("#%d in der Hand%s." % [top, " (beide Hände)" if cr.hold_mode == "two" else ""], {"done": true})
