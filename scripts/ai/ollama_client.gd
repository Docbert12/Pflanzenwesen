class_name OllamaClient
extends RefCounted
## Asynchroner Zugriff auf die lokale Ollama-API – ausschließlich ABFRAGEN:
##   GET /api/version, GET /api/tags (installierte Modelle), GET /api/ps (geladene Modelle), POST /api/chat.
## Es gibt bewusst KEINE Funktionen für pull/delete/create/copy/push oder Start/Stopp von Dienst
## oder Modellen. Antworten werden nur geparst, nicht interpretiert (das macht ResponseValidator).
## Transport: HttpTransport (echt) oder MockOllama (SIMULIERT, nur Tests/Entwicklung).
## Zeitbasis: clock() in Millisekunden Echtzeit (für Tests ersetzbar).

const ALLOWED := {"/api/version": "GET", "/api/tags": "GET", "/api/ps": "GET", "/api/chat": "POST"}

var settings: AISettings
var transport          # HttpTransport | MockOllama
var clock: Callable = Callable(Time, "get_ticks_msec")
var pending: Dictionary = {}     # handle -> {"meta", "kind", "started", "timeout_ms"}
var config_error: String = ""


func _init(p_settings: AISettings, p_transport = null) -> void:
	settings = p_settings
	configure(p_transport)


## Transport passend zu den Einstellungen (neu) aufbauen. Laufende Anfragen werden abgebrochen.
func configure(p_transport = null) -> void:
	if transport != null:
		transport.cancel_all()
	pending.clear()
	config_error = ""
	if p_transport != null:
		transport = p_transport
		return
	if settings.use_mock():
		transport = MockOllama.new()
		return
	var ep := settings.endpoint()
	var ht := HttpTransport.new()
	if not ep["ok"]:
		config_error = str(ep["message"])
	else:
		ht.setup(ep, settings.auth_headers(), float(settings.g("connect_timeout_s", 3.0)))
	transport = ht


func simulated() -> bool:
	return transport != null and transport.simulated


func now_ms() -> int:
	return int(clock.call())


func describe() -> String:
	return transport.describe() if transport != null else "-"


func busy_count() -> int:
	return pending.size()


func request_version(meta: Dictionary = {}) -> int:
	return _start("version", "/api/version", "", meta, int(float(settings.g("connect_timeout_s", 3.0)) * 1000.0) + 5000)


func request_tags(meta: Dictionary = {}) -> int:
	return _start("tags", "/api/tags", "", meta, int(float(settings.g("connect_timeout_s", 3.0)) * 1000.0) + 5000)


func request_ps(meta: Dictionary = {}) -> int:
	return _start("ps", "/api/ps", "", meta, int(float(settings.g("connect_timeout_s", 3.0)) * 1000.0) + 5000)


## Chat-Anfrage mit strukturierter Ausgabe (JSON-Schema im Feld format). Rückgabe: Kennung oder −1.
func request_chat(meta: Dictionary, messages: Array, schema: Dictionary) -> int:
	var model := str(settings.g("model", ""))
	var body := {"model": model, "messages": messages, "stream": false, "format": schema,
		"options": {"temperature": float(settings.g("temperature", 0.4)), "num_predict": int(settings.g("num_predict", 320)),
			"num_ctx": int(settings.g("num_ctx", 4096))},
		"keep_alive": str(settings.g("keep_alive", "15m"))}
	if settings.g("think", null) != null:
		body["think"] = bool(settings.g("think"))
	return _start("chat", "/api/chat", JSON.stringify(body), meta, int(float(settings.g("timeout_s", 90.0)) * 1000.0))


func _start(kind: String, path: String, body: String, meta: Dictionary, timeout_ms: int) -> int:
	if not ALLOWED.has(path):
		return -1      # Nur fest eingetragene Abfragepfade – nie aus Modelldaten
	if config_error != "":
		return -1
	var h: int = transport.start(ALLOWED[path], path, body, now_ms())
	pending[h] = {"meta": meta, "kind": kind, "started": now_ms(), "timeout_ms": timeout_ms}
	return h


func cancel(h: int) -> void:
	if pending.has(h):
		transport.cancel(h)
		pending.erase(h)


func cancel_all() -> void:
	if transport != null:
		transport.cancel_all()
	pending.clear()


