class_name TestLife
extends RefCounted
## Prüfungen der Lebenssimulation (Prompt 3). Laufen ohne Grafik auf denselben Klassen wie das Spiel.
## Nummern in Klammern verweisen auf die Prüfliste des Auftrags (Abschnitt 13).

const DT := 1.0 / 60.0
const TEST_SAVE := "user://saves/_test_spielstand.json"

var results: Array = []
var notes: Array = []
var long_run_s: float = 600.0
var _free: Array = []
var _lives: Array = []
var db: DefinitionDB


func run_all(p_long_run_s: float = 600.0) -> Array:
	long_run_s = p_long_run_s
	results.clear()
	notes.clear()
	db = DefinitionDB.new()
	db.load_all()
	_test_single_creature()
	_test_new_game_population()
	_test_food_and_reservations()
	_test_photosynthesis_and_darkness()
	_test_body_changes()
	_test_interrupts_release()
	_test_navigation_blocked()
	_test_death()
	_test_pause()
	_test_save_load()
	_test_corrupt_saves()
	if long_run_s > 0.0:
		_test_long_run()
	_cleanup()
	return results


func _check(name: String, cond: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": cond, "detail": detail})


## Frische Umgebung (eigene Simulation, Welt, Lebenssimulation).
func _env() -> LifeSimulation:
	var sim := Simulation.new()
	sim.initialize()
	sim.set_physics_process(false)
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	_free.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs)
	_lives.append(life)
	return life


func _seed() -> int:
	return int(db.config("world").get("seed", 12345))


func _cleanup() -> void:
	for l in _lives:
		l.dispose()
	_lives.clear()
	for o in _free:
		if is_instance_valid(o):
			o.free()
	_free.clear()


func _run(life: LifeSimulation, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		life.step(DT)


## Welt + Nahrung, aber nur n Wesen (für Einzeltests).
func _env_small(n: int) -> LifeSimulation:
	var life := _env()
	life.build_world(_seed())
	life._create_food_sources(_seed())
	var r := PopulationSpawner.spawn(life.ctx, n, 777, life.tree_node.position)
	if r["ok"]:
		life.game_ready = true
	return life


func _nearest_food(life: LifeSimulation, pos: Vector3) -> FoodSource:
	var best: FoodSource = null
	var bd := INF
	for fid in life.ctx.foods:
		var f: FoodSource = life.ctx.foods[fid]
		var d := life.ctx.distance_xz(pos, f.position)
		if d < bd:
			bd = d
			best = f
	return best


## Wesen neben eine Quelle stellen (begehbare Spalte in Reichweite).
func _place_near(life: LifeSimulation, cr: Creature, f: FoodSource) -> bool:
	var nav := life.ctx.nav
	for r in [0.6, 0.8, 0.9, 1.0]:
		for k in 16:
			var a := k * TAU / 16.0
			var p := f.position + Vector3(cos(a) * r, 0, sin(a) * r)
			var c := nav.world_to_col(p)
			if nav.in_bounds(c) and nav.is_walkable(c):
				cr.position = Vector3(p.x, nav.ground_y(c), p.z)
				return true
	return false


func _set_hunger(cr: Creature, hunger: float) -> void:
	# Nur für Tests: Zustand direkt setzen und die Bilanz-Startwerte gleichziehen.
	var m := cr.metabolism
	var e := m.energy_capacity_j * (1.0 - hunger)
	m.start_energy_j += e - m.energy_j
	m.energy_j = e
	m.start_nutrients_g += m.nutrient_capacity_g * (1.0 - hunger) - m.nutrients_g
	m.nutrients_g = m.nutrient_capacity_g * (1.0 - hunger)


# ── Einzelwesen vollständig ───────────────────────

func _test_single_creature() -> void:
	var life := _env_small(1)
	var ctx := life.ctx
	_check("Einzelwesen: genau 1 Wesen erzeugt", ctx.creatures.size() == 1 and life.game_ready)
	var cr: Creature = ctx.creatures.values()[0]
	var f := _nearest_food(life, cr.position)
	# Wahrnehmung: Quelle in Reichweite wird gesehen, eine ferne nicht
	_place_near(life, cr, f)
	Perception.scan(cr, ctx)
	var far_known := false
	var radius := float(ctx.c("perception")["radius_m"])
	for fid in cr.food_memory:
		if fid in ctx.foods and ctx.distance_xz(cr.position, ctx.foods[fid].position) > radius + 0.8:
			far_known = true
	_check("Einzelwesen: nahe Nahrung wahrgenommen, keine jenseits der Reichweite", cr.food_memory.has(f.id) and not far_known,
		"bekannt %d von %d Quellen" % [cr.food_memory.size(), ctx.foods.size()])
	# Bewegung: zu einem 4 m entfernten begehbaren Punkt gehen
	var start := cr.position
	var target := start
	for k in 16:
		var a := k * TAU / 16.0
		var p := start + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0)
		var c := ctx.nav.world_to_col(p)
		if ctx.nav.in_bounds(c) and ctx.nav.is_walkable(c) and ctx.nav.find_path(ctx.nav.world_to_col(start), c)["ok"]:
			target = Vector3(p.x, ctx.nav.ground_y(c), p.z)
			break
	cr.behavior_enabled = false   # Verhalten aus, Handlungen direkt
	var mr := ctx.executor.request(cr.id, "move_to", 0, target)
	var e0: float = cr.metabolism.totals["move_j"]
	var walked := false
	for i in 900:
		life.step(DT)
		if not ctx.executor.running.has(cr.id):
			walked = true
			break
	_check("Einzelwesen: move_to erreicht Ziel über Wegsuche", mr["result"].ok and walked and ctx.distance_xz(cr.position, target) <= 0.2 and cr.last_result.get("status") == "succeeded",
		"Abstand %.2f m, Ergebnis %s" % [ctx.distance_xz(cr.position, target), str(cr.last_result.get("code"))])
	_check("Einzelwesen: Bewegung kostet Energie (Stoffwechsel)", cr.metabolism.totals["move_j"] > e0, "%.1f J" % (cr.metabolism.totals["move_j"] - e0))
	var gy := ctx.nav.ground_y(ctx.nav.world_to_col(cr.position))
	_check("Einzelwesen: steht auf dem Boden (keine Animation verschiebt Position)", absf(cr.position.y - gy) < 0.05, "y %.3f, Boden %.3f" % [cr.position.y, gy])
	# Nahrung aufnehmen und essen über das Verhalten
	_place_near(life, cr, f)
	_set_hunger(cr, 0.7)
	cr.behavior_enabled = true
	cr.next_decision_t = ctx.now()
	cr.next_perception_t = ctx.now()
	var amount0 := f.amount_kg
	var e_food0: float = cr.metabolism.totals["food_energy_j"]
	var picked := false
	var ate := false
	for i in 60 * 40:
		life.step(DT)
		if cr.carried_item_id != 0:
			picked = true
		if cr.metabolism.totals["eaten_kg"] > 0.0 and cr.carried_item_id == 0 and picked:
			ate = true
			break
	_check("Einzelwesen: nimmt Nahrung auf (getragener Gegenstand) und isst sie", picked and ate, "Zustand %s – %s" % [cr.behavior_state, cr.behavior_reason])
	_check("(3) Nahrungsaufnahme verringert die tatsächliche Menge der Quelle", f.amount_kg < amount0 - 1e-9 and absf(ctx.ledger.balance_error(ctx)) < 1e-9,
		"%.3f → %.3f kg; Bilanzfehler %s" % [amount0, f.amount_kg, TestSuite.sci(ctx.ledger.balance_error(ctx))])
	_check("Einzelwesen: Essen erhöht Energie (Nahrungsenergie gebucht, Bilanz geschlossen)", cr.metabolism.totals["food_energy_j"] > e_food0 and absf(cr.metabolism.energy_balance_error()) < 1e-6,
		"+%.0f J, Bilanzfehler %s J" % [cr.metabolism.totals["food_energy_j"] - e_food0, TestSuite.sci(cr.metabolism.energy_balance_error())])
	_check("Einzelwesen: Abfall bilanziert (gegessen = assimiliert + Abfall)", absf(ctx.ledger.eaten_kg - ctx.ledger.assimilated_kg - ctx.ledger.waste_kg) < 1e-12 and ctx.ledger.waste_kg > 0.0)
	# Verletzung: Bein → langsamer
	cr.behavior_enabled = false
	ctx.executor.cancel(cr.id, "test", "Test")
	var v0 := cr.speed_m_s(ctx)
	var r := life.dev_body_change(cr.id, "injure_leg", "l")
	var v1 := cr.speed_m_s(ctx)
	_check("Einzelwesen: Beinverletzung senkt Geschwindigkeit (aus Körperzustand)", r["ok"] and v1 < v0 and v1 > 0.0, "%.2f → %.2f m/s" % [v0, v1])
	life.dev_body_change(cr.id, "injure_leg", "l")
	_check("Einzelwesen: zweite Beinverletzung → Teil verloren, Gehen nachvollziehbar gestoppt", not cr.caps["can_walk"] and cr.speed_m_s(ctx) == 0.0 and str(cr.caps["walk_reason"]) != "",
		str(cr.caps["walk_reason"]))
	var mv := ctx.executor.request(cr.id, "move_to", 0, target)
	_check("Einzelwesen: move_to ohne Gehfähigkeit abgewiesen (erklärt)", not mv["result"].ok and mv["result"].code == "cannot_walk", mv["result"].message)
	# Tod durch Mangel
	_set_hunger(cr, 1.0)
	cr.health.starvation = 0.995
	for i in 120:
		life.step(DT)
	_check("Einzelwesen: stirbt bei anhaltendem Mangel, Körper bleibt erhalten", not cr.alive and ctx.creatures.has(cr.id) and life.sim.registry.has_id(cr.id) and str(cr.death.get("cause", "")) != "",
		str(cr.death.get("cause", "")))


