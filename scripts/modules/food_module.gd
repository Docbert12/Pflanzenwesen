class_name FoodModule
extends SimModule
## Ökologie, Teil Nahrung: Nahrungsquellen, Portionen, Nahrungsbilanz, sichtbare Testoption „Nachfüllen“.
## Wird in Alpha 1.5 zum Pflanzenmodul ausgebaut.

func _init() -> void:
	id = "ecology.food"
	has_section = true
	title = "Ökologie: Nahrung"
	depends_on = ["communication"]
	load_order = 10


func tick(_dt: float, _zone: int) -> void:
	var now := ctx.now()
	if ctx.refill_enabled and now >= life.next_refill_t:
		life.refill_test(float(ctx.c("food").get("test_refill_kg", 0.5)))
		life.next_refill_t = now + float(ctx.c("food").get("refill_interval_s", 60.0))


func save_section() -> Dictionary:
	var foods: Array = []
	for fid in SaveManager.sorted_keys(ctx.foods):
		foods.append(ctx.foods[fid].to_dict())
	var items: Array = []
	for iid in SaveManager.sorted_keys(ctx.items):
		items.append(ctx.items[iid].to_dict())
	return {"foods": foods, "items": items, "ledger": ctx.ledger.to_dict(), "food_rng": SaveManager.rng_to_dict(life.food_rng),
		"next_refill_t": life.next_refill_t, "refill_enabled": ctx.refill_enabled}


func load_section(d: Dictionary) -> Dictionary:
	SaveManager.rng_from_dict(life.food_rng, d.get("food_rng", {}))
	life.next_refill_t = float(d.get("next_refill_t", 0.0))
	ctx.refill_enabled = bool(d.get("refill_enabled", false))
	var by_seed := {}
	for pl in life._plants_from_objects():
		by_seed[int(pl["spot"]["seed"])] = pl["node"]
	for fd in d.get("foods", []):
		if typeof(fd) != TYPE_DICTIONARY or float(fd.get("amount_kg", -1.0)) < 0.0:
			return {"ok": false, "code": "invalid", "message": "Ungültiger Nahrungseintrag (Menge negativ oder fehlend)."}
		var f := FoodSource.from_dict(fd)
		if life.sim.add_entity(f, "food_source") < 0:
			return {"ok": false, "code": "invalid", "message": "Nahrungsquelle #%d: ID-Konflikt." % f.id}
		ctx.foods[f.id] = f
		if by_seed.has(f.plant_seed):
			life.plant_nodes[f.id] = by_seed[f.plant_seed]
	for idd in d.get("items", []):
		var it := FoodItem.from_dict(idd)
		it.reserved_by = 0                       # Reservierungen werden beim Laden freigegeben
		if life.sim.add_entity(it, "food_item") < 0:
			return {"ok": false, "code": "invalid", "message": "Gegenstand #%d: ID-Konflikt." % it.id}
		ctx.items[it.id] = it
	ctx.ledger = ResourceLedger.from_dict(d.get("ledger", {}))
	return {"ok": true}


func metrics() -> Dictionary:
	var kg := 0.0
	for fid in ctx.foods:
		kg += ctx.foods[fid].amount_kg
	return {"quellen": ctx.foods.size(), "nahrung_kg": kg, "portionen": ctx.items.size()}
