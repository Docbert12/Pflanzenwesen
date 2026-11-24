class_name PlanManager
extends RefCounted
## Modellpläne eines Wesens (cr.ai["plan"]). Ablauf:
##   empfangen → Struktur prüfen → Inhalt/Voraussetzungen prüfen (ResponseValidator) → mit aktuellem Ziel und
##   Bedürfnis vergleichen (accept) → annehmen oder ablehnen → JEDEN Schritt vor der Ausführung neu prüfen
##   (execute_next) → tatsächliches Ergebnis speichern (on_action_finished / history).
## Ein Plan ist nur ein Vorschlag: er wirkt als Option „follow_plan“ mit begrenztem Nutzwert im EINEN
## Entscheider (DecisionSystem) und konkurriert dort mit allen lokalen Optionen. Kritischer Hunger
## verdrängt jeden Plan, der nicht der Nahrung dient.
## Kein Ersatzobjekt: ist das geplante Ziel weg (z. B. Pilz gegessen), scheitert der Schritt und damit der
## Plan. Gescheiterte Pläne (Signatur) werden für failed_signature_block_s nicht erneut angenommen.

const GOAL_TO_LOCAL := {"food": "food", "ask_food": "ask_food", "offer_food": "offer_food", "approach": "approach", "explore": "explore",
	"rest": "rest", "talk": "talk", "repeat_learned": "repeat_learned"}


static func label(a: String) -> String:
	return {"go_to": "Hingehen", "explore": "Erkunden", "talk": "Sprechen"}.get(a, ActionDefinition.label(a))


static func signature(goal: String, steps: Array) -> String:
	var parts: Array = [goal]
	for s in steps:
		parts.append("%s:%d" % [s["action"], int(s["target"])])
	return "|".join(parts)


static func is_blocked(cr: Creature, sig: String, ctx: LifeContext) -> bool:
	if cr.ai.is_empty():
		return false
	return float(cr.ai["failed_sigs"].get(sig, -1.0)) > ctx.now()


static func active(cr: Creature) -> bool:
	return not cr.ai.is_empty() and str(cr.ai.get("plan", {}).get("state", "")) == "aktiv"


## Vergleich mit Bedürfnis und aktuellem Ziel; bei Annahme Plan oder Zielvorschlag setzen.
## Rückgabe {"ok", "message", "as": "plan"|"suggestion"|"confirm"|"note"}
static func accept(cr: Creature, v: Dictionary, entry: Dictionary, via: String, ctx: LifeContext) -> Dictionary:
	var dc: Dictionary = ctx.m("decision")
	var pc: Dictionary = ctx.m("plans")
	var hunger := cr.metabolism.hunger()
	var critical := hunger >= float(dc.get("critical_hunger", 0.8))
	var goal := str(v["goal_type"])
	var steps: Array = v["steps"]
	var now := ctx.now()
	if str(entry["kind"]) == "interpret":
		_note(cr, v, entry, via, ctx)
		return {"ok": true, "as": "note", "message": "Deutung als Modellnotiz gespeichert (kein Beleg für Vermutungen)."}
	if critical and goal != "food":
		return {"ok": false, "message": "Abgelehnt: kritischer Hunger %.0f %% – Überleben hat Vorrang vor „%s“." % [hunger * 100, goal]}
	var feeds_others: bool = steps.any(func(s): return s["action"] in ["give_food", "offer_food"])
	if goal == "food" and hunger < float(ctx.c("behavior").get("sated_threshold", 0.15)) and not feeds_others:
		return {"ok": false, "message": "Abgelehnt: kein Nahrungsbedarf (Hunger %.0f %%)." % (hunger * 100)}
	var w := clampf(1.0 - float(v["uncertainty"]), 0.0, 1.0)
	if goal == "keep_current":
		var cur := str(cr.goal_state.get("type", ""))
		if cur != "" and cur in GoalManager.GOAL_TYPES:
			GoalManager.suggest(cr, cur, via, w, ctx, float(pc.get("suggestion_ttl_s", 30.0)))
		return {"ok": true, "as": "confirm", "message": "Aktuelles Ziel „%s“ bestätigt (Zuschlag %.2f)." % [cur, w * float(dc.get("suggestion_max_bonus", 0.2))]}
	if steps.is_empty():
		var lg: String = GOAL_TO_LOCAL.get(goal, "")
		var r := GoalManager.suggest(cr, lg, via, w, ctx, float(pc.get("suggestion_ttl_s", 30.0)))
		return {"ok": r["ok"], "as": "suggestion", "message": ("Als Zielvorschlag übernommen: " + str(r["message"])) if r["ok"] else "Abgelehnt: " + str(r["message"])}
	var old: Dictionary = cr.ai.get("plan", {})
	if str(old.get("state", "")) == "aktiv":
		_archive(cr, old, "ersetzt", "durch neueren Plan ersetzt", ctx)
	var st: Array = []
	for s in steps:
		st.append({"action": s["action"], "target": int(s["target"]), "intent": str(s.get("intent", "none")), "status": "offen", "result": "", "phase": ""})
	if entry.has("topic") and not st.is_empty():
		st[0]["topic"] = entry["topic"]
		st[0]["certainty"] = float(entry.get("certainty", -1.0))
		st[0]["model_text"] = str(entry.get("model_text", ""))
	cr.ai["plan_seq"] = int(cr.ai.get("plan_seq", 0)) + 1
	cr.ai["plan"] = {"id": int(cr.ai["plan_seq"]), "request_id": int(entry["id"]), "source": via, "goal_type": goal, "steps": st, "i": 0,
		"created_t": now, "explanation": str(v.get("explanation", "")), "uncertainty": float(v["uncertainty"]), "memory_ids": v.get("memory_ids", []).duplicate(),
		"signature": str(v.get("signature", signature(goal, steps))), "state": "aktiv", "running": {}, "step_started_t": -1.0, "result": ""}
	return {"ok": true, "as": "plan", "message": "Plan mit %d Schritten angenommen (Unsicherheit %.2f)." % [st.size(), float(v["uncertainty"])]}


