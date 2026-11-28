class_name MindScenarios
extends RefCounted
## Kontrollierte, reproduzierbare Versuche zu Geist und Lernen (Prompt 4, Abschnitt 16).
## Wird von tests/test_mind.gd und vom Testbereich „Geistlabor“ (scenes/tests/mind_lab.tscn) benutzt.
##
## WICHTIG: Diese Versuche lösen Ereignisse GEZIELT aus (Verhalten der Beteiligten angehalten,
## Handlungen direkt angefordert, Göttereingriffe per Code). Das ist ausschließlich hier so – im
## normalen Spiel gibt es keine vorgeschriebenen Handlungen; dort entscheidet DecisionSystem.
## Jeder Versuch läuft in einer eigenen, frischen Simulation.

const DT := 1.0 / 60.0
const SCENARIOS := {"A": "Individuelle Erfahrung", "B": "Hilfe (Nahrungsübergabe)", "C": "Verdecktes Ereignis",
	"D": "Belohnungsassoziation", "E": "Widerspruch", "F": "Ähnlichkeit und Erfahrung", "G": "Speichern/Laden des Geistes"}

var db: DefinitionDB
var nodes: Array = []
var lives: Array = []
var parent: Node = null


func _init(p_db: DefinitionDB, p_parent: Node = null) -> void:
	db = p_db
	parent = p_parent


func cleanup() -> void:
	for l in lives:
		l.dispose()
	lives.clear()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()


## Frische Simulation mit Welt, Nahrung und n Wesen (Startwert seed für Körper/Persönlichkeit).
func env(seed: int, n: int) -> LifeSimulation:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	if parent != null:
		parent.add_child(sim)
		parent.add_child(world)
		parent.add_child(objs)
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs)
	life.build_world(int(db.config("world").get("seed", 12345)))
	life._create_food_sources(int(db.config("world").get("seed", 12345)))
	var r := PopulationSpawner.spawn(life.ctx, n, seed, life.tree_node.position)
	if r["ok"]:
		life.game_ready = true
	for id in life.ctx.creatures:
		life.ctx.creatures[id].behavior_enabled = false     # gezielte Versuche: kein spontanes Verhalten
	lives.append(life)
	return life


