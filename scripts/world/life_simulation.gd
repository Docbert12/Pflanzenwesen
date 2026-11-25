class_name LifeSimulation
extends RefCounted
## Kern der Lebenssimulation (ohne Oberfläche). Wird von der Szene living_world.tscn und von den
## Tests gleichermaßen benutzt – es gibt keinen zweiten Simulationspfad.
##
## Ein Takt (fester Physikschritt, Standard 1/60 s), feste Reihenfolge:
##   1 Simulation.step (Uhr, Wärme/Phasen der Weltmassen) – bei Pause 0 → nichts weiter
##   2 Nachbarraster, Wegsuchbudget
##   3 ActionExecutor.step (Bewegung, Aufnehmen, Essen …)
##   4 je Wesen: Licht → Photosynthese, Stoffwechsel, Mangelschaden, Tod
##   5 je Wesen versetzt: Wahrnehmung (perception.interval_s), Entscheidung (behavior.decision_interval_s)
##   6 Testoption Nachfüllen (nur wenn sichtbar eingeschaltet)
## Prüfungen (audit) laufen auf Anforderung (Tests, Beobachtungsfenster), nicht jeden Takt.

var ctx := LifeContext.new()
var sim: Simulation
var db: DefinitionDB
var world: VoxelWorld
var world_cfg: Dictionary
var objects_root: Node3D
var world_object_ids: Array = []     # IDs der Massen von Baum und Pflanzen (Simulation.create_object)
var tree_info: Dictionary = {}
var tree_model: VoxelModel
var tree_node: Node3D
var plant_nodes: Dictionary = {}     # FoodSource-ID -> Node3D (nur Anzeige der Restmenge)
var base_cells := PackedByteArray()  # unverändertes Gelände direkt nach der Erzeugung
var base_hash: String = ""
var footprint: Dictionary = {}       # vom Baum belegte Terrainspalten
var stepping: bool = false           # true während eines Takts (kein Speichern mitten im Takt)
var food_rng := RandomNumberGenerator.new()
var next_refill_t: float = 0.0
var errors: Array = []
var game_ready: bool = false
var workshop: Dictionary = {}        # Testwerkstatt (Prompt 6): Rollen → IDs; leer im normalen Spiel
var perf := {"ticks": 0, "last_tick_us": 0, "sum_us": 0, "max_us": 0, "window": []}


## ai_service: anwendungsweite Ollama-Anbindung (LivingWorld: AIService.shared()). Ohne Angabe ist die
## Anbindung AUS – Tests und Werkzeuge laufen dann vollständig lokal und reproduzierbar.
func setup(p_sim: Simulation, p_db: DefinitionDB, p_world: VoxelWorld, p_objects_root: Node3D, ai_service: AIService = null) -> bool:
	sim = p_sim
	db = p_db
	world = p_world
	objects_root = p_objects_root
	errors.clear()
	ctx.sim = sim
	ctx.db = db
	ctx.world = world
	ctx.cfg = db.config("life")
	ctx.mind_cfg = db.config("mind")
	ctx.tech_cfg = db.config("technology")
	world_cfg = db.config("world")
	if ctx.cfg.is_empty():
		errors.append("data/config/life.json fehlt oder ist ungültig.")
	if ctx.mind_cfg.is_empty():
		errors.append("data/config/mind.json fehlt oder ist ungültig.")
	if world_cfg.is_empty():
		errors.append("data/config/world.json fehlt oder ist ungültig.")
	if ctx.tech_cfg.is_empty():
		errors.append("data/config/technology.json fehlt oder ist ungültig.")
	if not errors.is_empty():
		return false
	if world.data == null and world.palette.solid.is_empty():
		if not world.setup(sim, world_cfg, db.config("voxel_palette")):
			errors.append_array(world.errors)
			return false
	ctx.day_night = DayNightSystem.new()
	ctx.day_night.setup(ctx.cfg)
	ctx.ledger = ResourceLedger.new()
	ctx.ledger.digest_efficiency = float(ctx.c("metabolism").get("digest_efficiency", 0.8))
	ctx.executor = ActionExecutor.new(ctx)
	ctx.social = SocialInteractionSystem.new()
	ctx.interventions = InterventionSystem.new(ctx)
	ctx.comm = CommunicationSystem.new()
	ctx.ai = AISystem.new(ctx, ai_service)
	ctx.experiments = ExperimentSystem.new()
	ctx.work = WorkSystem.new()
	ctx.nav = NavigationService.new()
	return true


