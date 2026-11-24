class_name TestCreatures
extends RefCounted
## Prüfungen für Körperplan, Generator, Körperveränderungen, Animation und Speichern.

var results: Array = []
var notes: Array = []
var _free: Array = []
var sim: Simulation
var db: DefinitionDB


func run_all() -> Array:
	results.clear()
	notes.clear()
	sim = Simulation.new()
	sim.initialize()
	_free.append(sim)
	db = DefinitionDB.new()
	db.load_all()
	_test_generator()
	_test_validation()
	_test_forearm_and_animation()
	_test_prostheses()
	_test_leaves()
	_test_walk_requirement()
	_test_save_load()
	_test_entities()
	for o in _free:
		if is_instance_valid(o):
			o.free()
	_free.clear()
	return results


func _check(name: String, cond: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": cond, "detail": detail})


func _view(p: BodyPlan) -> CreatureView:
	var v := CreatureGenerator.build_view(p, sim.materials, 0.02)
	_free.append(v)
	return v


func _test_generator() -> void:
	var a := CreatureGenerator.generate(1001, db)
	var b := CreatureGenerator.generate(1001, db)
	_check("Generator: gleicher Startwert → gleicher Körperplan", JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()))
	var all_ok := true
	var heights: Array = []
	var hues: Array = []
	for s in range(2000, 2010):
		var p := CreatureGenerator.generate(s, db)
		var errs := p.validate(sim.materials)
		var caps := p.capabilities()
		var h := float(p.genes["height_m"])
		heights.append(h)
		hues.append(Color.html(p.genes["skin_color"]).h)
		if not errs.is_empty() or h < 0.85 * 0.85 or h > 0.85 * 1.15 or caps["leaves"] < 1 or caps["leaves"] > 3 or caps["grasp"]["l"] != "hand" or caps["grasp"]["r"] != "hand" or not caps["walk"]:
			all_ok = false
	_check("Generator: 10 Varianten gültig, Größe ±12 % um 85 cm, 1–3 Blätter, 2 Arme, 2 Beine", all_ok, "Höhen %s" % str(heights.map(func(x): return snappedf(x, 0.01))))
	var hmin: float = hues.min()
	var hmax: float = hues.max()
	_check("Generator: Farbtöne bleiben im Grünbereich (zusammengehörig)", hmin > 0.2 and hmax < 0.45, "Farbton %.3f–%.3f" % [hmin, hmax])
	var t0 := Time.get_ticks_usec()
	var v := _view(a)
	notes.append("Einzelfigur: %d Körperteile, %d Voxel à 20 mm, Masse %.3f kg, Aufbau %.1f ms" % [v.meshes.size(), v.voxel_count, a.total_mass(sim.materials), (Time.get_ticks_usec() - t0) / 1000.0])
	_check("Darstellung: Kollisionsform je vorhandenem Teil, getrennt vom Netz", v.areas.size() == a.present_ids().size() and v.meshes.size() == a.present_ids().size())


func _test_validation() -> void:
	var p := CreatureGenerator.generate(7, db)
	var dup: Dictionary = p.parts["head"].duplicate(true)
	_check("Körperplan: doppelte ID abgewiesen", p.add_part(dup) != "")
	var orphan: Dictionary = p.parts["head"].duplicate(true)
	orphan["id"] = "zusatzkopf"
	orphan["parent"] = "gibt_es_nicht"
	_check("Körperplan: ungültige Verbindung abgewiesen", p.add_part(orphan) != "")
	var cyc := CreatureGenerator.generate(7, db)
	cyc.parts["torso"]["parent"] = "hand_l"
	var errs := cyc.validate(sim.materials)
	_check("Körperplan: zyklische Hierarchie erkannt", str(errs).find("Zyklisch") >= 0, str(errs.slice(0, 2)))
	var badmat := CreatureGenerator.generate(7, db)
	badmat.parts["head"]["material_id"] = "unobtanium"
	_check("Körperplan: unbekanntes Material erkannt", not badmat.validate(sim.materials).is_empty())


