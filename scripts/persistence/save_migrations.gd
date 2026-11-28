class_name SaveMigrations
extends RefCounted
## Migrationen älterer Speicherformate, schrittweise (1→2→…). Eine fehlende Stufe = Abweisung.
##
## Format 1 → 2 (v0.3.0 → v0.4.0, Prompt 4):
##   - Voraussetzung: der Spielstand wurde mit den UNVERÄNDERTEN Definitionen von v0.3.0 gespeichert
##     (Fingerabdruck V1_KNOWN_DEFINITIONS) und die aktuellen Definitionen sind die von v0.4.0
##     (V2_SHIPPED_DEFINITIONS). Andernfalls wird nicht migriert (keine stille Übernahme).
##   - Jedes Wesen erhält reproduzierbare Persönlichkeitswerte aus seinem Körper-Startwert
##     (dieselbe Funktion wie bei „Neues Spiel“).
##   - Erinnerungen, Überzeugungen, Beziehungen: LEER. Es werden keine historischen Erinnerungen
##     erfunden; die Vergangenheit vor dem Laden bleibt unbekannt (mind_since_t = Speicherzeit).
##   - Körper, Ressourcen, Welt, Handlungen, Zufallszustände: unverändert übernommen.
##   - Neue leere Bereiche: soziale Bitten, Eingriffsprotokoll, Materialstücke, ledger.god_kg = 0.
##   Ergebnis entspricht einem Format-2-Stand mit den ausgelieferten v0.4.0-Definitionen; die Kette läuft
##   danach weiter (2→3).
##
## Format 2 → 3 (v0.4.0 → v0.5.0, Prompt 5):
##   - Voraussetzung: Spielstand mit den ausgelieferten Definitionen von v0.4.0 (V2_KNOWN_DEFINITIONS) und
##     aktuelle Definitionen = die von v0.5.0 (V3_SHIPPED_DEFINITIONS). Sonst keine Migration.
##   - Jedes Wesen erhält leere Plan-/Gesprächsdaten: kein Plan, kein Hörensagen, keine Modellnotizen,
##     keine Wartezeiten. Es werden keine Gespräche oder Pläne erfunden.
##   - Neues leeres Gesprächsprotokoll. Alles andere (Körper, Geist, Welt, Handlungen) bleibt unverändert.
##
## Format 3 → 4 (v0.5.x → v0.6.0, Prompt 6):
##   - Voraussetzung: Spielstand mit den ausgelieferten Definitionen von v0.5.x (V3_KNOWN_DEFINITIONS) und
##     aktuelle Definitionen = die von v0.6.0 (V4_SHIPPED_DEFINITIONS). Sonst keine Migration.
##   - Materialstücke (bis v0.5.x nur aus dem Göttermenü, immer Würfel bei Umgebungstemperatur) werden
##     PhysicalObjects: thermische Energie = Masse · h(293,15 K), Maße = Würfelkante, keine Verformung,
##     kein Verschleiß, nicht gehalten, kein Verbund.
##   - Jedes Wesen: hält nichts, leeres praktisches Wissen (keine bekannten Gegenstände, keine Verfahren,
##     keine Hypothesen). Es werden KEINE Entdeckungen rückwirkend geschenkt.
##   - Neue leere Bereiche: Verbünde, Testheizungen, Versuche, Wärmebilanz der Lebenswelt (0).
##   - Alles andere bleibt unverändert.
##   Zwischenstufen einer Kette (1→2→3 vor 3→4) prüfen die aktuellen Definitionen nicht selbst; das
##   macht die letzte Stufe – sonst wäre ein alter Stand nach jeder Definitionsänderung unladbar.
##   Vor dem Laden einer zu migrierenden Datei legt SaveManager eine Kopie „…vN.vor_migration“ an.

const MIGRATIONS := {1: "_migrate_1_to_2", 2: "_migrate_2_to_3", 3: "_migrate_3_to_4", 4: "_migrate_4_to_5", 5: "_migrate_5_to_6"}