static func _note(cr: Creature, v: Dictionary, entry: Dictionary, via: String, ctx: LifeContext) -> void:
	var notes: Array = cr.ai["notes"]
	notes.append({"t": ctx.now(), "request_id": int(entry["id"]), "source": via, "interpretation": str(v.get("interpretation", "none")),
		"memory_ids": v.get("memory_ids", []).duplicate(), "uncertainty": float(v["uncertainty"]), "text": str(v.get("explanation", "")), "reason": str(entry.get("reason", ""))})
	while notes.size() > int(ctx.m("plans").get("notes_max", 8)):
		notes.pop_front()


static func _archive(cr: Creature, plan: Dictionary, state: String, why: String, ctx: LifeContext) -> void:
	plan["state"] = state
	plan["result"] = why
	plan["ended_t"] = ctx.now()
	plan["running"] = {}     # eine noch laufende Handlung läuft zu Ende, wird dem Plan aber nicht mehr zugerechnet
	var h: Array = cr.ai["plan_history"]
	h.append(plan.duplicate(true))
	while h.size() > int(ctx.m("plans").get("history_max", 5)):
		h.pop_front()
	if state == "gescheitert":
		cr.ai["failed_sigs"][str(plan["signature"])] = ctx.now() + float(ctx.m("plans").get("failed_signature_block_s", 600.0))
		var fs: Dictionary = cr.ai["failed_sigs"]
		for k in fs.keys():
			if float(fs[k]) < ctx.now():
				fs.erase(k)
		while fs.size() > int(ctx.m("plans").get("failed_signatures_max", 8)):
			fs.erase(fs.keys()[0])
	cr.ai["plan"] = {}


static func fail(cr: Creature, why: String, ctx: LifeContext) -> void:
	var plan: Dictionary = cr.ai.get("plan", {})
	if plan.is_empty():
		return
	var i := int(plan["i"])
	if i < plan["steps"].size():
		plan["steps"][i]["status"] = "fehlgeschlagen"
		plan["steps"][i]["result"] = why
	_archive(cr, plan, "gescheitert", why, ctx)
	ctx.log_event("ai_plan_failed", [cr.id], {"plan": plan["id"], "reason": why})


static func abort(cr: Creature, why: String, ctx: LifeContext) -> void:
	if active(cr):
		_archive(cr, cr.ai["plan"], "abgebrochen", why, ctx)


