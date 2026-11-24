class_name DamageSystem
extends RefCounted
## SPIELMODELL für mechanische Beschädigung – keine reale Bruchmechanik.
## Eine Laborbelastung (Energie in J) erhöht den Schaden um
##     Δd = Last / (Masse · Zähigkeit_Spiel)
## Bei d ≥ 1: spröde/faserige/weiche Materialien zerbrechen in 2..max_fragments
## Teile, duktile Materialien (Kupfer) verformen sich nur.
## Fragmente: Massen summieren sich exakt zur Ausgangsmasse, die thermische
## Energie wird massenanteilig verteilt (gleiche Temperatur in allen Teilen).

const MAX_LOAD_J := 1.0e6


func apply_load(sim, id: int, load_j: float) -> Dictionary:
	var obj: PhysicalObject = sim.registry.get_entity(id) as PhysicalObject
	if obj == null:
		return _reject(sim, id, "Objekt %d existiert nicht." % id)
	if not (load_j > 0.0) or load_j > MAX_LOAD_J:
		return _reject(sim, id, "Belastung muss zwischen 0 und %.0f J liegen." % MAX_LOAD_J)
	var mat := obj.material()
	if mat.fracture_behavior == "not_applicable":
		return _reject(sim, id, "Für %s ist mechanische Belastung nicht modelliert." % mat.display_name)
	if obj.liquid_fraction() > 0.0:
		return _reject(sim, id, "Probe ist (teilweise) flüssig – Belastung nicht modelliert.")
	var before := obj.damage
	obj.damage = minf(1.0, obj.damage + load_j / (obj.mass_kg * mat.toughness_j_kg))
	sim.event_log.add("mechanical_load", [id], {"load_j": load_j, "damage_before": before, "damage_after": obj.damage, "lab_intervention": true})
	if obj.damage < 1.0:
		return {"ok": true, "status": "damaged", "damage": obj.damage}
	if mat.fracture_behavior == "ductile":
		if not obj.deformed:
			obj.deformed = true
			sim.event_log.add("deformed", [id], {"material": mat.id})
		return {"ok": true, "status": "deformed", "damage": obj.damage}
	return _fracture(sim, obj)


func _fracture(sim, obj: PhysicalObject) -> Dictionary:
	var mat := obj.material()
	var n: int = sim.rng.randi_range(2, maxi(2, mat.max_fragments))
	var mass_before := obj.mass_kg
	var shares := fragment_shares(sim.rng, mass_before, obj.thermal_energy_j, n)
	var frag_ids: Array = []
	var mass_acc := 0.0
	for i in n:
		mass_acc += float(shares[i][0])
		var f := PhysicalObject.create_from_mass_energy(mat, shares[i][0], shares[i][1])
		f.station = obj.station
		f.label = "Fragment %d/%d von #%d" % [i + 1, n, obj.id]
		f.origin = "fracture"
		f.parent_ids = [obj.id]
		var fid: int = sim.add_object(f)
		if fid > 0:
			frag_ids.append(fid)
	sim.remove_object(obj.id)
	sim.event_log.add("fractured", [obj.id] + frag_ids, {"fragments": n, "mass_before_kg": mass_before, "mass_after_kg": mass_acc})
	return {"ok": true, "status": "fractured", "fragment_ids": frag_ids, "mass_before_kg": mass_before, "mass_after_kg": mass_acc}


## Aufteilung in n Teile mit zufälligen Gewichten 0,5..1,5: [[Masse, Energie], …].
## Der letzte Teil schließt die Bilanz exakt (gemeinsam mit MaterialProcessSystem.work_piece genutzt).
static func fragment_shares(rng: RandomNumberGenerator, mass: float, energy: float, n: int) -> Array:
	var weights: Array = []
	var wsum := 0.0
	for i in n:
		var w: float = rng.randf_range(0.5, 1.5)
		weights.append(w)
		wsum += w
	var res: Array = []
	var mass_acc := 0.0
	var energy_acc := 0.0
	for i in n:
		var m: float
		var e: float
		if i < n - 1:
			m = mass * weights[i] / wsum
			e = energy * m / mass
		else:
			m = mass - mass_acc
			e = energy - energy_acc
		mass_acc += m
		energy_acc += e
		res.append([m, e])
	return res


func _reject(sim, id: int, message: String) -> Dictionary:
	sim.event_log.add("load_rejected", [id], {"reason": message}, "warning")
	return {"ok": false, "status": "rejected", "message": message}
