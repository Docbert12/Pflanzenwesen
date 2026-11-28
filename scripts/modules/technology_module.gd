class_name TechnologyModule
extends SimModule
## Technik: Gegenstände mit Wärme, Verbünde, Testheizungen, Versuche, Wärmebilanz der Lebenswelt.
## Takt: laufende Versuche (ExperimentSystem). Verfahrenswissen liegt je Wesen (Abschnitt actors).

func _init() -> void:
	id = "technology"
	has_section = true
	title = "Technik (Gegenstände, Versuche, Wärme)"
	depends_on = ["god"]
	load_order = 30
	after_load_order = 20


func tick(_dt: float, _zone: int) -> void:
	ctx.experiments.tick(ctx)


func save_section() -> Dictionary:
	var pieces: Array = []
	for pid in SaveManager.sorted_keys(ctx.material_pieces):
		pieces.append(ctx.material_pieces[pid].to_dict())
	var assemblies: Array = []
	for aid in SaveManager.sorted_keys(ctx.assemblies):
		assemblies.append(ctx.assemblies[aid].to_dict())
	var heaters: Array = []
	for hid in SaveManager.sorted_keys(ctx.heaters):
		heaters.append(ctx.heaters[hid].to_dict())
	var th: ThermalSystem = life.sim.thermal
	return {"material_pieces": pieces, "assemblies": assemblies, "heaters": heaters, "experiments": ctx.experiments.to_dict(),
		"thermal": {"environment_energy_j": th.environment_energy_j, "body_energy_j": th.body_energy_j,
			"contacts": th.contacts.duplicate(true), "heaters": th.heaters.duplicate(true),
			"_note": "Kontakte/Heizungen der Lebenswelt (Prompt 6: Tiegel, Guss, Testheizung). Weltmassen haben keine."}}


func load_section(d: Dictionary) -> Dictionary:
	for md in d.get("material_pieces", []):
		var mp := MaterialPiece.from_dict(md, life.sim.materials)
		if mp.material() == null:
			return {"ok": false, "code": "invalid", "message": "Materialstück #%d: unbekanntes Material %s." % [mp.id, mp.material_id]}
		mp.reserved_by = 0
		if life.sim.add_object(mp) < 0:
			return {"ok": false, "code": "invalid", "message": "Materialstück #%d: ID-Konflikt oder ungültige Masse." % mp.id}
		ctx.material_pieces[mp.id] = mp
	for ad2 in d.get("assemblies", []):
		var asm := Assembly.from_dict(ad2)
		if life.sim.add_entity(asm, "assembly") < 0:
			return {"ok": false, "code": "invalid", "message": "Verbund #%d: ID-Konflikt." % asm.id}
		ctx.assemblies[asm.id] = asm
	for hd in d.get("heaters", []):
		var hh := TestHeater.from_dict(hd)
		if life.sim.add_entity(hh, "test_heater") < 0:
			return {"ok": false, "code": "invalid", "message": "Testheizung #%d: ID-Konflikt." % hh.id}
		ctx.heaters[hh.id] = hh
	_thermal = d.get("thermal", {})
	ctx.experiments = ExperimentSystem.from_dict(d.get("experiments", {}))
	return {"ok": true}


var _thermal: Dictionary = {}

## Wärmekontakte erst, wenn alle Entitäten registriert sind (auch Lager/Bauwerke).
func after_load() -> Array:
	var th: ThermalSystem = life.sim.thermal
	th.environment_energy_j = float(_thermal.get("environment_energy_j", 0.0))
	th.body_energy_j = float(_thermal.get("body_energy_j", 0.0))
	for k in _thermal.get("contacts", {}):
		var c: Dictionary = _thermal["contacts"][k].duplicate(true)
		c["a"] = int(c["a"])
		c["b"] = int(c["b"])
		if life.sim.registry.has_id(c["a"]) and life.sim.registry.has_id(c["b"]):
			th.contacts[str(k)] = c
	for n in _thermal.get("heaters", {}):
		var h2: Dictionary = _thermal["heaters"][n].duplicate(true)
		h2["target_id"] = int(h2["target_id"])
		th.heaters[str(n)] = h2
	_thermal = {}
	return ctx.experiments.after_load(ctx)


func audit() -> Array:
	return ConstructionSystem.audit(ctx)


func metrics() -> Dictionary:
	return {"gegenstaende": ctx.material_pieces.size(), "verbuende": ctx.assemblies.size(), "testheizungen": ctx.heaters.size()}
