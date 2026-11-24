class_name AISystem
extends RefCounted
## Weltseite der Modellanbindung (eine Instanz je LifeSimulation, ctx.ai).
## - Entscheidet, WANN ein Wesen fragt (consider): nach wiederholtem Scheitern, bei auffälligem Ereignis,
##   für ein gezieltes Gespräch, zur Deutung widersprüchlicher Erfahrungen, bei einer knappen Wahl.
##   NIE für Bewegung, Nahrungssuche, Hungeraktualisierung, Ausweichen, Gesundheitsänderungen; nie bei
##   kritischem Hunger; höchstens eine offene Anfrage je Wesen; Mindestabstand je Wesen; globale Rate.
## - Versendet (dispatch) mit frisch gebautem Kontext; die Simulation wartet nie.
## - Wendet Antworten erst an, wenn die Simulation läuft (Pause: keine neuen Anfragen, eintreffende Antworten
##   werden erst nach dem Fortsetzen gegen den DANN aktuellen Zustand geprüft).
## - Sitzung: jede Instanz hat eine eigene Sitzungsnummer. Antworten aus früheren Welten (vor Laden/Neustart)
##   werden nie angewendet.

static var _session_counter: int = 0

var session: int = 0
var service: AIService
var ctx: LifeContext
var queue := RequestQueue.new()
var next_request_id: int = 1
var inbox: Array = []                 # eingetroffene Ergebnisse dieser Sitzung
var handles: Dictionary = {}          # handle -> request id
var rng := RandomNumberGenerator.new()
var schemas: Dictionary = {}
var local := {"enqueued": 0, "dispatched": 0, "accepted": 0, "rejected": 0, "discarded": 0, "failed": 0, "arrived_paused": 0,
	"by_trigger": {}, "by_stage": {}}
var recent: Array = []                # Diagnose: letzte Anfragen mit Ergebnis (begrenzt)
var alive_flag: bool = true


func _init(p_ctx: LifeContext, p_service: AIService) -> void:
	_session_counter += 1
	session = _session_counter
	ctx = p_ctx
	service = p_service if p_service != null else AIService.disabled()
	rng.seed = 7151 + session
	for k in ["decision", "conversation", "experiment"]:
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai/%s_schema.json" % k))
		schemas[k] = j if typeof(j) == TYPE_DICTIONARY else {}
	service.register(self)


func shutdown(reason: String = "Welt beendet") -> void:
	if not alive_flag:
		return
	alive_flag = false
	queue.clear(reason)
	service.unregister(self)
	handles.clear()
	inbox.clear()
	ctx = null


func enabled() -> bool:
	return alive_flag and service.settings.enabled()


func connected() -> bool:
	return enabled() and service.status == "verbunden"


func via() -> String:
	return "simuliert" if service.simulated() else "ollama"


## Vom Dienst zugestellt (nur diese Sitzung).
func receive(r: Dictionary) -> void:
	inbox.append(r)


## Einmal je Takt. paused=true: nur Netzwerk, keine neuen Anfragen, nichts anwenden.
func update(paused: bool) -> void:
	if not alive_flag:
		return
	service.poll()
	if paused:
		for r in inbox:
			if not r.get("arrived_paused", false):
				r["arrived_paused"] = true
				local["arrived_paused"] += 1
		return
	if not inbox.is_empty():
		var batch := inbox.duplicate()
		inbox.clear()
		for r in batch:
			_apply(r)
	if service.can_dispatch():
		_dispatch_one()


# ── Anlässe ────────────────────────────────────────

