class_name VoxelChunk
extends Node3D
## Darstellung + Kollision eines Terrainabschnitts. Die Daten liegen in VoxelData.

var chunk_coord: Vector3i
var origin_cell: Vector3i
var dims: Vector3i
var mesh_instance: MeshInstance3D
var body: StaticBody3D
var rebuild_count: int = 0
var face_count: int = 0
var collision_triangles: int = 0


func setup(coord: Vector3i, p_dims: Vector3i) -> void:
	chunk_coord = coord
	dims = p_dims
	origin_cell = Vector3i(coord.x * dims.x, coord.y * dims.y, coord.z * dims.z)
	name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	mesh_instance = MeshInstance3D.new()
	mesh_instance.material_override = MaterialVisuals.vertex_color_material()
	add_child(mesh_instance)
	body = StaticBody3D.new()
	body.name = "Kollision"
	body.set_meta("terrain_chunk", true)
	add_child(body)


## Baut Netz und Kollision aus den Daten neu auf.
func rebuild(data: VoxelData, palette: VoxelPalette) -> void:
	var local := PackedByteArray()
	local.resize(dims.x * dims.y * dims.z)
	var ox := origin_cell.x
	var oy := origin_cell.y
	var oz := origin_cell.z
	for z in dims.z:
		for y in dims.y:
			var src := ox + data.size.x * ((oy + y) + data.size.y * (oz + z))
			var dst := dims.x * (y + dims.y * z)
			for x in dims.x:
				local[dst + x] = data.cells[src + x]
	var outside := func(x: int, y: int, z: int) -> int:
		return data.get_cell(ox + x, oy + y, oz + z)
	var cs := data.cell_size
	var r := VoxelMesher.build(dims, local, palette.colors, cs, Vector3(origin_cell) * cs,
		palette.solid, palette.collide, outside, 0.06, origin_cell.y == 0)
	mesh_instance.mesh = r["mesh"]
	face_count = r["faces"]
	collision_triangles = ChunkCollision.apply(body, r["collision"])
	rebuild_count += 1
