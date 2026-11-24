class_name FoodItem
extends RefCounted
## Eine entnommene Nahrungsportion (getragen oder am Boden liegend).

var id: int = 0
var food_id: String = ""
var kind: String = ""
var mass_kg: float = 0.0
var energy_j_per_kg: float = 0.0
var nutrients_g_per_kg: float = 0.0
var carrier_id: int = 0          # 0 = liegt am Boden
var position: Vector3
var source_id: int = 0
var reserved_by: int = 0         # Reservierungs-ID oder 0


func props() -> Dictionary:
	return {"food_id": food_id, "kind": kind, "energy_j_per_kg": energy_j_per_kg, "nutrients_g_per_kg": nutrients_g_per_kg}


func to_dict() -> Dictionary:
	return {"id": id, "food_id": food_id, "kind": kind, "mass_kg": mass_kg, "energy_j_per_kg": energy_j_per_kg,
		"nutrients_g_per_kg": nutrients_g_per_kg, "carrier_id": carrier_id, "position": [position.x, position.y, position.z], "source_id": source_id}


static func from_dict(d: Dictionary) -> FoodItem:
	var it := FoodItem.new()
	it.id = int(d["id"])
	it.food_id = str(d["food_id"])
	it.kind = str(d.get("kind", ""))
	it.mass_kg = float(d["mass_kg"])
	it.energy_j_per_kg = float(d["energy_j_per_kg"])
	it.nutrients_g_per_kg = float(d["nutrients_g_per_kg"])
	it.carrier_id = int(d.get("carrier_id", 0))
	it.position = Vector3(d["position"][0], d["position"][1], d["position"][2])
	it.source_id = int(d.get("source_id", 0))
	return it
