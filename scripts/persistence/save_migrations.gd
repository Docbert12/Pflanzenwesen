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

const MIGRATIONS := {1: "_migrate_1_to_2", 2: "_migrate_2_to_3", 3: "_migrate_3_to_4"}

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
	if cur_fp["hash"] != V4_SHIPPED_DEFINITIONS:
		return {"ok": false, "code": "definitions_changed",
			"message": "Die aktuellen Definitionen weichen von den mit v0.6.0 ausgelieferten ab (Excel neu importiert oder Konfiguration geändert). Migration nur mit den ausgelieferten Definitionen."}
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
