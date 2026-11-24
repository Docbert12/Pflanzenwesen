class_name ObjectGenerator
extends RefCounted
## Prozedurale Modelle für Gegenstände der Lebenswelt (Prompt 6) aus den TATSÄCHLICHEN Daten:
## Form + Maße (verformt → neue Maße), Material (Farbe aus dem Physikmaterial), Schaden (Risse),
## Temperatur (Glühen ab ~800 K, Schmelze). Voxelmodell über VoxelModel (gleicher Generatorweg wie
## Pflanzen und Wesen). Der Name eines Gegenstands beeinflusst das Modell nie.
##
## Ursprung des Modells: Mitte der Unterseite. Stäbe liegen entlang +x, Verbünde werden aus ihren
## Bauteilen an den Verbund-Abständen zusammengesetzt (stabile Anschluss- und Griffpunkte).

const VOXEL := 0.005


## Signatur für Neuaufbau: ändert sich bei Verformung, Bruch, Glühen, Schmelzen.
static func signature(mp: MaterialPiece) -> String:
	return "%s|%s|%d|%d|%s|%d" % [mp.material_id, mp.shape, mp.visual_version, int(mp.damage * 4.0), _glow_state(mp), mp.assembly_id]


static func _glow_state(mp: MaterialPiece) -> String:
	if mp.liquid_fraction() > 0.0:
		return "melt"
	var t := mp.temperature_k()
	if t >= 1100.0:
		return "hell"
	if t >= 798.0:
		return "dunkelrot"
	return ""


static func glow_color(mp: MaterialPiece, base: Color) -> Color:
	match _glow_state(mp):
		"melt":
			return Color(1.0, 0.72, 0.25)
		"hell":
			return Color(1.0, 0.55, 0.15)
		"dunkelrot":
			return base.lerp(Color(0.85, 0.15, 0.05), 0.65)
	return base


static func build_piece(mp: MaterialPiece, materials: MaterialRegistry) -> Node3D:
	var d := mp.dims_m
	var nx := maxi(1, int(round(d.x / VOXEL)))
	var ny := maxi(1, int(round(d.y / VOXEL)))
	var nz := maxi(1, int(round(d.z / VOXEL)))
	var vm := VoxelModel.new(Vector3i(nx, ny, nz), VOXEL, Vector3(-nx * VOXEL * 0.5, 0.0, -nz * VOXEL * 0.5))
	var base := MaterialVisuals.color(materials, mp.material_id)
	var col := glow_color(mp, base)
	vm.define_type(1, mp.material_id, "", false, col)
	vm.define_type(2, mp.material_id, "", false, col.darkened(0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = mp.id * 7919 + 3
	match mp.shape:
		"rod":
			var r := ny * 0.5
			for x in nx:
				for y in ny:
					for z in nz:
						if Vector2(y + 0.5 - r, z + 0.5 - nz * 0.5).length() <= r:
							vm.set_v(x, y, z, 1)
		"lump":
			vm.fill_sphere(Vector3(nx, ny, nz) * 0.5, minf(nx, minf(ny, nz)) * 0.5, 1)
		"bundle":
			for x in nx:
				for y in ny:
					for z in nz:
						if rng.randf() < 0.55:
							vm.set_v(x, y, z, 1 if (z + y) % 3 != 0 else 2)
		"cup", "mold":
			# Wandstärke je Richtung (Form: Innenraum 60 % × 60 % der Außenmaße, wie MaterialPiece.inner_floor_m)
			var f := 0.17 if mp.shape == "cup" else 0.2
			var wall := maxi(1, int(round(nx * f)))
			var wall_z := maxi(1, int(round(nz * f)))
			var floor_h := maxi(1, ny - int(round(mp.cavity_m3 / ((d.x * 0.6) * (d.z * 0.6)) / VOXEL))) if mp.shape == "mold" else wall
			for x in nx:
				for y in ny:
					for z in nz:
						var inside := x >= wall and x < nx - wall and z >= wall_z and z < nz - wall_z and y >= floor_h
						if not inside:
							vm.set_v(x, y, z, 1)
		_:
			for x in nx:
				for y in ny:
					for z in nz:
						vm.set_v(x, y, z, 1)
	# Schaden sichtbar: dunkle Risszellen
	if mp.damage >= 0.25:
		var n := int(mp.damage * nx * ny * nz * 0.08)
		for i in n:
			var x := rng.randi_range(0, nx - 1)
			var y := rng.randi_range(0, ny - 1)
			var z := rng.randi_range(0, nz - 1)
			if vm.get_v(x, y, z) != 0:
				vm.set_v(x, y, z, 2)
	var node := vm.build_node(materials, "Stück_%d" % mp.id, false)
	if _glow_state(mp) != "":
		var mi: MeshInstance3D = node.get_node("Netz")
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.5 if _glow_state(mp) == "dunkelrot" else 2.5
		mi.material_override = m
	node.set_meta("signature", signature(mp))
	return node


## Verbund: Teile an ihren Abständen entlang +x vom Griffpunkt (Ursprung = Griffpunkt).
static func build_assembly(a: Assembly, ctx: LifeContext) -> Node3D:
	var root := Node3D.new()
	root.name = "Verbund_%d" % a.id
	for pid in a.part_ids:
		var p: MaterialPiece = ctx.material_pieces.get(pid, null)
		if p == null:
			continue
		var n := build_piece(p, ctx.sim.materials)
		var off := float(a.offsets.get(pid, 0.0))
		match p.role:
			"handle", "grip":
				n.position = Vector3(off, 0.0, 0.0) + Vector3(0, -p.dims_m.y * 0.5, 0)
			"head", "cup", "body":
				n.position = Vector3(off, -p.dims_m.y * 0.5, 0.0)
			"binding":
				n.position = Vector3(off, -p.dims_m.y * 0.5, 0.0)
				n.scale = Vector3(0.45, 1.25, 1.25)
		root.add_child(n)
	root.set_meta("signature", assembly_signature(a, ctx))
	return root


static func assembly_signature(a: Assembly, ctx: LifeContext) -> String:
	var s := "%d|%d" % [a.id, a.visual_version]
	for pid in a.part_ids:
		var p: MaterialPiece = ctx.material_pieces.get(pid, null)
		if p != null:
			s += "|" + signature(p)
	return s
