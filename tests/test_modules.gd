class_name TestModules
extends RefCounted
## Abnahmetests Alpha 1.1 – Fundament: Modulvertrag und Reihenfolge, Zufallsströme, WorldAccess,
## Kartenvorlagen (auch nicht-quadratisch), Speicherformat 6 (Abschnitte, Chunk-Deltas), Migration 5 → 6
## mit ECHTEN Spielständen aus v0.6.1 (vor jeder Codeänderung von Alpha 1.1 erzeugt), Determinismus.

const DT := 1.0 / 60.0
const FIXTURES := [["save_v5_v061.json", "normales Spiel"], ["save_v5_v061_werkstatt.json", "Testwerkstatt"], ["save_v5_v061_werkzeugkette.json", "Werkzeugkette mitten in einer Kette"]]

var results: Array = []
var notes: Array = []
var db: DefinitionDB
var sc: MindScenarios
var world_seed: int = 12345
var only: String = ""


## Prüfmodul: zählt Aufrufe, hat einen optionalen Abschnitt mit eigener Version.
class Probe extends SimModule:
	var ticks := 0
	var actor_calls := 0
	var value := 0
	var log: Array
	func _init(p_id: String, deps: Array[String], p_log: Array, p_actor := false) -> void:
		id = p_id
		title = "Prüfmodul " + p_id
		depends_on = deps
		per_actor = p_actor
		log = p_log
		has_section = true
		section_optional = true
		section_version = 2
	func tick(_dt: float, _zone: int) -> void:
		ticks += 1
		log.append(id)
	func actor_tick(_cr: Creature, _dt: float) -> void:
		actor_calls += 1
	func save_section() -> Dictionary:
		return {"wert": value}
	func load_section(d: Dictionary) -> Dictionary:
		value = int(d.get("wert", -1))
		return {"ok": true}
	func migrate_section(d: Dictionary, from_v: int) -> Dictionary:
		if from_v == 1:
			return {"ok": true, "section": {"v": 2, "wert": int(d.get("alt", 0)) * 10}}
		return super.migrate_section(d, from_v)


func run_all(p_only: String = "") -> Array:
	only = p_only
	results.clear()
	notes.clear()
	db = DefinitionDB.new()
	db.load_all()
	sc = MindScenarios.new(db)
	world_seed = int(db.config("world").get("seed", 12345))
	for f in [_t01_order, _t02_registry_errors, _t03_rng_streams, _t04_world_access, _t05_map_templates, _t06_nonsquare_map, _t07_sections_roundtrip,
			_t08_chunk_deltas, _t09_migration_v5, _t10_determinism, _t11_section_versions, _t12_no_direct_terrain_access, _t13_timing, _t14_definitions]:
		if only != "" and not str(f.get_method()).contains(only):
			continue
		print("  Modul-Test: %s (%.1f s)" % [str(f.get_method()), Time.get_ticks_msec() / 1000.0])
		f.call()
		sc.cleanup()
	return results


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": "[Module] " + name, "ok": ok, "detail": detail})


func _env() -> LifeSimulation:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs, AIService.disabled())
	sc.lives.append(life)
	return life


func _run(life: LifeSimulation, secs: float) -> void:
	for i in int(round(secs / DT)):
		life.step(DT)


static func _n(v):
	return JSON.parse_string(JSON.stringify(v, "", true, true))


# ── 1. Reihenfolge der Module ─────────────────────

func _t01_order() -> void:
	var life := _env()
	var want := ["core", "time.sky", "actors", "actions", "technology.tools", "life", "mind.perception", "technology.perception", "settlement",
		"mind.decision", "social", "god", "technology", "work", "communication", "ecology.food"]
	_check("Vorhandene Systeme sind als Module angemeldet; Reihenfolge aus Abhängigkeiten = Taktreihenfolge bis v0.6.1", life.modules.ids() == want and life.modules.errors.is_empty(), str(life.modules.ids()))
	var groups: Array = []
	for g in life.modules.groups:
		var n: Array = []
		for m in g["modules"]:
			n.append(m.id)
		groups.append(("A:" if g["per_actor"] else "") + "+".join(n))
	_check("Akteur-Module bilden EINE Gruppe (Körper → Wahrnehmung → Entscheidung je Wesen)", groups.size() == 3 and str(groups[1]) == "A:life+mind.perception+technology.perception+settlement+mind.decision", str(groups))
	var uniq := {}
	var titled := true
	for m in life.modules.order:
		uniq[m.id] = true
		if m.title == "":
			titled = false
	_check("Jedes Modul hat eindeutige ID und deutschen Titel", uniq.size() == life.modules.order.size() and titled)
	# Zusätzliches Modul: wird nach seinen Abhängigkeiten eingeordnet und im selben Takt aufgerufen
	var log: Array = []
	var pa := Probe.new("probe.a", ["actions"] as Array[String], log)
	var pb := Probe.new("probe.b", ["probe.a", "ecology.food"] as Array[String], log)
	var pc := Probe.new("probe.akteur", ["mind.decision"] as Array[String], log, true)
	var ok_add := life.add_module(pb) == false     # Abhängigkeit probe.a fehlt noch → Fehler, nichts läuft falsch
	life.errors.clear()
	life.modules = ModuleRegistry.new()
	ok_add = life._register_modules([pa, pb, pc]) and ok_add
	var ids: Array = life.modules.ids()
	_check("Neues Modul wird über Abhängigkeiten eingeordnet, ohne bestehende Reihenfolge zu ändern", ok_add and ids.find("probe.a") > ids.find("actions") and ids.find("probe.b") > ids.find("ecology.food")
		and ids.find("probe.akteur") == ids.find("mind.decision") + 1, str(ids))
	life.new_game(world_seed)
	_run(life, 1.0)
	var alive := 0
	for cid in life.ctx.creatures:
		if life.ctx.creatures[cid].alive:
			alive += 1
	_check("Zusätzliche Module laufen im selben Simulationspfad (60 Takte; Akteur-Modul je lebendem Wesen)", pa.ticks == 60 and pb.ticks == 60 and pc.actor_calls == 60 * alive and log.find("probe.a") < log.find("probe.b"),
		"a %d, b %d, Akteur %d bei %d Wesen" % [pa.ticks, pb.ticks, pc.actor_calls, alive])
	life.sim.set_paused(true)
	var t_before := life.ctx.now()
	_run(life, 0.5)
	_check("Pause: kein Modul tickt, Simulationszeit steht", pa.ticks == 60 and life.ctx.now() == t_before)
	life.sim.set_paused(false)


