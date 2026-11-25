class_name MockOllama
extends RefCounted
## SIMULIERTER Testdienst mit derselben Schnittstelle wie HttpTransport.
## KEIN Ollama, kein Sprachmodell, keine Netzwerkverbindung. Er beantwortet /api/version, /api/tags,
## /api/ps und /api/chat nach festen Regeln (oder einer vom Test gesetzten Funktion), damit Warteschlange,
## Prüfung, Pläne und Fehlerfälle reproduzierbar getestet werden können. Alle Ergebnisse tragen
## simulated=true und werden in Oberfläche, Protokoll und Testbericht als SIMULIERT ausgewiesen.

const simulated := true
const VERSION := "0.0.0-SIMULIERT"
const MODEL := "simuliert-regelbasiert"

## Betriebsart: "ok" | "down" (nicht erreichbar) | "timeout" (antwortet nie) | "invalid_json" | "empty" |
## "missing_model" (404) | "http_500" | "slow" (latency_ms gilt) – für Inhaltsfehler responder setzen.
var mode: String = "ok"
var latency_ms: int = 0
var models: Array = [MODEL]
## Optionale Antwortfunktion: func(request: Dictionary, context: Dictionary) -> Variant
## (Dictionary → als JSON-Inhalt; String → wörtlich als Inhalt).
var responder: Callable = Callable()
var requests: Array = []          # Protokoll aller empfangenen Anfragen (für Tests, begrenzt)
var _pending: Dictionary = {}
var _next: int = 1


func describe() -> String:
	return "SIMULIERTER Testdienst (kein Ollama)"


func active_count() -> int:
	return _pending.size()


func start(method: String, path: String, body: String, now_ms: int) -> int:
	var h := _next
	_next += 1
	var req := {"method": method, "path": path, "body": body, "t": now_ms}
	requests.append(req)
	while requests.size() > 200:
		requests.pop_front()
	_pending[h] = req
	return h


func cancel(h: int) -> void:
	_pending.erase(h)


func cancel_all() -> void:
	_pending.clear()


func poll(now_ms: int) -> Array:
	var out: Array = []
	for h in _pending.keys():
		var req: Dictionary = _pending[h]
		if mode == "timeout":
			continue
		if now_ms - int(req["t"]) < latency_ms:
			continue
		_pending.erase(h)
		out.append(_answer(h, req))
	return out


func _answer(h: int, req: Dictionary) -> Dictionary:
	var r := {"handle": h, "status": 200, "body": "", "error": "", "detail": ""}
	match mode:
		"down":
			r["error"] = "unreachable"
			r["detail"] = "SIMULIERT: Dienst nicht erreichbar."
			r["status"] = 0
			return r
		"http_500":
			r["status"] = 500
			r["body"] = JSON.stringify({"error": "SIMULIERT: interner Fehler"})
			return r
	var path := str(req["path"])
	if path == "/api/version":
		r["body"] = JSON.stringify({"version": VERSION})
	elif path == "/api/tags":
		var ms: Array = []
		for m in models:
			ms.append({"name": m, "model": m, "size": 0, "details": {"parameter_size": "simuliert", "quantization_level": "-"}})
		r["body"] = JSON.stringify({"models": ms})
	elif path == "/api/ps":
		r["body"] = JSON.stringify({"models": []})
	elif path == "/api/chat":
		var body = JSON.parse_string(str(req["body"]))
		if typeof(body) != TYPE_DICTIONARY:
			r["status"] = 400
			r["body"] = JSON.stringify({"error": "invalid request"})
			return r
		if mode == "missing_model" or not str(body.get("model", "")) in models:
			r["status"] = 404
			r["body"] = JSON.stringify({"error": "model '%s' not found" % str(body.get("model", ""))})
			return r
		var content := ""
		if mode == "invalid_json":
			content = "{\"request_id\": 1, \"goal_type\": "
		elif mode == "empty":
			content = ""
		else:
			var ctxd := _context_of(body)
			var v = responder.call(body, ctxd) if responder.is_valid() else default_answer(ctxd)
			content = v if typeof(v) == TYPE_STRING else JSON.stringify(v)
		r["body"] = JSON.stringify({"model": body.get("model", ""), "created_at": "SIMULIERT", "done": true, "done_reason": "stop",
			"message": {"role": "assistant", "content": content}, "eval_count": content.length() / 4, "total_duration": 1000000})
	else:
		r["status"] = 404
		r["body"] = JSON.stringify({"error": "SIMULIERT: unbekannter Pfad"})
	return r


## Der Kontext steht als JSON in der letzten Benutzernachricht (so baut ContextBuilder die Anfrage).
static func _context_of(body: Dictionary) -> Dictionary:
	var msgs: Array = body.get("messages", [])
	for i in range(msgs.size() - 1, -1, -1):
		if str(msgs[i].get("role", "")) == "user":
			var c = JSON.parse_string(str(msgs[i].get("content", "")))
			if typeof(c) == TYPE_DICTIONARY:
				return c
	return {}