## Fingerabdruck der Definitionsdateien von v0.3.0 (so ausgeliefert; gemessen beim Erstellen der Migration).
const V1_KNOWN_DEFINITIONS := ["8a3b9a3f99b43ba042a505802a769f01b458cc648abf5aa8fe30a0d1af1063e1"]
## Fingerabdruck der Definitionsdateien von v0.4.0 (so ausgeliefert).
const V2_SHIPPED_DEFINITIONS := "e8f1b282ed28bcd315c9eccfcbbedab5a0563ae2fed805ed252bce72b9e55ed4"
const V2_KNOWN_DEFINITIONS := [V2_SHIPPED_DEFINITIONS]
## Fingerabdruck der Definitionsdateien von v0.5.0 (Test „Migration: ausgelieferte Definitionen“ prüft ihn).
const V3_SHIPPED_DEFINITIONS := "2c041e8df09e35f85d822207ba54f6e44925f4537172ecfac757f41c2f4f8d4b"
const V3_KNOWN_DEFINITIONS := [V3_SHIPPED_DEFINITIONS]
## Fingerabdruck der Definitionsdateien von v0.6.0 (Test „Migration: ausgelieferte Definitionen“ prüft ihn).
const V4_SHIPPED_DEFINITIONS := "6303a08db5144550e5a2944e7ad3e1cdc0a499ef45646d45ad81e06332b21136"
const V4_KNOWN_DEFINITIONS := [V4_SHIPPED_DEFINITIONS]
## Wird beim Abschluss von v0.6.1 mit dem Fingerabdruck der ausgelieferten Definitionen gesetzt.
const V5_SHIPPED_DEFINITIONS := "011a6f986667927a42a7b454e6d747ff04089272d0390f3b71f53380bd433c0c"


## Rückgabe {"ok", "payload", "steps": Array, "code", "message"}
static func migrate(payload: Dictionary, from_version: int) -> Dictionary:
	var cur := SaveSchema.FORMAT_VERSION
	if from_version == cur:
		return {"ok": true, "payload": payload, "steps": [], "code": "ok", "message": ""}
	if from_version > cur:
		return {"ok": false, "payload": {}, "steps": [], "code": "newer_format",
			"message": "Der Spielstand hat Formatversion %d, dieses Programm kennt nur bis %d. Er wird nicht ungeprüft geladen." % [from_version, cur]}
	if from_version < 1:
		return {"ok": false, "payload": {}, "steps": [], "code": "invalid_format", "message": "Ungültige Formatversion %d." % from_version}
	var steps: Array = []
	var p := payload
	var v := from_version
	while v < cur:
		if not MIGRATIONS.has(v):
			return {"ok": false, "payload": {}, "steps": steps, "code": "no_migration",
				"message": "Keine Migration von Formatversion %d nach %d vorhanden." % [v, v + 1]}
		var r: Dictionary = Callable(SaveMigrations, MIGRATIONS[v]).call(p)
		if not r["ok"]:
			return {"ok": false, "payload": {}, "steps": steps, "code": r.get("code", "migration_failed"), "message": r["message"]}
		p = r["payload"]
		steps.append("%d→%d" % [v, v + 1])
		v += 1
	return {"ok": true, "payload": p, "steps": steps, "code": "migrated", "message": "Migriert: " + ", ".join(steps)}


static func _mind_cfg() -> Dictionary:
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/config/mind.json"))
	return j if typeof(j) == TYPE_DICTIONARY else {}


