class_name ToolUseSystem
extends RefCounted
## Greifen, Halten, Temperatur am Griff, Kontaktverletzung und Schlagphysik (Prompt 6).
## Alle Berechnungen nutzen nur Material, Geometrie, Masse, Temperatur und Körperfähigkeiten –
## NIE den Namen (label) eines Gegenstands.
##
## Schlagmodell (vereinfachte Starrkörper-Näherung, Spielparameter in data/config/technology.json):
##   r   = Armlänge der Greifseite (Oberarm + Unterarm + Hand aus dem Körperplan)
##   I   = m_Hand·r² + Σ Teile m_i·(r + a_i)² (+ m·L²/12 für Stäbe), a_i = Abstand vom Griffpunkt
##   E   = min(E_Körper, ½·I·ω_max²) mit E_Körper = body_work_j_per_kg_body · Körpermasse · Greiffähigkeit
##   wirksame Arbeit am Ziel W = E · Kopplung(Zielmaterial) · Härtefaktor · Massenfaktor · (1 − ½·Verschleiß)
##     Härtefaktor = clamp(H_Kopf / H_Ziel, 0, 1)^0,5 · Massenfaktor = m_eff / (m_eff + 0,05 kg), m_eff = I / d²
##   Rückprall am Kopf R = E · (1 − Kopplung·Härtefaktor) · Kopfanteil (I_Kopf / I) → belastet die Verbindung
##   Verbindung: R > Belastbarkeit → Bruch; sonst Verschleiß += fatigue · (R / Belastbarkeit)²

const FOOD_HAND_NOTE := "Ein gehaltener Gegenstand belegt die Greifhand; Nahrung kann zusätzlich nur mit einer zweiten greiffähigen Hand getragen werden."


static func cfg(ctx: LifeContext, section: String) -> Dictionary:
	return ctx.tc(section)


# ── Körperbezogene Größen ─────────────────────────

static func hand_part(cr: Creature) -> String:
	var side := str(cr.caps.get("grasp_side", "r"))
	for pid in cr.plan.present_ids():
		var p: Dictionary = cr.plan.parts[pid]
		if str(p.get("side", "")) == side and str(p.get("function", "")) in ["greifen", "haken"]:
			return pid
	return ""


static func arm_length_m(cr: Creature) -> float:
	var side := str(cr.caps.get("grasp_side", "r"))
	var s := 0.0
	for pid in cr.plan.present_ids():
		var p: Dictionary = cr.plan.parts[pid]
		if str(p.get("side", "")) == side and str(p.get("function", "")) in ["arm", "unterarm", "greifen", "haken"]:
			s += float(p["size"][1])
	return maxf(0.05, s)


static func hand_mass_kg(cr: Creature, ctx: LifeContext) -> float:
	var hp := hand_part(cr)
	return cr.plan.part_mass(hp, ctx.sim.materials) if hp != "" else 0.05


static func hand_hardness(cr: Creature, ctx: LifeContext) -> float:
	var hp := hand_part(cr)
	if hp == "":
		return 0.3
	var m := ctx.sim.materials.get_material(str(cr.plan.parts[hp]["material_id"]))
	return m.w("hardness", 0.3) if m != null else 0.3


static func hand_position(cr: Creature) -> Vector3:
	var fwd := Vector3(sin(cr.heading), 0.0, cos(cr.heading))
	return cr.position + Vector3(0, 0.32, 0) + fwd * 0.18


static func carry_limit_kg(cr: Creature, ctx: LifeContext) -> float:
	return float(cfg(ctx, "hands").get("carry_kg_per_body_kg", 0.15)) * cr.mass_kg * float(cr.caps.get("grasp", 0.0))


static func swing_limit_kg(cr: Creature, ctx: LifeContext) -> float:
	return float(cfg(ctx, "hands").get("swing_kg_per_body_kg", 0.07)) * cr.mass_kg * float(cr.caps.get("grasp", 0.0))