## Gelände, Baum, Pflanzen und Navigation aus dem Startwert aufbauen (für Neu UND Laden identisch).
func build_world(world_seed: int) -> void:
	world.generate(world_seed)
	base_cells = world.data.cells.duplicate()
	base_hash = world.data.hash_sha256()
	for c in objects_root.get_children():
		c.queue_free()
	var r := WorldObjects.spawn(objects_root, sim, db, world, world_cfg, extra_food_spots(world_seed))
	world_object_ids = r["entity_ids"]
	_plants_cache = r["plants"]
	plant_nodes.clear()
	tree_info = r["tree_info"]
	tree_model = r["tree_model"]
	tree_node = r["tree_node"]
	var cs := world.data.cell_size
	footprint = WorldObjects.tree_footprint(tree_model, tree_node.position, cs)
	ctx.nav.setup(world, ctx.cfg, footprint)
	ctx.shade_cols = WorldObjects.crown_shade(tree_model, tree_node.position, cs)
	if not world.terrain_changed.is_connected(_on_terrain_changed):
		world.terrain_changed.connect(_on_terrain_changed)
	tree_info["footprint_cols"] = footprint.size()
	tree_info["shade_cols"] = ctx.shade_cols.size()
	return


func _on_terrain_changed(cell: Vector3i) -> void:
	ctx.nav.on_terrain_changed(cell)


## Zusätzliche Nahrungsstandorte im Ring um den Baum (deterministisch aus dem Weltstartwert),
## damit der erste Beobachtungszeitraum genug erreichbare Nahrung hat.
func extra_food_spots(world_seed: int) -> Array:
	var fc: Dictionary = ctx.c("food")
	var want := int(fc.get("extra_sources", 20))
	var ring: Array = fc.get("extra_ring_m", [5.0, 13.0])
	var g: Dictionary = world.generated
	var tc: Vector3i = g["tree_cell"]
	var cs := world.data.cell_size
	var size := world.data.size
	var heights: PackedInt32Array = g["heights"]
	var grass := world.palette.id_of("grass")
	var used := {}
	for s in g["plant_spots"]:
		used[Vector2i(s["cell"].x, s["cell"].z)] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 9001
	var spots: Array = []
	var tries := 0
	while spots.size() < want and tries < want * 60:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(float(ring[0]), float(ring[1])) / cs
		var x := int(tc.x + cos(a) * r)
		var z := int(tc.z + sin(a) * r)
		if x < 1 or z < 1 or x >= size.x - 1 or z >= size.z - 1 or used.has(Vector2i(x, z)):
			continue
		var h := heights[x + size.x * z]
		if world.data.get_cell(x, h - 1, z) != grass:
			continue
		used[Vector2i(x, z)] = true
		var kind := "bush" if spots.size() % 3 != 2 else ("mushroom_red" if spots.size() % 2 == 0 else "mushroom_brown")
		spots.append({"cell": Vector3i(x, h, z), "kind": kind, "seed": rng.randi(), "extra_food": true})
	return spots


## Neues Spiel: Welt bauen, Nahrung anlegen, genau initial_population Wesen erzeugen.
func new_game(world_seed: int) -> Dictionary:
	build_world(world_seed)
	_create_food_sources(world_seed)
	var count := int(sim.settings.get("initial_population", 50))
	var center: Vector3 = tree_node.position
	var sr := PopulationSpawner.spawn(ctx, count, world_seed + int(ctx.c("population").get("seed_offset", 5000)), center)
	if not sr["ok"]:
		errors.append(sr["message"])
		return sr
	next_refill_t = ctx.now() + float(ctx.c("food").get("refill_interval_s", 60.0))
	game_ready = true
	ctx.log_event("new_game", [], {"seed": world_seed, "creatures": count, "food_sources": ctx.foods.size(), "food_kg": ctx.ledger.initial_kg})
	return sr


## Testwerkstatt (Prompt 6): eigene Welt mit 2 Testwesen und ausdrücklicher Testausrüstung.
func new_workshop(world_seed: int, behavior: bool = false) -> Dictionary:
	var r := TestWorkshop.setup(self, world_seed, behavior)
	if r.get("ok", false):
		ctx.log_event("new_game", [], {"seed": world_seed, "creatures": ctx.creatures.size(), "mode": "testwerkstatt"})
	else:
		errors.append(str(r.get("message", "")))
	return r


