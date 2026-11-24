class_name PlantGenerator
extends RefCounted
## Prozedurale Pflanzen und Pilze (Excel 07_Pflanzen_Bäume).
## Höhe = Basis_Höhe_Voxel × Excel-Voxel_Größe (0,1 m) × Zufallsfaktor 0,8–1,2.
## Pilzgewebe wird vorläufig als Pflanzengewebe modelliert (Annahme, dokumentiert).

const KINDS := {
	"bush": {"excel_id": "P007", "fallback_height_m": 0.8, "collision": true},
	"grass": {"excel_id": "P011", "fallback_height_m": 0.3, "collision": false},
	"fern": {"excel_id": "P013", "fallback_height_m": 1.0, "collision": false},
	"mushroom_red": {"excel_id": "P009", "fallback_height_m": 0.8, "collision": true},
	"mushroom_brown": {"excel_id": "P010", "fallback_height_m": 0.6, "collision": true},
}


static func height_for(kind: String, db: DefinitionDB) -> float:
	var info: Dictionary = KINDS[kind]
	var e := db.get_def("plants", info["excel_id"]) if db != null else {}
	var excel_voxel := db.generator_parameter("voxel_groesse", 0.1) if db != null else 0.1
	if not e.is_empty() and e.get("base_height_voxels") != null:
		return float(e["base_height_voxels"]) * excel_voxel
	return info["fallback_height_m"]


static func generate(kind: String, seed: int, height_m: float, voxel: float = 0.05) -> VoxelModel:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hc := maxi(4, int(round(height_m * rng.randf_range(0.8, 1.2) / voxel)))
	match kind:
		"bush":
			return _bush(rng, hc, voxel)
		"grass":
			return _grass(rng, hc, voxel)
		"fern":
			return _fern(rng, hc, voxel)
		"mushroom_red", "mushroom_brown":
			return _mushroom(rng, hc, voxel, kind == "mushroom_red")
	push_error("PlantGenerator: unbekannte Art " + kind)
	return null


static func _bush(rng: RandomNumberGenerator, hc: int, v: float) -> VoxelModel:
	var r := hc * 0.55
	var half := ceili(r) + 2
	var m := VoxelModel.new(Vector3i(half * 2 + 1, hc + 2, half * 2 + 1), v, Vector3(-(half + 0.5) * v, 0, -(half + 0.5) * v))
	m.define_type(1, "plant_tissue", "leaf", true, null, 0.08)
	m.define_type(2, "plant_tissue", "leaf_light", true, null, 0.08)
	m.define_type(3, "plant_tissue", "berry", true)
	m.define_type(4, "wood", "bark", true)
	var c := Vector3(half + 0.5, 0, half + 0.5)
	m.fill_line(c, c + Vector3(0, hc * 0.4, 0), 1.0, 0.7, 4)
	for i in 5:
		var off := Vector3(rng.randf_range(-r * 0.45, r * 0.45), hc * rng.randf_range(0.4, 0.62), rng.randf_range(-r * 0.45, r * 0.45))
		m.fill_sphere(c + off, r * rng.randf_range(0.5, 0.7), 1 if i % 2 == 0 else 2, true)
	# Beeren auf der Oberfläche
	for i in rng.randi_range(8, 14):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
		var p := c + Vector3(0, hc * 0.5, 0) + dir * r * 0.95
		m.set_v(int(p.x), int(p.y), int(p.z), 3)
	return m


static func _grass(rng: RandomNumberGenerator, hc: int, v: float) -> VoxelModel:
	var half := 4
	var m := VoxelModel.new(Vector3i(half * 2 + 1, hc + 1, half * 2 + 1), v, Vector3(-(half + 0.5) * v, 0, -(half + 0.5) * v))
	m.define_type(1, "plant_tissue", "leaf", false, null, 0.1)
	m.define_type(2, "plant_tissue", "leaf_light", false, null, 0.1)
	for i in rng.randi_range(7, 11):
		var x0 := half + rng.randi_range(-2, 2)
		var z0 := half + rng.randi_range(-2, 2)
		var lean := Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
		var blade_h := int(hc * rng.randf_range(0.6, 1.0))
		for y in blade_h:
			m.set_v(x0 + int(round(lean.x * y)), y, z0 + int(round(lean.y * y)), 1 if (i + y) % 3 else 2)
	return m


