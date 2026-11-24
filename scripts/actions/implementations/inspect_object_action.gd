class_name InspectObjectAction
extends ActionImpl
## Einen Gegenstand untersuchen: ansehen, beklopfen, (falls möglich) anheben, Wärme prüfen.
## Ergebnis sind wahrnehmbare Kategorien im Wissen des Wesens – keine exakten Messwerte.
## Wärme wird zuerst aus Abstand geprüft; ist der Gegenstand nur „warm/heiß“ ohne spürbare
## Strahlung, kann die Berührung leicht verbrennen (tatsächliche Erfahrung).

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("hands").get("inspect_s", 2.0))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	if not ConstructionSystem.is_object(ctx, a.target_id):
		return ActionResult.fail("target_lost", "Kein Gegenstand #%d." % a.target_id)
	return TechActionUtil.check_reach(ctx, ctx.creature(a.actor_id), a.target_id)


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
	var top := ConstructionSystem.top_id(ctx, a.target_id)
	var hot: MaterialPiece = null
	for p in ConstructionSystem.parts_of(ctx, top):
		if hot == null or (p as MaterialPiece).temperature_k() > hot.temperature_k():
			hot = p
	var tc: Dictionary = ctx.tc("temperature")
	var burn := {}
	if hot != null and hot.temperature_k() > ToolUseSystem.safe_k(ctx) and hot.temperature_k() < float(tc.get("radiant_feel_k", 500.0)):
		burn = ToolUseSystem.touch_burn(ctx, cr, hot, float(tc.get("touch_s", 0.25)), "beim Untersuchen berührt")
	var e := ProceduralKnowledge.inspect(ctx, cr, top)
	a.consumed = {"perceived": e.duplicate(true), "burn": burn}
	return ActionResult.success("Untersucht: %s, %s, %s." % [e.get("haerte", "?"), e.get("gewicht", "nicht anhebbar"), e.get("temperatur", "?")], {"done": true})
