class_name TestSuite
extends RefCounted
## Automatisierte Logikprüfungen (ohne Grafik). Wird vom Kommandozeilen-Runner
## (tests/run_tests.gd) und vom Knopf „Selbsttests“ im Labor verwendet.

var results: Array = []   # {name, ok, detail}
var notes: Array = []     # Messwerte, z. B. Zeitschrittvergleich
var _sims: Array = []


func run_all() -> Array:
	results.clear()
	notes.clear()
	_test_materials_valid()
	_test_invalid_data()
	_test_registry_and_log()
	_test_mass_density_volume()
	_test_closed_exchange_conservation()
	_test_contact_analytic_and_timesteps()
	_test_heater_energy()
	_test_melting_latent_heat()
	_test_solidification()
	_test_split_merge_fracture()
	_test_environment_ledger()
	_test_pause_stops_logic()
	_test_world_state_pure_data()
	_study_timestep_heating()
	for s in _sims:
		if is_instance_valid(s):
			s.free()
	_sims.clear()
	return results


func passed_count() -> int:
	var c := 0
	for r in results:
		if r["ok"]:
			c += 1
	return c


func _check(name: String, cond: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": cond, "detail": detail})


func _sim() -> Simulation:
	var s := Simulation.new()
	s.initialize()
	_sims.append(s)
	return s


static func sci(x: float) -> String:
	if x == 0.0:
		return "0"
	var ex := floori(log(absf(x)) / log(10.0))
	return "%.2fe%d" % [x / pow(10.0, ex), ex]


static func _rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-30)


# 1 ──────────────────────────────────────────────
func _test_materials_valid() -> void:
	var s := _sim()
	_check("1 Materialdefinitionen laden und validieren", s.is_ready() and s.materials.ids() == ["ceramic", "copper", "plant_fiber", "plant_tissue", "soil", "stone", "water", "wood"],
		"IDs: %s Fehler: %s" % [s.materials.ids(), s.init_errors])
	var cu := s.materials.get_material("copper")
	_check("1 Kupfer: Schmelzmodell vorhanden", cu != null and cu.has_melting() and is_equal_approx(cu.melting_point, 1357.77))
	var wood := s.materials.get_material("wood")
	_check("1 Holz: kein erfundener Schmelzpunkt", wood != null and not wood.has_melting() and wood.melting_point < 0.0)


# 2 ──────────────────────────────────────────────
func _test_invalid_data() -> void:
	var base: Dictionary = JsonUtil.load_json("res://data/materials/copper.json")["data"]
	var cases := {
		"negative Dichte": func(d): d["properties"]["density_kg_m3"]["value"] = -5.0,
		"ungültige ID": func(d): d["id"] = "Kupfer!",
		"Schmelzpunkt bei solid_only": func(d): d["phase_model"] = "solid_only",
		"Referenz ohne Quelle": func(d): d["properties"]["thermal_conductivity_w_mk"].erase("source"),
		"fehlende Eigenschaft": func(d): d["properties"].erase("specific_heat_solid_j_kgk"),
		"unbekannte Herkunftsart": func(d): d["properties"]["density_kg_m3"]["kind"] = "geraten",
		"Min ≥ Max": func(d): d["properties"]["model_valid_min_k"]["value"] = 5000.0,
		"Zahl als Text": func(d): d["properties"]["density_kg_m3"]["value"] = "8960",
		"falsche Schemaversion": func(d): d["schema_version"] = 99,
	}
	for name in cases:
		var d: Dictionary = base.duplicate(true)
		cases[name].call(d)
		var r := MaterialRegistry.validate(d, "copper")
		_check("2 Ungültig erkannt: %s" % name, not r["ok"] and r["errors"].size() > 0, str(r["errors"].slice(0, 1)))
	var r2 := MaterialRegistry.validate(base, "stone")
	_check("2 ID passt nicht zum Dateinamen", not r2["ok"])
	_check("2 Kein JSON-Objekt", not MaterialRegistry.validate([1, 2], "")["ok"])
	_check("2 Gültige Kupferdaten werden akzeptiert", MaterialRegistry.validate(base, "copper")["ok"])
	var s := _sim()
	_check("2 Unbekannte Material-ID abgewiesen", s.materials.get_material("unobtanium") == null and s.create_object("unobtanium", 0.001, 293.15, "", "x") == null)
	_check("2 Negatives Volumen abgewiesen", s.create_object("copper", -0.001, 293.15, "", "x") == null)
	_check("2 Temperatur außerhalb Modellbereich abgewiesen", s.create_object("water", 0.001, 500.0, "", "x") == null)
	_check("2 Abweisungen werden protokolliert", s.event_log.count_type("object_rejected") == 3)
	_check("2 Einstellungen: leeres Objekt abgewiesen", Simulation.validate_settings({}).size() > 0)
	var bad_settings: Dictionary = JsonUtil.load_json(Simulation.DEFAULT_SETTINGS_PATH)["data"].duplicate(true)
	bad_settings["initial_population"] = -1
	_check("2 Einstellungen: negative Population abgewiesen", Simulation.validate_settings(bad_settings).size() > 0)
	var good_settings: Dictionary = JsonUtil.load_json(Simulation.DEFAULT_SETTINGS_PATH)["data"]
	_check("2 Einstellungen: initial_population = 50", int(good_settings["initial_population"]) == 50 and Simulation.validate_settings(good_settings).is_empty())