## Prompt 6B: Testszene „Werkzeugkette“ (ein Testwesen, Material, Lager, Baustelle, Testofen).
func new_work_scene(world_seed: int, behavior: bool = false) -> Dictionary:
	var r := WorkChainScene.setup(self, world_seed, behavior)
	if r.get("ok", false):
		ctx.log_event("new_game", [], {"seed": world_seed, "creatures": ctx.creatures.size(), "mode": "werkzeugkette"})
	else:
		errors.append(str(r.get("message", "")))
	return r


func _create_food_sources(world_seed: int) -> void:
	var fc: Dictionary = ctx.c("food")
	var kinds: Dictionary = fc.get("kinds", {})
	food_rng.seed = world_seed + 4242
	ctx.ledger.initial_kg = 0.0
	for pl in _plants_from_objects():
		var excel_plant: String = pl["excel_id"]
		if not kinds.has(excel_plant):
			continue
		var k: Dictionary = kinds[excel_plant]
		var food := db.get_def("food", str(k["excel_food_id"]))
		var f := FoodSource.new()
		f.kind = excel_plant
		f.food_id = str(k["excel_food_id"])
		f.display_name = "%s (%s)" % [str(food.get("name", f.food_id)), str(db.get_def("plants", excel_plant).get("name", excel_plant))]
		f.position = pl["position"]
		var rng_kg: Array = k.get("edible_kg", [0.6, 1.0])
		f.initial_kg = snappedf(food_rng.randf_range(float(rng_kg[0]), float(rng_kg[1])), 0.001)
		f.amount_kg = f.initial_kg
		f.energy_j_per_kg = float(food.get("nutrition", 10.0)) * float(fc.get("energy_j_per_kg_per_nutrition_point", 3000.0))
		f.nutrients_g_per_kg = (1.0 - float(food.get("water_content", 0.5))) * float(fc.get("nutrient_g_per_kg_dry_matter", 100.0))
		f.plant_seed = int(pl["spot"]["seed"])
		f.plant_kind = str(pl["kind"])
		sim.add_entity(f, "food_source")
		ctx.foods[f.id] = f
		plant_nodes[f.id] = pl["node"]
		ctx.ledger.initial_kg += f.initial_kg


var _plants_cache: Array = []

func _plants_from_objects() -> Array:
	return _plants_cache


## Bricht Referenzzyklen (LifeContext ↔ ActionExecutor) auf, damit nach Szenenwechsel bzw.
## erneutem Laden nichts im Speicher zurückbleibt.
func dispose() -> void:
	game_ready = false
	if world != null and is_instance_valid(world) and world.terrain_changed.is_connected(_on_terrain_changed):
		world.terrain_changed.disconnect(_on_terrain_changed)
	if ctx.executor != null:
		ctx.executor.running.clear()
		ctx.executor.reservations.clear()
		ctx.executor.history.clear()
		ctx.executor.ctx = null
	ctx.executor = null
	if ctx.interventions != null:
		ctx.interventions.ctx = null
	ctx.interventions = null
	if ctx.ai != null:
		ctx.ai.shutdown("Welt beendet (Neustart, Laden oder Verlassen)")
	ctx.ai = null
	ctx.creatures.clear()
	ctx.foods.clear()
	ctx.items.clear()
	ctx.material_pieces.clear()
	ctx.assemblies.clear()
	ctx.heaters.clear()
	ctx.storages.clear()
	ctx.structures.clear()
	workshop = {}
	ctx.experiments = null
	ctx.work = null
	ctx._hash.clear()
	plant_nodes.clear()
	_plants_cache = []


# ── Takt ──────────────────────────────────────────

