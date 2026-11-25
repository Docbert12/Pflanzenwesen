class_name WorkMotion
extends RefCounted
## Gemeinsamer Bewegungsteil der Arbeitshandlungen (Prompt 6B): Phasen, Anlauf zum Arbeitsplatz,
## Ausrichtung und Animationsangabe. Phasen jeder aktiven Arbeitshandlung:
##   approach (Bewegung zum Ziel, echte Fortbewegung mit Voxelprüfung) → prepare (Ausgangspose)
##   → work (Arbeitsphase, ggf. mit Kontakt) → recover (Rückkehr in gültige Pose) → fertig.
##   Abbruch: Executor beendet; die Darstellung blendet aus der letzten Pose zurück (kontrolliert).
## Die Simulationswirkung (Schaden, Verbrauch, Übergabe) geschieht AUSSCHLIESSLICH in der Handlung an
## einem eindeutigen Zeitpunkt; die Animation liest nur a.state["anim"] und verändert nichts.

const PHASES := ["approach", "prepare", "work", "contact", "recover"]


static func mc(ctx: LifeContext) -> Dictionary:
	return ctx.tc("motion")


## Animationsangabe für die Darstellung (rein lesend genutzt). target: Weltpunkt des Kontakts.
static func set_anim(a: GameAction, pose: String, phase: String, u: float, target, extra: Dictionary = {}) -> void:
	var d: Dictionary = a.state.get("anim", {})
	d["pose"] = pose
	d["phase"] = phase
	d["u"] = clampf(u, 0.0, 1.0)
	if target != null:
		d["target"] = [target.x, target.y, target.z]
	d.merge(extra, true)
	a.state["anim"] = d


## Zielhöhe (Oberkante) eines Objekts bzw. Punkts relativ zum Boden unter dem Wesen.
static func target_height(ctx: LifeContext, cr: Creature, id: int, fallback: Vector3) -> Vector3:
	var top := ConstructionSystem.top_id(ctx, id)
	if top != 0:
		var p = ctx.position_of(top)
		var h := 0.0
		for mp in ConstructionSystem.parts_of(ctx, top):
			h = maxf(h, (mp as MaterialPiece).dims_m.y)
		return Vector3(p.x, p.y + h, p.z)
	return fallback


## Standabstand für eine Kontaktpose: (reach_z, sx, pose). kind "strike", "place" oder "pour".
## two_handed: Gegenstand zwischen beiden Händen → Kontaktpunkt mittig (sx = 0).
static func contact_geometry(ctx: LifeContext, cr: Creature, target_top: Vector3, kind: String, tool_h: float, two_handed: bool = false) -> Dictionary:
	var side := cr.hold_side if cr.hold_side != "" else str(cr.caps.get("grasp_side", "r"))
	var b := WorkPose.body(cr.plan, side)
	var pose := WorkPose.contact(b, tool_h, target_top.y - cr.position.y, kind)
	var two := two_handed or cr.hold_mode == "two"
	return {"body": b, "pose": pose, "reach_z": float(pose.get("reach_z", 0.3)), "sx": 0.0 if two else float(b["sx"]), "side": side, "two": two}


