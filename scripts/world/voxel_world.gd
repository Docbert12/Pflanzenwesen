class_name VoxelWorld
extends Node3D
## Verwaltet Terrain (VoxelData + Chunks), Wasser und abgetrennte Bruchstücke.
## Simulationsdaten (VoxelData, WaterSystem, PhysicalObjects der Bruchstücke) sind von
## Darstellung (Chunk-Netze, Wassernetz) und Kollision (Chunk-Körper) getrennt.

signal terrain_changed(cell: Vector3i)

var sim: Simulation
var cfg: Dictionary
var palette := VoxelPalette.new()
var data: VoxelData
var water := WaterSystem.new()
var support := SupportSystem.new()
var world_seed: int = 0
var generated: Dictionary = {}
var chunks: Dictionary = {}        # Vector3i -> VoxelChunk
var chunk_dims: Vector3i
var dirty: Dictionary = {}         # Vector3i -> true
var fragments: Array = []          # {body, object_ids, cells}
var max_fragments: int = 6
var errors: Array = []
var total_rebuilds: int = 0

var _water_mesh: MeshInstance3D
var _water_dirty := true
var _water_accum := 0.0
var _water_tick := 0.1
var _water_redraw_accum := 0.0
var _fragment_root: Node3D


func setup(p_sim: Simulation, p_cfg: Dictionary, palette_cfg: Dictionary) -> bool:
	sim = p_sim
	cfg = p_cfg
	errors.clear()
	if not palette.load_config(palette_cfg, sim.materials):
		errors.append_array(palette.errors)
		return false
	var cd: Array = cfg["chunk_size_cells"]
	chunk_dims = Vector3i(int(cd[0]), int(cd[1]), int(cd[2]))
	var sup: Dictionary = cfg.get("support", {})
	support.max_fragment_cells = int(sup.get("max_fragment_cells", 256))
	max_fragments = int(sup.get("max_dynamic_fragments", 6))
	var wc: Dictionary = cfg.get("water", {})
	_water_tick = float(wc.get("tick_s", 0.1))
	process_physics_priority = 10
	_water_mesh = MeshInstance3D.new()
	_water_mesh.name = "Wasser"
	_water_mesh.material_override = MaterialVisuals.vertex_color_material(true)
	add_child(_water_mesh)
	_fragment_root = Node3D.new()
	_fragment_root.name = "Bruchstücke"
	add_child(_fragment_root)
	return true


## Erzeugt die Welt aus dem Startwert (auch zum Zurücksetzen).
func generate(p_seed: int) -> void:
	clear_fragments()
	world_seed = p_seed
	generated = WorldGenerator.generate(cfg, palette, world_seed)
	data = generated["data"]
	water.setup(data, palette, generated["water"], float(cfg.get("water", {}).get("flow_rate_per_s", 2.0)))
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	dirty.clear()
	var nx := int(ceil(float(data.size.x) / chunk_dims.x))
	var ny := int(ceil(float(data.size.y) / chunk_dims.y))
	var nz := int(ceil(float(data.size.z) / chunk_dims.z))
	for cz in nz:
		for cy in ny:
			for cx in nx:
				var ch := VoxelChunk.new()
				ch.setup(Vector3i(cx, cy, cz), chunk_dims)
				add_child(ch)
				chunks[Vector3i(cx, cy, cz)] = ch
				dirty[Vector3i(cx, cy, cz)] = true
	flush_rebuilds()
	_water_dirty = true
	_redraw_water()
	sim.event_log.add("world_generated", [], {"seed": world_seed, "size": [data.size.x, data.size.y, data.size.z], "cell_m": data.cell_size, "hash": data.hash_sha256().substr(0, 12)})


func chunk_of(c: Vector3i) -> Vector3i:
	return Vector3i(floori(float(c.x) / chunk_dims.x), floori(float(c.y) / chunk_dims.y), floori(float(c.z) / chunk_dims.z))