## Fertige Ergebnisse abholen. Jedes Ergebnis:
## {"handle","meta","kind","ok","code","message","http_status","data","content","latency_ms","simulated","model"}
func poll() -> Array:
	var out: Array = []
	if transport == null:
		return out
	var t := now_ms()
	for raw in transport.poll(t):
		var h := int(raw["handle"])
		if not pending.has(h):
			continue          # abgebrochen
		var p: Dictionary = pending[h]
		pending.erase(h)
		out.append(_interpret(h, p, raw, t))
	for h in pending.keys():
		var p2: Dictionary = pending[h]
		if t - int(p2["started"]) > int(p2["timeout_ms"]):
			transport.cancel(h)
			pending.erase(h)
			out.append(_result(h, p2, false, "timeout", "Zeitüberschreitung nach %.0f s (Modell lädt noch oder Rechner ausgelastet)." % (int(p2["timeout_ms"]) / 1000.0), 0, {}, "", t))
	return out


func _result(h: int, p: Dictionary, ok: bool, code: String, msg: String, status: int, data: Dictionary, content: String, t: int) -> Dictionary:
	return {"handle": h, "meta": p["meta"], "kind": p["kind"], "ok": ok, "code": code, "message": msg, "http_status": status,
		"data": data, "content": content, "latency_ms": t - int(p["started"]), "simulated": simulated(), "model": str(settings.g("model", ""))}


func _interpret(h: int, p: Dictionary, raw: Dictionary, t: int) -> Dictionary:
	var err := str(raw.get("error", ""))
	if err != "":
		var msg := str(raw.get("detail", ""))
		if err == "unreachable":
			msg = "Ollama nicht erreichbar unter %s: %s Läuft Ollama (Ollama-App bzw. „ollama serve“)?" % [describe(), msg]
		return _result(h, p, false, err, msg, 0, {}, "", t)
	var status := int(raw.get("status", 0))
	var body := str(raw.get("body", ""))
	var parsed = JSON.parse_string(body) if body != "" else null
	if status >= 400:
		var etext := ""
		if typeof(parsed) == TYPE_DICTIONARY:
			etext = sanitize(str(parsed.get("error", "")), 200)
		if status == 404 and (etext.contains("not found") or p["kind"] == "chat"):
			return _result(h, p, false, "model_missing", "Modell „%s“ ist in Ollama nicht installiert (%s). Mit „ollama list“ prüfen; herunterladen nur selbst mit „ollama pull <name>“ – das Spiel lädt nichts herunter." % [str(settings.g("model", "")), etext], status, {}, "", t)
		return _result(h, p, false, "http_error", "Ollama meldet HTTP %d: %s" % [status, etext if etext != "" else "ohne Begründung"], status, {}, "", t)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _result(h, p, false, "invalid_json", "Antwort des Dienstes ist kein gültiges JSON-Objekt.", status, {}, "", t)
	if p["kind"] != "chat":
		return _result(h, p, true, "ok", "", status, parsed, "", t)
	var msg_d = parsed.get("message", {})
	var content := str(msg_d.get("content", "")) if typeof(msg_d) == TYPE_DICTIONARY else ""
	if content.strip_edges() == "":
		return _result(h, p, false, "empty", "Leere Modellantwort (done_reason: %s)." % sanitize(str(parsed.get("done_reason", "?")), 40), status, parsed, "", t)
	if content.length() > int(settings.g("max_response_chars", 3000)):
		return _result(h, p, false, "too_large", "Modellantwort zu lang (%d Zeichen > %d)." % [content.length(), int(settings.g("max_response_chars", 3000))], status, {}, "", t)
	var info := {"eval_count": int(parsed.get("eval_count", 0)), "total_duration_ms": float(parsed.get("total_duration", 0)) / 1e6,
		"load_duration_ms": float(parsed.get("load_duration", 0)) / 1e6, "done_reason": sanitize(str(parsed.get("done_reason", "")), 40)}
	return _result(h, p, true, "ok", "", status, info, content, t)


## Text aus fremder Quelle anzeigbar machen: Steuerzeichen und BBCode-Klammern entfernen, kürzen.
static func sanitize(s: String, max_len: int) -> String:
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 32 or c == 127:
			out += " "
		elif ch == "[" or ch == "]":
			out += "(" if ch == "[" else ")"
		else:
			out += ch
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len - 1) + "…"
	return out
