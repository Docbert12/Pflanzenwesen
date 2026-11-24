class_name ThermalSystem
extends RefCounted
## Wärmemodell mit einer Temperatur pro Objekt.
## Energiequellen/-senken werden getrennt bilanziert:
##   - Heizungen (zugeführte Energie, Leistung · Zeit)
##   - Kühlungen / Wärmesenken (aufgenommene Energie)
##   - Umgebung als Reservoir mit fester Temperatur (aufgenommene Energie)
##   - paarweise thermische Kontakte (Energie wird nur umverteilt)
##   - Körper der Wesen (Prompt 6: Wärme, die beim Greifen heißer Gegenstände in die Hand fließt)
## Bilanz: Σ Objektenergie + Umgebung + Senken + Körper − Heizungen = konstant.
##
## Stabilität: Kontakte verwenden die exakte Lösung für zwei konstante
## Wärmekapazitäten (Exponentialansatz). Zusätzlich wird jede Übertragung so
## begrenzt, dass das wärmere Objekt nicht unter das kältere fällt
## (kein Überschwingen, auch nicht während Phasenwechseln).

var ambient_temperature_k: float = 293.15
var environment_enabled: bool = true
var convection_coefficient: float = 10.0  # W/(m²·K), Annahme
var environment_energy_j: float = 0.0     # von der Umgebung aufgenommen (+)
var body_energy_j: float = 0.0            # von Wesenskörpern aufgenommen (+), Prompt 6
var contacts: Dictionary = {}             # "a:b" -> Dictionary
var heaters: Dictionary = {}              # name -> Dictionary
var sinks: Dictionary = {}                # name -> Dictionary
var event_log: EventLog


func _init(log_ref: EventLog = null) -> void:
	event_log = log_ref


func clear() -> void:
	contacts.clear()
	heaters.clear()
	sinks.clear()
	environment_energy_j = 0.0
	body_energy_j = 0.0


static func contact_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## Legt einen expliziten Kontakt an. Leitwert G = A / (La/ka + Lb/kb) mit
## La, Lb = halbe Würfelkante (Weg vom Probenzentrum zur Kontaktfläche).
## Ein bestehender Kontakt wird nicht doppelt angelegt.
func add_contact(a: PhysicalObject, b: PhysicalObject, area_m2: float, label: String, enabled: bool = false) -> String:
	if a == null or b == null or a.id == b.id or area_m2 <= 0.0:
		_log("contact_rejected", [], {"reason": "ungültige Kontaktparameter"}, "error")
		return ""
	var key := contact_key(a.id, b.id)
	if contacts.has(key):
		return key
	var la := a.cube_edge_m() * 0.5
	var lb := b.cube_edge_m() * 0.5
	var g := area_m2 / (la / a.material().conductivity + lb / b.material().conductivity)
	contacts[key] = {
		"a": mini(a.id, b.id), "b": maxi(a.id, b.id), "label": label,
		"area_m2": area_m2, "conductance_w_k": g, "enabled": enabled,
		"last_flow_w": 0.0, "transferred_j": 0.0,
	}
	_log("contact_created", [a.id, b.id], {"label": label, "conductance_w_k": g})
	return key


## Kontakt mit vorgegebenem Leitwert G [W/K] (Prompt 6: Behälter↔Probe, Tiegel↔Griff, Guss↔Form).
## Der Leitwert ist ein dokumentierter Spielparameter, keine Geometrieberechnung.
func add_contact_g(a: PhysicalObject, b: PhysicalObject, g_w_k: float, label: String, enabled: bool = true) -> String:
	if a == null or b == null or a.id == b.id or g_w_k <= 0.0:
		_log("contact_rejected", [], {"reason": "ungültige Kontaktparameter"}, "error")
		return ""
	var key := contact_key(a.id, b.id)
	if contacts.has(key):
		contacts[key]["conductance_w_k"] = g_w_k
		set_contact_enabled(key, enabled)
		return key
	contacts[key] = {
		"a": mini(a.id, b.id), "b": maxi(a.id, b.id), "label": label,
		"area_m2": 0.0, "conductance_w_k": g_w_k, "enabled": enabled,
		"last_flow_w": 0.0, "transferred_j": 0.0,
	}
	_log("contact_created", [a.id, b.id], {"label": label, "conductance_w_k": g_w_k})
	return key