func _mark_dirty_around(c: Vector3i) -> void:
	var k := chunk_of(c)
	dirty[k] = true
	# Nachbarchunks, wenn die Zelle an einer Chunkgrenze liegt
	var local := c - Vector3i(k.x * chunk_dims.x, k.y * chunk_dims.y, k.z * chunk_dims.z)
	for axis in 3:
		if local[axis] == 0:
			var n := k
			n[axis] -= 1
			if chunks.has(n):
				dirty[n] = true
		if local[axis] == chunk_dims[axis] - 1:
			var n2 := k
			n2[axis] += 1
			if chunks.has(n2):
				dirty[n2] = true


## Baut veränderte Chunks neu. max_count < 0: alle.
func flush_rebuilds(max_count: int = -1) -> int:
	var done := 0
	for k in dirty.keys():
		if max_count >= 0 and done >= max_count:
			break
		chunks[k].rebuild(data, palette)
		dirty.erase(k)
		done += 1
		total_rebuilds += 1
	return done


## Setzt eine Zelle (Weltbearbeitung). Gibt {"ok", "message", "detached": int} zurück.
func set_voxel(c: Vector3i, t: int) -> Dictionary:
	if not data.in_bounds(c.x, c.y, c.z):
		return {"ok": false, "message": "Außerhalb der Welt."}
	var old := data.get_cell(c.x, c.y, c.z)
	if old == t:
		return {"ok": false, "message": "Keine Änderung."}
	if old != 0 and not palette.is_editable(old):
		return {"ok": false, "message": "%s ist nicht veränderbar (verankert)." % palette.display_name(old)}
	if t != 0 and (palette.solid[t] != 1 or not palette.is_editable(t)):
		return {"ok": false, "message": "Typ %d kann nicht gesetzt werden." % t}
	data.set_cell(c.x, c.y, c.z, t)
	_mark_dirty_around(c)
	water.update_column(data, palette, c.x, c.z)
	_water_dirty = true
	sim.event_log.add("voxel_changed", [], {"cell": [c.x, c.y, c.z], "from": palette.display_name(old), "to": palette.display_name(t)})
	var detached := 0
	var large_kept := 0
	if t == 0:
		for comp in support.check_after_removal(data, palette, c):
			if comp["status"] == "too_large":
				# Suche hat das Limit erreicht, ohne Verankerung zu finden: Verband gilt als gestützt.
				# Das ist meist zusammenhängendes Terrain; echte große Überhänge bleiben im Modell ebenfalls stehen.
				large_kept += 1
				continue
			if fragments.size() >= max_fragments:
				sim.event_log.add("fragment_limit_reached", [], {"cells": comp["cells"].size(), "limit": max_fragments, "reason": "Verband bleibt als Terrain stehen"}, "warning")
				continue
			_detach(comp["cells"])
			detached += 1
	terrain_changed.emit(c)
	return {"ok": true, "message": "", "detached": detached, "large_kept": large_kept}