## Nutzwert der Option „follow_plan“ (oder −1, wenn keine sinnvolle Option).
static func utility(cr: Creature, ctx: LifeContext, food_u: float, critical: bool) -> Dictionary:
	if not active(cr):
		return {}
	var plan: Dictionary = cr.ai["plan"]
	var pc: Dictionary = ctx.m("plans")
	if ctx.now() - float(plan["created_t"]) > float(pc.get("max_plan_age_s", 180.0)):
		fail(cr, "Plan zu alt (nicht rechtzeitig ausgeführt)", ctx)
		return {}
	if critical and str(plan["goal_type"]) != "food":
		return {}
	var parts := {"modellplan": float(pc.get("follow_weight", 0.35)) * (1.0 - float(pc.get("uncertainty_discount", 0.5)) * float(plan["uncertainty"]))}
	if str(plan["goal_type"]) == "food":
		parts["bedarf"] = food_u * float(pc.get("food_alignment", 0.5))
	return parts


## Nächsten Schritt prüfen und ausführen. Bereits erfüllte Schritte (z. B. „hingehen“, wenn das Wesen
## schon dort ist) werden sofort abgehakt und der folgende Schritt im selben Aufruf geprüft.
## Rückgabe {"ok", "state", "reason"} wie DecisionSystem-Optionen.
static func execute_next(cr: Creature, ctx: LifeContext) -> Dictionary:
	var pc: Dictionary = ctx.m("plans")
	var now := ctx.now()
	for _guard in 6:
		if not active(cr):
			return {"ok": false, "state": "", "reason": "Plan abgeschlossen"}
		var plan: Dictionary = cr.ai["plan"]
		var i := int(plan["i"])
		if i >= plan["steps"].size():
			_archive(cr, plan, "abgeschlossen", "alle Schritte ausgeführt", ctx)
			return {"ok": false, "state": "", "reason": "Plan abgeschlossen"}
		var s: Dictionary = plan["steps"][i]
		if float(plan["step_started_t"]) < 0.0 or s["status"] == "offen":
			plan["step_started_t"] = now
			s["status"] = "läuft"
		elif now - float(plan["step_started_t"]) > float(pc.get("step_timeout_s", 40.0)):
			fail(cr, "Schritt %d „%s“ dauert zu lange" % [i + 1, s["action"]], ctx)
			return {"ok": false, "state": "", "reason": "Modellplan: Schritt zu lange"}
		var r := _do_step(cr, s, ctx)
		var tag := "Modellplan (%s) Schritt %d/%d „%s“: " % ["SIMULIERT" if plan["source"] == "simuliert" else "Ollama", i + 1, plan["steps"].size(), _step_label(s)]
		if r.get("done_now", false):
			_complete_step(cr, plan, "bereits erfüllt", ctx)
			continue
		if not r["ok"]:
			fail(cr, "Schritt %d „%s“: %s" % [i + 1, _step_label(s), r["reason"]], ctx)
			return {"ok": false, "state": "", "reason": tag + str(r["reason"])}
		var a: GameAction = r.get("action", null)
		if a != null:
			plan["running"] = {"action_id": a.id, "main": bool(r.get("main", true)), "type": a.type}
		s["phase"] = str(r.get("phase", ""))
		return {"ok": true, "state": str(r.get("state", "folgt_plan")), "reason": tag + str(r["reason"])}
	return {"ok": false, "state": "", "reason": "Modellplan: keine ausführbaren Schritte"}


static func _step_label(s: Dictionary) -> String:
	var t := int(s["target"])
	return "%s%s" % [s["action"], (" #%d" % t) if t != 0 else ""]


static func _complete_step(cr: Creature, plan: Dictionary, result: String, ctx: LifeContext) -> void:
	var i := int(plan["i"])
	plan["steps"][i]["status"] = "erledigt"
	plan["steps"][i]["result"] = result
	plan["i"] = i + 1
	plan["step_started_t"] = -1.0
	plan["running"] = {}
	if int(plan["i"]) >= plan["steps"].size():
		_archive(cr, plan, "abgeschlossen", "alle Schritte ausgeführt", ctx)
		ctx.log_event("ai_plan_done", [cr.id], {"plan": plan["id"]})