func remove_contact(key: String) -> void:
	if contacts.has(key):
		_log("contact_removed", [contacts[key]["a"], contacts[key]["b"]], {"label": contacts[key]["label"], "reason": "gelöst"})
		contacts.erase(key)


func remove_heater(name: String) -> void:
	heaters.erase(name)


## Wärmefluss Objekt → Wesenskörper (Hand) mit exakter Begrenzung: das Objekt fällt nicht unter
## body_k. Rückgabe: übertragene Energie [J] (in body_energy_j bilanziert).
func transfer_to_body(obj: PhysicalObject, g_w_k: float, body_k: float, dt: float) -> float:
	if obj == null or g_w_k <= 0.0 or dt <= 0.0:
		return 0.0
	var dT := obj.temperature_k() - body_k
	if dT <= 0.0:
		return 0.0
	var inv := _inv_capacity(obj)
	var q := g_w_k * dT * dt if inv == 0.0 else dT * (1.0 - exp(-g_w_k * dt * inv)) / inv
	var e_floor := obj.mass_kg * obj.material().enthalpy_from_temperature(body_k, 0.0)
	q = minf(q, maxf(0.0, obj.thermal_energy_j - e_floor))
	obj.thermal_energy_j -= q
	body_energy_j += q
	return q


func set_contact_enabled(key: String, enabled: bool) -> void:
	if not contacts.has(key):
		return
	if contacts[key]["enabled"] != enabled:
		contacts[key]["enabled"] = enabled
		_log("contact_enabled" if enabled else "contact_disabled", [contacts[key]["a"], contacts[key]["b"]], {"label": contacts[key]["label"]})
	if not enabled:
		contacts[key]["last_flow_w"] = 0.0


func add_heater(name: String, target_id: int, power_w: float) -> void:
	heaters[name] = {"target_id": target_id, "power_w": maxf(0.0, power_w), "enabled": false,
		"supplied_j": 0.0, "last_power_w": 0.0, "status": "aus"}


func add_sink(name: String, target_id: int, power_w: float, sink_temperature_k: float) -> void:
	sinks[name] = {"target_id": target_id, "power_w": maxf(0.0, power_w), "sink_temperature_k": sink_temperature_k,
		"enabled": false, "absorbed_j": 0.0, "last_power_w": 0.0, "status": "aus"}


func set_heater(name: String, enabled: bool, power_w: float = -1.0) -> void:
	if not heaters.has(name):
		return
	var h: Dictionary = heaters[name]
	if power_w >= 0.0:
		h["power_w"] = power_w
	if h["enabled"] != enabled:
		h["enabled"] = enabled
		_log("heater_on" if enabled else "heater_off", [h["target_id"]], {"name": name, "power_w": h["power_w"]})


func set_sink(name: String, enabled: bool) -> void:
	if not sinks.has(name):
		return
	var s: Dictionary = sinks[name]
	if s["enabled"] != enabled:
		s["enabled"] = enabled
		_log("cooling_on" if enabled else "cooling_off", [s["target_id"]], {"name": name, "power_w": s["power_w"]})


func retarget(name: String, target_id: int) -> void:
	if heaters.has(name):
		heaters[name]["target_id"] = target_id
	if sinks.has(name):
		sinks[name]["target_id"] = target_id
	_log("thermal_target_changed", [target_id], {"name": name})


## Muss aufgerufen werden, wenn ein Objekt entfernt wird.
func on_entity_removed(id: int) -> void:
	for key in contacts.keys():
		if contacts[key]["a"] == id or contacts[key]["b"] == id:
			_log("contact_removed", [contacts[key]["a"], contacts[key]["b"]], {"label": contacts[key]["label"], "reason": "Objekt entfernt"})
			contacts.erase(key)
	for name in heaters.keys():
		if heaters[name]["target_id"] == id:
			heaters[name]["target_id"] = 0
			heaters[name]["status"] = "Ziel entfernt"
			heaters[name]["last_power_w"] = 0.0
	for name in sinks.keys():
		if sinks[name]["target_id"] == id:
			sinks[name]["target_id"] = 0
			sinks[name]["status"] = "Ziel entfernt"
			sinks[name]["last_power_w"] = 0.0


