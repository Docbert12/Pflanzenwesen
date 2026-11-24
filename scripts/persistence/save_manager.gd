class_name SaveManager
extends RefCounted
## Speichern und Laden der Lebenssimulation unter user://saves/.
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


## Kurzinfo für das Menü (ohne vollständiges Laden). {"ok", "time_s", "alive", "dead", "saved_at", "message"}
static func peek(path: String) -> Dictionary:
	var r := read_file(path)
	if not r["ok"]:
		return r
	var p: Dictionary = r["payload"]
	var alive := 0
	var dead := 0
	for c in p.get("creatures", []):
		if c.get("alive", true):
			alive += 1
		else:
			dead += 1
	return {"ok": true, "time_s": float(p.get("simulation", {}).get("time_s", 0.0)), "alive": alive, "dead": dead,
		"saved_at": str(p.get("saved_at_real", "")), "message": ""}


# ── Speichern ─────────────────────────────────────

static func save(life: LifeSimulation, path: String = "") -> Dictionary:
	if path == "":
		path = path_for()
	if not life.game_ready:
		return {"ok": false, "message": "Kein laufendes Spiel."}
	if life.stepping:
		return {"ok": false, "message": "Speichern mitten in einem Simulationstakt ist nicht erlaubt."}
	var payload := snapshot(life)
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
	life.ctx.log_event("game_saved", [], {"path": path, "time_s": life.ctx.now(), "creatures": payload["creatures"].size()})
	return {"ok": true, "path": path, "bytes": text.length(), "message": "Gespeichert: %s (Simulationszeit %.1f s)." % [path, life.ctx.now()]}


static func _rng(r: RandomNumberGenerator) -> Dictionary:
	return {"seed": str(r.seed), "state": str(r.state)}


static func _set_rng(r: RandomNumberGenerator, d: Dictionary) -> void:
	r.seed = int(str(d.get("seed", "0")))
	r.state = int(str(d.get("state", "0")))


## Konsistente Momentaufnahme (nur Daten).
static func snapshot(life: LifeSimulation) -> Dictionary:
	var ctx := life.ctx
	var cells: PackedByteArray = life.world.data.cells
	var diff: Array = []
	for i in cells.size():
		if cells[i] != life.base_cells[i]:
			diff.append([i, cells[i]])
	var foods: Array = []
	for id in _sorted(ctx.foods):
		foods.append(ctx.foods[id].to_dict())
	var items: Array = []
	for id in _sorted(ctx.items):
		items.append(ctx.items[id].to_dict())
	var creatures: Array = []
	for id in _sorted(ctx.creatures):
		creatures.append(ctx.creatures[id].to_dict())
	var pieces: Array = []
	for id in _sorted(ctx.material_pieces):
		pieces.append(ctx.material_pieces[id].to_dict())
	var assemblies: Array = []
	for id in _sorted(ctx.assemblies):
		assemblies.append(ctx.assemblies[id].to_dict())
	var heaters: Array = []
	for id in _sorted(ctx.heaters):
		heaters.append(ctx.heaters[id].to_dict())
	var th := life.sim.thermal
	var running: Array = []
	for id in _sorted(ctx.executor.running):
		running.append(ctx.executor.running[id].to_dict())
	var ex := ctx.executor
	var hist: Array = ex.history.slice(maxi(0, ex.history.size() - HISTORY_TAIL))
	return {
		"format_version": SaveSchema.FORMAT_VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "?")),
		"definitions": SaveSchema.definitions_fingerprint(),
		"saved_at_real": Time.get_datetime_string_from_system(),
		"_note_time": "saved_at_real dient nur der Anzeige. Beim Laden vergeht keine Offline-Zeit.",
		"simulation": {"time_s": ctx.now(), "tick_count": life.sim.clock.tick_count, "registry_next_id": life.sim.registry.next_id(),
			"sim_rng": _rng(life.sim.rng), "food_rng": _rng(life.food_rng), "next_refill_t": life.next_refill_t,
			"refill_enabled": ctx.refill_enabled, "dev_mode": ctx.dev_mode, "population_initial": int(life.sim.settings.get("initial_population", 50))},
		"world": {"seed": life.world.world_seed, "size": [life.world.data.size.x, life.world.data.size.y, life.world.data.size.z],
			"base_hash": life.base_hash, "current_hash": life.world.data.hash_sha256(), "terrain_diff": diff,
			"water_b64": Marshalls.raw_to_base64(life.world.water.amount.to_byte_array()), "water_total_m3": life.world.water.total(),
			"fragments_not_saved": life.world.fragments.size()},
		"world_objects": {"entity_ids": life.world_object_ids.duplicate(),
			"tree": {"seed": life.tree_info.get("seed", 0), "height_m": life.tree_info.get("height_m", 0.0),
				"position": [life.tree_node.position.x, life.tree_node.position.y, life.tree_node.position.z],
				"root_bed_radius_m": life.tree_info.get("root_bed_radius_m", 0.0), "footprint_cols": life.footprint.size(),
				"state": "statisches Weltobjekt (kein Wachstum, kein Nachwuchs, kein Recycling in diesem Schritt)"}},
		"foods": foods, "items": items, "creatures": creatures,
		"actions": {"running": running, "next_action_id": ex.next_action_id, "next_res_id": ex.next_res_id, "stats": ex.stats.duplicate(),
			"history_tail": hist, "reservations_saved": false},
		"ledger": ctx.ledger.to_dict(),
		"social": ctx.social.to_dict(),
		"interventions": ctx.interventions.to_dict(),
		"material_pieces": pieces,
		"assemblies": assemblies,
		"heaters": heaters,
		"workshop": life.workshop.duplicate(),
		"experiments": ctx.experiments.to_dict(),
		"thermal": {"environment_energy_j": th.environment_energy_j, "body_energy_j": th.body_energy_j,
			"contacts": th.contacts.duplicate(true), "heaters": th.heaters.duplicate(true),
			"_note": "Kontakte/Heizungen der Lebenswelt (Prompt 6: Tiegel, Guss, Testheizung). Weltmassen haben keine."},
		"observation_stats": ctx.observation_stats.duplicate(),
		"communication": ctx.comm.to_dict(),
		"ai_note": "Gespeichert: angenommene Pläne, Hörensagen mit Herkunft und Vertrauen, Gesprächsprotokoll, Wartezeiten. NICHT gespeichert: offene Modellanfragen, Verbindungen, Modellname, Adresse (Anwendungseinstellungen). Der Spielstand lädt ohne Modell.",
	}