## Rückmeldung des Handlungssystems.
static func on_action_finished(cr: Creature, a: GameAction, ctx: LifeContext) -> void:
	if not active(cr):
		return
	var plan: Dictionary = cr.ai["plan"]
	var run: Dictionary = plan.get("running", {})
	if run.is_empty() or int(run.get("action_id", -1)) != a.id:
		return
	plan["running"] = {}
	if a.status != ActionDefinition.STATUS_SUCCEEDED:
		fail(cr, "Handlung „%s“ %s: %s" % [ActionDefinition.label(a.type), "abgebrochen" if a.status == ActionDefinition.STATUS_CANCELLED else "fehlgeschlagen", a.result_message], ctx)
		return
	if bool(run.get("main", true)):
		_complete_step(cr, plan, "%s: %s" % [ActionDefinition.label(a.type), a.result_message], ctx)


## Schritt in eine Handlungsanfrage umsetzen. Jede Prüfung erfolgt JETZT (nicht beim Planen).
static func _do_step(cr: Creature, s: Dictionary, ctx: LifeContext) -> Dictionary:
	var t := int(s["target"])
	var reach := float(ctx.c("food").get("reach_m", 1.1))
	var pc: Dictionary = ctx.m("plans")
	match str(s["action"]):
		"wait":
			var r := ctx.executor.request(cr.id, "wait", 0, null, {"duration_s": float(pc.get("step_wait_s", 5.0))})
			return _res(r, "wartet", "wartet %.0f s" % float(pc.get("step_wait_s", 5.0)))
		"explore":
			var p = BasicBehavior.random_walkable(cr, ctx, float(pc.get("step_explore_radius_m", 6.0)))
			if p == null:
				return {"ok": false, "reason": "kein begehbarer Punkt"}
			return _res(ctx.executor.request(cr.id, "move_to", 0, p), "erkundet", "erkundet")
		"raise_arms":
			return _res(ctx.executor.request(cr.id, "raise_arms"), "arme_heben", "hebt die Arme")
		"go_to":
			if cr.food_memory.has(t):
				var fp := _pos(cr.food_memory[t]["pos"])
				if ctx.distance_xz(cr.position, fp) <= reach:
					return {"ok": true, "done_now": true, "reason": "schon dort"}
				return _res(ctx.executor.request(cr.id, "move_to", 0, fp, {"arrive_radius_m": reach * 0.8}), "geht_zu_nahrung", "geht zu Nahrung #%d" % t)
			var v := CommunicationSystem._visible(cr, t)
			if v.is_empty():
				return {"ok": false, "reason": "Ziel #%d nicht mehr bekannt oder sichtbar – kein Ersatzziel" % t}
			var tc := ctx.creature(t)
			if ctx.distance_xz(cr.position, tc.position) <= 2.0:
				return {"ok": true, "done_now": true, "reason": "schon dort"}
			return _res(ctx.executor.request(cr.id, "move_to", 0, tc.position, {"arrive_radius_m": 1.5}), "geht_zu_wesen", "geht zu #%d" % t)
		"pick_up":
			return _food_step(cr, t, "pick_up", ctx)
		"eat":
			if t == 0 or (cr.carried_item_id != 0 and float(cr.caps.get("grasp", 0.0)) > 0.0):
				if cr.carried_item_id == 0:
					return {"ok": false, "reason": "trägt nichts zum Essen"}
				return _res(ctx.executor.request(cr.id, "eat", cr.carried_item_id), "isst", "isst getragene Portion")
			if float(cr.caps.get("grasp", 0.0)) > 0.0 and float(cr.caps.get("feeding", 0.0)) > 0.0:
				var pr := _food_step(cr, t, "pick_up", ctx)
				pr["main"] = false        # erst aufnehmen, Essen folgt im selben Schritt
				return pr
			return _food_step(cr, t, "eat", ctx)
		"give_food", "offer_food", "request_food":
			var tc2 := ctx.creature(t)
			if tc2 == null or not tc2.alive or CommunicationSystem._visible(cr, t).is_empty():
				return {"ok": false, "reason": "#%d nicht sichtbar oder nicht mehr da" % t}
			if s["action"] != "request_food" and cr.carried_item_id == 0:
				return {"ok": false, "reason": "trägt nichts"}
			var rng := float(ctx.m("social").get("give_range_m", 1.4)) if s["action"] == "give_food" else float(ctx.m("social").get("request_range_m", 3.0))
			if ctx.distance_xz(cr.position, tc2.position) > rng * 0.9:
				var mv := ctx.executor.request(cr.id, "move_to", 0, tc2.position, {"arrive_radius_m": rng * 0.6})
				var out := _res(mv, "geht_zu_wesen", "geht zu #%d" % t)
				out["main"] = false
				return out
			return _res(ctx.executor.request(cr.id, str(s["action"]), t), "sozial", "%s → #%d" % [ActionDefinition.label(str(s["action"])), t])
		"talk":
			var tc3 := ctx.creature(t)
			if tc3 == null or not tc3.alive:
				return {"ok": false, "reason": "Zuhörer #%d nicht mehr da" % t}
			var cc: Dictionary = ctx.m("communication")
			if ctx.distance_xz(cr.position, tc3.position) > float(cc.get("range_m", 4.0)) * 0.9:
				if CommunicationSystem._visible(cr, t).is_empty():
					return {"ok": false, "reason": "Zuhörer #%d nicht sichtbar" % t}
				var mv2 := ctx.executor.request(cr.id, "move_to", 0, tc3.position, {"arrive_radius_m": float(cc.get("range_m", 4.0)) * 0.5})
				var o2 := _res(mv2, "geht_zu_wesen", "geht zum Gespräch mit #%d" % t)
				o2["main"] = false
				return o2
			var topic: Dictionary = s.get("topic", {})
			if topic.is_empty():
				for tp in ctx.comm.topics(cr, t, ctx):
					if tp["absicht"] == s.get("intent", "none") or (s.get("intent", "none") == "none" and tp["absicht"] in ["point_food", "share_experience", "share_guess"]):
						topic = tp
						break
			else:
				var still := false
				for tp2 in ctx.comm.topics(cr, t, ctx):
					if tp2["absicht"] == topic["absicht"] and int(tp2["statement"].get("id", 0)) == int(topic["statement"].get("id", 0)) and str(tp2["statement"].get("key", "")) == str(topic["statement"].get("key", "")):
						still = true
						topic = tp2
						break
				if not still:
					return {"ok": false, "reason": "Inhalt gehört nicht mehr zum eigenen Wissen"}
			if topic.is_empty():
				return {"ok": false, "reason": "nichts Passendes zu sagen"}
			var plan: Dictionary = cr.ai["plan"]
			var via := "simuliert" if plan["source"] == "simuliert" else "ollama"
			var st := ctx.comm.start(cr, t, topic, via, ctx, float(s.get("certainty", -1.0)), str(s.get("model_text", "")))
			if not st["ok"]:
				return {"ok": false, "reason": st["message"]}
			var a = ctx.executor.running.get(cr.id, null)
			return {"ok": true, "state": "spricht", "reason": st["message"], "action": a, "main": true}
	return {"ok": false, "reason": "unbekannte Planhandlung"}