# ── (1)(2) Neues Spiel ─────────────────────────────

func _test_new_game_population() -> void:
	var life := _env()
	var r := life.new_game(_seed())
	var ctx := life.ctx
	var ids := ctx.creatures.keys()
	var uniq := {}
	for id in ids:
		uniq[id] = true
	var registered := true
	for id in ids:
		if not life.sim.registry.has_id(id) or life.sim.registry.get_entity(id) != ctx.creatures[id]:
			registered = false
	_check("(1) Neues Spiel erzeugt genau 50 eindeutige, registrierte Wesen", r["ok"] and ids.size() == 50 and uniq.size() == 50 and registered and int(life.sim.settings["initial_population"]) == 50,
		"%d Wesen, %d Versuche, Ablehnungen %s" % [ids.size(), r.get("attempts", 0), str(r.get("rejected", {}))])
	var bad: Array = []
	var spacing := float(ctx.c("population")["min_spacing_m"])
	var crs: Array = ctx.creatures.values()
	for i in crs.size():
		var c: Creature = crs[i]
		var col := ctx.nav.world_to_col(c.position)
		if not ctx.nav.is_walkable(col):
			bad.append("#%d nicht begehbar (%s)" % [c.id, ctx.nav.why_not_walkable(col)])
		if absf(c.position.y - ctx.nav.ground_y(col)) > 1e-6:
			bad.append("#%d nicht auf Boden" % c.id)
		if life.footprint.has(col):
			bad.append("#%d im Baum" % c.id)
		if ctx.nav.water_depth(col) > 0.0:
			bad.append("#%d im Wasser" % c.id)
		var vc := life.world.data.world_to_cell(c.position + Vector3(0, 0.1, 0))
		if life.world.palette.solid[life.world.data.get_cell(vc.x, vc.y, vc.z)] == 1:
			bad.append("#%d steckt im Gelände" % c.id)
		for j in range(i + 1, crs.size()):
			if ctx.distance_xz(c.position, crs[j].position) < spacing - 1e-9:
				bad.append("#%d/#%d zu nah" % [c.id, crs[j].id])
	_check("(2) Startpositionen gültig: begehbar, auf Boden, nicht im Baum/Gelände/Wasser, Mindestabstand", bad.is_empty(), ", ".join(bad.slice(0, 5)))
	var seeds := {}
	for c in crs:
		seeds[JSON.stringify(c.plan.to_dict())] = true
	var life2 := _env()
	life2.new_game(_seed())
	var same := true
	var ids2 := life2.ctx.creatures.keys()
	ids2.sort()
	ids.sort()
	for i in ids.size():
		if JSON.stringify(ctx.creatures[ids[i]].plan.to_dict()) != JSON.stringify(life2.ctx.creatures[ids2[i]].plan.to_dict()) or not ctx.creatures[ids[i]].position.is_equal_approx(life2.ctx.creatures[ids2[i]].position):
			same = false
	_check("Körpervarianten und Positionen reproduzierbar (gleicher Startwert)", same and seeds.size() > 40, "%d verschiedene Körperpläne" % seeds.size())
	var leaves_ok := true
	for c in crs:
		var n: int = c.plan.leaf_ids().size()
		if n < 1 or n > 3:
			leaves_ok = false
	_check("Jedes Wesen hat 1–3 Blätter", leaves_ok)
	_check("Nahrung: endliche Quellen aus Excel N001/N002 mit Menge > 0", ctx.foods.size() >= 20 and ctx.ledger.initial_kg > 10.0,
		"%d Quellen, %.1f kg" % [ctx.foods.size(), ctx.ledger.initial_kg])
	notes.append("Neues Spiel: %d Wesen, %d Nahrungsquellen (%.1f kg), Baum belegt %d Spalten, Schatten %d Spalten" % [ids.size(), ctx.foods.size(), ctx.ledger.initial_kg, life.footprint.size(), ctx.shade_cols.size()])


