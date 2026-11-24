class_name FoodSource
extends RefCounted
## Endliche Nahrungsquelle (Beerenstrauch, Pilz). Restmenge sinkt nur durch tatsächliche Entnahme.
## Reservierungen (res_id → kg) senken die verfügbare Menge; Entnahme nur gegen gültige Reservierung.
## Keine automatische Wiederauffüllung (nur sichtbare Testoption im Entwicklermodus).

var id: int = 0
var kind: String = ""            # Excel-Pflanze, z. B. P007
var food_id: String = ""         # Excel-Nahrung, z. B. N001
var display_name: String = ""
var position: Vector3
var amount_kg: float = 0.0
var initial_kg: float = 0.0
var energy_j_per_kg: float = 0.0
var nutrients_g_per_kg: float = 0.0
var plant_seed: int = 0
var plant_kind: String = ""      # Generatorart (bush, mushroom_red …)
var reserved: Dictionary = {}    # res_id -> kg
var refilled_kg: float = 0.0     # nur Testoption


func available_kg() -> float:
	var s := 0.0
	for r in reserved:
		s += reserved[r]
	return maxf(0.0, amount_kg - s)


## Atomare Entnahme gegen eine Reservierung. Gibt die tatsächlich entnommene Menge zurück.
func take_reserved(res_id: int, kg: float) -> float:
	if not reserved.has(res_id) or kg <= 0.0:
		return 0.0
	var take := minf(minf(kg, float(reserved[res_id])), amount_kg)
	amount_kg -= take
	reserved[res_id] = float(reserved[res_id]) - take
	if reserved[res_id] <= 1e-12:
		reserved[res_id] = 0.0
	return take


func fraction() -> float:
	return amount_kg / maxf(initial_kg, 1e-9)


func props() -> Dictionary:
	return {"food_id": food_id, "kind": kind, "energy_j_per_kg": energy_j_per_kg, "nutrients_g_per_kg": nutrients_g_per_kg}


func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "food_id": food_id, "display_name": display_name, "position": [position.x, position.y, position.z],
		"amount_kg": amount_kg, "initial_kg": initial_kg, "energy_j_per_kg": energy_j_per_kg, "nutrients_g_per_kg": nutrients_g_per_kg,
		"plant_seed": plant_seed, "plant_kind": plant_kind, "refilled_kg": refilled_kg}


static func from_dict(d: Dictionary) -> FoodSource:
	var f := FoodSource.new()
	f.id = int(d["id"])
	f.kind = str(d["kind"])
	f.food_id = str(d["food_id"])
	f.display_name = str(d.get("display_name", ""))
	f.position = Vector3(d["position"][0], d["position"][1], d["position"][2])
	f.amount_kg = float(d["amount_kg"])
	f.initial_kg = float(d["initial_kg"])
	f.energy_j_per_kg = float(d["energy_j_per_kg"])
	f.nutrients_g_per_kg = float(d["nutrients_g_per_kg"])
	f.plant_seed = int(d.get("plant_seed", 0))
	f.plant_kind = str(d.get("plant_kind", ""))
	f.refilled_kg = float(d.get("refilled_kg", 0.0))
	return f
