class_name MapTemplate
extends RefCounted
## Kartenvorlage (Alpha 1.1): beschreibt eine spielbare Karte (Region) – Größe, Zellgröße, Startwert,
## Generator und dessen Parameter. Dateien: data/maps/<id>.json (docs/world_expansion.md).
## Die Vorlage „lichtung“ ist die Welt von v0.6.x, unverändert. Neue Vorlagen überschreiben einzelne
## Generatorwerte aus data/config/world.json (`generator_params`); nichts ist im Code fest verdrahtet.

const DIR := "res://data/maps"
const DEFAULT_ID := "lichtung"
const SUPPORTED_SCHEMA := 1
const GENERATORS := ["lichtung_v0"]     # ab Alpha 1.2: Pipeline Höhe → Biome → Gewässer → Vegetation

var id: String = ""
var name: String = ""
var description: String = ""
var listed: bool = true
var order: int = 100
var cell_size_m: float = 0.5
var size_m := Vector3.ZERO
var size_cells := Vector3i.ZERO
var default_seed: int = 12345
var generator: String = "lichtung_v0"
var generator_version: int = 1
var latitude_deg: float = 50.0
var sea: bool = false
var raw: Dictionary = {}
var sha256: String = ""
var errors: Array = []


static func path_for(map_id: String) -> String:
	return "%s/%s.json" % [DIR, map_id]


## Alle gültigen Vorlagen, sortiert nach `order`, dann ID. include_hidden: auch nicht gelistete (Tests).
static func list_all(include_hidden: bool = false) -> Array:
	var out: Array = []
	var da := DirAccess.open(DIR)
	if da == null:
		return out
	var files := da.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var t := load_id(f.get_basename())
		if t.errors.is_empty() and (t.listed or include_hidden):
			out.append(t)
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.id < b.id)
	return out


static func load_id(map_id: String) -> MapTemplate:
	var t := MapTemplate.new()
	t.id = map_id
	var p := path_for(map_id)
	if not FileAccess.file_exists(p):
		t.errors.append("Kartenvorlage '%s' nicht gefunden (%s)." % [map_id, p])
		return t
	var bytes := FileAccess.get_file_as_bytes(p)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	t.sha256 = h.finish().hex_encode()
	var j = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(j) != TYPE_DICTIONARY:
		t.errors.append("Kartenvorlage '%s': kein gültiges JSON-Objekt." % map_id)
		return t
	t.raw = j
	t._read()
	return t


func _read() -> void:
	if int(raw.get("schema_version", 0)) != SUPPORTED_SCHEMA:
		errors.append("Kartenvorlage '%s': schema_version muss %d sein." % [id, SUPPORTED_SCHEMA])
		return
	if str(raw.get("id", "")) != id:
		errors.append("Kartenvorlage '%s': Feld id ('%s') passt nicht zum Dateinamen." % [id, str(raw.get("id", ""))])
	name = str(raw.get("name", id))
	description = str(raw.get("description", ""))
	listed = bool(raw.get("listed", true))
	order = int(raw.get("order", 100))
	cell_size_m = float(raw.get("cell_size_m", 0.0))
	default_seed = int(raw.get("seed", 12345))
	generator = str(raw.get("generator", ""))
	generator_version = int(raw.get("generator_version", 0))
	latitude_deg = float(raw.get("latitude_deg", 50.0))
	sea = bool(raw.get("sea", false))
	if cell_size_m <= 0.0:
		errors.append("Kartenvorlage '%s': cell_size_m fehlt oder ist nicht positiv." % id)
		return
	var sm = raw.get("size_m", null)
	if typeof(sm) != TYPE_ARRAY or sm.size() != 3:
		errors.append("Kartenvorlage '%s': size_m muss drei Zahlen enthalten." % id)
		return
	size_m = Vector3(float(sm[0]), float(sm[1]), float(sm[2]))
	for a in 3:
		var n := size_m[a] / cell_size_m
		if n < 8.0 or absf(n - roundf(n)) > 1e-6:
			errors.append("Kartenvorlage '%s': size_m[%d] = %s m ist kein ganzzahliges Vielfaches der Zellgröße (mindestens 8 Zellen)." % [id, a, str(size_m[a])])
			return
		size_cells[a] = int(roundf(n))
	if not generator in GENERATORS:
		errors.append("Kartenvorlage '%s': unbekannter Generator '%s'." % [id, generator])
	if generator_version < 1:
		errors.append("Kartenvorlage '%s': generator_version fehlt." % id)
	if absf(latitude_deg) > 90.0:
		errors.append("Kartenvorlage '%s': latitude_deg außerhalb −90…90." % id)
	if typeof(raw.get("generator_params", {})) != TYPE_DICTIONARY:
		errors.append("Kartenvorlage '%s': generator_params muss ein Objekt sein." % id)


## Weltkonfiguration für VoxelWorld/WorldGenerator: Grundwerte aus data/config/world.json, überschrieben
## durch die Vorlage. Prüft, dass Startgebiet und See in der Karte liegen.
func world_cfg(base: Dictionary) -> Dictionary:
	var cfg := base.duplicate(true)
	var gp: Dictionary = raw.get("generator_params", {})
	for k in gp:
		cfg[k] = gp[k].duplicate(true) if typeof(gp[k]) in [TYPE_DICTIONARY, TYPE_ARRAY] else gp[k]
	cfg["cell_size_m"] = cell_size_m
	cfg["size_cells"] = [size_cells.x, size_cells.y, size_cells.z]
	cfg["map_id"] = id
	cfg["generator"] = generator
	cfg["generator_version"] = generator_version
	return cfg


func check_cfg(cfg: Dictionary) -> Array:
	var errs: Array = []
	for key in ["start_area", "lake"]:
		var c: Array = cfg.get(key, {}).get("center", [])
		if c.size() != 2 or float(c[0]) < 1 or float(c[1]) < 1 or float(c[0]) >= size_cells.x - 1 or float(c[1]) >= size_cells.z - 1:
			errs.append("Kartenvorlage '%s': %s.center liegt nicht in der Karte (%d × %d Spalten)." % [id, key, size_cells.x, size_cells.z])
	for key in ["base_height_cells", "water_level_cells"]:
		if int(cfg.get(key, 0)) >= size_cells.y - 3:
			errs.append("Kartenvorlage '%s': %s passt nicht in die Kartenhöhe (%d Zellen)." % [id, key, size_cells.y])
	return errs


func summary() -> String:
	return "%s – %.0f × %.0f m Fläche, %.0f m hoch, Zellen %.2f m" % [name, size_m.x, size_m.z, size_m.y, cell_size_m]