static func _fern(rng: RandomNumberGenerator, hc: int, v: float) -> VoxelModel:
	var reach := hc * 0.7
	var half := ceili(reach) + 1
	var m := VoxelModel.new(Vector3i(half * 2 + 1, hc + 1, half * 2 + 1), v, Vector3(-(half + 0.5) * v, 0, -(half + 0.5) * v))
	m.define_type(1, "plant_tissue", "leaf", false, null, 0.1)
	m.define_type(2, "plant_tissue", "plant", false, null, 0.3)
	var c := Vector3(half + 0.5, 0, half + 0.5)
	var n := rng.randi_range(6, 9)
	for i in n:
		var ang := TAU * float(i) / n + rng.randf_range(-0.2, 0.2)
		var steps := 14
		var prev := c
		for s in steps + 1:
			var f := float(s) / steps
			# Wedel: steigt auf, biegt nach außen ab
			var p := c + Vector3(cos(ang) * reach * f, hc * sin(f * PI * 0.62) * 0.95, sin(ang) * reach * f)
			m.fill_line(prev, p, 0.5, 0.5, 2)
			# Fiederblättchen
			if s % 2 == 0 and s > 1:
				var side := Vector3(-sin(ang), 0, cos(ang)) * (1.0 - f) * 3.0
				m.fill_line(p, p + side, 0.5, 0.5, 1, true)
				m.fill_line(p, p - side, 0.5, 0.5, 1, true)
			prev = p
	return m


static func _mushroom(rng: RandomNumberGenerator, hc: int, v: float, red: bool) -> VoxelModel:
	var cap_r := hc * rng.randf_range(0.45, 0.6)
	var half := ceili(cap_r) + 1
	var m := VoxelModel.new(Vector3i(half * 2 + 1, hc + 2, half * 2 + 1), v, Vector3(-(half + 0.5) * v, 0, -(half + 0.5) * v))
	m.define_type(1, "plant_tissue", "mushroom_stalk", true)
	m.define_type(2, "plant_tissue", "mushroom_cap_red" if red else "mushroom_cap_brown", true)
	m.define_type(3, "plant_tissue", "mushroom_stalk", true)
	var c := Vector3(half + 0.5, 0, half + 0.5)
	var stalk_h := hc * 0.62
	m.fill_line(c, c + Vector3(0, stalk_h, 0), hc * 0.14, hc * 0.1, 1)
	# Hut: abgeflachte Halbkugel
	for z in m.dims.z:
		for y in range(int(stalk_h), m.dims.y):
			for x in m.dims.x:
				var dx := (x + 0.5 - c.x) / cap_r
				var dz := (z + 0.5 - c.z) / cap_r
				var dy := (y + 0.5 - stalk_h) / (hc - stalk_h + 0.5)
				if dx * dx + dz * dz + dy * dy <= 1.0 and dy >= 0.0:
					m.set_v(x, y, z, 2)
	if red:
		# weiße Tupfen auf der Hutoberfläche (Fliegenpilz-ähnlich, Excel P009)
		for i in rng.randi_range(6, 10):
			var a := rng.randf() * TAU
			var e := rng.randf_range(0.15, 0.9)
			var p := c + Vector3(cos(a) * cap_r * cos(e), stalk_h + (hc - stalk_h) * sin(e), sin(a) * cap_r * cos(e))
			for k in 3:
				var q := p + Vector3(0, -k, 0)
				if m.get_v(int(q.x), int(q.y), int(q.z)) == 2:
					m.set_v(int(q.x), int(q.y), int(q.z), 3)
					break
	return m
