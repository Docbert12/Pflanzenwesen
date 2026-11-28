class_name RngStreams
extends RefCounted
## Zufallsströme je Modul (Alpha 1.1): jeder Strom entsteht aus (Weltstartwert, Strom-ID) und ist von
## allen anderen unabhängig. Ein neues Modul verschiebt deshalb die Abläufe der vorhandenen nicht.
## Die Ströme der Systeme bis v0.6.1 (Simulation.rng, Nahrung, je Wesen) bleiben unverändert bestehen;
## neue Module holen ihren Strom ausschließlich hier.

var world_seed: int = 0
var streams: Dictionary = {}     # id -> RandomNumberGenerator


func reset(p_seed: int) -> void:
	world_seed = p_seed
	streams.clear()


## Startwert eines Stroms: SHA-256 über "Startwert|ID", erste 8 Byte (vorzeichenbehaftet, stabil auf allen Plattformen).
static func seed_for(p_seed: int, id: String) -> int:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(("%d|%s" % [p_seed, id]).to_utf8_buffer())
	var b := h.finish()
	var v := 0
	for i in 8:
		v = (v << 8) | int(b[i])
	return v


func stream(id: String) -> RandomNumberGenerator:
	if not streams.has(id):
		var r := RandomNumberGenerator.new()
		r.seed = seed_for(world_seed, id)
		streams[id] = r
	return streams[id]


func to_dict() -> Dictionary:
	var d := {}
	var keys := streams.keys()
	keys.sort()
	for k in keys:
		var r: RandomNumberGenerator = streams[k]
		d[k] = {"seed": str(r.seed), "state": str(r.state)}
	return {"world_seed": str(world_seed), "streams": d}


func from_dict(d: Dictionary) -> void:
	world_seed = int(str(d.get("world_seed", "0")))
	streams.clear()
	var s: Dictionary = d.get("streams", {})
	for k in s:
		var r := RandomNumberGenerator.new()
		r.seed = int(str(s[k].get("seed", "0")))
		r.state = int(str(s[k].get("state", "0")))
		streams[str(k)] = r
