class_name WorkPose
extends RefCounted
## Geometrie der Arbeitsbewegungen (Prompt 6B). Schulterhöhe, Armlänge und Beinlängen stammen aus dem
## Körperplan, der Abstand Griff→Arbeitskopf aus dem tatsächlich gehaltenen Gegenstand. DIESELBEN
## Formeln nutzen die Handlungen (Standabstand zum Ziel) und die Animation (Kontaktpose). Damit liegt
## der sichtbare Kontakt am Ziel („kein Hämmern neben dem Ziel“) – prüfbar ohne Grafik (TestWorkChain).
##
## Ebenes Gelenkmodell im Körperrahmen (+z vorne, +y oben, x seitlich wie die Gelenkanschlüsse):
##   Rumpfneigung φ (um x, vorwärts positiv), Hocke c (Hüfte tiefer), Armwinkel α (global, 0 = hängt
##   senkrecht, negativ = nach vorn gehoben), Handwinkel β (global; Werkzeugachse = (0, −sin β, cos β)).
##   Schulter  = (sx, H − c + a·cos φ, a·sin φ)
##   Hand      = Schulter + r·(0, −cos α, −sin α)
##   Kopf      = Hand + h·(0, −sin β, cos β)
## Vereinfachung (dokumentiert): starrer Arm, keine Ellbogenbeugung in der Kontaktgeometrie.

const PHI_MAX := 0.75
const CROUCH_MAX_SHARE := 0.42


## Körpermaße einer Seite aus dem Körperplan (Ruhelage). Fehlt der Arm: r = 0, has_arm = false.
static func body(plan: BodyPlan, side: String) -> Dictionary:
	var parts: Dictionary = plan.parts
	var h := float(plan.genes.get("stand_height_m", 0.35))
	var torso: Dictionary = parts.get("torso", {})
	var up_id := "arm_%s_upper" % side
	var a := 0.2
	var sx := 0.08 * (1.0 if side == "r" else -1.0)
	var r := 0.0
	var has_arm := false
	if plan.is_present(up_id):
		var at: Array = parts[up_id]["attach"]
		a = float(at[1])
		sx = float(at[0])
		has_arm = true
		for pid in plan.present_ids():
			var p: Dictionary = parts[pid]
			if str(p.get("side", "")) == side and str(p.get("function", "")) in ["arm", "unterarm", "greifen", "haken"]:
				r += float(p["size"][1])
	elif not torso.is_empty():
		a = float(torso["size"][1]) * 0.78
	var lu := 0.0
	var ll := 0.0
	for s in ["l", "r"]:
		if plan.is_present("leg_%s_upper" % s):
			lu = maxf(lu, float(parts["leg_%s_upper" % s]["size"][1]))
		if plan.is_present("leg_%s_lower" % s):
			ll = maxf(ll, float(parts["leg_%s_lower" % s]["size"][1]))
	return {"H": h, "a": a, "sx": sx, "r": r, "lu": lu, "ll": ll, "has_arm": has_arm, "side": side}


## Abstand Griffpunkt → Arbeitskopf [m] des gehaltenen Objekts (0 = Hand oder Stück in der Hand).
static func tool_reach(ctx: LifeContext, held_id: int) -> float:
	if held_id == 0 or not ctx.assemblies.has(held_id):
		var mp: MaterialPiece = ctx.material_pieces.get(held_id, null)
		if mp != null and mp.shape == "rod":
			return mp.dims_m.x
		return 0.0
	var asm: Assembly = ctx.assemblies[held_id]
	if asm.head_part_id != 0:
		return float(asm.offsets.get(asm.head_part_id, 0.0))
	var far := 0.0
	for pid in asm.part_ids:
		var p: MaterialPiece = ctx.material_pieces.get(pid, null)
		if p != null:
			far = maxf(far, float(asm.offsets.get(pid, 0.0)) + p.dims_m.x * 0.5)
	return far


