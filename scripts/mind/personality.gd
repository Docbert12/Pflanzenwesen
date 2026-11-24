class_name Personality
extends RefCounted
## Wenige, verständliche Persönlichkeitswerte (0…1), SPIELPARAMETER (data/config/mind.json).
## - Reproduzierbar aus dem Körper-Startwert (plan_seed) + seed_salt.
## - Unabhängig von Farbe, Art, Körperform oder Mutation; keine Kategorien „gut/böse“.
## - Keine Berufsklasse. Ändert sich in dieser Version nicht (keine Drift durch Ereignisse).
## - Kurzfristige Zustände (Hunger, Bedrohung) liegen NICHT hier, sondern im Stoffwechsel.
## Wirkung (siehe DecisionSystem): Neugier → Erkunden/Ausprobieren, Geselligkeit → Annäherung,
## Hilfsbereitschaft → Teilen/Antworten auf Bitten, Vorsicht → Abschlag für unsichere Optionen,
## Beharrlichkeit → Mindestbindung an Ziele.

var values: Dictionary = {}


static func generate(plan_seed: int, cfg: Dictionary) -> Personality:
	var pc: Dictionary = cfg.get("personality", {})
	var p := Personality.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = plan_seed * 31 + int(pc.get("seed_salt", 7151))
	var mean := float(pc.get("mean", 0.5))
	var spread := float(pc.get("spread", 0.18))
	for t in pc.get("traits", []):
		# Summe dreier Gleichverteilungen: annähernd glockenförmig, Standardabweichung ≈ spread
		var z := (rng.randf() + rng.randf() + rng.randf() - 1.5) / 0.5
		p.values[t] = clampf(mean + z * spread, float(pc.get("min", 0.05)), float(pc.get("max", 0.95)))
	return p


func v(trait_id: String) -> float:
	return float(values.get(trait_id, 0.5))


func describe(cfg: Dictionary) -> String:
	var labels: Dictionary = cfg.get("personality", {}).get("labels", {})
	var parts: Array = []
	for t in values:
		parts.append("%s %.2f" % [labels.get(t, t), values[t]])
	return " · ".join(parts)


func to_dict() -> Dictionary:
	return values.duplicate()


static func from_dict(d: Dictionary) -> Personality:
	var p := Personality.new()
	for k in d:
		p.values[str(k)] = float(d[k])
	return p