static func _food_step(cr: Creature, t: int, act: String, ctx: LifeContext) -> Dictionary:
	if not cr.food_memory.has(t):
		return {"ok": false, "reason": "Nahrung #%d ist nicht mehr bekannt – kein Ersatzziel" % t}
	var m: Dictionary = cr.food_memory[t]
	if float(m["available_kg"]) <= 1e-6:
		return {"ok": false, "reason": "Nahrung #%d zuletzt leer gesehen" % t}
	var p := _pos(m["pos"])
	var reach := float(ctx.c("food").get("reach_m", 1.1))
	if ctx.distance_xz(cr.position, p) > reach:
		var mv := ctx.executor.request(cr.id, "move_to", 0, p, {"arrive_radius_m": reach * 0.8})
		var o := _res(mv, "geht_zu_nahrung", "geht zu Nahrung #%d" % t)
		o["main"] = false
		return o
	return _res(ctx.executor.request(cr.id, act, t), "nimmt_auf" if act == "pick_up" else "isst", "%s #%d" % [ActionDefinition.label(act), t])


static func _res(r: Dictionary, state: String, reason: String) -> Dictionary:
	if not r["result"].ok:
		return {"ok": false, "reason": r["result"].message}
	return {"ok": true, "state": state, "reason": reason, "action": r["action"], "main": true}


static func _pos(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
