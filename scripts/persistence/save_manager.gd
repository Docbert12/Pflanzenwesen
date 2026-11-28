class_name SaveManager
extends RefCounted
## Speichern und Laden der Lebenssimulation unter user://saves/.
## Format 6 (Alpha 1.1): Kopf + Abschnitte je Modul + Regionen mit Chunk-Deltas (document()).
## Schreiben: Momentaufnahme zwischen zwei Takten → temporäre Datei → erneut lesen und Prüfsumme
## kontrollieren → bisherige Datei wird zur Sicherung (.bak) → temporäre Datei ersetzt die Datei.
## Laden: Kopfzeile, Prüfsumme, Formatversion (Migrationen), Definitionsfingerabdruck, Pflichtfelder,
## Welt-Neuaufbau aus dem Startwert mit Kontrolle des Basisgeländes, dann Zustände übernehmen.
## Der PopulationSpawner wird beim Laden NIE aufgerufen. Ältere Formate werden über
## SaveMigrations angehoben; vorher wird die Originaldatei gesichert (…vN.vor_migration). Es vergeht keine Offline-Zeit:
## die Simulationszeit ist genau die gespeicherte; die reale Uhrzeit wird nur angezeigt.

const SAVE_DIR := "user://saves"
const DEFAULT_SLOT := "spielstand"
const HISTORY_TAIL := 50


static func path_for(slot: String = DEFAULT_SLOT) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


static func backup_path(path: String) -> String:
	return path + ".bak"


static func has_save(slot: String = DEFAULT_SLOT) -> bool:
	return FileAccess.file_exists(path_for(slot))


## Kurzinfo für das Menü (ohne vollständiges Laden). {"ok", "time_s", "alive", "dead", "saved_at", "map_id", "message"}
static func peek(path: String) -> Dictionary:
	var r := read_file(path)
	if not r["ok"]:
		return r
	var p: Dictionary = flat(r["payload"])
	var alive := 0
	var dead := 0
	for c in p.get("creatures", []):
		if c.get("alive", true):
			alive += 1
		else:
			dead += 1
	return {"ok": true, "time_s": float(p.get("simulation", {}).get("time_s", 0.0)), "alive": alive, "dead": dead,
		"saved_at": str(p.get("saved_at_real", "")), "map_id": str(p.get("world", {}).get("map_id", "")),
		"game_version": str(p.get("game_version", "")), "message": ""}


# ── Speichern ─────────────────────────────────────

static func save(life: LifeSimulation, path: String = "") -> Dictionary:
	if path == "":
		path = path_for()
	if not life.game_ready:
		return {"ok": false, "message": "Kein laufendes Spiel."}
	if life.stepping:
		return {"ok": false, "message": "Speichern mitten in einem Simulationstakt ist nicht erlaubt."}
	var payload := document(life)
	var text := JSON.stringify(payload, "", true, true)
	var header := {"magic": SaveSchema.MAGIC, "format_version": SaveSchema.FORMAT_VERSION, "sha256": SaveSchema.sha256_text(text),
		"bytes": text.to_utf8_buffer().size()}
	var mk := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if mk != OK and not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return {"ok": false, "message": "Speicherordner konnte nicht angelegt werden (%s)." % error_string(mk)}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "message": "Temporäre Datei nicht schreibbar: %s" % error_string(FileAccess.get_open_error())}
	f.store_string(JSON.stringify(header) + "\n" + text)
	f.close()
	var check := read_file(tmp)
	if not check["ok"]:
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "message": "Kontrolle der geschriebenen Datei fehlgeschlagen: " + str(check["message"])}
	var bak := backup_path(path)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var e1 := DirAccess.rename_absolute(path, bak)
		if e1 != OK:
			return {"ok": false, "message": "Bisheriger Spielstand konnte nicht gesichert werden (%s); nichts überschrieben." % error_string(e1)}
	var e2 := DirAccess.rename_absolute(tmp, path)
	if e2 != OK:
		return {"ok": false, "message": "Ersetzen fehlgeschlagen (%s). Sicherung liegt unter %s." % [error_string(e2), bak]}
	life.ctx.log_event("game_saved", [], {"path": path, "time_s": life.ctx.now(), "creatures": life.ctx.creatures.size()})
	return {"ok": true, "path": path, "bytes": text.length(), "message": "Gespeichert: %s (Simulationszeit %.1f s)." % [path, life.ctx.now()]}


static func rng_to_dict(r: RandomNumberGenerator) -> Dictionary:
	return {"seed": str(r.seed), "state": str(r.state)}