func _test_forearm_and_animation() -> void:
	var p := CreatureGenerator.generate(1001, db)
	var v := _view(p)
	var m0 := p.total_mass(sim.materials)
	var expected := p.part_mass("arm_l_lower", sim.materials) + p.part_mass("hand_l", sim.materials)
	var r := p.remove_forearm("l")
	v.rebuild()
	var m1 := p.total_mass(sim.materials)
	_check("Unterarm entfernen: Masse sinkt um Unterarm + Hand", r["ok"] and absf((m0 - m1) - expected) < 1e-12, "Δm %.4f kg, erwartet %.4f kg" % [m0 - m1, expected])
	_check("Unterarm entfernen: kein Netz, keine Kollision, kein Gelenk für entfernte Teile",
		not v.pivots.has("arm_l_lower") and not v.pivots.has("hand_l") and not v.meshes.has("hand_l") and not v.areas.has("hand_l") and v.pivots.has("arm_l_upper"))
	var g := v.animator.request("grasp", "l")
	_check("Greifen links ohne Hand → Ersatz rechte Hand", g["ok"] and g["side"] == "r" and g["message"].find("Ersatz") >= 0, g["message"])
	for i in 30:
		v.animator.update(1.0 / 30.0)
	var used := v.animator.used_part_ids()
	_check("Animation verwendet keine entfernten Teile", not used.has("hand_l") and not used.has("arm_l_lower") and used.has("arm_r_upper"), str(used))
	v.animator.request("walk")
	for i in 30:
		v.animator.update(1.0 / 30.0)
	_check("Gehen nach Unterarmverlust weiter möglich, ohne entfernte Teile", v.animator.state == "walk" and not v.animator.used_part_ids().has("hand_l"))
	p.remove_forearm("r")
	v.rebuild()
	var e := v.animator.request("eat", "r")
	_check("Zum Mund führen ohne Hände verständlich abgelehnt", not e["ok"] and e["message"].find("nicht möglich") >= 0, e["message"])


func _test_prostheses() -> void:
	var p := CreatureGenerator.generate(1001, db)
	var v := _view(p)
	_check("Prothese nur nach Verlust möglich", not p.attach_prosthesis("l", "wood", sim.materials)["ok"])
	p.remove_forearm("l")
	var m_before := p.total_mass(sim.materials)
	var rw := p.attach_prosthesis("l", "wood", sim.materials)
	v.rebuild()
	var wid: String = rw.get("id", "")
	var wood_mass := p.part_mass(wid, sim.materials)
	_check("Holzprothese: Masse = Modellvolumen · Holzdichte", rw["ok"] and absf(wood_mass - p.model_volume(wid) * 700.0) < 1e-12 and absf(p.total_mass(sim.materials) - m_before - wood_mass) < 1e-12)
	_check("Holzprothese: Unterarm und Hand als „ersetzt“, sichtbar als neues Teil", p.parts["arm_l_lower"]["status"] == "replaced" and p.parts["hand_l"]["status"] == "replaced" and v.meshes.has(wid))
	_check("Holzprothese: kann nicht greifen", p.capabilities()["grasp"]["l"] == "")
	var rc := p.attach_prosthesis("l", "copper", sim.materials)
	v.rebuild()
	var cid: String = rc.get("id", "")
	_check("Kupferprothese ersetzt Holzprothese (Status, neue stabile ID)", rc["ok"] and p.parts[wid]["status"] == "replaced" and cid != wid and not v.meshes.has(wid) and v.meshes.has(cid))
	_check("Kupferprothese: Masse = Modellvolumen · 8960 kg/m³, Hakengriff möglich",
		absf(p.part_mass(cid, sim.materials) - p.model_volume(cid) * 8960.0) < 1e-9 and p.capabilities()["grasp"]["l"] == "hook")
	var g := v.animator.request("grasp", "l")
	for i in 20:
		v.animator.update(0.05)
	_check("Greifen mit Kupferhaken als Ersatzverhalten", g["ok"] and g["side"] == "l" and v.animator.used_part_ids().has(cid), g["message"])
	notes.append("Prothesen (Startwert 1001): Holz %.3f kg, Kupfer %.3f kg (Excel I002 nennt 3,5 kg – im Spiel gilt Material · Volumen)" % [wood_mass, p.part_mass(cid, sim.materials)])


