class_name WorkChainScene
extends RefCounted
## Testszene „Werkzeugkette“ (Prompt 6B) – getrennt vom normalen Spiel. EIN Testwesen, zugängliche
## Materialien und eine Arbeitsstelle:
##   Hammerteile (Holzstiel, Steinkopf, Pflanzenfasern), ein großer Stein (zu groß für einen Bauplatz,
##   für eine Hand zu schwer), Kupferstücke, ein Holzstück (nicht schmelzbar), ein sehr schwerer Block
##   (auch mit zwei Händen zu schwer), ein realer Lagerplatz, eine Baustelle „Steinreihe“ (3 Plätze)
##   und Testausrüstung zum Schmelzen (Testofen, Tiegel mit Griff, Gussform).
## Die Ketten laufen über DENSELBEN Code wie im normalen Spiel (WorkSystem → ActionExecutor → Handlungen).
## Die Szene löst sie nur gezielt aus (Herkunft sichtbar). Ein gezielt ausgelöster Ablauf beweist, dass
## die Kette funktioniert – nicht, dass Wesen sie von selbst wählen. Eigenständige Wahl: Beobachtungslauf
## mit eingeschaltetem Verhalten (Taste „Verhalten an“ bzw. tools/observe_work.gd).
## Der Testofen ist Testausrüstung: kein Nachweis, dass Wesen Öfen bauen können.

const SOURCE := "Testszene Werkzeugkette (gezielt ausgelöst)"
const GOALS := {"lagern": "Hammer bauen → großen Stein zerschlagen → Stücke einlagern",
	"bauen": "Hammer bauen → großen Stein zerschlagen → Steinreihe bauen",
	"schmelzen": "Hammer bauen → Kupfer bearbeiten → in den Tiegel → Testofen → gießen"}
const CASES := {
	"material": "Fehlendes Material: Fasern entfernt → Hammer nicht planbar",
	"weg": "Blockierter Weg: Lager ummauert → Kette stoppt nachvollziehbar",
	"arm": "Fehlender Arm: rechter Unterarm entfernt → einarmige Variante bzw. Ablehnung",
	"schwer": "Zu schwerer Gegenstand: sehr schwerer Block soll getragen werden",
	"unterbrechen": "Unterbrochene Handlung: Kette pausiert und wird fortgesetzt",
	"ungeeignet": "Ungeeignetes Schmelzgut: Holz in den Tiegel → abgewiesen",
	"ohne_ofen": "Fehlende Wärmequelle: Ofen entfernt → Kette stoppt",
}


