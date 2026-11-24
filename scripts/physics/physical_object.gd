class_name PhysicalObject
extends RefCounted
## Physikalischer Zustand eines Testobjekts – unabhängig von seiner Darstellung.
##
## GESPEICHERT (Quelle der Wahrheit):
##   id, material_id, mass_kg, thermal_energy_j (= Masse · spezifische Enthalpie),
##   damage (0..1, Spielmodell), deformed, station, label, origin, parent_ids
## ABGELEITET (nie gespeichert):
##   Volumen = Masse / Dichte, Temperatur und Flüssiganteil aus der Enthalpie,
##   Dichte aus dem Material.
## Position und Geschwindigkeit führt ausschließlich Godots Physikkörper.

var id: int = 0
var material_id: String = ""
var mass_kg: float = 0.0
var thermal_energy_j: float = 0.0
var damage: float = 0.0
var deformed: bool = false
var station: String = ""
var label: String = ""
var origin: String = "lab_created"
var parent_ids: Array = []

var _material: MaterialDefinition  # Nur Cache auf die unveränderliche Definition


## Erzeugt ein Objekt aus Volumen und Temperatur: Masse = Dichte · Volumen.
## Gibt null zurück und füllt errors, wenn Werte ungültig sind.
static func create(material: MaterialDefinition, volume_m3: float, temperature_k: float, errors: Array, liquid_fraction: float = 0.0) -> PhysicalObject:
	if material == null:
		errors.append("Unbekanntes Material.")
		return null
	if not (volume_m3 > 0.0) or is_inf(volume_m3):
		errors.append("Volumen muss > 0 sein (gefunden: %s)." % volume_m3)
		return null
	if not (temperature_k > 0.0) or is_inf(temperature_k):
		errors.append("Temperatur muss > 0 K sein (gefunden: %s)." % temperature_k)
		return null
	if temperature_k < material.valid_min_k or temperature_k > material.valid_max_k:
		errors.append("Temperatur %.2f K liegt außerhalb des Modellbereichs von %s (%.2f–%.2f K)." % [temperature_k, material.id, material.valid_min_k, material.valid_max_k])
		return null
	var o := PhysicalObject.new()
	o._material = material
	o.material_id = material.id
	o.mass_kg = material.density * volume_m3
	o.thermal_energy_j = o.mass_kg * material.enthalpy_from_temperature(temperature_k, liquid_fraction)
	return o


## Erzeugt ein Objekt direkt aus Masse und Energie (Fragmente, Teilmengen).
static func create_from_mass_energy(material: MaterialDefinition, mass: float, energy_j: float) -> PhysicalObject:
	var o := PhysicalObject.new()
	o._material = material
	o.material_id = material.id
	o.mass_kg = mass
	o.thermal_energy_j = energy_j
	return o


func material() -> MaterialDefinition:
	return _material


func bind_material(m: MaterialDefinition) -> void:
	_material = m


func specific_enthalpy() -> float:
	return thermal_energy_j / mass_kg


func volume_m3() -> float:
	return mass_kg / _material.density


func temperature_k() -> float:
	return _material.temperature_from_enthalpy(specific_enthalpy())


func liquid_fraction() -> float:
	return _material.liquid_fraction_from_enthalpy(specific_enthalpy())


## "solid", "melting", "liquid"
func phase_state() -> String:
	var lf := liquid_fraction()
	if lf <= 0.0:
		return "solid"
	if lf >= 1.0:
		return "liquid"
	return "melting"


## Wärmekapazität [J/K] im aktuellen Zustand.
func heat_capacity_j_k() -> float:
	return mass_kg * _material.cp_at_enthalpy(specific_enthalpy())


## Würfelnäherung für Oberfläche (Umgebungsaustausch) und Darstellung.
func cube_edge_m() -> float:
	return pow(volume_m3(), 1.0 / 3.0)


func surface_area_m2() -> float:
	var e := cube_edge_m()
	return 6.0 * e * e


func to_dict() -> Dictionary:
	return {
		"id": id,
		"material_id": material_id,
		"mass_kg": mass_kg,
		"thermal_energy_j": thermal_energy_j,
		"damage": damage,
		"deformed": deformed,
		"station": station,
		"label": label,
		"origin": origin,
		"parent_ids": parent_ids.duplicate(),
		"derived": {
			"temperature_k": temperature_k(),
			"liquid_fraction": liquid_fraction(),
			"volume_m3": volume_m3(),
		},
	}


static func from_dict(d: Dictionary, materials: MaterialRegistry) -> PhysicalObject:
	var m := materials.get_material(str(d.get("material_id", "")))
	if m == null:
		return null
	var o := create_from_mass_energy(m, float(d["mass_kg"]), float(d["thermal_energy_j"]))
	o.id = int(d.get("id", 0))
	o.damage = float(d.get("damage", 0.0))
	o.deformed = bool(d.get("deformed", false))
	o.station = str(d.get("station", ""))
	o.label = str(d.get("label", ""))
	o.origin = str(d.get("origin", ""))
	o.parent_ids = d.get("parent_ids", []).duplicate()
	return o
