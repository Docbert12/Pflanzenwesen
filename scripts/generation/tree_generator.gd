class_name TreeGenerator
extends RefCounted
## Prozeduraler Lebensbaum (Excel KR001 „Mutterbaum“, Größe_cm → Höhe).
## Voxelmodell mit Stamm, Ästen, Krone und sichtbaren Oberflächenwurzeln.
## Materialien: Holz (Stamm/Äste/Wurzeln), Pflanzengewebe (Blätter).
## Kollision: nur Holzteile (Laub ist durchlässig). Kein Wachstum, keine Fortpflanzung.

const T_BARK := 1
const T_ROOT := 2
const T_LEAF := 3
const T_LEAF2 := 4
const LEAF_FILL := 0.02


## params: height_m, trunk_radius_m, crown_radius_m, root_count, root_length_m, voxel_size, leaf_color (Color, optional)
static func generate(seed: int, params: Dictionary) -> VoxelModel:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v: float = params.get("voxel_size", 0.2)
	var h: float = params.get("height_m", 8.0) / v
	var tr: float = params.get("trunk_radius_m", 0.55) / v
	var cr: float = params.get("crown_radius_m", 2.2) / v
	var rl: float = params.get("root_length_m", 3.0) / v
	var roots: int = params.get("root_count", 7)
	var half := ceili(maxf(rl + 2.0, cr * 1.9)) + 2
	var below := 3
	var height_cells := ceili(h + cr * 0.7) + below + 2
	var dims := Vector3i(half * 2 + 1, height_cells, half * 2 + 1)
	var m := VoxelModel.new(dims, v, Vector3(-(half + 0.5) * v, -below * v, -(half + 0.5) * v))
	m.define_type(T_BARK, "wood", "bark", true)
	m.define_type(T_ROOT, "wood", "root", true)
	var leaf_col = params.get("leaf_color", null)
	# Laub: Füllanteil 2 % (Spielannahme: Blätter füllen eine Kronenzelle nur spärlich)
	m.define_type(T_LEAF, "plant_tissue", "leaf", false, leaf_col, LEAF_FILL)
	m.define_type(T_LEAF2, "plant_tissue", "leaf_light", false, leaf_col.lightened(0.18) if leaf_col != null else null, LEAF_FILL)
	var c := Vector3(half + 0.5, below, half + 0.5)   # Stammfuß (Bodenhöhe)
	# Stamm mit Wurzelanlauf
	var trunk_top := h * 0.72
	for y in range(below - 1, below + ceili(trunk_top) + 1):
		var f := float(y - below) / trunk_top
		var r := tr * (1.0 - 0.35 * clampf(f, 0.0, 1.0))
		if y - below < 3:
			r += tr * 0.45 * (1.0 - float(maxi(0, y - below)) / 3.0)
		m.fill_sphere(Vector3(c.x, y + 0.5, c.z), r, T_BARK)
	# Äste
	var tips: Array = []
	var n_br := rng.randi_range(5, 7)
	for i in n_br:
		var ang := TAU * (float(i) / n_br) + rng.randf_range(-0.35, 0.35)
		var start_h := trunk_top * rng.randf_range(0.6, 0.98)
		var a := Vector3(c.x, below + start_h, c.z)
		var reach := cr * rng.randf_range(0.75, 1.05)
		var rise := cr * rng.randf_range(0.35, 0.7)
		var b := a + Vector3(cos(ang) * reach, rise, sin(ang) * reach)
		m.fill_line(a, b, tr * 0.42, tr * 0.18, T_BARK)
		tips.append(b)
	var top := Vector3(c.x, below + trunk_top + cr * 0.35, c.z)
	m.fill_line(Vector3(c.x, below + trunk_top, c.z), top, tr * 0.5, tr * 0.25, T_BARK)
	tips.append(top)
	# Krone: Laubkugeln an den Astenden, leicht ausgedünnt
	var keep := func(x: int, y: int, z: int) -> bool:
		var hsh := ((x * 92837111) ^ (y * 689287499) ^ (z * 283923481) ^ seed) & 1023
		return hsh < 900
	for tip in tips:
		var lr := cr * rng.randf_range(0.48, 0.66)
		m.fill_sphere(tip, lr, T_LEAF if rng.randf() < 0.6 else T_LEAF2, true, keep)
	m.fill_sphere(top + Vector3(0, cr * 0.15, 0), cr * 0.7, T_LEAF, true, keep)
	# Oberflächenwurzeln: strahlenförmig, flach auslaufend, teils im Boden
	for i in roots:
		var ang := TAU * (float(i) / roots) + rng.randf_range(-0.25, 0.25)
		var length := rl * rng.randf_range(0.75, 1.0)
		var a := Vector3(c.x + cos(ang) * tr * 0.8, below + 0.9, c.z + sin(ang) * tr * 0.8)
		var mid := Vector3(c.x + cos(ang) * length * 0.55, below + 0.35, c.z + sin(ang) * length * 0.55)
		var b := Vector3(c.x + cos(ang + rng.randf_range(-0.3, 0.3)) * length, below - 0.6, c.z + sin(ang) * length)
		m.fill_line(a, mid, tr * 0.42, tr * 0.28, T_ROOT, true)
		m.fill_line(mid, b, tr * 0.28, 0.6, T_ROOT, true)
	return m