func step(dt: float) -> void:
	if not game_ready:
		return
	var t0 := Time.get_ticks_usec()
	var sdt := sim.step(dt)
	if sdt <= 0.0:
		if ctx.ai != null:
			ctx.ai.update(true)      # Pause: nur Netzwerk, keine neuen Anfragen, nichts anwenden
		return
	stepping = true
	ctx.rebuild_spatial_hash()
	ctx.nav.begin_tick()
	var ids := ctx.creatures.keys()
	ids.sort()
	for id in ids:
		ctx.creatures[id].tick_moved_m = 0.0
	ctx.executor.step(sdt)
	ToolUseSystem.tick(ctx, sdt)
	var now := ctx.now()
	var light := ctx.day_night.light(now)
	var mcfg: Dictionary = ctx.c("metabolism")
	var pi := float(ctx.c("perception").get("interval_s", 1.0))
	var di := float(ctx.c("behavior").get("decision_interval_s", 0.5))
	for id in ids:
		var cr: Creature = ctx.creatures[id]
		if not cr.alive:
			continue
		var shade := Photosynthesis.shade_at(ctx, cr.position)
		var lw := Photosynthesis.power_w(float(cr.caps.get("leaf_area_m2", 0.0)), light, shade, ctx.cfg)
		var aw := 0.0
		if ctx.executor.running.has(id):
			var a: GameAction = ctx.executor.running[id]
			aw = (ctx.executor.impls[a.type] as ActionImpl).power_w(a, ctx)
		var res := cr.metabolism.step(sdt, cr.mass_kg, int(cr.caps.get("leaf_count", 0)), cr.tick_moved_m, aw, lw, ctx.cfg)
		cr.stats["light_j"] = float(cr.stats.get("light_j", 0.0)) + lw * sdt
		if res["energy_empty"]:
			cr.health.starvation = minf(1.0, cr.health.starvation + float(mcfg.get("starvation_damage_per_s", 0.004)) * sdt)
		if res["nutrients_empty"]:
			cr.health.starvation = minf(1.0, cr.health.starvation + float(mcfg.get("nutrient_starvation_damage_per_s", 0.002)) * sdt)
		if cr.health.is_dead():
			var cause := "Verhungert (Energie leer)" if cr.metabolism.energy_j <= 0.0 else "Mangel an Nährstoffen"
			if cr.health.starvation < 1.0:
				cause = "Lebenswichtiges Körperteil zerstört"
			cr.die(cause, ctx)
			continue
		if now >= cr.next_perception_t:
			Perception.scan(cr, ctx)
			ClaimEvaluator.on_perception(cr, ctx)
			LearningSystem.tick(cr, ctx)
			ExperimentSystem.perceive_objects(cr, ctx)
			if not ctx.storages.is_empty() or not ctx.structures.is_empty():
				var prad := float(ctx.c("perception").get("radius_m", 10.0)) * float(cr.caps.get("perception", 1.0))
				StorageSystem.perceive(cr, ctx, prad)
				StructureSystem.perceive(cr, ctx, prad)
			cr.next_perception_t = now + pi
		if cr.behavior_enabled and now >= cr.next_decision_t:
			cr.next_decision_t = now + di
			DecisionSystem.decide(cr, ctx)
	ctx.social.tick(now, float(ctx.m("social").get("request_expire_s", 10.0)))
	ctx.interventions.tick()
	ctx.experiments.tick(ctx)
	ctx.work.tick(ctx)
	ctx.ai.update(false)
	if ctx.refill_enabled and now >= next_refill_t:
		refill_test(float(ctx.c("food").get("test_refill_kg", 0.5)))
		next_refill_t = now + float(ctx.c("food").get("refill_interval_s", 60.0))
	stepping = false
	var us := Time.get_ticks_usec() - t0
	perf["ticks"] += 1
	perf["last_tick_us"] = us
	perf["sum_us"] += us
	perf["max_us"] = maxi(int(perf["max_us"]), us)
	var win: Array = perf["window"]
	win.append(us)
	if win.size() > 120:
		win.pop_front()


## Testoption (nur sichtbar per Schalter): füllt jede Quelle bis höchstens zur Startmenge auf.
func refill_test(kg: float) -> float:
	var total := 0.0
	for fid in ctx.foods:
		var f: FoodSource = ctx.foods[fid]
		var add := minf(kg, f.initial_kg - f.amount_kg)
		if add > 0.0:
			f.amount_kg += add
			f.refilled_kg += add
			total += add
	ctx.ledger.refill_kg += total
	ctx.log_event("test_refill", [], {"kg": total, "note": "TESTOPTION – im normalen Spiel aus"}, "warning")
	return total


# ── Zusammenfassungen und Prüfungen ───────────────

