class_name CreatureView
extends Node3D
## Darstellung eines Wesens: Gelenkhierarchie (Pivots) mit einem Voxelnetz je Körperteil
## und – getrennt davon – einfachen Kollisionsformen (Area3D + Quader je Teil).
## Nur wirksam vorhandene Teile (BodyPlan.is_present) erhalten Nodes. Eine entfernte Hand
## hat damit weder Netz noch Kollision noch Gelenk, das eine Animation bewegen könnte.

var plan: BodyPlan
var materials: MaterialRegistry
var voxel_size: float = 0.02
var pivots: Dictionary = {}          # part id -> Node3D (Gelenk)
var meshes: Dictionary = {}          # part id -> MeshInstance3D
var areas: Dictionary = {}           # part id -> Area3D
var geometric_volume: Dictionary = {} # part id -> m³ (Voxel)
var voxel_count: int = 0
var animator: CreatureAnimator
var hips: Node3D


func setup(p_plan: BodyPlan, p_materials: MaterialRegistry, p_voxel: float) -> void:
	plan = p_plan
	materials = p_materials
	voxel_size = p_voxel
	name = "Wesen_%d" % plan.plan_seed
	rebuild()


## Baut Gelenke, Netze und Kollisionen vollständig aus dem Körperplan neu auf.
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	pivots.clear()
	meshes.clear()
	areas.clear()
	geometric_volume.clear()
	voxel_count = 0
	hips = Node3D.new()
	hips.name = "Huefte"
	hips.position = Vector3(0, float(plan.genes.get("stand_height_m", 0.35)), 0)
	add_child(hips)
	var vc := MaterialVisuals.vertex_color_material()
	for pid in plan.present_ids():
		var p: Dictionary = plan.parts[pid]
		var pivot := Node3D.new()
		pivot.name = pid
		var parent_node: Node3D = hips if p["parent"] == "" else pivots.get(p["parent"], null)
		if parent_node == null:
			continue
		parent_node.add_child(pivot)
		pivot.position = Vector3(p["attach"][0], p["attach"][1], p["attach"][2])
		if p.has("rot"):
			pivot.rotation = Vector3(p["rot"][0], p["rot"][1], p["rot"][2])
		pivot.set_meta("rest_rotation", pivot.rotation)
		pivots[pid] = pivot
		var m := CreatureGenerator.part_mesh(p, plan.genes, materials, voxel_size)
		var mi := MeshInstance3D.new()
		mi.name = "Netz"
		mi.mesh = m["mesh"]
		mi.material_override = vc
		pivot.add_child(mi)
		meshes[pid] = mi
		geometric_volume[pid] = m["geometric_volume"]
		voxel_count += m["voxels"]
		# Kollision (getrennt von der Darstellung): Quader in Teilgröße
		var area := Area3D.new()
		area.name = "Kollision"
		area.collision_layer = 2
		area.collision_mask = 0
		area.monitoring = false
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(p["size"][0], p["size"][1], p["size"][2])
		cs.shape = box
		var cy: float = float(p["size"][1]) * (0.5 if p["extent"] == "up" else -0.5)
		cs.position = Vector3(0, cy, 0)
		area.add_child(cs)
		pivot.add_child(area)
		areas[pid] = area
	if animator == null:
		animator = CreatureAnimator.new()
	animator.bind(self)


func _process(delta: float) -> void:
	if animator != null:
		animator.update(delta)


## Lage eines Gelenks relativ zu dieser Ansicht (Produkt der lokalen Transformationen bis zur Ansicht).
## Funktioniert auch ohne Szenenbaum (Tests). Unbekanntes Gelenk → Identität.
func chain_transform(pid: String) -> Transform3D:
	if not pivots.has(pid):
		return Transform3D.IDENTITY
	var n: Node3D = pivots[pid]
	var t := Transform3D.IDENTITY
	while n != null and n != self:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


func standing_height() -> float:
	var top := 0.0
	if pivots.has("head"):
		top = (pivots["head"] as Node3D).position.y + float(plan.parts["head"]["size"][1]) + hips.position.y + float(plan.parts["torso"]["attach"][1])
	return top
