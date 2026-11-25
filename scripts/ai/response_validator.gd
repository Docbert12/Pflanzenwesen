class_name ResponseValidator
extends RefCounted
## Prüft Modellantworten (UNTRUSTED DATA) in sieben Stufen, bevor irgendetwas davon wirken darf:
##   1 Größe und Format     – Länge begrenzt, gültiges JSON-Objekt
##   2 Schema und Typen     – Pflichtfelder, keine unbekannten Felder, Typen, Aufzählungen, Längen
##   3 IDs                  – nur IDs aus den angebotenen Kandidaten; das Modell vergibt nie eigene IDs
##   4 Wesen und Sitzung    – passende Anfrage-ID, passendes Wesen, gleiche Welt/Sitzung, Wesen lebt
##   5 Erlaubte Handlungen  – nur Handlungen/Ziele aus der für diese Anfrage erlaubten Liste
##   6 Wissen, Fähigkeiten  – eigenes Wissen (Nahrungsgedächtnis, Themen) und aktuelle Körperfähigkeiten
##   7 Aktuelle Voraussetzungen – Alter des Zustands, Ziele noch vorhanden, keine bereits gescheiterte Wiederholung
## Freitext (short_explanation, optional_text) wird nur bereinigt angezeigt und NIE ausgewertet.
## Diese Prüfung ersetzt keine Prüfung im Handlungssystem: jeder Schritt wird bei Ausführung erneut geprüft.

const STAGES := {1: "Größe/Format", 2: "Schema/Typen", 3: "IDs", 4: "Wesen/Sitzung", 5: "erlaubte Handlungen", 6: "Wissen/Fähigkeiten", 7: "aktuelle Voraussetzungen"}
const DECISION_KEYS := ["request_id", "actor_id", "goal_type", "proposed_steps", "referenced_memory_ids", "uncertainty", "interpretation", "short_explanation"]
const DECISION_REQUIRED := ["request_id", "actor_id", "goal_type", "proposed_steps", "referenced_memory_ids", "uncertainty", "short_explanation"]
const TALK_KEYS := ["request_id", "speaker_id", "listener_id", "intent", "subject_id", "referenced_memory_ids", "expressed_certainty", "optional_text"]
const TALK_REQUIRED := ["request_id", "speaker_id", "listener_id", "intent", "subject_id", "referenced_memory_ids", "expressed_certainty"]
const INTERPRETATIONS := ["none", "zufall", "zusammenhang_vermutet", "nicht_entscheidbar"]
const INTENTS := ["none", "ask_food", "offer_help", "point_food", "share_experience", "share_guess", "explain_procedure"]
const EXPERIMENT_KEYS := ["request_id", "actor_id", "question", "expected_effect", "proposed_steps", "uncertainty", "short_explanation"]
const WORK_KEYS := ["request_id", "actor_id", "goal", "proposed_steps", "uncertainty", "short_explanation"]
const WORK_GOALS := ["lagern", "bauen", "schmelzen", "keep_current"]
const WORK_STEP_FIELDS := ["op", "object_id", "target_id", "dest_id", "mode", "head_id", "fiber_id", "heater_id", "mold_id"]
const WORK_MODES := ["deposit", "place", "put_in", "bring"]
const EXPECTED_EFFECTS := ["form_change", "breaks", "tool_holds", "melts", "cast_piece", "properties", "unknown"]
const EXPERIMENT_OPS := ["inspect", "equip", "release", "strike", "deform", "connect", "disconnect", "heat", "wait_molten", "pour"]
const STEP_FIELDS := ["op", "object_id", "target_id", "head_id", "fiber_id", "heater_id", "mold_id", "strikes"]
## Prüfcodes der Handlungsschnittstelle, die nur vom aktuellen Zustand abhängen (Reichweite, volle Hand,
## noch nicht geschmolzen …): sie werden vor der Ausführung jedes Schritts erneut geprüft.
const STATE_DEPENDENT_CODES := ["out_of_reach", "hands_full", "not_liquid", "busy", "heater_full", "too_hot", "self_target", "held_by_other", "reserved", "in_container", "empty"]
## Zieltyp jedes Schritts: welche Kandidatenart ist erlaubt
const TARGET_KIND := {"go_to": "food_or_creature", "pick_up": "food", "eat": "food_or_none", "give_food": "creature", "request_food": "creature",
	"offer_food": "creature", "wait": "none", "explore": "none", "raise_arms": "none", "talk": "creature"}