static func _migrate_1_to_2(p: Dictionary) -> Dictionary:
	var old_fp: Dictionary = p.get("definitions", {})
	if not str(old_fp.get("hash", "")) in V1_KNOWN_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Der Spielstand (Format 1) wurde mit veränderten Definitionen gespeichert, nicht mit denen von v0.3.0. Eine Migration ist dafür nicht vorgesehen."}
	var mc := _mind_cfg()
	if mc.is_empty():
		return {"ok": false, "code": "migration_failed", "message": "data/config/mind.json fehlt."}
	var t := float(p["simulation"]["time_s"])
	var i := 0
	for c in p["creatures"]:
		var pers := Personality.generate(int(c.get("plan_seed", 0)), mc)
		c["mind"] = {"personality": pers.to_dict(), "memory": {"entries": [], "next_id": 1, "forgotten": 0}, "beliefs": {"items": {}},
			"relations": {}, "learning": {"pending": [], "pending_other": [], "base_window_t": t + float(i % 12), "base_hit": false, "running_credited": 0},
			"goal_state": {}, "decision": {}, "social": {"inbox": [], "pending_request": {}, "target_cooldown": {}, "next_request_t": 0.0,
			"next_approach_t": 0.0, "holding_for_sharing": false}, "interventions_seen": [], "suggestions": [],
			"mind_since_t": t, "next_learning_t": t, "migrated_from_format": 1}
		i += 1
	p["social"] = {"requests": {}, "next_id": 1, "stats": {}}
	p["interventions"] = {"history": [], "next_id": 1, "totals": {}, "effects": []}
	p["material_pieces"] = []
	p["ledger"]["god_kg"] = 0.0
	p["definitions"] = {"hash": V2_SHIPPED_DEFINITIONS, "files": {}, "note": "per Migration 1→2 gesetzt (entspricht v0.4.0)"}
	p["format_version"] = 2
	p["migration"] = {"from": 1, "to": 2, "at_time_s": t, "definitions_v1": old_fp.get("hash", ""),
		"note": "Persönlichkeit aus Körper-Startwert; Erinnerungen, Überzeugungen und Beziehungen leer – Vergangenheit vor t=%.1f s unbekannt." % t}
	return {"ok": true, "payload": p}


static func _migrate_2_to_3(p: Dictionary) -> Dictionary:
	var old_fp: Dictionary = p.get("definitions", {})
	if not str(old_fp.get("hash", "")) in V2_KNOWN_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Der Spielstand (Format 2) wurde mit veränderten Definitionen gespeichert, nicht mit denen von v0.4.0. Eine Migration ist dafür nicht vorgesehen."}
	var cur_fp := SaveSchema.definitions_fingerprint()
	if SaveSchema.FORMAT_VERSION == 3 and cur_fp["hash"] != V3_SHIPPED_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Die aktuellen Definitionen weichen von den mit v0.5.0 ausgelieferten ab (Excel neu importiert oder Konfiguration geändert). Migration nur mit den ausgelieferten Definitionen."}
	if SaveSchema.FORMAT_VERSION > 3:
		cur_fp = {"hash": V3_SHIPPED_DEFINITIONS, "files": {}, "note": "per Migration 2→3 gesetzt (entspricht v0.5.x); Kette läuft weiter"}
	var t := float(p["simulation"]["time_s"])
	for c in p["creatures"]:
		if typeof(c.get("mind", null)) != TYPE_DICTIONARY:
			return {"ok": false, "code": "migration_failed", "message": "Wesen ohne Geistesdaten in Format 2."}
		var a := Creature.default_ai()
		a["migrated_from_format"] = 2
		c["mind"]["ai"] = a
	p["communication"] = {"log": [], "next_id": 1, "stats": {}}
	p["definitions"] = cur_fp
	p["format_version"] = 3
	p["migration_2_3"] = {"from": 2, "to": 3, "at_time_s": t, "definitions_v2": old_fp.get("hash", ""),
		"note": "Keine Pläne, kein Hörensagen, keine Gespräche vor t=%.1f s – nichts erfunden." % t}
	return {"ok": true, "payload": p}



