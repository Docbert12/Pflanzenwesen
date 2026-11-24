class_name WorldPreview
extends Node3D
## Weltvorschau: Voxelwelt mit Bearbeitung, Wasser, Bruchstücken, Lebensbaum, Pflanzen und Pilzen.

@onready var sim: Simulation = $Simulation
@onready var camera: LabCamera = $LabCamera
@onready var world: VoxelWorld = $VoxelWorld

var db := DefinitionDB.new()
var cfg: Dictionary
var mode: String = "remove"         # remove / add / inspect
var place_type: int = 1
var selected_cell := Vector3i(-1, -1, -1)
var hover := {}
var objects_root: Node3D
var object_entities: Array = []     # IDs registrierter PhysicalObjects von Baum/Pflanzen
var tree_info: Dictionary = {}
var plant_count: int = 0
var last_message: String = ""
var errors: Array = []

var _ui_status: RichTextLabel
var _ui_sel: RichTextLabel
var _ui_msg: Label
var _ui_events: RichTextLabel
var _seed_box: SpinBox
var _type_opt: OptionButton
var _mode_btns: Dictionary = {}
var _cursor: MeshInstance3D
var _accum := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sim.initialize()
	if not db.load_all():
		errors.append_array(db.errors)
	cfg = db.config("world")
	if cfg.is_empty():
		errors.append("data/config/world.json fehlt oder ist ungültig.")
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_env()
	_build_ui()
	if not sim.is_ready() or not errors.is_empty():
		_ui_status.text = "[color=#ff6060]Fehler:[/color]\n" + "\n".join(sim.init_errors + errors)
		return
	if not world.setup(sim, cfg, db.config("voxel_palette")):
		_ui_status.text = "[color=#ff6060]Fehler:[/color]\n" + "\n".join(world.errors)
		return
	for id in world.palette.editable_solid_ids():
		_type_opt.add_item("%s (%s)" % [world.palette.display_name(id), world.palette.material_of(id)], id)
	place_type = world.palette.id_of("soil")
	_type_opt.select(_type_opt.get_item_index(place_type))
	camera.object_picked.connect(_on_pick)
	regenerate(int(cfg.get("seed", db.generator_parameter("gelaende_seed", 12345))))


func regenerate(seed_value: int) -> void:
	var t0 := Time.get_ticks_msec()
	_clear_objects()
	world.generate(seed_value)
	_spawn_objects()
	selected_cell = Vector3i(-1, -1, -1)
	if _seed_box:
		_seed_box.set_value_no_signal(seed_value)
	var size: Vector3i = world.data.size
	var cs := world.data.cell_size
	camera.target = Vector3(size.x * cs * 0.45, world.cfg["base_height_cells"] * cs, size.z * cs * 0.5)
	camera.distance = 30.0
	camera.pitch = -0.6
	camera.yaw = 0.5
	camera._apply()
	last_message = "Welt mit Startwert %d erzeugt (%d ms)." % [seed_value, Time.get_ticks_msec() - t0]


func _clear_objects() -> void:
	for id in object_entities:
		sim.remove_object(id)
	object_entities.clear()
	if objects_root:
		objects_root.queue_free()
	objects_root = Node3D.new()
	objects_root.name = "Weltobjekte"
	add_child(objects_root)


func _spawn_objects() -> void:
	var r := WorldObjects.spawn(objects_root, sim, db, world, cfg)
	object_entities.append_array(r["entity_ids"])
	tree_info = r["tree_info"]
	plant_count = r["plants"].size()


