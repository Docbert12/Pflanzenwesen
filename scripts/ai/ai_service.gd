class_name AIService
extends RefCounted
## Anwendungsweite Ollama-Anbindung (unabhängig von Spielständen): Einstellungen, Client, Verbindungszustand,
## Gesundheitsprüfung, Unterbrecher (nach breaker_failures Transportfehlern keine neuen Anfragen bis zur
## erfolgreichen Prüfung), Ratenbegrenzung, Statistik und begrenztes Protokoll.
## Antworten werden an die Welt (AISystem) mit passender Sitzungsnummer weitergereicht; Antworten für eine
## nicht mehr existierende Sitzung (früheres Spiel, geladener Stand) werden verworfen und gezählt.
## Zustände: aus | einstellung_fehlerhaft | prüft | keine_modellwahl | verbunden | nicht_erreichbar | modell_fehlt

const STATUS_TEXT := {"aus": "aus (Welt läuft lokal)", "einstellung_fehlerhaft": "Einstellung fehlerhaft", "prüft": "prüft Verbindung …",
	"keine_modellwahl": "verbunden – kein Modell gewählt", "verbunden": "verbunden", "nicht_erreichbar": "nicht erreichbar", "modell_fehlt": "Modell nicht installiert"}

static var _shared: AIService = null

var settings: AISettings
var client: OllamaClient
var status: String = "aus"
var status_message: String = ""
var version: String = ""
var models: Array = []            # installierte Modelle [{name, size, parameter_size, quantization}]
var loaded_models: Array = []     # /api/ps
var consecutive_failures: int = 0
var recoveries: int = 0
var was_down: bool = false
var last_check_ms: int = -1000000
var check_pending: Dictionary = {}    # handle -> "version"|"tags"|"ps"
var routes: Dictionary = {}           # handle -> session
var systems: Dictionary = {}          # session -> AISystem (schwach gekoppelt über unregister)
var dispatch_times: Array = []        # Echtzeit der letzten Sendungen (Ratenbegrenzung)
var log: Array = []
var stats := {"sent": 0, "answers": 0, "transport_errors": 0, "content_errors": 0, "accepted": 0, "rejected": 0, "discarded_stale": 0,
	"retries": 0, "latency_sum_ms": 0, "latency_n": 0, "latency_last_ms": 0, "latency_max_ms": 0, "by_code": {}, "by_stage": {}}


static func shared() -> AIService:
	if _shared == null:
		_shared = AIService.new(AISettings.load_settings())
	return _shared


## Ausgeschaltete Anbindung (Standard für Tests und Werkzeuge ohne ausdrückliche KI-Nutzung).
static func disabled() -> AIService:
	var s := AISettings.new()
	s.user_path = ""
	s.reload()
	s.values["enabled"] = false
	return AIService.new(s)


func _init(p_settings: AISettings, transport = null) -> void:
	settings = p_settings
	client = OllamaClient.new(settings, transport)
	_reset_status()


func simulated() -> bool:
	return client.simulated()


func now_ms() -> int:
	return client.now_ms()


## Nach Änderung der Einstellungen: Transport neu aufbauen, Zustand neu prüfen.
func reconfigure(transport = null) -> void:
	for h in routes.keys():
		client.cancel(h)
	routes.clear()
	check_pending.clear()
	client.configure(transport)
	_reset_status()
	add_log("info", "Einstellungen übernommen: %s, Modell „%s“%s." % [client.describe(), str(settings.g("model", "")), " – SIMULIERT" if simulated() else ""])


func _reset_status() -> void:
	consecutive_failures = 0
	if not settings.enabled():
		status = "aus"
		status_message = "KI-Anbindung ist ausgeschaltet."
	elif client.config_error != "":
		status = "einstellung_fehlerhaft"
		status_message = client.config_error
	else:
		status = "prüft"
		status_message = ""
		last_check_ms = -1000000


func status_text() -> String:
	var s: String = STATUS_TEXT.get(status, status)
	if simulated() and status != "aus":
		s += " (SIMULIERTER TESTDIENST – kein Ollama)"
	return s


