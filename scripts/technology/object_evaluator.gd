class_name ObjectEvaluator
extends RefCounted
## Funktionale Bewertung eines Gegenstands als einfaches SCHLAGWERKZEUG (Prompt 6).
## Grundlage sind ausschließlich Geometrie, Masse, Material, Verbindungen, Temperatur und die
## Körperfähigkeiten des bewertenden Wesens. Der Name (label) fließt NICHT ein – ein „Hammer“
## ohne geeigneten Kopf bleibt ungeeignet.
##
## Vergleichsgröße: vorhergesagte Stauchung je Schlag an einer Referenz-Kupferprobe
## (20-mm-Würfel, kalt, unverformt) und Schaden je Schlag an einem Referenzstein (0,2 kg).
## Die Vorhersage nutzt dieselben Formeln wie der tatsächliche Schlag (ToolUseSystem).

const REF_COPPER_EDGE_M := 0.02
const REF_STONE_KG := 0.2


static func evaluate(ctx: LifeContext, cr: Creature, top_id: int) -> Dictionary:
	var r := {"id": top_id, "checks": [], "suitable": false, "score": 0.0}
	var checks: Array = r["checks"]
	var is_unarmed := top_id == 0
	if not is_unarmed:
		top_id = ConstructionSystem.top_id(ctx, top_id)
		if top_id == 0:
			checks.append(["Gegenstand vorhanden", false, "existiert nicht"])
			return r
		r["id"] = top_id
		var grip := ConstructionSystem.grip_piece(ctx, top_id)
		var gw := float(ctx.tc("hands").get("grasp_max_width_m", 0.1))
		checks.append(["Griff erreichbar", grip != null and grip.grip_width_m() <= gw, "Griffbreite %.3f m (Hand bis %.2f m)" % [grip.grip_width_m() if grip != null else 0.0, gw]])
		var mass := ConstructionSystem.mass_of(ctx, top_id)
		var lim := ToolUseSystem.carry_limit_kg(cr, ctx)
		var slim := ToolUseSystem.swing_limit_kg(cr, ctx)
		checks.append(["Masse tragbar", mass <= lim, "%.3f kg (tragbar bis %.2f kg)" % [mass, lim]])
		checks.append(["Masse schwingbar", mass <= slim, "%.3f kg (schwingbar bis %.2f kg)" % [mass, slim]])
		var a: Assembly = ctx.assemblies.get(top_id, null)
		var has_head := false
		if a != null:
			has_head = a.head_part_id != 0 and ctx.material_pieces.has(a.head_part_id)
			for c in a.connections:
				checks.append(["Verbindung belastbar", float(c["capacity_j"]) > 0.0 and float(c["wear"]) < 1.0,
					"%s: Belastbarkeit %.2f J je Schlag, Verschleiß %.0f %%, Passung %.0f %%" % [ConnectionDefinition.label(str(c["method"])), float(c["capacity_j"]), float(c["wear"]) * 100.0, float(c.get("fit", 1.0)) * 100.0]])
		else:
			var mp: MaterialPiece = ctx.material_pieces[top_id]
			has_head = mp.shape in ConnectionDefinition.HEAD_SHAPES
		checks.append(["Arbeitskopf vorhanden", has_head, "kompakter Kopf" if has_head else "kein kompakter Kopf (Stab/Bündel trifft mit Ende oder Seite)"])
		var tmax := ConstructionSystem.max_temperature_k(ctx, top_id)
		var g_ok := grip != null and grip.temperature_k() <= ToolUseSystem.safe_k(ctx)
		checks.append(["Griff nicht zu heiß", g_ok, ToolUseSystem.temperature_category(ctx, grip.temperature_k() if grip != null else 0.0)])
		r["mass_kg"] = mass
		r["max_temperature_k"] = tmax
		r["has_head"] = has_head
	var sw := ToolUseSystem.swing(ctx, cr, top_id)
	if not sw["ok"]:
		checks.append(["Schwung möglich", false, str(sw["message"])])
		r["swing"] = sw
		return r
	r["swing"] = sw
	checks.append(["Schwung möglich", true, "%.1f J je Schlag (Körpergrenze %.1f J, Geschwindigkeitsgrenze %.1f J)" % [float(sw["energy_j"]), float(sw["energy_body_j"]), float(sw["energy_speed_j"])]])
	var head: MaterialPiece = ctx.material_pieces.get(int(sw["head_piece"]), null)
	var wear := head.wear if head != null else 0.0
	var cu := _ref_piece(ctx, "copper", Vector3.ONE * REF_COPPER_EDGE_M)
	var st := _ref_piece(ctx, "stone", Vector3.ONE * pow(REF_STONE_KG / 2700.0, 1.0 / 3.0))
	var p_cu := ToolUseSystem.predict_work(ctx, sw, cu, wear)
	var p_st := ToolUseSystem.predict_work(ctx, sw, st, wear)
	var de := minf(MaterialProcessSystem.MAX_STRAIN_PER_STRIKE, float(p_cu["work_j"]) / (MaterialProcessSystem.flow_stress_pa(cu) * cu.volume_m3()))
	var dd := float(p_st["work_j"]) / (st.mass_kg * st.material().toughness_j_kg)
	r["copper_strain_per_strike"] = de
	r["copper_work_j"] = p_cu["work_j"]
	r["stone_damage_per_strike"] = dd
	r["rebound_on_copper_j"] = p_cu["rebound_j"]
	r["contact"] = "%s (%s, Härte %.1f)" % [sw["contact_material"], sw["contact_shape"], float(sw["contact_hardness"])]
	checks.append(["Kopf härter als Kupfer", float(p_cu["hardness_factor"]) >= 0.99, "Härtefaktor %.2f" % float(p_cu["hardness_factor"])])
	# Haltbarkeit des Kopfes am Kupfer (gleiche Formel wie der echte Schlag); plastische Köpfe zerfallen nicht
	if head != null:
		var dw := ToolUseSystem.head_wear_per_strike(ctx, sw, head, cu.material().w("hardness", 1.0))
		var left := (1.0 - wear) / maxf(1e-9, dw)
		r["head_wear_per_strike"] = dw
		r["strikes_until_head_fails"] = left if not head.material().is_plastic() else INF
		checks.append(["Kopf hält Kupfer stand", head.material().is_plastic() or left >= 10.0,
			"Verschleiß %.1f %% je Schlag → %s" % [dw * 100.0, ("zerfällt beim ersten Schlag" if left <= 1.0 else "etwa %d Schläge" % int(floor(left))) if not head.material().is_plastic() else "verformbar, zerfällt nicht"]])
	r["score"] = de / float(sw["duration_s"])
	var all_ok := true
	for c in checks:
		if not bool(c[1]) and str(c[0]) != "Kopf härter als Kupfer":
			all_ok = false
	r["suitable"] = all_ok and de >= 0.004
	return r


## Referenzstück NUR für die Vorhersage (wird nicht registriert, existiert nicht in der Welt).
static func _ref_piece(ctx: LifeContext, mid: String, dims: Vector3) -> MaterialPiece:
	var errs: Array = []
	return MaterialPiece.make(ctx.sim.materials, mid, "block", dims, 293.15, errs)


static func lines(ev: Dictionary) -> Array:
	var L: Array = []
	for c in ev.get("checks", []):
		L.append("%s %s: %s" % ["✔" if c[1] else "✘", c[0], c[2]])
	if ev.has("copper_strain_per_strike"):
		L.append("Vorhersage Kupfer-Referenz: Stauchung %.4f je Schlag (%.2f J wirksam) · Stein-Referenz: Schaden %.0f %% je Schlag" % [float(ev["copper_strain_per_strike"]), float(ev["copper_work_j"]), float(ev["stone_damage_per_strike"]) * 100.0])
	L.append("Eignung als Schlagwerkzeug: %s (Kennzahl %.4f Stauchung/s)" % ["geeignet" if ev.get("suitable", false) else "ungeeignet", float(ev.get("score", 0.0))])
	return L