## Baut Welt, Nahrung, das Testwesen und die Ausrüstung. Rückgabe {ok, ids, center, a, message}.
static func setup(life: LifeSimulation, world_seed: int, behavior: bool = false) -> Dictionary:
	life.build_world(world_seed)
	life._create_food_sources(world_seed)
	var ctx := life.ctx
	var center := _flat_spot(life, life.tree_node.position + Vector3(-6, 0, 3))
	var sr := PopulationSpawner.spawn(ctx, 1, world_seed + 991, center)
	if not sr["ok"]:
		return sr
	var a: Creature = ctx.creatures.values()[0]
	a.position = center
	a.heading = 0.0
	a.behavior_enabled = behavior
	var amb := ctx.sim.thermal.ambient_temperature_k
	var o := {}
	var items := [
		["handle", "wood", "rod", Vector3(0.36, 0.026, 0.026), Vector3(0.4, 0, 0.45), "Holzstiel"],
		["head", "stone", "block", Vector3(0.06, 0.055, 0.06), Vector3(2.1, 0, -0.6), "Steinkopf"],
		["fiber", "plant_fiber", "bundle", Vector3(0.12, 0.04, 0.06), Vector3(-0.5, 0, -1.4), "Pflanzenfasern"],
		["big_stone", "stone", "block", Vector3(0.1, 0.1, 0.1), Vector3(-0.3, 0, 1.6), "Großer Stein"],
		["stone_medium", "stone", "block", Vector3(0.075, 0.075, 0.075), Vector3(0.6, 0, -1.6), "Mittlerer Stein"],
		["copper1", "copper", "block", Vector3(0.022, 0.022, 0.022), Vector3(1.0, 0, -0.9), "Kupferstück"],
		["copper2", "copper", "block", Vector3(0.02, 0.02, 0.02), Vector3(1.2, 0, -1.2), "Kupferstück"],
		["wood_scrap", "wood", "rod", Vector3(0.12, 0.02, 0.02), Vector3(1.5, 0, -1.0), "Holzstück"],
		["heavy_block", "stone", "block", Vector3(0.2, 0.18, 0.18), Vector3(-1.2, 0, 0.5), "Sehr schwerer Block"],
	]
	for it in items:
		var p := TestWorkshop._ground(life, center + (it[4] as Vector3))
		var r := ConstructionSystem.new_piece(ctx, it[1], it[2], it[3], amb, p, "test_equipment", it[5], true)
		if not r["ok"]:
			return {"ok": false, "message": "%s: %s" % [it[0], r["message"]]}
		o[it[0]] = int(r["id"])
	# Lagerplatz (real, begrenzte Kapazität) und Baustelle „Steinreihe“ (3 Plätze)
	var sp := StorageSystem.create(ctx, TestWorkshop._ground(life, center + Vector3(-1.6, 0, -0.9)) - Vector3(0, 0.01, 0), Vector2(0.7, 0.7), "Lagerplatz", "test_equipment")
	o["storage"] = sp.id
	var site_pos := TestWorkshop._ground(life, center + Vector3(1.4, 0, 1.6)) - Vector3(0, 0.01, 0)
	var st := StructureSystem.create_site(ctx, "steinreihe", site_pos, 0.0, 0, "test_equipment", "Steinreihe (Testszene)")
	o["site"] = st.id
	# Schmelzen: Tiegel (Keramik) mit Holzgriff, Gussform, Testofen (extern versorgt)
	var hp := TestWorkshop._ground(life, center + Vector3(-1.7, 0, 1.6))
	var cup := ConstructionSystem.new_piece(ctx, "ceramic", "cup", Vector3(0.06, 0.05, 0.06), amb, hp, "test_equipment", "Schmelztiegel", true, 0.04 * 0.04 * 0.04)
	var handle := ConstructionSystem.new_piece(ctx, "wood", "rod", Vector3(0.3, 0.02, 0.02), amb, hp, "test_equipment", "Tiegelgriff", true)
	if not cup["ok"] or not handle["ok"]:
		return {"ok": false, "message": "Tiegel: %s %s" % [cup.get("message", ""), handle.get("message", "")]}
	var fx := ConstructionSystem.connect_fixture(ctx, int(handle["id"]), int(cup["id"]), "Tiegel mit Griff (Testausrüstung)")
	o["crucible"] = int(fx["id"])
	o["cup"] = int(cup["id"])
	var mold := ConstructionSystem.new_piece(ctx, "ceramic", "mold", Vector3(0.08, 0.04, 0.06), amb, TestWorkshop._ground(life, center + Vector3(-2.3, 0, 1.2)),
		"test_equipment", "Gussform", true, 0.048 * 0.036 * 0.025)
	o["mold"] = int(mold["id"])
	var h := TestHeater.new()
	h.position = TestWorkshop._ground(life, center + Vector3(-2.2, 0, 2.0))
	h.power_w = float(ctx.tc("heater").get("power_w", 3500.0))
	h.label = "Testofen"
	ctx.sim.add_entity(h, "test_heater")
	ctx.heaters[h.id] = h
	ctx.sim.thermal.add_heater(h.heater_name(), 0, h.power_w)
	o["heater"] = h.id
	ConstructionSystem.sync_positions(ctx)
	life.next_refill_t = ctx.now() + float(ctx.c("food").get("refill_interval_s", 60.0))
	life.game_ready = true
	life.workshop = o.duplicate()
	life.workshop["a"] = a.id
	life.workshop["work_scene"] = 1   # nur Ganzzahlen (Speicherformat der Werkstattangaben)
	# Das Wesen sieht seine Umgebung (Wahrnehmung wie im Spiel, nur sofort statt im nächsten Takt)
	look_around(life)
	ctx.log_event("work_scene_created", [a.id], {"objects": o, "note": "Testszene Werkzeugkette – Testausrüstung, nicht im normalen Spiel"}, "warning")
	return {"ok": true, "ids": o, "center": center, "a": a.id,
		"message": "Testszene Werkzeugkette: Testwesen #%d, %d Gegenstände, Lager #%d, Baustelle #%d, Testofen #%d." % [a.id, ctx.material_pieces.size(), sp.id, st.id, h.id]}