func step(dt: float, registry: EntityRegistry) -> void:
	if dt <= 0.0:
		return
	var names := heaters.keys()
	names.sort()
	for n in names:
		_apply_heater(heaters[n], n, dt, registry)
	names = sinks.keys()
	names.sort()
	for n in names:
		_apply_sink(sinks[n], dt, registry)
	var keys := contacts.keys()
	keys.sort()
	for k in keys:
		_apply_contact(contacts[k], dt, registry)
	if environment_enabled:
		for id in registry.ids():
			# Nur physikalische Objekte tauschen Wärme aus (Wesen/Weltobjekte sind eigene Entitäten).
			var e = registry.get_entity(id)
			if e is PhysicalObject:
				_apply_environment(e, dt)


func _apply_heater(h: Dictionary, name: String, dt: float, registry: EntityRegistry) -> void:
	h["last_power_w"] = 0.0
	if not h["enabled"]:
		h["status"] = "aus"
		return
	var obj: PhysicalObject = registry.get_entity(h["target_id"]) as PhysicalObject
	if obj == null:
		h["status"] = "Ziel entfernt"
		return
	var mat := obj.material()
	var e_limit := obj.mass_kg * mat.enthalpy_from_temperature(mat.valid_max_k, 1.0)
	var room := e_limit - obj.thermal_energy_j
	if room <= 0.0:
		if h["status"] != "Modellgrenze":
			_log("heater_blocked_model_limit", [obj.id], {"name": name, "limit_k": mat.valid_max_k})
		h["status"] = "Modellgrenze"
		return
	var q := minf(h["power_w"] * dt, room)
	obj.thermal_energy_j += q
	h["supplied_j"] += q
	h["last_power_w"] = q / dt
	h["status"] = "heizt" if q > 0.0 else "an"


func _apply_sink(s: Dictionary, dt: float, registry: EntityRegistry) -> void:
	s["last_power_w"] = 0.0
	if not s["enabled"]:
		s["status"] = "aus"
		return
	var obj: PhysicalObject = registry.get_entity(s["target_id"]) as PhysicalObject
	if obj == null:
		s["status"] = "Ziel entfernt"
		return
	var e_at_sink := obj.mass_kg * obj.material().enthalpy_from_temperature(s["sink_temperature_k"], 0.0)
	var available := obj.thermal_energy_j - e_at_sink
	if available <= 0.0:
		s["status"] = "Senkentemperatur erreicht"
		return
	var q := minf(s["power_w"] * dt, available)
	obj.thermal_energy_j -= q
	s["absorbed_j"] += q
	s["last_power_w"] = q / dt
	s["status"] = "kühlt"


func _apply_contact(c: Dictionary, dt: float, registry: EntityRegistry) -> void:
	c["last_flow_w"] = 0.0
	if not c["enabled"]:
		return
	var a: PhysicalObject = registry.get_entity(c["a"]) as PhysicalObject
	var b: PhysicalObject = registry.get_entity(c["b"]) as PhysicalObject
	if a == null or b == null:
		return
	var ta := a.temperature_k()
	var tb := b.temperature_k()
	if is_equal_approx(ta, tb):
		return
	var hot := a if ta > tb else b
	var cold := b if ta > tb else a
	var dT := absf(ta - tb)
	var q := _exact_pair_transfer(c["conductance_w_k"], dT, dt, hot, cold)
	q = _limit_pair(hot, cold, q)
	hot.thermal_energy_j -= q
	cold.thermal_energy_j += q
	var signed := q if hot == a else -q   # positiv: Fluss von a nach b
	c["transferred_j"] += signed
	c["last_flow_w"] = signed / dt


