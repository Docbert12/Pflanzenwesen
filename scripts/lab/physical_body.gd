class_name PhysicalBody
extends RigidBody3D
## Darstellung und Godot-Körperphysik eines PhysicalObject.
## Liest den physikalischen Zustand nur – Masse, Energie und Phase werden
## ausschließlich im PhysicalObject geführt (eine Quelle der Wahrheit).
## Proben in Behältern (Tiegel, Becherglas) sind eingefroren: Flüssigkeit wird
## als ruhende Schicht gezeigt, freie Strömung wird NICHT vorgetäuscht.

var object_id: int = 0
var sim: Simulation
var contained: bool = false
var container_inner: Vector2 = Vector2(0.06, 0.06)
var fall_release_time: float = -1.0
var fall_time_s: float = -1.0

var _solid_mesh: MeshInstance3D
var _liquid_mesh: MeshInstance3D
var _shape: CollisionShape3D
var _mat_solid: StandardMaterial3D
var _mat_liquid: StandardMaterial3D
var _edge: float = 0.1
var _pick_radius: float = 0.1
var _pick_center_local: Vector3 = Vector3.ZERO


func setup(p_sim: Simulation, obj: PhysicalObject, p_contained: bool, inner: Vector2) -> void:
	sim = p_sim
	object_id = obj.id
	contained = p_contained
	container_inner = inner
	name = "Objekt_%d" % obj.id
	_edge = obj.cube_edge_m()
	mass = obj.mass_kg  # Masse aus dem physikalischen Zustand übernehmen
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.05
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * _edge
	_shape.shape = box
	add_child(_shape)
	_solid_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_solid_mesh.mesh = bm
	_mat_solid = StandardMaterial3D.new()
	_mat_solid.roughness = 0.6
	_solid_mesh.material_override = _mat_solid
	add_child(_solid_mesh)
	_liquid_mesh = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3.ONE
	_liquid_mesh.mesh = lm
	_mat_liquid = StandardMaterial3D.new()
	_mat_liquid.roughness = 0.15
	_liquid_mesh.material_override = _mat_liquid
	add_child(_liquid_mesh)
	if contained:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	refresh_visual(false, false, false)


func set_frozen_for_test(frozen: bool) -> void:
	if contained:
		return
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = frozen


func refresh_visual(false_color: bool, is_selected: bool, is_secondary: bool) -> void:
	var obj: PhysicalObject = sim.registry.get_entity(object_id) as PhysicalObject
	if obj == null:
		return
	if not is_equal_approx(mass, obj.mass_kg):
		mass = obj.mass_kg
	var mat := obj.material()
	var lf := obj.liquid_fraction()
	var temp := obj.temperature_k()
	var base := mat.color
	if false_color:
		base = PhysicsLab.temperature_color(temp)
	base = base.darkened(obj.damage * 0.35)
	_mat_solid.albedo_color = base
	var liquid_col := PhysicsLab.temperature_color(temp) if false_color else mat.liquid_color
	_mat_liquid.albedo_color = liquid_col
	if mat.id == "water":
		_mat_liquid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_liquid.albedo_color.a = 0.65
		if lf <= 0.0 and not false_color:
			_mat_solid.albedo_color = Color(0.82, 0.92, 1.0)  # Eis
	_mat_liquid.emission_enabled = mat.id == "copper" and lf > 0.0 and not false_color
	_mat_liquid.emission = mat.liquid_color
	_mat_liquid.emission_energy_multiplier = 1.5
	var highlight := Color(1, 1, 0.3) if is_selected else (Color(0.3, 0.9, 1.0) if is_secondary else Color.BLACK)
	_mat_solid.emission_enabled = is_selected or is_secondary
	_mat_solid.emission = highlight
	_mat_solid.emission_energy_multiplier = 0.35

	var vol := obj.volume_m3()
	if contained:
		var solid_edge := pow(vol * (1.0 - lf), 1.0 / 3.0) if lf < 1.0 else 0.0
		var area := container_inner.x * container_inner.y
		var liquid_h := vol * lf / area
		_solid_mesh.visible = solid_edge > 0.0005
		_solid_mesh.scale = Vector3.ONE * maxf(solid_edge, 0.0001)
		_solid_mesh.position = Vector3(0, liquid_h + solid_edge * 0.5 if lf > 0.0 and solid_edge > 0.0 else solid_edge * 0.5, 0)
		# Ungeschmolzener Rest sinkt im Modell nicht ein; er wird auf der Schmelze gezeigt,
		# weil Dichteunterschiede und Strömung nicht modelliert sind.
		_liquid_mesh.visible = liquid_h > 0.0001
		_liquid_mesh.scale = Vector3(container_inner.x, maxf(liquid_h, 0.0001), container_inner.y)
		_liquid_mesh.position = Vector3(0, liquid_h * 0.5, 0)
		var top := maxf(liquid_h, 0.0) + solid_edge
		_pick_center_local = Vector3(0, top * 0.5, 0)
		_pick_radius = maxf(maxf(container_inner.x, container_inner.y) * 0.6, top * 0.6)
		_shape.position = Vector3(0, maxf(top, 0.002) * 0.5, 0)
		(_shape.shape as BoxShape3D).size = Vector3(container_inner.x * 0.95, maxf(top, 0.002), container_inner.y * 0.95)
	else:
		_liquid_mesh.visible = false
		_solid_mesh.visible = true
		var e := pow(vol, 1.0 / 3.0)
		var sc := Vector3(1.15, 0.756, 1.15) if obj.deformed else Vector3.ONE  # volumentreue Stauchung
		_solid_mesh.scale = sc * e
		_solid_mesh.position = Vector3.ZERO
		(_shape.shape as BoxShape3D).size = sc * e
		_shape.position = Vector3.ZERO
		_pick_center_local = Vector3.ZERO
		_pick_radius = e * 0.8


## Schnitt eines Strahls mit der Auswahlkugel. Rückgabe: Abstand oder -1.
func ray_hit_distance(origin: Vector3, direction: Vector3) -> float:
	var c := global_transform * _pick_center_local
	var oc := origin - c
	var b := oc.dot(direction)
	var cc := oc.dot(oc) - _pick_radius * _pick_radius
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t if t > 0.0 else -1.0


func label_anchor() -> Vector3:
	return global_transform * _pick_center_local