# ── (3)(4) Nahrung und Reservierungen ─────────────

func _test_food_and_reservations() -> void:
	var life := _env_small(2)
	var ctx := life.ctx
	var cs: Array = ctx.creatures.values()
	var a: Creature = cs[0]
	var b: Creature = cs[1]
	a.behavior_enabled = false
	b.behavior_enabled = false
	var f := _nearest_food(life, a.position)
	_place_near(life, a, f)
	_place_near(life, b, f)
	b.position += Vector3(0.01, 0, 0)
	# Restmenge genau ein Bissen
	var bite := float(ctx.c("food")["bite_kg"])
	ctx.ledger.initial_kg += bite - f.amount_kg
	f.initial_kg = bite
	f.amount_kg = bite
	var ra := ctx.executor.request(a.id, "pick_up", f.id)
	var rb := ctx.executor.request(b.id, "pick_up", f.id)
	_check("(4) Zwei Wesen: zweite Aufnahme derselben Restmenge abgewiesen", ra["result"].ok and not rb["result"].ok and rb["result"].code == "unavailable", rb["result"].message)
	var res_direct := ctx.executor.reserve(b.id, 999, f.id, 0.01)
	_check("(4) Reservierung über verfügbare Menge hinaus nicht möglich", res_direct == 0 and f.available_kg() <= 1e-12)
	_run(life, 3.0)
	_check("(4) Erste Aufnahme erfolgreich, Quelle leer, nichts doppelt verbraucht", a.carried_item_id != 0 and f.amount_kg <= 1e-12 and absf(ctx.items[a.carried_item_id].mass_kg - bite) < 1e-12 and absf(ctx.ledger.balance_error(ctx)) < 1e-12,
		"Quelle %.4f kg, getragen %.4f kg" % [f.amount_kg, ctx.items[a.carried_item_id].mass_kg if a.carried_item_id != 0 else -1.0])
	var rb2 := ctx.executor.request(b.id, "pick_up", f.id)
	_check("(4) Leere Quelle: Aufnahme mit Begründung abgewiesen", not rb2["result"].ok and rb2["result"].code == "unavailable", rb2["result"].message)
	# Essen aus großer Entfernung verhindert
	var g: FoodSource = null
	for fid in ctx.foods:
		if ctx.distance_xz(b.position, ctx.foods[fid].position) > 3.0 and ctx.foods[fid].amount_kg > 0.1:
			g = ctx.foods[fid]
			break
	var rf := ctx.executor.request(b.id, "pick_up", g.id)
	_check("Kein Aufnehmen/Essen aus beliebiger Entfernung", not rf["result"].ok and rf["result"].code == "out_of_reach", rf["result"].message)
	# Essen unterbrechen: bereits Gegessenes bleibt bilanziert, Rest bleibt im Gegenstand
	var re := ctx.executor.request(a.id, "eat")
	_run(life, 1.0)
	ctx.executor.cancel(a.id, "test", "Test: Unterbrechung")
	var it: FoodItem = ctx.items.get(a.carried_item_id, null)
	var eaten: float = a.metabolism.totals["eaten_kg"]
	_check("Unterbrochenes Essen: Teil gegessen, Rest im Gegenstand, Bilanz geschlossen", re["result"].ok and it != null and eaten > 0.0 and absf(eaten + it.mass_kg - bite) < 1e-12 and absf(ctx.ledger.balance_error(ctx)) < 1e-12,
		"gegessen %.4f kg, Rest %.4f kg" % [eaten, it.mass_kg if it else -1.0])


# ── (5)(6) Licht ──────────────────────────────────

func _test_photosynthesis_and_darkness() -> void:
	var cfg: Dictionary = db.config("life")
	var p1 := Photosynthesis.power_w(0.03, 1.0, 1.0, cfg)
	var p2 := Photosynthesis.power_w(0.06, 1.0, 1.0, cfg)
	var ph := Photosynthesis.power_w(0.03, 0.5, 1.0, cfg)
	var ps := Photosynthesis.power_w(0.03, 1.0, float(cfg["photosynthesis"]["shade_factor_under_crown"]), cfg)
	_check("(5) Lichtenergie proportional zu Blattfläche und Licht, Schatten mindert", p1 > 0.0 and absf(p2 - 2.0 * p1) < 1e-9 and absf(ph - 0.5 * p1) < 1e-9 and ps < p1,
		"%.2f W, doppelte Fläche %.2f W, halbes Licht %.2f W, Schatten %.2f W" % [p1, p2, ph, ps])
	var life := _env_small(1)
	var ctx := life.ctx
	var cr: Creature = ctx.creatures.values()[0]
	cr.behavior_enabled = false
	var dn := ctx.day_night
	life.sim.clock.sim_time_s = (0.5 - dn.start_time_of_day) * dn.day_length_s   # Mittag
	var area0 := float(cr.caps["leaf_area_m2"])
	var lw0: float = cr.metabolism.totals["light_energy_j"]
	var n0: float = cr.metabolism.totals["food_nutrients_g"]
	_run(life, 2.0)
	var day_gain: float = cr.metabolism.totals["light_energy_j"] - lw0
	var leaves := cr.plan.leaf_ids().size()
	for i in leaves:
		life.dev_body_change(cr.id, "remove_leaf")
	var lw1: float = cr.metabolism.totals["light_energy_j"]
	_run(life, 2.0)
	_check("(5) Ohne Blätter keine Lichtenergie; mit Blättern bei Tag > 0", day_gain > 0.0 and cr.metabolism.totals["light_energy_j"] == lw1 and float(cr.caps["leaf_area_m2"]) == 0.0,
		"Fläche %.4f m², Gewinn %.1f J in 2 s" % [area0, day_gain])
	_check("Licht liefert keine Nährstoffe", cr.metabolism.totals["food_nutrients_g"] == n0)
	life.dev_body_change(cr.id, "add_leaf")
	life.sim.clock.sim_time_s = (1.0 - dn.start_time_of_day) * dn.day_length_s   # Mitternacht
	var lw2: float = cr.metabolism.totals["light_energy_j"]
	var target := cr.position + Vector3(1.5, 0, 0)
	var c := ctx.nav.world_to_col(target)
	if not ctx.nav.is_walkable(c):
		target = cr.position + Vector3(-1.5, 0, 0)
	var mv := ctx.executor.request(cr.id, "move_to", 0, Vector3(target.x, ctx.nav.ground_y(ctx.nav.world_to_col(target)), target.z))
	var p0 := cr.position
	_run(life, 2.0)
	_check("(6) Nachts: keine Photosynthese, Handlungen laufen weiter (kein Schlafzwang)",
		dn.light(ctx.now()) == 0.0 and cr.metabolism.totals["light_energy_j"] == lw2 and mv["result"].ok and cr.position.distance_to(p0) > 0.5,
		"Licht %.2f, %s, bewegt %.2f m" % [dn.light(ctx.now()), dn.phase_name(ctx.now()), cr.position.distance_to(p0)])


