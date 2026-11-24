class_name JsonUtil
extends RefCounted
## Lädt JSON-Dateien mit verständlichen Fehlermeldungen.


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Datei nicht gefunden: %s" % path}
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		return {"ok": false, "error": "JSON-Fehler in %s (Zeile %d): %s" % [path, parser.get_error_line(), parser.get_error_message()]}
	return {"ok": true, "data": parser.data}


static func is_number(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