func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.72, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.75)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	_cursor = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 1.02
	_cursor.mesh = bm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1, 1, 0.2, 0.28)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.no_depth_test = true
	_cursor.material_override = cm
	_cursor.visible = false
	add_child(_cursor)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var left := Nav.panel(root)
	left.offset_left = 10
	left.offset_top = 10
	left.offset_right = 430
	var v := VBoxContainer.new()
	left.add_child(v)
	Nav.back_button(v, self)
	_ui_status = RichTextLabel.new()
	_ui_status.bbcode_enabled = true
	_ui_status.fit_content = true
	_ui_status.custom_minimum_size = Vector2(410, 0)
	_ui_status.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(_ui_status)
	Nav.label(v, "Bearbeitung (Testmodus)", 15).modulate = Color(0.75, 0.9, 1)
	var modes := HBoxContainer.new()
	v.add_child(modes)
	for m in [["remove", "Entfernen (1)"], ["add", "Hinzufügen (2)"], ["inspect", "Auswählen (3)"]]:
		_mode_btns[m[0]] = Nav.button(modes, m[1], _set_mode.bind(m[0]))
	var trow := HBoxContainer.new()
	v.add_child(trow)
	Nav.label(trow, "Material:", 13, false)
	_type_opt = OptionButton.new()
	_type_opt.focus_mode = Control.FOCUS_NONE
	_type_opt.item_selected.connect(func(i): place_type = _type_opt.get_item_id(i))
	trow.add_child(_type_opt)
	var srow := HBoxContainer.new()
	v.add_child(srow)
	Nav.label(srow, "Startwert:", 13, false)
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 2147483647
	_seed_box.step = 1
	_seed_box.custom_minimum_size = Vector2(140, 0)
	srow.add_child(_seed_box)
	Nav.button(srow, "Erzeugen", func(): regenerate(int(_seed_box.value)))
	var rrow := HBoxContainer.new()
	v.add_child(rrow)
	Nav.button(rrow, "Zurücksetzen (gleicher Startwert, R)", func(): regenerate(world.world_seed))
	Nav.button(rrow, "Pause (Leertaste)", _toggle_pause)
	var hints := Nav.label(v, "Maus: rechts ziehen = drehen · Mitte/Umschalt+rechts = verschieben · Rad = zoomen · Linksklick = Werkzeug anwenden\nTasten: 1 Entfernen · 2 Hinzufügen · 3 Auswählen · WASD/QE bewegen · R Zurücksetzen · Leertaste Pause\nEntfernen unter einem Überhang löst kleine, nicht verankerte Teile als fallende Bruchstücke.", 12)
	hints.modulate = Color(0.8, 0.85, 0.9)
	var right := Nav.panel(root)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -400
	right.offset_right = -10
	right.offset_top = 10
	var rv := VBoxContainer.new()
	right.add_child(rv)
	Nav.label(rv, "Auswahl", 15).modulate = Color(0.75, 0.9, 1)
	_ui_sel = RichTextLabel.new()
	_ui_sel.bbcode_enabled = true
	_ui_sel.fit_content = true
	_ui_sel.custom_minimum_size = Vector2(380, 0)
	_ui_sel.add_theme_font_size_override("normal_font_size", 13)
	rv.add_child(_ui_sel)
	var bottom := Nav.panel(root)
	bottom.anchor_left = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -640
	bottom.offset_right = -10
	bottom.offset_top = -220
	bottom.offset_bottom = -10
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	_ui_msg = Nav.label(bv, "")
	_ui_msg.modulate = Color(0.6, 1, 0.6)
	_ui_events = RichTextLabel.new()
	_ui_events.bbcode_enabled = true
	_ui_events.custom_minimum_size = Vector2(610, 160)
	_ui_events.add_theme_font_size_override("normal_font_size", 12)
	bv.add_child(_ui_events)
	_set_mode(mode)


func _set_mode(m: String) -> void:
	mode = m
	for k in _mode_btns:
		_mode_btns[k].modulate = Color(1, 1, 0.4) if k == m else Color.WHITE


func _toggle_pause() -> void:
	sim.set_paused(not sim.is_paused())


## Werkzeug am Strahl anwenden (auch für Tests aufrufbar).
func apply_tool(origin: Vector3, dir: Vector3) -> Dictionary:
	var hit := world.raycast(origin, dir)
	if not hit["hit"]:
		last_message = "Kein Terrain getroffen."
		return {"ok": false}
	var cell: Vector3i = hit["cell"]
	match mode:
		"inspect":
			selected_cell = cell
			return {"ok": true}
		"remove":
			var r := world.set_voxel(cell, 0)
			last_message = ("Entfernt %s." % str(cell)) if r["ok"] else r["message"]
			if r.get("detached", 0) > 0:
				last_message += " %d Bruchstück(e) gelöst." % r["detached"]
			selected_cell = cell
			return r
		"add":
			var n: Vector3i = hit["normal"]
			var target: Vector3i = cell + n
			if n == Vector3i.ZERO:
				last_message = "Kamera steckt im Terrain."
				return {"ok": false}
			var r2 := world.set_voxel(target, place_type)
			last_message = ("%s gesetzt bei %s." % [world.palette.display_name(place_type), str(target)]) if r2["ok"] else r2["message"]
			selected_cell = target
			return r2
	return {"ok": false}