func population_summary() -> Dictionary:
	var alive := 0
	var dead := 0
	var hunger := 0.0
	var states := {}
	for id in ctx.creatures:
		var cr: Creature = ctx.creatures[id]
		if cr.alive:
			alive += 1
			hunger += cr.metabolism.hunger()
			states[cr.behavior_state] = int(states.get(cr.behavior_state, 0)) + 1
		else:
			dead += 1
	var food := 0.0
	var food_free := 0.0
	var nonempty := 0
	for fid in ctx.foods:
		var f: FoodSource = ctx.foods[fid]
		food += f.amount_kg
		food_free += f.available_kg()
		if f.amount_kg > 1e-6:
			nonempty += 1
	var ground_items := 0
	for iid in ctx.items:
		if ctx.items[iid].carrier_id == 0:
			ground_items += 1
	return {"alive": alive, "dead": dead, "avg_hunger": hunger / maxf(alive, 1), "states": states, "food_kg": food, "food_free_kg": food_free,
		"food_sources": ctx.foods.size(), "food_sources_nonempty": nonempty, "items": ctx.items.size(), "ground_items": ground_items,
		"time_s": ctx.now(), "clock": ctx.day_night.clock_text(ctx.now()), "phase": ctx.day_night.phase_name(ctx.now()),
		"light": ctx.day_night.light(ctx.now()), "running_actions": ctx.executor.running.size(), "reservations": ctx.executor.reservations.size()}


## Vollständige Konsistenzprüfung. Leere Liste = in Ordnung.
func audit() -> Array:
	var p: Array = ctx.executor.audit()
	var err := ctx.ledger.balance_error(ctx)
	if absf(err) > 1e-6:
		p.append("Nahrungsbilanz weicht um %.3e kg ab" % err)
	for id in ctx.creatures:
		var cr: Creature = ctx.creatures[id]
		var eb := cr.metabolism.energy_balance_error()
		if absf(eb) > 1e-3 * maxf(1.0, cr.metabolism.energy_capacity_j):
			p.append("Wesen #%d: Energiebilanz weicht um %.4f J ab" % [id, eb])
		if cr.metabolism.energy_j < -1e-9 or cr.metabolism.nutrients_g < -1e-9:
			p.append("Wesen #%d: negativer Speicher" % id)
		if not is_finite(cr.position.x) or not is_finite(cr.position.y) or not is_finite(cr.position.z):
			p.append("Wesen #%d: ungültige Position" % id)
		if cr.carried_item_id != 0:
			if not ctx.items.has(cr.carried_item_id):
				p.append("Wesen #%d trägt fehlenden Gegenstand #%d" % [id, cr.carried_item_id])
			elif ctx.items[cr.carried_item_id].carrier_id != id:
				p.append("Wesen #%d: Trägerverweis inkonsistent" % id)
			if not cr.alive:
				p.append("Totes Wesen #%d trägt noch etwas" % id)
		if not sim.registry.has_id(id):
			p.append("Wesen #%d nicht registriert" % id)
		for q in cr.memory.audit() + cr.beliefs.audit():
			p.append("Wesen #%d: %s" % [id, q])
		if cr.memory.entries.size() > int(ctx.m("memory").get("capacity", 64)) or cr.beliefs.items.size() > int(ctx.m("beliefs").get("capacity", 32)) + 1 \
				or cr.relations.rel.size() > int(ctx.m("relationships").get("capacity", 24)):
			p.append("Wesen #%d: Geistesspeicher über Kapazität" % id)
	p.append_array(ConstructionSystem.audit(ctx))
	p.append_array(StorageSystem.audit(ctx))
	p.append_array(StructureSystem.audit(ctx))
	if ctx.work != null:
		p.append_array(ctx.work.audit(ctx))
	for iid in ctx.items:
		var it: FoodItem = ctx.items[iid]
		if it.reserved_by != 0 and not ctx.executor.reservations.has(it.reserved_by):
			p.append("Gegenstand #%d: Reservierung %d ohne Besitzer" % [iid, it.reserved_by])
		if it.mass_kg < -1e-12:
			p.append("Gegenstand #%d: negative Masse" % iid)
		if it.carrier_id != 0:
			var c := ctx.creature(it.carrier_id)
			if c == null or c.carried_item_id != iid:
				p.append("Gegenstand #%d: Träger #%d hält ihn nicht" % [iid, it.carrier_id])
	return p


# ── Entwicklermodus (Testeingriffe, klar gekennzeichnet) ──────