func _test_registry_and_log() -> void:
	var reg := EntityRegistry.new()
	var s := _sim()
	var mat := s.materials.get_material("stone")
	var seen := {}
	var unique := true
	for i in 100:
		var o := PhysicalObject.create_from_mass_energy(mat, 1.0, 1000.0)
		var id := reg.register(o)
		if id <= 0 or seen.has(id):
			unique = false
		seen[id] = true
	_check("Register: 100 eindeutige IDs", unique and reg.count() == 100)
	var dup := PhysicalObject.create_from_mass_energy(mat, 1.0, 1000.0)
	dup.id = 5
	_check("Register: doppelte ID abgewiesen", reg.register(dup) == -1 and reg.count() == 100)
	_check("Register: Abfrage per ID", reg.get_entity(42) != null and reg.get_entity(42).id == 42)
	reg.unregister(42)
	_check("Register: Entfernen", not reg.has_id(42) and reg.count() == 99)
	var log := EventLog.new(null, 300)
	for i in 1000:
		log.add("test", [], {"i": i})
	_check("Ereignisprotokoll: begrenzte Historie", log.all_entries().size() == 300 and log.dropped_count == 700)


# 3 ──────────────────────────────────────────────
func _test_mass_density_volume() -> void:
	var s := _sim()
	var temps := {"copper": 293.15, "stone": 293.15, "wood": 293.15, "water": 293.15, "plant_tissue": 293.15}
	for mid in temps:
		var o := s.create_object(mid, 0.001, temps[mid], "", "t")
		var mat := s.materials.get_material(mid)
		_check("3 Masse = Dichte · Volumen (%s)" % mid, o != null and _rel(o.mass_kg, mat.density * 0.001) < 1e-12 and _rel(o.volume_m3(), 0.001) < 1e-12 and absf(o.temperature_k() - temps[mid]) < 1e-9,
			"m=%.6f kg" % (o.mass_kg if o else -1.0))


# 4 ──────────────────────────────────────────────
func _test_closed_exchange_conservation() -> void:
	var s := _sim()
	s.thermal.environment_enabled = false
	var cu := s.create_object("copper", 0.05 * 0.05 * 0.05, 363.15, "B", "warm")
	var st := s.create_object("stone", 0.05 * 0.05 * 0.05, 278.15, "B", "kalt")
	var wa := s.create_object("water", 0.00025, 293.15, "B", "Wasser")
	s.thermal.set_contact_enabled(s.thermal.add_contact(cu, st, 0.0025, "Cu-Stein"), true)
	s.thermal.set_contact_enabled(s.thermal.add_contact(cu, wa, 0.0025, "Cu-Wasser"), true)
	var dup_key := s.thermal.add_contact(st, cu, 0.0025, "doppelt")
	_check("4 Kontakt wird nicht doppelt angelegt", s.thermal.contacts.size() == 2 and dup_key == ThermalSystem.contact_key(cu.id, st.id))
	var e0 := s.thermal.total_object_energy(s.registry)
	var max_err := 0.0
	for i in 36000:  # 600 s bei 1/60 s
		s.step(1.0 / 60.0)
		max_err = maxf(max_err, _rel(s.thermal.total_object_energy(s.registry), e0))
	_check("4 Geschlossener Austausch erhält Energie (rel. Fehler < 1e-12)", max_err < 1e-12, "max. rel. Abweichung %s" % sci(max_err))
	notes.append("Geschlossener Austausch (Cu/Stein/Wasser, 600 s, dt=1/60 s): max. relative Energieabweichung %s" % sci(max_err))


