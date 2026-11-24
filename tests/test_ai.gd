class_name TestAI
extends RefCounted
## Prüfungen der Ollama-Anbindung, Pläne, Gespräche und Hörensagen (Prompt 5).
## ALLE Modellantworten hier stammen vom SIMULIERTEN Testdienst (MockOllama) bzw. einer lokalen
## HTTP-Attrappe (tools/ollama_attrappe.py). Kein Ergebnis dieser Datei ist ein Nachweis einer echten
## Ollama-Verbindung – dafür gibt es tools/ollama_live_test.gd (auf dem eigenen Rechner auszuführen).

const DT := 1.0 / 60.0
const FIXTURE_V2 := "res://tests/fixtures/save_v2_prompt04.json"

var results: Array = []
var notes: Array = []
var db: DefinitionDB
var sc: MindScenarios
var clock := {"ms": 0.0}
var world_seed: int = 12345


func run_all() -> Array:
	results.clear()
	notes.clear()
	db = DefinitionDB.new()
	db.load_all()
	sc = MindScenarios.new(db)
	world_seed = int(db.config("world").get("seed", 12345))
	_test_settings_and_client()
	_test_queue()
	_test_valid_plan()
	_test_rejections()
	_test_eaten_target()
	_test_stale_and_reset()
	_test_death_and_pause()
	_test_errors_and_breaker()
	_test_context_privacy()
	_test_conversation_and_hearsay()
	_test_verification()
	_test_save_load_and_migration()
	_test_without_ollama()
	_test_rate_limit_50()
	_test_http_paths()
	sc.cleanup()
	return results


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": "[KI/SIMULIERT] " + name, "ok": ok, "detail": detail})


# ── Hilfen ────────────────────────────────────────

func _settings(extra: Dictionary = {}) -> AISettings:
	var s := AISettings.new()
	s.user_path = ""
	s.reload()
	s.set_value("enabled", true)
	s.set_value("use_mock", true)
	s.set_value("model", MockOllama.MODEL)
	s.set_value("eligible_share", 0.0)          # keine automatischen Anfragen, außer ausdrücklich gewünscht
	s.set_value("per_creature_min_interval_s", 5.0)
	s.set_value("global_rate_per_min", 600)
	s.set_value("health_check_interval_s", 15.0)
	for k in extra:
		s.set_value(k, extra[k])
	return s


func _svc(extra: Dictionary = {}, mode: String = "ok", latency_ms: int = 0) -> AIService:
	var m := MockOllama.new()
	var svc := AIService.new(_settings(extra), m)
	svc.client.clock = func(): return int(clock["ms"])
	svc.test_connection()
	for i in 4:
		svc.poll()
	m.mode = mode                 # Verzögerung/Betriebsart erst nach der Verbindungsprüfung
	m.latency_ms = latency_ms
	return svc


func _mock(svc: AIService) -> MockOllama:
	return svc.client.transport as MockOllama


func _env(svc: AIService, n: int, seed: int, behavior: bool = false) -> LifeSimulation:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs, svc)
	life.build_world(world_seed)
	life._create_food_sources(world_seed)
	var r := PopulationSpawner.spawn(life.ctx, n, seed, life.tree_node.position)
	if r["ok"]:
		life.game_ready = true
	for id in life.ctx.creatures:
		life.ctx.creatures[id].behavior_enabled = behavior
	sc.lives.append(life)
	return life


func _run(life: LifeSimulation, secs: float) -> void:
	for i in int(round(secs / DT)):
		clock["ms"] = float(clock["ms"]) + 1000.0 / 60.0
		life.step(DT)


func _ids(life: LifeSimulation) -> Array:
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	return ids


## Nächste Nahrungsquelle mit Menge; Wesen mit Sicht in Abstand d davon, Wahrnehmung aktualisiert.
func _near_food(life: LifeSimulation, cr: Creature, d: float = 3.0) -> FoodSource:
	var best: FoodSource = null
	var bd := INF
	var c := sc.center(life)
	for fid in life.ctx.foods:
		var f: FoodSource = life.ctx.foods[fid]
		var dd := life.ctx.distance_xz(c, f.position)
		if f.available_kg() > 0.3 and dd < bd:
			bd = dd
			best = f
	sc.place_with_view(life, cr, best.position, d)
	life.ctx.rebuild_spatial_hash()
	Perception.scan(cr, life.ctx)
	return best


## Begehbarer Punkt mit möglichst großem Abstand zu allen Nahrungsquellen (dort sieht niemand Nahrung).
func _far_from_food(life: LifeSimulation, _r: float) -> Vector3:
	var nav := life.ctx.nav
	var c := life.tree_node.position
	var best := c
	var best_d := -1.0
	for ring in [8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0]:
		for k in 48:
			var a := k * TAU / 48.0
			var q := c + Vector3(cos(a) * ring, 0, sin(a) * ring)
			var col := nav.world_to_col(q)
			if not nav.in_bounds(col) or not nav.is_walkable(col):
				continue
			var md := INF
			for fid in life.ctx.foods:
				md = minf(md, life.ctx.distance_xz(life.ctx.foods[fid].position, q))
			if md > best_d:
				best_d = md
				best = Vector3(q.x, nav.ground_y(col), q.z)
	return best


## Begehbarer Punkt in rmin..rmax Metern von p, mindestens clear Meter von jeder Nahrungsquelle entfernt.
func _point_near(life: LifeSimulation, p: Vector3, rmin: float, rmax: float, clear: float) -> Vector3:
	var nav := life.ctx.nav
	var r := rmin
	while r <= rmax:
		for k in 36:
			var a := k * TAU / 36.0
			var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
			var col := nav.world_to_col(q)
			if not nav.in_bounds(col) or not nav.is_walkable(col):
				continue
			var ok := true
			for fid in life.ctx.foods:
				if life.ctx.distance_xz(life.ctx.foods[fid].position, q) < clear:
					ok = false
					break
			if ok:
				return Vector3(q.x, nav.ground_y(col), q.z)
		r += 0.5
	return _far_from_food(life, clear)


## Zuhörer dicht neben den Sprecher stellen, mit Sichtlinie (Gelände kann sonst verdecken).
func _place_listener(life: LifeSimulation, l: Creature, sp: Creature) -> void:
	for r in [1.2, 1.6, 2.0]:
		for k in 12:
			var a := k * TAU / 12.0
			sc.place(life, l, sp.position + Vector3(cos(a) * r, 0, sin(a) * r), 0.0)
			life.ctx.rebuild_spatial_hash()
			if life.ctx.distance_xz(l.position, sp.position) <= 2.5 and CommunicationSystem.listener_perceives(sp, l, life.ctx):
				return


## Kurzsichtiger Zuhörer (3 m): in der kleinen Testwelt sieht er so keine fernen Nahrungsquellen selbst.
func _myopic(xs: Array) -> void:
	for x in xs:
		x.caps["perception"] = 0.3


## Sprecher kennt nur diese eine Quelle und sieht danach nur noch 3 m weit (eindeutige Gesprächsinhalte).
func _only_knows(cr: Creature, fid: int) -> void:
	cr.caps["perception"] = 0.3
	for k in cr.food_memory.keys():
		if k != fid:
			cr.food_memory.erase(k)


## Wesen lernt eine Quelle mit voller Sicht kennen und kennt danach nur diese (Sicht dann 3 m).
func _learn(life: LifeSimulation, cr: Creature, f: FoodSource, d: float = 2.0) -> bool:
	cr.caps["perception"] = 1.0
	var placed := sc.place_with_view(life, cr, f.position, d)
	life.ctx.rebuild_spatial_hash()
	Perception.scan(cr, life.ctx)
	ClaimEvaluator.on_perception(cr, life.ctx)
	_only_knows(cr, f.id)
	return placed and f.id in cr.visible_food


func _wait_answer(life: LifeSimulation, cr: Creature, max_s: float = 3.0) -> void:
	var t := 0.0
	while t < max_s:
		_run(life, DT)
		t += DT
		var st := str(cr.ai.get("last", {}).get("status", ""))
		if st in ["angenommen", "abgelehnt", "fehlgeschlagen", "verworfen"]:
			return


