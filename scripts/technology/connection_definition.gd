class_name ConnectionDefinition
extends RefCounted
## Unterstützte Verbindungsmethoden (Prompt 6). Nur hier definierte Methoden sind ausführbar.
## Eine Verbindung ohne passende Methode und reales Verbindungsmittel ist unmöglich.
##
## lashing  – Stiel + Arbeitskopf mit Pflanzenfasern umwickeln (für Wesen verfügbar).
##            Belastbarkeit [J je Schlag] = Fasermasse · binding_energy_j_per_kg(Faser) · Passung · Geschick
##            Passung = min(1, verwendete Fasermasse / (fiber_need_kg_per_kg_head · Kopfmasse))
## test_fixture – fest montierte Testausrüstung (Tiegel mit Griff). Für Wesen NICHT verfügbar.

const METHODS := {
	"lashing": {"label": "Umwickeln mit Pflanzenfasern", "binding_material": "plant_fiber", "creature_usable": true},
	"test_fixture": {"label": "Fest montiert (Testausrüstung)", "binding_material": "", "creature_usable": false},
}

const HEAD_SHAPES := ["block", "lump", "ingot"]


static func is_supported(m: String) -> bool:
	return METHODS.has(m)


static func label(m: String) -> String:
	return str(METHODS.get(m, {}).get("label", m))


static func creature_usable(m: String) -> bool:
	return bool(METHODS.get(m, {}).get("creature_usable", false))


## Prüft eine Umwicklung. Rückgabe {ok, code, message, fiber_use_kg, capacity_j, fit, skill, need_kg}.
## Prüft NUR Material/Geometrie/Mengen/Temperatur – Reichweite, Besitz und Reservierung prüft die Handlung.
static func check_lashing(ctx: LifeContext, handle: MaterialPiece, head: MaterialPiece, fiber: MaterialPiece, skill_level: String) -> Dictionary:
	var cc: Dictionary = ctx.tc("connection").get("lashing", {})
	if handle == null or head == null or fiber == null:
		return _no("missing_part", "Stiel, Kopf oder Fasern fehlen.")
	if handle.id == head.id or handle.id == fiber.id or head.id == fiber.id:
		return _no("same_part", "Stiel, Kopf und Fasern müssen verschiedene Gegenstände sein.")
	for p in [handle, head, fiber]:
		if p.assembly_id != 0:
			return _no("already_connected", "#%d ist bereits Teil eines Verbunds." % p.id)
		if p.liquid_fraction() > 0.0:
			return _no("liquid", "#%d ist (teilweise) flüssig." % p.id)
		if p.container_id != 0:
			return _no("in_container", "#%d liegt in einem Behälter." % p.id)
	if fiber.material_id != "plant_fiber":
		return _no("no_binding_material", "Umwickeln braucht Pflanzenfasern – #%d ist %s." % [fiber.id, fiber.material().display_name])
	if handle.shape != "rod":
		return _no("handle_shape", "Ein Stiel muss stabförmig sein (#%d ist %s)." % [handle.id, handle.shape_label()])
	if handle.dims_m.x < float(cc.get("handle_min_length_m", 0.2)):
		return _no("handle_short", "Stiel zu kurz (%.2f m < %.2f m)." % [handle.dims_m.x, float(cc.get("handle_min_length_m", 0.2))])
	if handle.dims_m.y > float(cc.get("handle_max_diameter_m", 0.05)):
		return _no("handle_thick", "Stiel zu dick zum Umwickeln und Greifen (%.3f m)." % handle.dims_m.y)
	if handle.material_id in ["plant_fiber", "plant_tissue", "soil", "water"]:
		return _no("handle_material", "%s ist als Stiel nicht formstabil." % handle.material().display_name)
	if not (head.shape in HEAD_SHAPES):
		return _no("head_shape", "Als Arbeitskopf wird ein kompaktes Stück gebraucht (#%d ist %s)." % [head.id, head.shape_label()])
	if head.mass_kg > float(cc.get("head_max_kg", 1.0)):
		return _no("head_heavy", "Kopf zu schwer für eine Faserumwicklung (%.2f kg)." % head.mass_kg)
	var fiber_max_k := fiber.material().valid_max_k - 20.0
	for p in [handle, head]:
		if p.temperature_k() > fiber_max_k:
			return _no("too_hot_for_fiber", "#%d ist zu heiß – die Fasern würden beschädigt." % p.id)
	var need := float(cc.get("fiber_need_kg_per_kg_head", 0.08)) * head.mass_kg
	need = maxf(need, float(cc.get("fiber_min_kg", 0.004)))
	if fiber.mass_kg < float(cc.get("fiber_min_kg", 0.004)):
		return _no("fiber_too_little", "Zu wenig Fasern (%.3f kg < %.3f kg)." % [fiber.mass_kg, float(cc.get("fiber_min_kg", 0.004))])
	var use := minf(fiber.mass_kg, minf(need, float(cc.get("fiber_use_max_kg", 0.04))))
	var fit := minf(1.0, use / need)
	var skills: Dictionary = cc.get("skill_fit", {})
	var skill := float(skills.get(skill_level, skills.get("none", 0.45)))
	var cap := use * fiber.material().w("binding_energy_j_per_kg", 450.0) * fit * skill
	return {"ok": true, "code": "ok", "message": "Umwicklung möglich.", "fiber_use_kg": use, "need_kg": need,
		"capacity_j": cap, "fit": fit, "skill": skill, "fatigue": fiber.material().w("binding_fatigue", 0.03)}


static func _no(code: String, msg: String) -> Dictionary:
	return {"ok": false, "code": code, "message": msg}