## Prüft nach einer lokalen Entscheidung, ob ein Anlass für eine Modellanfrage besteht.
func consider(cr: Creature, options: Array) -> void:
	if not connected() or not cr.alive or not cr.ai_eligible(float(service.settings.g("eligible_share", 0.5))):
		return
	var now := ctx.now()
	if now < float(cr.ai.get("next_request_t", 0.0)) or queue.has_actor(cr.id):
		return
	if cr.metabolism.hunger() >= float(ctx.m("decision").get("critical_hunger", 0.8)):
		return
	if PlanManager.active(cr):
		return
	var tc: Dictionary = ctx.m("ai_triggers")
	var pr: Dictionary = tc.get("priority", {})
	var trig := ""
	var reason := ""
	var listener := 0
	if int(cr.ai.get("fail_streak", 0)) >= int(tc.get("fail_streak", 3)):
		trig = "failure"
		reason = "wiederholtes Scheitern (%d Fehlschläge in Folge, zuletzt: %s)" % [int(cr.ai["fail_streak"]), str(cr.last_result.get("message", "")).substr(0, 80)]
	elif _failed_experiment(cr) != 0:
		var fe := _failed_experiment(cr)
		trig = "experiment"
		reason = "Versuch #%d misslungen – Vorschlag für einen anderen Versuch" % fe
		cr.tech["model_asked_exp"] = fe
	elif now - float(cr.ai.get("notable_t", -1e9)) <= float(tc.get("notable_window_s", 8.0)) and int(cr.ai.get("notable_mem", 0)) != int(cr.ai.get("notable_asked", -1)):
		trig = "notable"
		reason = "auffälliges Ereignis (Erinnerung %d)" % int(cr.ai["notable_mem"])
		cr.ai["notable_asked"] = int(cr.ai["notable_mem"])
	else:
		var key := _contradiction(cr)
		if key != "":
			trig = "interpret"
			reason = "widersprüchliche Erfahrungen: %s" % BeliefStore.statement(cr.beliefs.items[key])
			cr.ai["interpreted"][key] = now
		else:
			if options.size() >= 2:
				var u0 := float(options[0]["u"])
				var u1 := float(options[1]["u"])
				if u0 >= float(tc.get("hard_choice_min_u", 0.3)) and u0 - u1 <= float(tc.get("hard_choice_margin", 0.03)) and options[0]["id"] != options[1]["id"]:
					trig = "hard_choice"
					reason = "knappe Wahl zwischen „%s“ (%.2f) und „%s“ (%.2f)" % [options[0]["id"], u0, options[1]["id"], u1]
			if trig == "" and rng.randf() < float(tc.get("talk_request_chance", 0.25)):
				var opp := _talk_listener(cr)
				if opp != 0:
					trig = "talk"
					listener = opp
					reason = "Gesprächsgelegenheit mit #%d" % opp
	if trig == "":
		return
	var kind := "talk" if trig == "talk" else ("interpret" if trig == "interpret" else ("experiment" if trig == "experiment" else "plan"))
	var e := {"id": next_request_id, "session": session, "actor": cr.id, "kind": kind, "trigger": trig, "reason": reason,
		"priority": int(pr.get(trig, 1)), "created_t": now, "expires_t": now + float(service.settings.g("request_ttl_s", 60.0)),
		"attempts": 0, "next_try_ms": 0, "listener": listener, "state": "wartend"}
	queue.max_len = int(service.settings.g("max_queue", 16))
	var q := queue.enqueue(e)
	if not q["ok"]:
		cr.ai["last"] = {"status": "nicht angenommen", "reason": reason, "why": q["message"], "t": now, "request_id": 0, "kind": kind}
		return
	next_request_id += 1
	cr.ai["next_request_t"] = now + float(service.settings.g("per_creature_min_interval_s", 90.0))
	if trig == "failure":
		cr.ai["fail_streak"] = 0
	cr.ai["last"] = {"status": "wartet", "reason": reason, "why": "", "t": now, "request_id": e["id"], "kind": kind, "queued_t": now}
	local["enqueued"] += 1
	local["by_trigger"][trig] = int(local["by_trigger"].get(trig, 0)) + 1