func _on_pick(origin: Vector3, direction: Vector3, _additive: bool) -> void:
	if world.data == null:
		return
	apply_tool(origin, direction)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_set_mode("remove")
			KEY_2:
				_set_mode("add")
			KEY_3:
				_set_mode("inspect")
			KEY_R:
				regenerate(world.world_seed)
			KEY_SPACE:
				_toggle_pause()
			_:
				return
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if world.data == null:
		return
	# Cursor unter der Maus
	var mp := get_viewport().get_mouse_position()
	var hit := world.raycast(camera.project_ray_origin(mp), camera.project_ray_normal(mp))
	if hit["hit"]:
		var c: Vector3i = hit["cell"]
		if mode == "add":
			c += hit["normal"]
		var cs := world.data.cell_size
		_cursor.visible = true
		_cursor.scale = Vector3.ONE * cs
		_cursor.position = (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * cs
	else:
		_cursor.visible = false
	_accum += delta
	if _accum < 0.15:
		return
	_accum = 0.0
	_refresh_ui()


func _refresh_ui() -> void:
	var ms := world.mass_summary()
	var size: Vector3i = world.data.size
	var cs := world.data.cell_size
	var wdev := world.water.total() - world.water.initial_total
	_ui_status.text = "[b]Weltvorschau[/b]  Startwert [b]%d[/b] %s\nKarte %d × %d × %d Zellen à %.2f m = %.0f × %.0f × %.0f m\nChunks %d × %d × %d Zellen, %d Chunks · Neuaufbauten gesamt %d\nTerrainmasse %s · Bruchstücke %d (%s, max. %d)\nWasser %.3f m³ (%.0f kg) · Abweichung %s m³ · %d Schritte\nLebensbaum %.1f m · Pflanzen/Pilze %d · Physikobjekte %d" % [
		world.world_seed, "[color=#ffcc40](pausiert)[/color]" if sim.is_paused() else "",
		size.x, size.y, size.z, cs, size.x * cs, size.y * cs, size.z * cs,
		world.chunk_dims.x, world.chunk_dims.y, world.chunk_dims.z, world.chunks.size(), world.total_rebuilds,
		_fmt_mass(ms["terrain_kg"]), world.fragments.size(), _fmt_mass(ms["fragments_kg"]), world.max_fragments,
		ms["water_m3"], ms["water_kg"], TestSuite.sci(wdev), world.water.steps,
		tree_info.get("height_m", 0.0), plant_count, sim.registry.count()]
	_ui_msg.text = last_message
	var lines: Array = []
	if world.data.in_bounds(selected_cell.x, selected_cell.y, selected_cell.z):
		var t := world.data.get_cell(selected_cell.x, selected_cell.y, selected_cell.z)
		var col := selected_cell.x + world.water.w * selected_cell.z
		lines.append("Zelle %s" % str(selected_cell))
		if t == 0:
			lines.append("Luft")
		else:
			var mid := world.palette.material_of(t)
			var m := sim.materials.get_material(mid)
			lines.append("Typ: %s (ID %d)" % [world.palette.display_name(t), t])
			lines.append("Physikmaterial: %s" % m.display_name)
			lines.append("Zellmasse: %.1f kg (ρ %.0f kg/m³ · %.4f m³)" % [m.density * cs * cs * cs, m.density, cs * cs * cs])
			lines.append("Veränderbar: %s" % ("ja" if world.palette.is_editable(t) else "nein (verankert)"))
		lines.append("Spalte: Boden %d Zellen, Wassertiefe %.3f m" % [world.water.ground[col], world.water.depth_m(col)])
	else:
		lines.append("Mit „Auswählen (3)“ eine Zelle anklicken.")
	lines.append("")
	lines.append("[b]Lebensbaum[/b] (Excel KR001, %.0f cm)" % (tree_info.get("height_m", 0.0) * 100))
	for mid in tree_info.get("mass", {}):
		lines.append("  %s: %s" % [mid, _fmt_mass(tree_info["mass"][mid])])
	lines.append("  Wurzelbeet: Radius %.1f m (Terrainzellen „Wurzelbeet“, Material Erde)" % tree_info.get("root_bed_radius_m", 0.0))
	lines.append("  Nur Weltobjekt: keine Fortpflanzung, kein Wachstum.")
	_ui_sel.text = "\n".join(lines)
	var ev: Array = []
	var rec := sim.event_log.recent(8)
	rec.reverse()
	for e in rec:
		var col := "#ffcc60" if e["severity"] == "warning" else ("#ff6060" if e["severity"] == "error" else "#ffffff")
		ev.append("[color=%s][t=%.1f s] %s %s[/color]" % [col, e["t"], e["type"], JSON.stringify(e["data"]).left(110)])
	_ui_events.text = "\n".join(ev)


static func _fmt_mass(kg: float) -> String:
	return ("%.2f t" % (kg / 1000.0)) if kg >= 1000.0 else ("%.1f kg" % kg)