# ── (7) Körperteilverlust ──────────────────────────

func _test_body_changes() -> void:
	var life := _env_small(1)
	var ctx := life.ctx
	var cr: Creature = ctx.creatures.values()[0]
	cr.behavior_enabled = false
	var view := CreatureGenerator.build_view(cr.plan, life.sim.materials, 0.02)
	_free.append(view)
	var m0 := cr.mass_kg
	var g0 := float(cr.caps["grasp_by_side"]["r"])
	life.dev_body_change(cr.id, "remove_forearm", "r")
	view.rebuild()
	_check("(7) Unterarmverlust: Darstellung ohne Teil, Greifen rechts 0, Masse sinkt", not view.meshes.has("hand_r") and not view.pivots.has("arm_r_lower") and g0 > 0.0 and float(cr.caps["grasp_by_side"]["r"]) == 0.0 and cr.mass_kg < m0 and cr.caps["grasp_side"] == "l",
		"Masse %.3f → %.3f kg" % [m0, cr.mass_kg])
	var anim := view.animator.request("grasp", "r")
	_check("Greifanimation nur mit vorhandener Fähigkeit (Ersatzseite links)", anim["ok"] and anim["side"] == "l", anim["message"])
	life.dev_body_change(cr.id, "remove_forearm", "l")
	view.rebuild()
	_check("Ohne Hände: kein Greifen, Essen nur direkt mit dem Mund", float(cr.caps["grasp"]) == 0.0 and float(cr.caps["feeding"]) == 0.0 and float(cr.caps["mouth"]) > 0.0)
	var f := _nearest_food(life, cr.position)
	_place_near(life, cr, f)
	var pu := ctx.executor.request(cr.id, "pick_up", f.id)
	var e0: float = cr.metabolism.totals["eaten_kg"]
	var ed := ctx.executor.request(cr.id, "eat", f.id)
	_run(life, 3.0)
	_check("Ohne Hände: pick_up abgewiesen, direktes Essen an der Quelle funktioniert", not pu["result"].ok and pu["result"].code == "missing_capability" and ed["result"].ok and cr.metabolism.totals["eaten_kg"] > e0,
		pu["result"].message)
	ctx.executor.cancel(cr.id, "test", "Test")
	var m1 := cr.mass_kg
	var rw := life.dev_body_change(cr.id, "attach_prosthesis", "l", "wood")
	view.rebuild()
	var m2 := cr.mass_kg
	var rc := life.dev_body_change(cr.id, "attach_prosthesis", "r", "copper")
	view.rebuild()
	_check("Prothesen: Holz ohne Greifen, Kupferhaken greift; Masse steigt; Darstellung vorhanden",
		rw["ok"] and rc["ok"] and m2 > m1 and cr.mass_kg > m2 and float(cr.caps["grasp_by_side"]["l"]) == 0.0 and float(cr.caps["grasp_by_side"]["r"]) > 0.0 and view.meshes.has(str(rc["id"])),
		"Masse %.3f → %.3f → %.3f kg; Greifen %s" % [m1, m2, cr.mass_kg, str(cr.caps["grasp_by_side"])])
	var lc := int(cr.caps["leaf_count"])
	life.dev_body_change(cr.id, "remove_leaf")
	view.rebuild()
	_check("Blatt entfernen: Blattzahl und Blattfläche sinken", int(cr.caps["leaf_count"]) == lc - 1)
	_check("Körperänderungen protokolliert (Ereignisse)", life.sim.event_log.count_type("dev_body_change") >= 5)


# ── (8) Reservierungen bei Unterbrechung ──────────

func _test_interrupts_release() -> void:
	var life := _env_small(1)
	var ctx := life.ctx
	var cr: Creature = ctx.creatures.values()[0]
	cr.behavior_enabled = false
	var f := _nearest_food(life, cr.position)
	_place_near(life, cr, f)
	var cases := {}
	# Abbruch
	ctx.executor.request(cr.id, "pick_up", f.id)
	var had := not f.reserved.is_empty()
	ctx.executor.cancel(cr.id, "test", "Abbruch")
	cases["Abbruch"] = had and f.reserved.is_empty() and ctx.executor.reservations.is_empty()
	# Zeitüberschreitung
	ctx.executor.request(cr.id, "pick_up", f.id, null, {"timeout_s": 0.2})
	had = not f.reserved.is_empty()
	_run(life, 0.4)
	cases["Zeitlimit"] = had and f.reserved.is_empty() and ctx.executor.reservations.is_empty() and cr.last_result.get("code") == "timeout"
	# Zielverlust (Gegenstand am Boden verschwindet)
	var it := ctx.create_item(f.props(), 0.05, 0, cr.position + Vector3(0.3, 0, 0), f.id)
	ctx.ledger.initial_kg += 0.05
	ctx.executor.request(cr.id, "pick_up", it.id)
	had = it.reserved_by != 0
	ctx.remove_item(it.id, "Test: Ziel verschwindet")
	ctx.ledger.initial_kg -= 0.05
	life.step(DT)
	cases["Zielverlust"] = had and ctx.executor.reservations.is_empty() and cr.last_result.get("code") == "target_lost"
	# Ablauf der Reservierung (TTL)
	ctx.executor.request(cr.id, "pick_up", f.id, null, {"timeout_s": 1000.0})
	var rid: int = ctx.executor.running[cr.id].reservation_id
	ctx.executor.reservations[rid]["expires_t"] = ctx.now()
	life.step(DT)
	cases["Reservierung abgelaufen"] = f.reserved.is_empty() and ctx.executor.reservations.is_empty()
	# Tod
	ctx.executor.request(cr.id, "pick_up", f.id)
	had = not f.reserved.is_empty()
	cr.die("Test", ctx)
	cases["Tod"] = had and f.reserved.is_empty() and ctx.executor.reservations.is_empty() and not ctx.executor.running.has(cr.id)
	var bad: Array = []
	for k in cases:
		if not cases[k]:
			bad.append(k)
	_check("(8) Reservierungen frei bei Abbruch, Zeitlimit, Zielverlust, Ablauf und Tod", bad.is_empty() and life.audit().is_empty(), "fehlerhaft: %s %s" % [str(bad), str(life.audit())])
	_check("Strukturierte Ergebnisereignisse protokolliert", life.sim.event_log.count_type("action_cancelled") >= 1 and life.sim.event_log.count_type("action_failed") >= 2 and ctx.executor.history.size() >= 4)