static func _migrate_3_to_4(p: Dictionary) -> Dictionary:
	var old_fp: Dictionary = p.get("definitions", {})
	if not str(old_fp.get("hash", "")) in V3_KNOWN_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Der Spielstand (Format 3) wurde mit veränderten Definitionen gespeichert, nicht mit denen von v0.5.x. Eine Migration ist dafür nicht vorgesehen."}
	var cur_fp := SaveSchema.definitions_fingerprint()
	if SaveSchema.FORMAT_VERSION == 4 and cur_fp["hash"] != V4_SHIPPED_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Die aktuellen Definitionen weichen von den mit v0.6.0 ausgelieferten ab (Excel neu importiert oder Konfiguration geändert). Migration nur mit den ausgelieferten Definitionen."}
	if SaveSchema.FORMAT_VERSION > 4:
		cur_fp = {"hash": V4_SHIPPED_DEFINITIONS, "files": {}, "note": "per Migration 3→4 gesetzt (entspricht v0.6.0); Kette läuft weiter"}
	var t := float(p["simulation"]["time_s"])
	var mats := MaterialRegistry.new()
	mats.load_directory("res://data/materials")
	var amb := 293.15
	for mp in p.get("material_pieces", []):
		var m := mats.get_material(str(mp.get("material_id", "")))
		if m == null:
			return {"ok": false, "code": "migration_failed", "message": "Materialstück #%s: Material unbekannt." % str(mp.get("id", "?"))}
		var s := float(mp.get("size_m", 0.12))
		mp["shape"] = "block"
		mp["dims_m"] = [s, s, s]
		mp["thermal_energy_j"] = float(mp["mass_kg"]) * m.enthalpy_from_temperature(amb, 0.0)
		for k in ["damage", "strain", "wear", "cavity_m3"]:
			mp[k] = 0.0
		for k in ["carrier_id", "assembly_id", "container_id"]:
			mp[k] = 0
		mp["deformed"] = false
		mp["role"] = ""
		mp["label"] = ""
		mp["station"] = "world"
		mp["parent_ids"] = []
		mp["test_equipment"] = false
		mp["created_t"] = 0.0
		mp["history"] = [{"t": t, "what": "per Migration 3→4 übernommen (Umgebungstemperatur)"}]
	for c in p["creatures"]:
		if typeof(c.get("mind", null)) != TYPE_DICTIONARY:
			return {"ok": false, "code": "migration_failed", "message": "Wesen ohne Geistesdaten in Format 3."}
		c["held_object_id"] = 0
		var tech := ProceduralKnowledge.default_tech()
		tech["migrated_from_format"] = 3
		c["mind"]["tech"] = ProceduralKnowledge.to_save(tech)
	p["assemblies"] = []
	p["heaters"] = []
	p["experiments"] = {"next_id": 1, "records": [], "stats": {"started": 0, "completed": 0, "failed": 0, "aborted": 0, "by_source": {}}}
	p["thermal"] = {"environment_energy_j": 0.0, "body_energy_j": 0.0, "contacts": {}, "heaters": {}}
	p["definitions"] = cur_fp
	p["format_version"] = 4
	p["migration_3_4"] = {"from": 3, "to": 4, "at_time_s": t, "definitions_v3": old_fp.get("hash", ""), "pieces": p.get("material_pieces", []).size(),
		"note": "Kein Verfahrenswissen, keine Versuche, keine Werkzeuge vor t=%.1f s – nichts erfunden oder geschenkt." % t}
	return {"ok": true, "payload": p}


