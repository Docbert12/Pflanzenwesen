class_name VoxelModel
extends RefCounted
## Kleines Voxelmodell für Weltobjekte (Lebensbaum, Pflanzen, Pilze) und Körperteile.
## Typ-IDs sind modellintern (1..n); jede ID hat ein Physikmaterial und eine Darstellungsvariante.
## Simulationsdaten (Zellen, Material, Masse), Darstellung (Netz) und Kollision werden getrennt erzeugt.

var dims: Vector3i
var voxel_size: float
var origin: Vector3            # lokale Lage der Zelle (0,0,0) relativ zum Modellursprung
var cells := PackedByteArray()
var type_material: Dictionary = {}   # id -> material_id
var type_variant: Dictionary = {}    # id -> Darstellungsvariante
var type_color: Dictionary = {}      # id -> Color (optional, überschreibt Variante, nur Darstellung)
var collide_types: Dictionary = {}   # id -> true
## Füllanteil je Typ (Modellvolumen = Zellvolumen · Füllanteil). Laubkronen, Grashalme und
## Farnwedel füllen ihre Zellen nur zu einem kleinen Teil; ohne diesen Faktor wöge eine
## Baumkrone aus 0,2-m-Laubvoxeln zig Tonnen. Werte sind Spielannahmen (dokumentiert).
var fill_fraction: Dictionary = {}   # id -> float (Standard 1.0)


func _init(p_dims: Vector3i = Vector3i.ONE, p_voxel: float = 0.1, p_origin: Vector3 = Vector3.ZERO) -> void:
	dims = p_dims
	voxel_size = p_voxel
	origin = p_origin
	cells.resize(dims.x * dims.y * dims.z)
	cells.fill(0)


func define_type(id: int, material_id: String, variant: String, collides: bool, color_override = null, fill: float = 1.0) -> void:
	type_material[id] = material_id
	fill_fraction[id] = fill
	type_variant[id] = variant
	if collides:
		collide_types[id] = true
	if color_override != null:
		type_color[id] = color_override


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < dims.x and y < dims.y and z < dims.z


func set_v(x: int, y: int, z: int, t: int, only_empty: bool = false) -> void:
	if not in_bounds(x, y, z):
		return
	var i := x + dims.x * (y + dims.y * z)
	if only_empty and cells[i] != 0:
		return
	cells[i] = t


func get_v(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 0
	return cells[x + dims.x * (y + dims.y * z)]


## Kugel (in Zellkoordinaten, Mittelpunkt als float).
func fill_sphere(c: Vector3, r: float, t: int, only_empty: bool = false, keep: Callable = Callable()) -> void:
	for z in range(floori(c.z - r), ceili(c.z + r) + 1):
		for y in range(floori(c.y - r), ceili(c.y + r) + 1):
			for x in range(floori(c.x - r), ceili(c.x + r) + 1):
				if Vector3(x + 0.5, y + 0.5, z + 0.5).distance_to(c) <= r:
					if keep.is_valid() and not keep.call(x, y, z):
						continue
					set_v(x, y, z, t, only_empty)


## Dicke Linie (Zylinderabschnitte) von a nach b mit Radius r_a → r_b.
func fill_line(a: Vector3, b: Vector3, r_a: float, r_b: float, t: int, only_empty: bool = false) -> void:
	var length := a.distance_to(b)
	var n := maxi(1, ceili(length * 2.0))
	for i in n + 1:
		var f := float(i) / n
		fill_sphere(a.lerp(b, f), lerpf(r_a, r_b, f), t, only_empty)


func count_by_type() -> Dictionary:
	var c := {}
	for t in cells:
		if t != 0:
			c[t] = c.get(t, 0) + 1
	return c


## Modellvolumen je Material [m³] = Zellanzahl · Zellvolumen · Füllanteil.
func model_volume_by_material() -> Dictionary:
	var v := voxel_size * voxel_size * voxel_size
	var res := {}
	var counts := count_by_type()
	for t in counts:
		var mid: String = type_material[t]
		res[mid] = res.get(mid, 0.0) + counts[t] * v * float(fill_fraction.get(t, 1.0))
	return res


## Masse je Material [kg] = Modellvolumen · Dichte (Physikmaterial).
func mass_by_material(materials: MaterialRegistry) -> Dictionary:
	var res := {}
	var vols := model_volume_by_material()
	for mid in vols:
		res[mid] = vols[mid] * materials.get_material(mid).density
	return res


func total_mass(materials: MaterialRegistry) -> float:
	var s := 0.0
	for m in mass_by_material(materials).values():
		s += m
	return s


## Baut Netz (+ optional Kollision) als Node3D. Kollision nur für Typen in collide_types.
func build_node(materials: MaterialRegistry, node_name: String, with_collision: bool) -> Node3D:
	var colors := PackedColorArray()
	colors.resize(256)
	colors.fill(Color.MAGENTA)
	var solid := PackedByteArray()
	solid.resize(256)
	var collide := PackedByteArray()
	collide.resize(256)
	for t in type_material:
		colors[t] = type_color[t] if type_color.has(t) else MaterialVisuals.color(materials, type_material[t], type_variant.get(t, ""))
		solid[t] = 1
		collide[t] = 1 if collide_types.has(t) else 0
	var r := VoxelMesher.build(dims, cells, colors, voxel_size, origin, solid, collide, Callable(), 0.07)
	var root := Node3D.new()
	root.name = node_name
	var mi := MeshInstance3D.new()
	mi.name = "Netz"
	mi.mesh = r["mesh"]
	mi.material_override = MaterialVisuals.vertex_color_material()
	root.add_child(mi)
	root.set_meta("faces", r["faces"])
	if with_collision and r["collision"].size() > 0:
		var body := StaticBody3D.new()
		body.name = "Kollision"
		ChunkCollision.apply(body, r["collision"])
		root.add_child(body)
	return root
