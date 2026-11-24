class_name VoxelPalette
extends RefCounted
## Terrain-Voxeltypen aus data/config/voxel_palette.json (handgeschrieben, stabile Byte-IDs).
## Jeder feste Typ verweist auf ein Physikmaterial aus MaterialRegistry.

var types: Dictionary = {}          # id -> Dictionary
var solid := PackedByteArray()      # 256 Einträge
var collide := PackedByteArray()
var colors := PackedColorArray()
var errors: Array = []


func load_config(cfg: Dictionary, materials: MaterialRegistry) -> bool:
	errors.clear()
	types.clear()
	solid.resize(256)
	solid.fill(0)
	collide.resize(256)
	collide.fill(0)
	colors.resize(256)
	colors.fill(Color.MAGENTA)
	if typeof(cfg.get("types", null)) != TYPE_ARRAY:
		errors.append("voxel_palette.json: 'types' fehlt.")
		return false
	for t in cfg["types"]:
		var id := int(t.get("id", -1))
		if id < 0 or id > 255:
			errors.append("voxel_palette.json: ungültige ID %s." % str(t.get("id")))
			continue
		if types.has(id):
			errors.append("voxel_palette.json: doppelte ID %d." % id)
			continue
		var is_solid: bool = t.get("solid", false)
		if is_solid:
			var mid = t.get("material_id", null)
			if typeof(mid) != TYPE_STRING or not materials.has_material(mid):
				errors.append("voxel_palette.json: Typ %d (%s) verweist auf unbekanntes Material '%s'." % [id, t.get("key", "?"), str(mid)])
				continue
			var r := MaterialVisuals.resolve(materials, mid, str(t.get("visual", "")))
			if not r["ok"]:
				errors.append("voxel_palette.json: Typ %d: %s" % [id, r["error"]])
				continue
			colors[id] = r["color"]
			solid[id] = 1
			collide[id] = 1
		elif id != 0:
			errors.append("voxel_palette.json: nur ID 0 darf leer (nicht fest) sein.")
			continue
		types[id] = t
	if not types.has(0):
		errors.append("voxel_palette.json: Typ 0 (Luft) fehlt.")
	return errors.is_empty()


func id_of(key: String) -> int:
	for id in types:
		if types[id].get("key", "") == key:
			return id
	return -1


func material_of(id: int) -> String:
	return str(types.get(id, {}).get("material_id", ""))


func is_editable(id: int) -> bool:
	return bool(types.get(id, {}).get("editable", false))


func is_anchored(id: int) -> bool:
	return bool(types.get(id, {}).get("anchored", false))


func display_name(id: int) -> String:
	return str(types.get(id, {}).get("name", "?"))


func editable_solid_ids() -> Array:
	var r: Array = []
	for id in types:
		if solid[id] == 1 and is_editable(id):
			r.append(id)
	r.sort()
	return r
