class_name WorkPose
extends RefCounted
## Geometrie der Arbeitsbewegungen (Prompt 6B). Schulterhöhe, Armlänge und Beinlängen stammen aus dem
## Körperplan, der Abstand Griff→Arbeitskopf aus dem tatsächlich gehaltenen Gegenstand. DIESELBEN
## Formeln nutzen die Handlungen (Standabstand zum Ziel) und die Animation (Gelenkwinkel). Damit liegt
## der sichtbare Kontakt am Ziel („kein Hämmern neben dem Ziel“) – prüfbar ohne Grafik (TestWorkChain).
##
## Ebenes Gelenkmodell im Körperrahmen (+z vorne, +y oben, x seitlich wie die Gelenkanschlüsse):
##   Rumpfneigung φ (um x, vorwärts positiv), Hocke c (Hüfte tiefer), Armwinkel α (global, 0 = hängt
##   senkrecht, negativ = nach vorn gehoben), Werkzeugwinkel β (global; Werkzeugachse = (0, −sin β, cos β)).
##   Die Faust hält die Werkzeugachse unter dem festen Griffwinkel G zur Handachse; die Hand (bzw. eine
##   Hakenprothese) zeigt daher in Richtung γ = β − G (Beugung im Handgelenk bzw. Ellbogen: γ − α).
##   Schulter  = (sx, H − c + a·cos φ, a·sin φ)
##   Gelenk    = Schulter + r·(0, −cos α, −sin α)        (r: Ober- + Unterarm bzw. nur Oberarm bei Haken)
##   Griff     = Gelenk + g·(0, −cos γ, −sin γ)          (g: halbe Handlänge bzw. Hakenlänge)
##   Kopf      = Griff + h·(0, −sin β, cos β)            (h: Abstand Griff → Arbeitskopf)
## Vereinfachung (dokumentiert): Ellbogen bei vorhandener Hand gestreckt (Ober- und Unterarm in einer
## Linie); seitliche Armbewegung (Abspreizen) ist für arbeitende Arme 0.

const PHI_MAX := 1.0
const CROUCH_MAX_SHARE := 0.48
const GRIP_ANGLE := 0.785   # 45°: Werkzeugachse in der Faust gegenüber der Handachse (Hand-+z, nach unten gedreht)


## Körpermaße einer Seite aus dem Körperplan (Ruhelage).
## Rückgabe: H, a, sx, r, g, lu, ll, has_arm, grasp ("hand"/"hook"/""), upper/lower/last (Gelenk-IDs).
static func body(plan: BodyPlan, side: String) -> Dictionary:
	var parts: Dictionary = plan.parts
	var h := float(plan.genes.get("stand_height_m", 0.35))
	var torso: Dictionary = parts.get("torso", {})
	var up_id := "arm_%s_upper" % side
	var lo_id := "arm_%s_lower" % side
	var hand_id := "hand_%s" % side
	var a := 0.2
	var sx := 0.08 * (1.0 if side == "r" else -1.0)
	var r := 0.0
	var g := 0.0
	var has_arm := false
	var grasp := ""
	var lower := ""
	var last := ""
	if plan.is_present(up_id):
		var at: Array = parts[up_id]["attach"]
		a = float(at[1])
		sx = float(at[0])
		has_arm = true
		r = float(parts[up_id]["size"][1])
		last = up_id
		var pros := plan.present_prosthesis(side)
		if plan.is_present(lo_id):
			lower = lo_id
			last = lo_id
			r += float(parts[lo_id]["size"][1])
			if plan.is_present(hand_id):
				g = float(parts[hand_id]["size"][1]) * 0.5
				last = hand_id
				grasp = "hand"
		elif pros != "":
			# Prothese am Ellbogen: Haken greift an seinem Ende, Holzstütze greift nicht
			g = float(parts[pros]["size"][1])
			last = pros
			grasp = "hook" if str(parts[pros].get("function", "")) == "haken" else ""
	elif not torso.is_empty():
		a = float(torso["size"][1]) * 0.78
	var lu := 0.0
	var ll := 0.0
	for s in ["l", "r"]:
		if plan.is_present("leg_%s_upper" % s):
			lu = maxf(lu, float(parts["leg_%s_upper" % s]["size"][1]))
		if plan.is_present("leg_%s_lower" % s):
			ll = maxf(ll, float(parts["leg_%s_lower" % s]["size"][1]))
	return {"H": h, "a": a, "sx": sx, "r": r, "g": g, "lu": lu, "ll": ll, "has_arm": has_arm, "grasp": grasp,
		"side": side, "upper": up_id if has_arm else "", "lower": lower, "last": last}


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


## Handrichtung γ einer Pose (Werkzeugwinkel minus Griffwinkel).
static func hand_angle(pose: Dictionary) -> float:
	return float(pose["beta"]) - GRIP_ANGLE


## Griffwinkel β, bei dem das Handgelenk gerade ist (Hand in Verlängerung des Arms).
static func neutral_beta(alpha: float) -> float:
	return alpha + GRIP_ANGLE


static func shoulder_local(b: Dictionary, pose: Dictionary) -> Vector3:
	var phi := float(pose["phi"])
	return Vector3(float(b["sx"]), float(b["H"]) - float(pose["crouch"]) + float(b["a"]) * cos(phi), float(b["a"]) * sin(phi))