static func _fail(stage: int, code: String, msg: String) -> Dictionary:
	return {"ok": false, "stage": stage, "stage_name": STAGES[stage], "code": code, "message": "Stufe %d (%s): %s" % [stage, STAGES[stage], msg], "value": {}}


static func _is_int(v) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and v == floor(v) and absf(v) < 1e12)


static func _is_num(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v))


## Gemeinsame Stufen 1–2. Rückgabe {"ok", "data"} oder Fehler.
static func _parse(content: String, max_chars: int, keys: Array, required: Array) -> Dictionary:
	if content.length() > max_chars:
		return _fail(1, "too_large", "Antwort zu lang (%d > %d Zeichen)." % [content.length(), max_chars])
	var j := JSON.new()
	if j.parse(content) != OK:
		return _fail(1, "invalid_json", "Kein gültiges JSON (%s)." % j.get_error_message())
	if typeof(j.data) != TYPE_DICTIONARY:
		return _fail(1, "invalid_json", "JSON ist kein Objekt.")
	var d: Dictionary = j.data
	for k in required:
		if not d.has(k):
			return _fail(2, "schema", "Pflichtfeld „%s“ fehlt." % k)
	for k in d:
		if not str(k) in keys:
			return _fail(2, "schema", "Unbekanntes Feld „%s“." % OllamaClient.sanitize(str(k), 40))
	return {"ok": true, "data": d}


