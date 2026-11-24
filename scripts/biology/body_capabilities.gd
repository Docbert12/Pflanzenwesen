class_name BodyCapabilities
extends RefCounted
## Leitet Körperfähigkeiten aus vorhandenen Teilen, deren FUNKTION und Schaden ab –
## nicht aus festen Gliedmaßennamen. Tabelle: data/config/life.json → capabilities.by_function.
## Wirksamer Beitrag eines Teils = Tabellenwert · Π(1 − Schaden) über das Teil und alle Vorfahren
## (ein verletzter Oberarm schwächt auch die Hand daran).
## Fortbewegung: Summe der Beiträge; Gehen nur, wenn jede Körperseite ≥ walk_min_per_side beiträgt
## (Zweibeiner; Hinken/Kriechen ist nicht implementiert).

static func compute(plan: BodyPlan, health: Health, life_cfg: Dictionary) -> Dictionary:
	var table: Dictionary = life_cfg.get("capabilities", {}).get("by_function", {})
	var walk_min := float(life_cfg.get("health", {}).get("walk_min_per_side", 0.2))
	var leaf_factor := float(life_cfg.get("photosynthesis", {}).get("leaf_area_factor", 0.6))
	var loco_side := {"l": 0.0, "r": 0.0}
	var grasp_side := {"l": 0.0, "r": 0.0}
	var feed_side := {"l": 0.0, "r": 0.0}
	var mouth := 0.0
	var perception := 0.0
	var gesture := 0.0
	var leaf_area := 0.0
	var leaf_area_nominal := 0.0
	var contributors := {"locomotion": [], "grasp": [], "feeding": [], "mouth": [], "photosynthesis": [], "gesture": []}
	for pid in plan.present_ids():
		var p: Dictionary = plan.parts[pid]
		var contrib: Dictionary = table.get(p["function"], {})
		if contrib.is_empty():
			continue
		var h := _chain_health(plan, health, pid)
		var side: String = p.get("side", "")
		for cap in contrib:
			var v := float(contrib[cap]) * h
			match cap:
				"locomotion":
					if side in loco_side:
						loco_side[side] += v
				"grasp":
					if side in grasp_side:
						grasp_side[side] = maxf(grasp_side[side], v)
				"feeding":
					if side in feed_side:
						feed_side[side] = maxf(feed_side[side], v)
				"mouth":
					mouth = maxf(mouth, v)
				"perception":
					perception = maxf(perception, v)
				"gesture":
					gesture = minf(1.0, gesture + v)   # Oberarme: Arme heben (Prompt 4)
				"photosynthesis":
					var a := float(p["size"][0]) * float(p["size"][1]) * leaf_factor
					leaf_area += a * h
					leaf_area_nominal += a
			if v > 0.0 and contributors.has(cap):
				contributors[cap].append("%s %.2f" % [pid, v])
	var loco: float = loco_side["l"] + loco_side["r"]
	var can_walk: bool = loco_side["l"] >= walk_min and loco_side["r"] >= walk_min
	var reason := ""
	if not can_walk:
		reason = "Beitrag links %.2f / rechts %.2f < %.2f je Seite; Hinken/Kriechen ist nicht implementiert" % [loco_side["l"], loco_side["r"], walk_min]
	var gs := "r" if grasp_side["r"] >= grasp_side["l"] else "l"
	var fs := "r" if feed_side["r"] >= feed_side["l"] else "l"
	var explain := {}
	for cap in contributors:
		explain[cap] = ", ".join(contributors[cap]) if not contributors[cap].is_empty() else "kein beitragendes Körperteil"
	return {
		"locomotion": loco if can_walk else 0.0, "locomotion_raw": loco, "locomotion_side": loco_side,
		"can_walk": can_walk, "walk_reason": reason,
		"grasp": grasp_side[gs], "grasp_side": gs, "grasp_by_side": grasp_side,
		"feeding": feed_side[fs], "feeding_side": fs,
		"mouth": mouth, "perception": perception, "gesture": gesture,
		"leaf_area_m2": leaf_area, "leaf_area_nominal_m2": leaf_area_nominal, "leaf_count": plan.leaf_ids().size(),
		"explain": explain,
	}


static func _chain_health(plan: BodyPlan, health: Health, pid: String) -> float:
	var h := 1.0
	var cur := pid
	var guard := 0
	while cur != "" and guard < 32:
		h *= 1.0 - health.damage_of(cur)
		cur = plan.parts[cur]["parent"]
		guard += 1
	return h