## Griffpunkt (Handmitte bzw. Hakenende) im Körperrahmen.
static func grip_local(b: Dictionary, pose: Dictionary) -> Vector3:
	var al := float(pose["alpha"])
	var ga := hand_angle(pose)
	var wrist := shoulder_local(b, pose) + float(b["r"]) * Vector3(0.0, -cos(al), -sin(al))
	return wrist + float(b["g"]) * Vector3(0.0, -cos(ga), -sin(ga))


## Werkzeugachse (Einheitsvektor) im Körperrahmen.
static func tool_axis(pose: Dictionary) -> Vector3:
	var be := float(pose["beta"])
	return Vector3(0.0, -sin(be), cos(be))


## Kopf- bzw. Griffpunkt (h = 0) im Körperrahmen für eine Pose.
static func head_local(b: Dictionary, pose: Dictionary, h: float) -> Vector3:
	return grip_local(b, pose) + h * tool_axis(pose)


## Kontaktpose: bringt Werkzeugkopf (h > 0) bzw. Griffpunkt (h = 0) auf die Höhe target_y (über dem Boden
## unter dem Wesen). kind "strike": Werkzeug schräg nach unten; "place": Hand senkt sich zum Ziel;
## "pour": Gefäß vor dem Körper leicht geneigt. Gesucht wird in einer festen Vorzugsreihenfolge von Arm-/
## Werkzeugwinkeln (zuerst die typische Haltung, für hohe bzw. tiefe Ziele angehobener bzw. hängender Arm),
## je mit Rumpfneigung φ und Hocke c (Knie). Rückgabe {phi, crouch, alpha, beta, reach_z, head_y, ok}.
## ok = false: Höhe mit diesem Körper nicht erreichbar (beste Näherung wird geliefert).
static func contact(b: Dictionary, h: float, target_y: float, kind: String = "strike") -> Dictionary:
	var cands: Array = []
	match kind:
		"strike":
			if h > 0.0:
				cands = [[-0.45, 0.75], [-0.6, 0.6], [-0.8, 0.45], [-1.0, 0.3], [-1.2, 0.15], [-1.4, 0.0], [-0.3, 0.9], [-0.15, 1.05]]
			else:
				for al in [-0.45, -0.7, -0.95, -1.2, -0.3, -0.15, 0.0]:
					cands.append([al, neutral_beta(al)])
		"pour":
			cands = [[-0.75, 0.3], [-0.95, 0.15], [-1.15, 0.0], [-0.55, 0.45], [-0.35, 0.6]]
		_:
			for al2 in [-0.6, -0.8, -1.0, -1.2, -1.4, -0.45, -0.3, -0.15, 0.0]:
				cands.append([al2, neutral_beta(al2)])
	var cmax := CROUCH_MAX_SHARE * (float(b["lu"]) + float(b["ll"]))
	var best := {}
	for cand in cands:
		var al3 := float(cand[0])
		var be := float(cand[1])
		var phi := 0.15
		while phi <= PHI_MAX + 1e-6:
			var pose := {"phi": phi, "crouch": 0.0, "alpha": al3, "beta": be}
			var y0 := head_local(b, pose, h).y
			pose["crouch"] = clampf(y0 - target_y, 0.0, cmax)
			var hp := head_local(b, pose, h)
			pose["reach_z"] = hp.z
			pose["head_y"] = hp.y
			pose["ok"] = absf(hp.y - target_y) <= 0.02
			if pose["ok"]:
				return pose
			if best.is_empty() or absf(hp.y - target_y) < absf(float(best["head_y"]) - target_y):
				best = pose
			phi += 0.05
	return best


## Ausholpose (Schlag): Arm hoch über die Schulter, Werkzeug nach hinten gekippt.
static func windup(contact_pose: Dictionary) -> Dictionary:
	return {"phi": float(contact_pose["phi"]) * 0.35, "crouch": float(contact_pose["crouch"]) * 0.5, "alpha": -2.35, "beta": -2.05}


## Haltepose mit einem Gegenstand in einer Hand (Arm leicht vorn, Handgelenk gerade).
static func rest_hold() -> Dictionary:
	return {"phi": 0.0, "crouch": 0.0, "alpha": -0.15, "beta": neutral_beta(-0.15)}


## Tragehaltung mit beiden Händen (Gegenstand vor dem Körper).
static func carry_two_hold() -> Dictionary:
	return {"phi": 0.05, "crouch": 0.0, "alpha": -0.75, "beta": neutral_beta(-0.75)}


## Ruhehaltung ohne Gegenstand (Arm hängt).
static func rest_free() -> Dictionary:
	return {"phi": 0.0, "crouch": 0.0, "alpha": 0.0, "beta": neutral_beta(0.0)}


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


## Lage eines gehaltenen Werkzeugs im Rahmen des letzten Armgelenks (Hand bzw. Haken):
## Ursprung im Griffpunkt, +x = Werkzeugachse (Griff → Kopf), +y = „oben“ des Werkzeugs.
static func tool_frame(b: Dictionary) -> Transform3D:
	var x := Vector3(0.0, -sin(GRIP_ANGLE), cos(GRIP_ANGLE))
	var y := Vector3(0.0, cos(GRIP_ANGLE), sin(GRIP_ANGLE))
	return Transform3D(Basis(x, y, x.cross(y)), Vector3(0.0, -float(b["g"]), 0.0))