static func free_hands(cr: Creature) -> int:
	var n := 0
	for s in cr.caps.get("grasp_by_side", {}):
		if float(cr.caps["grasp_by_side"][s]) > 0.0:
			n += 1
	var used := (1 if cr.carried_item_id != 0 else 0) + (1 if cr.held_object_id != 0 else 0)
	return n - used


# ── Temperatur (wahrnehmbar vs. exakt) ───────────

## Wahrnehmbare Kategorie ohne Messmittel (Wesenswissen). Exakte Werte nur als Spielerdiagnose.
static func temperature_category(ctx: LifeContext, t_k: float, liquid_fraction: float = 0.0) -> String:
	if liquid_fraction >= 1.0:
		return "flüssig (glühend)"
	if liquid_fraction > 0.0:
		return "schmilzt (glühend)"
	var tc: Dictionary = cfg(ctx, "temperature")
	for c in tc.get("categories", []):
		if t_k < float(c[0]):
			return str(c[1])
	return str(tc.get("glow_label", "glühend"))


static func object_temperature_category(ctx: LifeContext, id: int) -> String:
	var hot: MaterialPiece = null
	for p in ConstructionSystem.parts_of(ctx, id):
		if hot == null or (p as MaterialPiece).temperature_k() > hot.temperature_k():
			hot = p
	if hot == null:
		return "?"
	return temperature_category(ctx, hot.temperature_k(), hot.liquid_fraction())


static func safe_k(ctx: LifeContext) -> float:
	return float(cfg(ctx, "temperature").get("handle_safe_k", 318.15))


## Kurze Berührung eines zu heißen Griffs: Wärme fließt in die Hand (bilanziert), Verbrennung.
static func touch_burn(ctx: LifeContext, cr: Creature, piece: MaterialPiece, seconds: float, cause: String) -> Dictionary:
	var tc: Dictionary = cfg(ctx, "temperature")
	var t := piece.temperature_k()
	var over := t - safe_k(ctx)
	if over <= 0.0:
		return {"burned": false, "damage": 0.0, "q_j": 0.0}
	var q := ctx.sim.thermal.transfer_to_body(piece, float(tc.get("hand_conductance_w_k", 0.25)), 310.0, seconds)
	var dmg := minf(0.6, over * seconds * float(tc.get("burn_damage_per_k_s", 0.0008)))
	var hp := hand_part(cr)
	var res := {"burned": true, "damage": dmg, "q_j": q, "part": hp, "temperature_k": t}
	if hp != "":
		var r := cr.health.damage_part(cr.plan, hp, dmg, "Verbrennung: " + cause, ctx.now())
		if not r.get("removed", []).is_empty():
			cr.refresh_body(ctx)
	ctx.publish({"type": "burned_by_object", "actor": cr.id, "target": 0, "position": cr.position,
		"consequences": {"object": piece.id, "teil": hp, "schaden": dmg, "zuckt_zurück": true},
		"visibility_m": float(ctx.m("observation").get("gesture_visibility_m", 10.0))}, "warning")
	return res


# ── Greifen / Halten ─────────────────────────────