func dev_body_change(id: int, op: String, side: String = "r", material_id: String = "wood") -> Dictionary:
	var cr := ctx.creature(id)
	if cr == null:
		return {"ok": false, "message": "Kein Wesen #%d." % id}
	if not cr.alive:
		return {"ok": false, "message": "Wesen #%d ist tot." % id}
	var r: Dictionary
	match op:
		"remove_forearm":
			r = cr.plan.remove_forearm(side)
			if r.get("ok", false):
				ctx.publish({"type": "injury_visible", "actor": 0, "target": cr.id, "position": cr.position,
					"consequences": {"sichtbar": "Unterarm fehlt", "ursache_sichtbar": false}}, "warning")
		"attach_prosthesis":
			r = cr.plan.attach_prosthesis(side, material_id, sim.materials)
		"injure_leg":
			var pid := "leg_%s_upper" % side if cr.plan.is_present("leg_%s_lower" % side) == false else "leg_%s_lower" % side
			if not cr.plan.is_present(pid):
				return {"ok": false, "message": "Bein %s nicht vorhanden." % side}
			r = cr.health.damage_part(cr.plan, pid, float(ctx.c("health").get("leg_injury_damage", 0.6)), "Entwicklermodus", ctx.now())
			if r.get("ok", false):
				ctx.publish({"type": "injury_visible", "actor": 0, "target": cr.id, "position": cr.position,
					"consequences": {"teil": pid, "sichtbar": "verletztes Bein", "ursache_sichtbar": false}}, "warning")
				r["message"] = "%s Schaden jetzt %.0f %%%s" % [pid, float(r["damage"]) * 100, " – Teil verloren" if not r["removed"].is_empty() else ""]
		"remove_leaf":
			r = cr.plan.remove_leaf()
		"add_leaf":
			r = cr.plan.add_leaf()
		"kill":
			cr.die("Entwicklermodus: getötet", ctx)
			return {"ok": true, "message": "Wesen #%d getötet (Testeingriff)." % id}
		_:
			return {"ok": false, "message": "Unbekannter Eingriff '%s'." % op}
	if not r.get("ok", false):
		return r
	after_body_change(cr, "Entwicklermodus: %s %s" % [op, side])
	ctx.log_event("dev_body_change", [id], {"op": op, "side": side, "material": material_id, "result": str(r.get("message", r.get("id", "")))}, "warning")
	if not r.has("message"):
		r["message"] = "%s ausgeführt." % op
	return r


## Nach jeder Körperänderung: Fähigkeiten/Masse neu, laufende Handlung prüfen, ggf. Gegenstand ablegen.
func after_body_change(cr: Creature, reason: String) -> void:
	cr.refresh_body(ctx)
	if cr.carried_item_id != 0 and float(cr.caps.get("grasp", 0.0)) <= 0.0:
		if ctx.executor.running.has(cr.id):
			ctx.executor.cancel(cr.id, "body_changed", "Körperänderung: " + reason)
		var it: FoodItem = ctx.items.get(cr.carried_item_id, null)
		if it != null:
			it.carrier_id = 0
			it.position = cr.position + Vector3(0, 0.05, 0)
			ctx.log_event("item_dropped", [cr.id, it.id], {"reason": "Greiffähigkeit verloren"}, "warning")
		cr.carried_item_id = 0
	if cr.held_object_id != 0:
		# Prompt 6B: auch die haltende Seite bzw. die zweite Hand beim Tragen mit beiden Händen prüfen
		var gs: Dictionary = cr.caps.get("grasp_by_side", {})
		var lost := float(cr.caps.get("grasp", 0.0)) <= 0.0
		if cr.hold_mode == "two" and ToolUseSystem.grasp_hands(cr) < 2:
			lost = true
		elif cr.hold_mode != "two" and cr.hold_side != "" and float(gs.get(cr.hold_side, 0.0)) <= 0.0:
			lost = true
		if lost:
			if ctx.executor.running.has(cr.id):
				ctx.executor.cancel(cr.id, "body_changed", "Körperänderung: " + reason)
			ToolUseSystem.release(ctx, cr, "Greiffähigkeit verloren")
	if ctx.executor.running.has(cr.id):
		var a: GameAction = ctx.executor.running[cr.id]
		var v := ctx.executor.validator.check_capabilities(a, cr)
		if not v.ok:
			ctx.executor.cancel(cr.id, "body_changed", v.message)
	if not cr.caps.get("can_walk", false):
		cr.behavior_reason = "Gehen nicht möglich: " + str(cr.caps.get("walk_reason", ""))