# ── 2. Fehler im Register ─────────────────────────

func _t02_registry_errors() -> void:
	var log: Array = []
	var r1 := ModuleRegistry.new()
	r1.register(Probe.new("a", ["b"] as Array[String], log))
	r1.register(Probe.new("b", ["c"] as Array[String], log))
	r1.register(Probe.new("c", ["a"] as Array[String], log))
	_check("Zyklische Abhängigkeit wird als Fehler erkannt (keine Reihenfolge, nichts läuft)", not r1.resolve() and r1.order.is_empty() and str(r1.errors).find("Zyklische") >= 0, str(r1.errors))
	var r2 := ModuleRegistry.new()
	r2.register(Probe.new("a", ["gibt_es_nicht"] as Array[String], log))
	_check("Unbekannte Abhängigkeit wird als Fehler erkannt", not r2.resolve() and str(r2.errors).find("unbekanntem Modul") >= 0, str(r2.errors))
	var r3 := ModuleRegistry.new()
	var first := r3.register(Probe.new("a", [] as Array[String], log))
	var second := r3.register(Probe.new("a", [] as Array[String], log))
	_check("Doppelte Modul-ID wird abgewiesen", first and not second and r3.modules.size() == 1)
	var r4 := ModuleRegistry.new()
	for mid in ["z", "m", "a"]:
		r4.register(Probe.new(mid, [] as Array[String], log))
	r4.register(Probe.new("vor_allem", [] as Array[String], log))
	(r4.get_module("z") as SimModule).depends_on = ["a"] as Array[String]
	_check("Stabile Sortierung: ohne Abhängigkeit gilt die Anmeldereihenfolge", r4.resolve() and r4.ids() == ["m", "a", "z", "vor_allem"], str(r4.ids()))


# ── 3. Zufallsströme ──────────────────────────────

func _t03_rng_streams() -> void:
	var a := RngStreams.new()
	a.reset(12345)
	var b := RngStreams.new()
	b.reset(12345)
	var seq_a: Array = []
	for i in 5:
		seq_a.append(a.stream("klima").randi())
	b.stream("neues.modul").randi()          # ein zusätzlicher Strom …
	b.stream("noch.eins").randf()
	var seq_b: Array = []
	for i in 5:
		seq_b.append(b.stream("klima").randi())
	_check("Zufallsstrom je Modul: gleicher Startwert + gleiche ID → gleiche Folge; weitere Ströme verschieben sie nicht", seq_a == seq_b)
	var c := RngStreams.new()
	c.reset(12346)
	_check("Anderer Weltstartwert oder andere ID → anderer Strom", c.stream("klima").randi() != seq_a[0] and RngStreams.seed_for(12345, "klima") != RngStreams.seed_for(12345, "klimb"))
	var d := RngStreams.new()
	d.from_dict(_n(a.to_dict()))
	_check("Zufallsströme überstehen Speichern/Laden (nächste Zahl identisch)", d.stream("klima").randi() == a.stream("klima").randi() and d.world_seed == 12345)
	# Vorhandene Ströme der Simulation bleiben unberührt: ein Strom, der im Spiel gezogen wird, ändert den Ablauf nicht
	var l1 := _env()
	l1.new_game(world_seed)
	var l2 := _env()
	l2.new_game(world_seed)
	for i in 120:
		l1.step(DT)
		l2.ctx.rng_streams.stream("test.stoerer").randf()
		l2.step(DT)
	var h1 := JSON.stringify(SaveManager.snapshot(l1)["creatures"], "", true, true)
	var h2 := JSON.stringify(SaveManager.snapshot(l2)["creatures"], "", true, true)
	_check("Ein neuer Zufallsstrom verändert den Ablauf der bestehenden Systeme nicht (2 s, 50 Wesen, Zustand identisch)", h1 == h2)


# ── 4. WorldAccess ────────────────────────────────