## Trennt einen Verband ab: Zellen werden aus dem Terrain entfernt und als EIN beweglicher
## Körper erzeugt. Die Masse wird je Material über PhysicalObjects (Dichte · Volumen) geführt.
func _detach(cells: Array) -> void:
	var lo := Vector3i(1048576, 1048576, 1048576)
	var hi := Vector3i(-1048576, -1048576, -1048576)
	for c in cells:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	var dims := hi - lo + Vector3i.ONE
	var grid := PackedByteArray()
	grid.resize(dims.x * dims.y * dims.z)
	var per_material := {}
	for c in cells:
		var t := data.get_cell(c.x, c.y, c.z)
		var l: Vector3i = c - lo
		grid[l.x + dims.x * (l.y + dims.y * l.z)] = t
		var mid := palette.material_of(t)
		per_material[mid] = per_material.get(mid, 0) + 1
		data.set_cell(c.x, c.y, c.z, 0)       # Terrainzelle entfernen → keine doppelte Materie
		_mark_dirty_around(c)
		water.update_column(data, palette, c.x, c.z)
	var vol_cell := data.cell_size * data.cell_size * data.cell_size
	var ids: Array = []
	var total_mass := 0.0
	for mid in per_material:
		var o := sim.create_object(mid, per_material[mid] * vol_cell, sim.thermal.ambient_temperature_k, "world", "Bruchstück (%s, %d Zellen)" % [mid, per_material[mid]])
		if o != null:
			ids.append(o.id)
			total_mass += o.mass_kg
	var body := RigidBody3D.new()
	body.name = "Bruchstueck_%d" % (ids[0] if ids.size() > 0 else 0)
	body.mass = total_mass
	body.set_meta("object_ids", ids)
	var r := VoxelMesher.build(dims, grid, palette.colors, data.cell_size, Vector3.ZERO, palette.solid, palette.collide, Callable(), 0.06)
	var mi := MeshInstance3D.new()
	mi.mesh = r["mesh"]
	mi.material_override = MaterialVisuals.vertex_color_material()
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = _unique_points(r["collision"])   # konvexe Hülle (Näherung, dokumentiert)
	cs.shape = shape
	body.add_child(cs)
	_fragment_root.add_child(body)
	if body.is_inside_tree():
		body.global_position = Vector3(lo) * data.cell_size
	else:
		body.position = Vector3(lo) * data.cell_size   # Welt ohne Szenenbaum (Tests): Ursprung der Welt = 0
	fragments.append({"body": body, "object_ids": ids, "cells": cells.size(), "mass_kg": total_mass})
	sim.event_log.add("terrain_fragment_detached", ids, {"cells": cells.size(), "mass_kg": total_mass, "materials": per_material.keys()})


static func _unique_points(tris: PackedVector3Array) -> PackedVector3Array:
	var seen := {}
	var out := PackedVector3Array()
	for p in tris:
		if not seen.has(p):
			seen[p] = true
			out.append(p)
	return out


func clear_fragments() -> void:
	for f in fragments:
		for id in f["object_ids"]:
			if sim != null:
				sim.remove_object(id)
		if is_instance_valid(f["body"]):
			f["body"].queue_free()
	fragments.clear()


## Massenbilanz: Terrain (aus Zellen) + Bruchstücke (aus PhysicalObjects).
func mass_summary() -> Dictionary:
	var terrain: Dictionary = data.mass_by_material(palette, sim.materials)
	var t_total := 0.0
	for m in terrain.values():
		t_total += m
	var f_total := 0.0
	for f in fragments:
		for id in f["object_ids"]:
			var o := sim.registry.get_entity(id) as PhysicalObject
			if o != null:
				f_total += o.mass_kg
	var water_mass := water.total() * sim.materials.get_material("water").density
	return {"terrain_kg": t_total, "fragments_kg": f_total, "solid_total_kg": t_total + f_total, "by_material": terrain, "water_m3": water.total(), "water_kg": water_mass}


