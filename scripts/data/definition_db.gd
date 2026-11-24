class_name DefinitionDB
extends RefCounted
## Lädt die vom Excel-Importer erzeugten Definitionen (data/generated/excel/*.json)
## und die handgeschriebenen Konfigurationen (data/config/*.json).
## Zum Spielen wird weder Python noch Excel benötigt.
## Die Excel-Materialien (material_catalog) sind reine Designdaten – physikalische
## Eigenschaften kommen ausschließlich aus MaterialRegistry (data/materials/).

const GENERATED_DIR := "res://data/generated/excel"
const CONFIG_DIR := "res://data/config"

var _defs: Dictionary = {}     # kind -> {id -> entry}
var _config: Dictionary = {}   # name -> Dictionary
var errors: Array = []
var warnings: Array = []


func load_all(generated_dir: String = GENERATED_DIR, config_dir: String = CONFIG_DIR) -> bool:
	errors.clear()
	warnings.clear()
	_defs.clear()
	_config.clear()
	var dir := DirAccess.open(generated_dir)
	if dir == null:
		errors.append("Ordner mit erzeugten Definitionen fehlt: %s – Import ausführen: python tools/import_definitions.py --write" % generated_dir)
	else:
		for f in dir.get_files():
			if not f.ends_with(".json") or f.begins_with("_"):
				continue
			var r := JsonUtil.load_json(generated_dir.path_join(f))
			if not r["ok"]:
				errors.append(r["error"])
				continue
			var d: Dictionary = r["data"]
			if int(d.get("schema_version", 0)) != 1 or typeof(d.get("entries", null)) != TYPE_ARRAY:
				errors.append("%s: unbekanntes Format." % f)
				continue
			var kind: String = d.get("kind", f.get_basename())
			var table := {}
			for e in d["entries"]:
				table[str(e["id"])] = e
			_defs[kind] = table
			if d.get("rejected", []).size() > 0:
				warnings.append("%s: %d Excel-Zeilen beim Import abgewiesen (siehe reports/import_report.md)." % [f, d["rejected"].size()])
	var cdir := DirAccess.open(config_dir)
	if cdir == null:
		errors.append("Konfigurationsordner fehlt: %s" % config_dir)
	else:
		for f in cdir.get_files():
			if f.ends_with(".json"):
				var r := JsonUtil.load_json(config_dir.path_join(f))
				if r["ok"]:
					_config[f.get_basename()] = r["data"]
				else:
					errors.append(r["error"])
	return errors.is_empty()


func get_def(kind: String, id: String) -> Dictionary:
	return _defs.get(kind, {}).get(id, {})


func has_def(kind: String, id: String) -> bool:
	return _defs.get(kind, {}).has(id)


func all_of(kind: String) -> Dictionary:
	return _defs.get(kind, {})


func kinds() -> Array:
	var k := _defs.keys()
	k.sort()
	return k


func config(name: String) -> Dictionary:
	return _config.get(name, {})


func palette_color(palette_id: String, fallback: Color = Color.MAGENTA) -> Color:
	var e := get_def("palettes", palette_id)
	if e.is_empty() or not Color.html_is_valid(str(e.get("color", ""))):
		return fallback
	return Color.html(e["color"])


func palette_variation(palette_id: String) -> float:
	var v = get_def("palettes", palette_id).get("variation", null)
	return float(v) if v != null else 0.0


func generator_parameter(id: String, fallback: float) -> float:
	var e := get_def("generator_parameters", id)
	return float(e["value"]) if not e.is_empty() and e.get("value") != null else fallback


func game_status(kind: String, id: String) -> String:
	return str(get_def(kind, id).get("game_status", "data_only"))
