class_name Health
extends RefCounted
## Gesundheit: lokaler Schaden je Körperteil (0 = intakt … 1 = funktionslos) und
## Mangelschaden durch anhaltenden Energie-/Nährstoffmangel.
## Vitalität = (1 − Mangelschaden) · (1 − Schaden Rumpf) · (1 − Schaden Kopf). Tod bei Vitalität ≤ 0.
## Schaden 1 an einem abnehmbaren Teil (Glieder, Blätter) bedeutet Verlust des Teils
## (BodyPlan.remove_part). Keine Regeneration in diesem Schritt.

var part_damage: Dictionary = {}   # part id -> 0..1
var starvation: float = 0.0
var causes: Array = []             # Protokoll {t, part, amount, cause}


func damage_of(pid: String) -> float:
	return float(part_damage.get(pid, 0.0))


## Fügt Schaden zu. Rückgabe {"removed": Array} falls ein Teil verloren ging.
func damage_part(plan: BodyPlan, pid: String, amount: float, cause: String, t: float) -> Dictionary:
	if not plan.parts.has(pid) or not plan.is_present(pid):
		return {"ok": false, "removed": [], "message": "Teil '%s' nicht vorhanden." % pid}
	var d := clampf(damage_of(pid) + amount, 0.0, 1.0)
	part_damage[pid] = d
	causes.append({"t": t, "part": pid, "amount": amount, "cause": cause})
	if causes.size() > 50:
		causes.pop_front()
	var removed: Array = []
	if d >= 1.0 and plan.parts[pid]["parent"] != "" and pid != "head":
		var r := plan.remove_part(pid, "Verlust durch Schaden (%s)" % cause)
		removed = r.get("removed", [])
	return {"ok": true, "removed": removed, "damage": d}


func vitality() -> float:
	return clampf((1.0 - starvation) * (1.0 - damage_of("torso")) * (1.0 - damage_of("head")), 0.0, 1.0)


func is_dead() -> bool:
	return vitality() <= 0.0


func to_dict() -> Dictionary:
	return {"part_damage": part_damage.duplicate(), "starvation": starvation, "causes": causes.duplicate(true)}


static func from_dict(d: Dictionary) -> Health:
	var h := Health.new()
	for k in d.get("part_damage", {}):
		h.part_damage[str(k)] = float(d["part_damage"][k])
	h.starvation = float(d.get("starvation", 0.0))
	h.causes = d.get("causes", []).duplicate(true)
	return h
