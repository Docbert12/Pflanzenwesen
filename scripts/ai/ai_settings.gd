class_name AISettings
extends RefCounted
## Anwendungseinstellungen der Ollama-Anbindung (NICHT Teil des Spielstands, NICHT Teil der
## Spieldefinitionen). Vorgaben: res://data/settings/ai.json; eigene Änderungen: user://ai_settings.json.
## Sicherheitsregeln (im Code, nicht nur in der Dokumentation):
##   - Nur lokale Adressen, außer allow_remote ist ausdrücklich true. Keine Ausweichverbindung.
##   - Ein Zugangsschlüssel wird nur zur Laufzeit aus einer Umgebungsvariablen gelesen
##     (auth_env_var = deren NAME), nie gespeichert, nie protokolliert, nie im Spielstand.
##   - Unbekannte Schlüssel in user://ai_settings.json werden ignoriert; Typen werden geprüft.

const DEFAULTS_PATH := "res://data/settings/ai.json"
const USER_PATH := "user://ai_settings.json"
const LOCAL_HOSTS := ["127.0.0.1", "localhost", "::1", "[::1]"]

var values: Dictionary = {}
var defaults: Dictionary = {}
var errors: Array = []
var user_path: String = USER_PATH


static func load_settings(p_user_path: String = USER_PATH) -> AISettings:
	var s := AISettings.new()
	s.user_path = p_user_path
	s.reload()
	return s


func reload() -> void:
	errors.clear()
	var d = JSON.parse_string(FileAccess.get_file_as_string(DEFAULTS_PATH)) if FileAccess.file_exists(DEFAULTS_PATH) else null
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("data/settings/ai.json fehlt oder ist ungültig – KI-Anbindung bleibt aus.")
		d = {"enabled": false}
	defaults = {}
	for k in d:
		if not str(k).begins_with("_") and k != "schema_version":
			defaults[k] = d[k]
	values = defaults.duplicate(true)
	if user_path != "" and FileAccess.file_exists(user_path):
		var u = JSON.parse_string(FileAccess.get_file_as_string(user_path))
		if typeof(u) == TYPE_DICTIONARY:
			for k in u:
				set_value(str(k), u[k])
		else:
			errors.append("%s ist ungültig und wird ignoriert." % user_path)


## Setzt einen bekannten Wert mit Typprüfung. Rückgabe: true bei Erfolg.
func set_value(key: String, v) -> bool:
	if not defaults.has(key):
		return false
	var dt := typeof(defaults[key])
	if key == "think":
		if v == null or typeof(v) == TYPE_BOOL:
			values[key] = v
			return true
		return false
	if dt == TYPE_FLOAT and typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		values[key] = float(v)
	elif dt == TYPE_INT and typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		values[key] = int(v)
	elif dt == typeof(v):
		values[key] = v
	else:
		errors.append("Einstellung '%s': falscher Typ, Vorgabe bleibt." % key)
		return false
	return true


func g(key: String, fallback = null):
	return values.get(key, fallback)


func enabled() -> bool:
	return bool(values.get("enabled", false))


func use_mock() -> bool:
	return bool(values.get("use_mock", false))


## Prüft Adresse und Modell. Rückgabe {"ok", "host", "port", "tls", "message"}.
func endpoint() -> Dictionary:
	var url := str(values.get("base_url", "")).strip_edges()
	var tls := false
	if url.begins_with("http://"):
		url = url.substr(7)
	elif url.begins_with("https://"):
		url = url.substr(8)
		tls = true
	else:
		return {"ok": false, "message": "Adresse muss mit http:// oder https:// beginnen."}
	if url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	if url.contains("/") or url.contains("@") or url.contains("?"):
		return {"ok": false, "message": "Adresse darf nur Rechner und Port enthalten (kein Pfad, keine Zugangsdaten)."}
	var host := url
	var port := 443 if tls else 80
	var colon := url.rfind(":")
	if colon > 0 and not url.ends_with("]"):
		host = url.substr(0, colon)
		var ps := url.substr(colon + 1)
		if not ps.is_valid_int():
			return {"ok": false, "message": "Ungültiger Port '%s'." % ps}
		port = int(ps)
	if host == "" or port <= 0 or port > 65535:
		return {"ok": false, "message": "Ungültige Adresse."}
	var local := host in LOCAL_HOSTS
	if not local and not bool(values.get("allow_remote", false)):
		return {"ok": false, "message": "Nur lokale Adressen erlaubt (127.0.0.1/localhost). Eine andere Umgebung muss ausdrücklich mit allow_remote=true eingetragen werden."}
	return {"ok": true, "host": host.trim_prefix("[").trim_suffix("]"), "port": port, "tls": tls, "local": local, "message": ""}


## Zusätzliche Kopfzeilen (nur Laufzeit). Der Schlüssel wird nirgends gespeichert oder protokolliert.
func auth_headers() -> PackedStringArray:
	var out := PackedStringArray()
	var envn := str(values.get("auth_env_var", ""))
	if envn != "" and bool(values.get("allow_remote", false)):
		var tok := OS.get_environment(envn)
		if tok != "":
			out.append("Authorization: Bearer " + tok)
	return out


## Darstellbare Einstellungen (ohne Geheimnisse – es werden ohnehin keine gespeichert).
func public_dict() -> Dictionary:
	var d := values.duplicate(true)
	d["auth"] = "Umgebungsvariable %s" % values.get("auth_env_var", "") if str(values.get("auth_env_var", "")) != "" else "keine"
	return d


## Speichert NUR die vom Vorgabewert abweichenden Werte nach user://ai_settings.json.
func save_user() -> Dictionary:
	if user_path == "":
		return {"ok": false, "message": "Kein Speicherort für Benutzereinstellungen."}
	var diff := {}
	for k in values:
		if not defaults.has(k) or values[k] != defaults[k]:
			diff[k] = values[k]
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "message": "Einstellungen nicht schreibbar: %s" % error_string(FileAccess.get_open_error())}
	f.store_string(JSON.stringify(diff, "  "))
	f.close()
	return {"ok": true, "message": "Einstellungen gespeichert (%s)." % user_path}
