class_name SaveSchema
extends RefCounted
## Aufbau und Prüfung eines Spielstands (Format siehe docs/save_format.md).
## Datei = Kopfzeile (JSON) + Zeilenumbruch + Nutzdaten (JSON, volle Gleitkommagenauigkeit).
## Die Kopfzeile enthält die SHA-256-Prüfsumme der Nutzdaten → abgeschnittene oder veränderte
## Dateien werden erkannt. Es werden nur Daten gespeichert, keine Node-Referenzen.

const MAGIC := "pflanzenwesen_save"
const FORMAT_VERSION := 6   # 6 = Alpha 1.1 (Kopf + Abschnitte je Modul mit eigener Version + Regionen mit Chunk-Deltas); 1 = v0.3.0 (Prompt 3), 2 = v0.4.0 (Prompt 4: Geist, Soziales, Eingriffe), 3 = v0.5.0 (Prompt 5: Pläne, Gespräche, Hörensagen), 5 = v0.6.1 (Prompt 6B: Lager, Baustellen, Arbeitsketten, Haltemodus)
                            # 4 = v0.6.0 (Prompt 6: Gegenstände mit Wärme, Verbünde, Testheizung, Versuche, Verfahrenswissen)

## Dateien, deren Inhalt die Spieldefinitionen bildet. Jede Änderung → Spielstand wird abgewiesen
## (strenge Strategie, siehe docs/save_format.md). implementation_status.json ist nur
## beschreibend und gehört nicht dazu; _manifest.json enthält Importzeitstempel.
const DEFINITION_DIRS := ["res://data/generated/excel", "res://data/materials", "res://data/maps"]
const DEFINITION_FILES := ["res://data/config/life.json", "res://data/config/mind.json", "res://data/config/world.json", "res://data/config/voxel_palette.json",
	"res://data/config/creature_defaults.json", "res://data/config/material_mapping.json", "res://data/settings/simulation.json",
	"res://data/config/technology.json"]
const EXCLUDED := ["_manifest.json"]

const REQUIRED := {"format_version": TYPE_FLOAT, "game_version": TYPE_STRING, "definitions": TYPE_DICTIONARY, "simulation": TYPE_DICTIONARY,
	"world": TYPE_DICTIONARY, "world_objects": TYPE_DICTIONARY, "foods": TYPE_ARRAY, "items": TYPE_ARRAY, "creatures": TYPE_ARRAY,
	"actions": TYPE_DICTIONARY, "ledger": TYPE_DICTIONARY, "social": TYPE_DICTIONARY, "interventions": TYPE_DICTIONARY,
	"material_pieces": TYPE_ARRAY, "communication": TYPE_DICTIONARY, "assemblies": TYPE_ARRAY, "heaters": TYPE_ARRAY,
	"experiments": TYPE_DICTIONARY, "thermal": TYPE_DICTIONARY, "storages": TYPE_ARRAY, "structures": TYPE_ARRAY, "work": TYPE_DICTIONARY}


## Pflichtteile eines Format-6-Dokuments. Die Abschnitte der Module prüft das ModuleRegistry.
const REQUIRED_META := ["game_version", "definitions", "map_id", "seed"]
const REQUIRED_SECTIONS := ["core", "actors", "actions", "ecology.food", "technology", "settlement", "work", "social", "god", "communication"]
const REQUIRED_REGION := ["seed", "base_hash", "chunks", "water_b64", "size", "map_id"]

## Ausgelieferte Definitionen je Alpha-Version (Format 6). Ein Spielstand mit einem dieser Fingerabdrücke
## darf geladen werden, auch wenn die aktuellen Definitionen neuer sind: die Abschnitte der Module werden
## dann je Modul angehoben (SimModule.migrate_section). Unbekannte Fingerabdrücke = veränderte
## Definitionen → Abweisung. Der Eintrag der aktuellen Version wird beim Abschluss der Version gesetzt.
const SHIPPED_DEFINITIONS := {
	"v0.6.1": "011a6f986667927a42a7b454e6d747ff04089272d0390f3b71f53380bd433c0c",   # über Migration 5→6
	"alpha-1.1": "78c0cbf4e6420ce4d4b3a1ee3459810c3d36aaec1e022ffa27ffeceeeec69063",
}


## Alpha-Version zu einem ausgelieferten Fingerabdruck ("" = unbekannt).
static func shipped_version_of(hash: String) -> String:
	for v in SHIPPED_DEFINITIONS:
		if str(SHIPPED_DEFINITIONS[v]) == hash:
			return str(v)
	return ""