# 4b / Zeitschritte ──────────────────────────────
func _test_contact_analytic_and_timesteps() -> void:
	for dt in [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0, 1.0, 10.0]:
		var s := _sim()
		s.thermal.environment_enabled = false
		var cu := s.create_object("copper", 0.000125, 363.15, "B", "warm")
		var st := s.create_object("stone", 0.000125, 278.15, "B", "kalt")
		var key := s.thermal.add_contact(cu, st, 0.0025, "Cu-Stein")
		s.thermal.set_contact_enabled(key, true)
		var g: float = s.thermal.contacts[key]["conductance_w_k"]
		var c1 := cu.heat_capacity_j_k()
		var c2 := st.heat_capacity_j_k()
		var t_end := 600.0
		var steps := int(round(t_end / dt))
		var sign_flip := false
		for i in steps:
			s.step(dt)
			if cu.temperature_k() < st.temperature_k() - 1e-9:
				sign_flip = true
		var analytic := 85.0 * exp(-g * t_end * (1.0 / c1 + 1.0 / c2))
		var numeric := cu.temperature_k() - st.temperature_k()
		var err := absf(numeric - analytic)
		_check("4 Kontakt ohne Überschwingen, analytisch korrekt (dt=%.4f s)" % dt, not sign_flip and err < 1e-6, "ΔT num=%.6f K, analytisch=%.6f K" % [numeric, analytic])
		notes.append("Kontakt Cu–Stein nach 600 s, dt=%.4f s: ΔT=%.9f K (analytisch %.9f K, Abweichung %s K)" % [dt, numeric, analytic, sci(err)])


# 5 ──────────────────────────────────────────────
func _test_heater_energy() -> void:
	var s := _sim()
	s.thermal.environment_enabled = false
	var cu := s.create_object("copper", 0.03 * 0.03 * 0.03, 293.15, "C", "Probe")
	s.thermal.add_heater("h", cu.id, 1000.0)
	s.thermal.set_heater("h", true)
	var e0 := cu.thermal_energy_j
	for i in 1800:
		s.step(1.0 / 60.0)
	var supplied: float = s.thermal.heaters["h"]["supplied_j"]
	_check("5 Heizenergie = Leistung · Zeit", absf(supplied - 1000.0 * s.clock.sim_time_s) < 1e-6 and absf(s.clock.sim_time_s - 30.0) < 1e-9,
		"zugeführt %.6f J, P·t = %.6f J" % [supplied, 1000.0 * s.clock.sim_time_s])
	_check("5 Energie kommt vollständig in der Probe an", absf((cu.thermal_energy_j - e0) - supplied) < 1e-6)