static func rng_from_dict(r: RandomNumberGenerator, d: Dictionary) -> void:
	r.seed = int(str(d.get("seed", "0")))
	r.state = int(str(d.get("state", "0")))


static func sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


## Speicherformat 6 (Alpha 1.1): Kopf (`meta`) + ein Abschnitt je Modul (`modules`, jeder mit eigener
## Abschnittsversion "v") + Regionen (`regions`: Kartenvorlage, Startwert, Chunk-Deltas, Wasser).
## Konsistente Momentaufnahme zwischen zwei Takten, nur Daten.
static func document(life: LifeSimulation) -> Dictionary:
	return {
		"format_version": SaveSchema.FORMAT_VERSION,
		"meta": {
			"game_version": str(ProjectSettings.get_setting("application/config/version", "?")),
			"definitions": SaveSchema.definitions_fingerprint(),
			"saved_at_real": Time.get_datetime_string_from_system(),
			"_note_time": "saved_at_real dient nur der Anzeige. Beim Laden vergeht keine Offline-Zeit.",
			"map_id": life.map.id, "seed": life.world.world_seed, "module_order": life.modules.ids()},
		"modules": life.modules.save_sections(),
		"regions": {RegionStore.MAIN: RegionStore.save(life)},
	}


## Flache Sicht auf ein Format-6-Dokument: alle Abschnitte nebeneinander unter den Schlüsseln, die bis
## Format 5 die Datei selbst hatte (creatures, foods, ledger, work …). Für Vergleiche, Tests und das Menü.
## `simulation` = Abschnitt core + Nahrungs-Zufall, `world` = Hauptregion, `world_objects` daraus.
static func flat(doc: Dictionary) -> Dictionary:
	var meta: Dictionary = doc.get("meta", {})
	var out := {"format_version": doc.get("format_version", 0), "game_version": meta.get("game_version", ""),
		"definitions": meta.get("definitions", {}), "saved_at_real": meta.get("saved_at_real", "")}
	var mods: Dictionary = doc.get("modules", {})
	for mid in mods:
		if mid == "core":
			continue
		for k in mods[mid]:
			if k != "v":
				out[k] = mods[mid][k]
	var sim: Dictionary = mods.get("core", {}).duplicate()
	sim.erase("v")
	for k in ["food_rng", "next_refill_t", "refill_enabled"]:
		if out.has(k):
			sim[k] = out[k]
	out["simulation"] = sim
	var region: Dictionary = doc.get("regions", {}).get(RegionStore.MAIN, {})
	out["world"] = region
	out["world_objects"] = region.get("world_objects", {})
	return out


## Flache Momentaufnahme (siehe flat). Die Datei selbst enthält document().
static func snapshot(life: LifeSimulation) -> Dictionary:
	return flat(document(life))


# ── Lesen ─────────────────────────────────────────

## Liest und prüft eine Datei. {"ok", "payload", "code", "message"}
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "missing", "message": "Kein Spielstand unter %s." % path}
	var text := FileAccess.get_file_as_string(path)
	var nl := text.find("\n")
	if nl < 0:
		return {"ok": false, "code": "corrupt", "message": "Datei ist beschädigt oder kein Spielstand (keine Kopfzeile)."}
	var hj := JSON.new()
	if hj.parse(text.substr(0, nl)) != OK or typeof(hj.data) != TYPE_DICTIONARY or hj.data.get("magic", "") != SaveSchema.MAGIC:
		return {"ok": false, "code": "corrupt", "message": "Datei ist kein Pflanzenwesen-Spielstand oder die Kopfzeile ist beschädigt."}
	var header: Dictionary = hj.data
	var body := text.substr(nl + 1)
	if SaveSchema.sha256_text(body) != str(header.get("sha256", "")):
		return {"ok": false, "code": "corrupt", "message": "Prüfsumme stimmt nicht – die Datei ist beschädigt oder unvollständig."}
	var pj := JSON.new()
	if pj.parse(body) != OK:
		return {"ok": false, "code": "corrupt", "message": "Nutzdaten nicht lesbar (Zeile %d: %s)." % [pj.get_error_line(), pj.get_error_message()]}
	if typeof(pj.data) != TYPE_DICTIONARY:
		return {"ok": false, "code": "corrupt", "message": "Nutzdaten sind kein JSON-Objekt."}
	var version := int(header.get("format_version", 0))
	var mig := SaveMigrations.migrate(pj.data, version)
	if not mig["ok"]:
		return {"ok": false, "code": mig["code"], "message": mig["message"]}
	var errs := SaveSchema.validate_document(mig["payload"])
	if not errs.is_empty():
		return {"ok": false, "code": "invalid", "message": "Spielstand unvollständig: " + "; ".join(errs)}
	return {"ok": true, "payload": mig["payload"], "code": "ok", "message": mig["message"], "from_version": version}


