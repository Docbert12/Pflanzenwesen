class_name WorldAccess
extends RefCounted
## Einziger Zugriff auf das Gelände für alles außerhalb der Welt-Schicht (Alpha 1.1,
## docs/ROADMAP_ALPHA.md Abschnitt 8.4). Kein Teil des Spiels nimmt eine feste Kartengröße an:
## Größe und Zellgröße kommen von hier. Schreibweg ist allein set_material().
## Ab Alpha 1.2 liegt dahinter der gestreamte Chunk-Speicher; die Schnittstelle bleibt.

var world: VoxelWorld


func _init(p_world: VoxelWorld = null) -> void:
	world = p_world


func is_ready() -> bool:
	return world != null and is_instance_valid(world) and world.data != null


func size_cells() -> Vector3i:
	return world.data.size


func cell_size() -> float:
	return world.data.cell_size if is_ready() else 0.5


func size_m() -> Vector3:
	return Vector3(world.data.size) * world.data.cell_size


func world_seed() -> int:
	return world.world_seed


func in_bounds(c: Vector3i) -> bool:
	return world.data.in_bounds(c.x, c.y, c.z)


func column_in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < world.data.size.x and z < world.data.size.z


## Ab Alpha 1.2: false für nicht geladene Chunks. Bis dahin ist die ganze Karte geladen.
func is_loaded(c: Vector3i) -> bool:
	return in_bounds(c)


func world_to_cell(p: Vector3) -> Vector3i:
	return world.data.world_to_cell(p)


func cell_center(c: Vector3i) -> Vector3:
	return world.data.cell_center(c)


## Zelltyp (Index der Voxelpalette); 0 = Luft, auch außerhalb der Karte.
func type_at(c: Vector3i) -> int:
	return world.data.get_cell(c.x, c.y, c.z)


func type_id(type_name: String) -> int:
	return world.palette.id_of(type_name)


func type_name(t: int) -> String:
	return world.palette.display_name(t)


## Physikmaterial der Zelle ("" = Luft).
func material_at(c: Vector3i) -> String:
	var t := type_at(c)
	return world.palette.material_of(t) if t != 0 else ""


func is_solid(c: Vector3i) -> bool:
	return world.palette.solid[type_at(c)] == 1


func is_solid_at(p: Vector3) -> bool:
	return is_solid(world_to_cell(p))


## Höchste feste Zelle + 1 in der Spalte (0 = keine); außerhalb der Karte 0.
func surface_height(x: int, z: int) -> int:
	if not column_in_bounds(x, z):
		return 0
	return world.data.column_top(x, z, world.palette.solid)


func surface_y_m(x: int, z: int) -> float:
	return float(surface_height(x, z)) * world.data.cell_size


## Geländehöhe direkt nach der Erzeugung (Generator), unabhängig von späteren Änderungen.
func generated_height(x: int, z: int) -> int:
	if not column_in_bounds(x, z):
		return 0
	var h: PackedInt32Array = world.generated["heights"]
	return h[x + world.data.size.x * z]


func water_depth_m(x: int, z: int) -> float:
	if not column_in_bounds(x, z):
		return 0.0
	return world.water.depth_m(x + world.water.w * z)


func water_total_m3() -> float:
	return world.water.total()


func raycast(from: Vector3, dir: Vector3, max_dist: float = 200.0) -> Dictionary:
	return world.raycast(from, dir, max_dist)


## Einziger Schreibweg: setzt eine Zelle über die Weltbearbeitung (Netz, Wasser, Abstützung, Navigation,
## Ereignis). `cause` wird protokolliert. {"ok", "message", "detached", "large_kept"}
func set_material(c: Vector3i, t: int, cause: String = "") -> Dictionary:
	var r := world.set_voxel(c, t)
	if r.get("ok", false) and cause != "":
		world.sim.event_log.add("terrain_edit", [], {"cell": [c.x, c.y, c.z], "cause": cause})
	return r


func terrain_hash() -> String:
	return world.data.hash_sha256()