## Regelbasierte Antwort (deterministisch) – wählt nur aus den angebotenen Kandidaten.
static func default_answer(c: Dictionary) -> Dictionary:
	var req: Dictionary = c.get("anfrage", {})
	var kind := str(req.get("art", "plan"))
	var rid := int(req.get("request_id", 0))
	var aid := int(c.get("ich", {}).get("id", 0))
	var cand: Dictionary = c.get("kandidaten", {})
	var mems: Array = []
	for m in c.get("erinnerungen", []).slice(0, 2):
		mems.append(int(m.get("id", 0)))
	if kind == "talk":
		var topics: Array = cand.get("themen", [])
		var lid := int(c.get("zuhoerer", {}).get("id", 0))
		if topics.is_empty():
			return {"request_id": rid, "speaker_id": aid, "listener_id": lid, "intent": "none", "subject_id": 0, "referenced_memory_ids": [],
				"expressed_certainty": 0.0, "optional_text": "(simuliert) nichts zu sagen"}
		var t: Dictionary = topics[0]
		return {"request_id": rid, "speaker_id": aid, "listener_id": lid, "intent": str(t.get("absicht", "none")), "subject_id": int(t.get("thema_id", 0)),
			"referenced_memory_ids": [], "expressed_certainty": float(t.get("eigene_sicherheit", 0.5)), "optional_text": "(simuliert) Hinweis"}
	if kind == "work":
		# Prompt 6B: einfacher, deterministischer Arbeitsvorschlag nur aus angebotenen Kandidaten
		var ar: Dictionary = c.get("arbeit", {})
		var tkw: Dictionary = c.get("technik", {})
		var last: Dictionary = ar.get("letzte_kette", {})
		var excl := {}
		var rx := RegEx.create_from_string("#(\\d+)")
		for mt in rx.search_all(str(last.get("grund", ""))):
			excl[int(mt.get_string(1))] = true
		var dest := 0
		var mode := "deposit"
		var goal := "lagern"
		for b in ar.get("baustellen", []):
			if str(last.get("ziel", "")) == "bauen" and int(b.get("plaetze_frei", 0)) > 0:
				dest = int(b["id"])
				mode = "place"
				goal = "bauen"
				break
		if dest == 0:
			for l in ar.get("lager", []):
				if bool(l.get("platz_frei", true)):
					dest = int(l["id"])
					break
		var wsteps: Array = []
		if dest != 0:
			for o in tkw.get("bekannte_gegenstaende", []):
				if wsteps.size() >= 2:
					break
				if str(o.get("form", "")) in ["lump", "block"] and not o.has("teile") and not excl.has(int(o["id"])):
					wsteps.append({"op": "carry", "object_id": int(o["id"]), "dest_id": dest, "mode": mode})
		if wsteps.is_empty():
			return {"request_id": rid, "actor_id": aid, "goal": "keep_current", "proposed_steps": [], "uncertainty": 0.9,
				"short_explanation": "(simuliert) Kein anderer Ablauf erkennbar."}
		wsteps.append({"op": "check"})
		return {"request_id": rid, "actor_id": aid, "goal": goal, "proposed_steps": wsteps, "uncertainty": 0.5,
			"short_explanation": "(simuliert) Andere, tragbare Stücke statt des gescheiterten Gegenstands."}
	if kind == "experiment":
		var tk: Dictionary = c.get("technik", {})
		var objs: Array = tk.get("bekannte_gegenstaende", [])
		var tool := 0
		var target := 0
		for o in objs:
			if tool == 0 and str(o.get("haerte", "")) == "hart" and str(o.get("gewicht", "")) in ["leicht", "mittel"]:
				tool = int(o["id"])
		for o in objs:
			if target == 0 and int(o["id"]) != tool and str(o.get("klang", "")).contains("nach"):
				target = int(o["id"])
		if tool != 0 and target != 0:
			return {"request_id": rid, "actor_id": aid, "question": "(simuliert) Wird #%d flacher, wenn ich mit #%d darauf schlage?" % [target, tool],
				"expected_effect": "form_change", "proposed_steps": [{"op": "equip", "object_id": tool}, {"op": "deform", "target_id": target, "strikes": 6}],
				"uncertainty": 0.6, "short_explanation": "(simuliert) Hartes Stück auf nachgiebiges Stück schlagen."}
		var first := int(objs[0]["id"]) if not objs.is_empty() else 0
		return {"request_id": rid, "actor_id": aid, "question": "(simuliert) Was ist #%d?" % first, "expected_effect": "properties",
			"proposed_steps": [{"op": "inspect", "object_id": first}], "uncertainty": 0.8, "short_explanation": "(simuliert) Erst genauer ansehen."}
	if kind == "interpret":
		return {"request_id": rid, "actor_id": aid, "goal_type": "keep_current", "proposed_steps": [], "referenced_memory_ids": mems,
			"uncertainty": 0.8, "interpretation": "nicht_entscheidbar", "short_explanation": "(simuliert) Die Erfahrungen reichen nicht für eine Deutung."}
	var foods: Array = cand.get("nahrung", [])
	var hunger := float(c.get("beduerfnisse", {}).get("hunger", 0.0))
	var can_grasp := bool(c.get("faehigkeiten", {}).get("greifen", false))
	if hunger >= 0.4 and not foods.is_empty():
		var f := int(foods[0].get("id", 0))
		var steps: Array = [{"action": "go_to", "target_id": f}]
		if can_grasp:
			steps.append_array([{"action": "pick_up", "target_id": f}, {"action": "eat", "target_id": 0}])
		else:
			steps.append({"action": "eat", "target_id": f})
		return {"request_id": rid, "actor_id": aid, "goal_type": "food", "proposed_steps": steps, "referenced_memory_ids": mems,
			"uncertainty": 0.3, "interpretation": "none", "short_explanation": "(simuliert) Bekannte Nahrung aufsuchen und essen."}
	return {"request_id": rid, "actor_id": aid, "goal_type": "explore", "proposed_steps": [{"action": "explore", "target_id": 0}, {"action": "wait", "target_id": 0}],
		"referenced_memory_ids": mems, "uncertainty": 0.6, "interpretation": "none", "short_explanation": "(simuliert) Umgebung erkunden."}