# 6 ──────────────────────────────────────────────
func _test_melting_latent_heat() -> void:
	var s := _sim()
	s.thermal.environment_enabled = false
	var cu := s.create_object("copper", 0.03 * 0.03 * 0.03, 293.15, "C", "Probe")
	var mat := cu.material()
	var power := 1500.0
	var dt := 1.0 / 60.0
	s.thermal.add_heater("h", cu.id, power)
	s.thermal.set_heater("h", true)
	var e_start_melt := -1.0
	var e_end_melt := -1.0
	var plateau_ok := true
	var steps := 0
	while steps < 400000:
		s.step(dt)
		steps += 1
		var lf := cu.liquid_fraction()
		var supplied: float = s.thermal.heaters["h"]["supplied_j"]
		if lf > 0.0 and e_start_melt < 0.0:
			e_start_melt = supplied
		if lf > 0.0 and lf < 1.0 and cu.temperature_k() != mat.melting_point:
			plateau_ok = false
		if lf >= 1.0:
			e_end_melt = supplied
			break
	var m := cu.mass_kg
	var expected_start := m * mat.cp_solid * (mat.melting_point - 293.15)
	var expected_end := expected_start + m * mat.latent_heat_fusion
	var tol := power * dt
	_check("6 Schmelzbeginn erst nach Erwärmen auf Tm", e_start_melt >= expected_start - 1e-6 and e_start_melt <= expected_start + tol, "%.3f J (erwartet %.3f J)" % [e_start_melt, expected_start])
	_check("6 Vollständiges Schmelzen braucht latente Wärme m·L", e_end_melt >= expected_end - 1e-6 and e_end_melt <= expected_end + tol, "%.3f J (erwartet %.3f J, m·L = %.3f J)" % [e_end_melt, expected_end, m * mat.latent_heat_fusion])
	_check("6 Temperatur bleibt während des Schmelzens auf Tm", plateau_ok)
	for i in 600:
		s.step(dt)
	_check("6 Erst nach vollständigem Schmelzen steigt T über Tm", cu.temperature_k() > mat.melting_point and cu.liquid_fraction() == 1.0)
	notes.append("Kupferprobe %.4f kg: Schmelzbeginn nach %.1f J, vollständig flüssig nach %.1f J (erwartet %.1f / %.1f J)" % [m, e_start_melt, e_end_melt, expected_start, expected_end])


# 7 ──────────────────────────────────────────────
func _test_solidification() -> void:
	var s := _sim()
	s.thermal.environment_enabled = false
	var mat := s.materials.get_material("copper")
	var cu := s.create_object("copper", 0.03 * 0.03 * 0.03, mat.melting_point + 50.0, "C", "Schmelze")
	_check("7 Probe startet flüssig", cu != null and cu.liquid_fraction() == 1.0)
	var power := 800.0
	var dt := 1.0 / 60.0
	s.thermal.add_sink("k", cu.id, power, 293.15)
	s.thermal.set_sink("k", true)
	var b0: float = s.thermal.ledger(s.registry)["balance_j"]
	var e_start := -1.0
	var e_end := -1.0
	var mono := true
	var plateau_ok := true
	var last_lf := 1.0
	var steps := 0
	while steps < 400000:
		s.step(dt)
		steps += 1
		var lf := cu.liquid_fraction()
		var absorbed: float = s.thermal.sinks["k"]["absorbed_j"]
		if lf > last_lf + 1e-15:
			mono = false
		last_lf = lf
		if lf < 1.0 and e_start < 0.0:
			e_start = absorbed
		if lf > 0.0 and lf < 1.0 and cu.temperature_k() != mat.melting_point:
			plateau_ok = false
		if lf <= 0.0:
			e_end = absorbed
			break
	var m := cu.mass_kg
	var exp_start := m * mat.cp_liquid * 50.0
	var exp_end := exp_start + m * mat.latent_heat_fusion
	var tol := power * dt
	_check("7 Erstarren beginnt nach Abkühlen auf Tm", e_start >= exp_start - 1e-6 and e_start <= exp_start + tol, "%.3f J (erwartet %.3f J)" % [e_start, exp_start])
	_check("7 Vollständiges Erstarren gibt m·L ab", e_end >= exp_end - 1e-6 and e_end <= exp_end + tol, "%.3f J (erwartet %.3f J)" % [e_end, exp_end])
	_check("7 Flüssiganteil sinkt monoton, T bleibt auf Tm", mono and plateau_ok)
	var b1: float = s.thermal.ledger(s.registry)["balance_j"]
	_check("7 Energiebilanz inkl. Senke konstant", _rel(b1, b0) < 1e-12, "Bilanz %.6f → %.6f J" % [b0, b1])
	_check("7 Masse unverändert", cu.mass_kg == m)