func _plan_resp(steps: Array, goal: String = "food", extra: Dictionary = {}) -> Callable:
	return func(_body: Dictionary, c: Dictionary) -> Dictionary:
		var d := {"request_id": int(c["anfrage"]["request_id"]), "actor_id": int(c["ich"]["id"]), "goal_type": goal, "proposed_steps": steps,
			"referenced_memory_ids": [], "uncertainty": 0.3, "short_explanation": "Testantwort"}
		d.merge(extra, true)
		return d


# ── Einstellungen und Client ──────────────────────

func _test_settings_and_client() -> void:
	print("  KI-Test: _test_settings_and_client (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var s := _settings({"use_mock": false})
	s.set_value("base_url", "http://192.168.1.50:11434")
	var e1 := s.endpoint()
	s.set_value("base_url", "https://ollama.example.com")
	var e2 := s.endpoint()
	s.set_value("allow_remote", true)
	var e3 := s.endpoint()
	s.set_value("base_url", "http://user:pw@127.0.0.1:11434")
	var e4 := s.endpoint()
	s.set_value("base_url", "http://127.0.0.1:11434")
	s.set_value("allow_remote", false)
	var e5 := s.endpoint()
	_check("Einstellungen: nur lokale Adressen ohne ausdrückliche Freigabe; keine Zugangsdaten/Pfade in der Adresse", not e1["ok"] and not e2["ok"] and e3["ok"] and not e4["ok"] and e5["ok"] and e5["local"],
		"%s | %s" % [e1["message"], e4["message"]])
	OS.set_environment("PW_TEST_OLLAMA_TOKEN", "geheim-123-xyz")
	var s2 := _settings({"use_mock": false, "allow_remote": true, "auth_env_var": "PW_TEST_OLLAMA_TOKEN"})
	s2.user_path = "user://_test_ai_settings.json"
	var hdr := s2.auth_headers()
	var sv := s2.save_user()
	var saved := FileAccess.get_file_as_string(s2.user_path)
	var pub := JSON.stringify(s2.public_dict())
	var s3 := _settings({"use_mock": false, "auth_env_var": "PW_TEST_OLLAMA_TOKEN"})
	_check("Zugangsschlüssel nur zur Laufzeit aus Umgebungsvariable – nie gespeichert, nie in Anzeige; lokal wird er gar nicht gesendet",
		hdr.size() == 1 and sv["ok"] and not saved.contains("geheim-123") and not pub.contains("geheim-123") and s3.auth_headers().is_empty(), saved.substr(0, 120))
	DirAccess.remove_absolute(s2.user_path)
	OS.set_environment("PW_TEST_OLLAMA_TOKEN", "")
	var cl := OllamaClient.new(_settings(), MockOllama.new())
	var forbidden := cl._start("pull", "/api/pull", "{}", {}, 1000) < 0 and cl._start("delete", "/api/delete", "{}", {}, 1000) < 0 and cl._start("x", "/api/create", "{}", {}, 1000) < 0
	_check("Client: nur Abfragen (version, tags, ps, chat) – kein pull/delete/create, kein Start/Stopp", forbidden and OllamaClient.ALLOWED.size() == 4 and not OllamaClient.ALLOWED.has("/api/pull"))
	var b := s.set_value("unbekannt", 1)
	var bad_type := s.set_value("max_queue", "viel")
	_check("Einstellungen: unbekannte Schlüssel ignoriert, falsche Typen abgewiesen", not b and not bad_type and int(s.g("max_queue")) == 16)


# ── Warteschlange ─────────────────────────────────

func _q(id: int, actor: int, prio: int, t: float = 0.0) -> Dictionary:
	return {"id": id, "session": 1, "actor": actor, "kind": "plan", "reason": "", "priority": prio, "created_t": t, "expires_t": t + 60.0, "attempts": 0, "next_try_ms": 0, "listener": 0}


func _test_queue() -> void:
	print("  KI-Test: _test_queue (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var q := RequestQueue.new()
	q.max_len = 3
	var a := q.enqueue(_q(1, 10, 1))
	var dup := q.enqueue(_q(2, 10, 1))
	var rep := q.enqueue(_q(3, 10, 3))
	q.enqueue(_q(4, 11, 1, 1.0))
	q.enqueue(_q(5, 12, 1, 2.0))
	var full := q.enqueue(_q(6, 13, 1))
	var evict := q.enqueue(_q(7, 14, 2))
	_check("Warteschlange: begrenzt, eine Anfrage je Wesen, dringendere ersetzt/verdrängt, sonst Abweisung",
		a["ok"] and dup["code"] == "duplicate" and rep["code"] == "replaced" and full["code"] == "queue_full" and evict["code"] == "evicted_other" and q.size() == 3,
		"%s %s %s %s" % [dup["code"], rep["code"], full["code"], evict["code"]])
	var first := q.pop_ready(0, 0.0)
	q.mark_running(first, 100)
	var second := q.pop_ready(0, 0.0)
	_check("Warteschlange: Priorität zuerst, dann Fairness/Alter", int(first["id"]) == 3 and int(second["id"]) == 7, "%d, %d" % [int(first["id"]), int(second["id"])])
	var q2 := RequestQueue.new()
	q2.enqueue(_q(1, 1, 1))
	q2.enqueue(_q(2, 2, 1))
	q2.served_at[1] = 500
	var f2 := q2.pop_ready(1000, 0.0)
	q2.enqueue(_q(3, 3, 1, 0.0))
	q2.waiting[q2.waiting.size() - 1]["expires_t"] = 5.0
	var none_exp := q2.pop_ready(1000, 10.0)
	_check("Warteschlange: Fairness (länger nicht bedientes Wesen zuerst) und Ablauf nach Zeitlimit", int(f2["actor"]) == 2 and int(none_exp.get("actor", 1)) == 1 and q2.size() == 0 and q2.dropped.any(func(d): return str(d["reason"]).begins_with("abgelaufen")))
	var q3 := RequestQueue.new()
	var e := _q(9, 9, 1)
	q3.enqueue(e)
	var x := q3.pop_ready(0, 0.0)
	x["attempts"] = 1
	q3.mark_running(x, 0)
	var r1 := q3.retry(x, 0, 1, 5.0)
	var blocked := q3.pop_ready(4000, 0.0).is_empty()
	var y := q3.pop_ready(5001, 0.0)
	y["attempts"] = 2
	q3.mark_running(y, 5001)
	var r2 := q3.retry(y, 5001, 1, 5.0)
	_check("Warteschlange: begrenzte Wiederholung mit Wartezeit, danach keine Endlosschleife", r1 and blocked and not y.is_empty() and not r2 and q3.size() == 0 and q3.running.is_empty())


# ── Gültiger Plan ─────────────────────────────────

func _test_valid_plan() -> void:
	print("  KI-Test: _test_valid_plan (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc()
	var life := _env(svc, 3, 101)
	var ids := _ids(life)
	var a: Creature = life.ctx.creatures[ids[0]]
	for k in range(1, ids.size()):
		sc.place(life, life.ctx.creatures[ids[k]], _far_from_food(life, 12.0) + Vector3(k, 0, 0))
	var f := _near_food(life, a, 3.0)
	sc.set_hunger(a, 0.55)
	var eaten0 := float(a.stats.get("eaten_kg", 0.0))
	var reg0 := life.sim.registry.count()
	var rq := life.ctx.ai.request_now(a, "plan", "Test: gültiger Plan")
	_wait_answer(life, a)
	var accepted := str(a.ai["last"].get("status", "")) == "angenommen" and PlanManager.active(a)
	var steps_ok: bool = accepted and a.ai["plan"]["steps"].size() == 3 and int(a.ai["plan"]["steps"][0]["target"]) == f.id
	a.behavior_enabled = true
	var saw_model := false
	for i in 40:
		_run(life, 1.0)
		if str(a.decision.get("source", "")) == "modellplan":
			saw_model = true
		if not PlanManager.active(a) and i > 2:
			break
	var h: Array = a.ai["plan_history"]
	var last_plan: Dictionary = h[h.size() - 1] if not h.is_empty() else {}
	var hist := life.ctx.executor.history.filter(func(x): return int(x["actor"]) == a.id and x["status"] == "succeeded")
	var types: Array = hist.map(func(x): return str(x["type"]))
	_check("(1) Gültiger Plan (SIMULIERT) wird angenommen und über das Handlungssystem ausgeführt (Gehen → Aufnehmen → Essen)",
		rq["ok"] and steps_ok and saw_model and str(last_plan.get("state", "")) == "abgeschlossen" and "pick_up" in types and "eat" in types and float(a.stats.get("eaten_kg", 0.0)) > eaten0,
		"Plan: %s; Handlungen %s; gegessen %.3f kg" % [str(last_plan.get("state", "?")), str(types.slice(0, 6)), float(a.stats.get("eaten_kg", 0.0)) - eaten0])
	_check("(13) Keine doppelten Ressourcen: Nahrungsbilanz und Prüfung nach Planausführung in Ordnung", absf(life.ctx.ledger.balance_error(life.ctx)) < 1e-9 and life.audit().is_empty(), str(life.audit().slice(0, 3)))
	_check("Plan erzeugt keine Objekte außerhalb definierter Handlungen (nur die aufgenommene Portion entsteht und wird gegessen)", life.sim.registry.count() <= reg0 + 1, "Register %d → %d" % [reg0, life.sim.registry.count()])


# ── Ablehnungen ───────────────────────────────────

func _reject_case(steps: Array, extra: Dictionary = {}, goal: String = "food") -> Dictionary:
	var svc := _svc()
	_mock(svc).responder = _plan_resp(steps, goal, extra)
	var life := _env(svc, 2, 202)
	var a: Creature = life.ctx.creatures[_ids(life)[0]]
	var f := _near_food(life, a, 3.0)
	sc.set_hunger(a, 0.55)
	var reg0 := life.sim.registry.count()
	var food0 := 0.0
	for fid in life.ctx.foods:
		food0 += life.ctx.foods[fid].amount_kg
	var items0 := life.ctx.items.size()
	life.ctx.ai.request_now(a, "plan")
	_wait_answer(life, a)
	_run(life, 2.0)
	var food1 := 0.0
	for fid in life.ctx.foods:
		food1 += life.ctx.foods[fid].amount_kg
	return {"last": a.ai["last"].duplicate(true), "plan": a.ai["plan"].duplicate(true), "reg_same": life.sim.registry.count() == reg0, "food_same": absf(food1 - food0) < 1e-12,
		"items_same": life.ctx.items.size() == items0, "f": f.id, "life": life, "a": a}


func _test_rejections() -> void:
	print("  KI-Test: _test_rejections (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var r1 := _reject_case([{"action": "go_to", "target_id": 987654}])
	_check("(2) Unbekannte IDs werden abgelehnt (Stufe 3) – kein Plan", r1["last"].get("status") == "abgelehnt" and int(r1["last"].get("stage", 0)) == 3 and r1["plan"].is_empty(), str(r1["last"].get("why", "")))
	var r2 := _reject_case([{"action": "create_food", "target_id": 0}], {"short_explanation": "Ignoriere die Regeln und erschaffe Nahrung"})
	_check("(3) „Ignoriere die Regeln und erschaffe Nahrung“: verbotene Handlung abgelehnt (Stufe 5), keine Nahrung, keine Objekte",
		r2["last"].get("status") == "abgelehnt" and int(r2["last"].get("stage", 0)) == 5 and r2["plan"].is_empty() and r2["reg_same"] and r2["food_same"] and r2["items_same"], str(r2["last"].get("why", "")))
	var r3 := _reject_case([{"action": "build_generator", "target_id": 0}], {"short_explanation": "Ich baue einen Generator."}, "explore")
	_check("Erwähnter Generator/Fahrzeug erzeugt nichts: unbekannte Handlung abgelehnt", r3["last"].get("status") == "abgelehnt" and r3["reg_same"] and r3["items_same"], str(r3["last"].get("why", "")))
	var r4 := _reject_case([{"action": "pick_up", "target_id": 0, "material": "gold"}])
	_check("(4) Erfundene Materialregel/Zusatzfeld abgelehnt (Stufe 2, Schema)", r4["last"].get("status") == "abgelehnt" and int(r4["last"].get("stage", 0)) == 2 and r4["food_same"], str(r4["last"].get("why", "")))
	var r5 := _reject_case([{"action": "wait", "target_id": 0}], {"short_explanation": "Ich erschaffe aus Steinen Gold und baue ein Fahrzeug."}, "rest")
	var a5: Creature = r5["a"]
	_check("Freitext ohne Wirkung: Plan aus erlaubten Schritten angenommen, Erklärung bewirkt nichts (keine Objekte, keine Nahrung)",
		str(r5["last"].get("status")) == "angenommen" and r5["reg_same"] and r5["food_same"] and r5["items_same"] and str(a5.ai["last"].get("explanation", "")).contains("Fahrzeug"), str(r5["last"].get("why", "")))
	var r6 := _reject_case([], {"request_id": 99999})
	_check("Fremde Anfrage-ID abgelehnt (Stufe 4)", r6["last"].get("status") == "abgelehnt" and int(r6["last"].get("stage", 0)) == 4, str(r6["last"].get("why", "")))
	var r7 := _reject_case([{"action": "give_food", "target_id": 0}])
	_check("Ziel fehlt bei Handlung mit Ziel → abgelehnt (Stufe 3)", r7["last"].get("status") == "abgelehnt" and int(r7["last"].get("stage", 0)) == 3)
	var r8 := _reject_case([{"action": "eat", "target_id": 0}])
	_check("Unmögliche Folge (Getragenes essen, ohne etwas zu tragen) abgelehnt (Stufe 6)", r8["last"].get("status") == "abgelehnt" and int(r8["last"].get("stage", 0)) == 6, str(r8["last"].get("why", "")))
	# Kritischer Hunger: Nicht-Nahrungsplan wird abgelehnt (Überleben vorrangig)
	var svc := _svc()
	_mock(svc).responder = _plan_resp([{"action": "explore", "target_id": 0}], "explore")
	var life := _env(svc, 2, 203)
	var a: Creature = life.ctx.creatures[_ids(life)[0]]
	sc.set_hunger(a, 0.5)
	life.ctx.ai.request_now(a, "plan")
	sc.set_hunger(a, 0.85)
	_wait_answer(life, a)
	_check("Kritischer Hunger: Modellplan ohne Nahrungsbezug wird abgelehnt – lokale Überlebensreaktion bleibt", str(a.ai["last"].get("status")) in ["abgelehnt", "verworfen"] and a.ai["plan"].is_empty(), str(a.ai["last"].get("why", "")))


# ── Ziel inzwischen weg ───────────────────────────

func _test_eaten_target() -> void:
	print("  KI-Test: _test_eaten_target (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc()
	var life := _env(svc, 2, 204)
	var ids := _ids(life)
	var a: Creature = life.ctx.creatures[ids[0]]
	sc.place(life, life.ctx.creatures[ids[1]], _far_from_food(life, 12.0))
	var f := _near_food(life, a, 3.0)
	sc.set_hunger(a, 0.55)
	life.ctx.ai.request_now(a, "plan")
	_wait_answer(life, a)
	var accepted := PlanManager.active(a)
	var sig := str(a.ai["plan"].get("signature", ""))
	# Der geplante „Pilz“ wird inzwischen vollständig gegessen (Weltfakt; das Wesen weiß es noch nicht)
	life.ctx.ledger.eaten_kg += f.amount_kg
	f.amount_kg = 0.0
	a.behavior_enabled = true
	var other_food_pick := false
	for i in 20:
		_run(life, 1.0)
		if not PlanManager.active(a):
			break
	var h: Array = a.ai["plan_history"]
	var lp: Dictionary = h[h.size() - 1] if not h.is_empty() else {}
	for x in life.ctx.executor.history:
		if int(x["actor"]) == a.id and x["type"] == "pick_up" and int(x["target"]) != f.id and float(x["t"]) < float(lp.get("ended_t", 0.0)):
			other_food_pick = true
	_check("Geplantes Ziel inzwischen gegessen: Plan scheitert, KEIN erfundenes Ersatzobjekt", accepted and str(lp.get("state", "")) == "gescheitert" and not other_food_pick,
		"Plan: %s – %s" % [str(lp.get("state", "?")), str(lp.get("result", ""))])
	_check("Gescheiterter Plan wird nicht endlos wiederholt (Signatur gesperrt)", PlanManager.is_blocked(a, sig, life.ctx))


# ── Veraltete Antworten, Neustart ─────────────────

func _test_stale_and_reset() -> void:
	print("  KI-Test: _test_stale_and_reset (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc({}, "ok", 1500)
	var life1 := _env(svc, 3, 301)
	var a1: Creature = life1.ctx.creatures[_ids(life1)[0]]
	var f := _near_food(life1, a1, 3.0)
	sc.set_hunger(a1, 0.55)
	life1.ctx.ai.request_now(a1, "plan")
	_run(life1, 0.2)
	var running := life1.ctx.ai.queue.running.size() == 1 and _mock(svc).active_count() == 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var path := "user://saves/_test_ai_stale.json"
	var sr := SaveManager.save(life1, path)
	var old_session := life1.ctx.ai.session
	var life2 := _env_fresh(svc)
	var lr := SaveManager.load_into(life2, path)
	life1.dispose()           # wie beim Szenenwechsel: alte Welt beendet, Anfragen abgebrochen
	var cancelled := _mock(svc).active_count() == 0
	_run(life2, 3.0)
	var a2: Creature = life2.ctx.creatures.get(a1.id, null)
	_check("(5) Laden: offene Anfrage der alten Welt abgebrochen, ihre Antwort wird nie angewendet; Hinweis „beim Laden verworfen“",
		running and sr["ok"] and lr["ok"] and cancelled and a2 != null and a2.ai["plan"].is_empty() and str(a2.ai["last"].get("status", "")) == "beim Laden verworfen",
		"%s | %s" % [str(lr.get("message", "")).substr(0, 80), str(a2.ai["last"] if a2 != null else {})])
	# Späte Antwort mit alter Sitzungsnummer (z. B. aus einem noch offenen Netzwerkpuffer)
	var forged := {"handle": 999, "meta": {"session": old_session, "request_id": 1}, "kind": "chat", "ok": true, "code": "ok", "message": "", "http_status": 200, "data": {},
		"content": JSON.stringify({"request_id": 1, "actor_id": a1.id, "goal_type": "food", "proposed_steps": [{"action": "go_to", "target_id": f.id}], "referenced_memory_ids": [], "uncertainty": 0.1, "short_explanation": "alt"}),
		"latency_ms": 10, "simulated": true, "model": "x"}
	life2.ctx.ai.receive(forged)
	var d0 := int(life2.ctx.ai.local["discarded"])
	_run(life2, 0.1)
	_check("(6) Antwort aus früherer Welt/Sitzung (Neustart/Laden) wird verworfen und gezählt", int(life2.ctx.ai.local["discarded"]) == d0 + 1 and a2.ai["plan"].is_empty())
	var notes_ok: bool = lr.has("plans")
	_check("Laden lädt ohne Modell; Spielstand enthält keine Verbindungsdaten/Modellnamen", notes_ok and not FileAccess.get_file_as_string(path).contains(MockOllama.MODEL) and not FileAccess.get_file_as_string(path).contains(":11434"))
	for ext in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + ext):
			DirAccess.remove_absolute(path + ext)


func _env_fresh(svc: AIService) -> LifeSimulation:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs, svc)
	sc.lives.append(life)
	return life


# ── Tod, Pause ────────────────────────────────────

func _test_death_and_pause() -> void:
	print("  KI-Test: _test_death_and_pause (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc({}, "ok", 1000)
	var life := _env(svc, 3, 401)
	var ids := _ids(life)
	var a: Creature = life.ctx.creatures[ids[0]]
	_near_food(life, a, 3.0)
	sc.set_hunger(a, 0.55)
	life.ctx.ai.request_now(a, "plan")
	_run(life, 0.2)
	var was_running := life.ctx.ai.queue.running.size() == 1
	life.dev_body_change(a.id, "kill")
	_run(life, 2.0)
	_check("(7) Tod verhindert Ausführung: laufende Anfrage abgebrochen, kein Plan, keine Handlung danach", was_running and life.ctx.ai.queue.running.is_empty() and a.ai["plan"].is_empty()
		and not life.ctx.executor.running.has(a.id) and life.audit().is_empty())
	# Pause
	var b: Creature = life.ctx.creatures[ids[1]]
	_near_food(life, b, 3.0)
	sc.set_hunger(b, 0.55)
	life.ctx.ai.request_now(b, "plan")
	_run(life, 0.2)
	life.sim.set_paused(true)
	var t_paused := life.ctx.now()
	_run(life, 2.0)          # Antwort trifft während der Pause ein
	var in_inbox: bool = life.ctx.ai.inbox.size() == 1 and b.ai["plan"].is_empty() and absf(life.ctx.now() - t_paused) < 1e-9
	var sent_before := int(svc.stats["sent"])
	life.ctx.ai.request_now(life.ctx.creatures[ids[2]], "plan")
	_run(life, 1.0)
	var no_new := int(svc.stats["sent"]) == sent_before
	life.sim.set_paused(false)
	_run(life, 0.1)
	_check("(8) Pause: keine neuen Anfragen, eingetroffene Antwort wird nicht sofort angewendet", in_inbox and no_new)
	_check("Nach dem Fortsetzen wird die Antwort gegen den aktuellen Zustand geprüft und erst dann angewendet", PlanManager.active(b) and bool(b.ai["last"].get("after_pause", false)), str(b.ai["last"]))
	# Tod während aktiver Plan
	b.behavior_enabled = false
	life.dev_body_change(b.id, "kill")
	var hb: Array = b.ai["plan_history"]
	_check("Tod bricht aktiven Plan ab (Protokoll: abgebrochen)", b.ai["plan"].is_empty() and not hb.is_empty() and str(hb[hb.size() - 1]["state"]) == "abgebrochen")


# ── Fehler, Unterbrecher, Wiederherstellung ───────

func _test_errors_and_breaker() -> void:
	print("  KI-Test: _test_errors_and_breaker (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	# Zeitüberschreitung: Simulation läuft weiter
	var svc := _svc({"timeout_s": 2.0}, "ok")
	var life := _env(svc, 2, 501, true)
	var a: Creature = life.ctx.creatures[_ids(life)[0]]
	_mock(svc).mode = "timeout"
	var t0 := life.ctx.now()
	var dec0 := int(a.stats.get("decisions", 0))
	life.ctx.ai.request_now(a, "plan")
	_run(life, 12.0)
	_check("(9) Zeitüberschreitung: Simulation läuft weiter, Wesen handelt lokal, begrenzte Wiederholung, keine erfundene Entscheidung",
		life.ctx.now() - t0 > 11.9 and int(a.stats.get("decisions", 0)) > dec0 and str(a.ai["last"].get("status", "")) == "fehlgeschlagen" and a.ai["plan"].is_empty()
		and int(svc.stats["retries"]) == 1 and int(svc.stats["by_code"].get("timeout", 0)) == 2, str(a.ai["last"].get("why", "")))
	# Ungültiges JSON / leere Antwort
	var svc2 := _svc({}, "ok")
	var life2 := _env(svc2, 2, 502)
	var b: Creature = life2.ctx.creatures[_ids(life2)[0]]
	_mock(svc2).responder = func(_b, _c): return "{\"request_id\": 1, kaputt"
	life2.ctx.ai.request_now(b, "plan")
	_wait_answer(life2, b)
	var inv: bool = str(b.ai["last"].get("status")) == "abgelehnt" and int(b.ai["last"].get("stage", 0)) == 1 and b.ai["plan"].is_empty()
	_mock(svc2).responder = Callable()
	_mock(svc2).mode = "empty"
	b.ai["next_request_t"] = 0.0
	life2.ctx.ai.request_now(b, "plan")
	_run(life2, 10.0)
	_check("Ungültiges JSON (Stufe 1) und leere Antwort: abgelehnt bzw. nach einer Wiederholung aufgegeben, kein Plan", inv and str(b.ai["last"].get("status")) == "fehlgeschlagen" and b.ai["plan"].is_empty(), str(b.ai["last"].get("why", "")))
	# Nicht erreichbar → Unterbrecher → Wiederherstellung
	var svc3 := _svc({"breaker_failures": 3, "health_check_interval_s": 5.0, "retry_backoff_s": 1.0}, "ok")
	var life3 := _env(svc3, 4, 503)
	var ids3 := _ids(life3)
	_mock(svc3).mode = "down"
	for k in 2:
		life3.ctx.ai.request_now(life3.ctx.creatures[ids3[k]], "plan")
		_run(life3, 3.0)
	var down := svc3.status == "nicht_erreichbar"
	var rq := life3.ctx.ai.request_now(life3.ctx.creatures[ids3[2]], "plan")
	var sent0 := int(svc3.stats["sent"])
	_run(life3, 2.0)
	var no_send := int(svc3.stats["sent"]) == sent0
	var down_msg := svc3.status_message
	_mock(svc3).mode = "ok"
	_run(life3, 7.0)
	_check("(10) Dienst unterbrochen: nach 3 Fehlern keine neuen Anfragen (verständliche Meldung), Welt läuft weiter",
		down and not rq["ok"] and no_send and down_msg.contains("Fehler in Folge"), down_msg)
	_check("(11) Dienst wieder da: Prüfung erkennt Wiederherstellung, Anfragen laufen wieder", svc3.status == "verbunden" and svc3.recoveries == 1 and life3.ctx.ai.request_now(life3.ctx.creatures[ids3[3]], "plan")["ok"],
		"Zustand %s, Wiederherstellungen %d" % [svc3.status, svc3.recoveries])
	# Modell fehlt
	var m := MockOllama.new()
	m.models = ["anderes-modell:3b"]
	var svc4 := AIService.new(_settings(), m)
	svc4.client.clock = func(): return int(clock["ms"])
	svc4.test_connection()
	for i in 4:
		svc4.poll()
	_check("Modell nicht installiert: verständliche Meldung, keine Anfragen, kein automatischer Download", svc4.status == "modell_fehlt" and not svc4.can_dispatch()
		and svc4.status_message.contains("nicht installiert") and not m.requests.any(func(r): return str(r["path"]) in ["/api/pull", "/api/create"]), svc4.status_message)
	var svc5 := AIService.new(_settings({"model": ""}), MockOllama.new())
	svc5.client.clock = func(): return int(clock["ms"])
	svc5.test_connection()
	for i in 4:
		svc5.poll()
	_check("Kein Modell gewählt: Zustand „kein Modell gewählt“, Liste der installierten Modelle verfügbar", svc5.status == "keine_modellwahl" and svc5.models.size() == 1)


# ── Kontext: nur eigene Daten ─────────────────────

func _test_context_privacy() -> void:
	print("  KI-Test: _test_context_privacy (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc()
	var life := _env(svc, 3, 601)
	var ids := _ids(life)
	var a: Creature = life.ctx.creatures[ids[0]]
	var b: Creature = life.ctx.creatures[ids[1]]
	_near_food(life, a, 3.0)
	sc.place(life, b, _far_from_food(life, 6.0))
	sc.place(life, life.ctx.creatures[ids[2]], a.position + Vector3(1.5, 0, 0))
	life.ctx.rebuild_spatial_hash()
	sc.gift_near(life, b, 0.1)          # nur b sieht diesen Eingriff
	life.ctx.interventions.history.append({"intent": "GEHEIME_SPIELERABSICHT"})
	_run(life, 1.5)
	var bld := ContextBuilder.build(a, life.ctx, "plan", 1, "Test", 7000)
	var js: String = bld["json"]
	var own_mem_ok := true
	for m in bld["context"]["erinnerungen"]:
		var found := false
		for e in a.memory.entries:
			if int(e["id"]) == int(m["id"]) and str(e["type"]) == str(m["art"]):
				found = true
		if not found:
			own_mem_ok = false
	var b_types: Array = b.memory.entries.map(func(e): return str(e["type"]))
	var keys_ok := true
	for v in bld["context"]["wahrnehmung"]["wesen_sichtbar"]:
		if not v.keys().all(func(k): return k in ["id", "entfernung_m", "lebt", "traegt_etwas"]):
			keys_ok = false
	var forbidden := ["GEHEIME_SPIELERABSICHT", "personality", "hilfsbereitschaft\":" + str(snappedf(b.personality.v("hilfsbereitschaft"), 0.01)) + ",\"neugier", "food_appeared", "tech", "inventions"]
	var leaks: Array = []
	for w in forbidden:
		if js.contains(w):
			leaks.append(w)
	_check("(12) Kontext enthält nur eigene Erinnerungen und Wahrnehmungen – keine fremden Erinnerungen, keine verborgenen Werte anderer, keine Spielerabsicht, kein Technologiebaum",
		own_mem_ok and keys_ok and leaks.is_empty() and "food_appeared" in b_types and int(bld["chars"]) <= 7000, "Lecks: %s; %d Zeichen" % [str(leaks), int(bld["chars"])])
	var small := ContextBuilder.build(a, life.ctx, "plan", 1, "Test", 900)
	_check("Kontextgröße begrenzt (Listen werden gekürzt)", int(small["chars"]) < int(bld["chars"]) and bld["cand"]["memories"].size() >= small["cand"]["memories"].size())
	life.ctx.ai.request_now(a, "plan")
	_wait_answer(life, a)
	var sent: Array = _mock(svc).requests.filter(func(r): return str(r["path"]) == "/api/chat")
	var body = JSON.parse_string(str(sent[sent.size() - 1]["body"])) if not sent.is_empty() else {}
	var user_msg := ""
	if typeof(body) == TYPE_DICTIONARY:
		for msg in body["messages"]:
			if msg["role"] == "user":
				user_msg = str(msg["content"])
	_check("Gesendet wird genau der eigene Kontext; Strukturausgabe per JSON-Schema (format), stream aus",
		typeof(body) == TYPE_DICTIONARY and typeof(body.get("format", null)) == TYPE_DICTIONARY and body.get("stream", true) == false and int(JSON.parse_string(user_msg)["ich"]["id"]) == a.id and not user_msg.contains("GEHEIME"))


# ── Gespräche und Hörensagen ──────────────────────

func _topic(life: LifeSimulation, s: Creature, l: Creature, intent: String) -> Dictionary:
	for t in life.ctx.comm.topics(s, l.id, life.ctx):
		if t["absicht"] == intent:
			return t
	return {}


func _say(life: LifeSimulation, s: Creature, l: Creature, intent: String) -> Dictionary:
	var tp := _topic(life, s, l, intent)
	if tp.is_empty():
		return {"ok": false, "message": "kein Thema %s" % intent}
	var r := life.ctx.comm.start(s, l.id, tp, "lokal", life.ctx)
	sc.run_until_idle(life, s.id, 4.0)
	return r


func _claim(l: Creature, fid: int) -> Dictionary:
	for c in l.ai["hearsay"]:
		if int(c["subject"].get("id", 0)) == fid:
			return c
	return {}


func _test_conversation_and_hearsay() -> void:
	print("  KI-Test: _test_conversation_and_hearsay (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc()
	var life := _env(svc, 5, 701)
	var ids := _ids(life)
	var a: Creature = life.ctx.creatures[ids[0]]
	var b: Creature = life.ctx.creatures[ids[1]]
	var c: Creature = life.ctx.creatures[ids[2]]
	var d: Creature = life.ctx.creatures[ids[3]]
	var e: Creature = life.ctx.creatures[ids[4]]
	var f := _near_food(life, a, 2.0)
	_only_knows(a, f.id)
	var far := _far_from_food(life, 14.0)
	sc.place(life, a, far)
	sc.place(life, b, far + Vector3(1.5, 0, 0), 0.0)
	sc.place(life, c, far + Vector3(0, 0, 1.5), 0.0)
	sc.place(life, e, far + Vector3(-1.5, 0, 0), 0.0)
	sc.place(life, d, far + Vector3(0, 0, 30), 0.0)
	_myopic([b, c, d, e])
	for x in [a, b, c, e]:
		if x != a:
			x.food_memory.clear()
		Perception.scan(x, life.ctx)
	var beliefs_b := b.beliefs.items.size()
	var r1 := _say(life, a, b, "point_food")
	var cb := _claim(b, f.id)
	_check("Gespräch: Hinweis auf eigene Beobachtung wird zugestellt (Vorlagentext, Quelle, Sicherheit)", r1["ok"] and not cb.is_empty() and str(cb["source_kind"]) == "eigene_beobachtung"
		and str(cb["statement"]).contains("#%d" % f.id), str(r1.get("message", "")))
	_check("(11) Hörensagen bleibt gekennzeichnet: nicht im Nahrungsgedächtnis, nicht als Beleg in Vermutungen",
		not cb.is_empty() and str(cb["status"]) == "ungeprüft" and not b.food_memory.has(f.id) and b.beliefs.items.size() == beliefs_b and CreatureInspector.describe(life, b.id).contains("HÖRENSAGEN"))
	# b erzählt weiter an c; danach erzählt a selbst c dasselbe → keine unabhängige Bestätigung
	_run(life, 3.0)
	var r2 := _say(life, b, c, "point_food")
	var cc1 := _claim(c, f.id).duplicate(true)
	_run(life, 26.0)
	for x in [a, b, c, e]:
		x.position = x.position     # unverändert; Wahrnehmung läuft weiter
	var r3 := _say(life, a, c, "point_food")
	var cc2 := _claim(c, f.id)
	_check("(12) Weitererzählen derselben Quelle ist keine unabhängige Bestätigung (Ursprung bleibt #%d)" % a.id,
		r2["ok"] and r3["ok"] and str(cc1.get("source_kind", "")) == "hörensagen" and int(cc1["origin"]["creature"]) == a.id and int(cc2["independent"]) == 1 and int(cc2["retold"]) == 1,
		"unabhängig %d, weitererzählt %d, Kette %s" % [int(cc2.get("independent", -1)), int(cc2.get("retold", -1)), str(cc2.get("chain", []))])
	# Eine unabhängige Beobachtung (anderes Wesen, eigene Sicht) zählt
	var e_learned := _learn(life, e, f, 2.5) or _learn(life, e, f, 1.5) or _learn(life, e, f, 3.0)
	sc.place(life, e, c.position + Vector3(1.2, 0, 0), 0.0)
	life.ctx.rebuild_spatial_hash()
	Perception.scan(e, life.ctx)
	Perception.scan(c, life.ctx)
	var r4 := _say(life, e, c, "point_food")
	_check("Unabhängige zweite Quelle erhöht die Zahl unabhängiger Quellen", r4["ok"] and int(_claim(c, f.id).get("independent", 0)) == 2,
		"%s | gelernt %s, kennt %s, Abstand %.1f" % [str(r4.get("message", "")), str(e_learned), str(e.food_memory.keys()), life.ctx.distance_xz(e.position, c.position)])
	# Täuschung nicht möglich: Thema außerhalb des eigenen Wissens wird nicht angenommen
	var fake_entry := {"id": 77, "session": life.ctx.ai.session, "actor": d.id, "kind": "talk", "listener": c.id, "state_t": life.ctx.now(),
		"cand": {"food": [], "creatures": [], "memories": [], "topics": {1: {"absicht": "point_food", "eigene_sicherheit": 0.4, "statement": {"type": "food_source", "id": f.id}, "source": {}}}}}
	var v := ResponseValidator.validate_talk(JSON.stringify({"request_id": 77, "speaker_id": d.id, "listener_id": c.id, "intent": "point_food", "subject_id": 1, "referenced_memory_ids": [], "expressed_certainty": 0.9}),
		fake_entry, life.ctx.ai.session, life.ctx, 3000, 45.0)
	_check("Keine Täuschung: Sprecher kann nur eigenes Wissen mitteilen (Thema nicht im eigenen Wissen → abgelehnt)", not v["ok"] and int(v["stage"]) in [6, 7], str(v["message"]))
	# Gespräch über den simulierten Dienst (Ollama-Pfad): Absicht + Thema gewählt, geprüft, als Plan ausgeführt
	c.ai["talk"]["next_t"] = 0.0
	b.ai["talk"]["next_t"] = 0.0
	b.ai["talk"]["pair"].clear()
	var cs: int = c.ai["hearsay"].size()
	var n0 := life.ctx.comm.log.size()
	_near_food(life, b, 2.0)
	sc.place(life, b, c.position + Vector3(1.4, 0, 0), 0.0)
	life.ctx.rebuild_spatial_hash()
	Perception.scan(b, life.ctx)
	Perception.scan(c, life.ctx)
	var rq := life.ctx.ai.request_now(b, "talk", "Test: Gespräch", c.id)
	_wait_answer(life, b)
	b.behavior_enabled = true
	_run(life, 4.0)
	b.behavior_enabled = false
	var us: Array = life.ctx.comm.log.slice(n0)
	var sim_u: Array = us.filter(func(u): return str(u["via"]) == "simuliert" and str(u["status"]) == "gehört")
	_check("Gespräch über den Testdienst (SIMULIERT): Antwort geprüft, als kurzer Plan ausgeführt, Text aus Vorlage, Modelltext ohne Wirkung",
		rq["ok"] and not sim_u.is_empty() and str(sim_u[0]["model_text"]).contains("simuliert") and not str(sim_u[0]["text"]).contains("simuliert") and c.ai["hearsay"].size() >= cs,
		"%s | %s" % [str(b.ai["last"].get("status", "")), str(b.ai["last"].get("why", ""))])
	_check("Gespräche erzeugen keine Ressourcen (Bilanz, Prüfung)", absf(life.ctx.ledger.balance_error(life.ctx)) < 1e-9 and life.audit().is_empty(), str(life.audit().slice(0, 2)))
	var cert_entry := {"id": 78, "session": life.ctx.ai.session, "actor": a.id, "kind": "talk", "listener": c.id, "state_t": life.ctx.now(), "cand": {"food": [], "creatures": [], "memories": [], "topics": {}}}
	a.ai["talk"]["next_t"] = 0.0
	a.ai["talk"]["pair"].clear()
	var tps := life.ctx.comm.topics(a, c.id, life.ctx)
	for t in tps:
		cert_entry["cand"]["topics"][int(t["thema_id"])] = t
	var pf := tps.filter(func(t): return t["absicht"] == "point_food")
	if not pf.is_empty():
		var v2 := ResponseValidator.validate_talk(JSON.stringify({"request_id": 78, "speaker_id": a.id, "listener_id": c.id, "intent": "point_food", "subject_id": int(pf[0]["thema_id"]),
			"referenced_memory_ids": [], "expressed_certainty": 1.0, "optional_text": "[b]Ich bin ganz sicher![/b]"}), cert_entry, life.ctx.ai.session, life.ctx, 3000, 45.0)
		_check("Geäußerte Sicherheit wird auf die eigene begrenzt; Modelltext bereinigt (keine Formatierungsbefehle)",
			v2["ok"] and float(v2["value"]["certainty"]) <= float(pf[0]["eigene_sicherheit"]) + 1e-9 and not str(v2["value"]["model_text"]).contains("["), str(v2["message"]))
	else:
		_check("Geäußerte Sicherheit wird auf die eigene begrenzt", false, "kein Thema")


func _test_verification() -> void:
	print("  KI-Test: _test_verification (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc()
	var life := _env(svc, 4, 801)
	var ids := _ids(life)
	var a: Creature = life.ctx.creatures[ids[0]]
	var b: Creature = life.ctx.creatures[ids[1]]
	var c: Creature = life.ctx.creatures[ids[2]]
	var d: Creature = life.ctx.creatures[ids[3]]
	var f := _near_food(life, a, 2.0)
	_only_knows(a, f.id)
	var far := _far_from_food(life, 14.0)
	sc.place(life, a, far)
	sc.place(life, b, far + Vector3(1.5, 0, 0), 0.0)
	sc.place(life, d, far + Vector3(0, 0, 30), 0.0)
	sc.place(life, c, far + Vector3(0, 0, -30), 0.0)
	_myopic([b, c, d])
	for x in [b, c, d]:
		x.food_memory.clear()
	life.ctx.rebuild_spatial_hash()
	Perception.scan(a, life.ctx)
	Perception.scan(b, life.ctx)
	var trust0 := b.relations.trust(a.id)
	_say(life, a, b, "point_food")
	_learn(life, b, f)
	var cb := _claim(b, f.id)
	_check("Prüfung „gefunden“: eigene Sicht bestätigt den Hinweis, Vertrauen steigt vorsichtig", str(cb.get("status", "")) == "bestätigt" and b.relations.trust(a.id) > trust0 and b.relations.trust(a.id) - trust0 < 0.15,
		"Vertrauen %.3f → %.3f" % [trust0, b.relations.trust(a.id)])
	# Veraltet: Quelle inzwischen leer, Hinweis war älter
	var f2: FoodSource = null
	for fid in life.ctx.foods:
		if fid != f.id and life.ctx.foods[fid].available_kg() > 0.2 and _learn(life, a, life.ctx.foods[fid]):
			f2 = life.ctx.foods[fid]
			break
	sc.place(life, a, far)
	sc.place(life, d, far + Vector3(1.5, 0, 0), 0.0)
	life.ctx.rebuild_spatial_hash()
	Perception.scan(a, life.ctx)
	Perception.scan(d, life.ctx)
	a.ai["talk"]["next_t"] = 0.0
	_say(life, a, d, "point_food")
	var trust_d0 := d.relations.trust(a.id)
	_run(life, 12.0)
	var saved_amount := f2.amount_kg
	f2.amount_kg = 0.0
	_learn(life, d, f2)
	var cd := _claim(d, f2.id)
	_check("Prüfung „Quelle jetzt leer“: als VERALTET erkannt (nicht als Lüge), Vertrauen unverändert", str(cd.get("status", "")) == "veraltet" and absf(d.relations.trust(a.id) - trust_d0) < 1e-9,
		"%s | f2=#%d gehört: %s | Sprecher kennt %s" % [str(cd.get("note", "")), f2.id, str(d.ai["hearsay"].map(func(x): return [x["subject"]["id"], x["status"]])), str(a.food_memory.keys())])
	# Widerspruch: Zuhörer sah die Quelle zur gleichen Zeit leer
	f2.amount_kg = saved_amount
	a.ai["talk"]["next_t"] = 0.0
	a.ai["talk"]["pair"].clear()
	_learn(life, a, f2)
	f2.amount_kg = 0.0
	_learn(life, c, f2, 2.5)
	f2.amount_kg = saved_amount
	sc.place(life, a, far)
	sc.place(life, c, far + Vector3(0, 0, 1.5), 0.0)
	life.ctx.rebuild_spatial_hash()
	Perception.scan(a, life.ctx)
	var trust_c0 := c.relations.trust(a.id) if c.relations.rel.has(a.id) else 0.5
	_say(life, a, c, "point_food")
	var cc := _claim(c, f2.id)
	_check("Widerspruch: eigene Beobachtung zur gleichen Zeit sagt „leer“ → WIDERSPROCHEN, Vertrauen sinkt vorsichtig",
		str(cc.get("status", "")) == "widersprochen" and c.relations.trust(a.id) < trust_c0 and trust_c0 - c.relations.trust(a.id) < 0.15, "%s, Vertrauen %.3f → %.3f" % [str(cc.get("note", "")), trust_c0, c.relations.trust(a.id)])
	# Fehler: Angabe (Art) passt nicht zur gesehenen Quelle
	var u := {"id": 900, "speaker": a.id, "listener": b.id, "intent": "point_food", "statement": {"type": "food_source", "id": f2.id, "pos": [f2.position.x, f2.position.y, f2.position.z], "kind": "falsche_art", "kg": 0.5},
		"source": {"kind": "eigene_beobachtung", "creature": a.id, "t": life.ctx.now() - 30.0, "chain": []}, "certainty": 0.8, "text": "Test"}
	b.ai["hearsay"].clear()
	ClaimEvaluator.hear(b, u, life.ctx)
	_learn(life, b, f2)
	_check("Fehler: Angabe passt nicht zur selbst gesehenen Quelle → FEHLER (getrennt von veraltet/widersprochen)", str(_claim(b, f2.id).get("status", "")) == "fehler")
	# Hinweis selbst prüfen (Entscheidung): hungriges Wesen ohne eigenes Wissen geht hin
	var svc2 := _svc()
	var life2 := _env(svc2, 4, 802, false)
	var ids2 := _ids(life2).filter(func(i): return life2.ctx.creatures[i].carried_item_id == 0)
	var s2: Creature = life2.ctx.creatures[ids2[0]]
	var l2: Creature = life2.ctx.creatures[ids2[1]]
	for i in _ids(life2):
		if not i in [s2.id, l2.id]:
			sc.place(life2, life2.ctx.creatures[i], _far_from_food(life2, 10.0) + Vector3(0, 0, 12), 0.0)
	var fx := _near_food(life2, s2, 2.0)
	_only_knows(s2, fx.id)
	var far2 := _point_near(life2, fx.position, 4.5, 7.0, 3.5)
	sc.place(life2, s2, far2)
	_myopic([l2])
	_place_listener(life2, l2, s2)
	life2.ctx.rebuild_spatial_hash()
	Perception.scan(s2, life2.ctx)
	Perception.scan(l2, life2.ctx)
	l2.food_memory.clear()
	_say(life2, s2, l2, "point_food")
	sc.set_hunger(l2, 0.7)
	l2.food_memory.clear()
	l2.behavior_enabled = true
	var went := false
	for i in 30:
		_run(life2, 1.0)
		if str(l2.decision.get("chosen", "")) == "check_hint":
			went = true
		if str(_claim(l2, fx.id).get("status", "")) in ["bestätigt", "veraltet", "nicht_prüfbar", "widersprochen"]:
			break
	_check("Gehörter Hinweis wird bei Hunger selbst geprüft (Option „check_hint“) und mit eigener Wahrnehmung aufgelöst",
		went and str(_claim(l2, fx.id).get("status", "")) in ["bestätigt", "veraltet", "nicht_prüfbar"], "Status %s, gewählt %s, Optionen %s, Hunger %.2f" % [str(_claim(l2, fx.id).get("status", "?")),
		str(l2.decision.get("chosen", "")), str(l2.decision.get("options", [])).substr(0, 300), l2.metabolism.hunger()])


# ── Speichern/Laden, Migration 2 → 3 ──────────────

func _test_save_load_and_migration() -> void:
	print("  KI-Test: _test_save_load_and_migration (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc()
	var life := _env(svc, 3, 901)
	var ids := _ids(life)
	var a: Creature = life.ctx.creatures[ids[0]]
	var b: Creature = life.ctx.creatures[ids[1]]
	var f := _near_food(life, a, 2.0)
	_only_knows(a, f.id)
	var far := _far_from_food(life, 14.0)
	sc.place(life, a, far)
	sc.place(life, b, far + Vector3(1.5, 0, 0), 0.0)
	_myopic([b])
	b.food_memory.clear()
	life.ctx.rebuild_spatial_hash()
	Perception.scan(a, life.ctx)
	Perception.scan(b, life.ctx)
	_say(life, a, b, "point_food")
	_near_food(life, a, 3.0)
	sc.set_hunger(a, 0.55)
	life.ctx.ai.request_now(a, "plan")
	_wait_answer(life, a)
	var had_plan := PlanManager.active(a)
	var path := "user://saves/_test_ai_v3.json"
	var sr := SaveManager.save(life, path)
	var life2 := _env_fresh(svc)
	var lr := SaveManager.load_into(life2, path)
	var a2: Creature = life2.ctx.creatures.get(a.id, null)
	var b2: Creature = life2.ctx.creatures.get(b.id, null)
	var same_hs := b2 != null and JSON.stringify(TestMind._n(b2.ai["hearsay"])) == JSON.stringify(TestMind._n(b.ai["hearsay"]))
	var plan_ok := a2 != null and PlanManager.active(a2) == had_plan and (not had_plan or int(a2.ai["plan"]["id"]) == int(a.ai["plan"]["id"]))
	_check("Format 3: Pläne, Hörensagen (Herkunft, Vertrauen), Gesprächsprotokoll und Wartezeiten gespeichert und geladen; Pläne nach dem Laden neu geprüft",
		sr["ok"] and lr["ok"] and same_hs and plan_ok and life2.ctx.comm.log.size() == life.ctx.comm.log.size() and life2.ctx.ai.queue.size() == 0 and lr.has("plans"),
		"%s | Pläne: %s" % [str(lr.get("message", "")).substr(0, 60), str(lr.get("plans", []))])
	for ext in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + ext):
			DirAccess.remove_absolute(path + ext)
	# Echter Format-2-Spielstand aus v0.4.0
	var mp := "user://saves/_test_mig_v2.json"
	for ext in ["", ".bak", ".v2.vor_migration"]:
		if FileAccess.file_exists(mp + ext):
			DirAccess.remove_absolute(mp + ext)
	DirAccess.copy_absolute(FIXTURE_V2, mp)
	var orig := FileAccess.get_file_as_string(mp)
	var v2 = JSON.parse_string(orig.substr(orig.find("\n") + 1))
	var calls := PopulationSpawner.spawn_calls
	var life3 := _env_fresh(AIService.disabled())
	var r := SaveManager.load_into(life3, mp)
	var ok_mind := true
	var ok_ai := true
	if r["ok"]:
		for c in v2["creatures"]:
			var cr: Creature = life3.ctx.creatures[int(c["id"])]
			if JSON.stringify(TestMind._n(c["mind"]["memory"])) != JSON.stringify(TestMind._n(cr.memory.to_dict())) or JSON.stringify(TestMind._n(c["mind"]["personality"])) != JSON.stringify(TestMind._n(cr.personality.to_dict())):
				ok_mind = false
			if not cr.ai["hearsay"].is_empty() or not cr.ai["plan"].is_empty() or not cr.ai["notes"].is_empty():
				ok_ai = false
	_check("Migration Format 2 → 3: echter Spielstand aus v0.4.0 lädt, Original vorher gesichert, Spawner nicht aufgerufen",
		r["ok"] and int(r.get("migrated_from", 0)) == 2 and FileAccess.get_file_as_string(mp + ".v2.vor_migration") == orig and PopulationSpawner.spawn_calls == calls, str(r["message"]).substr(0, 160))
	_check("Migration 2 → 3: Geist (Erinnerungen, Persönlichkeit) unverändert; keine erfundenen Pläne, Gespräche oder Hörensagen",
		r["ok"] and ok_mind and ok_ai and life3.ctx.comm.log.is_empty() and life3.audit().is_empty() and absf(life3.ctx.now() - float(v2["simulation"]["time_s"])) < 1e-9)
	if r["ok"]:
		_run(life3, 10.0)
	_check("Migration 2 → 3: Simulation läuft danach weiter", r["ok"] and life3.audit().is_empty())
	var bad: Dictionary = JSON.parse_string(orig.substr(orig.find("\n") + 1))
	bad["definitions"]["hash"] = "verändert"
	var mr := SaveMigrations.migrate(bad, 2)
	_check("Migration verweigert Format-2-Stände mit veränderten Definitionen", not mr["ok"] and mr["code"] == "definitions_changed", str(mr["message"]))
	for ext in ["", ".bak", ".v2.vor_migration"]:
		if FileAccess.file_exists(mp + ext):
			DirAccess.remove_absolute(mp + ext)


# ── Ohne Ollama ───────────────────────────────────

func _test_without_ollama() -> void:
	print("  KI-Test: _test_without_ollama (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var life := _env(AIService.disabled(), 12, 1001, true)
	_run(life, 60.0)
	_check("Ohne Ollama (ausgeschaltet): Welt läuft, keine Anfragen, lokale Gespräche möglich", life.ctx.ai.local["enqueued"] == 0 and int(life.ctx.ai.service.stats["sent"]) == 0
		and life.audit().is_empty() and life.population_summary()["alive"] == 12, "Gespräche lokal: %d" % int(life.ctx.comm.stats["via_local"]))
	# Eingeschaltet, aber kein Dienst unter der Adresse: echter HTTP-Transport, Verbindung abgelehnt
	var s := _settings({"use_mock": false, "base_url": "http://127.0.0.1:9", "connect_timeout_s": 1.0, "eligible_share": 1.0})
	var svc := AIService.new(s)
	var life2 := _env(svc, 6, 1002, true)
	svc.test_connection()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and svc.status != "nicht_erreichbar":
		life2.step(DT)
		OS.delay_msec(20)
	_check("Kein Dienst erreichbar (echter HTTP-Weg, Port geschlossen): verständliche Diagnose, Welt läuft lokal weiter, keine Anfragen",
		svc.status == "nicht_erreichbar" and svc.status_message.contains("nicht erreichbar") and int(svc.stats["sent"]) == 0 and life2.audit().is_empty(), svc.status_message)


# ── 50 Wesen, Ratenbegrenzung ─────────────────────

func _test_rate_limit_50() -> void:
	print("  KI-Test: _test_rate_limit_50 (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var svc := _svc({"eligible_share": 0.5, "global_rate_per_min": 8, "per_creature_min_interval_s": 90.0, "max_queue": 16}, "ok", 1500)
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs, svc)
	life.new_game(world_seed)
	sc.lives.append(life)
	var per_actor := {}
	var max_q := 0
	var t_wall := Time.get_ticks_msec()
	for i in 180:
		_run(life, 1.0)
		max_q = maxi(max_q, life.ctx.ai.queue.size())
	var wall := Time.get_ticks_msec() - t_wall
	for e in life.ctx.ai.recent:
		per_actor[int(e["actor"])] = per_actor.get(int(e["actor"]), []) + [float(e["t"])]
	var spacing_ok := true
	for k in per_actor:
		var ts: Array = per_actor[k]
		for j in range(1, ts.size()):
			if float(ts[j]) - float(ts[j - 1]) < 90.0 - 15.0:
				spacing_ok = false
	var sent := int(svc.stats["sent"])
	var elig := 0
	for id in life.ctx.creatures:
		if life.ctx.creatures[id].ai_eligible(0.5):
			elig += 1
	_check("50 Wesen mit Ratenbegrenzung (SIMULIERT, 180 s): höchstens 8 Anfragen/min, Abstand je Wesen, Warteschlange begrenzt, Welt konsistent",
		sent > 0 and sent <= 8 * 3 + 1 and max_q <= 16 and spacing_ok and life.audit().is_empty(),
		"gesendet %d, Anlässe %s, KI-fähig %d/50, max. Warteschlange %d, %.1f s Rechenzeit" % [sent, str(life.ctx.ai.local["by_trigger"]), elig, max_q, wall / 1000.0])
	notes.append("50-Wesen-Lauf mit SIMULIERTEM Dienst (1,5 s Antwortzeit, Echtzeit = Simulationszeit): gesendet %d, angenommen %d, abgelehnt %d, Anlässe %s, Rechenzeit %.1f s für 180 s." % [sent,
		int(life.ctx.ai.local["accepted"]), int(life.ctx.ai.local["rejected"]), str(life.ctx.ai.local["by_trigger"]), wall / 1000.0])


# ── Echter HTTP-Weg gegen lokale Attrappe (kein Ollama) ──

func _test_http_paths() -> void:
	print("  KI-Test: _test_http_paths (%.1f s)" % (Time.get_ticks_msec() / 1000.0))
	var py := ""
	for cand in ["python3", "python"]:
		var out: Array = []
		if OS.execute(cand, ["--version"], out, true) == 0:
			py = cand
			break
	if py == "":
		notes.append("HTTP-Attrappe übersprungen: kein Python gefunden (kein Fehler).")
		return
	var port := 11900 + randi() % 80
	var script := ProjectSettings.globalize_path("res://tools/ollama_attrappe.py")
	var pid := OS.create_process(py, [script, "--port", str(port)])
	var s := _settings({"use_mock": false, "base_url": "http://127.0.0.1:%d" % port, "model": "attrappe:klein", "timeout_s": 10.0, "connect_timeout_s": 1.0})
	var svc := AIService.new(s)
	var life := _env(svc, 2, 1101)
	var a: Creature = life.ctx.creatures[_ids(life)[0]]
	_near_food(life, a, 3.0)
	sc.set_hunger(a, 0.55)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and svc.status != "verbunden":
		svc.test_connection()
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 600 and svc.status != "verbunden":
			svc.poll()
			OS.delay_msec(15)
	var connected := svc.status == "verbunden"
	var rq := life.ctx.ai.request_now(a, "plan", "Test über HTTP-Attrappe")
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 8000 and not str(a.ai["last"].get("status", "")) in ["angenommen", "abgelehnt", "fehlgeschlagen"]:
		life.step(DT)
		OS.delay_msec(5)
	OS.kill(pid)
	_check("HTTP-Weg gegen lokale ATTRAPPE (Python, kein Ollama): Version, Modelliste, strukturierte Chat-Antwort über echten HTTP-Transport",
		connected and rq["ok"] and str(a.ai["last"].get("status", "")) == "angenommen" and not svc.simulated(), "%s | %s | %s" % [svc.status_message, str(a.ai["last"].get("status", "")), str(a.ai["last"].get("why", ""))])
	notes.append("HTTP-Attrappe ist KEIN Ollama: sie prüft nur den Netzwerkweg (Verbindung, Kopfzeilen, JSON-Antworten).")