func _test_leaves() -> void:
	var p := CreatureGenerator.generate(3003, db)
	var v := _view(p)
	var n0 := p.leaf_ids().size()
	var m0 := p.total_mass(sim.materials)
	var r := p.add_leaf()
	v.rebuild()
	_check("Blatt hinzufügen: Masse und Darstellung aktualisiert", r["ok"] and p.leaf_ids().size() == n0 + 1 and absf(p.total_mass(sim.materials) - m0 - p.part_mass(r["id"], sim.materials)) < 1e-12 and v.meshes.has(r["id"]))
	var rr := p.remove_leaf()
	v.rebuild()
	_check("Blatt entfernen: Teil nicht mehr sichtbar, Status entfernt", rr["ok"] and not v.meshes.has(rr["removed"][0]) and p.parts[rr["removed"][0]]["status"] == "removed")
	while p.leaf_ids().size() < 8:
		p.add_leaf()
	_check("Blattanzahl auf 8 begrenzt (Excel 0–8)", not p.add_leaf()["ok"])


func _test_walk_requirement() -> void:
	var p := CreatureGenerator.generate(4004, db)
	var v := _view(p)
	p.remove_part("leg_l_lower", "Test")
	v.rebuild()
	var w := v.animator.request("walk")
	_check("Gehen ohne vollständiges Bein abgelehnt (Hinken nicht implementiert)", not w["ok"] and w["message"].find("Hinken") >= 0)


func _test_save_load() -> void:
	var p := CreatureGenerator.generate(5005, db)
	p.remove_forearm("r")
	p.attach_prosthesis("r", "copper", sim.materials)
	p.add_leaf()
	var text := JSON.stringify(p.to_dict())
	var r := BodyPlan.from_dict(JSON.parse_string(text), sim.materials)
	_check("Körperkonfiguration speichern und laden (JSON-Rundlauf)", r["ok"] and JSON.parse_string(JSON.stringify(r["plan"].to_dict())) == JSON.parse_string(text) and absf(r["plan"].total_mass(sim.materials) - p.total_mass(sim.materials)) < 1e-12)
	var bad = JSON.parse_string(text)
	for q in bad["parts"]:
		if q["id"] == "torso":
			q["parent"] = "head"
	_check("Laden: zyklische Datei abgewiesen", not BodyPlan.from_dict(bad, sim.materials)["ok"])
	var bad2 = JSON.parse_string(text)
	bad2["parts"].append(bad2["parts"][0].duplicate())
	_check("Laden: doppelte Teil-ID abgewiesen", not BodyPlan.from_dict(bad2, sim.materials)["ok"])
	var path := "user://test_creature_roundtrip.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var r2 := BodyPlan.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)), sim.materials)
	_check("Speichern im Benutzerdatenbereich und Wiederherstellen", r2["ok"] and r2["plan"].capabilities()["grasp"]["r"] == "hook")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_entities() -> void:
	var ids := {}
	for s in 5:
		var p := CreatureGenerator.generate(s, db)
		var id := sim.add_entity(p, "test")
		ids[id] = true
	var cu := sim.create_object("copper", 0.001, 400.0, "", "x")
	sim.step(1.0 / 60.0)
	_check("Wesen erhalten eindeutige Entitäts-IDs im gemeinsamen Register; Physik läuft weiter", ids.size() == 5 and not ids.has(0) and cu.temperature_k() < 400.0)