func _t04_world_access() -> void:
	var life := _env()
	life.new_game(world_seed)
	var ter := life.ctx.terrain
	var size := ter.size_cells()
	var same := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var c := Vector3i(rng.randi_range(-2, size.x + 1), rng.randi_range(-2, size.y + 1), rng.randi_range(-2, size.z + 1))
		var t := life.world.data.get_cell(c.x, c.y, c.z)
		if ter.type_at(c) != t or ter.is_solid(c) != (life.world.palette.solid[t] == 1) or ter.in_bounds(c) != life.world.data.in_bounds(c.x, c.y, c.z):
			same = false
	_check("WorldAccess liefert dieselben Zellen wie die Weltdaten (400 Stichproben, auch außerhalb der Karte = Luft)", same and ter.size_m() == Vector3(32, 16, 32) and ter.cell_size() == 0.5)
	var tc: Vector3i = life.world.generated["tree_cell"]
	var col := Vector2i(tc.x + 6, tc.z)
	var h := ter.surface_height(col.x, col.y)
	_check("Oberflächenhöhe = höchste feste Zelle + 1; außerhalb der Karte 0", h > 0 and ter.is_solid(Vector3i(col.x, h - 1, col.y)) and not ter.is_solid(Vector3i(col.x, h, col.y))
		and ter.surface_height(-1, 0) == 0 and ter.surface_height(0, size.z) == 0 and ter.material_at(Vector3i(col.x, h, col.y)) == "" and ter.material_at(Vector3i(col.x, h - 1, col.y)) != "")
	var before_v := life.ctx.nav.version
	var r := ter.set_material(Vector3i(col.x, h, col.y), ter.type_id("stone"), "Test")
	var logged := false
	for e in life.sim.event_log.all_entries():
		if str(e.get("type", "")) == "terrain_edit" and str(e.get("data", {}).get("cause", "")) == "Test":
			logged = true
	_check("set_material ist der Schreibweg: Zelle gesetzt, Navigation aktualisiert, Ursache protokolliert", r["ok"] and ter.surface_height(col.x, col.y) == h + 1 and life.ctx.nav.version == before_v + 1
		and int(life.ctx.nav.ground[col.x + life.ctx.nav.w * col.y]) == h + 1 and logged)
	var bad := ter.set_material(Vector3i(-3, 0, 0), ter.type_id("stone"), "Test")
	var bedrock := ter.set_material(Vector3i(col.x, 0, col.y), 0, "Test")
	_check("set_material lehnt Zellen außerhalb der Karte und verankertes Grundgestein ab", not bad["ok"] and not bedrock["ok"])
	var hit := ter.raycast(Vector3(col.x + 0.5, h + 6, col.y + 0.5) * ter.cell_size(), Vector3.DOWN, 20.0)
	_check("Strahl von oben trifft die neue Oberfläche", hit.get("hit", false) and hit["cell"] == Vector3i(col.x, h, col.y))


# ── 5. Kartenvorlagen ─────────────────────────────

func _t05_map_templates() -> void:
	var listed := MapTemplate.list_all()
	var all := MapTemplate.list_all(true)
	var ids: Array = []
	for t in listed:
		ids.append(t.id)
	_check("Kartenvorlagen aus data/maps: „Lichtung (klein, wie v0.6)“ ist wählbar; Prüfkarten sind nicht gelistet", ids.has("lichtung") and not ids.has("pruefkarte_schmal") and all.size() > listed.size()
		and (listed[0] as MapTemplate).id == MapTemplate.DEFAULT_ID, str(ids))
	var t := MapTemplate.load_id("lichtung")
	var cfg := t.world_cfg(db.config("world"))
	var base: Dictionary = db.config("world")
	var same := true
	for k in base:
		if JSON.stringify(_n(cfg.get(k))) != JSON.stringify(_n(base[k])):
			same = false
	_check("Vorlage „lichtung“ = Welt von v0.6.x: 32 × 16 × 32 m, Zellen 0,5 m, Generatorwerte unverändert", t.errors.is_empty() and t.size_cells == Vector3i(64, 32, 64) and same and t.generator == "lichtung_v0" and t.latitude_deg == 50.0 and not t.sea)
	var life := _env()
	life.new_game(world_seed)
	_check("Neues Spiel ohne Angabe nutzt die Standardvorlage; Gelände bitgleich mit v0.6.1 (SHA-256 b54f3496…)", life.map.id == "lichtung" and life.base_hash.begins_with("b54f34964bfa264b"), life.base_hash.substr(0, 16))
	var bad := MapTemplate.load_id("gibt_es_nicht")
	var life2 := _env()
	var r := life2.new_game(world_seed, "gibt_es_nicht")
	_check("Unbekannte Kartenvorlage: verständlicher Fehler, kein Spiel, keine Wesen", not bad.errors.is_empty() and not r["ok"] and str(r["message"]).find("nicht gefunden") >= 0 and life2.ctx.creatures.is_empty() and not life2.game_ready, str(r["message"]))
	# Ungültige Vorlagen (im Benutzerordner nachgebaut) werden abgewiesen
	var t2 := MapTemplate.new()
	t2.id = "kaputt"
	t2.raw = {"schema_version": 1, "id": "kaputt", "cell_size_m": 0.5, "size_m": [10.3, 16, 32], "generator": "lichtung_v0", "generator_version": 1}
	t2._read()
	var t3 := MapTemplate.new()
	t3.id = "kaputt2"
	t3.raw = {"schema_version": 1, "id": "kaputt2", "cell_size_m": 0.5, "size_m": [32, 16, 32], "generator": "unbekannt", "generator_version": 1}
	t3._read()
	var t4 := MapTemplate.load_id("pruefkarte_schmal")
	var cfg4 := t4.world_cfg(db.config("world"))
	cfg4["lake"] = {"center": [200, 10], "radius_cells": 5, "floor_cells": 6}
	_check("Ungültige Vorlagen abgewiesen: Größe kein Vielfaches der Zellgröße, unbekannter Generator, See außerhalb der Karte", not t2.errors.is_empty() and not t3.errors.is_empty() and not t4.check_cfg(cfg4).is_empty(),
		"%s | %s | %s" % [str(t2.errors), str(t3.errors), str(t4.check_cfg(cfg4))])


# ── 6. Nicht-quadratische Karte ───────────────────