## Prüft, ob ein Wesen das (oberste) Objekt id greifen und halten kann. Ohne Seiteneffekte.
static func check_grasp(ctx: LifeContext, cr: Creature, id: int) -> ActionResult:
	var top := ConstructionSystem.top_id(ctx, id)
	if top == 0:
		return ActionResult.fail("target_lost", "Gegenstand #%d existiert nicht." % id)
	if float(cr.caps.get("grasp", 0.0)) <= 0.0:
		return ActionResult.fail("missing_capability", "Keine greiffähige Hand.")
	if cr.held_object_id == top:
		return ActionResult.success("bereits in der Hand")
	if cr.held_object_id != 0:
		return ActionResult.fail("hands_full", "Hält bereits #%d." % cr.held_object_id)
	if free_hands(cr) <= 0:
		return ActionResult.fail("hands_full", "Keine freie Greifhand (trägt Nahrung).")
	var carrier := ConstructionSystem.carrier_of(ctx, top)
	if carrier != 0:
		return ActionResult.fail("held_by_other", "#%d wird von #%d gehalten." % [top, carrier])
	var a: Assembly = ctx.assemblies.get(top, null)
	var mp: MaterialPiece = ctx.material_pieces.get(top, null)
	if (a != null and a.reserved_by != 0 and a.reserved_by != cr.id) or (mp != null and mp.reserved_by != 0 and mp.reserved_by != cr.id):
		return ActionResult.fail("reserved", "#%d ist von einem anderen Wesen reserviert." % top)
	if mp != null and mp.container_id != 0 and ctx.material_pieces.has(mp.container_id):
		return ActionResult.fail("in_container", "#%d liegt in Behälter/Form #%d." % [top, mp.container_id])
	var grip := ConstructionSystem.grip_piece(ctx, top)
	if grip == null:
		return ActionResult.fail("no_grip", "Kein Griffbereich.")
	if grip.liquid_fraction() > 0.0:
		return ActionResult.fail("liquid", "Flüssiges Material lässt sich nicht greifen.")
	var gw := float(cfg(ctx, "hands").get("grasp_max_width_m", 0.1))
	if grip.grip_width_m() > gw:
		return ActionResult.fail("no_grip", "Griffbereich zu breit (%.2f m > %.2f m)." % [grip.grip_width_m(), gw])
	var mass := ConstructionSystem.mass_of(ctx, top)
	var lim := carry_limit_kg(cr, ctx)
	if mass > lim:
		return ActionResult.fail("too_heavy", "Zu schwer zum Halten (%.2f kg > %.2f kg)." % [mass, lim])
	if grip.temperature_k() > safe_k(ctx):
		return ActionResult.fail("too_hot", "Griff zu heiß zum Anfassen (%s)." % temperature_category(ctx, grip.temperature_k()))
	return ActionResult.success()


static func hold(ctx: LifeContext, cr: Creature, id: int) -> void:
	var top := ConstructionSystem.top_id(ctx, id)
	ConstructionSystem.set_carrier(ctx, top, cr.id)
	cr.held_object_id = top
	if ctx.assemblies.has(top):
		(ctx.assemblies[top] as Assembly).container_id = 0
	ConstructionSystem.sync_positions(ctx)


static func release(ctx: LifeContext, cr: Creature, reason: String) -> int:
	var top := cr.held_object_id
	if top == 0:
		return 0
	cr.held_object_id = 0
	ConstructionSystem.set_carrier(ctx, top, 0)
	var ground := cr.position + Vector3(sin(cr.heading), 0.0, cos(cr.heading)) * 0.25
	if ctx.assemblies.has(top):
		(ctx.assemblies[top] as Assembly).position = ground + Vector3(-0.15, 0.02, 0)
	elif ctx.material_pieces.has(top):
		(ctx.material_pieces[top] as MaterialPiece).position = ground + Vector3(0, 0.02, 0)
	ConstructionSystem.sync_positions(ctx)
	ctx.log_event("object_released", [cr.id, top], {"reason": reason})
	return top


# ── Schwung und Schlag ────────────────────────────