# ── (9) Blockierte Wege ───────────────────────────

func _test_navigation_blocked() -> void:
	var life := _env_small(1)
	var ctx := life.ctx
	var nav := ctx.nav
	var cr: Creature = ctx.creatures.values()[0]
	cr.behavior_enabled = false
	var c0 := nav.world_to_col(cr.position)
	# Ziel: begehbare Spalte 3 Zellen entfernt, dann komplett ummauern
	var goal := c0
	for d in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]:
		var g: Vector2i = c0 + d
		if nav.is_walkable(g) and nav.find_path(c0, g)["ok"]:
			goal = g
			break
	var stone := life.world.palette.id_of("stone")
	var changed := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var cc := goal + Vector2i(dx, dz)
			var top := int(nav.ground[cc.x + nav.w * cc.y])
			for h in 4:
				if life.world.set_voxel(Vector3i(cc.x, top + h, cc.y), stone)["ok"]:
					changed += 1
	var updates := int(nav.stats["column_updates"])
	var r := nav.find_path(c0, goal)
	_check("Terrainänderung aktualisiert nur betroffene Spalten (keine Neuberechnung der Welt)", changed > 0 and updates > 0 and updates <= changed, "%d Zellen, %d Spaltenupdates" % [changed, updates])
	_check("(9) Ummauertes Ziel: Wegsuche erklärt unerreichbar (begrenzt)", not r["ok"] and r["code"] in ["unreachable", "search_limit"] and int(r["expansions"]) <= nav.max_expansions,
		"%s: %s (%d Knoten)" % [r["code"], r["reason"], r["expansions"]])
	var target := nav.col_center(goal)
	var mv := ctx.executor.request(cr.id, "move_to", 0, target)
	_run(life, 1.0)
	_check("(9) move_to zu unerreichbarem Ziel: erklärter Fehlschlag", mv["result"].ok and not ctx.executor.running.has(cr.id) and cr.last_result.get("status") == "failed" and str(cr.last_result.get("message", "")) != "",
		"%s – %s" % [str(cr.last_result.get("code")), str(cr.last_result.get("message"))])
	# Blockade während der Bewegung: Weg geplant, dann Spalte im Weg zumauern → begrenzte Neuplanung
	var life2 := _env_small(1)
	var ctx2 := life2.ctx
	var cr2: Creature = ctx2.creatures.values()[0]
	cr2.behavior_enabled = false
	var a0 := ctx2.nav.world_to_col(cr2.position)
	var far := a0
	for d2 in [Vector2i(10, 0), Vector2i(-10, 0), Vector2i(0, 10), Vector2i(0, -10)]:
		var g2: Vector2i = a0 + d2
		if ctx2.nav.in_bounds(g2) and ctx2.nav.is_walkable(g2) and ctx2.nav.find_path(a0, g2)["ok"]:
			far = g2
			break
	ctx2.executor.request(cr2.id, "move_to", 0, ctx2.nav.col_center(far))
	_run(life2, 0.2)
	var blocked_col: Vector2i = cr2.path[mini(cr2.path_i + 1, cr2.path.size() - 1)] if cr2.path.size() > 0 else a0
	var st := life2.world.palette.id_of("stone")
	var top2 := int(ctx2.nav.ground[blocked_col.x + ctx2.nav.w * blocked_col.y])
	for h in 4:
		life2.world.set_voxel(Vector3i(blocked_col.x, top2 + h, blocked_col.y), st)
	var ev0 := life2.sim.event_log.count_type("path_blocked")
	_run(life2, 20.0)
	var ev1 := life2.sim.event_log.count_type("path_blocked")
	var ok_end: bool = not ctx2.executor.running.has(cr2.id) and (cr2.last_result.get("status") == "succeeded" or cr2.last_result.get("code") in ["path_blocked", "unreachable"])
	_check("(9) Blockade unterwegs: erkannt, begrenzt neu geplant (Umweg oder erklärter Fehlschlag)", ev1 > ev0 and ev1 - ev0 <= int(ctx2.c("navigation")["max_replans"]) + 1 and ok_end,
		"%d Blockaden, Ergebnis %s/%s" % [ev1 - ev0, str(cr2.last_result.get("status")), str(cr2.last_result.get("code"))])
	# Suchbudget je Takt
	ctx2.nav.begin_tick()
	var granted := 0
	for i in 20:
		if ctx2.nav.take_request_budget():
			granted += 1
	_check("Wegsuchen je Takt begrenzt", granted == int(ctx2.c("navigation")["max_path_requests_per_tick"]), "%d von 20" % granted)
	# Stufen: zu hohe Stufe nicht begehbar
	var lc := ctx2.nav.world_to_col(cr2.position)
	var nb := lc + Vector2i(1, 0)
	var nb_top := int(ctx2.nav.ground[nb.x + ctx2.nav.w * nb.y])
	var own_top := int(ctx2.nav.ground[lc.x + ctx2.nav.w * lc.y])
	for h in range(nb_top, own_top + 3):
		life2.world.set_voxel(Vector3i(nb.x, h, nb.y), st)
	_check("Begrenzte Stufenhöhe: Stufe > 1 Zelle nicht begehbar", not ctx2.nav.can_step(lc, nb), "Höhe %d → %d Zellen" % [own_top, int(ctx2.nav.ground[nb.x + ctx2.nav.w * nb.y])])


# ── (10) Tod ──────────────────────────────────────

