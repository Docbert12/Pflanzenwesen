class_name Metabolism
extends RefCounted
## VEREINFACHTE RESSOURCENBILANZ (Spielbiologie, Werte in data/config/life.json).
## Pools: Energie [J, Spieleinheit], Nährstoffe [g, Spieleinheit].
## Zufluss: Nahrung (assimiliert = Masse · Verdauungsgrad), Licht (nur Energie).
## Abfluss: Grundumsatz (∝ Körpermasse), Blattunterhalt (je Blatt), Bewegung (∝ Masse · Weg),
##          Handlungen (Leistung je Handlungstyp), Nährstoffverbrauch (∝ Masse).
## Nicht assimilierter Anteil der Nahrung wird als Abfall bilanziert (ResourceLedger).
## Bilanz: Energie_jetzt = Energie_start + Σ Zufluss − Σ Abfluss − Überlauf (bei vollem Speicher).

var energy_j: float = 0.0
var energy_capacity_j: float = 1.0
var nutrients_g: float = 0.0
var nutrient_capacity_g: float = 1.0
var totals := {"food_energy_j": 0.0, "light_energy_j": 0.0, "basal_j": 0.0, "leaf_upkeep_j": 0.0, "move_j": 0.0,
	"action_j": 0.0, "overflow_j": 0.0, "food_nutrients_g": 0.0, "nutrient_use_g": 0.0, "nutrient_overflow_g": 0.0,
	"eaten_kg": 0.0, "assimilated_kg": 0.0, "waste_kg": 0.0, "deficit_j": 0.0}
var start_energy_j: float = 0.0
var start_nutrients_g: float = 0.0
var last_power := {}   # letzte Leistungen [W] für die Anzeige


func setup(mass_kg: float, start_fraction: float, cfg: Dictionary) -> void:
	var m: Dictionary = cfg.get("metabolism", {})
	energy_capacity_j = mass_kg * float(m.get("energy_capacity_j_per_kg", 1500.0))
	nutrient_capacity_g = mass_kg * float(m.get("nutrient_capacity_g_per_kg", 2.0))
	energy_j = energy_capacity_j * start_fraction
	nutrients_g = nutrient_capacity_g * start_fraction
	start_energy_j = energy_j
	start_nutrients_g = nutrients_g


## Kapazität nach Körperänderung anpassen (Inhalt bleibt, wird höchstens gekappt → Überlauf).
func update_capacity(mass_kg: float, cfg: Dictionary) -> void:
	var m: Dictionary = cfg.get("metabolism", {})
	energy_capacity_j = mass_kg * float(m.get("energy_capacity_j_per_kg", 1500.0))
	nutrient_capacity_g = mass_kg * float(m.get("nutrient_capacity_g_per_kg", 2.0))
	_cap()


func energy_fraction() -> float:
	return energy_j / maxf(energy_capacity_j, 1e-9)


func nutrient_fraction() -> float:
	return nutrients_g / maxf(nutrient_capacity_g, 1e-9)


## Hunger 0…1 (Excel-Skala „Hunger“ 0–100 / 100): größerer Mangel von Energie oder Nährstoffen.
func hunger() -> float:
	return clampf(1.0 - minf(energy_fraction(), nutrient_fraction()), 0.0, 1.0)