## Entscheidungs-/Deutungsantwort prüfen.
## entry: Warteschlangeneintrag {id, actor, session, kind, cand, allowed, state_t}
static func validate_decision(content: String, entry: Dictionary, session: int, ctx: LifeContext, max_chars: int, max_state_age_s: float) -> Dictionary:
	var p := _parse(content, max_chars, DECISION_KEYS, DECISION_REQUIRED)
	if not p["ok"]:
		return p
	var d: Dictionary = p["data"]
	# 2 Schema/Typen
	if not _is_int(d["request_id"]) or not _is_int(d["actor_id"]):
		return _fail(2, "schema", "request_id/actor_id müssen ganze Zahlen sein.")
	if typeof(d["goal_type"]) != TYPE_STRING or not d["goal_type"] in ContextBuilder.GOAL_TYPES:
		return _fail(2, "schema", "Unbekannter Zieltyp „%s“." % OllamaClient.sanitize(str(d["goal_type"]), 40))
	if typeof(d["proposed_steps"]) != TYPE_ARRAY or d["proposed_steps"].size() > 5:
		return _fail(2, "schema", "proposed_steps muss eine Liste mit höchstens 5 Schritten sein.")
	if typeof(d["referenced_memory_ids"]) != TYPE_ARRAY or d["referenced_memory_ids"].size() > 5 or not d["referenced_memory_ids"].all(func(x): return _is_int(x)):
		return _fail(2, "schema", "referenced_memory_ids muss eine Liste mit höchstens 5 ganzen Zahlen sein.")
	if not _is_num(d["uncertainty"]) or float(d["uncertainty"]) < 0.0 or float(d["uncertainty"]) > 1.0:
		return _fail(2, "schema", "uncertainty muss eine Zahl von 0 bis 1 sein.")
	if typeof(d["short_explanation"]) != TYPE_STRING:
		return _fail(2, "schema", "short_explanation muss Text sein.")
	var interp := str(d.get("interpretation", "none"))
	if d.has("interpretation") and (typeof(d["interpretation"]) != TYPE_STRING or not interp in INTERPRETATIONS):
		return _fail(2, "schema", "Unbekannte Deutung „%s“." % OllamaClient.sanitize(interp, 40))
	var steps: Array = []
	for s in d["proposed_steps"]:
		if typeof(s) != TYPE_DICTIONARY or not s.has("action") or not s.has("target_id") or typeof(s["action"]) != TYPE_STRING or not _is_int(s["target_id"]):
			return _fail(2, "schema", "Ungültiger Schritt (action/target_id).")
		for k in s:
			if not str(k) in ["action", "target_id", "intent"]:
				return _fail(2, "schema", "Unbekanntes Schrittfeld „%s“." % OllamaClient.sanitize(str(k), 40))
		var it := str(s.get("intent", "none"))
		if s.has("intent") and (typeof(s["intent"]) != TYPE_STRING or not it in INTENTS):
			return _fail(2, "schema", "Unbekannte Gesprächsabsicht.")
		steps.append({"action": str(s["action"]), "target": int(s["target_id"]), "intent": it})
	# 4 Wesen/Sitzung (vor IDs: eine fremde Antwort soll nie weiter geprüft werden)
	var w := _check_actor(int(d["request_id"]), int(d["actor_id"]), entry, session, ctx)
	if not w.is_empty():
		return w
	# 3 IDs
	var cand: Dictionary = entry["cand"]
	for s2 in steps:
		var tk: String = TARGET_KIND.get(s2["action"], "")
		var t := int(s2["target"])
		if tk == "":
			continue      # unbekannte Handlung → Stufe 5
		var is_food: bool = t in cand["food"]
		var is_cr: bool = t in cand["creatures"]
		var ok := false
		match tk:
			"none":
				ok = t == 0
			"food":
				ok = is_food
			"creature":
				ok = is_cr
			"food_or_none":
				ok = t == 0 or is_food
			"food_or_creature":
				ok = is_food or is_cr
		if not ok:
			return _fail(3, "unknown_id", "Ziel %d für „%s“ ist keine angebotene Kandidaten-ID." % [t, s2["action"]])
	var mids: Array = []
	for m in d["referenced_memory_ids"]:
		if not int(m) in cand["memories"]:
			return _fail(3, "unknown_id", "Erinnerung %d wurde nicht angeboten." % int(m))
		mids.append(int(m))
	# 5 Erlaubte Handlungen / Ziele
	var allowed: Array = entry["allowed"]
	for s3 in steps:
		if not s3["action"] in ContextBuilder.PLAN_ACTIONS or not s3["action"] in allowed:
			return _fail(5, "forbidden_action", "Handlung „%s“ ist nicht erlaubt (erlaubt: %s)." % [OllamaClient.sanitize(s3["action"], 40), ", ".join(allowed)])
	var kind := str(entry["kind"])
	if kind == "interpret" and (d["goal_type"] != "keep_current" or not steps.is_empty()):
		return _fail(5, "forbidden_action", "Bei einer Deutung sind weder Ziel noch Schritte erlaubt.")
	# 6 Wissen/Fähigkeiten (aktueller Körper)
	var cr := ctx.creature(int(entry["actor"]))
	var carrying := cr.carried_item_id != 0
	var will_carry := carrying
	for s4 in steps:
		var a: String = s4["action"]
		if a in ["go_to", "explore"] and not bool(cr.caps.get("can_walk", false)):
			return _fail(6, "capability", "Kann nicht gehen.")
		if a in ["pick_up", "give_food", "offer_food"] and float(cr.caps.get("grasp", 0.0)) <= 0.0:
			return _fail(6, "capability", "Kann nicht greifen.")
		if a == "eat" and float(cr.caps.get("mouth", 0.0)) <= 0.0:
			return _fail(6, "capability", "Kann nicht essen.")
		if a == "raise_arms" and float(cr.caps.get("gesture", 0.0)) <= 0.0:
			return _fail(6, "capability", "Kann die Arme nicht heben.")
		var tg := int(s4["target"])
		if (a in ["pick_up", "eat"] and tg != 0) or (a == "go_to" and tg in cand["food"]):
			if not cr.food_memory.has(tg) and tg != cr.carried_item_id:
				return _fail(6, "unknown_knowledge", "Nahrung #%d ist dem Wesen nicht (mehr) bekannt." % tg)
		if a == "pick_up":
			if will_carry:
				return _fail(6, "impossible", "Aufnehmen, obwohl die Hände schon voll wären.")
			will_carry = true
		elif a == "eat" and int(s4["target"]) == 0:
			if not will_carry:
				return _fail(6, "impossible", "Getragenes essen, ohne etwas zu tragen.")
			will_carry = false
		elif a in ["give_food", "offer_food"]:
			if not will_carry:
				return _fail(6, "impossible", "Geben/Anbieten ohne getragene Nahrung.")
			will_carry = false
	# 7 Aktuelle Voraussetzungen
	var age := ctx.now() - float(entry["state_t"])
	if age > max_state_age_s:
		return _fail(7, "stale_state", "Abgefragter Zustand ist %.0f s alt (höchstens %.0f s)." % [age, max_state_age_s])
	for s5 in steps:
		if TARGET_KIND.get(s5["action"], "") == "creature":
			var tc := ctx.creature(int(s5["target"]))
			if tc == null or not tc.alive:
				return _fail(7, "target_gone", "Wesen #%d lebt nicht mehr." % int(s5["target"]))
	var sig := PlanManager.signature(str(d["goal_type"]), steps)
	if not steps.is_empty() and PlanManager.is_blocked(cr, sig, ctx):
		return _fail(7, "repeated_failure", "Derselbe Plan ist kürzlich gescheitert – keine Wiederholung.")
	var expl := OllamaClient.sanitize(str(d["short_explanation"]), 200)
	return {"ok": true, "stage": 7, "stage_name": "", "code": "ok", "message": "gültig",
		"value": {"goal_type": str(d["goal_type"]), "steps": steps, "memory_ids": mids, "uncertainty": float(d["uncertainty"]),
			"interpretation": interp, "explanation": expl, "signature": sig}}