func add_log(level: String, text: String, extra: Dictionary = {}) -> void:
	var e := {"ms": now_ms(), "level": level, "text": text, "simulated": simulated()}
	e.merge(extra)
	log.append(e)
	while log.size() > int(settings.g("log_max", 200)):
		log.pop_front()


func register(sys) -> void:
	systems[int(sys.session)] = sys


func unregister(sys) -> void:
	systems.erase(int(sys.session))
	for h in routes.keys():
		if int(routes[h]) == int(sys.session):
			client.cancel(h)
			routes.erase(h)


## Verbindung prüfen (Version, installierte Modelle, geladene Modelle). Nur Abfragen.
func test_connection() -> void:
	if client.config_error != "":
		status = "einstellung_fehlerhaft"
		status_message = client.config_error
		return
	last_check_ms = now_ms()
	var h := client.request_version({"health": true})
	if h > 0:
		check_pending[h] = "version"
		if settings.enabled() and status != "verbunden":
			status = "prüft"


func can_dispatch() -> bool:
	if not settings.enabled() or status != "verbunden":
		return false
	if routes.size() >= int(settings.g("max_concurrent", 1)):
		return false
	var t := now_ms()
	while not dispatch_times.is_empty() and t - int(dispatch_times[0]) > 60000:
		dispatch_times.pop_front()
	return dispatch_times.size() < int(settings.g("global_rate_per_min", 8))


func send_chat(session: int, request_id: int, messages: Array, schema: Dictionary) -> int:
	var h := client.request_chat({"session": session, "request_id": request_id}, messages, schema)
	if h > 0:
		routes[h] = session
		dispatch_times.append(now_ms())
		stats["sent"] += 1
	return h


func cancel_route(h: int) -> void:
	client.cancel(h)
	routes.erase(h)


## Netzwerk vorantreiben, Ergebnisse verteilen, Gesundheitsprüfung planen. Blockiert nie.
func poll() -> void:
	for r in client.poll():
		var h := int(r["handle"])
		if check_pending.has(h):
			_health_result(str(check_pending[h]), r)
			check_pending.erase(h)
			continue
		var sess := int(routes.get(h, -1))
		routes.erase(h)
		_count(r)
		if not systems.has(sess):
			stats["discarded_stale"] += 1
			add_log("warn", "Antwort zu Anfrage %d verworfen: stammt aus einer früheren Welt/Sitzung." % int(r["meta"].get("request_id", 0)))
			continue
		systems[sess].receive(r)
	if settings.enabled() and status in ["prüft", "nicht_erreichbar", "modell_fehlt", "keine_modellwahl"] and check_pending.is_empty() \
			and now_ms() - last_check_ms >= int(float(settings.g("health_check_interval_s", 15.0)) * 1000.0):
		test_connection()


func _count(r: Dictionary) -> void:
	if r["ok"]:
		stats["answers"] += 1
		var l := int(r["latency_ms"])
		stats["latency_sum_ms"] += l
		stats["latency_n"] += 1
		stats["latency_last_ms"] = l
		stats["latency_max_ms"] = maxi(int(stats["latency_max_ms"]), l)
	else:
		var c := str(r["code"])
		stats["by_code"][c] = int(stats["by_code"].get(c, 0)) + 1
		if c in ["unreachable", "timeout", "connection_lost", "http_error"]:
			stats["transport_errors"] += 1
		else:
			stats["content_errors"] += 1


## Transportfehler/Erfolg melden (Unterbrecher).
func report_transport(ok: bool, code: String, message: String) -> void:
	if ok:
		if consecutive_failures > 0:
			consecutive_failures = 0
		return
	if code == "model_missing":
		status = "modell_fehlt"
		status_message = message
		was_down = true
		last_check_ms = now_ms()
		add_log("error", message)
		return
	if code in ["unreachable", "timeout", "connection_lost"]:
		consecutive_failures += 1
		if consecutive_failures >= int(settings.g("breaker_failures", 3)) and status == "verbunden":
			status = "nicht_erreichbar"
			status_message = "%d Fehler in Folge (%s). Neue Anfragen pausiert; Prüfung alle %.0f s." % [consecutive_failures, message, float(settings.g("health_check_interval_s", 15.0))]
			was_down = true
			last_check_ms = now_ms()
			add_log("error", status_message)


