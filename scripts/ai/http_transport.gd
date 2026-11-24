class_name HttpTransport
extends RefCounted
## Nicht blockierender HTTP-Transport für die Ollama-Anbindung (Godot HTTPClient, manuell gepollt –
## funktioniert ohne Szenenbaum, also auch in der Simulation und in Testläufen ohne Fenster).
## Eine Verbindung je Anfrage; das Spiel wartet nie auf eine Antwort.
## Antwortgröße ist begrenzt (max_body_bytes) – größere Antworten werden abgebrochen.

const simulated := false

var host: String = "127.0.0.1"
var port: int = 11434
var tls: bool = false
var extra_headers := PackedStringArray()
var connect_timeout_ms: int = 3000
var max_body_bytes: int = 262144
var _conns: Dictionary = {}     # handle -> Dictionary
var _next: int = 1


func setup(ep: Dictionary, headers: PackedStringArray, p_connect_timeout_s: float) -> void:
	host = str(ep.get("host", "127.0.0.1"))
	port = int(ep.get("port", 11434))
	tls = bool(ep.get("tls", false))
	extra_headers = headers
	connect_timeout_ms = int(p_connect_timeout_s * 1000.0)


func describe() -> String:
	return "%s://%s:%d" % ["https" if tls else "http", host, port]


func active_count() -> int:
	return _conns.size()


## Startet eine Anfrage. Rückgabe: Kennung (> 0).
func start(method: String, path: String, body: String, now_ms: int) -> int:
	var h := _next
	_next += 1
	var http := HTTPClient.new()
	var err := http.connect_to_host(host, port, TLSOptions.client() if tls else null)
	var c := {"http": http, "method": method, "path": path, "body": body, "started": now_ms, "state": "connect",
		"buf": PackedByteArray(), "code": 0, "error": "", "detail": ""}
	if err != OK:
		c["state"] = "done"
		c["error"] = "unreachable"
		c["detail"] = "Verbindungsaufbau nicht möglich (%s)." % error_string(err)
	_conns[h] = c
	return h


func cancel(h: int) -> void:
	if _conns.has(h):
		(_conns[h]["http"] as HTTPClient).close()
		_conns.erase(h)


func cancel_all() -> void:
	for h in _conns.keys():
		cancel(h)


## Treibt alle Verbindungen voran. Rückgabe: fertige Ergebnisse
## [{"handle", "status", "body": String, "error": ""|code, "detail"}]. Gesamtzeitlimit setzt der Aufrufer.
func poll(now_ms: int) -> Array:
	var done: Array = []
	for h in _conns.keys():
		var c: Dictionary = _conns[h]
		if c["state"] != "done":
			_advance(c, now_ms)
		if c["state"] == "done":
			(c["http"] as HTTPClient).close()
			done.append({"handle": h, "status": int(c["code"]), "body": (c["buf"] as PackedByteArray).get_string_from_utf8(),
				"error": str(c["error"]), "detail": str(c["detail"])})
			_conns.erase(h)
	return done


func _advance(c: Dictionary, now_ms: int) -> void:
	var http: HTTPClient = c["http"]
	# Mehrere Schritte je Aufruf, aber begrenzt (kein Blockieren). Im Zustand „body“ wird VOR einem
	# weiteren poll() gelesen: poll() prüft dort nur die Verbindung, und ein Server, der nach der
	# Antwort schließt, würde sonst als Verbindungsfehler gelten, obwohl die Daten bereits vorliegen.
	for _i in 64:
		if c["state"] == "body":
			var sb := http.get_status()
			if sb == HTTPClient.STATUS_BODY:
				var chunk := http.read_response_body_chunk()
				if chunk.size() > 0:
					var buf: PackedByteArray = c["buf"]
					buf.append_array(chunk)          # PackedByteArray ist ein Werttyp: zurückschreiben
					c["buf"] = buf
					if buf.size() > max_body_bytes:
						_fail(c, "too_large", "Antwort größer als %d Byte – abgebrochen." % max_body_bytes)
						return
					continue
				http.poll()
				if http.get_status() == HTTPClient.STATUS_BODY:
					return      # noch keine Daten – später weiter
				continue
			if sb in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
				c["state"] = "done"
				return
			if (c["buf"] as PackedByteArray).size() > 0 and http.get_response_body_length() >= 0 and (c["buf"] as PackedByteArray).size() >= http.get_response_body_length():
				c["state"] = "done"      # vollständig gelesen, danach geschlossen
				return
			_fail(c, "connection_lost", _status_text(sb))
			return
		http.poll()
		var st := http.get_status()
		match c["state"]:
			"connect":
				if st in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
					if now_ms - int(c["started"]) > connect_timeout_ms:
						_fail(c, "unreachable", "Keine Verbindung innerhalb von %.1f s." % (connect_timeout_ms / 1000.0))
					return
				if st == HTTPClient.STATUS_CONNECTED:
					var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "User-Agent: Pflanzenwesen"])
					headers.append_array(extra_headers)
					var m := HTTPClient.METHOD_POST if c["method"] == "POST" else HTTPClient.METHOD_GET
					var e := http.request(m, str(c["path"]), headers, str(c["body"]) if c["method"] == "POST" else "")
					if e != OK:
						_fail(c, "unreachable", "Anfrage konnte nicht gesendet werden (%s)." % error_string(e))
						return
					c["state"] = "request"
					continue
				_fail(c, "unreachable", _status_text(st))
				return
			"request":
				if st == HTTPClient.STATUS_REQUESTING:
					return
				if st == HTTPClient.STATUS_BODY or (st in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED] and http.has_response()):
					c["code"] = http.get_response_code()
					c["state"] = "body" if st == HTTPClient.STATUS_BODY else "done"
					if c["state"] == "done":
						return
					continue
				if st == HTTPClient.STATUS_CONNECTED:
					return
				_fail(c, "connection_lost", _status_text(st))
				return
			_:
				return


func _fail(c: Dictionary, code: String, detail: String) -> void:
	c["state"] = "done"
	c["error"] = code
	c["detail"] = detail


static func _status_text(st: int) -> String:
	match st:
		HTTPClient.STATUS_CANT_RESOLVE:
			return "Rechnername nicht auflösbar."
		HTTPClient.STATUS_CANT_CONNECT:
			return "Verbindung abgelehnt (Dienst läuft nicht oder falscher Port)."
		HTTPClient.STATUS_CONNECTION_ERROR:
			return "Verbindungsfehler."
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "TLS-Fehler."
		HTTPClient.STATUS_DISCONNECTED:
			return "Verbindung getrennt."
	return "Verbindungsstatus %d." % st