## Ebener, begehbarer Platz für den Aufbau (Fläche x −2,5…2,5 m, z −1,5…2,5 m) in der Nähe von near,
## mindestens 3,5 m vom Lebensbaum entfernt. Bewertet wird die Höhenabweichung der Geländespalten.
static func _flat_spot(life: LifeSimulation, near: Vector3) -> Vector3:
	var nav := life.ctx.nav
	var tree := life.tree_node.position
	var c0 := nav.world_to_col(near)
	var fx0 := int(ceil(2.5 / nav.cell))
	var fz0 := int(ceil(1.5 / nav.cell))
	var fz1 := int(ceil(2.5 / nav.cell))
	var best := near
	var best_score := INF
	var R := int(ceil(10.0 / nav.cell))
	for dz in range(-R, R + 1):
		for dx in range(-R, R + 1):
			var c := c0 + Vector2i(dx, dz)
			if not nav.in_bounds(c) or not nav.is_walkable(c):
				continue
			var q := nav.col_center(c)
			if Vector2(q.x - tree.x, q.z - tree.z).length() < 3.5:
				continue
			var gy := nav.ground_y(c)
			var dev := 0.0
			for fz in range(-fz0, fz1 + 1):
				for fx in range(-fx0, fx0 + 1):
					var cc := c + Vector2i(fx, fz)
					if not nav.in_bounds(cc) or not nav.is_walkable(cc):
						dev += 10.0
					else:
						dev += absf(nav.ground_y(cc) - gy)
				if dev * 10.0 >= best_score:
					break
			var score := dev * 10.0 + Vector2(q.x - near.x, q.z - near.z).length() * 0.05
			if score < best_score:
				best_score = score
				best = Vector3(q.x, gy, q.z)
	return best


## Wahrnehmung sofort aktualisieren (Gegenstände, Testofen, Lager, Baustelle).
static func look_around(life: LifeSimulation) -> void:
	var ctx := life.ctx
	ctx.rebuild_spatial_hash()
	for id in ctx.creatures:
		var cr: Creature = ctx.creatures[id]
		ExperimentSystem.perceive_objects(cr, ctx)
		var rad := float(ctx.c("perception").get("radius_m", 10.0)) * float(cr.caps.get("perception", 1.0))
		StorageSystem.perceive(cr, ctx, rad)
		StructureSystem.perceive(cr, ctx, rad)


static func actor(life: LifeSimulation) -> Creature:
	if life.workshop.is_empty() or not life.workshop.has("a"):
		return null
	return life.ctx.creature(int(life.workshop["a"]))


## Gezielt eine Kette auslösen: "lagern", "bauen" oder "schmelzen".
static func trigger(life: LifeSimulation, goal: String) -> Dictionary:
	var w: Dictionary = life.workshop
	var cr := actor(life)
	if cr == null or not cr.alive:
		return {"ok": false, "message": "Testwesen fehlt."}
	if life.ctx.work.active(cr) != null:
		return {"ok": false, "message": "Wesen #%d arbeitet noch an Kette #%d." % [cr.id, life.ctx.work.active(cr).id]}
	look_around(life)
	var opts := {}
	match goal:
		"lagern":
			opts = {"storage": int(w["storage"]), "target": int(w["big_stone"]) if life.ctx.material_pieces.has(int(w["big_stone"])) else 0}
		"bauen":
			opts = {"site": int(w["site"]), "target": int(w["big_stone"]) if life.ctx.material_pieces.has(int(w["big_stone"])) else 0}
		"schmelzen":
			var pieces: Array = []
			for k in ["copper2"]:
				if life.ctx.material_pieces.has(int(w[k])):
					pieces.append(int(w[k]))
			opts = {"crucible": int(w["crucible"]), "heater": int(w["heater"]), "mold": int(w["mold"]), "pieces": pieces,
				"target": int(w["copper1"]) if life.ctx.material_pieces.has(int(w["copper1"])) else 0}
		_:
			return {"ok": false, "message": "Unbekanntes Ziel %s." % goal}
	return life.ctx.work.trigger(cr, goal, opts, life.ctx, SOURCE)


