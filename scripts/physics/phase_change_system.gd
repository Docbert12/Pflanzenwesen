class_name PhaseChangeSystem
extends RefCounted
## Erkennt Phasenwechsel und Modellgrenzen und protokolliert sie.
## Die Energiebilanz des Phasenwechsels selbst steckt im Enthalpiemodell
## (MaterialDefinition): Schmelzen/Erstarren entsteht dort ohne Sonderregeln,
## deshalb kann dieses System keine Masse oder Energie erzeugen oder vernichten.

var _last_state: Dictionary = {}   # id -> "solid"/"melting"/"liquid"
var _outside_model: Dictionary = {} # id -> bool


func update(registry: EntityRegistry, event_log: EventLog) -> void:
	for id in registry.ids():
		var obj: PhysicalObject = registry.get_entity(id) as PhysicalObject
		if obj == null:
			continue  # andere Entitätsarten (z. B. Wesen) haben keinen Phasenzustand
		var st := obj.phase_state()
		var prev: String = _last_state.get(id, "")
		_last_state[id] = st
		if prev != "" and prev != st and event_log != null:
			var data := {"material": obj.material_id, "temperature_k": obj.temperature_k(), "liquid_fraction": obj.liquid_fraction()}
			if prev == "solid":
				event_log.add("melting_started", [id], data)
				if st == "liquid":
					event_log.add("melting_complete", [id], data)
			elif prev == "melting":
				event_log.add("melting_complete" if st == "liquid" else "solidification_complete", [id], data)
			elif prev == "liquid":
				event_log.add("solidification_started", [id], data)
				if st == "solid":
					event_log.add("solidification_complete", [id], data)
		var t := obj.temperature_k()
		var mat := obj.material()
		var outside := t > mat.valid_max_k + 1e-6 or t < mat.valid_min_k - 1e-6
		if outside and not _outside_model.get(id, false) and event_log != null:
			event_log.add("model_limit_exceeded", [id], {"temperature_k": t, "valid_min_k": mat.valid_min_k, "valid_max_k": mat.valid_max_k}, "warning")
		_outside_model[id] = outside


func is_outside_model(id: int) -> bool:
	return _outside_model.get(id, false)


func forget(id: int) -> void:
	_last_state.erase(id)
	_outside_model.erase(id)


func clear() -> void:
	_last_state.clear()
	_outside_model.clear()