# 8 ──────────────────────────────────────────────
func _test_split_merge_fracture() -> void:
	var s := _sim()
	var stone := s.create_object("stone", 0.001, 300.0, "D", "Stein")
	var m0 := stone.mass_kg
	var e0 := stone.thermal_energy_j
	var r := s.processes.split(s, stone.id, 0.3)
	var a: PhysicalObject = s.registry.get_entity(r["ids"][0])
	var b: PhysicalObject = s.registry.get_entity(r["ids"][1])
	_check("8 Teilen erhält Masse", r["ok"] and absf(a.mass_kg + b.mass_kg - m0) < 1e-12 and not s.registry.has_id(stone.id))
	_check("8 Teilen erhält Energie und Temperatur", absf(a.thermal_energy_j + b.thermal_energy_j - e0) < 1e-9 and absf(a.temperature_k() - 300.0) < 1e-9 and absf(b.temperature_k() - 300.0) < 1e-9)
	var mr := s.processes.merge(s, a.id, b.id)
	var merged: PhysicalObject = s.registry.get_entity(mr["id"])
	_check("8 Zusammenführen erhält Masse und Energie", mr["ok"] and _rel(merged.mass_kg, m0) < 1e-12 and _rel(merged.thermal_energy_j, e0) < 1e-12 and s.registry.count() == 1)
	var hot := s.create_object("stone", 0.001, 400.0, "D", "heiß")
	var mr2 := s.processes.merge(s, merged.id, hot.id)
	var mix: PhysicalObject = s.registry.get_entity(mr2["id"])
	_check("8 Mischtemperatur aus Energiebilanz (300 K + 400 K → 350 K)", absf(mix.temperature_k() - 350.0) < 1e-9)
	var wood := s.create_object("wood", 0.001, 300.0, "D", "Holz")
	_check("8 Unterschiedliche Materialien nicht zusammenführbar", not s.processes.merge(s, mix.id, wood.id)["ok"])
	_check("8 Selbst-Zusammenführung abgewiesen", not s.processes.merge(s, wood.id, wood.id)["ok"])
	var liquid := s.create_object("copper", 0.00001, 1400.0, "C", "flüssig")
	var cu2 := s.create_object("copper", 0.00001, 1400.0, "C", "flüssig2")
	_check("8 Flüssige Proben nicht teil-/zusammenführbar", not s.processes.split(s, liquid.id, 0.5)["ok"] and not s.processes.merge(s, liquid.id, cu2.id)["ok"])
	_check("8 Ungültiger Teilungsanteil abgewiesen", not s.processes.split(s, wood.id, 0.01)["ok"])
	# Bruch
	var m_before := mix.mass_kg
	var e_before := mix.thermal_energy_j
	var fr := s.damage.apply_load(s, mix.id, 1000.0)
	var m_sum := 0.0
	var e_sum := 0.0
	var temps_ok := true
	for fid in fr.get("fragment_ids", []):
		var f: PhysicalObject = s.registry.get_entity(fid)
		m_sum += f.mass_kg
		e_sum += f.thermal_energy_j
		temps_ok = temps_ok and absf(f.temperature_k() - 350.0) < 1e-9
	_check("8 Bruch: wenige Fragmente, Masse erhalten", fr["status"] == "fractured" and fr["fragment_ids"].size() >= 2 and fr["fragment_ids"].size() <= 3 and absf(m_sum - m_before) < 1e-12, "%d Fragmente, Σm=%.12f kg" % [fr.get("fragment_ids", []).size(), m_sum])
	_check("8 Bruch: thermischer Zustand übertragen", absf(e_sum - e_before) < 1e-9 and temps_ok)
	var small := s.damage.apply_load(s, wood.id, 1.0)
	_check("8 Kleine Last: nur Schaden, kein Bruch", small["status"] == "damaged" and s.registry.has_id(wood.id))
	var cu := s.create_object("copper", 0.001, 300.0, "D", "Cu")
	var dres := s.damage.apply_load(s, cu.id, 1.0e5)
	_check("8 Kupfer (duktil) verformt sich statt zu zerbrechen", dres["status"] == "deformed" and s.registry.has_id(cu.id) and cu.deformed)
	var w := s.create_object("water", 0.001, 293.15, "B", "Wasser")
	_check("8 Last auf Wasser abgewiesen (nicht modelliert)", s.damage.apply_load(s, w.id, 10.0)["status"] == "rejected")