## Fehlerfälle gezielt herstellen und auslösen. Rückgabe {ok, message} (ok = Fall wurde eingerichtet).
static func trigger_case(life: LifeSimulation, case: String) -> Dictionary:
	var w: Dictionary = life.workshop
	var ctx := life.ctx
	var cr := actor(life)
	if cr == null:
		return {"ok": false, "message": "Testwesen fehlt."}
	match case:
		"material":
			# Testeingriff: Fasern aus der Welt nehmen (wie Göttermenü) – ohne Bindematerial kein Hammer
			if ctx.material_pieces.has(int(w["fiber"])) and (ctx.material_pieces[int(w["fiber"])] as MaterialPiece).assembly_id == 0:
				ConstructionSystem.remove_piece(ctx, int(w["fiber"]))
				(cr.tech.get("objects", {}) as Dictionary).erase(int(w["fiber"]))
				ctx.log_event("work_case", [cr.id], {"case": "fehlendes Material", "removed": int(w["fiber"])}, "warning")
			var r := trigger(life, "lagern")
			return {"ok": true, "message": "Fasern entfernt. Auslösen: %s" % str(r.get("message", "")), "started": r.get("ok", false)}
		"weg":
			var n := wall_around(life, ctx.storages[int(w["storage"])].position, 0.5)
			var r2 := trigger(life, "lagern")
			return {"ok": true, "message": "Lager ummauert (%d Voxel). Auslösen: %s" % [n, str(r2.get("message", ""))]}
		"arm":
			var rr := life.dev_body_change(cr.id, "remove_forearm", "r")
			var r3 := trigger(life, "bauen")
			return {"ok": true, "message": "Rechter Unterarm: %s Auslösen: %s" % [str(rr.get("message", "")), str(r3.get("message", ""))]}
		"schwer":
			# Der sehr schwere Block soll eingelagert werden: Das Wesen geht hin, prüft das Anheben und lässt ihn liegen
			var hb := int(w["heavy_block"])
			var chk := ToolUseSystem.check_carry(ctx, cr, hb)
			var r7 := ctx.work.trigger(cr, "lagern", {"storage": int(w["storage"]), "pieces": [hb]}, ctx, SOURCE)
			return {"ok": true, "message": "Block #%d (%.1f kg) soll getragen werden – Tragprüfung: %s. Auslösen: %s" % [hb, ConstructionSystem.mass_of(ctx, hb), str(chk["message"]), str(r7.get("message", ""))],
				"code": str(chk["code"])}
		"unterbrechen":
			var wc0 := ctx.work.active(cr)
			if wc0 == null:
				var r4 := trigger(life, "lagern")
				if not r4.get("ok", false):
					return {"ok": false, "message": str(r4.get("message", ""))}
			ctx.executor.cancel(cr.id, "interrupted", "Unterbrechung (Testszene)")
			ctx.work.pause(cr, "gezielt unterbrochen (Testszene)", ctx)
			return {"ok": true, "message": "Kette #%d unterbrochen; sie wird beim nächsten Schritt fortgesetzt." % ctx.work.active(cr).id}
		"ungeeignet":
			# Holz (brennbar, Verbrennung nicht simuliert) und Kupfer angeboten: Holz wird abgewiesen, Kupfer geschmolzen
			var offer: Array = [int(w["wood_scrap"])]
			if ctx.material_pieces.has(int(w["copper2"])):
				offer.append(int(w["copper2"]))
			var r5 := ctx.work.trigger(cr, "schmelzen", {"crucible": int(w["crucible"]), "heater": int(w["heater"]), "mold": int(w["mold"]), "pieces": offer}, ctx, SOURCE)
			return {"ok": true, "message": "Holzstück und Kupfer als Schmelzgut angeboten. Auslösen: %s" % str(r5.get("message", ""))}
		"ohne_ofen":
			var hid := int(w["heater"])
			if ctx.heaters.has(hid):
				ctx.sim.thermal.remove_heater((ctx.heaters[hid] as TestHeater).heater_name())
				ctx.heaters.erase(hid)
				ctx.sim.remove_object(hid)
				(cr.tech.get("objects", {}) as Dictionary).erase(hid)
			var r6 := ctx.work.trigger(cr, "schmelzen", {"crucible": int(w["crucible"]), "heater": hid, "mold": int(w["mold"]), "pieces": [int(w["copper2"])]}, ctx, SOURCE)
			return {"ok": true, "message": "Testofen entfernt. Auslösen: %s" % str(r6.get("message", ""))}
	return {"ok": false, "message": "Unbekannter Fall %s." % case}


## Mauer (Stein, 4 Voxel hoch) als Ring um pos. Rückgabe: gesetzte Voxel.
static func wall_around(life: LifeSimulation, pos: Vector3, radius: float) -> int:
	var nav := life.ctx.nav
	var stone := life.world.palette.id_of("stone")
	var n := 0
	var c0 := nav.world_to_col(pos)
	var cell := maxf(0.05, nav.col_center(c0 + Vector2i(1, 0)).x - nav.col_center(c0).x)
	var rc := int(ceil(radius / cell))
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			if maxi(absi(dx), absi(dz)) != rc:
				continue
			var cc := c0 + Vector2i(dx, dz)
			if not nav.in_bounds(cc):
				continue
			var top := int(nav.ground[cc.x + nav.w * cc.y])
			for hh in 4:
				if life.world.set_voxel(Vector3i(cc.x, top + hh, cc.y), stone)["ok"]:
					n += 1
	return n