static func _check_actor(rid: int, aid: int, entry: Dictionary, session: int, ctx: LifeContext) -> Dictionary:
	if rid != int(entry["id"]):
		return _fail(4, "wrong_request", "Antwort gehört zu Anfrage %d, erwartet %d." % [rid, int(entry["id"])])
	if aid != int(entry["actor"]):
		return _fail(4, "wrong_actor", "Antwort nennt Wesen #%d, angefragt war #%d." % [aid, int(entry["actor"])])
	if int(entry["session"]) != session:
		return _fail(4, "stale_session", "Antwort stammt aus einer früheren Welt/Sitzung.")
	var cr := ctx.creature(aid)
	if cr == null or not cr.alive:
		return _fail(4, "actor_dead", "Wesen #%d lebt nicht mehr." % aid)
	return {}


## Gesprächsantwort prüfen. entry zusätzlich: listener, cand.topics
static func validate_talk(content: String, entry: Dictionary, session: int, ctx: LifeContext, max_chars: int, max_state_age_s: float) -> Dictionary:
	var p := _parse(content, max_chars, TALK_KEYS, TALK_REQUIRED)
	if not p["ok"]:
		return p
	var d: Dictionary = p["data"]
	if not _is_int(d["request_id"]) or not _is_int(d["speaker_id"]) or not _is_int(d["listener_id"]) or not _is_int(d["subject_id"]):
		return _fail(2, "schema", "IDs müssen ganze Zahlen sein.")
	if typeof(d["intent"]) != TYPE_STRING or not d["intent"] in INTENTS:
		return _fail(2, "schema", "Unbekannte Absicht „%s“." % OllamaClient.sanitize(str(d["intent"]), 40))
	if not _is_num(d["expressed_certainty"]) or float(d["expressed_certainty"]) < 0.0 or float(d["expressed_certainty"]) > 1.0:
		return _fail(2, "schema", "expressed_certainty muss eine Zahl von 0 bis 1 sein.")
	if typeof(d["referenced_memory_ids"]) != TYPE_ARRAY or d["referenced_memory_ids"].size() > 3 or not d["referenced_memory_ids"].all(func(x): return _is_int(x)):
		return _fail(2, "schema", "referenced_memory_ids ungültig.")
	if d.has("optional_text") and typeof(d["optional_text"]) != TYPE_STRING:
		return _fail(2, "schema", "optional_text muss Text sein.")
	var w := _check_actor(int(d["request_id"]), int(d["speaker_id"]), entry, session, ctx)
	if not w.is_empty():
		return w
	if int(d["listener_id"]) != int(entry["listener"]):
		return _fail(4, "wrong_listener", "Antwort nennt Zuhörer #%d, angefragt war #%d." % [int(d["listener_id"]), int(entry["listener"])])
	var topics: Dictionary = entry["cand"]["topics"]
	var sid := int(d["subject_id"])
	if d["intent"] == "none":
		return {"ok": true, "stage": 7, "stage_name": "", "code": "nothing", "message": "Modell: nichts sagen", "value": {"intent": "none"}}
	if not topics.has(sid):
		return _fail(3, "unknown_id", "Thema %d wurde nicht angeboten." % sid)
	for m in d["referenced_memory_ids"]:
		if not int(m) in entry["cand"]["memories"]:
			return _fail(3, "unknown_id", "Erinnerung %d wurde nicht angeboten." % int(m))
	var topic: Dictionary = topics[sid]
	if str(d["intent"]) != str(topic["absicht"]):
		return _fail(5, "forbidden_action", "Absicht „%s“ passt nicht zum Thema („%s“)." % [d["intent"], topic["absicht"]])
	# 6 Wissen: Thema muss JETZT noch zum eigenen Wissen gehören
	var cr := ctx.creature(int(entry["actor"]))
	var now_topics: Array = ctx.comm.topics(cr, int(entry["listener"]), ctx)
	var still := false
	for t in now_topics:
		if t["absicht"] == topic["absicht"] and t["statement"].get("type", "") == topic["statement"].get("type", "") and int(t["statement"].get("id", 0)) == int(topic["statement"].get("id", 0)) \
				and str(t["statement"].get("key", "")) == str(topic["statement"].get("key", "")):
			still = true
			topic = t
			break
	if not still:
		return _fail(6, "unknown_knowledge", "Der Inhalt gehört nicht mehr zum eigenen Wissen des Sprechers.")
	var cert := float(d["expressed_certainty"])
	var note := ""
	if cert > float(topic["eigene_sicherheit"]) + 1e-6:
		note = "geäußerte Sicherheit %.2f auf eigene %.2f begrenzt" % [cert, float(topic["eigene_sicherheit"])]
		cert = float(topic["eigene_sicherheit"])
	var age := ctx.now() - float(entry["state_t"])
	if age > max_state_age_s:
		return _fail(7, "stale_state", "Abgefragter Zustand ist %.0f s alt." % age)
	var l := ctx.creature(int(entry["listener"]))
	if l == null or not l.alive:
		return _fail(7, "target_gone", "Zuhörer lebt nicht mehr.")
	var ck := ctx.comm.can_talk(cr, l.id, ctx, false)
	if not ck["ok"]:
		return _fail(7, "precondition", ck["message"])
	return {"ok": true, "stage": 7, "stage_name": "", "code": "ok", "message": "gültig" + (" (%s)" % note if note != "" else ""),
		"value": {"intent": str(d["intent"]), "topic": topic, "certainty": cert, "model_text": OllamaClient.sanitize(str(d.get("optional_text", "")), 120)}}