func _t06_nonsquare_map() -> void:
	var life := _env()
	var r := life.new_game(4711, "pruefkarte_schmal")
	_check("Nicht-quadratische Karte 48 × 32 × 80 Zellen: neues Spiel mit 50 Wesen", r.get("ok", false) and life.ctx.terrain.size_cells() == Vector3i(48, 32, 80) and life.ctx.creatures.size() == 50, str(r.get("message", "")))
	if not r.get("ok", false):
		return
	var size := life.ctx.terrain.size_m()
	_check("Navigation, Wasser und Chunks folgen der Kartengröße (48 × 80 Spalten, 3 × 5 Chunks)", life.ctx.nav.w == 48 and life.ctx.nav.d == 80 and life.world.water.w == 48 and life.world.water.d == 80 and life.world.chunks.size() == 15
		and life.world.water.total() > 1.0, "Wasser %.1f m³, Chunks %d" % [life.world.water.total(), life.world.chunks.size()])
	_run(life, 60.0)
	var inside := true
	for cid in life.ctx.creatures:
		var cr: Creature = life.ctx.creatures[cid]
		if cr.position.x < 0.0 or cr.position.z < 0.0 or cr.position.x > size.x or cr.position.z > size.z:
			inside = false
	var foods_in := true
	for fid in life.ctx.foods:
		var f: FoodSource = life.ctx.foods[fid]
		if f.position.x < 0.0 or f.position.z < 0.0 or f.position.x > size.x or f.position.z > size.z:
			foods_in = false
	_check("60 s auf der schmalen Karte: alle Wesen und Nahrungsquellen in der Karte, Wegsuche ohne Fehlschlag, Prüfung ohne Befund", inside and foods_in and life.audit().is_empty() and int(life.ctx.nav.stats["failed"]) == 0 and int(life.ctx.nav.stats["found"]) > 20,
		"Wegsuchen %s, Audit %s" % [str(life.ctx.nav.stats), str(life.audit().slice(0, 2))])
	var path := "user://saves/_test_schmal.json"
	var sv := SaveManager.save(life, path)
	var life2 := _env()
	var lr := SaveManager.load_into(life2, path)
	_check("Spielstand der schmalen Karte: Vorlage im Spielstand, lädt in derselben Größe", sv["ok"] and lr["ok"] and life2.map.id == "pruefkarte_schmal" and life2.ctx.terrain.size_cells() == Vector3i(48, 32, 80) and life2.audit().is_empty(), str(lr.get("message", "")))
	notes.append("Nicht-quadratische Prüfkarte 48 × 32 × 80: 60 s mit 50 Wesen, Wegsuchen %d (0 fehlgeschlagen), Wasser %.1f m³" % [int(life.ctx.nav.stats["found"]), life.world.water.total()])
	for ext in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))


# ── 7. Speicherabschnitte im Rundlauf ─────────────

