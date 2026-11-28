class_name SettlementModule
extends SimModule
## Lager und Bauwerke (Prompt 6B; wird in Alpha 1.12 zur Siedlung ausgebaut): Bestand, Wahrnehmung
## durch Wesen, Speicherabschnitt.

var _radius: float = 10.0

func _init() -> void:
	id = "settlement"
	has_section = true
	title = "Lager und Bauwerke"
	depends_on = ["technology.perception"]
	per_actor = true
	load_order = 40


func tick(_dt: float, _zone: int) -> void:
	_radius = float(ctx.c("perception").get("radius_m", 10.0))


func actor_tick(cr: Creature, _dt: float) -> void:
	if ctx.perceived_actor_id != cr.id or (ctx.storages.is_empty() and ctx.structures.is_empty()):
		return
	var prad := _radius * float(cr.caps.get("perception", 1.0))
	StorageSystem.perceive(cr, ctx, prad)
	StructureSystem.perceive(cr, ctx, prad)


func save_section() -> Dictionary:
	var storages: Array = []
	for sid in SaveManager.sorted_keys(ctx.storages):
		storages.append(ctx.storages[sid].to_dict())
	var structures: Array = []
	for sid in SaveManager.sorted_keys(ctx.structures):
		structures.append(ctx.structures[sid].to_dict())
	return {"storages": storages, "structures": structures}


func load_section(d: Dictionary) -> Dictionary:
	for sd in d.get("storages", []):
		var sp := StoragePlace.from_dict(sd)
		if life.sim.add_entity(sp, "storage_place") < 0:
			return {"ok": false, "code": "invalid", "message": "Lager #%d: ID-Konflikt." % sp.id}
		ctx.storages[sp.id] = sp
	for std in d.get("structures", []):
		var stc := Structure.from_dict(std)
		if life.sim.add_entity(stc, "structure") < 0:
			return {"ok": false, "code": "invalid", "message": "Bauwerk #%d: ID-Konflikt." % stc.id}
		ctx.structures[stc.id] = stc
	return {"ok": true}


func audit() -> Array:
	return StorageSystem.audit(ctx) + StructureSystem.audit(ctx)


func metrics() -> Dictionary:
	return {"lager": ctx.storages.size(), "bauwerke": ctx.structures.size()}