## Versuchsvorschlag prüfen (Prompt 6). Ergebnis ist höchstens eine HYPOTHESE des Wesens – kein
## Gegenstand, keine Entdeckung. Jeder Schritt wird über die echte Handlungsschnittstelle
## (ActionExecutor.dry_run) geprüft; nur zustandsabhängige Codes sind zulässig und werden vor der
## Ausführung erneut geprüft.
static func validate_experiment(content: String, entry: Dictionary, session: int, ctx: LifeContext, max_chars: int, max_state_age_s: float) -> Dictionary:
	var p := _parse(content, max_chars, EXPERIMENT_KEYS, EXPERIMENT_KEYS)
	if not p["ok"]:
		return p
	var d: Dictionary = p["data"]
	if not _is_int(d["request_id"]) or not _is_int(d["actor_id"]):
		return _fail(2, "schema", "request_id/actor_id müssen ganze Zahlen sein.")
	if typeof(d["question"]) != TYPE_STRING or typeof(d["short_explanation"]) != TYPE_STRING:
		return _fail(2, "schema", "question/short_explanation müssen Text sein.")
	if typeof(d["expected_effect"]) != TYPE_STRING or not d["expected_effect"] in EXPECTED_EFFECTS:
		return _fail(2, "schema", "Unbekannte erwartete Wirkung „%s“." % OllamaClient.sanitize(str(d["expected_effect"]), 40))
	if not _is_num(d["uncertainty"]) or float(d["uncertainty"]) < 0.0 or float(d["uncertainty"]) > 1.0:
		return _fail(2, "schema", "uncertainty muss eine Zahl von 0 bis 1 sein.")
	if typeof(d["proposed_steps"]) != TYPE_ARRAY or d["proposed_steps"].is_empty() or d["proposed_steps"].size() > 5:
		return _fail(2, "schema", "proposed_steps muss 1–5 Schritte enthalten.")
	var raw: Array = []
	for s in d["proposed_steps"]:
		if typeof(s) != TYPE_DICTIONARY or not s.has("op") or typeof(s["op"]) != TYPE_STRING:
			return _fail(2, "schema", "Ungültiger Schritt (op fehlt).")
		for k in s:
			if not str(k) in STEP_FIELDS:
				return _fail(2, "schema", "Unbekanntes Schrittfeld „%s“." % OllamaClient.sanitize(str(k), 40))
			if str(k) != "op" and not _is_int(s[k]):
				return _fail(2, "schema", "Schrittfeld „%s“ muss eine ganze Zahl sein." % str(k))
		raw.append(s)
	var w := _check_actor(int(d["request_id"]), int(d["actor_id"]), entry, session, ctx)
	if not w.is_empty():
		return w
	# 3 IDs: nur angebotene Gegenstände/Heizungen
	var cand: Dictionary = entry["cand"]
	var objs: Array = cand.get("objects", [])
	var heaters: Array = cand.get("heaters", [])
	for s2 in raw:
		for f in ["object_id", "target_id", "head_id", "fiber_id", "mold_id"]:
			if s2.has(f) and int(s2[f]) != 0 and not int(s2[f]) in objs:
				return _fail(3, "unknown_id", "%s %d ist kein angebotener, dem Wesen bekannter Gegenstand." % [f, int(s2[f])])
		if s2.has("heater_id") and int(s2["heater_id"]) != 0 and not int(s2["heater_id"]) in heaters:
			return _fail(3, "unknown_id", "Heizung %d wurde nicht angeboten." % int(s2["heater_id"]))
	# 5 Erlaubte Vorgänge
	for s3 in raw:
		if not str(s3["op"]) in EXPERIMENT_OPS:
			return _fail(5, "forbidden_action", "Vorgang „%s“ ist nicht erlaubt." % OllamaClient.sanitize(str(s3["op"]), 40))
	# Übersetzung in Versuchsschritte (ExperimentSystem-Format)
	var steps: Array = []
	for s4 in raw:
		var st := {"op": str(s4["op"])}
		match st["op"]:
			"deform", "strike":
				st["target"] = int(s4.get("target_id", s4.get("object_id", 0)))
				if st["op"] == "deform":
					st["params"] = {"strikes": clampi(int(s4.get("strikes", 8)), 1, 20)}
			"connect":
				st["obj"] = int(s4.get("object_id", 0))
				st["head"] = int(s4.get("head_id", 0))
				st["fiber"] = int(s4.get("fiber_id", 0))
			"heat":
				st["obj"] = int(s4.get("object_id", 0))
				st["heater"] = int(s4.get("heater_id", 0))
			"pour":
				st["obj"] = int(s4.get("object_id", 0))
				st["mold"] = int(s4.get("mold_id", 0))
			"release":
				pass
			_:
				st["obj"] = int(s4.get("object_id", 0))
		steps.append(st)
	# 6 Wissen/Fähigkeiten über die echte Handlungsschnittstelle
	var cr := ctx.creature(int(entry["actor"]))
	if float(cr.caps.get("grasp", 0.0)) <= 0.0:
		return _fail(6, "capability", "Wesen kann nicht greifen – keine Werkzeugversuche möglich.")
	var es := ExperimentSystem.new()
	for st2 in steps:
		var op := str(st2["op"])
		if op in ["inspect", "equip", "deform", "strike", "connect", "heat", "wait_molten", "pour"]:
			var need := int(st2.get("obj", st2.get("target", 0)))
			if need == 0:
				return _fail(6, "missing_target", "Schritt „%s“ braucht einen bekannten Gegenstand." % op)
		if op in ["release", "wait_molten"]:
			continue
		var req: Dictionary = es._request_for(cr, st2, ctx)
		var dry := ctx.executor.dry_run(cr.id, str(req["type"]), int(req["target"]), null, req["params"])
		if not dry.ok and not dry.code in STATE_DEPENDENT_CODES:
			return _fail(6, dry.code, "Schritt „%s“ ist über die Handlungsschnittstelle unmöglich: %s" % [op, dry.message])
	# 7 Aktuelle Voraussetzungen
	var age := ctx.now() - float(entry["state_t"])
	if age > max_state_age_s:
		return _fail(7, "stale_state", "Abgefragter Zustand ist %.0f s alt (höchstens %.0f s)." % [age, max_state_age_s])
	return {"ok": true, "stage": 7, "stage_name": "", "code": "ok", "message": "gültig (als ungeprüfte Hypothese)",
		"value": {"question": OllamaClient.sanitize(str(d["question"]), 160), "expected": str(d["expected_effect"]), "steps": steps,
			"uncertainty": float(d["uncertainty"]), "explanation": OllamaClient.sanitize(str(d["short_explanation"]), 200)}}


