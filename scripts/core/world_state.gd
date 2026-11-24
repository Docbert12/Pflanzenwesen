class_name WorldState
extends RefCounted
## Serialisierbarer Zustand der aktuellen Testobjekte.
## Enthält ausschließlich Daten (Zahlen, Texte, Arrays, Dictionaries) –
## keine Node- oder Objektreferenzen. Keine vollständige Spielstandsverwaltung.

const SCHEMA_VERSION := 1


## transforms: Dictionary id -> {"position": [x,y,z], "linear_velocity": [...]}
## (vom Labor aus Godots Physikkörpern gelesen; Position ist dort die Quelle der Wahrheit).
static func capture(sim, transforms: Dictionary = {}) -> Dictionary:
	var objects: Array = []
	for id in sim.registry.ids():
		var obj = sim.registry.get_entity(id)
		var d: Dictionary = obj.to_dict()
		if transforms.has(id):
			d["body"] = transforms[id]
		objects.append(d)
	return {
		"schema_version": SCHEMA_VERSION,
		"random_seed": sim.settings.get("random_seed", 0),
		"clock": sim.clock.to_dict(),
		"objects": objects,
		"thermal": sim.thermal.to_dict(),
	}


## Prüft, dass ein Zustand nur JSON-fähige Daten enthält.
static func is_pure_data(value) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for v in value:
				if not is_pure_data(v):
					return false
			return true
		TYPE_DICTIONARY:
			for k in value.keys():
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_INT:
					return false
				if not is_pure_data(value[k]):
					return false
			return true
	return false