## Anlaufphase: geht in gerader Linie (mit Voxelprüfung) zum Standpunkt vor dem Ziel und dreht sich
## zum Ziel. Rückgabe {done, blocked, reason}. Höchstens approach_max_m Weg je Handlung.
static func approach(a: GameAction, ctx: LifeContext, dt: float, target_top: Vector3, kind: String, tool_h: float, two_handed: bool = false) -> Dictionary:
	var cr := ctx.creature(a.actor_id)
	var g := contact_geometry(ctx, cr, target_top, kind, tool_h, two_handed)
	if not a.state.has("stand"):
		var sp := WorkPose.stand_point(target_top, cr.position, float(g["reach_z"]), float(g["sx"]))
		a.state["stand"] = [sp["pos"].x, sp["pos"].z, sp["heading"]]
		a.state["walked_m"] = 0.0
	var st: Array = a.state["stand"]
	var goal := Vector3(float(st[0]), cr.position.y, float(st[1]))
	var to := Vector2(goal.x - cr.position.x, goal.z - cr.position.z)
	var dist := to.length()
	var tol := float(mc(ctx).get("stand_tolerance_m", 0.04))
	set_anim(a, "walk_short", "approach", 0.0, target_top, {"kind": kind})
	if dist <= tol:
		cr.heading = float(st[2])
		cr.speed_now = 0.0
		return {"done": true, "blocked": false, "reason": ""}
	if float(a.state["walked_m"]) > float(mc(ctx).get("approach_max_m", 1.4)):
		return {"done": false, "blocked": true, "reason": "Arbeitsplatz nicht erreicht (Anlauf über %.1f m)." % float(mc(ctx).get("approach_max_m", 1.4))}
	var speed := cr.speed_m_s(ctx) * float(mc(ctx).get("approach_speed_factor", 0.6))
	if speed <= 0.0:
		return {"done": false, "blocked": true, "reason": "Fortbewegung nicht möglich: %s" % str(cr.caps.get("walk_reason", ""))}
	var stepv := to / dist * minf(dist, speed * dt)
	var np := Vector3(cr.position.x + stepv.x, cr.position.y, cr.position.z + stepv.y)
	if ctx.nav != null:
		var c0 := ctx.nav.world_to_col(cr.position)
		var c1 := ctx.nav.world_to_col(np)
		if c1 != c0:
			if not ctx.nav.in_bounds(c1) or not ctx.nav.is_walkable(c1) or not ctx.nav.can_step(c0, c1):
				return {"done": false, "blocked": true, "reason": "Weg zum Arbeitsplatz blockiert (%s)." % (ctx.nav.why_not_walkable(c1) if ctx.nav.in_bounds(c1) else "Weltrand")}
			np.y = ctx.nav.ground_y(c1)
	var moved := Vector2(np.x - cr.position.x, np.z - cr.position.z).length()
	cr.position = np
	cr.tick_moved_m += moved
	cr.stats["distance_m"] = float(cr.stats.get("distance_m", 0.0)) + moved
	a.state["walked_m"] = float(a.state["walked_m"]) + moved
	cr.speed_now = moved / maxf(dt, 1e-6)
	cr.heading = lerp_angle(cr.heading, atan2(to.x, to.y), minf(1.0, dt * 8.0))
	return {"done": false, "blocked": false, "reason": ""}


## Phasenuhr innerhalb einer Handlung: liefert die aktuelle Phase für (prepare, work, recover)-Dauern
## ab dem Zeitpunkt t0 (Ende des Anlaufs). Rückgabe {phase, u, done}.
static func phase_at(elapsed: float, t0: float, prepare_s: float, work_s: float, recover_s: float) -> Dictionary:
	var t := elapsed - t0
	if t < prepare_s:
		return {"phase": "prepare", "u": t / maxf(prepare_s, 1e-6), "done": false}
	t -= prepare_s
	if t < work_s:
		return {"phase": "work", "u": t / maxf(work_s, 1e-6), "done": false}
	t -= work_s
	if t < recover_s:
		return {"phase": "recover", "u": t / maxf(recover_s, 1e-6), "done": false}
	return {"phase": "recover", "u": 1.0, "done": true}


## Benötigte Hände einer Handlung prüfen (Körper berücksichtigen). need = 1 oder 2.
## one_arm_variant: true → mit einer Hand erlaubt (Rückgabe data.variant = "einarmig").
static func check_hands(cr: Creature, need: int, one_arm_variant: bool, what: String) -> ActionResult:
	var n := ToolUseSystem.grasp_hands(cr)
	if n <= 0:
		return ActionResult.fail("missing_capability", "%s nicht möglich: keine greiffähige Hand." % what)
	if n < need:
		if one_arm_variant:
			return ActionResult.success("einarmige Variante", {"variant": "einarmig"})
		return ActionResult.fail("missing_capability", "%s braucht %d greiffähige Hände (vorhanden: %d); keine einarmige Variante implementiert." % [what, need, n])
	return ActionResult.success("", {"variant": "zweihändig" if need == 2 else "einhändig"})