func _t07_sections_roundtrip() -> void:
	var life := _env()
	life.new_game(world_seed)
	_run(life, 20.0)
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	life.ctx.interventions.execute({"kind": "place_material", "target_id": int(ids[0]), "material_id": "stone", "size_m": 0.08})
	var tc: Vector3i = life.world.generated["tree_cell"]
	var h := life.ctx.terrain.surface_height(tc.x + 7, tc.z + 1)
	life.ctx.terrain.set_material(Vector3i(tc.x + 7, h, tc.z + 1), life.ctx.terrain.type_id("stone"), "Test")
	life.ctx.terrain.set_material(Vector3i(40, life.ctx.terrain.surface_height(40, 20) - 1, 20), 0, "Test")
	life.ctx.rng_streams.stream("test.strom").randi()
	_run(life, 2.0)
	var path := "user://saves/_test_abschnitte.json"
	var sv := SaveManager.save(life, path)
	var doc := SaveManager.document(life)
	var text := FileAccess.get_file_as_string(path)
	var header: Dictionary = JSON.parse_string(text.substr(0, text.find("\n")))
	var body: Dictionary = JSON.parse_string(text.substr(text.find("\n") + 1))
	var versions_ok := true
	for mid in body["modules"]:
		if int(body["modules"][mid].get("v", 0)) != 1:
			versions_ok = false
	_check("Format 6: Kopf + Abschnitt je Modul (jeder mit Version) + Region; Formatversion 6 in Kopfzeile und Datei", sv["ok"] and int(header["format_version"]) == 6 and int(body["format_version"]) == 6
		and body.has("meta") and versions_ok and body["modules"].keys().size() == 10 and body["regions"].has("main") and str(body["meta"]["game_version"]).begins_with("alpha-1."),
		"Abschnitte %s" % str(body["modules"].keys()))
	var want := ["core", "actors", "actions", "settlement", "social", "god", "technology", "work", "communication", "ecology.food"]
	want.sort()
	var got: Array = body["modules"].keys()
	got.sort()
	_check("Abschnitte gehören den Modulen mit Zustand; Module ohne Zustand (Zeit, Werkzeuggebrauch, Wahrnehmung, Entscheidung) schreiben keinen", got == want, str(got))
	var life2 := _env()
	var lr := SaveManager.load_into(life2, path)
	_check("Rundlauf: Speichern → Laden in frische Welt", lr["ok"] and life2.audit().is_empty(), str(lr.get("message", "")) + str(life2.audit().slice(0, 2)))
	if not lr["ok"]:
		return
	var doc2 := SaveManager.document(life2)
	var diffs: Array = []
	for mid in doc["modules"]:
		var a = _n(doc["modules"][mid])
		var b = _n(doc2["modules"][mid])
		if mid == "actions":
			a["actions"].erase("running")     # Ladeverhalten: einzelne Handlungen werden kontrolliert abgebrochen
			b["actions"].erase("running")
			a["actions"].erase("history_tail")
			b["actions"].erase("history_tail")
		if mid == "actors":
			for arr in [a["creatures"], b["creatures"]]:
				for e in arr:
					e.erase("last_result")
					e.erase("next_decision_t")
		var d := TestTechnology.first_diff(a, b, mid)
		if d != "":
			diffs.append(d)
	_check("Rundlauf: jeder Modulabschnitt nach dem Laden inhaltlich identisch (bis auf kontrolliert abgebrochene Handlungen)", diffs.is_empty(), str(diffs.slice(0, 3)))
	var ra: Dictionary = _n(doc["regions"]["main"])
	var rb: Dictionary = _n(doc2["regions"]["main"])
	_check("Rundlauf: Region identisch (Vorlage, Startwert, Geländeprüfsummen, 2 geänderte Zellen als Chunk-Deltas, Wasser)", TestTechnology.first_diff(ra, rb, "Region") == "" and int(ra["changed_cells"]) == 2
		and str(ra["map_id"]) == "lichtung" and life2.world.data.hash_sha256() == life.world.data.hash_sha256(), TestTechnology.first_diff(ra, rb, "Region"))
	_check("Rundlauf: Zeit, Takte, nächste ID und Zufallszustände (Simulation, Nahrung, Modulströme) identisch", life2.ctx.now() == life.ctx.now() and life2.sim.clock.tick_count == life.sim.clock.tick_count
		and life2.sim.registry.next_id() == life.sim.registry.next_id() and life2.sim.rng.state == life.sim.rng.state and life2.food_rng.state == life.food_rng.state
		and life2.ctx.rng_streams.stream("test.strom").state == life.ctx.rng_streams.stream("test.strom").state)
	# Fremder Abschnitt / fehlender Pflichtabschnitt / neuere Abschnittsversion
	var cases := {}
	var d1: Dictionary = _n(body)
	d1["modules"]["fremdes.modul"] = {"v": 1}
	cases["unknown_module"] = SaveManager.apply(_env(), d1)
	var d2: Dictionary = _n(body)
	d2["modules"]["social"]["v"] = 99
	cases["newer_format"] = SaveManager.apply(_env(), d2)
	var d3: Dictionary = _n(body)
	d3["modules"].erase("work")
	cases["invalid"] = SaveManager.apply(_env(), d3)
	var d4: Dictionary = _n(body)
	d4["regions"]["main"]["chunks"]["9,9,9"] = {"n": 1, "bytes": 8, "data": "AAAA"}
	cases["invalid "] = SaveManager.apply(_env(), d4)
	var bad: Array = []
	for k in cases:
		if cases[k]["ok"] or str(cases[k]["code"]) != str(k).strip_edges() or str(cases[k]["message"]) == "":
			bad.append("%s→%s" % [k, str(cases[k].get("code"))])
	_check("Abgewiesen ohne Teil-Laden: Abschnitt eines unbekannten Moduls, neuere Abschnittsversion, fehlender Abschnitt, Chunk außerhalb der Welt", bad.is_empty(), str(bad))
	var peek := SaveManager.peek(path)
	_check("Menü-Kurzinfo liest Format 6 (Zeit, Wesen, Karte, Version)", peek["ok"] and int(peek["alive"]) + int(peek["dead"]) == 50 and str(peek["map_id"]) == "lichtung" and absf(float(peek["time_s"]) - life.ctx.now()) < 1e-9)
	notes.append("Spielstand Format 6 (50 Wesen, 22 s): %d kB, 10 Abschnitte, Region mit %d geänderten Zellen in %d Chunk(s)" % [text.length() / 1024, int(ra["changed_cells"]), (ra["chunks"] as Dictionary).size()])
	for ext in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))


# ── 8. Chunk-Deltas ───────────────────────────────