## Kinematik des Schlags mit dem gehaltenen Objekt (top_id = 0: unbewaffnet, Hand trifft).
## Rückgabe: {ok, message, energy_j, inertia, omega, head_mass_kg, head_dist_m, m_eff_kg,
##            contact_material, contact_hardness, contact_shape, head_share, duration_s, power_w}
static func swing(ctx: LifeContext, cr: Creature, top_id: int) -> Dictionary:
	var sc: Dictionary = cfg(ctx, "strike")
	var r := arm_length_m(cr)
	var mh := hand_mass_kg(cr, ctx)
	var grasp := float(cr.caps.get("grasp", 0.0))
	var e_body := float(sc.get("body_work_j_per_kg_body", 0.5)) * cr.mass_kg * grasp
	var inertia := mh * r * r
	var head_i := 0.0
	var head_d := r
	var head_m := mh
	var contact_mat := ""
	var contact_h := hand_hardness(cr, ctx)
	var shape := "Hand"
	var head_piece: MaterialPiece = null
	var total_mass := 0.0
	if top_id != 0:
		total_mass = ConstructionSystem.mass_of(ctx, top_id)
		if total_mass > swing_limit_kg(cr, ctx):
			return {"ok": false, "code": "too_heavy_to_swing", "message": "Zu schwer zum Schwingen (%.2f kg > %.2f kg)." % [total_mass, swing_limit_kg(cr, ctx)]}
		var a: Assembly = ctx.assemblies.get(top_id, null)
		if a != null:
			for p in ConstructionSystem.parts_of(ctx, top_id):
				var off := float(a.offsets.get(p.id, 0.0))
				var d := r + off
				var ip: float = p.mass_kg * d * d
				if p.shape == "rod":
					ip += p.mass_kg * p.dims_m.x * p.dims_m.x / 12.0
				inertia += ip
			if a.head_part_id != 0 and ctx.material_pieces.has(a.head_part_id):
				head_piece = ctx.material_pieces[a.head_part_id]
				head_d = r + float(a.offsets.get(head_piece.id, 0.0))
			else:
				# kein Arbeitskopf: das Ende des längsten Stabs trifft
				var far := 0.0
				for p in ConstructionSystem.parts_of(ctx, top_id):
					var off2: float = float(a.offsets.get(p.id, 0.0)) + p.dims_m.x * 0.5
					if off2 > far:
						far = off2
						head_piece = p
				head_d = r + far
		else:
			var mp: MaterialPiece = ctx.material_pieces[top_id]
			head_piece = mp
			if mp.shape == "rod":
				# Stab am Ende gehalten: Schwerpunkt bei L/2, Treffpunkt am Ende
				inertia += mp.mass_kg * pow(r + mp.dims_m.x * 0.5, 2) + mp.mass_kg * mp.dims_m.x * mp.dims_m.x / 12.0
				head_d = r + mp.dims_m.x
			else:
				inertia += mp.mass_kg * r * r
				head_d = r
		contact_mat = head_piece.material_id
		contact_h = head_piece.material().w("hardness", 1.0)
		shape = {"block": "flache Fläche", "ingot": "flache Fläche", "lump": "gerundet", "rod": "schmales Stabende", "bundle": "weich, faserig", "cup": "Gefäßwand", "mold": "Formwand"}.get(head_piece.shape, head_piece.shape)
		head_m = head_piece.mass_kg
		head_i = head_m * head_d * head_d
	else:
		head_i = inertia
	var w_max := float(sc.get("arm_omega_max_rad_s", 14.0))
	var e_speed := 0.5 * inertia * w_max * w_max
	var energy := minf(e_body, e_speed)
	var omega := sqrt(2.0 * energy / inertia) if inertia > 0.0 else 0.0
	var m_eff := inertia / (head_d * head_d)
	var duration := float(sc.get("base_duration_s", 0.7)) + float(sc.get("duration_per_sqrt_inertia_s", 1.2)) * sqrt(inertia)
	var power := energy / float(sc.get("muscle_efficiency", 0.25)) / duration
	return {"ok": true, "message": "", "energy_j": energy, "energy_body_j": e_body, "energy_speed_j": e_speed, "inertia": inertia,
		"omega": omega, "arm_m": r, "head_mass_kg": head_m, "head_dist_m": head_d, "m_eff_kg": m_eff,
		"head_piece": head_piece.id if head_piece != null else 0, "contact_material": contact_mat if contact_mat != "" else "Hand",
		"contact_hardness": contact_h, "contact_shape": shape, "head_share": clampf(head_i / inertia, 0.0, 1.0) if inertia > 0.0 else 0.0,
		"duration_s": duration, "power_w": power, "tool_mass_kg": total_mass, "head_speed_m_s": omega * head_d}