## Gezielte Anfrage ohne Anlassprüfung (Entwicklermodus, Tests, Live-Testwerkzeug). Alle übrigen Regeln
## gelten weiter: Anbindung verbunden, Wesen lebt, kein kritischer Hunger, eine Anfrage je Wesen, Warteschlange.
## Rückgabe {"ok", "message", "request_id"}.
func request_now(cr: Creature, kind: String = "plan", reason: String = "Entwicklermodus: gezielte Anfrage", listener: int = 0) -> Dictionary:
	if not connected():
		return {"ok": false, "message": "KI-Anbindung nicht verbunden (%s)." % service.status_text(), "request_id": 0}
	if cr == null or not cr.alive:
		return {"ok": false, "message": "Kein lebendes Wesen.", "request_id": 0}
	if cr.metabolism.hunger() >= float(ctx.m("decision").get("critical_hunger", 0.8)):
		return {"ok": false, "message": "Kritischer Hunger – nur lokale Reaktion.", "request_id": 0}
	if kind == "talk" and listener == 0:
		listener = _talk_listener(cr)
		if listener == 0:
			return {"ok": false, "message": "Kein möglicher Gesprächspartner mit Thema in der Nähe.", "request_id": 0}
	var now := ctx.now()
	var e := {"id": next_request_id, "session": session, "actor": cr.id, "kind": kind, "trigger": "manual", "reason": reason,
		"priority": 5, "created_t": now, "expires_t": now + float(service.settings.g("request_ttl_s", 60.0)),
		"attempts": 0, "next_try_ms": 0, "listener": listener, "state": "wartend"}
	queue.max_len = int(service.settings.g("max_queue", 16))
	var q := queue.enqueue(e)
	if not q["ok"]:
		return {"ok": false, "message": q["message"], "request_id": 0}
	next_request_id += 1
	cr.ai["last"] = {"status": "wartet", "reason": reason, "why": "", "t": now, "request_id": e["id"], "kind": kind, "queued_t": now}
	local["enqueued"] += 1
	local["by_trigger"]["manual"] = int(local["by_trigger"].get("manual", 0)) + 1
	return {"ok": true, "message": "Anfrage %d für #%d eingereiht (%s)." % [int(e["id"]), cr.id, kind], "request_id": int(e["id"])}


## Jüngster misslungener eigener Versuch (≤ 60 s), zu dem noch kein Vorschlag erbeten wurde.
func _failed_experiment(cr: Creature) -> int:
	if ctx.experiments == null or cr.tech.is_empty() or ctx.experiments.active(cr) != null:
		return 0
	var open := 0
	for h in cr.tech["hypotheses"]:
		if str(h["status"]) == "ungeprüft":
			open += 1
	if open >= int(ctx.tc("experiments").get("model_hypotheses_max", 4)):
		return 0
	var recs := ctx.experiments.of_creature(cr.id)
	if recs.is_empty():
		return 0
	var r: ExperimentRecord = recs[0]
	if r.status == "fehlgeschlagen" or r.outcome in ["kein sichtbarer Effekt", "keine sichtbare Veränderung", "kaum eine Veränderung zu sehen"]:
		if ctx.now() - r.ended_t <= 60.0 and int(cr.tech.get("model_asked_exp", 0)) != r.id:
			return r.id
	return 0


func _contradiction(cr: Creature) -> String:
	var tc: Dictionary = ctx.m("ai_triggers")
	for h in cr.beliefs.of_kind("gift_after_action"):
		if int(h["n_support"]) >= int(tc.get("contradiction_min_support", 1)) and int(h["n_contra"]) >= int(tc.get("contradiction_min_contra", 2)) \
				and not cr.ai["interpreted"].has(str(h["key"])):
			return str(h["key"])
	return ""


func _talk_listener(cr: Creature) -> int:
	if ctx.comm == null:
		return 0
	for v in cr.visible_creatures:
		if not v["alive"] or float(v["d"]) > float(ctx.m("communication").get("range_m", 4.0)) * 1.5:
			continue
		if not ctx.comm.can_talk(cr, int(v["id"]), ctx, false)["ok"]:
			continue
		var tps := ctx.comm.topics(cr, int(v["id"]), ctx)
		if tps.any(func(t): return t["absicht"] in ["point_food", "share_experience", "share_guess"]):
			return int(v["id"])
	return 0