func _apply_environment(obj: PhysicalObject, dt: float) -> void:
	if obj == null:
		return
	var t := obj.temperature_k()
	var dT := t - ambient_temperature_k
	if absf(dT) < 1e-9:
		return
	var g := convection_coefficient * obj.surface_area_m2()
	var inv_c := _inv_capacity(obj)
	var q: float
	if inv_c == 0.0:
		q = g * dT * dt
	else:
		q = dT * (1.0 - exp(-g * dt * inv_c)) / inv_c
	# Begrenzung: Objekt überschreitet die Umgebungstemperatur nicht.
	var e_amb := obj.mass_kg * obj.material().enthalpy_from_temperature(ambient_temperature_k, 0.0 if ambient_temperature_k < obj.material().melting_point or not obj.material().has_melting() else 1.0)
	var max_q := obj.thermal_energy_j - e_amb  # >0: so viel darf abgegeben werden
	if q > 0.0:
		q = minf(q, maxf(max_q, 0.0))
	else:
		q = maxf(q, minf(max_q, 0.0))
	obj.thermal_energy_j -= q
	environment_energy_j += q


## Exakte Lösung für zwei Körper mit konstanten Wärmekapazitäten:
## Q = ΔT · (1 − e^(−G·dt·(1/C1+1/C2))) / (1/C1+1/C2).
## Während des Schmelzens bleibt T konstant → Kapazität dort als unendlich (1/C = 0).
func _exact_pair_transfer(g: float, dT: float, dt: float, hot: PhysicalObject, cold: PhysicalObject) -> float:
	var inv := _inv_capacity(hot) + _inv_capacity(cold)
	if inv == 0.0:
		return g * dT * dt
	return dT * (1.0 - exp(-g * dt * inv)) / inv


func _inv_capacity(o: PhysicalObject) -> float:
	if o.phase_state() == "melting":
		return 0.0
	return 1.0 / o.heat_capacity_j_k()


## Begrenzt Q, sodass T_heiß(E−Q) ≥ T_kalt(E+Q) bleibt (Bisektion, monoton).
func _limit_pair(hot: PhysicalObject, cold: PhysicalObject, q: float) -> float:
	if _temp_after(hot, -q) >= _temp_after(cold, q):
		return q
	var lo := 0.0
	var hi := q
	for i in 60:
		var mid := (lo + hi) * 0.5
		if _temp_after(hot, -mid) >= _temp_after(cold, mid):
			lo = mid
		else:
			hi = mid
	return lo


func _temp_after(o: PhysicalObject, delta_e: float) -> float:
	return o.material().temperature_from_enthalpy((o.thermal_energy_j + delta_e) / o.mass_kg)


func total_object_energy(registry: EntityRegistry) -> float:
	var s := 0.0
	for id in registry.ids():
		var e = registry.get_entity(id)
		if e is PhysicalObject:
			s += e.thermal_energy_j
	return s


func ledger(registry: EntityRegistry) -> Dictionary:
	var heat_in := 0.0
	for n in heaters:
		heat_in += heaters[n]["supplied_j"]
	var sink_out := 0.0
	for n in sinks:
		sink_out += sinks[n]["absorbed_j"]
	var objects := total_object_energy(registry)
	return {
		"objects_j": objects,
		"environment_j": environment_energy_j,
		"sinks_j": sink_out,
		"heaters_j": heat_in,
		"body_j": body_energy_j,
		"balance_j": objects + environment_energy_j + sink_out + body_energy_j - heat_in,
	}


func to_dict() -> Dictionary:
	return {
		"ambient_temperature_k": ambient_temperature_k,
		"environment_enabled": environment_enabled,
		"convection_coefficient": convection_coefficient,
		"environment_energy_j": environment_energy_j,
		"body_energy_j": body_energy_j,
		"contacts": contacts.duplicate(true),
		"heaters": heaters.duplicate(true),
		"sinks": sinks.duplicate(true),
	}


func _log(type: String, ids: Array, data: Dictionary, severity: String = "info") -> void:
	if event_log != null:
		event_log.add(type, ids, data, severity)