## Kopplung je Zielmaterial: plastisch (Kupfer) > spröde (Stein) > sonstige.
static func coupling(ctx: LifeContext, target: MaterialPiece) -> float:
	var sc: Dictionary = cfg(ctx, "strike")
	var m := target.material()
	if m.is_plastic():
		return float(sc.get("coupling_plastic", 0.8))
	if m.fracture_behavior == "brittle":
		return float(sc.get("coupling_brittle", 0.5))
	return float(sc.get("coupling_other", 0.3))


## Vorhersage ohne Seiteneffekte: wirksame Arbeit eines Schlags mit sw auf target.
static func predict_work(ctx: LifeContext, sw: Dictionary, target: MaterialPiece, tool_wear: float = 0.0) -> Dictionary:
	var sc: Dictionary = cfg(ctx, "strike")
	var ht := maxf(0.05, target.material().w("hardness", 1.0))
	var hard_f := pow(clampf(float(sw["contact_hardness"]) / ht, 0.0, 1.0), 0.5)
	var mass_f := float(sw["m_eff_kg"]) / (float(sw["m_eff_kg"]) + 0.05)
	var cpl := coupling(ctx, target)
	var wear_f := 1.0 - float(sc.get("wear_efficiency_loss", 0.5)) * clampf(tool_wear, 0.0, 1.0)
	var work := float(sw["energy_j"]) * cpl * hard_f * mass_f * wear_f
	var rebound := float(sw["energy_j"]) * (1.0 - cpl * hard_f) * float(sw["head_share"])
	return {"work_j": work, "rebound_j": rebound, "hardness_factor": hard_f, "mass_factor": mass_f, "coupling": cpl, "wear_factor": wear_f}


## Verschleiß des Werkzeugkopfs je Schlag (1.0 = zerstört): stärker an härteren Zielen, schwächer bei
## schwerem Kopf. Dieselbe Formel nutzen Schlag und Bewertung.
static func head_wear_per_strike(ctx: LifeContext, sw: Dictionary, head: MaterialPiece, target_hardness: float) -> float:
	var sc: Dictionary = cfg(ctx, "strike")
	var hh := maxf(0.05, head.material().w("hardness", 1.0))
	return float(sc.get("tool_wear_per_j", 0.001)) * float(sw["energy_j"]) * pow(target_hardness / hh, 2.0) / maxf(0.05, head.mass_kg * 5.0)