# ── Versand ────────────────────────────────────────

func _dispatch_one() -> void:
	var now_ms := service.now_ms()
	var e := queue.pop_ready(now_ms, ctx.now())
	if e.is_empty():
		return
	var cr := ctx.creature(int(e["actor"]))
	if cr == null or not cr.alive:
		queue._drop(e, "Wesen lebt nicht mehr")
		return
	if cr.metabolism.hunger() >= float(ctx.m("decision").get("critical_hunger", 0.8)):
		queue._drop(e, "kritischer Hunger – lokal")
		cr.ai["last"] = {"status": "verworfen", "reason": e["reason"], "why": "kritischer Hunger: nur lokale Reaktion", "t": ctx.now(), "request_id": e["id"], "kind": e["kind"]}
		return
	var b := ContextBuilder.build(cr, ctx, str(e["kind"]), int(e["id"]), str(e["reason"]), int(service.settings.g("max_context_chars", 7000)), int(e["listener"]))
	if str(e["kind"]) == "talk" and b["cand"]["topics"].is_empty():
		queue._drop(e, "kein Gesprächsthema mehr")
		cr.ai["last"] = {"status": "verworfen", "reason": e["reason"], "why": "kein Gesprächsthema mehr", "t": ctx.now(), "request_id": e["id"], "kind": e["kind"]}
		return
	e["cand"] = b["cand"]
	e["allowed"] = b["allowed"]
	e["state_t"] = b["state_t"]
	e["context_chars"] = b["chars"]
	var schema: Dictionary = schemas["conversation" if e["kind"] == "talk" else ("experiment" if e["kind"] == "experiment" else "decision")]
	var h := service.send_chat(session, int(e["id"]), ContextBuilder.messages(str(e["kind"]), b["json"], schema), schema)
	if h < 0:
		queue._drop(e, "Senden nicht möglich: " + service.client.config_error)
		return
	e["attempts"] = int(e["attempts"]) + 1
	e["handle"] = h
	e["sent_ms"] = now_ms
	e["state"] = "läuft"
	queue.mark_running(e, now_ms)
	handles[h] = int(e["id"])
	local["dispatched"] += 1
	cr.ai["last"] = {"status": "läuft", "reason": e["reason"], "why": "", "t": ctx.now(), "request_id": e["id"], "kind": e["kind"],
		"state_t": e["state_t"], "attempt": e["attempts"], "context_chars": b["chars"]}
	if bool(service.settings.g("diagnostic_mode", false)):
		service.add_log("diag", "Kontext Anfrage %d (#%d): %s" % [int(e["id"]), cr.id, b["json"]], {"request_id": e["id"], "actor": cr.id})
	else:
		service.add_log("info", "Anfrage %d gesendet: #%d, %s – %s (%d Zeichen Kontext)." % [int(e["id"]), cr.id, e["kind"], e["reason"], int(b["chars"])], {"request_id": e["id"], "actor": cr.id})


# ── Anwenden ───────────────────────────────────────

