class_name TestWorld
extends RefCounted
## Prüfungen für Definitionen, Voxelwelt, Abstützung, Wasser, Baum- und Pflanzengeneratoren.

var results: Array = []
var notes: Array = []
var _free: Array = []


func run_all() -> Array:
	results.clear()
	notes.clear()
	var sim := Simulation.new()
	sim.initialize()
	_free.append(sim)
	var db := DefinitionDB.new()
	db.load_all()
	_test_definitions(db, sim)
	_test_palette_and_visuals(db, sim)
	_test_determinism(db, sim)
	_test_voxel_edit_and_chunks(db, sim)
	_test_chunk_boundaries(db, sim)
	_test_support(db, sim)
	_test_water_synthetic(db, sim)
	_test_water_world(db, sim)
	_test_tree_and_plants(db, sim)
	for o in _free:
		if is_instance_valid(o):
			o.free()
	_free.clear()
	return results


func _check(name: String, cond: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": cond, "detail": detail})


func _world(db: DefinitionDB, sim: Simulation, seed: int = 12345) -> VoxelWorld:
	var w := VoxelWorld.new()
	_free.append(w)
	w.setup(sim, db.config("world"), db.config("voxel_palette"))
	w.generate(seed)
	return w


func _test_definitions(db: DefinitionDB, sim: Simulation) -> void:
	_check("Definitionen: erzeugte JSON-Dateien geladen", db.errors.is_empty() and db.kinds().size() >= 20, "Arten: %d, Fehler: %s" % [db.kinds().size(), str(db.errors)])
	_check("Definitionen: KR002 Setzling 85 cm aus Excel", float(db.get_def("species", "KR002").get("size_cm", 0)) == 85.0)
	_check("Definitionen: Spielstatus stammt aus Konfiguration", db.game_status("species", "KR002") == "partial" and db.game_status("species", "KR050") == "data_only")
	_check("Definitionen: Excel-Farbe F006 Pilzrot", db.palette_color("F006").to_html(false) == "e53935")
	var cat := db.get_def("material_catalog", "MAT111")
	_check("Definitionen: Excel-Material nur Designdaten mit Physikzuordnung", cat.get("physics_material_id") == "copper" and sim.materials.get_material("copper").density == 8960.0,
		"Excel-Dichte %s, Physik-Dichte 8960" % str(cat.get("density_kg_m3")))
	_check("Materialien: Erde (soil) geladen und validiert", sim.materials.has_material("soil") and sim.materials.ids().size() == 8)


func _test_palette_and_visuals(db: DefinitionDB, sim: Simulation) -> void:
	var pal := VoxelPalette.new()
	_check("Voxelpalette gültig", pal.load_config(db.config("voxel_palette"), sim.materials), str(pal.errors))
	var bad: Dictionary = db.config("voxel_palette").duplicate(true)
	bad["types"][1]["material_id"] = "lava"
	var pal2 := VoxelPalette.new()
	_check("Voxelpalette: unbekanntes Material abgewiesen", not pal2.load_config(bad, sim.materials) and str(pal2.errors).find("lava") >= 0)
	var r := MaterialVisuals.resolve(sim.materials, "soil", "bark")
	_check("Darstellung kann kein fremdes Material vortäuschen (Erde ≠ Rinde)", not r["ok"])
	_check("Darstellungsvariante passend zum Material erlaubt", MaterialVisuals.resolve(sim.materials, "soil", "grass")["ok"])


func _test_determinism(db: DefinitionDB, sim: Simulation) -> void:
	var a := _world(db, sim, 12345)
	var b := _world(db, sim, 12345)
	var c := _world(db, sim, 999)
	_check("Gleicher Startwert → identische Terraindaten", a.data.hash_sha256() == b.data.hash_sha256(), a.data.hash_sha256().substr(0, 16))
	_check("Gleicher Startwert → identische Wassermengen und Pflanzenorte", a.generated["water"] == b.generated["water"] and str(a.generated["plant_spots"]) == str(b.generated["plant_spots"]))
	_check("Anderer Startwert → andere Terraindaten", a.data.hash_sha256() != c.data.hash_sha256())
	var size := a.data.size
	notes.append("Welt: %d×%d×%d Zellen à %.2f m, Chunks %s, Startwert 12345 → SHA-256 %s…" % [size.x, size.y, size.z, a.data.cell_size, str(a.chunk_dims), a.data.hash_sha256().substr(0, 16)])
	var t0 := Time.get_ticks_msec()
	_world(db, sim, 4242)
	notes.append("Weltgenerierung inkl. Netz und Kollision aller 16 Chunks: %d ms" % (Time.get_ticks_msec() - t0))


func _test_voxel_edit_and_chunks(db: DefinitionDB, sim: Simulation) -> void:
	var w := _world(db, sim)
	var x := 8
	var z := 8
	var top := w.data.column_top(x, z, w.palette.solid)
	var counts := {}
	for k in w.chunks:
		counts[k] = w.chunks[k].rebuild_count
	var ch: VoxelChunk = w.chunks[Vector3i(0, 0, 0)]
	var faces_before := ch.face_count
	var r := w.set_voxel(Vector3i(x, top, z), w.palette.id_of("stone"))
	w.flush_rebuilds()
	var only_one := true
	for k in w.chunks:
		var expected: int = counts[k] + (1 if k == Vector3i(0, 0, 0) else 0)
		if w.chunks[k].rebuild_count != expected:
			only_one = false
	_check("Voxel hinzufügen: nur betroffener Chunk neu aufgebaut", r["ok"] and only_one)
	var sum := 0
	for k in w.chunks:
		sum += w.chunks[k].face_count
	var exposed := VoxelMesher.count_exposed_faces(w.data.size, w.data.cells, w.palette.solid, true)
	_check("Voxel hinzufügen: Geometrie und Kollision aktualisiert", ch.face_count != faces_before and ch.collision_triangles == ch.face_count * 2 and sum == exposed,
		"Flächen %d → %d, Kollisionsdreiecke %d, Welt %d/%d" % [faces_before, ch.face_count, ch.collision_triangles, sum, exposed])
	var r2 := w.set_voxel(Vector3i(x, top, z), 0)
	w.flush_rebuilds()
	_check("Voxel entfernen: Geometrie wieder wie vorher", r2["ok"] and ch.face_count == faces_before)
	var r3 := w.set_voxel(Vector3i(x, 0, z), 0)
	_check("Verankertes Grundgestein nicht entfernbar", not r3["ok"])
	var ray := w.raycast(Vector3((x + 0.5) * 0.5, 15.0, (z + 0.5) * 0.5), Vector3.DOWN)
	_check("Voxel-Strahl trifft Oberfläche", ray["hit"] and ray["cell"] == Vector3i(x, top - 1, z) and ray["normal"] == Vector3i(0, 1, 0), str(ray))


func _test_chunk_boundaries(db: DefinitionDB, sim: Simulation) -> void:
	var w := _world(db, sim)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var neighbor_rebuilt := false
	var c15: int = w.chunks[Vector3i(1, 0, 0)].rebuild_count
	var top := w.data.column_top(15, 5, w.palette.solid)
	w.set_voxel(Vector3i(15, top - 1, 5), 0)   # Zelle am Rand von Chunk (0,0,0)
	w.flush_rebuilds()
	neighbor_rebuilt = w.chunks[Vector3i(1, 0, 0)].rebuild_count == c15 + 1
	_check("Chunkgrenze: Nachbarchunk wird mit aktualisiert", neighbor_rebuilt)
	for i in 40:
		var bx: int = [15, 16, 31, 32, 47, 48][rng.randi_range(0, 5)]
		var bz := rng.randi_range(0, 63)
		if rng.randf() < 0.5:
			var tmp: int = bx
			bx = bz
			bz = tmp
		var t := w.data.column_top(bx, bz, w.palette.solid)
		if rng.randf() < 0.5 and t > 2:
			w.set_voxel(Vector3i(bx, t - 1, bz), 0)
		elif t < 30:
			w.set_voxel(Vector3i(bx, t, bz), w.palette.id_of("stone"))
	w.flush_rebuilds()
	var sum := 0
	for k in w.chunks:
		sum += w.chunks[k].face_count
	var expected := VoxelMesher.count_exposed_faces(w.data.size, w.data.cells, w.palette.solid, true)
	_check("Chunkgrenzen: keine fehlenden oder doppelten Flächen nach 40 Randänderungen", sum == expected, "Chunkflächen %d, erwartet %d" % [sum, expected])


func _total_solid_mass(w: VoxelWorld) -> float:
	return w.mass_summary()["solid_total_kg"]


func _test_support(db: DefinitionDB, sim: Simulation) -> void:
	var w := _world(db, sim)
	var soil := w.palette.id_of("soil")
	var x := 30
	var z := 30
	var h := w.data.column_top(x, z, w.palette.solid)
	for y in 3:
		w.set_voxel(Vector3i(x, h + y, z), soil)
	for dx in range(1, 4):
		w.set_voxel(Vector3i(x + dx, h + 2, z), soil)
	var cell_mass := 0.5 * 0.5 * 0.5 * sim.materials.get_material("soil").density
	var before := _total_solid_mass(w)
	var solid_before := _solid_count(w)
	var r := w.set_voxel(Vector3i(x, h + 1, z), 0)
	var after := _total_solid_mass(w)
	_check("Abstützung: nicht verankerter Verband löst sich als Bruchstück", r["detached"] == 1 and w.fragments.size() == 1 and w.fragments[0]["cells"] == 4)
	_check("Abstützung: Bruchstücke duplizieren keine Masse", absf(after - (before - cell_mass)) < 1e-6 and _solid_count(w) == solid_before - 5,
		"vorher %.3f kg, nachher %.3f kg (eine Zelle %.1f kg entfernt)" % [before, after, cell_mass])
	_check("Abstützung: Bruchstückmasse = Dichte · Volumen", absf(w.fragments[0]["mass_kg"] - 4 * cell_mass) < 1e-9 and (w.fragments[0]["body"] as RigidBody3D).mass == w.fragments[0]["mass_kg"])
	# Grenze: Höchstzahl gleichzeitiger Bruchstücke
	w.max_fragments = 1
	for dx in range(1, 3):
		w.set_voxel(Vector3i(x + 5 + dx, h + 2, z), soil)
	for y in 3:
		w.set_voxel(Vector3i(x + 5, h + y, z), soil)
	var count_before := _solid_count(w)
	var r2 := w.set_voxel(Vector3i(x + 5, h + 1, z), 0)
	_check("Abstützung: über der Höchstzahl bleibt der Verband als Terrain stehen", r2["detached"] == 0 and _solid_count(w) == count_before - 1 and sim.event_log.count_type("fragment_limit_reached") >= 1)
	# Grenze: Verbandsgröße
	w.max_fragments = 6
	w.support.max_fragment_cells = 2
	for dx in range(1, 4):
		w.set_voxel(Vector3i(x - 8 + dx, h + 2, z + 5), soil)
	for y in 3:
		w.set_voxel(Vector3i(x - 8, h + y, z + 5), soil)
	var r3 := w.set_voxel(Vector3i(x - 8, h + 1, z + 5), 0)
	_check("Abstützung: zu großer Verband (> Grenze) bleibt stehen", r3["detached"] == 0 and r3["large_kept"] >= 1)
	w.clear_fragments()


func _solid_count(w: VoxelWorld) -> int:
	var n := 0
	for t in w.data.cells:
		if w.palette.solid[t] == 1:
			n += 1
	return n


func _test_water_synthetic(db: DefinitionDB, sim: Simulation) -> void:
	var pal := VoxelPalette.new()
	pal.load_config(db.config("voxel_palette"), sim.materials)
	var stone := pal.id_of("stone")
	var d := VoxelData.new(Vector3i(9, 6, 1), 0.5)
	for x in 9:
		d.set_cell(x, 0, 0, stone)
	for y in range(1, 5):
		d.set_cell(4, y, 0, stone)   # Wand in der Mitte, Höhe 5 Zellen
	var init := PackedFloat64Array()
	init.resize(9)
	for x in 4:
		init[x] = 0.25 * 1.0    # Spaltenfläche 0,25 m² · 1 m Wassertiefe → Spiegel 1,5 m
	var ws := WaterSystem.new()
	ws.setup(d, pal, init, 2.0)
	var t0 := ws.total()
	var negative := false
	for i in 300:
		ws.step(0.1)
		for a in ws.amount:
			if a < -1e-15:
				negative = true
	var right := 0.0
	for x in range(5, 9):
		right += ws.amount[x]
	_check("Wasser: läuft nicht durch eine feste Wand", right == 0.0 and not negative)
	# Wand abtragen bis unter den Wasserspiegel
	for y in range(2, 5):
		d.set_cell(4, y, 0, 0)
	ws.update_column(d, pal, 4, 0)
	for i in 600:
		ws.step(0.1)
	right = 0.0
	for x in range(5, 9):
		right += ws.amount[x]
	_check("Wasser: fließt nach Untergrundänderung weiter", right > 0.0)
	_check("Wasser: Menge bleibt erhalten (rel. < 1e-12)", absf(ws.total() - t0) / t0 < 1e-12, "Abweichung %s m³" % TestSuite.sci(ws.total() - t0))
	var lvl_l := ws.level_m(0)
	var lvl_r := ws.level_m(8)
	_check("Wasser: Spiegel gleichen sich an", absf(lvl_l - lvl_r) < 0.01, "links %.4f m, rechts %.4f m" % [lvl_l, lvl_r])
	var before := ws.amount[0]
	d.set_cell(0, 1, 0, stone)
	ws.update_column(d, pal, 0, 0)
	_check("Wasser: Zelle unter Wasser hebt Spiegel, Menge bleibt", ws.amount[0] == before and ws.level_m(0) > lvl_l)


func _test_water_world(db: DefinitionDB, sim: Simulation) -> void:
	var w := _world(db, sim)
	var t0 := w.water.total()
	var lake: Array = w.cfg["lake"]["center"]
	# Kanal vom See graben → Wasser verteilt sich
	var lx := int(lake[0])
	var lz := int(lake[1])
	for dx in range(10, 18):
		var top := w.data.column_top(lx - dx, lz, w.palette.solid)
		for y in range(maxi(top - 4, 7), top):
			w.set_voxel(Vector3i(lx - dx, y, lz), 0)
	var moved := 0.0
	for i in 600:
		moved += w.water.step(0.1)
	var dev := absf(w.water.total() - t0) / t0
	_check("Wasser in der Welt: Erhaltung über 600 Schritte (rel. < 1e-12)", dev < 1e-12, "Gesamt %.6f m³, rel. Abweichung %s, bewegt %.3f m³" % [w.water.total(), TestSuite.sci(dev), moved])
	notes.append("Wasser (Startwert 12345): %.3f m³ = %.0f kg; nach Kanalgrabung 600 Schritte: rel. Abweichung %s" % [t0, t0 * 998.2, TestSuite.sci(dev)])


func _test_tree_and_plants(db: DefinitionDB, sim: Simulation) -> void:
	var p := {"height_m": 8.0, "voxel_size": 0.2}
	var t1 := TreeGenerator.generate(55, p)
	var t2 := TreeGenerator.generate(55, p)
	var t3 := TreeGenerator.generate(56, p)
	_check("Lebensbaum: gleicher Startwert → gleiches Modell", t1.cells == t2.cells and t1.cells != t3.cells)
	var counts := t1.count_by_type()
	_check("Lebensbaum: Stamm, Wurzeln und Laub vorhanden", counts.get(TreeGenerator.T_BARK, 0) > 0 and counts.get(TreeGenerator.T_ROOT, 0) > 0 and counts.get(TreeGenerator.T_LEAF, 0) > 0)
	var roots_below := 0
	for z in t1.dims.z:
		for y in 3:   # Zeilen unterhalb der Bodenhöhe (Modell: 3 Zellen unter dem Stammfuß)
			for x in t1.dims.x:
				if t1.get_v(x, y, z) == TreeGenerator.T_ROOT:
					roots_below += 1
	var m := t1.mass_by_material(sim.materials)
	_check("Lebensbaum: Wurzeln reichen teils in den Boden, Massen aus Physikmaterialien", roots_below > 0 and m.has("wood") and m.has("plant_tissue"),
		"Holz %.0f kg, Laub %.0f kg" % [m.get("wood", 0.0), m.get("plant_tissue", 0.0)])
	notes.append("Lebensbaum 8 m (0,2-m-Voxel): Holz %.0f kg, Laub %.0f kg (Laub-Füllanteil %.0f %%)" % [m.get("wood", 0.0), m.get("plant_tissue", 0.0), TreeGenerator.LEAF_FILL * 100])
	var ok := true
	for kind in PlantGenerator.KINDS:
		var a := PlantGenerator.generate(kind, 9, PlantGenerator.height_for(kind, db))
		var b := PlantGenerator.generate(kind, 9, PlantGenerator.height_for(kind, db))
		if a == null or a.cells != b.cells or a.count_by_type().is_empty():
			ok = false
	_check("Pflanzen/Pilze: alle 5 Arten deterministisch erzeugt", ok)
	_check("Pflanzenhöhe aus Excel (P007 Beerenstrauch 8 Voxel × 0,1 m)", is_equal_approx(PlantGenerator.height_for("bush", db), 0.8))
