class_name PutIntoContainerAction
extends ActionImpl
## Prompt 6B: Gehaltenes Stück in einen Behälter (Tiegel) legen (target = Tiegelkörper oder Tiegel mit
## Griff). Zweck „schmelzen“ (Standard): nur Materialien mit unterstütztem Schmelzmodell, die der
## Behälter aushält – Schmelzen ist keine universelle Recyclingaktion (MaterialProcessSystem.melt_support).
## Prüft Hohlraum (freies Volumen), festen Zustand und Temperatur. Wärmekontakt Stück↔Tiegel wie in der
## Testwerkstatt. Ablauf: Anlauf → hineinlegen (genau einmal) → aufrichten.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.tc("containers").get("put_in_s", 1.2)) + float(ctx.tc("motion").get("approach_budget_s", 2.5)) + 0.6


static func cup_of(ctx: LifeContext, id: int) -> MaterialPiece:
	var top := ConstructionSystem.top_id(ctx, id)
	for p in ConstructionSystem.parts_of(ctx, top):
		if (p as MaterialPiece).shape == "cup":
			return p
	return null


static func free_volume_m3(ctx: LifeContext, cup: MaterialPiece) -> float:
	var used := 0.0
	for c in ConstructionSystem.contents_of(ctx, cup.id):
		used += (c as MaterialPiece).volume_m3()
	return cup.cavity_m3 - used


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var cup := cup_of(ctx, a.target_id)
	if cup == null or cup.cavity_m3 <= 0.0:
		return ActionResult.fail("no_container", "#%d ist kein unterstützter Behälter (Tiegel)." % a.target_id)
	if cr.held_object_id == 0 or not ctx.material_pieces.has(cr.held_object_id):
		return ActionResult.fail("nothing_held", "Hält kein einzelnes Stück zum Hineinlegen.")
	var p: MaterialPiece = ctx.material_pieces[cr.held_object_id]
	if p.liquid_fraction() > 0.0:
		return ActionResult.fail("liquid", "Flüssiges Material kann so nicht umgefüllt werden.")
	if str(a.params.get("purpose", "schmelzen")) == "schmelzen":
		var ms := MaterialProcessSystem.melt_support(p.material(), cup.material())
		if not ms["ok"]:
			return ActionResult.fail(str(ms["code"]) if str(ms["code"]) != "ok" else "unsuitable_for_melting", str(ms["message"]))
	if p.volume_m3() > free_volume_m3(ctx, cup) + 1e-12:
		return ActionResult.fail("container_full", "Passt nicht in Tiegel #%d (%.1f cm³ > %.1f cm³ frei)." % [cup.id, p.volume_m3() * 1e6, maxf(0.0, free_volume_m3(ctx, cup)) * 1e6])
	if ToolUseSystem.heater_of(ctx, ConstructionSystem.top_id(ctx, cup.id)) != 0:
		return ActionResult.fail("container_in_heater", "Tiegel steht in der Heizung – erst herausnehmen.")
	var r := TechActionUtil.check_reach(ctx, cr, cup.id)
	if not r.ok:
		return r
	return ActionResult.success()


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	if cup_of(ctx, a.target_id) == null:
		return ActionResult.fail("target_lost", "Behälter existiert nicht mehr.")
	if ctx.creature(a.actor_id).held_object_id == 0 and not a.state.get("put", false):
		return ActionResult.fail("nothing_held", "Stück ist nicht mehr in der Hand.")
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, dt: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var cup := cup_of(ctx, a.target_id)
	var mc := WorkMotion.mc(ctx)
	var tt := Vector3(cup.position.x, cup.position.y + cup.dims_m.y + 0.02, cup.position.z)
	if not a.state.get("approached", false):
		var ap := WorkMotion.approach(a, ctx, dt, tt, "place", 0.0)
		if ap["blocked"]:
			return ActionResult.fail("blocked", str(ap["reason"]))
		if not ap["done"]:
			return ActionResult.success()
		a.state["approached"] = true
		a.state["t0"] = a.elapsed_s
		a.state["piece"] = cr.held_object_id
	var work_s := float(ctx.tc("containers").get("put_in_s", 1.2))
	var ph := WorkMotion.phase_at(a.elapsed_s, float(a.state["t0"]), float(mc.get("prepare_s", 0.25)), work_s, float(mc.get("recover_s", 0.3)))
	WorkMotion.set_anim(a, "place", str(ph["phase"]), float(ph["u"]), tt, {"object": int(a.state.get("piece", 0)), "container": cup.id})
	a.progress = clampf((a.elapsed_s - float(a.state["t0"])) / (work_s + float(mc.get("prepare_s", 0.25))), 0.0, 1.0)
	if str(ph["phase"]) == "recover" and not a.state.get("put", false):
		if cr.held_object_id == 0 or not ctx.material_pieces.has(cr.held_object_id):
			return ActionResult.fail("nothing_held", "Stück nicht mehr in der Hand.")
		var p: MaterialPiece = ctx.material_pieces[cr.held_object_id]
		if p.volume_m3() > free_volume_m3(ctx, cup) + 1e-12:
			return ActionResult.fail("container_full", "Tiegel #%d ist inzwischen voll." % cup.id)
		var pid := ToolUseSystem.release_at(ctx, cr, cup.position + Vector3(0, cup.inner_floor_m() + 0.001, 0), "in Tiegel #%d gelegt" % cup.id)
		var mp: MaterialPiece = ctx.material_pieces[pid]
		mp.container_id = cup.id
		ctx.sim.thermal.add_contact_g(mp, cup, float(ctx.tc("heater").get("container_sample_conductance_w_k", 3.0)), "Tiegel #%d↔Stück #%d" % [cup.id, pid], true)
		mp.add_history(ctx.now(), "in Tiegel #%d gelegt von #%d" % [cup.id, cr.id])
		ConstructionSystem.sync_positions(ctx)
		ctx.publish({"type": "put_into_container", "actor": cr.id, "target": 0, "position": cup.position,
			"consequences": {"piece": pid, "container": cup.id, "material": mp.material_id}, "visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})
		a.state["put"] = true
		a.consumed = {"piece": pid, "container": cup.id, "kg": mp.mass_kg, "material": mp.material_id}
	if ph["done"]:
		return ActionResult.success("#%d liegt in Tiegel #%d." % [int(a.consumed.get("piece", 0)), cup.id], {"done": true})
	return ActionResult.success()