## Format 4 → 5 (v0.6.0 → v0.6.1, Prompt 6B):
##   - Voraussetzung: Spielstand mit den ausgelieferten Definitionen von v0.6.0 (V4_KNOWN_DEFINITIONS) und
##     aktuelle Definitionen = die von v0.6.1 (V5_SHIPPED_DEFINITIONS). Sonst keine Migration.
##   - Materialstücke: nicht eingelagert, nicht verbaut (storage_id = structure_id = 0).
##   - Wesen: Haltemodus aus dem vorhandenen Gegenstand in der Hand („one“, wenn etwas gehalten wird).
##   - Neue leere Bereiche: Lager, Baustellen, Arbeitsketten. Es werden KEINE Lager, Bauwerke oder
##     Arbeitsabsichten erfunden. Alles andere (Versuche, Verbünde, Wärme, Wissen) bleibt unverändert.
static func _migrate_4_to_5(p: Dictionary) -> Dictionary:
	var old_fp: Dictionary = p.get("definitions", {})
	if not str(old_fp.get("hash", "")) in V4_KNOWN_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Der Spielstand (Format 4) wurde mit veränderten Definitionen gespeichert, nicht mit denen von v0.6.0. Eine Migration ist dafür nicht vorgesehen."}
	var cur_fp := SaveSchema.definitions_fingerprint()
	if SaveSchema.FORMAT_VERSION == 5 and cur_fp["hash"] != V5_SHIPPED_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Die aktuellen Definitionen weichen von den mit v0.6.1 ausgelieferten ab (Excel neu importiert oder Konfiguration geändert). Migration nur mit den ausgelieferten Definitionen."}
	if SaveSchema.FORMAT_VERSION > 5:
		cur_fp = {"hash": V5_SHIPPED_DEFINITIONS, "files": {}, "note": "per Migration 4→5 gesetzt (entspricht v0.6.1); Kette läuft weiter"}
	var t := float(p["simulation"]["time_s"])
	for mp in p.get("material_pieces", []):
		mp["storage_id"] = 0
		mp["structure_id"] = 0
	for c in p["creatures"]:
		c["hold_mode"] = "one" if int(c.get("held_object_id", 0)) != 0 else ""
		c["hold_side"] = ""
	p["storages"] = []
	p["structures"] = []
	p["work"] = {"chains": [], "by_actor": {}, "next_id": 1, "last_end_t": {}, "last_site_t": {}, "stats": {}}
	p["definitions"] = cur_fp
	p["format_version"] = 5
	p["migration_4_5"] = {"from": 4, "to": 5, "at_time_s": t, "definitions_v4": old_fp.get("hash", ""),
		"note": "Keine Lager, Baustellen oder Arbeitsketten vor t=%.1f s – nichts erfunden." % t}
	return {"ok": true, "payload": p}


## Format 5 → 6 (v0.6.1 → Alpha 1.1):
##   - Voraussetzung: Spielstand mit den ausgelieferten Definitionen von v0.6.1 (V5_KNOWN_DEFINITIONS).
##     Die AKTUELLEN Definitionen dürfen neuer sein, wenn sie zu einer ausgelieferten Alpha-Version gehören:
##     ab Format 6 hebt jedes Modul seinen Abschnitt selbst an (SimModule.migrate_section).
##   - Reine Umordnung, kein Inhalt wird erfunden oder verworfen: die Einzeldatei wird in Kopf (`meta`),
##     Abschnitte je Modul (alle Version 1) und die Hauptregion zerlegt.
##   - Welt: Karte „lichtung“ (die Welt von v0.6.x, Generator lichtung_v0 Version 1). Die Liste der
##     Terrainänderungen [[Index, Typ], …] wird in Chunk-Deltas (Chunks 16 × 32 × 16) umgerechnet.
##   - Zufallsströme je Modul: leer (bis v0.6.1 gab es keine).
const V5_KNOWN_DEFINITIONS := [V5_SHIPPED_DEFINITIONS]
const V5_CHUNK_SIZE := Vector3i(16, 32, 16)
const V5_CELL_SIZE_M := 0.5
const V5_MAP_ID := "lichtung"
const V5_SECTION_KEYS := {
	"actors": ["creatures", "observation_stats"],
	"actions": ["actions"],
	"ecology.food": ["foods", "items", "ledger"],
	"technology": ["material_pieces", "assemblies", "heaters", "experiments", "thermal"],
	"settlement": ["storages", "structures"],
	"work": ["work", "workshop"],
	"social": ["social"],
	"god": ["interventions"],
	"communication": ["communication", "ai_note"],
}

