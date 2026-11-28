class_name ActorsModule
extends SimModule
## Akteure: Bestand der Wesen, Nachbarraster, Wegsuchbudget. Besitzt den Speicherabschnitt der Wesen
## (Körper, Stoffwechsel, Geist, praktisches Wissen – ein Wesen wird als Ganzes gespeichert).

func _init() -> void:
	id = "actors"
	has_section = true
	title = "Akteure (Wesen, Nachbarraster)"
	depends_on = ["time.sky"]
	load_order = 20
	after_load_order = 40


func tick(_dt: float, _zone: int) -> void:
	ctx.rebuild_spatial_hash()
	ctx.nav.begin_tick()
	for cid in ctx.creatures:
		ctx.creatures[cid].tick_moved_m = 0.0


func save_section() -> Dictionary:
	var creatures: Array = []
	for cid in SaveManager.sorted_keys(ctx.creatures):
		creatures.append(ctx.creatures[cid].to_dict())
	return {"creatures": creatures, "observation_stats": ctx.observation_stats.duplicate()}


func load_section(d: Dictionary) -> Dictionary:
	for cd in d.get("creatures", []):
		var cr_r := Creature.from_dict(cd, life.sim.materials)
		if not cr_r["ok"]:
			return {"ok": false, "code": "invalid", "message": "Wesen #%s: %s" % [str(cd.get("id", "?")), "; ".join(cr_r["errors"])]}
		var cr: Creature = cr_r["creature"]
		if life.sim.add_entity(cr, "creature") < 0:
			return {"ok": false, "code": "invalid", "message": "Wesen #%d: ID-Konflikt." % cr.id}
		ctx.creatures[cr.id] = cr
		var m_saved := cr.metabolism.to_dict()
		cr.refresh_body(ctx)
		# Kapazität ergibt sich aus der Körpermasse; Abweichung nur durch Rundung zulässig,
		# dann gelten die gespeicherten Werte (bitgenaue Wiederherstellung).
		if absf(cr.metabolism.energy_capacity_j - float(m_saved["energy_capacity_j"])) > 1e-6 * maxf(1.0, cr.metabolism.energy_capacity_j):
			return {"ok": false, "code": "invalid", "message": "Wesen #%d: Speicherkapazität passt nicht zur Körpermasse." % cr.id}
		cr.metabolism = Metabolism.from_dict(m_saved)
	for k in d.get("observation_stats", {}):
		ctx.observation_stats[k] = int(d["observation_stats"][k])
	return {"ok": true}


## Gehaltenes und Positionen technischer Gegenstände konsistent herstellen.
func after_load() -> Array:
	for cid in ctx.creatures:
		var crx: Creature = ctx.creatures[cid]
		if crx.held_object_id != 0 and ConstructionSystem.carrier_of(ctx, crx.held_object_id) != cid:
			crx.held_object_id = 0
	ConstructionSystem.sync_positions(ctx)
	return []


func metrics() -> Dictionary:
	var alive := 0
	for cid in ctx.creatures:
		if ctx.creatures[cid].alive:
			alive += 1
	return {"wesen": ctx.creatures.size(), "lebend": alive, "wegsuchen": int(ctx.nav.stats["requests"]), "wegknoten": int(ctx.nav.stats["expansions"])}