func _test_death() -> void:
	var life := _env_small(2)
	var ctx := life.ctx
	var cs: Array = ctx.creatures.values()
	var cr: Creature = cs[0]
	cr.behavior_enabled = false
	var f := _nearest_food(life, cr.position)
	_place_near(life, cr, f)
	ctx.executor.request(cr.id, "pick_up", f.id)
	_run(life, 2.5)
	var item_id := cr.carried_item_id
	ctx.executor.request(cr.id, "eat")
	life.step(DT)
	var food_before := ctx.ledger.sources_total(ctx)
	var pos := cr.position
	cr.health.starvation = 1.0   # Test: tödlicher Mangelschaden
	_run(life, 1.0)
	var it: FoodItem = ctx.items.get(item_id, null)
	_check("(10) Tod: Handlung abgebrochen, getragene Nahrung am Körper abgelegt", not cr.alive and item_id != 0 and it != null and it.carrier_id == 0 and it.position.distance_to(pos) < 0.2 and cr.carried_item_id == 0 and not ctx.executor.running.has(cr.id),
		"Ursache: %s" % str(cr.death.get("cause")))
	var p_dead := cr.position
	var e_dead := cr.metabolism.energy_j
	var dec0: int = int(cr.stats["decisions"])
	_run(life, 3.0)
	_check("(10) Nach dem Tod: kein Verhalten, kein Stoffwechsel, Körper bleibt am Ort", cr.position == p_dead and cr.metabolism.energy_j == e_dead and int(cr.stats["decisions"]) == dec0 and cr.behavior_state == "tot")
	_check("(10) Kein Recycling durch den Lebensbaum, Weltzustand konsistent", ctx.creatures.has(cr.id) and absf(ctx.ledger.sources_total(ctx) - food_before) < 1e-12 and life.audit().is_empty() and life.sim.event_log.count_type("creature_died") == 1,
		str(life.audit()))
	var other: Creature = cs[1]
	other.behavior_enabled = false
	ctx.executor.cancel(other.id, "test", "Test")
	_place_near(life, other, f)
	other.position = it.position + Vector3(0.3, 0, 0)
	var pu := ctx.executor.request(other.id, "pick_up", it.id)
	_check("Abgelegte Nahrung ist für andere Wesen wieder aufnehmbar", pu["result"].ok, pu["result"].message)


# ── (11) Pause ────────────────────────────────────

func _test_pause() -> void:
	var life := _env()
	life.new_game(_seed())
	_run(life, 5.0)
	var snap := JSON.stringify(SaveManager.snapshot(life)["creatures"])
	var t0 := life.ctx.now()
	var food0 := life.ctx.ledger.sources_total(life.ctx)
	life.sim.set_paused(true)
	_run(life, 5.0)
	var same := JSON.stringify(SaveManager.snapshot(life)["creatures"]) == snap
	_check("(11) Pause stoppt Zeit, Bewegung, Stoffwechsel, Handlungen und Nahrung", life.ctx.now() == t0 and same and life.ctx.ledger.sources_total(life.ctx) == food0)
	life.sim.set_paused(false)
	_run(life, 1.0)
	_check("(11) Fortsetzen nach Pause", life.ctx.now() > t0)


# ── (12)(13) Speichern und Laden ──────────────────

func _test_save_load() -> void:
	var life := _env()
	life.new_game(_seed())
	_run(life, 40.0)
	var ctx := life.ctx
	var ids: Array = ctx.creatures.keys()
	ids.sort()
	var c0: Creature = ctx.creatures[ids[0]]
	life.dev_body_change(c0.id, "remove_forearm", "l")
	life.dev_body_change(c0.id, "attach_prosthesis", "l", "copper")
	life.dev_body_change(c0.id, "injure_leg", "r")
	life.dev_body_change(c0.id, "remove_leaf")
	life.dev_body_change(ctx.creatures[ids[1]].id, "kill")
	# Terrainänderung, damit sie mitgespeichert wird
	var tc: Vector3i = life.world.generated["tree_cell"]
	var cell := Vector3i(tc.x + 20, int(life.ctx.nav.ground[(tc.x + 20) + life.ctx.nav.w * (tc.z + 20)]), tc.z + 20)
	var tr := life.world.set_voxel(cell, life.world.palette.id_of("stone"))
	# Laufende Aufnahme mit Reservierung zum Speicherzeitpunkt (Ladeverhalten: kontrolliert abbrechen)
	var c2: Creature = ctx.creatures[ids[2]]
	c2.behavior_enabled = false
	ctx.executor.cancel(c2.id, "test", "Test")
	if c2.carried_item_id != 0:
		ctx.executor.request(c2.id, "drop")
		_run(life, 1.0)
	var fpu := _nearest_food(life, c2.position)
	for fid in ctx.foods:
		if ctx.foods[fid].available_kg() > 0.2:
			fpu = ctx.foods[fid]
			break
	_place_near(life, c2, fpu)
	var pu := ctx.executor.request(c2.id, "pick_up", fpu.id)
	var sr := SaveManager.save(life, TEST_SAVE)
	var before := SaveManager.snapshot(life)
	var calls := PopulationSpawner.spawn_calls
	var life2 := _env()
	var lr := SaveManager.load_into(life2, TEST_SAVE)
	_check("Speichern über temporäre Datei, Laden erfolgreich", sr["ok"] and lr["ok"] and not FileAccess.file_exists(TEST_SAVE + ".tmp"), "%s / %s" % [sr["message"], lr["message"]])
	if not lr["ok"]:
		return
	var after := SaveManager.snapshot(life2)
	_check("(12) Laden erzeugt keine zusätzlichen Wesen, Spawner nicht aufgerufen", life2.ctx.creatures.size() == ctx.creatures.size() and PopulationSpawner.spawn_calls == calls and after["creatures"].size() == 50,
		"%d Wesen, Spawneraufrufe %d → %d" % [life2.ctx.creatures.size(), calls, PopulationSpawner.spawn_calls])
	var keys_eq := true
	var exact := true
	var diffs: Array = []
	for k in ["foods", "items", "creatures", "ledger", "world_objects"]:
		var na = _norm(before[k])
		var nb = _norm(after[k])
		if k == "creatures":
			# beim Laden abgebrochene Handlung: nur letztes Ergebnis/Entscheidungszeit ändern sich (gewollt)
			for arr in [na, nb]:
				for e in arr:
					if int(e["id"]) == c2.id:
						e.erase("last_result")
						e.erase("next_decision_t")
		if JSON.stringify(na) != JSON.stringify(nb):
			exact = false
		var d := _diff(na, nb, k)
		if not d.is_empty():
			keys_eq = false
			diffs.append_array(d.slice(0, 4))
	_check("(13) Nahrung, Gegenstände, Körper, Verletzungen, Prothesen, Speicher, Positionen identisch nach Speichern/Laden", keys_eq, "abweichend: %s" % str(diffs))
	notes.append("Speichern/Laden: Zustand %s" % ("bitgenau gleich" if exact else "gleich innerhalb 1e-12 relativ (einzelne Gleitkommawerte in der letzten Binärstelle verschieden)"))
	_check("(13) Terrainänderung und Wasser überstehen den Zyklus", tr["ok"] and after["world"]["current_hash"] == before["world"]["current_hash"] and after["world"]["water_b64"] == before["world"]["water_b64"] and int(before["world"]["changed_cells"]) >= 1)
	_check("Keine Offline-Zeit: Simulationszeit exakt die gespeicherte", life2.ctx.now() == ctx.now() and life2.sim.clock.tick_count == life.sim.clock.tick_count)
	_check("Zufallszustände wiederhergestellt", life2.sim.rng.state == life.sim.rng.state and life2.food_rng.state == life.food_rng.state)
	_check("Reservierungen nach dem Laden konsistent (freigegeben), Prüfung ohne Befund", life2.ctx.executor.reservations.is_empty() and life2.audit().is_empty(), str(life2.audit()))
	var reg_ok := true
	for id in life2.ctx.creatures:
		if life2.sim.registry.get_entity(id) != life2.ctx.creatures[id]:
			reg_ok = false
	_check("Keine doppelte Registrierung, IDs erhalten, nächste freie ID korrekt", reg_ok and life2.sim.registry.next_id() == life.sim.registry.next_id() and life2.sim.registry.count() == life.sim.registry.count(),
		"%d / %d Einträge" % [life2.sim.registry.count(), life.sim.registry.count()])
	var c2b: Creature = life2.ctx.creatures[c2.id]
	var f2: FoodSource = life2.ctx.foods[fpu.id]
	_check("Ladeverhalten: laufende Aufnahme (Reservierung) kontrolliert abgebrochen, Menge wieder frei", pu["result"].ok and not life2.ctx.executor.running.has(c2.id) and c2b.last_result.get("code") == "cancelled_on_load" and absf(f2.available_kg() - f2.amount_kg) < 1e-12 and str(lr.get("cancelled_actions", [])).find("pick_up") >= 0,
		"abgebrochen: %s" % str(lr.get("cancelled_actions", [])))
	var cont_ok := true
	for id in life2.ctx.executor.running:
		var ga: GameAction = life2.ctx.executor.running[id]
		var pol := str(ActionDefinition.info(ga.type).get("on_load", "cancel"))
		if not pol in ["continue", "replan"] or (ga.type == "eat" and ga.state.get("mode", "") != "carried"):
			cont_ok = false
	_check("Ladeverhalten: nur Handlungen mit „fortsetzen/neu planen“ (move_to, wait, Arme heben, Essen getragener Nahrung) laufen weiter", cont_ok and life2.ctx.executor.running.size() > 0, "%d laufend" % life2.ctx.executor.running.size())
	var dead2: Creature = life2.ctx.creatures[ids[1]]
	_check("Tote Wesen bleiben tot und am Ort", not dead2.alive and dead2.death.get("cause", "") != "")
	notes.append("Laden: fortgesetzt %s; abgebrochen %s" % [str(lr.get("continued_actions", []).size()), str(lr.get("cancelled_actions", []).size())])
	_run(life2, 10.0)
	_check("Simulation läuft nach dem Laden weiter, Prüfung ohne Befund", life2.ctx.now() > ctx.now() and life2.audit().is_empty(), str(life2.audit()))
	var again := SaveManager.load_into(life2, TEST_SAVE)
	_check("Laden in eine laufende Welt wird abgewiesen (keine doppelte Registrierung)", not again["ok"] and again["code"] == "not_fresh")


