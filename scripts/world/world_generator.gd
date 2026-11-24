class_name WorldGenerator
extends RefCounted
## Erzeugt reproduzierbar die Testkarte aus Startwert + data/config/world.json.
## Gleicher Startwert und gleiche Konfiguration → identische Terrainzellen und Wassermengen.
## Aufbau: flacher Startbereich (Platz für den Lebensbaum), Hügel, Seebecken mit Wasser,
## Grundgestein (verankert) in der untersten Lage.


## Rückgabe: {"data": VoxelData, "water": PackedFloat64Array (m³ je Spalte), "tree_cell": Vector3i,
##            "plant_spots": Array[Dictionary], "seed": int}
static func generate(cfg: Dictionary, palette: VoxelPalette, seed: int) -> Dictionary:
	var sz: Array = cfg["size_cells"]
	var size := Vector3i(int(sz[0]), int(sz[1]), int(sz[2]))
	var cell := float(cfg["cell_size_m"])
	var data := VoxelData.new(size, cell)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var base := int(cfg["base_height_cells"])
	var amp := float(cfg["hill_amplitude_cells"])
	var water_level := int(cfg["water_level_cells"])
	var stone_above := int(cfg["stone_above_cells"])
	var sa: Dictionary = cfg["start_area"]
	var start := Vector2(sa["center"][0], sa["center"][1])
	var start_r := float(sa["radius_cells"])
	var lk: Dictionary = cfg["lake"]
	var lake := Vector2(lk["center"][0], lk["center"][1])
	var lake_r := float(lk["radius_cells"])
	var lake_floor := int(lk["floor_cells"])
	var root_r := float(cfg["root_bed_radius_cells"])
	var id_bedrock := palette.id_of("bedrock")
	var id_stone := palette.id_of("stone")
	var id_soil := palette.id_of("soil")
	var id_grass := palette.id_of("grass")
	var id_root := palette.id_of("root_bed")
	var heights := PackedInt32Array()
	heights.resize(size.x * size.z)
	for z in size.z:
		for x in size.x:
			var p := Vector2(x, z)
			var n := noise.get_noise_2d(x, z)               # −1 … 1
			var hill := maxf(0.0, n + 0.15) * amp
			var flat := smoothstep(start_r, start_r + 7.0, p.distance_to(start))
			var h := float(base) + hill * flat
			var dl := p.distance_to(lake)
			if dl < lake_r + 4.0:
				var t := smoothstep(lake_r * 0.35, lake_r + 4.0, dl)
				h = lerpf(float(lake_floor), minf(h, float(base)), t)
			heights[x + size.x * z] = clampi(int(round(h)), 2, size.y - 3)
	var water := PackedFloat64Array()
	water.resize(size.x * size.z)
	water.fill(0.0)
	var area := cell * cell
	for z in size.z:
		for x in size.x:
			var h := heights[x + size.x * z]
			var in_root := Vector2(x, z).distance_to(start) <= root_r
			for y in h:
				var t := id_soil
				if y == 0:
					t = id_bedrock
				elif y < h - 3:
					t = id_stone
				elif y == h - 1:
					if in_root:
						t = id_root
					elif y >= stone_above:
						t = id_stone
					elif y >= water_level:
						t = id_grass
					else:
						t = id_soil
				data.set_cell(x, y, z, t)
			# Wasser nur im Seebecken (keine zufälligen Pfützen)
			if h < water_level and Vector2(x, z).distance_to(lake) < lake_r + 4.0:
				water[x + size.x * z] = float(water_level - h) * cell * area
	var tree_cell := Vector3i(int(start.x), heights[int(start.x) + size.x * int(start.y)], int(start.y))
	# Pflanzenstandorte (deterministisch)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	var spots: Array = []
	var pc: Dictionary = cfg.get("plants", {})
	var want := int(pc.get("count", 40))
	var mush := float(pc.get("mushroom_share", 0.25))
	var tries := 0
	var used := {}
	while spots.size() < want and tries < want * 40:
		tries += 1
		var x := rng.randi_range(1, size.x - 2)
		var z := rng.randi_range(1, size.z - 2)
		var key := x + size.x * z
		if used.has(key):
			continue
		var h := heights[key]
		if data.get_cell(x, h - 1, z) != id_grass:
			continue
		if Vector2(x, z).distance_to(start) <= root_r + 2.0:
			continue
		used[key] = true
		var hilly := h > base + 1
		var r := rng.randf()
		var kind := "bush"
		if r < mush * (1.6 if hilly else 0.6):
			kind = "mushroom_red" if rng.randf() < 0.5 else "mushroom_brown"
		elif r < 0.55:
			kind = "grass"
		elif r < 0.75:
			kind = "fern"
		spots.append({"cell": Vector3i(x, h, z), "kind": kind, "seed": rng.randi()})
	return {"data": data, "water": water, "tree_cell": tree_cell, "plant_spots": spots, "seed": seed, "heights": heights}