## Voxel-Strahlverfolgung (Amanatides & Woo) direkt auf den Daten.
## Rückgabe: {"hit": bool, "cell": Vector3i, "normal": Vector3i, "distance": float}
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 200.0) -> Dictionary:
	var cs := data.cell_size
	var p := origin / cs
	var dirn := dir.normalized()
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var step := Vector3i(int(signf(dirn.x)), int(signf(dirn.y)), int(signf(dirn.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if dirn[a] == 0.0:
			t_max[a] = INF
			t_delta[a] = INF
		else:
			var next_b := float(cell[a] + (1 if step[a] > 0 else 0))
			t_max[a] = (next_b - p[a]) / dirn[a]
			t_delta[a] = absf(1.0 / dirn[a])
	var normal := Vector3i.ZERO
	var t := 0.0
	var limit := max_dist / cs
	while t <= limit:
		if data.in_bounds(cell.x, cell.y, cell.z) and palette.solid[data.get_cell(cell.x, cell.y, cell.z)] == 1:
			return {"hit": true, "cell": cell, "normal": normal, "distance": t * cs}
		var a := 0
		if t_max.y < t_max[a]:
			a = 1
		if t_max.z < t_max[a]:
			a = 2
		t = t_max[a]
		t_max[a] += t_delta[a]
		cell[a] += step[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
		# Abbruch, wenn der Strahl die Welt endgültig verlassen hat
		if (cell[a] < -1 and step[a] < 0) or (cell[a] > data.size[a] and step[a] > 0):
			break
	return {"hit": false}


func _physics_process(delta: float) -> void:
	if data == null:
		return
	_water_accum += delta
	while _water_accum >= _water_tick:
		_water_accum -= _water_tick
		if water.step(_water_tick) > 1e-9:
			_water_dirty = true
	for f in fragments:
		var b: RigidBody3D = f["body"]
		if is_instance_valid(b) and not b.freeze and b.global_position.y < -20.0:
			b.freeze = true
			sim.event_log.add("fragment_left_world", f["object_ids"], {"note": "eingefroren; Masse bleibt registriert"}, "warning")


func _process(delta: float) -> void:
	if data == null:
		return
	flush_rebuilds(4)   # höchstens 4 Chunks pro Bild → keine Ruckler bei vielen Änderungen
	_water_redraw_accum += delta
	if _water_dirty and _water_redraw_accum >= 0.2:
		_water_redraw_accum = 0.0
		_redraw_water()


## Wasseroberfläche als ein Netz: Deckflächen je Spalte + Seitenflächen zu niedrigeren Nachbarn.
func _redraw_water() -> void:
	_water_dirty = false
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var cs := data.cell_size
	var min_d := float(cfg.get("water", {}).get("min_depth_m", 0.001))
	var col := Color(MaterialVisuals.color(sim.materials, "water"), 0.62)
	for z in water.d:
		for x in water.w:
			var i := x + water.w * z
			if water.depth_m(i) < min_d:
				continue
			var top := water.level_m(i)
			var gy := water.ground[i] * cs
			var x0 := x * cs
			var z0 := z * cs
			var a := Vector3(x0, top, z0)
			var b := Vector3(x0 + cs, top, z0)
			var c := Vector3(x0 + cs, top, z0 + cs)
			var dd := Vector3(x0, top, z0 + cs)
			verts.append_array([a, b, c, a, c, dd])
			cols.append_array([col, col, col, col, col, col])
			# Seiten zu Nachbarn mit niedrigerem Spiegel
			for nb in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = x + nb[0]
				var nz: int = z + nb[1]
				var low := gy
				if nx >= 0 and nz >= 0 and nx < water.w and nz < water.d:
					var j := nx + water.w * nz
					low = maxf(water.ground[j] * cs, water.level_m(j)) if water.depth_m(j) >= min_d else water.ground[j] * cs
				if low >= top - 1e-4:
					continue
				low = maxf(low, gy)
				var p0: Vector3
				var p1: Vector3
				if nb[0] == 1:
					p0 = Vector3(x0 + cs, 0, z0); p1 = Vector3(x0 + cs, 0, z0 + cs)
				elif nb[0] == -1:
					p0 = Vector3(x0, 0, z0 + cs); p1 = Vector3(x0, 0, z0)
				elif nb[1] == 1:
					p0 = Vector3(x0 + cs, 0, z0 + cs); p1 = Vector3(x0, 0, z0 + cs)
				else:
					p0 = Vector3(x0, 0, z0); p1 = Vector3(x0 + cs, 0, z0)
				var q0 := Vector3(p0.x, low, p0.z)
				var q1 := Vector3(p1.x, low, p1.z)
				var q2 := Vector3(p1.x, top, p1.z)
				var q3 := Vector3(p0.x, top, p0.z)
				verts.append_array([q0, q3, q2, q0, q2, q1])
				cols.append_array([col, col, col, col, col, col])
	if verts.is_empty():
		_water_mesh.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_water_mesh.mesh = m