func _apply(r: Dictionary) -> void:
	var rid := int(r["meta"].get("request_id", 0))
	handles.erase(int(r["handle"]))
	if int(r["meta"].get("session", -1)) != session:
		local["discarded"] += 1
		service.stats["discarded_stale"] += 1
		service.add_log("warn", "Antwort %d verworfen: andere Sitzung." % rid)
		return
	var e := queue.finish(rid)
	if e.is_empty():
		local["discarded"] += 1
		service.stats["discarded_stale"] += 1
		service.add_log("warn", "Antwort %d verworfen: Anfrage nicht mehr offen (abgebrochen)." % rid)
		return
	var cr := ctx.creature(int(e["actor"]))
	if cr == null or not cr.alive:
		local["discarded"] += 1
		service.add_log("warn", "Antwort %d verworfen: Wesen #%d lebt nicht mehr." % [rid, int(e["actor"])])
		return
	var last := {"reason": e["reason"], "t": ctx.now(), "request_id": rid, "kind": e["kind"], "state_t": e.get("state_t", 0.0),
		"latency_ms": int(r["latency_ms"]), "simulated": bool(r["simulated"]), "after_pause": bool(r.get("arrived_paused", false)), "attempt": int(e["attempts"])}
	if not r["ok"]:
		var code := str(r["code"])
		service.report_transport(false, code, str(r["message"]))
		var transient := code in ["unreachable", "timeout", "connection_lost", "http_error", "empty", "invalid_json"]
		if transient and service.status == "verbunden" and queue.retry(e, service.now_ms(), int(service.settings.g("max_retries", 1)), float(service.settings.g("retry_backoff_s", 6.0))):
			service.stats["retries"] += 1
			last.merge({"status": "wiederholt", "why": str(r["message"])})
			cr.ai["last"] = last
			service.add_log("warn", "Anfrage %d: %s – wird einmal wiederholt." % [rid, r["message"]])
			return
		local["failed"] += 1
		last.merge({"status": "fehlgeschlagen", "why": str(r["message"]), "code": code})
		cr.ai["last"] = last
		_remember(e, "fehlgeschlagen: " + str(r["message"]))
		service.add_log("error", "Anfrage %d (#%d): %s Wesen handelt lokal weiter." % [rid, cr.id, r["message"]])
		return
	service.report_transport(true, "ok", "")
	var mx := int(service.settings.g("max_response_chars", 3000))
	var age := float(service.settings.g("max_state_age_s", 45.0))
	var v: Dictionary
	if e["kind"] == "talk":
		v = ResponseValidator.validate_talk(str(r["content"]), e, session, ctx, mx, age)
	elif e["kind"] == "experiment":
		v = ResponseValidator.validate_experiment(str(r["content"]), e, session, ctx, mx, age)
	else:
		v = ResponseValidator.validate_decision(str(r["content"]), e, session, ctx, mx, age)
	last["raw_chars"] = str(r["content"]).length()
	if bool(service.settings.g("diagnostic_mode", false)):
		service.add_log("diag", "Rohantwort %d: %s" % [rid, OllamaClient.sanitize(str(r["content"]), 1500)], {"request_id": rid})
	if not v["ok"]:
		local["rejected"] += 1
		local["by_stage"][str(v["stage"])] = int(local["by_stage"].get(str(v["stage"]), 0)) + 1
		service.stats["rejected"] += 1
		service.stats["by_stage"][str(v["stage"])] = int(service.stats["by_stage"].get(str(v["stage"]), 0)) + 1
		last.merge({"status": "abgelehnt", "why": str(v["message"]), "stage": int(v["stage"])})
		cr.ai["last"] = last
		_remember(e, "abgelehnt: " + str(v["message"]))
		service.add_log("warn", "Antwort %d (#%d) abgelehnt – %s" % [rid, cr.id, v["message"]], {"request_id": rid, "actor": cr.id})
		return
	var val: Dictionary = v["value"]
	var acc: Dictionary
	if e["kind"] == "experiment":
		# Nur als ungeprüfte Hypothese ablegen – kein Gegenstand, keine Entdeckung, kein Erfolg
		var src := "Modell (SIMULIERT)" if r["simulated"] else "Modell (Ollama)"
		var h := ProceduralKnowledge.add_hypothesis(ctx, cr, {"kind": "modellvorschlag", "question": val["question"], "expected": val["expected"],
			"steps": val["steps"], "source": src, "uncertainty": val["uncertainty"], "explanation": val["explanation"], "request_id": rid, "risk": 0.2})
		acc = {"ok": true, "as": "hypothesis", "message": "Als ungeprüfte Hypothese #%d gespeichert (%s): %s" % [int(h["id"]), src, val["question"]]}
	elif e["kind"] == "talk":
		if val["intent"] == "none":
			acc = {"ok": true, "as": "nothing", "message": "Modell schlägt vor, nichts zu sagen."}
		else:
			e["topic"] = val["topic"]
			e["certainty"] = float(val["certainty"])
			e["model_text"] = str(val["model_text"])
			var steps := [{"action": "talk", "target": int(e["listener"]), "intent": str(val["intent"])}]
			acc = PlanManager.accept(cr, {"goal_type": "talk", "steps": steps, "uncertainty": 1.0 - float(val["certainty"]),
				"explanation": "Gespräch: " + str(CommunicationSystem.INTENT_LABEL.get(val["intent"], val["intent"])), "memory_ids": [],
				"signature": PlanManager.signature("talk", steps) + "|%d" % int(val["topic"]["statement"].get("id", 0))}, e, via(), ctx)
	else:
		acc = PlanManager.accept(cr, val, e, via(), ctx)
	if acc["ok"]:
		local["accepted"] += 1
		service.stats["accepted"] += 1
		last.merge({"status": "angenommen", "why": str(acc["message"]), "as": acc.get("as", ""), "explanation": str(val.get("explanation", ""))})
		cr.next_decision_t = minf(cr.next_decision_t, ctx.now())
	else:
		local["rejected"] += 1
		service.stats["rejected"] += 1
		last.merge({"status": "abgelehnt", "why": str(acc["message"]), "stage": 0})
	cr.ai["last"] = last
	_remember(e, "%s: %s" % ["angenommen" if acc["ok"] else "abgelehnt", acc["message"]])
	service.add_log("info" if acc["ok"] else "warn", "Antwort %d (#%d, %s): %s" % [rid, cr.id, "SIMULIERT" if r["simulated"] else "Ollama", acc["message"]], {"request_id": rid, "actor": cr.id})