func run(life: LifeSimulation, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		life.step(DT)


func run_until_idle(life: LifeSimulation, id: int, max_s: float = 10.0) -> void:
	var t := 0.0
	while t < max_s and life.ctx.executor.running.has(id):
		life.step(DT)
		t += DT


## Begehbarer Punkt nahe p (Ringsuche).
func walkable_near(life: LifeSimulation, p: Vector3, min_r: float = 0.0) -> Vector3:
	var nav := life.ctx.nav
	for r in [min_r, min_r + 0.3, min_r + 0.6, min_r + 1.0, min_r + 1.5, min_r + 2.5]:
		for k in 16:
			var a := k * TAU / 16.0
			var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
			var c := nav.world_to_col(q)
			if nav.in_bounds(c) and nav.is_walkable(c):
				var free := true
				for oid in life.ctx.creatures:
					if life.ctx.distance_xz(life.ctx.creatures[oid].position, q) < 0.45:
						free = false
				if free:
					return Vector3(q.x, nav.ground_y(c), q.z)
	return p


func place(life: LifeSimulation, cr: Creature, p: Vector3, min_r: float = 0.0) -> void:
	cr.position = walkable_near(life, p, min_r)
	life.ctx.rebuild_spatial_hash()


## Platziert ein Wesen im Abstand d um p an einer Stelle mit freier Sichtlinie (Augenhöhe → p).
func place_with_view(life: LifeSimulation, cr: Creature, p: Vector3, d: float) -> bool:
	var nav := life.ctx.nav
	var eye_h := float(life.ctx.c("perception").get("eye_height_m", 0.75))
	for rr in [d, d + 0.5, d - 0.5, d + 1.0]:
		for k in 24:
			var a := k * TAU / 24.0
			var q := p + Vector3(cos(a) * rr, 0, sin(a) * rr)
			var c := nav.world_to_col(q)
			if not nav.in_bounds(c) or not nav.is_walkable(c):
				continue
			var gq := Vector3(q.x, nav.ground_y(c), q.z)
			var busy := false
			for oid in life.ctx.creatures:
				if life.ctx.distance_xz(life.ctx.creatures[oid].position, gq) < 0.45:
					busy = true
			if busy:
				continue
			var eye := gq + Vector3(0, eye_h, 0)
			var tp := p + Vector3(0, 0.4, 0)
			var h := life.ctx.terrain.raycast(eye, tp - eye, eye.distance_to(tp))
			if not h["hit"] or float(h["distance"]) >= eye.distance_to(tp) - 0.35:
				cr.position = gq
				life.ctx.rebuild_spatial_hash()
				return true
	place(life, cr, p, d)
	return false


func set_hunger(cr: Creature, h: float) -> void:
	var m := cr.metabolism
	var e := m.energy_capacity_j * (1.0 - h)
	m.start_energy_j += e - m.energy_j
	m.energy_j = e
	var nn := m.nutrient_capacity_g * (1.0 - h)
	m.start_nutrients_g += nn - m.nutrients_g
	m.nutrients_g = nn


## Wesen holt sich echt eine Portion von der nächsten Quelle (Aufnehmen, 1 s).
func fetch_food(life: LifeSimulation, cr: Creature) -> bool:
	var best: FoodSource = null
	var bd := INF
	for fid in life.ctx.foods:
		var f: FoodSource = life.ctx.foods[fid]
		var d := life.ctx.distance_xz(cr.position, f.position)
		if f.available_kg() > 0.15 and d < bd:
			bd = d
			best = f
	if best == null:
		return false
	place(life, cr, best.position, 0.6)
	var r := life.ctx.executor.request(cr.id, "pick_up", best.id)
	if not r["result"].ok:
		return false
	run_until_idle(life, cr.id, 5.0)
	return cr.carried_item_id != 0


func center(life: LifeSimulation) -> Vector3:
	return walkable_near(life, life.tree_node.position + Vector3(6, 0, 0), 0.0)


func _c(out: Array, name: String, ok: bool, detail: String = "") -> void:
	out.append({"name": name, "ok": ok, "detail": detail})


func gift_near(life: LifeSimulation, cr: Creature, kg: float = 0.1) -> Dictionary:
	life.ctx.rebuild_spatial_hash()
	return life.ctx.interventions.execute({"kind": "gift_food", "target_id": cr.id, "amount_kg": kg, "food_id": "N001"})


func raise_arms(life: LifeSimulation, cr: Creature) -> bool:
	var r := life.ctx.executor.request(cr.id, "raise_arms")
	run_until_idle(life, cr.id, 6.0)
	return r["result"].ok


# ── A: individuelle Erfahrung ─────────────────────

func scenario_a(seed: int) -> Dictionary:
	var out: Array = []
	var life := env(seed, 6)
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	var a: Creature = life.ctx.creatures[ids[0]]
	var b: Creature = life.ctx.creatures[ids[1]]
	var c: Creature = life.ctx.creatures[ids[2]]
	# weitere Wesen weit weg
	for k in range(3, ids.size()):
		place(life, life.ctx.creatures[ids[k]], center(life) + Vector3(0, 0, 18 + k))
	fetch_food(life, c)
	var p := center(life)
	place(life, c, p)
	place_with_view(life, a, c.position, 1.0)
	place_with_view(life, b, c.position, 2.2)
	set_hunger(a, 0.6)
	set_hunger(b, 0.6)
	# b bittet → c lehnt ab (c trägt sichtbar Nahrung)
	var rq := life.ctx.executor.request(b.id, "request_food", c.id)
	run_until_idle(life, b.id)
	var req_id := int(c.social["inbox"][0]["req"]) if not c.social["inbox"].is_empty() else 0
	life.ctx.executor.request(c.id, "decline_request", b.id, null, {"request_id": req_id})
	run_until_idle(life, c.id)
	var trust_b_after_decline := b.relations.trust(c.id)
	# c gibt a die Portion
	var g := life.ctx.executor.request(c.id, "give_food", a.id)
	run_until_idle(life, c.id)
	run(life, 1.0)
	var now := life.ctx.now()
	var mc := life.ctx.mind_cfg
	var a_got: Array = a.memory.recall({"participant": a.id, "type": "food_given"}, now, mc, 3)
	var b_dec: Array = b.memory.recall({"participant": b.id, "type": "request_declined"}, now, mc, 3)
	var a_dec_self: Array = a.memory.recall({"participant": a.id, "type": "request_declined"}, now, mc, 3)
	var b_seen_given: Array = b.memory.recall({"type": "food_given"}, now, mc, 3)
	_c(out, "A: Bitte und Ablehnung bzw. Übergabe tatsächlich ausgeführt", rq["result"].ok and req_id != 0 and g["result"].ok, "%s / %s" % [rq["result"].message, g["result"].message])
	_c(out, "A: unterschiedliche eigene Erfahrungen (a: Hilfe an sich, b: Ablehnung an sich; a nie selbst abgelehnt)",
		not a_got.is_empty() and not b_dec.is_empty() and a_dec_self.is_empty(),
		"a: %s · b: %s" % [str(a.memory.entries.map(func(e): return "%s→%d" % [e["type"], int(e["target"])])), str(b.memory.entries.map(func(e): return "%s→%d" % [e["type"], int(e["target"])]))])
	_c(out, "A: eigene Hilfe bedeutsamer als nur beobachtete Hilfe (persönliche Bedeutung)",
		not b_seen_given.is_empty() and float(a_got[0]["significance"]) > float(b_seen_given[0]["significance"]) if not a_got.is_empty() else false,
		"a %.2f vs b %.2f" % [float(a_got[0]["significance"]) if not a_got.is_empty() else -1.0, float(b_seen_given[0]["significance"]) if not b_seen_given.is_empty() else -1.0])
	_c(out, "A: unterschiedliche Bewertung von c (Vertrauen a→c > b→c)", a.relations.trust(c.id) > b.relations.trust(c.id),
		"a→c %.2f, b→c %.2f" % [a.relations.trust(c.id), b.relations.trust(c.id)])
	var prior_b := 1.0 + float(life.ctx.m("relationships")["similarity_trust_prior"]) * float(b.relations.rel[c.id]["similarity"])
	var prior_trust := prior_b / (prior_b + 1.0)
	_c(out, "A: Ablehnung ist kein schwerer Vertrauensbruch (Abnahme ≤ 0,10)", prior_trust - trust_b_after_decline <= 0.10 and trust_b_after_decline < prior_trust + 1e-9,
		"%.3f → %.3f" % [prior_trust, trust_b_after_decline])
	return {"checks": out, "life": life}


# ── B: Hilfe ──────────────────────────────────────

func scenario_b(seed: int) -> Dictionary:
	var out: Array = []
	var life := env(seed, 4)
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	var giver: Creature = life.ctx.creatures[ids[0]]
	var recv: Creature = life.ctx.creatures[ids[1]]
	fetch_food(life, giver)
	var p := center(life)
	place(life, giver, p)
	place(life, recv, p + Vector3(0.9, 0, 0))
	set_hunger(recv, 0.6)
	var item_id := giver.carried_item_id
	var kg: float = life.ctx.items[item_id].mass_kg if item_id != 0 else 0.0
	var bal0 := life.ctx.ledger.balance_error(life.ctx)
	giver.relations.ensure(giver, recv, life.ctx.now(), life.ctx.mind_cfg)
	recv.relations.ensure(recv, giver, life.ctx.now(), life.ctx.mind_cfg)
	var trust_g_before := giver.relations.trust(recv.id)
	var trust_r_before := recv.relations.trust(giver.id)
	var r := life.ctx.executor.request(giver.id, "give_food", recv.id)
	var mid_eat := life.ctx.executor.request(giver.id, "eat")     # während der Übergabe nicht essbar/belegt
	run_until_idle(life, giver.id)
	run(life, 0.5)
	_c(out, "B: Übergabe gestartet, Geber kann die Portion währenddessen nicht anders verwenden", r["result"].ok and not mid_eat["result"].ok, mid_eat["result"].message)
	_c(out, "B: Nahrung tatsächlich übertragen (Träger gewechselt, beim Geber abgezogen, Masse gleich)",
		item_id != 0 and giver.carried_item_id == 0 and recv.carried_item_id == item_id and life.ctx.items[item_id].carrier_id == recv.id and absf(life.ctx.items[item_id].mass_kg - kg) < 1e-12,
		"%.3f kg Portion #%d" % [kg, item_id])
	_c(out, "B: Nahrungsbilanz unverändert geschlossen", absf(life.ctx.ledger.balance_error(life.ctx)) < 1e-9 and absf(bal0) < 1e-9)
	var rr: Dictionary = recv.relations.rel.get(giver.id, {})
	var gr: Dictionary = giver.relations.rel.get(recv.id, {})
	_c(out, "B: gerichtete Beziehung: Empfänger→Geber Hilfe erhalten 1, Vertrauen gestiegen; Geber→Empfänger nur „gegeben“",
		int(rr.get("help_received", 0)) == 1 and recv.relations.trust(giver.id) > trust_r_before and int(gr.get("help_given", 0)) == 1 and int(gr.get("help_received", 0)) == 0 and absf(giver.relations.trust(recv.id) - trust_g_before) < 1e-9,
		"Empfänger→Geber Vertrauen %.2f; Geber→Empfänger %.2f" % [recv.relations.trust(giver.id), giver.relations.trust(recv.id)])
	return {"checks": out, "life": life}


# ── C: verdecktes Ereignis ────────────────────────

func scenario_c(seed: int) -> Dictionary:
	var out: Array = []
	var life := env(seed, 4)
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	var a: Creature = life.ctx.creatures[ids[0]]
	var near: Creature = life.ctx.creatures[ids[1]]
	var far: Creature = life.ctx.creatures[ids[2]]
	var p := center(life)
	place(life, a, p)
	place_with_view(life, near, a.position, 3.0)
	place(life, far, p + Vector3(0, 0, 22))
	place(life, life.ctx.creatures[ids[3]], p + Vector3(-22, 0, 0))
	var mem_far := far.memory.entries.size()
	var rel_far := far.relations.rel.duplicate(true)
	var g := gift_near(life, a)
	life.ctx.rebuild_spatial_hash()
	var g2 := life.ctx.interventions.execute({"kind": "heal", "target_id": a.id, "heal_amount": 0.5})    # a ist unverletzt → abgewiesen
	life.dev_body_change(a.id, "injure_leg", "l")
	var h := life.ctx.interventions.execute({"kind": "heal", "target_id": a.id, "heal_amount": 0.5})
	run(life, 1.0)
	var far_json := JSON.stringify([far.memory.to_dict(), far.relations.to_dict(), far.interventions_seen])
	_c(out, "C: Eingriffe ausgeführt (Heilen ohne Verletzung abgewiesen)", g["ok"] and not g2["ok"] and h["ok"], "%s / %s" % [g2["message"], h["message"]])
	_c(out, "C: Wesen außerhalb der Wahrnehmung: keine Erinnerung, keine Beziehungskorrektur, keine Deutung",
		far.memory.entries.size() == mem_far and JSON.stringify(far.relations.to_dict()) == JSON.stringify(rel_far) and far.interventions_seen.is_empty() and far_json.find("food_appeared") < 0,
		"%d Erinnerungen" % far.memory.entries.size())
	_c(out, "C: Empfänger und nahes Wesen haben es wahrgenommen", not a.interventions_seen.is_empty() and not near.interventions_seen.is_empty(),
		"a %d, nah %d" % [a.interventions_seen.size(), near.interventions_seen.size()])
	var rec: Dictionary = life.ctx.interventions.find(int(g["id"]))
	var obs_ids: Array = rec.get("observers", []).map(func(o): return int(o["id"]))
	_c(out, "C: Diagnose (Weltseite) nennt die Beobachter – getrennt vom Wissen der Wesen", a.id in obs_ids and not far.id in obs_ids, str(obs_ids))
	return {"checks": out, "life": life}


# ── D: Belohnungsassoziation ──────────────────────

func scenario_d(seed: int, trials: int = 6) -> Dictionary:
	var out: Array = []
	var life := env(seed, 4)
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	var a: Creature = life.ctx.creatures[ids[0]]
	var ctrl: Creature = life.ctx.creatures[ids[1]]
	var obs: Creature = life.ctx.creatures[ids[2]]
	var p := center(life)
	place(life, a, p)
	place_with_view(life, obs, a.position, 3.5)
	place(life, ctrl, p + Vector3(0, 0, 24))
	place(life, life.ctx.creatures[ids[3]], p + Vector3(-24, 0, 0))
	var key := "gift_after_action:raise_arms"
	var ps: Array = []
	var confs: Array = []
	for k in trials:
		raise_arms(life, a)
		run(life, 1.0)
		gift_near(life, a, 0.05)
		run(life, 0.2)
		ps.append(a.beliefs.p(key))
		confs.append(a.beliefs.confidence(key, life.ctx.mind_cfg))
		# Kontrolle: Geste, Gabe erst nach 20 s (außerhalb des Zeitfensters)
		raise_arms(life, ctrl)
		run(life, 20.0)
		gift_near(life, ctrl, 0.05)
		run(life, 1.0)
	var est := LearningSystem.repeat_estimate(a, "raise_arms", life.ctx)
	var est_c := LearningSystem.repeat_estimate(ctrl, "raise_arms", life.ctx)
	var rising := true
	for i in range(1, ps.size()):
		if ps[i] < ps[i - 1] - 0.05:
			rising = false
	_c(out, "D: keine Gewissheit nach einer einzelnen Gabe (Konfidenz ≤ 0,2)", confs.size() > 0 and float(confs[0]) <= 0.2 + 1e-9, "Konfidenz nach 1: %.2f" % float(confs[0]))
	_c(out, "D: Erwartung steigt nachvollziehbar mit Wiederholung (Konfidenz ↑, Häufigkeit über Grundhäufigkeit)",
		rising and float(confs[confs.size() - 1]) > float(confs[0]) and float(est["delta"]) > 0.0 and float(confs[confs.size() - 1]) < 0.95,
		"p: %s; Konfidenz %s; Δ zur Grundhäufigkeit %.2f" % [str(ps.map(func(x): return snappedf(x, 0.01))), str(confs.map(func(x): return snappedf(x, 0.01))), float(est["delta"])])
	_c(out, "D: zeitlich unverbundene Gaben erzeugen keine Erwartung", float(est_c["delta"]) <= 0.0 and float(est_c["confidence"]) < float(est["confidence"]),
		"Kontrolle Δ %.2f, Konfidenz %.2f" % [float(est_c["delta"]), float(est_c["confidence"])])
	_c(out, "D: Beobachter bildet eine andere Erklärung (bei a, nicht bei sich)", obs.beliefs.has_belief("gift_after_other:raise_arms") and not obs.beliefs.has_belief(key),
		str(obs.beliefs.items.keys()))
	# Gewichtung: kurz vorher beendete Handlung erhält den Großteil
	var life2 := env(seed + 1, 2)
	var x: Creature = life2.ctx.creatures.values()[0]
	place(life2, x, center(life2))
	life2.ctx.executor.request(x.id, "wait", 0, null, {"duration_s": 1.0})
	run_until_idle(life2, x.id)
	run(life2, 7.0)
	raise_arms(life2, x)
	run(life2, 0.5)
	gift_near(life2, x, 0.05)
	var cred: Array = x.interventions_seen.back()["credited"] if not x.interventions_seen.is_empty() else []
	var w := {}
	for c in cred:
		w[c["type"]] = float(c["w"])
	_c(out, "D: ein Eingriff verstärkt nicht alle kürzlichen Handlungen gleich (Arme heben ≫ Warten)", float(w.get("raise_arms", 0.0)) > 0.8 and float(w.get("wait", 0.0)) < 0.15,
		str(cred))
	return {"checks": out, "life": life, "p_series": ps, "conf_series": confs, "delta_end": float(est["delta"])}


# ── E: Widerspruch ────────────────────────────────

func scenario_e(seed: int) -> Dictionary:
	var out: Array = []
	var d := scenario_d(seed, 6)
	var life: LifeSimulation = d["life"]
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	var a: Creature = life.ctx.creatures[ids[0]]
	var key := "gift_after_action:raise_arms"
	var p0 := a.beliefs.p(key)
	var ps: Array = [p0]
	for k in 8:
		raise_arms(life, a)
		run(life, 14.0)          # Zeitfenster verstreicht ohne Ereignis → Gegenbeispiel
		ps.append(a.beliefs.p(key))
	var max_drop := 0.0
	var falling := true
	for i in range(1, ps.size()):
		max_drop = maxf(max_drop, float(ps[i - 1]) - float(ps[i]))
		if float(ps[i]) > float(ps[i - 1]) + 1e-9:
			falling = false
	var h: Dictionary = a.beliefs.items.get(key, {})
	_c(out, "E: ausbleibende Bestätigung schwächt die Erwartung ab", falling and float(ps[ps.size() - 1]) < p0 - 0.1, "p: %s" % str(ps.map(func(x): return snappedf(x, 0.01))))
	_c(out, "E: Abschwächung begrenzt (je Gegenbeispiel ≤ 0,15), Gegenbeispiele gezählt", max_drop <= 0.15 and int(h.get("n_contra", 0)) >= 8 and float(ps[ps.size() - 1]) > 0.0,
		"größter Schritt %.3f; dagegen %d" % [max_drop, int(h.get("n_contra", 0))])
	var est := LearningSystem.repeat_estimate(a, "raise_arms", life.ctx)
	_c(out, "E: Vorteil gegenüber der Grundhäufigkeit mindestens halbiert", float(est["delta"]) <= 0.5 * float(d["delta_end"]), "Δ %.2f → %.2f" % [float(d["delta_end"]), float(est["delta"])])
	return {"checks": out, "life": life}


# ── F: Ähnlichkeit und Erfahrung ──────────────────

func scenario_f(seed: int) -> Dictionary:
	var out: Array = []
	var life := env(seed, 14)
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	var a: Creature = life.ctx.creatures[ids[0]]
	var best_sim := -1.0
	var worst_sim := 2.0
	var similar: Creature = null
	var different: Creature = null
	for k in range(1, ids.size()):
		var o: Creature = life.ctx.creatures[ids[k]]
		var s := RelationshipStore.similarity(RelationshipStore.visible_traits(a), RelationshipStore.visible_traits(o))
		if s > best_sim:
			best_sim = s
			similar = o
		if s < worst_sim:
			worst_sim = s
			different = o
	for k in range(1, ids.size()):
		var o2: Creature = life.ctx.creatures[ids[k]]
		if o2 != similar and o2 != different:
			place(life, o2, center(life) + Vector3(0, 0, 20 + k))
	var p := center(life)
	place(life, a, p)
	place(life, similar, p + Vector3(-2.5, 0, 0))
	a.relations.ensure(a, similar, life.ctx.now(), life.ctx.mind_cfg)
	a.relations.ensure(a, different, life.ctx.now(), life.ctx.mind_cfg)
	var t_sim0 := a.relations.trust(similar.id)
	var t_dif0 := a.relations.trust(different.id)
	var helps := 0
	for k in 3:
		if not fetch_food(life, different):
			break
		place(life, a, p)
		place(life, different, p + Vector3(1.0, 0, 0))
		set_hunger(a, 0.6)
		var r := life.ctx.executor.request(different.id, "give_food", a.id)
		run_until_idle(life, different.id)
		run(life, 0.3)
		if r["result"].ok and a.carried_item_id != 0:
			helps += 1
			life.ctx.executor.request(a.id, "eat")
			run_until_idle(life, a.id, 30.0)
	_c(out, "F: Ähnlichkeit nur aus sichtbaren Merkmalen; Anfangsvertrauen zum Ähnlichen höher", best_sim > worst_sim and t_sim0 > t_dif0,
		"Ähnlichkeit %.2f vs %.2f; Vertrauen anfangs %.2f vs %.2f" % [best_sim, worst_sim, t_sim0, t_dif0])
	_c(out, "F: wiederholte Hilfe des äußerlich anderen Wesens überwiegt die Anfangstendenz", helps == 3 and a.relations.trust(different.id) > a.relations.trust(similar.id),
		"%d× geholfen; Vertrauen jetzt %.2f (anders) vs %.2f (ähnlich)" % [helps, a.relations.trust(different.id), a.relations.trust(similar.id)])
	return {"checks": out, "life": life}


# ── G: Speichern/Laden ────────────────────────────

func scenario_g(seed: int, path: String) -> Dictionary:
	var out: Array = []
	var d := scenario_d(seed, 3)
	var life: LifeSimulation = d["life"]
	life.ctx.interventions.execute({"kind": "place_material", "target_id": life.ctx.creatures.keys()[0], "material_id": "stone"})
	var sr := SaveManager.save(life, path)
	var before := SaveManager.snapshot(life)
	var life2 := LifeSimulation.new()
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	if parent != null:
		parent.add_child(sim)
		parent.add_child(world)
		parent.add_child(objs)
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	nodes.append_array([sim, world, objs])
	life2.setup(sim, db, world, objs)
	lives.append(life2)
	var lr := SaveManager.load_into(life2, path)
	_c(out, "G: Speichern und Laden erfolgreich", sr["ok"] and lr["ok"], "%s / %s" % [sr["message"], lr["message"]])
	if not lr["ok"]:
		return {"checks": out, "life": life}
	var after := SaveManager.snapshot(life2)
	var diffs: Array = []
	for i in before["creatures"].size():
		diffs.append_array(_diff(_norm(before["creatures"][i]["mind"]), _norm(after["creatures"][i]["mind"]), "wesen[%d].mind" % i))
	_c(out, "G: Persönlichkeit, Erinnerungen, Überzeugungen, Beziehungen, Ziele, Wartezeiten identisch (Gleitkomma ≤ 1e-12 relativ)", diffs.is_empty(), str(diffs.slice(0, 3)))
	var d2: Array = []
	for k in ["interventions", "material_pieces", "social", "ledger"]:
		d2.append_array(_diff(_norm(before[k]), _norm(after[k]), k))
	_c(out, "G: Eingriffsprotokoll, Materialstücke, soziale Bitten und Bilanz identisch", d2.is_empty(), str(d2.slice(0, 3)))
	var a1: Creature = life.ctx.creatures[life.ctx.creatures.keys()[0]]
	var a2: Creature = life2.ctx.creatures[a1.id]
	_c(out, "G: gelernte Bewertung nach dem Laden gleich (Wiederholungsschätzung)",
		absf(float(LearningSystem.repeat_estimate(a1, "raise_arms", life.ctx)["delta"]) - float(LearningSystem.repeat_estimate(a2, "raise_arms", life2.ctx)["delta"])) < 1e-9)
	return {"checks": out, "life": life2}


static func _norm(v):
	return JSON.parse_string(JSON.stringify(v, "", true, true))


## Strukturvergleich; Gleitkommazahlen mit Toleranz 1e-12 relativ (Godot 4.5 liest manche
## 17-stelligen Dezimalzahlen um eine Binärstelle abweichend ein).
static func _diff(a, b, path: String) -> Array:
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
		var o2: Array = []
		for i in a.size():
			o2.append_array(_diff(a[i], b[i], "%s[%d]" % [path, i]))
		return o2
	if typeof(a) == TYPE_FLOAT:
		return [] if absf(a - b) <= 1e-12 * maxf(1.0, absf(a)) else ["%s: %.17g ≠ %.17g" % [path, a, b]]
	return [] if a == b else ["%s: %s ≠ %s" % [path, str(a), str(b)]]


func run_scenario(letter: String, seed: int, save_path: String = "user://saves/_szenario_g.json") -> Array:
	var r: Dictionary
	match letter:
		"A": r = scenario_a(seed)
		"B": r = scenario_b(seed)
		"C": r = scenario_c(seed)
		"D": r = scenario_d(seed)
		"E": r = scenario_e(seed)
		"F": r = scenario_f(seed)
		"G": r = scenario_g(seed, save_path)
		_: return [{"name": "unbekanntes Szenario", "ok": false, "detail": letter}]
	var problems: Array = (r["life"] as LifeSimulation).audit()
	r["checks"].append({"name": "%s: Konsistenzprüfung ohne Befund" % letter, "ok": problems.is_empty(), "detail": str(problems.slice(0, 3))})
	return r["checks"]