## JSON-Normalisierung (Ganzzahlen werden in JSON zu Gleitkommazahlen).
func _norm(v):
	return JSON.parse_string(JSON.stringify(v, "", true, true))


func _diff(a, b, path: String) -> Array:
	if typeof(a) != typeof(b):
		return [path + " (Typ)"]
	if a is Dictionary:
		var out: Array = []
		for k in a:
			if not b.has(k):
				out.append(path + "." + str(k) + " fehlt")
			else:
				out.append_array(_diff(a[k], b[k], path + "." + str(k)))
		for k in b:
			if not a.has(k):
				out.append(path + "." + str(k) + " neu")
		return out
	if a is Array:
		if a.size() != b.size():
			return [path + " (Länge)"]
		var out2: Array = []
		for i in a.size():
			out2.append_array(_diff(a[i], b[i], "%s[%d]" % [path, i]))
		return out2
	if typeof(a) == TYPE_FLOAT:
		# Toleranz 1e-12 relativ: Godot 4.5 liest manche 17-stelligen Dezimalzahlen um 1 Binärstelle abweichend ein
		return [] if absf(a - b) <= 1e-12 * maxf(1.0, absf(a)) else ["%s: %.17g ≠ %.17g" % [path, a, b]]
	return [] if a == b else ["%s: %s ≠ %s" % [path, str(a).substr(0, 40), str(b).substr(0, 40)]]