## Ein Stoffwechselschritt. Rückgabe Dictionary mit Mangelinformation.
func step(dt: float, mass_kg: float, leaf_count: int, moved_m: float, action_w: float, light_w: float, cfg: Dictionary) -> Dictionary:
	var m: Dictionary = cfg.get("metabolism", {})
	var basal := float(m.get("basal_w_per_kg", 1.0)) * mass_kg
	var upkeep := float(m.get("leaf_upkeep_w", 0.25)) * leaf_count
	var move_j := float(m.get("move_cost_j_per_kg_m", 2.0)) * mass_kg * moved_m
	var e_in := light_w * dt
	var e_out := (basal + upkeep + action_w) * dt + move_j
	totals["light_energy_j"] += e_in
	totals["basal_j"] += basal * dt
	totals["leaf_upkeep_j"] += upkeep * dt
	totals["move_j"] += move_j
	totals["action_j"] += action_w * dt
	energy_j += e_in - e_out
	var deficit := 0.0
	if energy_j < 0.0:
		deficit = -energy_j
		totals["deficit_j"] += deficit
		energy_j = 0.0
	var n_use := float(m.get("nutrient_use_g_per_s_per_kg", 0.0006)) * mass_kg * dt
	totals["nutrient_use_g"] += minf(n_use, nutrients_g)
	nutrients_g -= n_use
	var n_deficit := false
	if nutrients_g < 0.0:
		nutrients_g = 0.0
		n_deficit = true
	_cap()
	last_power = {"light_w": light_w, "basal_w": basal, "leaf_upkeep_w": upkeep, "move_w": move_j / maxf(dt, 1e-9), "action_w": action_w}
	return {"energy_deficit_j": deficit, "energy_empty": energy_j <= 0.0, "nutrients_empty": n_deficit or nutrients_g <= 0.0}


## Nahrung aufnehmen: kg tatsächlich gegessene Masse mit Eigenschaften props.
func ingest(kg: float, props: Dictionary, ledger: ResourceLedger) -> void:
	if kg <= 0.0:
		return
	var m_eff := 0.8
	if ledger != null:
		m_eff = ledger.digest_efficiency
	var assimilated := kg * m_eff
	var waste := kg - assimilated
	var e := assimilated * float(props.get("energy_j_per_kg", 0.0))
	var n := assimilated * float(props.get("nutrients_g_per_kg", 0.0))
	energy_j += e
	nutrients_g += n
	totals["food_energy_j"] += e
	totals["food_nutrients_g"] += n
	totals["eaten_kg"] += kg
	totals["assimilated_kg"] += assimilated
	totals["waste_kg"] += waste
	if ledger != null:
		ledger.eaten_kg += kg
		ledger.assimilated_kg += assimilated
		ledger.waste_kg += waste
	_cap()


func _cap() -> void:
	if energy_j > energy_capacity_j:
		totals["overflow_j"] += energy_j - energy_capacity_j
		energy_j = energy_capacity_j
	if nutrients_g > nutrient_capacity_g:
		totals["nutrient_overflow_g"] += nutrients_g - nutrient_capacity_g
		nutrients_g = nutrient_capacity_g


## Energiebilanz-Abweichung [J] (0 = geschlossen).
func energy_balance_error() -> float:
	var t := totals
	var expected: float = start_energy_j + t["food_energy_j"] + t["light_energy_j"] - t["basal_j"] - t["leaf_upkeep_j"] - t["move_j"] - t["action_j"] - t["overflow_j"] + t["deficit_j"]
	return energy_j - expected


func to_dict() -> Dictionary:
	return {"energy_j": energy_j, "energy_capacity_j": energy_capacity_j, "nutrients_g": nutrients_g, "nutrient_capacity_g": nutrient_capacity_g,
		"start_energy_j": start_energy_j, "start_nutrients_g": start_nutrients_g, "totals": totals.duplicate()}


static func from_dict(d: Dictionary) -> Metabolism:
	var m := Metabolism.new()
	m.energy_j = float(d["energy_j"])
	m.energy_capacity_j = float(d["energy_capacity_j"])
	m.nutrients_g = float(d["nutrients_g"])
	m.nutrient_capacity_g = float(d["nutrient_capacity_g"])
	m.start_energy_j = float(d.get("start_energy_j", m.energy_j))
	m.start_nutrients_g = float(d.get("start_nutrients_g", m.nutrients_g))
	for k in d.get("totals", {}):
		m.totals[k] = float(d["totals"][k])
	return m
