class_name CreatureGenerator
extends RefCounted
## Erzeugt Pflanzenwesen (Excel KR002 „Setzling_Pflanzenwesen“) aus Startwert + Genen.
## 1. make_genes(): zusammenhängende, gekoppelte Variation (keine unabhängigen Zufallswerte je Merkmal)
## 2. build_plan(): Körperbauplan (Simulationsdaten)
## 3. build_view(): Darstellung (Voxelnetze je Körperteil) + getrennte Kollisionsformen
## Excel-Quellen: Größe_cm (KR002), Farben F001/F002/F005 + Variation (16), Blattzahl/Größenbereich (13),
## Blatt_Variation und Kreatur_Max_Größe (09). Proportionen: data/config/creature_defaults.json.

const GENERATOR_VERSION := 1
const LEAF_SHAPES := ["rund", "spitz", "gelappt"]
const C_BASE := 1
const C_DARK := 2
const C_LIGHT := 3
const C_ACCENT := 4

static var _mesh_cache: Dictionary = {}


static func defaults(db: DefinitionDB) -> Dictionary:
	var d := db.config("creature_defaults")
	return d


## Gene: alle Variationen hängen an wenigen gekoppelten Größen.
static func make_genes(seed: int, db: DefinitionDB, overrides: Dictionary = {}) -> Dictionary:
	var cfg := defaults(db)
	var var_cfg: Dictionary = cfg.get("variation", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var kr := db.get_def("species", str(cfg.get("species_id", "KR002")))
	var base_cm := float(kr.get("size_cm", float(cfg.get("base_height_m_fallback", 0.85)) * 100.0))
	var g_size := db.get_def("genetics", "groesse")
	var max_cm := minf(float(g_size.get("max_value", 200.0)), db.generator_parameter("kreatur_max_groesse", 200.0))
	var min_cm := float(g_size.get("min_value", 50.0))
	var sf: Array = var_cfg.get("size_factor", [0.88, 1.12])
	var tr: Array = var_cfg.get("torso_ratio", [0.9, 1.12])
	var lf: Array = var_cfg.get("limb_factor", [0.9, 1.1])
	var dec := float(var_cfg.get("arm_leg_decoupling", 0.04))
	var size_factor := rng.randf_range(float(sf[0]), float(sf[1]))
	var limb := rng.randf_range(float(lf[0]), float(lf[1]))
	# Kopplung: größere Wesen haben tendenziell etwas längere Glieder und schmaleren Rumpf
	limb = clampf(limb + (size_factor - 1.0) * 0.3, float(lf[0]), float(lf[1]))
	var torso := clampf(rng.randf_range(float(tr[0]), float(tr[1])) - (size_factor - 1.0) * 0.4, float(tr[0]), float(tr[1]))
	var skin_ids: Array = var_cfg.get("skin_palette_ids", ["F001", "F002", "F005"])
	var weights := [0.6, 0.25, 0.15]
	var pick := rng.randf()
	var skin_id: String = skin_ids[0]
	var acc := 0.0
	for i in skin_ids.size():
		acc += weights[i] if i < weights.size() else 0.0
		if pick <= acc:
			skin_id = skin_ids[i]
			break
	var skin := db.palette_color(skin_id, Color("#2E7D32"))
	var variation := db.palette_variation(skin_id) * 0.5     # halbe Excel-Variation → Wesen bleiben zusammengehörig
	skin = Color.from_hsv(skin.h + rng.randf_range(-0.02, 0.02), clampf(skin.s * (1.0 + rng.randf_range(-variation, variation)), 0.0, 1.0),
		clampf(skin.v * (1.0 + rng.randf_range(-variation, variation)), 0.0, 1.0))
	# Blattfarbe aus der Hautfarbe abgeleitet (heller, leicht verschoben) → einheitlicher Eindruck
	var leaf := Color.from_hsv(skin.h + rng.randf_range(-0.03, 0.04), clampf(skin.s * 0.95, 0, 1), clampf(skin.v * 1.25 + 0.05, 0, 1))
	var lc: Array = var_cfg.get("leaf_count", [1, 3])
	var blatt_var := db.generator_parameter("blatt_variation", 0.4)
	var genes := {
		"generator_version": GENERATOR_VERSION,
		"height_m": clampf(base_cm * size_factor, min_cm, max_cm) / 100.0,
		"size_factor": size_factor,
		"torso_ratio": torso,
		"arm_factor": limb * (1.0 + rng.randf_range(-dec, dec)),
		"leg_factor": limb * (1.0 + rng.randf_range(-dec, dec)),
		"skin_palette_id": skin_id,
		"skin_color": skin.to_html(false),
		"leaf_color": leaf.to_html(false),
		"leaf_shape": LEAF_SHAPES[rng.randi_range(0, LEAF_SHAPES.size() - 1)],
		"leaf_count": rng.randi_range(int(lc[0]), int(lc[1])),
		"leaf_size": 1.0 + rng.randf_range(-blatt_var, blatt_var) * 0.5,
	}
	for k in overrides:
		genes[k] = overrides[k]
	# Grenzen erzwingen
	genes["height_m"] = clampf(float(genes["height_m"]), min_cm / 100.0, max_cm / 100.0)
	genes["leaf_count"] = clampi(int(genes["leaf_count"]), 0, BodyPlan.MAX_LEAVES)
	genes["torso_ratio"] = clampf(float(genes["torso_ratio"]), 0.8, 1.25)
	genes["arm_factor"] = clampf(float(genes["arm_factor"]), 0.8, 1.2)
	genes["leg_factor"] = clampf(float(genes["leg_factor"]), 0.8, 1.2)
	return genes


static func generate(seed: int, db: DefinitionDB, overrides: Dictionary = {}) -> BodyPlan:
	return build_plan(make_genes(seed, db, overrides), seed, db)


static func build_plan(genes: Dictionary, seed: int, db: DefinitionDB) -> BodyPlan:
	var cfg := defaults(db)
	var pr: Dictionary = cfg.get("proportions", {})
	var body_mat := str(cfg.get("materials", {}).get("body", "plant_tissue"))
	var H := float(genes["height_m"])
	var tr := float(genes["torso_ratio"])
	var af := float(genes["arm_factor"])
	var lf := float(genes["leg_factor"])
	var th := H * float(pr.get("limb_thickness", 0.07))
	var leg_u := H * float(pr.get("leg_upper", 0.19)) * lf
	var leg_l := H * float(pr.get("leg_lower", 0.18)) * lf
	var foot_h := H * float(pr.get("foot_height", 0.035))
	var t_h := H * float(pr.get("torso_height", 0.30)) * tr
	var t_w := H * float(pr.get("torso_width", 0.27)) * (0.85 + 0.15 * tr)
	var t_d := H * float(pr.get("torso_depth", 0.19)) * (0.9 + 0.1 * tr)
	var head := H * float(pr.get("head_size", 0.26))
	var neck := H * float(pr.get("neck", 0.02))
	var arm_u := H * float(pr.get("arm_upper", 0.17)) * af
	var arm_l := H * float(pr.get("arm_lower", 0.16)) * af
	var hand := H * float(pr.get("hand", 0.065))
	var bp := BodyPlan.new()
	bp.species_id = str(cfg.get("species_id", "KR002"))
	bp.plan_seed = seed
	bp.genes = genes.duplicate(true)
	bp.genes["leaf_length_m"] = H * float(pr.get("leaf_length", 0.2)) * float(genes.get("leaf_size", 1.0))
	bp.genes["stand_height_m"] = leg_u + leg_l + foot_h
	var P := func(d: Dictionary) -> void:
		var err := bp.add_part(d)
		if err != "":
			push_error("CreatureGenerator: " + err)
	P.call({"id": "torso", "type": "torso", "function": "rumpf", "material_id": body_mat, "shape": "ellipsoid",
		"size": [t_w, t_h, t_d], "parent": "", "attach": [0.0, 0.0, 0.0], "joint": "hips", "extent": "up", "side": "", "excel_ref": "KT001"})
	P.call({"id": "head", "type": "head", "function": "kopf_sinne", "material_id": body_mat, "shape": "ellipsoid",
		"size": [head * 1.05, head, head * 0.95], "parent": "torso", "attach": [0.0, t_h * 0.92 + neck, 0.0], "joint": "neck", "extent": "up", "side": "", "excel_ref": "KT003"})
	for s in ["l", "r"]:
		var sx := -1.0 if s == "l" else 1.0
		P.call({"id": "arm_%s_upper" % s, "type": "arm_upper", "function": "arm", "material_id": body_mat, "shape": "cylinder",
			"size": [th, arm_u, th], "parent": "torso", "attach": [sx * (t_w * 0.5 + th * 0.15), t_h * 0.78, 0.0], "joint": "shoulder_%s" % s, "extent": "down", "side": s, "excel_ref": "KT006"})
		P.call({"id": "arm_%s_lower" % s, "type": "arm_lower", "function": "unterarm", "material_id": body_mat, "shape": "cylinder",
			"size": [th * 0.9, arm_l, th * 0.9], "parent": "arm_%s_upper" % s, "attach": [0.0, -arm_u, 0.0], "joint": "elbow_%s" % s, "extent": "down", "side": s, "excel_ref": "KT006"})
		P.call({"id": "hand_%s" % s, "type": "hand", "function": "greifen", "material_id": body_mat, "shape": "ellipsoid",
			"size": [th * 1.25, hand, th * 0.95], "parent": "arm_%s_lower" % s, "attach": [0.0, -arm_l, 0.0], "joint": "wrist_%s" % s, "extent": "down", "side": s, "excel_ref": "KT006"})
		P.call({"id": "leg_%s_upper" % s, "type": "leg_upper", "function": "bein", "material_id": body_mat, "shape": "cylinder",
			"size": [th * 1.25, leg_u, th * 1.25], "parent": "torso", "attach": [sx * t_w * 0.24, t_h * 0.08, 0.0], "joint": "hip_%s" % s, "extent": "down", "side": s, "excel_ref": "KT008"})
		P.call({"id": "leg_%s_lower" % s, "type": "leg_lower", "function": "unterschenkel", "material_id": body_mat, "shape": "cylinder",
			"size": [th * 1.1, leg_l, th * 1.1], "parent": "leg_%s_upper" % s, "attach": [0.0, -leg_u, 0.0], "joint": "knee_%s" % s, "extent": "down", "side": s, "excel_ref": "KT008"})
		P.call({"id": "foot_%s" % s, "type": "foot", "function": "stehen", "material_id": body_mat, "shape": "foot",
			"size": [th * 1.45, foot_h, th * 2.3], "parent": "leg_%s_lower" % s, "attach": [0.0, -leg_l, 0.0], "joint": "ankle_%s" % s, "extent": "down", "side": s, "excel_ref": "KT008"})
	for i in int(genes["leaf_count"]):
		bp.add_leaf()
	bp.history.clear()
	return bp


# ───────────────────────── Darstellung ─────────────────────────

## Voxelgitter eines Körperteils. Rückgabe {"dims", "cells", "origin"}.
static func part_grid(p: Dictionary, v: float, leaf_shape: String) -> Dictionary:
	var sz: Array = p["size"]
	var nx := maxi(1, int(round(float(sz[0]) / v)))
	var ny := maxi(1, int(round(float(sz[1]) / v)))
	var nz := maxi(1, int(round(float(sz[2]) / v)))
	var dims := Vector3i(nx, ny, nz)
	var cells := PackedByteArray()
	cells.resize(nx * ny * nz)
	var shape: String = p["shape"]
	for z in nz:
		for y in ny:
			for x in nx:
				var u := (x + 0.5) / nx * 2.0 - 1.0
				var w := (y + 0.5) / ny * 2.0 - 1.0
				var q := (z + 0.5) / nz * 2.0 - 1.0
				var inside := false
				var t := C_BASE
				match shape:
					"box":
						inside = true
					"foot":
						inside = not (w > 0.2 and q > 0.45) and not (w < -0.6 and absf(u) > 0.8 and q > 0.6)
					"ellipsoid":
						inside = u * u + w * w + q * q <= 1.0
					"cylinder":
						inside = u * u + q * q <= 1.05
					"leaf":
						var f := (y + 0.5) / ny          # 0 Stiel … 1 Spitze
						var half_w := 0.0
						match leaf_shape:
							"spitz":
								half_w = pow(sin(PI * pow(f, 0.8)), 1.3) * (1.0 - 0.25 * f)
							"gelappt":
								half_w = sin(PI * f) * (0.72 + 0.28 * cos(f * 5.0 * TAU / 2.0))
							_:
								half_w = pow(sin(PI * f), 0.75)
						if f < 0.12:
							half_w = maxf(half_w, 0.12)
						inside = absf(u) <= half_w
						if inside and absf(u) <= 1.0 / nx + 0.02:
							t = C_DARK       # Mittelrippe
					"hook":
						# J-Haken: Schaft hinten (−z), unten Bogen nach vorn, Spitze zeigt nach oben
						var shaft := u * u + (q + 0.45) * (q + 0.45) <= 0.22 and w > -0.85
						var bottom := w < -0.6 and q > -0.65 and q < 0.9 and absf(u) < 0.5
						var tip := q > 0.42 and q < 0.98 and w < -0.2 and absf(u) < 0.5
						inside = shaft or bottom or tip
				if inside:
					cells[x + nx * (y + ny * z)] = t
	if p["type"] == "head":
		_paint_face(cells, dims)
	if p["type"] == "torso":
		# Längsrippen wie bei einem Pflanzenstängel
		for z in nz:
			for y in ny:
				for x in nx:
					var i := x + nx * (y + ny * z)
					if cells[i] == C_BASE and x % 3 == 1:
						cells[i] = C_ACCENT
	var origin := Vector3(-nx * v * 0.5, 0.0, -nz * v * 0.5)
	if p["extent"] == "down":
		origin.y = -ny * v
	if shape == "foot":
		origin.z = -nz * v * 0.32
	return {"dims": dims, "cells": cells, "origin": origin}


## Einfaches, lesbares Gesicht auf der Vorderseite (+z): zwei Augen mit Lichtpunkt, Lächeln.
static func _paint_face(cells: PackedByteArray, d: Vector3i) -> void:
	var front := func(x: int, y: int) -> int:
		for z in range(d.z - 1, -1, -1):
			if cells[x + d.x * (y + d.y * z)] != 0:
				return z
		return -1
	var paint := func(x: int, y: int, t: int) -> void:
		if x < 0 or y < 0 or x >= d.x or y >= d.y:
			return
		var z: int = front.call(x, y)
		if z >= 0:
			cells[x + d.x * (y + d.y * z)] = t
	var cx := d.x / 2.0
	var eye_y := int(d.y * 0.5)
	var eye_dx := maxi(2, int(round(d.x * 0.2)))
	for s in [-1, 1]:
		var ex := int(round(cx + s * eye_dx)) - 1
		for yy in range(eye_y, eye_y + 3):
			for xx in range(ex, ex + 2):
				paint.call(xx, yy, C_DARK)
		paint.call(ex + 1, eye_y + 2, C_LIGHT)   # Lichtpunkt oben im Auge
	var mouth_y := int(d.y * 0.3)
	var mw := maxi(2, int(round(d.x * 0.18)))
	for xx in range(int(cx) - mw, int(cx) + mw):
		paint.call(xx, mouth_y, C_DARK)
	paint.call(int(cx) - mw - 1, mouth_y + 1, C_DARK)
	paint.call(int(cx) + mw, mouth_y + 1, C_DARK)


static func part_colors(p: Dictionary, genes: Dictionary, materials: MaterialRegistry) -> PackedColorArray:
	var c := PackedColorArray()
	c.resize(5)
	var base: Color
	match p["type"]:
		"leaf":
			base = Color.html(genes.get("leaf_color", "#81C784"))
		"prosthesis":
			base = MaterialVisuals.color(materials, p["material_id"])
		_:
			if p["material_id"] == "plant_tissue":
				base = Color.html(genes.get("skin_color", "#2E7D32"))   # Erscheinungsmerkmal des Pflanzengewebes
			else:
				base = MaterialVisuals.color(materials, p["material_id"])
	# Abstufung innerhalb desselben Gewebes: Glieder wie Stängel etwas dunkler,
	# Hände/Füße wurzelartig, Kopf etwas heller. Reine Darstellung (Material bleibt gleich).
	if p["material_id"] == "plant_tissue" and p["type"] != "leaf":
		match p["type"]:
			"arm_upper", "arm_lower", "leg_upper", "leg_lower":
				base = base.darkened(0.12)
			"hand", "foot":
				base = base.darkened(0.25).lerp(Color("#5D4037"), 0.25)
			"head":
				base = base.lightened(0.06)
	c[0] = Color.TRANSPARENT
	c[C_BASE] = base
	c[C_DARK] = base.darkened(0.72) if p["type"] != "leaf" else base.darkened(0.3)
	c[C_LIGHT] = Color(0.95, 0.97, 0.9)
	c[C_ACCENT] = base.darkened(0.14)
	return c


static func part_mesh(p: Dictionary, genes: Dictionary, materials: MaterialRegistry, v: float) -> Dictionary:
	var leaf_shape := str(genes.get("leaf_shape", "rund"))
	var colors := part_colors(p, genes, materials)
	var key := "%s|%s|%s|%s|%s|%s|%.4f" % [p["shape"], p["type"], str(p["size"]), leaf_shape, colors[C_BASE].to_html(), p["extent"], v]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var g := part_grid(p, v, leaf_shape)
	var solid := PackedByteArray([0, 1, 1, 1, 1])
	solid.resize(256)
	var none := PackedByteArray()
	none.resize(256)
	var r := VoxelMesher.build(g["dims"], g["cells"], colors, v, g["origin"], solid, none, Callable(), 0.04)
	var res := {"mesh": r["mesh"], "voxels": r["solid_cells"], "faces": r["faces"], "geometric_volume": r["solid_cells"] * v * v * v}
	if _mesh_cache.size() > 4000:
		_mesh_cache.clear()
	_mesh_cache[key] = res
	return res


static func clear_cache() -> void:
	_mesh_cache.clear()


## Baut die Darstellung eines Körperplans. Nur wirksam vorhandene Teile erhalten Nodes.
## Rückgabe: Node3D mit Metadaten; pivots/areas über CreatureView.
static func build_view(plan: BodyPlan, materials: MaterialRegistry, voxel_size: float) -> CreatureView:
	var view := CreatureView.new()
	view.setup(plan, materials, voxel_size)
	return view