func _test_corrupt_saves() -> void:
	var life := _env()
	life.new_game(_seed())
	_run(life, 2.0)
	SaveManager.save(life, TEST_SAVE)
	var s2 := SaveManager.save(life, TEST_SAVE)
	_check("Zweites Speichern behält vorherige Datei als Sicherung", s2["ok"] and FileAccess.file_exists(TEST_SAVE + ".bak") and SaveManager.read_file(TEST_SAVE + ".bak")["ok"])
	var text := FileAccess.get_file_as_string(TEST_SAVE)
	var cases := {}
	_write("user://saves/_t_trunc.json", text.substr(0, text.length() / 2))
	cases["abgeschnitten"] = SaveManager.read_file("user://saves/_t_trunc.json")
	_write("user://saves/_t_flip.json", text.replace("\"amount_kg\":", "\"amount_kg\": 1.0e9 ,\"x\":"))
	cases["verändert"] = SaveManager.read_file("user://saves/_t_flip.json")
	_write("user://saves/_t_garbage.json", "kein Spielstand")
	cases["fremd"] = SaveManager.read_file("user://saves/_t_garbage.json")
	var nl := text.find("\n")
	var header: Dictionary = JSON.parse_string(text.substr(0, nl))
	var body := text.substr(nl + 1)
	header["format_version"] = 99
	_write("user://saves/_t_newer.json", JSON.stringify(header) + "\n" + body)
	cases["neuere Version"] = SaveManager.read_file("user://saves/_t_newer.json")
	header["format_version"] = 0
	_write("user://saves/_t_old.json", JSON.stringify(header) + "\n" + body)
	cases["unbekannte alte Version"] = SaveManager.read_file("user://saves/_t_old.json")
	var p: Dictionary = JSON.parse_string(body)
	p["modules"]["actors"].erase("creatures")   # Alpha 1.1 (Format 6): die Wesen stehen im Abschnitt des Moduls „actors“
	var b2 := JSON.stringify(p, "", true, true)
	header["format_version"] = SaveSchema.FORMAT_VERSION
	header["sha256"] = SaveSchema.sha256_text(b2)
	_write("user://saves/_t_missing.json", JSON.stringify(header) + "\n" + b2)
	cases["Pflichtfeld fehlt"] = SaveManager.read_file("user://saves/_t_missing.json")
	var expected := {"abgeschnitten": "corrupt", "verändert": "corrupt", "fremd": "corrupt", "neuere Version": "newer_format", "unbekannte alte Version": "invalid_format", "Pflichtfeld fehlt": "invalid"}
	var bad: Array = []
	for k in cases:
		if cases[k]["ok"] or cases[k]["code"] != expected[k] or str(cases[k]["message"]) == "":
			bad.append("%s→%s" % [k, cases[k].get("code")])
	_check("(14) Beschädigte/inkompatible Dateien kontrolliert abgewiesen (abgeschnitten, verändert, fremd, neuer, alt, unvollständig)", bad.is_empty(), str(bad))
	# Geänderte Definitionen
	var p2: Dictionary = JSON.parse_string(body)
	p2["meta"]["definitions"]["hash"] = "0000"   # Format 6: Definitionen im Kopf (meta)
	p2["meta"]["definitions"]["files"]["res://data/generated/excel/food.json"] = "geändert"
	var life2 := _env()
	var ar := SaveManager.apply(life2, p2)
	_check("(14) Geänderte Excel-Definitionen erkannt, Spielstand nicht still übernommen", not ar["ok"] and ar["code"] == "definitions_changed" and str(ar["message"]).find("food.json") >= 0 and life2.ctx.creatures.is_empty(), str(ar["message"]).substr(0, 160))
	var p3: Dictionary = JSON.parse_string(body)
	p3["regions"]["main"]["base_hash"] = "abc"   # Format 6: Gelände in der Region
	var life3 := _env()
	var ar3 := SaveManager.apply(life3, p3)
	_check("(14) Abweichendes Grundgelände (Generator geändert) erkannt", not ar3["ok"] and ar3["code"] == "world_mismatch")
	var mig := SaveMigrations.migrate({}, SaveSchema.FORMAT_VERSION)
	_check("Migrationsschnittstelle: aktuelles Format ohne Migration; nur die tatsächlich vorhandenen Stufen 1→2→3→4→5→6", mig["ok"] and mig["steps"].is_empty() and SaveMigrations.MIGRATIONS.keys() == [1, 2, 3, 4, 5])
	var bl := _env()
	var br := SaveManager.load_into(bl, TEST_SAVE + ".bak")
	_check("Sicherung (.bak) ist ladbar", br["ok"], br["message"])
	for f in ["_t_trunc", "_t_flip", "_t_garbage", "_t_newer", "_t_old", "_t_missing"]:
		DirAccess.remove_absolute("user://saves/%s.json" % f)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ── Dauerlauf ─────────────────────────────────────

func _test_long_run() -> void:
	var life := _env()
	life.new_game(_seed())
	var ctx := life.ctx
	var ticks := int(round(long_run_s / DT))
	var problems: Array = []
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var t0 := Time.get_ticks_usec()
	var max_us := 0
	var fails := {}
	var last_pos := {}
	var stuck: Array = []
	var minute_mark := int(round(60.0 / DT))
	var samples: Array = []
	for i in ticks:
		var a := Time.get_ticks_usec()
		life.step(DT)
		max_us = maxi(max_us, Time.get_ticks_usec() - a)
		if i % minute_mark == minute_mark - 1:
			var au := life.audit()
			if not au.is_empty():
				problems.append("t=%.0f: %s" % [ctx.now(), str(au.slice(0, 3))])
			for id in ctx.executor.running:
				var ga: GameAction = ctx.executor.running[id]
				if ga.elapsed_s > ga.timeout_s + 1.0:
					stuck.append("#%d %s %.0f s" % [id, ga.type, ga.elapsed_s])
			var s := life.population_summary()
			samples.append("t=%.0f lebend %d, tot %d, Hunger Ø %.2f, Nahrung %.1f kg, Handlungen %d" % [s["time_s"], s["alive"], s["dead"], s["avg_hunger"], s["food_kg"], s["running_actions"]])
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0
	for h in ctx.executor.history:
		if h["status"] == "failed":
			fails[h["actor"]] = int(fails.get(h["actor"], 0)) + 1
	var worst := 0
	for k in fails:
		worst = maxi(worst, fails[k])
	var obj1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem1 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var s_end := life.population_summary()
	var bounded := ctx.executor.history.size() <= int(ctx.c("actions")["result_history"]) and life.sim.event_log.all_entries().size() <= life.sim.event_log.max_entries
	_check("Dauerlauf %.0f s mit 50 Wesen: keine Laufzeit-/Bilanzfehler, keine Reservierungen ohne Besitzer" % long_run_s, problems.is_empty() and life.audit().is_empty(), str(problems.slice(0, 3)))
	_check("Dauerlauf: keine feststeckenden Handlungen (Zeitlimit greift), keine Dauerschleife von Fehlschlägen", stuck.is_empty() and worst <= 20,
		"festgesteckt %d; max. %d Fehlschläge eines Wesens in den letzten %d Ergebnissen" % [stuck.size(), worst, ctx.executor.history.size()])
	_check("Dauerlauf: begrenzte Listen, kein unkontrolliertes Speicherwachstum", bounded and obj1 - obj0 < 2000 and mem1 - mem0 < 64.0 * 1024.0 * 1024.0,
		"Objekte %+d, statischer Speicher %+.1f MB" % [int(obj1 - obj0), (mem1 - mem0) / 1048576.0])
	_check("Dauerlauf: Nahrung reicht für den Testzeitraum (Wesen haben gegessen)", ctx.ledger.eaten_kg > (1.0 if long_run_s >= 300.0 else 0.0) and s_end["food_kg"] > 0.0, "gegessen %.2f kg, Rest %.1f kg" % [ctx.ledger.eaten_kg, s_end["food_kg"]])
	notes.append("Dauerlauf: %.0f s Simulationszeit, %d Takte in %.1f s Rechenzeit → %.3f ms/Takt (max %.2f ms); lebend %d, tot %d; Handlungen %s; Wegsuchen %s" % [long_run_s, ticks, total_ms / 1000.0, total_ms / ticks, max_us / 1000.0, s_end["alive"], s_end["dead"], str(ctx.executor.stats), str(ctx.nav.stats)])
	for smp in samples:
		notes.append("  " + smp)