func _health_result(what: String, r: Dictionary) -> void:
	if not r["ok"]:
		if r["code"] == "model_missing":
			report_transport(false, "model_missing", r["message"])
			return
		status = "nicht_erreichbar"
		status_message = str(r["message"])
		was_down = true
		add_log("error", "Verbindungsprüfung: " + status_message)
		return
	match what:
		"version":
			version = OllamaClient.sanitize(str(r["data"].get("version", "?")), 40)
			var h := client.request_tags({"health": true})
			if h > 0:
				check_pending[h] = "tags"
		"tags":
			models.clear()
			var raw = r["data"].get("models", [])
			if typeof(raw) == TYPE_ARRAY:
				for m in raw.slice(0, 100):
					if typeof(m) == TYPE_DICTIONARY:
						var det = m.get("details", {})
						models.append({"name": OllamaClient.sanitize(str(m.get("name", m.get("model", ""))), 80), "size": float(m.get("size", 0)),
							"parameter_size": OllamaClient.sanitize(str(det.get("parameter_size", "")) if typeof(det) == TYPE_DICTIONARY else "", 20),
							"quantization": OllamaClient.sanitize(str(det.get("quantization_level", "")) if typeof(det) == TYPE_DICTIONARY else "", 20)})
			var h2 := client.request_ps({"health": true})
			if h2 > 0:
				check_pending[h2] = "ps"
			_decide_status()
		"ps":
			loaded_models.clear()
			var raw2 = r["data"].get("models", [])
			if typeof(raw2) == TYPE_ARRAY:
				for m2 in raw2.slice(0, 20):
					if typeof(m2) == TYPE_DICTIONARY:
						loaded_models.append({"name": OllamaClient.sanitize(str(m2.get("name", "")), 80), "size_vram": float(m2.get("size_vram", 0)),
							"context_length": int(m2.get("context_length", 0))})


func model_installed(name: String) -> bool:
	if name == "":
		return false
	for m in models:
		var n := str(m["name"])
		if n == name or n == name + ":latest" or (n.ends_with(":latest") and n.trim_suffix(":latest") == name):
			return true
	return false


func _decide_status() -> void:
	if not settings.enabled():
		status = "aus"
		status_message = "Verbindung geprüft: Ollama %s, %d Modelle installiert. KI-Anbindung ist ausgeschaltet." % [version, models.size()]
		add_log("info", status_message)
		return
	var model := str(settings.g("model", ""))
	if model == "":
		status = "keine_modellwahl"
		status_message = "Ollama %s erreichbar, %d Modelle installiert. Bitte im KI-Panel ein Modell wählen." % [version, models.size()]
	elif not model_installed(model):
		status = "modell_fehlt"
		status_message = "Modell „%s“ ist nicht installiert (installiert: %s). Das Spiel lädt keine Modelle herunter." % [model, ", ".join(models.map(func(m): return m["name"]).slice(0, 8))]
	else:
		if status != "verbunden" and was_down:
			recoveries += 1
			add_log("info", "Verbindung wiederhergestellt – Anfragen laufen wieder.")
		was_down = false
		status = "verbunden"
		consecutive_failures = 0
		status_message = "Ollama %s, Modell „%s“%s." % [version, model, " (SIMULIERT)" if simulated() else ""]
	add_log("info" if status == "verbunden" else "warn", status_message)


func avg_latency_ms() -> float:
	return float(stats["latency_sum_ms"]) / maxf(1.0, float(stats["latency_n"]))


func error_rate() -> float:
	var total := int(stats["answers"]) + int(stats["transport_errors"]) + int(stats["content_errors"])
	return float(int(stats["transport_errors"]) + int(stats["content_errors"]) + int(stats["rejected"])) / maxf(1.0, float(total))