static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


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
	var errs := SaveSchema.validate(mig["payload"])
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


static func apply(life: LifeSimulation, p: Dictionary) -> Dictionary:
	var ctx := life.ctx
	if life.game_ready or life.sim.registry.count() > 0 or not ctx.creatures.is_empty():
		return {"ok": false, "code": "not_fresh", "message": "Laden nur in eine frische Welt (keine doppelte Registrierung)."}
	var fp := SaveSchema.definitions_fingerprint()
	if str(p["definitions"].get("hash", "")) != fp["hash"]:
		var ch := SaveSchema.definition_changes(p["definitions"], fp)
		return {"ok": false, "code": "definitions_changed",
			"message": "Die Spieldefinitionen (Excel-Import/Konfiguration) wurden seit dem Speichern geändert. Der Spielstand wird nicht mit veränderten Definitionen geladen. Änderungen: " + ", ".join(ch.slice(0, 6)) + ("…" if ch.size() > 6 else "")}
	var w: Dictionary = p["world"]
	life.build_world(int(w["seed"]))
	if life.base_hash != str(w["base_hash"]):
		return {"ok": false, "code": "world_mismatch", "message": "Das aus dem Startwert erzeugte Grundgelände weicht vom gespeicherten ab (Weltgenerator geändert)."}
	var saved_ids: Array = p["world_objects"].get("entity_ids", [])
	var cur_ids: Array = life.world_object_ids
	if saved_ids.size() != cur_ids.size():
		return {"ok": false, "code": "world_mismatch", "message": "Anzahl der Weltobjekte weicht ab (%d gespeichert, %d erzeugt)." % [saved_ids.size(), cur_ids.size()]}
	for i in saved_ids.size():
		if int(saved_ids[i]) != int(cur_ids[i]):
			return {"ok": false, "code": "world_mismatch", "message": "IDs der Weltobjekte weichen ab."}
	# Terrain: Änderungen gegenüber dem Grundgelände
	var cells: PackedByteArray = life.world.data.cells
	for e in w["terrain_diff"]:
		var i := int(e[0])
		if i < 0 or i >= cells.size():
			return {"ok": false, "code": "invalid", "message": "Terrainänderung außerhalb der Welt."}
		cells[i] = int(e[1])
	life.world.data.cells = cells
	if not w["terrain_diff"].is_empty():
		for k in life.world.chunks:
			life.world.dirty[k] = true
		life.world.flush_rebuilds()
		life.ctx.nav.setup(life.world, ctx.cfg, life.footprint)
	if life.world.data.hash_sha256() != str(w.get("current_hash", life.world.data.hash_sha256())):
		return {"ok": false, "code": "invalid", "message": "Gelände nach Anwendung der Änderungen inkonsistent."}
	var water := Marshalls.base64_to_raw(str(w["water_b64"])).to_float64_array()
	if water.size() != life.world.water.amount.size():
		return {"ok": false, "code": "invalid", "message": "Wasserdaten haben falsche Größe."}
	life.world.water.setup(life.world.data, life.world.palette, water, life.world.water.flow_rate)
	life.world._water_dirty = true
	# Simulation
	var s: Dictionary = p["simulation"]
	life.sim.clock.sim_time_s = float(s["time_s"])
	life.sim.clock.tick_count = int(s["tick_count"])
	_set_rng(life.sim.rng, s["sim_rng"])
	_set_rng(life.food_rng, s["food_rng"])
	life.next_refill_t = float(s.get("next_refill_t", 0.0))
	ctx.refill_enabled = bool(s.get("refill_enabled", false))
	ctx.dev_mode = bool(s.get("dev_mode", false))
	# Nahrung (IDs bleiben erhalten)
	var by_seed := {}
	for pl in life._plants_from_objects():
		by_seed[int(pl["spot"]["seed"])] = pl["node"]
	for fd in p["foods"]:
		var f := FoodSource.from_dict(fd)
		if life.sim.add_entity(f, "food_source") < 0:
			return {"ok": false, "code": "invalid", "message": "Nahrungsquelle #%d: ID-Konflikt." % f.id}
		ctx.foods[f.id] = f
		if by_seed.has(f.plant_seed):
			life.plant_nodes[f.id] = by_seed[f.plant_seed]
	for idd in p["items"]:
		var it := FoodItem.from_dict(idd)
		it.reserved_by = 0                       # Reservierungen werden beim Laden freigegeben
		if life.sim.add_entity(it, "food_item") < 0:
			return {"ok": false, "code": "invalid", "message": "Gegenstand #%d: ID-Konflikt." % it.id}
		ctx.items[it.id] = it
	for cd in p["creatures"]:
		var cr_r := Creature.from_dict(cd, life.sim.materials)
		if not cr_r["ok"]:
			return {"ok": false, "code": "invalid", "message": "Wesen #%s: %s" % [str(cd.get("id", "?")), "; ".join(cr_r["errors"])]}
		var cr: Creature = cr_r["creature"]
		if life.sim.add_entity(cr, "creature") < 0:
			return {"ok": false, "code": "invalid", "message": "Wesen #%d: ID-Konflikt." % cr.id}
		ctx.creatures[cr.id] = cr
		var m_saved := cr.metabolism.to_dict()
		cr.refresh_body(ctx)
		# Kapazität ergibt sich aus der Körpermasse; Abweichung nur durch Rundung zulässig,
		# dann gelten die gespeicherten Werte (bitgenaue Wiederherstellung).
		if absf(cr.metabolism.energy_capacity_j - float(m_saved["energy_capacity_j"])) > 1e-6 * maxf(1.0, cr.metabolism.energy_capacity_j):
			return {"ok": false, "code": "invalid", "message": "Wesen #%d: Speicherkapazität passt nicht zur Körpermasse." % cr.id}
		cr.metabolism = Metabolism.from_dict(m_saved)
	life.sim.registry.ensure_next_id(int(s["registry_next_id"]))
	ctx.ledger = ResourceLedger.from_dict(p["ledger"])
	for md in p["material_pieces"]:
		var mp := MaterialPiece.from_dict(md, life.sim.materials)
		if mp.material() == null:
			return {"ok": false, "code": "invalid", "message": "Materialstück #%d: unbekanntes Material %s." % [mp.id, mp.material_id]}
		mp.reserved_by = 0
		if life.sim.add_object(mp) < 0:
			return {"ok": false, "code": "invalid", "message": "Materialstück #%d: ID-Konflikt oder ungültige Masse." % mp.id}
		ctx.material_pieces[mp.id] = mp
	for ad2 in p.get("assemblies", []):
		var asm := Assembly.from_dict(ad2)
		if life.sim.add_entity(asm, "assembly") < 0:
			return {"ok": false, "code": "invalid", "message": "Verbund #%d: ID-Konflikt." % asm.id}
		ctx.assemblies[asm.id] = asm
	for hd in p.get("heaters", []):
		var hh := TestHeater.from_dict(hd)
		if life.sim.add_entity(hh, "test_heater") < 0:
			return {"ok": false, "code": "invalid", "message": "Testheizung #%d: ID-Konflikt." % hh.id}
		ctx.heaters[hh.id] = hh
	var thd: Dictionary = p.get("thermal", {})
	var th := life.sim.thermal
	th.environment_energy_j = float(thd.get("environment_energy_j", 0.0))
	th.body_energy_j = float(thd.get("body_energy_j", 0.0))
	for k in thd.get("contacts", {}):
		var c: Dictionary = thd["contacts"][k].duplicate(true)
		c["a"] = int(c["a"])
		c["b"] = int(c["b"])
		if life.sim.registry.has_id(c["a"]) and life.sim.registry.has_id(c["b"]):
			th.contacts[str(k)] = c
	for n in thd.get("heaters", {}):
		var h2: Dictionary = thd["heaters"][n].duplicate(true)
		h2["target_id"] = int(h2["target_id"])
		th.heaters[str(n)] = h2
	ctx.experiments = ExperimentSystem.from_dict(p.get("experiments", {}))
	life.workshop = {}
	for k in p.get("workshop", {}):
		life.workshop[str(k)] = int(p["workshop"][k])
	ctx.social = SocialInteractionSystem.from_dict(p["social"])
	ctx.comm = CommunicationSystem.from_dict(p.get("communication", {}))
	ctx.interventions.load_dict(p["interventions"])
	for k in p.get("observation_stats", {}):
		ctx.observation_stats[k] = int(p["observation_stats"][k])
	# Handlungen nach Ladeverhalten (ActionDefinition.on_load)
	var ex := ctx.executor
	ex.next_action_id = int(p["actions"].get("next_action_id", 1))
	ex.next_res_id = int(p["actions"].get("next_res_id", 1))
	for k in p["actions"].get("stats", {}):
		ex.stats[k] = int(p["actions"]["stats"][k])
	ex.history = p["actions"].get("history_tail", []).duplicate(true)
	var cancelled: Array = []
	var continued: Array = []
	for ad in p["actions"]["running"]:
		var a := GameAction.from_dict(ad)
		var cr2 := ctx.creature(a.actor_id)
		var policy := str(ActionDefinition.info(a.type).get("on_load", "cancel"))
		a.reservation_id = 0
		if policy == "continue" and a.type == "eat" and a.state.get("mode", "") != "carried":
			policy = "cancel"   # direktes Essen hing an einer Reservierung → kontrolliert abbrechen
		if cr2 == null or not cr2.alive:
			policy = "cancel"
		if policy == "replan":
			a.state["need_path"] = true
			a.state["replans"] = 0
		if policy in ["continue", "replan"]:
			var impl: ActionImpl = ex.impls[a.type]
			var v := ex.validator.validate_step(a, ctx, impl)
			if v.ok:
				ex.running[a.actor_id] = a
				continued.append("%s #%d (%s)" % [a.type, a.actor_id, policy])
				continue
			policy = "cancel"
		cancelled.append("%s #%d" % [a.type, a.actor_id])
		ctx.log_event("action_cancelled_on_load", [a.actor_id], {"action_id": a.id, "type": a.type, "reason": "Ladeverhalten: kontrolliert abgebrochen"}, "warning")
		if cr2 != null:
			cr2.last_result = {"type": a.type, "status": ActionDefinition.STATUS_CANCELLED, "code": "cancelled_on_load", "message": "Beim Laden kontrolliert abgebrochen.", "t": ctx.now(), "target": a.target_id}
			cr2.next_decision_t = ctx.now()
	var plan_notes := ctx.ai.after_load()
	plan_notes.append_array(ctx.experiments.after_load(ctx))
	# Gehaltenes, Reservierungen technischer Gegenstände und Schritte: konsistent herstellen
	for cid in ctx.creatures:
		var crx: Creature = ctx.creatures[cid]
		if crx.held_object_id != 0 and ConstructionSystem.carrier_of(ctx, crx.held_object_id) != cid:
			crx.held_object_id = 0
	ConstructionSystem.sync_positions(ctx)
	life.game_ready = true
	var problems := life.audit()
	if not problems.is_empty():
		life.game_ready = false
		return {"ok": false, "code": "inconsistent", "message": "Geladener Zustand inkonsistent: " + "; ".join(problems.slice(0, 5))}
	ctx.log_event("game_loaded", [], {"time_s": ctx.now(), "creatures": ctx.creatures.size(), "continued": continued, "cancelled": cancelled, "plans": plan_notes})
	return {"ok": true, "code": "ok", "message": "Geladen (Simulationszeit %.1f s, %d Wesen)." % [ctx.now(), ctx.creatures.size()],
		"cancelled_actions": cancelled, "continued_actions": continued, "plans": plan_notes}
