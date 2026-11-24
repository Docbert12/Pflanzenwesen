class_name EquipToolAction
extends ActionImpl
## Einen Gegenstand (Stück oder Verbund) in die Greifhand nehmen. Prüft Reichweite, Greifbarkeit,
## Masse, freie Hand, Reservierung und Temperatur am Griff. Ein zu heißer Griff wird kurz berührt
## (Verbrennung, Wärme in die Hand bilanziert) und nicht genommen.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("hands").get("equip_s", 1.0))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var r := TechActionUtil.check_reach(ctx, cr, a.target_id)
	if not r.ok:
		return r
	var g := ToolUseSystem.check_grasp(ctx, cr, a.target_id)
	if not g.ok and g.code == "too_hot":
		var grip := ConstructionSystem.grip_piece(ctx, ConstructionSystem.top_id(ctx, a.target_id))
		ToolUseSystem.touch_burn(ctx, cr, grip, float(ctx.tc("temperature").get("touch_s", 0.25)), "zu heißen Griff angefasst")
		ProceduralKnowledge.see_object(ctx, cr, a.target_id, 0.5)
		cr.tech["objects"][ConstructionSystem.top_id(ctx, a.target_id)]["temperatur"] = ToolUseSystem.object_temperature_category(ctx, a.target_id)
	return g


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if not ConstructionSystem.is_object(ctx, a.target_id):
		return ActionResult.fail("target_lost", "Gegenstand existiert nicht mehr.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var cr := ctx.creature(a.actor_id)
	var g := ToolUseSystem.check_grasp(ctx, cr, a.target_id)
	if not g.ok:
		return g
	var top := ConstructionSystem.top_id(ctx, a.target_id)
	var hid := ToolUseSystem.heater_of(ctx, top)
	if hid != 0:
		ToolUseSystem.remove_from_heater(ctx, hid)
	ToolUseSystem.hold(ctx, cr, top)
	ProceduralKnowledge.see_object(ctx, cr, top, 0.0)
	a.consumed = {"held": top, "mass_kg": ConstructionSystem.mass_of(ctx, top)}
	return ActionResult.success("#%d in der Hand." % top, {"done": true})
