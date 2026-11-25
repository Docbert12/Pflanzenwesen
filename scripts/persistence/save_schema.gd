class_name SaveSchema
extends RefCounted
## Aufbau und Prüfung eines Spielstands (Format siehe docs/save_format.md).
## Datei = Kopfzeile (JSON) + Zeilenumbruch + Nutzdaten (JSON, volle Gleitkommagenauigkeit).
## Die Kopfzeile enthält die SHA-256-Prüfsumme der Nutzdaten → abgeschnittene oder veränderte
## Dateien werden erkannt. Es werden nur Daten gespeichert, keine Node-Referenzen.

const MAGIC := "pflanzenwesen_save"
const FORMAT_VERSION := 5   # 1 = v0.3.0 (Prompt 3), 2 = v0.4.0 (Prompt 4: Geist, Soziales, Eingriffe), 3 = v0.5.0 (Prompt 5: Pläne, Gespräche, Hörensagen), 5 = v0.6.1 (Prompt 6B: Lager, Baustellen, Arbeitsketten, Haltemodus)
                            # 4 = v0.6.0 (Prompt 6: Gegenstände mit Wärme, Verbünde, Testheizung, Versuche, Verfahrenswissen)

## Dateien, deren Inhalt die Spieldefinitionen bildet. Jede Änderung → Spielstand wird abgewiesen
## (strenge Strategie, siehe docs/save_format.md). implementation_status.json ist nur
## beschreibend und gehört nicht dazu; _manifest.json enthält Importzeitstempel.
const DEFINITION_DIRS := ["res://data/generated/excel", "res://data/materials"]
const DEFINITION_FILES := ["res://data/config/life.json", "res://data/config/mind.json", "res://data/config/world.json", "res://data/config/voxel_palette.json",
	"res://data/config/creature_defaults.json", "res://data/config/material_mapping.json", "res://data/settings/simulation.json",
	"res://data/config/technology.json"]
const EXCLUDED := ["_manifest.json"]

const REQUIRED := {"format_version": TYPE_FLOAT, "game_version": TYPE_STRING, "definitions": TYPE_DICTIONARY, "simulation": TYPE_DICTIONARY,
	"world": TYPE_DICTIONARY, "world_objects": TYPE_DICTIONARY, "foods": TYPE_ARRAY, "items": TYPE_ARRAY, "creatures": TYPE_ARRAY,
	"actions": TYPE_DICTIONARY, "ledger": TYPE_DICTIONARY, "social": TYPE_DICTIONARY, "interventions": TYPE_DICTIONARY,
	"material_pieces": TYPE_ARRAY, "communication": TYPE_DICTIONARY, "assemblies": TYPE_ARRAY, "heaters": TYPE_ARRAY,
	"experiments": TYPE_DICTIONARY, "thermal": TYPE_DICTIONARY, "storages": TYPE_ARRAY, "structures": TYPE_ARRAY, "work": TYPE_DICTIONARY}


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


## Grundprüfung der Nutzdaten (Pflichtfelder und Typen). Leere Liste = in Ordnung.
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