func _t08_chunk_deltas() -> void:
	var size := Vector3i(40, 20, 24)
	var cd := Vector3i(16, 8, 16)
	var base := PackedByteArray()
	base.resize(size.x * size.y * size.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in base.size():
		base[i] = rng.randi_range(0, 4)
	var cells := base.duplicate()
	var changed := {}
	for i in 300:
		var idx := rng.randi_range(0, cells.size() - 1)
		cells[idx] = (cells[idx] + 1 + rng.randi_range(0, 3)) % 6
		changed[idx] = true
	var real := 0
	for idx in changed:
		if cells[idx] != base[idx]:
			real += 1
	var dl := RegionStore.deltas(base, cells, size, cd)
	var ar := RegionStore.apply_deltas(base.duplicate(), _n(dl["chunks"]), size, cd)
	_check("Chunk-Deltas: nur geänderte Zellen, je Chunk gespeichert; Anwenden auf das Grundgelände ergibt exakt den Zustand", int(dl["changed"]) == real and ar["ok"] and ar["cells"] == cells and int(ar["changed"]) == real
		and (dl["chunks"] as Dictionary).size() <= 3 * 3 * 2, "%d Zellen in %d Chunks" % [real, (dl["chunks"] as Dictionary).size()])
	var none := RegionStore.deltas(base, base, size, cd)
	_check("Unverändertes Gelände → keine Chunks im Spielstand", (none["chunks"] as Dictionary).is_empty() and int(none["changed"]) == 0)
	# Rand: letzte Zelle der Welt (unvollständiger Chunk an der Kartenkante)
	var edge := base.duplicate()
	edge[edge.size() - 1] = (edge[edge.size() - 1] + 1) % 6
	var de := RegionStore.deltas(base, edge, size, cd)
	var ae := RegionStore.apply_deltas(base.duplicate(), de["chunks"], size, cd)
	_check("Änderung an der Kartenkante (angeschnittener Chunk) bleibt erhalten", ae["ok"] and ae["cells"] == edge and (de["chunks"] as Dictionary).keys() == ["2,2,1"], str((de["chunks"] as Dictionary).keys()))
	# Umrechnung der Format-5-Liste
	var glob: Array = []
	for i in cells.size():
		if cells[i] != base[i]:
			glob.append([i, cells[i]])
	var dg := RegionStore.deltas_from_global(_n(glob), size, cd)
	var ag := RegionStore.apply_deltas(base.duplicate(), dg["chunks"], size, cd)
	_check("Format-5-Änderungsliste wird verlustfrei in Chunk-Deltas umgerechnet", dg["ok"] and ag["ok"] and ag["cells"] == cells)
	var broken: Dictionary = _n(dl["chunks"])
	var k0: String = broken.keys()[0]
	broken[k0]["n"] = int(broken[k0]["n"]) + 1
	_check("Beschädigte Chunk-Daten werden erkannt", not RegionStore.apply_deltas(base.duplicate(), broken, size, cd)["ok"])


# ── 9. Migration 5 → 6 mit echten Spielständen aus v0.6.1 ─────────

func _t09_migration_v5() -> void:
	for fx in FIXTURES:
		var path := "user://saves/_test_mig_v5_%s.json" % str(fx[1]).replace(" ", "_")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
		for ext in ["", ".bak", ".v5.vor_migration"]:
			if FileAccess.file_exists(path + ext):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/" + str(fx[0])), ProjectSettings.globalize_path(path))
		var orig := FileAccess.get_file_as_string(path)
		var head: Dictionary = JSON.parse_string(orig.substr(0, orig.find("\n")))
		var raw: Dictionary = JSON.parse_string(orig.substr(orig.find("\n") + 1))
		var life := _env()
		var calls := PopulationSpawner.spawn_calls
		var r := SaveManager.load_into(life, path)
		_check("Migration 5 → 6 (%s, echter Spielstand v0.6.1): lädt, Original unverändert gesichert, Spawner nicht aufgerufen" % fx[1],
			r["ok"] and int(head["format_version"]) == 5 and str(raw["game_version"]) == "0.6.1-prototype" and int(r.get("migrated_from", 0)) == 5
			and FileAccess.get_file_as_string(path + ".v5.vor_migration") == orig and PopulationSpawner.spawn_calls == calls, str(r.get("message", "")).substr(0, 220))
		if not r["ok"]:
			continue
		var ctx := life.ctx
		var snap := SaveManager.snapshot(life)
		var diffs: Array = []
		for k in ["foods", "items", "ledger", "material_pieces", "assemblies", "heaters", "storages", "structures", "social", "interventions", "communication", "workshop"]:
			var d := TestTechnology.first_diff(_n(raw.get(k)), _n(snap.get(k)), k)
			if d != "":
				diffs.append(d)
		# Ladeverhalten wie bis v0.6.1 (kein Teil der Migration): laufende Handlungen werden kontrolliert abgebrochen,
		# laufende Versuche als „unterbrochen“ beendet. Verglichen werden deshalb Anzahl, Nummern und alle beendeten Versuche.
		var ea: Array = _n(raw["experiments"]["records"])
		var eb: Array = _n(snap["experiments"]["records"])
		var exp_ok := ea.size() == eb.size() and int(raw["experiments"]["next_id"]) == int(snap["experiments"]["next_id"])
		for i in mini(ea.size(), eb.size()):
			if float(ea[i].get("ended_t", -1.0)) >= 0.0 and TestTechnology.first_diff(ea[i], eb[i], "Versuch") != "":
				exp_ok = false
			if int(ea[i]["id"]) != int(eb[i]["id"]):
				exp_ok = false
		if not exp_ok:
			diffs.append("Versuche weichen ab")
		var ca: Array = _n(raw["creatures"])
		var cb: Array = _n(snap["creatures"])
		for arr in [ca, cb]:
			for e in arr:
				e.erase("last_result")
				e.erase("next_decision_t")
				e["mind"]["tech"].erase("experiment_id")
				e["mind"]["tech"].erase("next_experiment_t")
				e["mind"]["tech"].erase("hypotheses")
		var dc := TestTechnology.first_diff(ca, cb, "creatures")
		if dc != "":
			diffs.append(dc)
		_check("Migration 5 → 6 (%s): Wesen, Nahrung, Gegenstände, Verbünde, Lager, Bauwerke, Versuche, Gespräche, Eingriffe inhaltlich unverändert" % fx[1], diffs.is_empty(), str(diffs.slice(0, 3)))
		_check("Migration 5 → 6 (%s): Zeit, Takte, nächste ID, Zufallszustände, Gelände und Wasser erhalten; nichts erfunden (keine Modulströme)" % fx[1],
			ctx.now() == float(raw["simulation"]["time_s"]) and life.sim.clock.tick_count == int(raw["simulation"]["tick_count"]) and life.sim.registry.next_id() == int(raw["simulation"]["registry_next_id"])
			and str(life.sim.rng.state) == str(raw["simulation"]["sim_rng"]["state"]) and str(life.food_rng.state) == str(raw["simulation"]["food_rng"]["state"])
			and life.world.data.hash_sha256() == str(raw["world"]["current_hash"]) and absf(life.world.water.total() - float(raw["world"]["water_total_m3"])) < 1e-9
			and ctx.rng_streams.streams.is_empty() and life.map.id == "lichtung" and life.audit().is_empty(), str(life.audit().slice(0, 2)))
		if str(fx[0]).contains("werkzeugkette"):
			var cr := WorkChainScene.actor(life)
			var wc: WorkChain = ctx.work.active(cr)
			var raw_chain: Dictionary = raw["work"]["chains"][0]
			_check("Migration 5 → 6 (Werkzeugkette): die laufende Kette ist nach dem Laden weiter aktiv (gleiches Ziel, gleicher Schritt)", wc != null and str(wc.goal) == str(raw_chain.get("goal", ""))
				and int(wc.id) == int(raw_chain.get("id", -1)), "Kette %s" % (str(wc.goal) if wc != null else "fehlt"))
			for i in int(420.0 / DT):
				life.step(DT)
				if ctx.work.active(cr) == null:
					break
			var all := ctx.work.of_creature(cr.id)
			_check("Migration 5 → 6 (Werkzeugkette): die übernommene Kette wird zu Ende geführt (Steinreihe fertig)", not all.is_empty() and str((all[0] as WorkChain).status) == "abgeschlossen" and life.audit().is_empty(),
				"Status %s" % (str((all[0] as WorkChain).status) if not all.is_empty() else "–"))
		else:
			_run(life, 10.0)
		var sv := SaveManager.save(life, path)
		var life2 := _env()
		var r2 := SaveManager.load_into(life2, path)
		var text2 := FileAccess.get_file_as_string(path)
		var body2: Dictionary = JSON.parse_string(text2.substr(text2.find("\n") + 1))
		_check("Migration 5 → 6 (%s): danach im Format 6 gespeichert und ohne Migration wieder geladen; Audit leer" % fx[1],
			sv["ok"] and r2["ok"] and int(r2.get("migrated_from", 0)) == 0 and int(body2["format_version"]) == 6 and life2.audit().is_empty() and life2.ctx.creatures.size() == ctx.creatures.size(), str(r2.get("message", "")))
		for ext in ["", ".bak", ".v5.vor_migration"]:
			if FileAccess.file_exists(path + ext):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
	# Veränderte Definitionen in Format 5 → keine Migration
	var t := FileAccess.get_file_as_string("res://tests/fixtures/save_v5_v061_werkstatt.json")
	var p_bad: Dictionary = JSON.parse_string(t.substr(t.find("\n") + 1))
	p_bad["definitions"]["hash"] = "verändert"
	var mr := SaveMigrations.migrate(p_bad, 5)
	_check("Migration verweigert Format-5-Stände mit veränderten Definitionen", not mr["ok"] and mr["code"] == "definitions_changed", str(mr["message"]))
	var p_cut: Dictionary = JSON.parse_string(t.substr(t.find("\n") + 1))
	p_cut.erase("work")
	var mc := SaveMigrations.migrate(p_cut, 5)
	_check("Migration verweigert unvollständige Format-5-Stände", not mc["ok"] and mc["code"] == "invalid")


# ── 10. Determinismus ─────────────────────────────

func _t10_determinism() -> void:
	var sums: Array = []
	var mets: Array = []
	for run in 2:
		var life := _env()
		life.new_game(world_seed)
		_run(life, 30.0)
		var snap := SaveManager.snapshot(life)
		var s := ""
		for k in ["creatures", "foods", "items", "ledger", "social", "communication"]:
			s += SaveSchema.sha256_text(JSON.stringify(snap[k], "", true, true))
		sums.append(SaveSchema.sha256_text(s))
		var m := life.modules.metrics_all()
		mets.append(JSON.stringify([m["actors"], m["ecology.food"], m["actions"]["angefordert"], life.ctx.executor.stats]))
		sc.cleanup()
	_check("Determinismus: gleicher Startwert → gleicher Zustand und gleiche Messwerte je Modul (2 Läufe à 30 s, 50 Wesen)", sums[0] == sums[1] and mets[0] == mets[1], "%s / %s" % [str(sums[0]).substr(0, 12), str(sums[1]).substr(0, 12)])
	notes.append("Determinismus 30 s: Zustandsprüfsumme %s…, Messwerte %s" % [str(sums[0]).substr(0, 16), str(mets[0]).substr(0, 160)])


# ── 11. Abschnittsversionen ───────────────────────

func _t11_section_versions() -> void:
	var log: Array = []
	var life := _env()
	var probe := Probe.new("probe.abschnitt", ["ecology.food"] as Array[String], log)
	life.modules = ModuleRegistry.new()
	life._register_modules([probe])
	life.new_game(world_seed)
	_run(life, 1.0)
	probe.value = 7
	var doc: Dictionary = _n(SaveManager.document(life))
	_check("Zusätzliches Modul schreibt seinen Abschnitt mit eigener Version", int(doc["modules"]["probe.abschnitt"]["v"]) == 2 and int(doc["modules"]["probe.abschnitt"]["wert"]) == 7)
	# a) Abschnitt älterer Version → vom Modul selbst angehoben
	var old_doc: Dictionary = _n(doc)
	old_doc["modules"]["probe.abschnitt"] = {"v": 1, "alt": 4}
	var l2 := _env()
	var p2 := Probe.new("probe.abschnitt", ["ecology.food"] as Array[String], log)
	l2.modules = ModuleRegistry.new()
	l2._register_modules([p2])
	var r2 := SaveManager.apply(l2, old_doc)
	_check("Abschnitt älterer Version wird beim Laden vom Modul angehoben (1 → 2), die übrigen Abschnitte bleiben unberührt", r2["ok"] and p2.value == 40 and str(r2.get("section_notes", [])).find("probe.abschnitt") >= 0, str(r2.get("message", "")))
	# b) Spielstand OHNE den Abschnitt (älteres Programm kannte das Modul nicht) → Startzustand, nichts erfunden
	var no_doc: Dictionary = _n(doc)
	no_doc["modules"].erase("probe.abschnitt")
	var l3 := _env()
	var p3 := Probe.new("probe.abschnitt", ["ecology.food"] as Array[String], log)
	l3.modules = ModuleRegistry.new()
	l3._register_modules([p3])
	var r3 := SaveManager.apply(l3, no_doc)
	_check("Spielstand ohne Abschnitt eines neuen (optionalen) Moduls lädt mit dessen Startzustand", r3["ok"] and p3.value == 0 and l3.ctx.creatures.size() == 50, str(r3.get("message", "")))
	# c) Abschnitt ohne Migrationsweg → Abweisung
	var gap: Dictionary = _n(doc)
	gap["modules"].erase("probe.abschnitt")
	gap["modules"]["social"]["v"] = 0
	var r4 := SaveManager.apply(_env(), gap)
	_check("Abschnitt ohne gültige Version wird abgewiesen", not r4["ok"] and r4["code"] == "invalid")


# ── 12. Kein direkter Geländezugriff außerhalb der Welt-Schicht ───

func _t12_no_direct_terrain_access() -> void:
	var hits: Array = []
	_scan_dir("res://scripts", hits)
	_check("Kein Skript außerhalb der Welt-Schicht (scripts/world) greift direkt auf VoxelData zu – nur über WorldAccess", hits.is_empty(), str(hits.slice(0, 6)))


func _scan_dir(dir: String, hits: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for sub in da.get_directories():
		if dir + "/" + sub == "res://scripts/world":
			continue
		_scan_dir(dir + "/" + sub, hits)
	var re := RegEx.new()
	re.compile("world\\.data\\b|\\.data\\.(cells|size|cell_size|get_cell|set_cell|in_bounds|column_top|world_to_cell)\\b|VoxelData\\.new")
	for f in da.get_files():
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(dir + "/" + f).split("\n"):
			n += 1
			if line.strip_edges().begins_with("#"):
				continue
			if re.search(line) != null:
				hits.append("%s/%s:%d" % [dir.trim_prefix("res://"), f, n])


# ── 13. Zeitmessung je Modul ──────────────────────

func _t13_timing() -> void:
	var life := _env()
	life.new_game(world_seed)
	_run(life, 5.0)
	var rep := life.modules.timing_report()
	var mods: Dictionary = rep["modules"]
	var share := 0.0
	var all_called := true
	for mid in mods:
		share += float(mods[mid]["share"])
		if int(mods[mid]["calls"]) != 300:
			all_called = false
	var tick_avg := float(life.perf["sum_us"]) / float(life.perf["ticks"]) / 1000.0
	var mod_avg := float(rep["total_ms"]) / 300.0
	_check("Zeitmessung je Modul: jedes Modul 300 Takte gemessen, Anteile ergeben 100 %, Summe ≤ gemessene Taktzeit", mods.size() == 16 and all_called and absf(share - 1.0) < 1e-6 and mod_avg <= tick_avg + 0.05 and mod_avg > 0.0,
		"Module %.3f ms, Takt %.3f ms" % [mod_avg, tick_avg])
	var top: Array = mods.keys()
	top.sort_custom(func(a, b): return float(mods[a]["avg_ms"]) > float(mods[b]["avg_ms"]))
	var parts: Array = []
	for mid in top.slice(0, 5):
		parts.append("%s %.3f ms (%.0f %%)" % [mid, float(mods[mid]["avg_ms"]), float(mods[mid]["share"]) * 100.0])
	notes.append("Simulationszeit je Modul (50 Wesen, 5 s, ohne Grafik): Takt Ø %.2f ms; größte Anteile: %s" % [tick_avg, ", ".join(parts)])
	var mm := life.modules.metrics_all()
	_check("Messwerte je Modul: Akteure 50, Nahrungsquellen > 0, Kern zählt Entitäten", int(mm["actors"]["wesen"]) == 50 and int(mm["ecology.food"]["quellen"]) > 0 and int(mm["core"]["entitaeten"]) > 50, str(mm["actors"]))
	life.modules.measure = false
	life.modules.reset_timing()
	_run(life, 1.0)
	_check("Zeitmessung abschaltbar (keine Messung, Simulation läuft unverändert weiter)", int(life.modules.timing["life"]["calls"]) == 0 and life.audit().is_empty())


# ── 14. Definitionen und Version ──────────────────

func _t14_definitions() -> void:
	var fp := SaveSchema.definitions_fingerprint()
	var has_maps := false
	for p in fp["files"]:
		if str(p).begins_with("res://data/maps/"):
			has_maps = true
	_check("Kartenvorlagen gehören zu den Spieldefinitionen (Fingerabdruck)", has_maps)
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	_check("Versionsschema Alpha: project.godot „alpha-1.N“, Anzeige „Alpha 1.N“", ver.begins_with("alpha-1.") and MainMenuVersion.text().begins_with("Alpha 1."), ver)
	var t := FileAccess.get_file_as_string("res://tests/fixtures/save_v5_v061.json")
	var v5: Dictionary = JSON.parse_string(t.substr(t.find("\n") + 1))
	_check("Ausgelieferte Definitionen v0.6.1 (echter Prüfling) sind als ladbare Vorversion eingetragen", SaveSchema.shipped_version_of(str(v5["definitions"]["hash"])) == "v0.6.1"
		and str(v5["definitions"]["hash"]) == SaveMigrations.V5_SHIPPED_DEFINITIONS)
	var cur := SaveSchema.shipped_version_of(str(fp["hash"]))
	_check("Ausgelieferte Definitionen dieser Version sind eingetragen (SaveSchema.SHIPPED_DEFINITIONS)", cur == ver, "aktuell %s → '%s'" % [str(fp["hash"]), cur])
	var unknown: Dictionary = _n(SaveManager.document(_game()))
	unknown["meta"]["definitions"]["hash"] = "0000"
	var r := SaveManager.apply(_env(), unknown)
	_check("Spielstand mit unbekannten (veränderten) Definitionen wird weiterhin abgewiesen", not r["ok"] and r["code"] == "definitions_changed")


func _game() -> LifeSimulation:
	var life := _env()
	life.new_game(world_seed)
	_run(life, 1.0)
	return life