static func _migrate_5_to_6(p: Dictionary) -> Dictionary:
	var errs := SaveSchema.validate(p)
	if not errs.is_empty():
		return {"ok": false, "code": "invalid", "message": "Spielstand unvollständig: " + "; ".join(errs)}
	var old_fp: Dictionary = p.get("definitions", {})
	if not str(old_fp.get("hash", "")) in V5_KNOWN_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Der Spielstand (Format 5) wurde mit veränderten Definitionen gespeichert, nicht mit denen von v0.6.1. Eine Migration ist dafür nicht vorgesehen."}
	var s: Dictionary = p["simulation"]
	var t := float(s["time_s"])
	var w: Dictionary = p["world"]
	var sz: Array = w.get("size", [64, 32, 64])
	var size := Vector3i(int(sz[0]), int(sz[1]), int(sz[2]))
	var dl := RegionStore.deltas_from_global(w["terrain_diff"], size, V5_CHUNK_SIZE)
	if not dl["ok"]:
		return {"ok": false, "code": "invalid", "message": dl["message"]}
	var mods := {}
	mods["core"] = {"v": 1, "time_s": s["time_s"], "tick_count": s["tick_count"], "registry_next_id": s["registry_next_id"], "sim_rng": s["sim_rng"],
		"dev_mode": s.get("dev_mode", false), "population_initial": s.get("population_initial", 50),
		"rng_streams": {"world_seed": str(int(w["seed"])), "streams": {}}}
	for mid in V5_SECTION_KEYS:
		var sec := {"v": 1}
		for k in V5_SECTION_KEYS[mid]:
			if p.has(k):
				sec[k] = p[k]
		mods[mid] = sec
	mods["ecology.food"]["food_rng"] = s["food_rng"]
	mods["ecology.food"]["next_refill_t"] = s.get("next_refill_t", 0.0)
	mods["ecology.food"]["refill_enabled"] = s.get("refill_enabled", false)
	var region := {"v": 1, "map_id": V5_MAP_ID, "map_sha256": "", "seed": w["seed"], "generator": "lichtung_v0", "generator_version": 1,
		"cell_size_m": V5_CELL_SIZE_M, "size": [size.x, size.y, size.z], "chunk_size": [V5_CHUNK_SIZE.x, V5_CHUNK_SIZE.y, V5_CHUNK_SIZE.z],
		"base_hash": w["base_hash"], "current_hash": w.get("current_hash", w["base_hash"]), "delta_encoding": RegionStore.ENCODING,
		"changed_cells": int(dl["changed"]), "chunks": dl["chunks"], "water_b64": w["water_b64"], "water_total_m3": w.get("water_total_m3", 0.0),
		"fragments_not_saved": w.get("fragments_not_saved", 0), "world_objects": p["world_objects"]}
	var migrations := {}
	for k in p:
		if str(k).begins_with("migration"):
			migrations[k] = p[k]
	migrations["migration_5_6"] = {"from": 5, "to": 6, "at_time_s": t, "definitions_v5": old_fp.get("hash", ""), "terrain_changes": int(dl["changed"]),
		"note": "Reine Umordnung in Kopf, Modulabschnitte und Region; nichts erfunden, nichts verworfen."}
	var doc := {"format_version": 6,
		"meta": {"game_version": p.get("game_version", "?"), "definitions": {"hash": V5_SHIPPED_DEFINITIONS, "files": old_fp.get("files", {}), "note": "Definitionen von v0.6.1"},
			"saved_at_real": p.get("saved_at_real", ""), "_note_time": p.get("_note_time", ""), "map_id": V5_MAP_ID, "seed": w["seed"],
			"module_order": mods.keys(), "migrations": migrations},
		"modules": mods, "regions": {RegionStore.MAIN: region}}
	return {"ok": true, "payload": doc}
