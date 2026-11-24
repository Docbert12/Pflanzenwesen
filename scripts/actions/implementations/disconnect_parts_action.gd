class_name DisconnectPartsAction
extends ActionImpl
## Einen Verbund gewollt lösen. Alle Bauteile (auch die Fasern) bleiben als Weltobjekte erhalten.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("connection").get("disconnect_s", 3.0))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var top := ConstructionSystem.top_id(ctx, a.target_id)
	if not ctx.assemblies.has(top):
		return ActionResult.fail("not_assembly", "#%d ist kein zusammengesetzter Gegenstand." % a.target_id)
	if (ctx.assemblies[top] as Assembly).test_equipment:
		return ActionResult.fail("test_equipment", "Testausrüstung ist fest montiert.")
	a.target_id = top
	var cr := ctx.creature(a.actor_id)
	var c := ConstructionSystem.carrier_of(ctx, top)
	if c != 0 and c != cr.id:
		return ActionResult.fail("held_by_other", "Wird von #%d gehalten." % c)
	return TechActionUtil.check_reach(ctx, cr, top)


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if not ctx.assemblies.has(a.target_id):
		return ActionResult.fail("target_lost", "Verbund existiert nicht mehr.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var r := ConstructionSystem.dissolve(ctx, a.target_id, "von #%d gelöst" % a.actor_id, false, a.actor_id)
	a.consumed = {"parts": r.get("parts", [])}
	return ActionResult.success(str(r["message"]), {"done": true})