## Ein Schlag des Wesens mit dem gehaltenen Objekt (oder der Hand) auf target_id.
## Wirkt tatsächlich: Zielbearbeitung (MaterialProcessSystem.work_piece), Werkzeugverschleiß,
## Verbindungsbelastung/-bruch, Handverletzung, Hitzekontakt. Rückgabe mit allen Messgrößen.
static func strike(ctx: LifeContext, cr: Creature, target_id: int) -> Dictionary:
	var sc: Dictionary = cfg(ctx, "strike")
	var target: MaterialPiece = ctx.material_pieces.get(target_id, null)
	if target == null:
		return {"ok": false, "code": "target_lost", "message": "Ziel #%d existiert nicht mehr." % target_id}
	var top := cr.held_object_id
	var sw := swing(ctx, cr, top)
	if not sw["ok"]:
		return sw
	var tool_wear := 0.0
	var head: MaterialPiece = ctx.material_pieces.get(int(sw["head_piece"]), null)
	if head != null:
		tool_wear = head.wear
	var pr := predict_work(ctx, sw, target, tool_wear)
	var ht := target.material().w("hardness", 1.0)
	var proc_key := ProceduralKnowledge.strike_key(str(sw["contact_material"]), TechActionUtil.tool_form(ctx, top), target.material_id)
	var res := {"ok": true, "tool": top, "target": target_id, "energy_j": sw["energy_j"], "work_j": pr["work_j"], "rebound_j": pr["rebound_j"],
		"contact": sw["contact_material"], "hardness_factor": pr["hardness_factor"], "mass_factor": pr["mass_factor"], "joint": "", "broke": false,
		"tool_wear": 0.0, "hand_damage": 0.0, "power_w": sw["power_w"], "duration_s": sw["duration_s"]}
	# Ziel bearbeiten
	var thickness_before := target.dims_m.y
	var wr := MaterialProcessSystem.work_piece(ctx, target, float(pr["work_j"]))
	res["effect"] = wr
	res["thickness_before_m"] = thickness_before
	res["thickness_after_m"] = target.dims_m.y if ctx.material_pieces.has(target_id) else 0.0
	# Werkzeugkopf verschleißt (stärker an härteren Zielen)
	if head != null:
		var dw := head_wear_per_strike(ctx, sw, head, ht)
		head.wear = minf(1.0, head.wear + dw)
		res["tool_wear"] = dw
		if head.wear >= 1.0 and not head.material().is_plastic() and ctx.material_pieces.has(head.id):
			res["tool_fracture"] = MaterialProcessSystem.fracture_piece(ctx, head)
	else:
		# unbewaffnet: harte Ziele verletzen die Hand
		var hh2 := hand_hardness(cr, ctx)
		if ht > hh2:
			var dmg := float(sc.get("hand_damage_per_j", 0.004)) * float(sw["energy_j"]) * minf(1.0, (ht - hh2) / ht)
			var hp := hand_part(cr)
			if hp != "" and dmg > 0.0:
				cr.health.damage_part(cr.plan, hp, dmg, "Schlag mit bloßer Hand auf %s" % target.material_id, ctx.now())
				res["hand_damage"] = dmg
	# Verbindung belasten
	if top != 0 and ctx.assemblies.has(top):
		var a: Assembly = ctx.assemblies[top]
		for c in a.connections:
			var load := float(pr["rebound_j"]) * float(cfg(ctx, "connection").get("joint_rebound_share", 1.0))
			c["strikes"] = int(c["strikes"]) + 1
			res["joint_load_j"] = load
			res["joint_capacity_j"] = c["capacity_j"]
			if load > float(c["capacity_j"]):
				res["joint"] = "überlastet"
				res["broke"] = true
			else:
				c["wear"] = float(c["wear"]) + float(c.get("fatigue", 0.03)) * pow(load / maxf(1e-6, float(c["capacity_j"])), 2.0)
				if float(c["wear"]) >= 1.0:
					c["wear"] = 1.0
					res["joint"] = "verschlissen"
					res["broke"] = true
				else:
					res["joint"] = "hält"
					res["joint_wear"] = c["wear"]
		if res["broke"]:
			ConstructionSystem.dissolve(ctx, top, "Verbindung %s (Last %.2f J, Belastbarkeit %.2f J)" % [res["joint"], float(res.get("joint_load_j", 0.0)), float(res.get("joint_capacity_j", 0.0))], true, cr.id)
	# heißer Griff während des Schlags
	if top != 0:
		var g := ConstructionSystem.grip_piece(ctx, cr.held_object_id) if cr.held_object_id != 0 else null
		if g != null and g.temperature_k() > safe_k(ctx):
			res["burn"] = touch_burn(ctx, cr, g, float(sw["duration_s"]), "heißer Griff beim Schlagen")
	ctx.publish({"type": "object_struck", "actor": cr.id, "target": 0, "position": target.position,
		"consequences": {"tool": top, "piece": target_id, "contact": sw["contact_material"], "effect": str(wr.get("kind", "")),
			"broke": res["broke"], "verfahren": proc_key,
			"sichtbare_stauchung": (1.0 - exp(-target.strain)) if ctx.material_pieces.has(target_id) else 0.0}, "visibility_m": float(cfg(ctx, "teaching").get("demo_visibility_m", 6.0))})
	res["key"] = proc_key
	return res


# ── Testheizung ───────────────────────────────────