## Prompt 6B: Arbeitsvorschlag nach gescheiterter Kette. Stufen wie bei den übrigen Antworten; zusätzlich
## prüft WorkSystem.validate_model_plan das Wissen des Wesens. Ergebnis ist nur ein VORSCHLAG, der über den
## Entscheider als Option konkurriert; jeder Schritt läuft später über geprüfte Spielhandlungen.
static func validate_work(content: String, entry: Dictionary, session: int, ctx: LifeContext, max_chars: int, _max_state_age_s: float) -> Dictionary:
	var p := _parse(content, max_chars, WORK_KEYS, WORK_KEYS)
	if not p["ok"]:
		return p
	var d: Dictionary = p["data"]
	if not _is_int(d["request_id"]) or not _is_int(d["actor_id"]):
		return _fail(2, "schema", "request_id/actor_id müssen ganze Zahlen sein.")
	if typeof(d["goal"]) != TYPE_STRING or not d["goal"] in WORK_GOALS:
		return _fail(2, "schema", "Unbekanntes Ziel „%s“." % OllamaClient.sanitize(str(d["goal"]), 40))
	if typeof(d["short_explanation"]) != TYPE_STRING:
		return _fail(2, "schema", "short_explanation muss Text sein.")
	if not _is_num(d["uncertainty"]) or float(d["uncertainty"]) < 0.0 or float(d["uncertainty"]) > 1.0:
		return _fail(2, "schema", "uncertainty muss eine Zahl von 0 bis 1 sein.")
	if typeof(d["proposed_steps"]) != TYPE_ARRAY or d["proposed_steps"].size() > 10 or (d["goal"] != "keep_current" and d["proposed_steps"].is_empty()):
		return _fail(2, "schema", "proposed_steps muss 1–10 Schritte enthalten.")
	var raw: Array = []
	for s in d["proposed_steps"]:
		if typeof(s) != TYPE_DICTIONARY or not s.has("op") or typeof(s["op"]) != TYPE_STRING:
			return _fail(2, "schema", "Ungültiger Schritt (op fehlt).")
		for k in s:
			if not str(k) in WORK_STEP_FIELDS:
				return _fail(2, "schema", "Unbekanntes Schrittfeld „%s“." % OllamaClient.sanitize(str(k), 40))
			if str(k) == "mode":
				if typeof(s[k]) != TYPE_STRING or not s[k] in WORK_MODES:
					return _fail(2, "schema", "Unbekannte Ablageart „%s“." % OllamaClient.sanitize(str(s[k]), 20))
			elif str(k) != "op" and not _is_int(s[k]):
				return _fail(2, "schema", "Schrittfeld „%s“ muss eine ganze Zahl sein." % str(k))
		raw.append(s)
	var w := _check_actor(int(d["request_id"]), int(d["actor_id"]), entry, session, ctx)
	if not w.is_empty():
		return w
	var explanation := OllamaClient.sanitize(str(d["short_explanation"]), 200)
	if d["goal"] == "keep_current":
		return {"ok": true, "value": {"goal": "keep_current", "explanation": explanation, "uncertainty": float(d["uncertainty"])}}
	# 3 IDs: nur angebotene Gegenstände, Heizungen, Lager, Baustellen
	var cand: Dictionary = entry["cand"]
	var objs: Array = cand.get("objects", [])
	var heaters: Array = cand.get("heaters", [])
	var dests: Array = cand.get("storages", []) + cand.get("sites", []) + objs
	for s2 in raw:
		for f in ["object_id", "target_id", "head_id", "fiber_id", "mold_id"]:
			if s2.has(f) and int(s2[f]) != 0 and not int(s2[f]) in objs:
				return _fail(3, "unknown_id", "%s %d ist kein angebotener, dem Wesen bekannter Gegenstand." % [f, int(s2[f])])
		if s2.has("heater_id") and int(s2["heater_id"]) != 0 and not int(s2["heater_id"]) in heaters:
			return _fail(3, "unknown_id", "Heizung %d wurde nicht angeboten." % int(s2["heater_id"]))
		if s2.has("dest_id") and int(s2["dest_id"]) != 0 and not int(s2["dest_id"]) in dests:
			return _fail(3, "unknown_id", "Ziel %d (Lager/Baustelle/Tiegel) wurde nicht angeboten." % int(s2["dest_id"]))
	# 5 erlaubte Schritte
	for s3 in raw:
		if not str(s3["op"]) in WorkSystem.OPS or str(s3["op"]) == "mark_site":
			return _fail(5, "forbidden_action", "Schritt „%s“ ist nicht erlaubt." % OllamaClient.sanitize(str(s3["op"]), 40))
	# Übersetzung ins WorkSystem-Format
	var steps: Array = []
	var dest := 0
	var target := 0
	for s4 in raw:
		var st := {"op": str(s4["op"])}
		for pair in [["object_id", "obj"], ["target_id", "target"], ["dest_id", "dest"], ["head_id", "head"], ["fiber_id", "fiber"], ["heater_id", "heater"], ["mold_id", "mold"]]:
			if s4.has(pair[0]):
				st[pair[1]] = int(s4[pair[0]])
		if s4.has("mode"):
			st["mode"] = str(s4["mode"])
		if st["op"] == "carry" and not st.has("mode"):
			st["mode"] = "deposit"
		if st["op"] == "collect":
			st["pieces"] = []
		if dest == 0 and st.has("dest"):
			dest = int(st["dest"])
		if target == 0 and st.has("target") and st["op"] in ["break", "work_copper"]:
			target = int(st["target"])
		steps.append(st)
	# 6 Wissen und Fähigkeiten des Wesens
	var cr := ctx.creature(int(entry["actor"]))
	if float(cr.caps.get("grasp", 0.0)) <= 0.0:
		return _fail(6, "capability", "Wesen kann nicht greifen – kein Arbeitsablauf möglich.")
	var vm := ctx.work.validate_model_plan(cr, {"goal": str(d["goal"]), "dest": dest, "target": target, "steps": steps}, ctx)
	if not vm["ok"]:
		return _fail(6, "knowledge", "; ".join((vm["errors"] as Array).slice(0, 2)))
	# 7 aktuelle Voraussetzungen: keine laufende Kette; Ziele existieren noch
	if ctx.work.active(cr) != null:
		return _fail(7, "busy", "Wesen arbeitet bereits an einer Kette.")
	for st2 in steps:
		if st2.has("dest") and ctx.position_of(int(st2["dest"])) == null:
			return _fail(7, "target_lost", "Ziel %d existiert nicht mehr." % int(st2["dest"]))
		if st2.has("heater") and not ctx.heaters.has(int(st2["heater"])):
			return _fail(7, "no_heater", "Heizung %d existiert nicht mehr." % int(st2["heater"]))
	var plan: Dictionary = vm["plan"]
	return {"ok": true, "value": {"goal": str(d["goal"]), "plan": plan, "explanation": explanation, "uncertainty": float(d["uncertainty"])}}