func _remember(e: Dictionary, outcome: String) -> void:
	recent.append({"id": e["id"], "actor": e["actor"], "kind": e["kind"], "reason": e["reason"], "outcome": outcome, "t": ctx.now()})
	while recent.size() > 40:
		recent.pop_front()


# ── Ereignisse aus der Welt ───────────────────────

func on_death(cr: Creature) -> void:
	for e in queue.remove_actor(cr.id, "Wesen gestorben"):
		if e.has("handle"):
			service.cancel_route(int(e["handle"]))
			handles.erase(int(e["handle"]))
	if not cr.ai.is_empty():
		PlanManager.abort(cr, "Wesen gestorben", ctx)


func waiting_for(cr_id: int) -> Dictionary:
	return queue.entry_for_actor(cr_id)


## Nach dem Laden: offene Anfragen gibt es nicht (nie gespeichert); angenommene Pläne werden gegen den
## geladenen Zustand neu geprüft. Rückgabe: Liste kurzer Hinweise.
func after_load() -> Array:
	var notes: Array = []
	queue.clear("Spielstand geladen")
	for id in ctx.creatures:
		var cr: Creature = ctx.creatures[id]
		if not PlanManager.active(cr):
			continue
		if not cr.alive:
			PlanManager.abort(cr, "beim Laden: Wesen tot", ctx)
			continue
		var plan: Dictionary = cr.ai["plan"]
		var bad := ""
		for i in range(int(plan["i"]), plan["steps"].size()):
			var s: Dictionary = plan["steps"][i]
			var t := int(s["target"])
			if t == 0:
				continue
			if s["action"] in ["pick_up", "eat"] and not cr.food_memory.has(t):
				bad = "Nahrung #%d nicht mehr bekannt" % t
			elif s["action"] in ["give_food", "offer_food", "request_food", "talk"] and (ctx.creature(t) == null or not ctx.creature(t).alive):
				bad = "Wesen #%d nicht mehr da" % t
			if bad != "":
				break
		if bad != "":
			PlanManager.fail(cr, "beim Laden ungültig: " + bad, ctx)
			notes.append("#%d: Plan verworfen (%s)" % [id, bad])
		else:
			notes.append("#%d: Plan %d gültig, weiter ab Schritt %d" % [id, int(plan["id"]), int(plan["i"]) + 1])
	return notes
