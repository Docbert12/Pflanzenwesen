class_name CoreModule
extends SimModule
## Kern: Simulationszeit, Takte, ID-Vergabe, Zufallszustand der Simulation, Zufallsströme je Modul,
## Entwicklerschalter. Kein eigener Takt (die Uhr läuft in Simulation.step vor allen Modulen).

func _init() -> void:
	id = "core"
	has_section = true
	title = "Kern (Uhr, IDs, Zufall)"
	load_order = 0
	after_load_order = 0


func save_section() -> Dictionary:
	var sim: Simulation = life.sim
	return {"time_s": ctx.now(), "tick_count": sim.clock.tick_count, "registry_next_id": sim.registry.next_id(),
		"sim_rng": SaveManager.rng_to_dict(sim.rng), "dev_mode": ctx.dev_mode,
		"population_initial": int(sim.settings.get("initial_population", 50)), "rng_streams": ctx.rng_streams.to_dict()}


func load_section(d: Dictionary) -> Dictionary:
	var sim: Simulation = life.sim
	for k in ["time_s", "tick_count", "registry_next_id", "sim_rng"]:
		if not d.has(k):
			return {"ok": false, "code": "invalid", "message": "Abschnitt core: Feld %s fehlt." % k}
	sim.clock.sim_time_s = float(d["time_s"])
	sim.clock.tick_count = int(d["tick_count"])
	SaveManager.rng_from_dict(sim.rng, d["sim_rng"])
	ctx.dev_mode = bool(d.get("dev_mode", false))
	if d.has("rng_streams"):
		ctx.rng_streams.from_dict(d["rng_streams"])
	_next_id = int(d["registry_next_id"])
	return {"ok": true}


var _next_id: int = 0

func after_load() -> Array:
	life.sim.registry.ensure_next_id(_next_id)
	return []


func metrics() -> Dictionary:
	return {"entitaeten": life.sim.registry.count(), "ereignisse": life.sim.event_log.all_entries().size(),
		"zufallsstroeme": ctx.rng_streams.streams.size()}
