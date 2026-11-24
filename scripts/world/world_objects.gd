class_name WorldObjects
extends RefCounted
## Gemeinsamer Aufbau der Weltobjekte (Lebensbaum, Pflanzen, Pilze) für Weltvorschau
## und lebende Welt. Vorher in world_preview.gd; ausgelagert, damit es keine zweite,
## abweichende Implementierung gibt.

## Rückgabe: {"tree_model", "tree_node", "tree_info", "plants": Array[{node, model, kind, excel_id, spot, position}], "entity_ids"}
static func spawn(root: Node3D, sim: Simulation, db: DefinitionDB, world: VoxelWorld, cfg: Dictionary, extra_spots: Array = []) -> Dictionary:
	var g: Dictionary = world.generated
	var cs := world.data.cell_size
	var vs: Dictionary = cfg.get("voxel_sizes_m", {})
	var ids: Array = []
	var kr001 := db.get_def("species", "KR001")
	var height_m := float(kr001.get("size_cm", 800.0)) / 100.0
	var tc: Vector3i = g["tree_cell"]
	var tree := TreeGenerator.generate(world.world_seed + 7, {"height_m": height_m, "voxel_size": float(vs.get("tree", 0.2)),
		"leaf_color": db.palette_color("F001", Color("#2E7D32")).lightened(0.12)})
	var tnode := tree.build_node(sim.materials, "Lebensbaum", true)
	root.add_child(tnode)
	tnode.position = Vector3((tc.x + 0.5) * cs, tc.y * cs, (tc.z + 0.5) * cs)
	ids.append_array(register_masses(sim, tree, "Lebensbaum"))
	var info := {"height_m": height_m, "cells": tree.count_by_type(), "mass": tree.mass_by_material(sim.materials),
		"position": tnode.position, "root_bed_radius_m": float(cfg.get("root_bed_radius_cells", 4)) * cs, "seed": world.world_seed + 7}
	var lbl := Label3D.new()
	lbl.text = "Lebensbaum mit Wurzelbeet"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.01
	lbl.outline_size = 8
	lbl.position = tnode.position + Vector3(0, height_m + 2.5, 0)
	root.add_child(lbl)
	var plants: Array = []
	var plant_v := float(vs.get("plant", 0.05))
	var all_spots: Array = g["plant_spots"].duplicate()
	all_spots.append_array(extra_spots)
	for spot in all_spots:
		var kind: String = spot["kind"]
		var model := PlantGenerator.generate(kind, int(spot["seed"]), PlantGenerator.height_for(kind, db), plant_v)
		var node := model.build_node(sim.materials, "%s_%d" % [kind, plants.size()], PlantGenerator.KINDS[kind]["collision"])
		var c: Vector3i = spot["cell"]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(spot["seed"])
		node.position = Vector3((c.x + rng.randf_range(0.25, 0.75)) * cs, c.y * cs, (c.z + rng.randf_range(0.25, 0.75)) * cs)
		node.rotation.y = rng.randf() * TAU
		node.set_meta("kind", kind)
		node.set_meta("excel_id", PlantGenerator.KINDS[kind]["excel_id"])
		root.add_child(node)
		ids.append_array(register_masses(sim, model, "Pflanze %s" % kind))
		plants.append({"node": node, "model": model, "kind": kind, "excel_id": PlantGenerator.KINDS[kind]["excel_id"], "spot": spot, "position": node.position})
	return {"tree_model": tree, "tree_node": tnode, "tree_info": info, "plants": plants, "entity_ids": ids}


static func register_masses(sim: Simulation, model: VoxelModel, label: String) -> Array:
	var ids: Array = []
	var vols := model.model_volume_by_material()
	for mid in vols:
		var o := sim.create_object(mid, vols[mid], sim.thermal.ambient_temperature_k, "world", "%s (%s)" % [label, mid])
		if o != null:
			ids.append(o.id)
	return ids


## Terrainspalten, die der Baum am Boden belegt (Stamm/tiefe Äste, 0,6–2 m über Boden).
## Oberflächenwurzeln blockieren nicht (sie sind niedrig und begehbar).
static func tree_footprint(model: VoxelModel, node_pos: Vector3, cell_size: float) -> Dictionary:
	var cols := {}
	var v := model.voxel_size
	var y0 := int(round(-model.origin.y / v))   # Zellindex der Bodenhöhe
	for z in model.dims.z:
		for y in range(y0 + 3, mini(model.dims.y, y0 + int(2.0 / v) + 1)):
			for x in model.dims.x:
				var t := model.get_v(x, y, z)
				if t == 0 or not model.collide_types.has(t):
					continue
				var p := node_pos + model.origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * v
				cols[Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))] = true
	return cols


## Spalten unter der Laubkrone (vereinfachte Verschattung).
static func crown_shade(model: VoxelModel, node_pos: Vector3, cell_size: float) -> Dictionary:
	var cols := {}
	var v := model.voxel_size
	for z in model.dims.z:
		for y in model.dims.y:
			for x in model.dims.x:
				var t := model.get_v(x, y, z)
				if t == TreeGenerator.T_LEAF or t == TreeGenerator.T_LEAF2:
					var p := node_pos + model.origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * v
					cols[Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))] = true
	return cols