# ── Laden ─────────────────────────────────────────

## Lädt in eine FRISCHE LifeSimulation (setup aufgerufen, kein new_game, leeres Register).
## {"ok", "code", "message", "cancelled_actions": Array, "continued_actions": Array}
static func load_into(life: LifeSimulation, path: String = "") -> Dictionary:
	if path == "":
		path = path_for()
	var r := read_file(path)
	if not r["ok"]:
		return r
	var backup := ""
	if int(r.get("from_version", SaveSchema.FORMAT_VERSION)) < SaveSchema.FORMAT_VERSION:
		# Spielstand vor der Migration sichern (Original bleibt unverändert erhalten)
		backup = "%s.v%d.vor_migration" % [path, int(r["from_version"])]
		if not FileAccess.file_exists(backup):
			var e := DirAccess.copy_absolute(path, backup)
			if e != OK:
				return {"ok": false, "code": "backup_failed", "message": "Sicherung vor der Migration fehlgeschlagen (%s) – nichts geladen." % error_string(e)}
	var res := apply(life, r["payload"])
	if res["ok"] and backup != "":
		res["message"] = str(res["message"]) + " " + str(r["message"]) + "; Original gesichert: " + backup
		res["migrated_from"] = int(r["from_version"])
		res["backup"] = backup
	return res


## Übernimmt ein Format-6-Dokument in eine frische Welt: Definitionen prüfen → Abschnitte prüfen und
## anheben (ohne Wirkung) → Region aufbauen → Abschnitte in Ladereihenfolge → Nacharbeit → Prüfung.
static func apply(life: LifeSimulation, p: Dictionary) -> Dictionary:
	var ctx := life.ctx
	if life.game_ready or life.sim.registry.count() > 0 or not ctx.creatures.is_empty():
		return {"ok": false, "code": "not_fresh", "message": "Laden nur in eine frische Welt (keine doppelte Registrierung)."}
	var errs := SaveSchema.validate_document(p)
	if not errs.is_empty():
		return {"ok": false, "code": "invalid", "message": "Spielstand unvollständig: " + "; ".join(errs)}
	var meta: Dictionary = p["meta"]
	var fp := SaveSchema.definitions_fingerprint()
	var saved_hash := str(meta["definitions"].get("hash", ""))
	var older := ""
	if saved_hash != fp["hash"]:
		older = SaveSchema.shipped_version_of(saved_hash)
		if older == "":
			var ch := SaveSchema.definition_changes(meta["definitions"], fp)
			return {"ok": false, "code": "definitions_changed",
				"message": "Die Spieldefinitionen (Excel-Import/Konfiguration) wurden seit dem Speichern geändert. Der Spielstand wird nicht mit veränderten Definitionen geladen. Änderungen: " + ", ".join(ch.slice(0, 6)) + ("…" if ch.size() > 6 else "")}
	var prep := life.modules.prepare_sections(p["modules"])
	if not prep["ok"]:
		return {"ok": false, "code": prep["code"], "message": prep["message"]}
	var region: Dictionary = p["regions"].get(RegionStore.MAIN, {})
	var rr := RegionStore.load_into(life, region)
	if not rr["ok"]:
		return rr
	var lr := life.modules.load_sections(prep["sections"])
	if not lr["ok"]:
		return lr
	var plan_notes := life.modules.after_load_all()
	var am: ActionsModule = life.modules.get_module("actions")
	life.game_ready = true
	var problems := life.audit()
	if not problems.is_empty():
		life.game_ready = false
		return {"ok": false, "code": "inconsistent", "message": "Geladener Zustand inkonsistent: " + "; ".join(problems.slice(0, 5))}
	ctx.log_event("game_loaded", [], {"time_s": ctx.now(), "creatures": ctx.creatures.size(), "continued": am.continued, "cancelled": am.cancelled, "plans": plan_notes,
		"sections": prep["notes"], "definitions_from": older})
	var msg := "Geladen (Simulationszeit %.1f s, %d Wesen)." % [ctx.now(), ctx.creatures.size()]
	if older != "":
		msg += " Spielstand aus %s; Abschnitte angehoben: %s." % [older, ", ".join(prep["notes"]) if not prep["notes"].is_empty() else "keine Änderung nötig"]
	return {"ok": true, "code": "ok", "message": msg, "cancelled_actions": am.cancelled, "continued_actions": am.continued, "plans": plan_notes,
		"section_notes": prep["notes"]}
