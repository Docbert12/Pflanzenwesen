class_name PourIntoMoldAction
extends ActionImpl
## Tiegel (target) am Griff nehmen und den geschmolzenen Inhalt in eine Gussform (params.mold) gießen.
## Prüft Griffttemperatur (mit Wärmefluss in die Hand während des Gießens), Flüssiganteil,
## Form, Kapazität, Formmaterial. Nach dem Gießen wird der Tiegel neben der Form abgestellt.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("casting").get("pour_s", 3.0))


func _melt(ctx: LifeContext, top: int) -> MaterialPiece:
	for p in ConstructionSystem.parts_of(ctx, top):
		if (p as MaterialPiece).shape == "cup":
			for c in ConstructionSystem.contents_of(ctx, p.id):
				return c
	return null


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var top := ConstructionSystem.top_id(ctx, a.target_id)
	if top == 0:
		return ActionResult.fail("target_lost", "Tiegel #%d fehlt." % a.target_id)
	a.target_id = top
	var mold: MaterialPiece = ctx.material_pieces.get(int(a.params.get("mold", 0)), null)
	if mold == null or mold.shape != "mold":
		return ActionResult.fail("no_mold", "Keine Gussform #%d." % int(a.params.get("mold", 0)))
	var melt := _melt(ctx, top)
	if melt == null:
		return ActionResult.fail("empty", "Tiegel #%d ist leer." % top)
	var r := TechActionUtil.check_reach(ctx, cr, top)
	if not r.ok:
		return r
	r = TechActionUtil.check_reach(ctx, cr, mold.id)
	if not r.ok:
		return r
	if cr.held_object_id != 0 and cr.held_object_id != top:
		return ActionResult.fail("hands_full", "Hält bereits #%d." % cr.held_object_id)
	var g := ConstructionSystem.grip_piece(ctx, top)
	if g == null:
		return ActionResult.fail("no_grip", "Tiegel ohne Griff – Schmelze lässt sich nicht gefahrlos tragen.")
	if g.temperature_k() > ToolUseSystem.safe_k(ctx):
		return ActionResult.fail("too_hot", "Griff zu heiß (%s)." % ToolUseSystem.temperature_category(ctx, g.temperature_k()))
	var mc := float(ctx.tc("casting").get("min_liquid_fraction", 0.95))
	if melt.liquid_fraction() < mc:
		return ActionResult.fail("not_liquid", "Inhalt nicht ausreichend geschmolzen.")
	return ActionResult.success()


func start(a: GameAction, ctx: LifeContext) -> ActionResult:
	return TechActionUtil.reserve_objects(ctx, a, [a.target_id, int(a.params["mold"])])


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if ConstructionSystem.top_id(ctx, a.target_id) == 0 or not ctx.material_pieces.has(int(a.params.get("mold", 0))):
		return ActionResult.fail("target_lost", "Tiegel oder Form fehlt.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var g := ConstructionSystem.grip_piece(ctx, a.target_id)
	# Prompt 6B: vorsichtiges Gießen – langsames Neigen über die Gießdauer (Darstellung liest nur)
	var mold_p: MaterialPiece = ctx.material_pieces.get(int(a.params.get("mold", 0)), null)
	if mold_p != null:
		WorkMotion.set_anim(a, "pour", "work", a.elapsed_s / maxf(0.1, estimate_s(a, ctx)), mold_p.position + Vector3(0, mold_p.dims_m.y + 0.04, 0),
			{"object": a.target_id, "mold": mold_p.id})
	# Während des Gießens hält die Hand den Griff: Wärme fließt in die Hand (bilanziert)
	if g != null:
		ctx.sim.thermal.transfer_to_body(g, float(ctx.tc("temperature").get("hand_conductance_w_k", 0.25)), 310.0, dt)
		if g.temperature_k() > ToolUseSystem.safe_k(ctx):
			ToolUseSystem.touch_burn(ctx, cr, g, 0.25, "Tiegelgriff wurde beim Gießen heiß")
			return ActionResult.fail("too_hot", "Griff wurde zu heiß – Gießen abgebrochen.")
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var melt := _melt(ctx, a.target_id)
	var mold: MaterialPiece = ctx.material_pieces[int(a.params["mold"])]
	var hid := ToolUseSystem.heater_of(ctx, a.target_id)
	if hid != 0:
		ToolUseSystem.remove_from_heater(ctx, hid)
	var r := MaterialProcessSystem.pour(ctx, melt, mold)
	# Tiegel neben der Form abstellen
	var top := a.target_id
	if ctx.assemblies.has(top):
		(ctx.assemblies[top] as Assembly).position = mold.position + Vector3(-0.35, 0.0, 0.25)
	ConstructionSystem.sync_positions(ctx)
	if not r["ok"]:
		return ActionResult.fail(str(r["code"]), str(r["message"]))
	var cast: MaterialPiece = r["cast"]
	var key := ProceduralKnowledge.cast_key(cast.material_id)
	a.consumed = {"cast": cast.id, "poured_kg": r["poured_kg"], "rest_kg": r["rest_kg"], "energy_before_j": r["energy_before_j"],
		"energy_after_j": r["energy_after_j"], "key": key}
	ctx.publish({"type": "metal_poured", "actor": cr.id, "target": 0, "position": mold.position,
		"consequences": {"cast": cast.id, "mold": mold.id, "verfahren": key, "glühend": true},
		"visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})
	return ActionResult.success(str(r["message"]), {"done": true})


func cleanup(a: GameAction, ctx: LifeContext) -> void:
	TechActionUtil.release_objects(ctx, a)
