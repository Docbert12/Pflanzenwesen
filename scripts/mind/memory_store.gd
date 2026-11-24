class_name MemoryStore
extends RefCounted
## Begrenzter individueller Erinnerungsspeicher.
## Jede Erinnerung enthält ihre eigenen Daten (Kopie aus der Beobachtung) – sie verweist nicht auf
## das globale Ereignisprotokoll, das Einträge verwerfen darf.
## - Zugänglichkeit sinkt mit der Zeit: exp(−Δt·ln2 / (Halbwertszeit · (1 + k·Bedeutung))).
## - Verdichtung: gleiche Art, gleicher Handelnder, gleiches Ziel, gleicher Ort (Raster) innerhalb
##   des Zeitfensters → Zähler + letzter Zeitpunkt. Sicherheit = Minimum (nie gewisser als die
##   unsicherste Einzelbeobachtung). Es entstehen keine neuen Ereignisse.
## - Bei voller Kapazität wird die Erinnerung mit dem kleinsten Wert Bedeutung × Zugänglichkeit verworfen.

var entries: Array = []
var next_id: int = 1
var forgotten: int = 0


static func place_key(p: Vector3, cell_m: float) -> String:
	return "%d,%d" % [floori(p.x / cell_m), floori(p.z / cell_m)]


func accessibility(e: Dictionary, now: float, cfg: Dictionary) -> float:
	var mc: Dictionary = cfg.get("memory", {})
	var hl := float(mc.get("salience_half_life_s", 300.0)) * (1.0 + float(mc.get("significance_slows_decay", 4.0)) * float(e["significance"]))
	return exp(-(now - float(e["t_last"])) * 0.693147 / maxf(hl, 1.0))


## Speichert eine Beobachtung mit persönlicher Bedeutung. Rückgabe: Erinnerung (neu oder verdichtet) oder {}.
func remember(obs: Observation, significance: float, now: float, cfg: Dictionary) -> Dictionary:
	var mc: Dictionary = cfg.get("memory", {})
	if significance < float(mc.get("min_significance_store", 0.08)):
		return {}
	var pk := place_key(obs.position, float(mc.get("merge_place_m", 4.0)))
	var window := float(mc.get("merge_window_s", 120.0))
	for e in entries:
		if e["type"] == obs.event_type and int(e["actor"]) == obs.actor_id and int(e["target"]) == obs.target_id and e["place"] == pk and obs.t - float(e["t_last"]) <= window:
			e["count"] = int(e["count"]) + 1
			e["t_last"] = obs.t
			e["certainty"] = minf(float(e["certainty"]), obs.quality)
			e["significance"] = maxf(float(e["significance"]), significance)
			e["consequences"] = obs.consequences.duplicate(true)   # letzte wahrgenommene Folgen
			return e
	var m := {"id": next_id, "type": obs.event_type, "actor": obs.actor_id, "target": obs.target_id, "participants": obs.participants.duplicate(),
		"pos": [snappedf(obs.position.x, 0.01), snappedf(obs.position.y, 0.01), snappedf(obs.position.z, 0.01)], "place": pk,
		"consequences": obs.consequences.duplicate(true), "certainty": obs.quality, "significance": significance,
		"t_first": obs.t, "t_last": obs.t, "count": 1, "source": obs.source.duplicate(true)}
	next_id += 1
	entries.append(m)
	var cap := int(mc.get("capacity", 64))
	while entries.size() > cap:
		var worst := 0
		var ws := INF
		for i in entries.size():
			var sc := float(entries[i]["significance"]) * accessibility(entries[i], now, cfg)
			if sc < ws:
				ws = sc
				worst = i
		entries.remove_at(worst)
		forgotten += 1
	return m


## Abruf nach Kriterien: {"participant", "type", "types", "near": Vector3, "radius", "since"}; sortiert nach Bedeutung × Zugänglichkeit.
func recall(filter: Dictionary, now: float, cfg: Dictionary, n: int = 5) -> Array:
	var out: Array = []
	for e in entries:
		if filter.has("participant") and not (int(e["actor"]) == int(filter["participant"]) or int(e["target"]) == int(filter["participant"])):
			continue
		if filter.has("type") and e["type"] != filter["type"]:
			continue
		if filter.has("types") and not e["type"] in filter["types"]:
			continue
		if filter.has("since") and float(e["t_last"]) < float(filter["since"]):
			continue
		if filter.has("near"):
			var p: Vector3 = filter["near"]
			if Vector2(float(e["pos"][0]) - p.x, float(e["pos"][2]) - p.z).length() > float(filter.get("radius", 5.0)):
				continue
		out.append(e)
	out.sort_custom(func(a, b): return float(a["significance"]) * accessibility(a, now, cfg) > float(b["significance"]) * accessibility(b, now, cfg))
	return out.slice(0, n)


## Nach Tod/Entfernen eines anderen Wesens bleiben Erinnerungen gültig: sie tragen eigene Daten.
## Diese Funktion prüft nur die interne Konsistenz (für Tests/Audit).
func audit() -> Array:
	var p: Array = []
	var seen := {}
	for e in entries:
		if seen.has(e["id"]):
			p.append("doppelte Erinnerungs-ID %d" % e["id"])
		seen[e["id"]] = true
		if float(e["certainty"]) < 0.0 or float(e["certainty"]) > 1.0:
			p.append("Erinnerung %d: Sicherheit außerhalb 0…1" % e["id"])
	return p


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "next_id": next_id, "forgotten": forgotten}


static func from_dict(d: Dictionary) -> MemoryStore:
	var s := MemoryStore.new()
	s.next_id = int(d.get("next_id", 1))
	s.forgotten = int(d.get("forgotten", 0))
	for e in d.get("entries", []):
		var m: Dictionary = e.duplicate(true)
		for k in ["id", "actor", "target", "count"]:
			m[k] = int(m[k])
		var parts: Array = []
		for x in m.get("participants", []):
			parts.append(int(x))
		m["participants"] = parts
		s.entries.append(m)
	return s