func _test_environment_ledger() -> void:
	var s := _sim()
	var cu := s.create_object("copper", 0.03 * 0.03 * 0.03, 293.15, "C", "Probe")
	s.thermal.add_heater("h", cu.id, 1000.0)
	s.thermal.set_heater("h", true)
	var b0: float = s.thermal.ledger(s.registry)["balance_j"]
	for i in 3600:
		s.step(1.0 / 60.0)
	var led := s.thermal.ledger(s.registry)
	_check("Energiebilanz mit Umgebung und Heizung geschlossen", _rel(led["balance_j"], b0) < 1e-12 and led["environment_j"] > 0.0, "Umgebung hat %.3f J aufgenommen" % led["environment_j"])


# 9 ──────────────────────────────────────────────
func _test_pause_stops_logic() -> void:
	var s := _sim()
	var cu := s.create_object("copper", 0.001, 293.15, "C", "Probe")
	s.thermal.add_heater("h", cu.id, 1000.0)
	s.thermal.set_heater("h", true)
	s.step(1.0 / 60.0)
	var t0 := s.clock.sim_time_s
	var e0 := cu.thermal_energy_j
	s.set_paused(true)
	for i in 120:
		s.step(1.0 / 60.0)
	_check("9 Pause stoppt Simulationszeit und Wärme (Logikebene)", s.clock.sim_time_s == t0 and cu.thermal_energy_j == e0)
	s.set_paused(false)
	s.step(1.0 / 60.0)
	_check("9 Fortsetzen läuft weiter", s.clock.sim_time_s > t0)


func _test_world_state_pure_data() -> void:
	var s := _sim()
	var cu := s.create_object("copper", 0.001, 293.15, "C", "Probe")
	var st := s.create_object("stone", 0.001, 293.15, "C", "Stein")
	s.thermal.add_contact(cu, st, 0.0001, "k")
	var snap := WorldState.capture(s, {cu.id: {"position": [0.0, 1.0, 0.0]}})
	var text := JSON.stringify(snap)
	var back = JSON.parse_string(text)
	_check("Weltzustand: nur reine Daten, JSON-Rundlauf", WorldState.is_pure_data(snap) and typeof(back) == TYPE_DICTIONARY and back["objects"].size() == 2)


func _study_timestep_heating() -> void:
	# Vergleich gleicher Zeitintervalle mit unterschiedlichen Schritten:
	# (a) Temperatur nach 60 s Heizen (noch fest), (b) Flüssiganteil nach 150 s (im Schmelzen).
	var res := {}
	for dt in [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0]:
		var s := _sim()
		var cu := s.create_object("copper", 0.03 * 0.03 * 0.03, 293.15, "C", "Probe")
		s.thermal.add_heater("h", cu.id, 1000.0)
		s.thermal.set_heater("h", true)
		for i in int(round(60.0 / dt)):
			s.step(dt)
		var t60 := cu.temperature_k()
		for i in int(round(90.0 / dt)):
			s.step(dt)
		res[dt] = [t60, cu.liquid_fraction()]
	var ref: Array = res[1.0 / 120.0]
	var max_dt := 0.0
	var max_dlf := 0.0
	for dt in res:
		var dT: float = res[dt][0] - ref[0]
		var dlf: float = res[dt][1] - ref[1]
		max_dt = maxf(max_dt, absf(dT))
		max_dlf = maxf(max_dlf, absf(dlf))
		notes.append("Heizen 1000 W mit Umgebungsverlust, dt=%.4f s: T(60 s)=%.6f K (Δ zu 1/120: %s K), Flüssiganteil(150 s)=%.6f (Δ %s)" % [dt, res[dt][0], sci(dT), res[dt][1], sci(dlf)])
	_check("Zeitschrittvergleich Heizen: ΔT < 0,01 K und ΔFlüssiganteil < 1e-4", max_dt < 0.01 and max_dlf < 1e-4, "max. ΔT %s K, max. Δlf %s" % [sci(max_dt), sci(max_dlf)])
