class_name RegionStore
extends RefCounted
## Speicherabschnitt einer Region (Alpha 1.1, Speicherformat 6): Kartenvorlage, Startwert, Generator-
## version und NUR die Änderungen gegenüber dem Generator, je Chunk („Chunk-Deltas“), dazu Wasser und
## die Weltobjekte. Das Grundgelände wird beim Laden aus Startwert + Vorlage neu erzeugt und über
## base_hash kontrolliert. Grundlage für die gestreamte Welt (Alpha 1.2): dort werden nur geänderte
## Chunks je Region abgelegt.

const SECTION_VERSION := 1
const MAIN := "main"
const ENCODING := "i32-paare(lokaler Index, Typ)+deflate+base64"


static func chunk_key(k: Vector3i) -> String:
	return "%d,%d,%d" % [k.x, k.y, k.z]


static func parse_key(s: String) -> Vector3i:
	var p := s.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2])) if p.size() == 3 else Vector3i(-1, -1, -1)


static func encode_pairs(pairs: PackedInt32Array) -> Dictionary:
	var raw := pairs.to_byte_array()
	return {"n": pairs.size() / 2, "bytes": raw.size(), "data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))}


static func decode_pairs(d: Dictionary) -> PackedInt32Array:
	var comp := Marshalls.base64_to_raw(str(d.get("data", "")))
	var size := int(d.get("bytes", 0))
	if size <= 0 or comp.is_empty():
		return PackedInt32Array()
	return comp.decompress(size, FileAccess.COMPRESSION_DEFLATE).to_int32_array()


## Chunk-Deltas aus zwei gleich großen Zellfeldern. {"chunks": {key: {n, bytes, data}}, "changed": int}
static func deltas(base: PackedByteArray, cells: PackedByteArray, size: Vector3i, cd: Vector3i) -> Dictionary:
	var per := {}
	var changed := 0
	var sx := size.x
	var sxy := size.x * size.y
	for i in cells.size():
		if cells[i] == base[i]:
			continue
		changed += 1
		var z := i / sxy
		var y := (i - z * sxy) / sx
		var x := i - z * sxy - y * sx
		var k := Vector3i(x / cd.x, y / cd.y, z / cd.z)
		var li := (x - k.x * cd.x) + cd.x * ((y - k.y * cd.y) + cd.y * (z - k.z * cd.z))
		if not per.has(k):
			per[k] = PackedInt32Array()
		var arr: PackedInt32Array = per[k]
		arr.append(li)
		arr.append(cells[i])
		per[k] = arr
	var chunks := {}
	for k in per:
		chunks[chunk_key(k)] = encode_pairs(per[k])
	return {"chunks": chunks, "changed": changed}


## Wendet Chunk-Deltas auf ein Zellfeld an. {"ok", "message", "cells", "changed", "chunks": Array[Vector3i]}
static func apply_deltas(cells: PackedByteArray, chunks: Dictionary, size: Vector3i, cd: Vector3i) -> Dictionary:
	var changed := 0
	var touched: Array = []
	for key in chunks:
		var k := parse_key(str(key))
		if k.x < 0 or k.y < 0 or k.z < 0 or k.x * cd.x >= size.x or k.y * cd.y >= size.y or k.z * cd.z >= size.z:
			return {"ok": false, "message": "Chunk %s liegt außerhalb der Welt." % str(key)}
		var pairs := decode_pairs(chunks[key])
		if pairs.size() != int(chunks[key].get("n", -1)) * 2:
			return {"ok": false, "message": "Chunk %s: Änderungsdaten beschädigt." % str(key)}
		touched.append(k)
		for j in range(0, pairs.size(), 2):
			var li := pairs[j]
			var lz := li / (cd.x * cd.y)
			var ly := (li - lz * cd.x * cd.y) / cd.x
			var lx := li - lz * cd.x * cd.y - ly * cd.x
			var x := k.x * cd.x + lx
			var y := k.y * cd.y + ly
			var z := k.z * cd.z + lz
			if li < 0 or lz >= cd.z or x >= size.x or y >= size.y or z >= size.z or pairs[j + 1] < 0 or pairs[j + 1] > 255:
				return {"ok": false, "message": "Terrainänderung außerhalb der Welt."}
			cells[x + size.x * (y + size.y * z)] = pairs[j + 1]
			changed += 1
	return {"ok": true, "message": "", "cells": cells, "changed": changed, "chunks": touched}


## Format 5 → 6: Liste [[globaler Index, Typ], …] in Chunk-Deltas umrechnen (ohne Welt).
static func deltas_from_global(diff: Array, size: Vector3i, cd: Vector3i) -> Dictionary:
	var per := {}
	var sxy := size.x * size.y
	for e in diff:
		var i := int(e[0])
		if i < 0 or i >= sxy * size.z:
			return {"ok": false, "message": "Terrainänderung außerhalb der Welt."}
		var z := i / sxy
		var y := (i - z * sxy) / size.x
		var x := i - z * sxy - y * size.x
		var k := Vector3i(x / cd.x, y / cd.y, z / cd.z)
		if not per.has(k):
			per[k] = PackedInt32Array()
		var arr: PackedInt32Array = per[k]
		arr.append((x - k.x * cd.x) + cd.x * ((y - k.y * cd.y) + cd.y * (z - k.z * cd.z)))
		arr.append(int(e[1]))
		per[k] = arr
	var chunks := {}
	for k in per:
		chunks[chunk_key(k)] = encode_pairs(per[k])
	return {"ok": true, "chunks": chunks, "changed": diff.size()}


static func save(life) -> Dictionary:
	var w: VoxelWorld = life.world
	var dl := deltas(life.base_cells, w.data.cells, w.data.size, w.chunk_dims)
	return {"v": SECTION_VERSION, "map_id": life.map.id, "map_sha256": life.map.sha256, "seed": w.world_seed,
		"generator": life.map.generator, "generator_version": life.map.generator_version,
		"cell_size_m": w.data.cell_size, "size": [w.data.size.x, w.data.size.y, w.data.size.z],
		"chunk_size": [w.chunk_dims.x, w.chunk_dims.y, w.chunk_dims.z],
		"base_hash": life.base_hash, "current_hash": w.data.hash_sha256(),
		"delta_encoding": ENCODING, "changed_cells": int(dl["changed"]), "chunks": dl["chunks"],
		"water_b64": Marshalls.raw_to_base64(w.water.amount.to_byte_array()), "water_total_m3": w.water.total(),
		"fragments_not_saved": w.fragments.size(),
		"world_objects": {"entity_ids": life.world_object_ids.duplicate(),
			"tree": {"seed": life.tree_info.get("seed", 0), "height_m": life.tree_info.get("height_m", 0.0),
				"position": [life.tree_node.position.x, life.tree_node.position.y, life.tree_node.position.z],
				"root_bed_radius_m": life.tree_info.get("root_bed_radius_m", 0.0), "footprint_cols": life.footprint.size(),
				"state": "statisches Weltobjekt (kein Wachstum, kein Nachwuchs, kein Recycling in diesem Schritt)"}}}


## Baut die Welt aus Vorlage + Startwert und wendet die Änderungen an. {"ok", "code", "message"}
static func load_into(life, r: Dictionary) -> Dictionary:
	if int(r.get("v", 0)) != SECTION_VERSION:
		return {"ok": false, "code": "newer_format" if int(r.get("v", 0)) > SECTION_VERSION else "invalid", "message": "Regionsabschnitt hat Version %d, erwartet %d." % [int(r.get("v", 0)), SECTION_VERSION]}
	var map_id := str(r.get("map_id", MapTemplate.DEFAULT_ID))
	if not life.build_world(int(r["seed"]), map_id):
		return {"ok": false, "code": "world_mismatch", "message": "Kartenvorlage nicht ladbar: " + "; ".join(life.errors)}
	var w: VoxelWorld = life.world
	var sz: Array = r.get("size", [])
	if sz.size() != 3 or Vector3i(int(sz[0]), int(sz[1]), int(sz[2])) != w.data.size:
		return {"ok": false, "code": "world_mismatch", "message": "Kartengröße weicht ab (gespeichert %s, Vorlage %s)." % [str(sz), str(w.data.size)]}
	if life.base_hash != str(r["base_hash"]):
		return {"ok": false, "code": "world_mismatch", "message": "Das aus dem Startwert erzeugte Grundgelände weicht vom gespeicherten ab (Weltgenerator geändert)."}
	var saved_ids: Array = r.get("world_objects", {}).get("entity_ids", [])
	var cur_ids: Array = life.world_object_ids
	if saved_ids.size() != cur_ids.size():
		return {"ok": false, "code": "world_mismatch", "message": "Anzahl der Weltobjekte weicht ab (%d gespeichert, %d erzeugt)." % [saved_ids.size(), cur_ids.size()]}
	for i in saved_ids.size():
		if int(saved_ids[i]) != int(cur_ids[i]):
			return {"ok": false, "code": "world_mismatch", "message": "IDs der Weltobjekte weichen ab."}
	var cs: Array = r.get("chunk_size", [])
	var cd := Vector3i(int(cs[0]), int(cs[1]), int(cs[2])) if cs.size() == 3 else w.chunk_dims
	var chunks: Dictionary = r.get("chunks", {})
	if not chunks.is_empty():
		var ar := apply_deltas(w.data.cells, chunks, w.data.size, cd)
		if not ar["ok"]:
			return {"ok": false, "code": "invalid", "message": ar["message"]}
		w.data.cells = ar["cells"]
		w.mark_all_dirty()
		w.flush_rebuilds()
		life.ctx.nav.setup(w, life.ctx.cfg, life.footprint)
	if w.data.hash_sha256() != str(r.get("current_hash", w.data.hash_sha256())):
		return {"ok": false, "code": "invalid", "message": "Gelände nach Anwendung der Änderungen inkonsistent."}
	var water := Marshalls.base64_to_raw(str(r["water_b64"])).to_float64_array()
	if water.size() != w.water.amount.size():
		return {"ok": false, "code": "invalid", "message": "Wasserdaten haben falsche Größe."}
	w.restore_water(water)
	return {"ok": true, "code": "ok", "message": ""}