## Prüfung eines Format-6-Dokuments (Aufbau und Pflichtteile). Leere Liste = in Ordnung.
static func validate_document(p) -> Array:
	var errs: Array = []
	if typeof(p) != TYPE_DICTIONARY:
		return ["Nutzdaten sind kein JSON-Objekt."]
	for k in ["meta", "modules", "regions"]:
		if typeof(p.get(k, null)) != TYPE_DICTIONARY:
			errs.append("Pflichtfeld '%s' fehlt." % k)
	if not errs.is_empty():
		return errs
	for k in REQUIRED_META:
		if not p["meta"].has(k):
			errs.append("meta.%s fehlt." % k)
	if typeof(p["meta"].get("definitions", null)) != TYPE_DICTIONARY:
		errs.append("meta.definitions fehlt.")
	for k in REQUIRED_SECTIONS:
		if typeof(p["modules"].get(k, null)) != TYPE_DICTIONARY:
			errs.append("Abschnitt '%s' fehlt." % k)
	var region = p["regions"].get(RegionStore.MAIN, null)
	if typeof(region) != TYPE_DICTIONARY:
		errs.append("Region '%s' fehlt." % RegionStore.MAIN)
	else:
		for k in REQUIRED_REGION:
			if not region.has(k):
				errs.append("Region: %s fehlt." % k)
	if not errs.is_empty():
		return errs
	if typeof(p["modules"]["actors"].get("creatures", null)) != TYPE_ARRAY:
		errs.append("Pflichtfeld 'creatures' fehlt.")
		return errs
	for c in p["modules"]["actors"]["creatures"]:
		if typeof(c) != TYPE_DICTIONARY or not c.has("id") or not c.has("plan") or not c.has("metabolism"):
			errs.append("Ungültiger Wesen-Eintrag.")
			break
		if typeof(c.get("mind", null)) != TYPE_DICTIONARY or not c["mind"].has("personality"):
			errs.append("Wesen #%s: Geistesdaten (Persönlichkeit, Erinnerungen …) fehlen." % str(c.get("id", "?")))
			break
		if typeof(c["mind"].get("ai", null)) != TYPE_DICTIONARY:
			errs.append("Wesen #%s: Plan-/Gesprächsdaten fehlen." % str(c.get("id", "?")))
			break
	for f in p["modules"]["ecology.food"].get("foods", []):
		if typeof(f) != TYPE_DICTIONARY or float(f.get("amount_kg", -1.0)) < 0.0:
			errs.append("Ungültiger Nahrungseintrag (Menge negativ oder fehlend).")
			break
	return errs


## Fingerabdruck aller Definitionsdateien: {"hash": Gesamt-SHA-256, "files": {Pfad: SHA-256}}
static func definitions_fingerprint() -> Dictionary:
	var paths: Array = DEFINITION_FILES.duplicate()
	for dir in DEFINITION_DIRS:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".json") and not f in EXCLUDED:
				paths.append(dir + "/" + f)
	paths.sort()
	var files := {}
	var total := HashingContext.new()
	total.start(HashingContext.HASH_SHA256)
	for p in paths:
		var bytes := FileAccess.get_file_as_bytes(p)
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(bytes)
		var hex := h.finish().hex_encode()
		files[p] = hex
		total.update((p + ":" + hex + "\n").to_utf8_buffer())
	return {"hash": total.finish().hex_encode(), "files": files}


## Unterschiede zweier Fingerabdrücke als lesbare Liste.
static func definition_changes(saved: Dictionary, current: Dictionary) -> Array:
	var out: Array = []
	var a: Dictionary = saved.get("files", {})
	var b: Dictionary = current.get("files", {})
	for p in a:
		if not b.has(p):
			out.append("entfernt: " + p)
		elif a[p] != b[p]:
			out.append("geändert: " + p)
	for p in b:
		if not a.has(p):
			out.append("neu: " + p)
	return out


static func sha256_text(s: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(s.to_utf8_buffer())
	return h.finish().hex_encode()


## Grundprüfung flacher Nutzdaten bis Format 5 (Pflichtfelder und Typen); die Migration 5→6 prüft damit
## ihren Eingang. Leere Liste = in Ordnung.
static func validate(p) -> Array:
	var errs: Array = []
	if typeof(p) != TYPE_DICTIONARY:
		return ["Nutzdaten sind kein JSON-Objekt."]
	for k in REQUIRED:
		if not p.has(k):
			errs.append("Pflichtfeld '%s' fehlt." % k)
		elif typeof(p[k]) != REQUIRED[k] and not (REQUIRED[k] == TYPE_FLOAT and typeof(p[k]) == TYPE_INT):
			errs.append("Feld '%s' hat falschen Typ." % k)
	if not errs.is_empty():
		return errs
	for k in ["seed", "base_hash", "terrain_diff", "water_b64"]:
		if not p["world"].has(k):
			errs.append("world.%s fehlt." % k)
	for k in ["time_s", "tick_count", "registry_next_id", "sim_rng", "food_rng"]:
		if not p["simulation"].has(k):
			errs.append("simulation.%s fehlt." % k)
	for c in p["creatures"]:
		if typeof(c) != TYPE_DICTIONARY or not c.has("id") or not c.has("plan") or not c.has("metabolism"):
			errs.append("Ungültiger Wesen-Eintrag.")
			break
		if typeof(c.get("mind", null)) != TYPE_DICTIONARY or not c["mind"].has("personality"):
			errs.append("Wesen #%s: Geistesdaten (Persönlichkeit, Erinnerungen …) fehlen." % str(c.get("id", "?")))
			break
		if typeof(c["mind"].get("ai", null)) != TYPE_DICTIONARY:
			errs.append("Wesen #%s: Plan-/Gesprächsdaten fehlen." % str(c.get("id", "?")))
			break
	for f in p["foods"]:
		if typeof(f) != TYPE_DICTIONARY or float(f.get("amount_kg", -1.0)) < 0.0:
			errs.append("Ungültiger Nahrungseintrag (Menge negativ oder fehlend).")
			break
	return errs
