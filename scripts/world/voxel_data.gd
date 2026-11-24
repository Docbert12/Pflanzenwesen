class_name VoxelData
extends RefCounted
## Simulationsdaten des Terrains: ein dichtes Gitter aus Byte-Typen.
## Reine Daten – keine Darstellung, keine Kollision.

var size: Vector3i
var cell_size: float = 0.5
var cells := PackedByteArray()


func _init(p_size: Vector3i = Vector3i(1, 1, 1), p_cell: float = 0.5) -> void:
	size = p_size
	cell_size = p_cell
	cells.resize(size.x * size.y * size.z)
	cells.fill(0)


func idx(x: int, y: int, z: int) -> int:
	return x + size.x * (y + size.y * z)


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z


func get_cell(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 0
	return cells[x + size.x * (y + size.y * z)]


func set_cell(x: int, y: int, z: int, t: int) -> void:
	cells[x + size.x * (y + size.y * z)] = t


## Höchste feste Zelle + 1 in der Spalte (0 = keine).
func column_top(x: int, z: int, solid: PackedByteArray) -> int:
	for y in range(size.y - 1, -1, -1):
		if solid[cells[x + size.x * (y + size.y * z)]] == 1:
			return y + 1
	return 0


func hash_sha256() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(cells)
	return ctx.finish().hex_encode()


func count_by_type() -> Dictionary:
	var c := {}
	for t in cells:
		c[t] = c.get(t, 0) + 1
	return c


## Masse je Physikmaterial [kg] = Zellanzahl · Zellvolumen · Dichte.
func mass_by_material(palette: VoxelPalette, materials: MaterialRegistry) -> Dictionary:
	var vol := cell_size * cell_size * cell_size
	var res := {}
	var counts := count_by_type()
	for t in counts:
		if palette.solid[t] != 1:
			continue
		var mid := palette.material_of(t)
		res[mid] = res.get(mid, 0.0) + counts[t] * vol * materials.get_material(mid).density
	return res


func world_to_cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / cell_size), floori(p.y / cell_size), floori(p.z / cell_size))


func cell_center(c: Vector3i) -> Vector3:
	return (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * cell_size