## Kopf- bzw. Handpunkt im Körperrahmen für eine Pose.
static func head_local(b: Dictionary, pose: Dictionary, h: float) -> Vector3:
	var phi := float(pose["phi"])
	var al := float(pose["alpha"])
	var be := float(pose["beta"])
	var sh := Vector3(float(b["sx"]), float(b["H"]) - float(pose["crouch"]) + float(b["a"]) * cos(phi), float(b["a"]) * sin(phi))
	var hand := sh + float(b["r"]) * Vector3(0.0, -cos(al), -sin(al))
	return hand + h * Vector3(0.0, -sin(be), cos(be))


## Kontaktpose: bringt Werkzeugkopf (h > 0) bzw. Hand (h = 0) auf die Höhe target_y (über dem Boden
## unter dem Wesen). kind "strike": Werkzeug schräg nach unten; "place": Hand senkt sich zum Ziel.
## Rückgabe {phi, crouch, alpha, beta, reach_z, head_y, ok}. ok = false: Höhe nicht erreichbar.
static func contact(b: Dictionary, h: float, target_y: float, kind: String = "strike") -> Dictionary:
	var al := -0.45 if kind == "strike" else -0.6
	var be := 0.75 if (kind == "strike" and h > 0.0) else al
	var cmax := CROUCH_MAX_SHARE * (float(b["lu"]) + float(b["ll"]))
	var best := {}
	var phi := 0.15
	while phi <= PHI_MAX + 1e-6:
		var pose := {"phi": phi, "crouch": 0.0, "alpha": al, "beta": be}
		var y0 := head_local(b, pose, h).y
		var need := y0 - target_y
		var c := clampf(need, 0.0, cmax)
		pose["crouch"] = c
		var hp := head_local(b, pose, h)
		pose["reach_z"] = hp.z
		pose["head_y"] = hp.y
		pose["ok"] = absf(hp.y - target_y) <= 0.03
		if pose["ok"]:
			return pose
		if best.is_empty() or absf(hp.y - target_y) < absf(float(best["head_y"]) - target_y):
			best = pose
		phi += 0.05
	return best


## Ausholpose (Schlag) bzw. Ruhepose mit Gegenstand.
static func windup(contact_pose: Dictionary) -> Dictionary:
	return {"phi": float(contact_pose["phi"]) * 0.35, "crouch": float(contact_pose["crouch"]) * 0.5, "alpha": -2.35, "beta": -2.05}


static func rest_hold() -> Dictionary:
	return {"phi": 0.0, "crouch": 0.0, "alpha": -0.15, "beta": 0.05}


static func lerp_pose(p: Dictionary, q: Dictionary, t: float) -> Dictionary:
	var k := clampf(t, 0.0, 1.0)
	return {"phi": lerpf(float(p["phi"]), float(q["phi"]), k), "crouch": lerpf(float(p["crouch"]), float(q["crouch"]), k),
		"alpha": lerpf(float(p["alpha"]), float(q["alpha"]), k), "beta": lerpf(float(p["beta"]), float(q["beta"]), k)}


## Standpunkt und Blickrichtung, damit der Kontaktpunkt (seitlich versetzt um sx, vorn um reach_z)
## genau auf target liegt. from: aktuelle Position (bestimmt die Anlaufrichtung).
static func stand_point(target: Vector3, from: Vector3, reach_z: float, sx: float) -> Dictionary:
	var d := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if d.length() < 0.01:
		d = Vector3(0, 0, 1)
	d = d.normalized()
	var hd := atan2(d.x, d.z)
	var fwd := Vector3(sin(hd), 0.0, cos(hd))
	var right := Vector3(cos(hd), 0.0, -sin(hd))
	var pos := target - right * sx - fwd * reach_z
	return {"pos": Vector3(pos.x, from.y, pos.z), "heading": hd}


## Körperrahmen → Welt (Wesenposition, Blickrichtung).
static func to_world(cr_pos: Vector3, heading: float, local: Vector3) -> Vector3:
	return cr_pos + Vector3(local.x * cos(heading) + local.z * sin(heading), local.y, -local.x * sin(heading) + local.z * cos(heading))


static func to_local(cr_pos: Vector3, heading: float, world: Vector3) -> Vector3:
	var d := world - cr_pos
	return Vector3(d.x * cos(heading) - d.z * sin(heading), d.y, d.x * sin(heading) + d.z * cos(heading))