## Behälter (Verbund mit Tiegelkörper oder einzelner Tiegel) in die Heizung setzen.
static func place_in_heater(ctx: LifeContext, cr: Creature, obj_id: int, heater_id: int) -> Dictionary:
	var h: TestHeater = ctx.heaters.get(heater_id, null)
	if h == null:
		return {"ok": false, "code": "no_heater", "message": "Keine Heizung #%d." % heater_id}
	if h.slot_id != 0:
		return {"ok": false, "code": "heater_full", "message": "Heizung #%d ist belegt (#%d)." % [heater_id, h.slot_id]}
	var top := ConstructionSystem.top_id(ctx, obj_id)
	var cup: MaterialPiece = null
	for p in ConstructionSystem.parts_of(ctx, top):
		if (p as MaterialPiece).shape == "cup":
			cup = p
	if cup == null:
		return {"ok": false, "code": "no_container", "message": "Nur ein unterstützter Behälter (Tiegel) darf in die Heizung."}
	if cup.material().valid_max_k < 1000.0:
		return {"ok": false, "code": "container_incompatible", "message": "Behältermaterial %s ist für die Heizung ungeeignet." % cup.material().display_name}
	if cr != null and cr.held_object_id == top:
		cr.held_object_id = 0
		ConstructionSystem.set_carrier(ctx, top, 0)
	if ctx.assemblies.has(top):
		(ctx.assemblies[top] as Assembly).container_id = heater_id
	else:
		cup.container_id = heater_id
	h.slot_id = top
	h.target_piece_id = cup.id
	var th := ctx.sim.thermal
	if not th.heaters.has(h.heater_name()):
		th.add_heater(h.heater_name(), cup.id, h.power_w)
	th.retarget(h.heater_name(), cup.id)
	th.set_heater(h.heater_name(), true, h.power_w)
	ConstructionSystem.sync_positions(ctx)
	ctx.publish({"type": "placed_in_heater", "actor": cr.id if cr != null else 0, "target": 0, "position": h.position,
		"consequences": {"object": top, "heater": heater_id}, "visibility_m": float(cfg(ctx, "teaching").get("demo_visibility_m", 6.0))})
	return {"ok": true, "message": "#%d steht in Testheizung #%d (%.0f W, extern versorgt)." % [top, heater_id, h.power_w]}


static func remove_from_heater(ctx: LifeContext, heater_id: int) -> int:
	var h: TestHeater = ctx.heaters.get(heater_id, null)
	if h == null or h.slot_id == 0:
		return 0
	var top := h.slot_id
	if ctx.assemblies.has(top):
		(ctx.assemblies[top] as Assembly).container_id = 0
	elif ctx.material_pieces.has(top):
		(ctx.material_pieces[top] as MaterialPiece).container_id = 0
	h.slot_id = 0
	h.target_piece_id = 0
	ctx.sim.thermal.set_heater(h.heater_name(), false)
	return top


static func heater_of(ctx: LifeContext, top_id: int) -> int:
	for hid in ctx.heaters:
		if (ctx.heaters[hid] as TestHeater).slot_id == top_id:
			return hid
	return 0


## Takt: gehaltene Gegenstände folgen der Hand; heißer Griff → Wärme in die Hand, Verbrennung,
## Reflex: loslassen. Kritische Reaktion lokal, keine Modellanfrage.
static func tick(ctx: LifeContext, dt: float) -> void:
	ConstructionSystem.sync_positions(ctx)
	var tc: Dictionary = cfg(ctx, "temperature")
	for cid in ctx.creatures:
		var cr: Creature = ctx.creatures[cid]
		if cr.held_object_id == 0 or not cr.alive:
			continue
		var g := ConstructionSystem.grip_piece(ctx, cr.held_object_id)
		if g == null:
			continue
		var t := g.temperature_k()
		if t > 310.0:
			ctx.sim.thermal.transfer_to_body(g, float(tc.get("hand_conductance_w_k", 0.25)), 310.0, dt)
		if t > safe_k(ctx):
			touch_burn(ctx, cr, g, float(tc.get("touch_s", 0.25)), "Griff wurde heiß")
			if ctx.executor.running.has(cid):
				ctx.executor.cancel(cid, "too_hot", "Griff zu heiß – losgelassen.")
			release(ctx, cr, "Reflex: Griff zu heiß")
