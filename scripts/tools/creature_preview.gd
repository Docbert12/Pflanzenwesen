class_name CreaturePreview
extends Node3D
## Kreaturenvorschau: Einzelansicht mit Reglern und Körperveränderungen, 10 Varianten,
## 50 Figuren als Darstellungs- und Leistungstest. Die Figuren sind KEINE lebende
## Bevölkerung (kein Hunger, kein Gedächtnis, keine KI).

const SAVE_DIR := "user://creature_configs"
const SAVE_PATH := "user://creature_configs/kreatur.json"
const PERF_PATH := "user://perf_50_figuren.json"

@onready var sim: Simulation = $Simulation
@onready var camera: LabCamera = $LabCamera

var db := DefinitionDB.new()
var voxel_size: float = 0.02
var view_mode: String = "single"
var base_seed: int = 1001
var overrides: Dictionary = {}
var plan: BodyPlan
var views: Array = []                # CreatureView
var side: String = "l"
var prosthesis_material: String = "wood"
var last_message: String = ""
var perf: Dictionary = {}
var errors: Array = []

var _figures_root: Node3D
var _ui_info: RichTextLabel
var _ui_msg: Label
var _ui_anim: Label
var _seed_box: SpinBox
var _sliders: Dictionary = {}
var _color_opt: OptionButton
var _shape_opt: OptionButton
var _single_controls: Array = []
var _accum := 0.0
var _perf_frames: Array = []
var _perf_written := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sim.initialize()
	if not db.load_all():
		errors.append_array(db.errors)
	voxel_size = float(db.config("world").get("voxel_sizes_m", {}).get("creature", 0.02))
	_build_env()
	_figures_root = Node3D.new()
	_figures_root.name = "Figuren"
	_figures_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_figures_root)
	_build_ui()
	if not sim.is_ready() or not errors.is_empty():
		_ui_info.text = "[color=#ff6060]Fehler:[/color]\n" + "\n".join(sim.init_errors + errors)
		return
	show_single(base_seed)


# ── Ansichten ─────────────────────────────────────

func _clear_figures() -> void:
	for v in views:
		if v.plan != null and v.plan.id != 0:
			sim.remove_object(v.plan.id)   # Entität aus dem Register entfernen
		v.queue_free()
	views.clear()


func _spawn(p: BodyPlan, pos: Vector3, phase: float = 0.0) -> CreatureView:
	sim.add_entity(p, "creature_preview")
	var v := CreatureGenerator.build_view(p, sim.materials, voxel_size)
	v.position = pos
	v.animator.phase_offset = phase
	_figures_root.add_child(v)
	views.append(v)
	return v


func show_single(seed_value: int, keep_overrides: bool = false) -> void:
	view_mode = "single"
	base_seed = seed_value
	if not keep_overrides:
		overrides.clear()
	_clear_figures()
	plan = CreatureGenerator.generate(base_seed, db, overrides)
	_spawn(plan, Vector3.ZERO)
	_sync_controls()
	_set_camera(Vector3(0, 0.45, 0), 2.2, -0.15)
	for c in _single_controls:
		c.visible = true
	last_message = "Startwert %d erzeugt." % base_seed


func show_variants(count: int) -> void:
	view_mode = "ten" if count == 10 else "fifty"
	_clear_figures()
	var t0 := Time.get_ticks_usec()
	var cols := 10
	for i in count:
		var p := CreatureGenerator.generate(base_seed + i, db)
		var row := i / cols
		var col := i % cols
		var v := _spawn(p, Vector3((col - (cols - 1) * 0.5) * 0.85, 0, -row * 1.1), i * 0.37)
		if count == 50:
			v.animator.request("walk" if i % 2 == 0 else "idle")
		var lbl := Label3D.new()
		lbl.text = str(base_seed + i)
		lbl.pixel_size = 0.004
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.15, 0)
		v.add_child(lbl)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	plan = views[0].plan
	for c in _single_controls:
		c.visible = false
	if count == 10:
		_set_camera(Vector3(0.6, 0.5, 0), 5.2, -0.1)
		last_message = "10 Varianten, Startwerte %d–%d (gestalterische Kontrolle)." % [base_seed, base_seed + 9]
	else:
		_set_camera(Vector3(0, 0.4, -2.2), 9.5, -0.45)
		last_message = "50 Figuren erzeugt in %.0f ms (Darstellungs- und Leistungstest, keine lebende Bevölkerung)." % build_ms
		_start_perf(build_ms)


func _start_perf(build_ms: float) -> void:
	var voxels := 0
	var meshes := 0
	var areas := 0
	for v in views:
		voxels += v.voxel_count
		meshes += v.meshes.size()
		areas += v.areas.size()
	perf = {"figures": views.size(), "build_ms": build_ms, "mesh_instances": meshes, "collision_areas": areas,
		"voxels_total": voxels, "voxel_size_m": voxel_size, "renderer": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info()["string"],
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "window": [get_viewport().size.x, get_viewport().size.y]}
	_perf_frames.clear()
	_perf_written = false


func _set_camera(target: Vector3, dist: float, pitch: float) -> void:
	camera.target = target
	camera.distance = dist
	camera.pitch = pitch
	camera.yaw = 0.35
	camera._apply()


## Nach Körperänderung: Darstellung, Kollision und Animation aus dem Plan neu aufbauen.
func _refresh_body(msg: String) -> void:
	last_message = msg
	if views.is_empty():
		return
	var v: CreatureView = views[0]
	var prev_state := v.animator.state
	var prev_side := v.animator.side
	v.rebuild()
	var r := v.animator.request(prev_state, prev_side)
	if not r["ok"]:
		v.animator.request("idle")
		last_message += " Animation „%s“ beendet: %s" % [prev_state, r["message"]]


# ── Bedienaktionen (auch von Tests aufgerufen) ────

func set_gene(key: String, value) -> void:
	overrides[key] = value
	show_single(base_seed, true)
	last_message = "Gen „%s“ geändert – Körper neu erzeugt (Veränderungen wie Prothesen wurden zurückgesetzt)." % key


func remove_forearm() -> Dictionary:
	var r := plan.remove_forearm(side)
	if r["ok"]:
		_refresh_body("Entfernt: %s." % ", ".join(r["removed"]))
	else:
		last_message = r["message"]
	return r


func attach_prosthesis() -> Dictionary:
	var r := plan.attach_prosthesis(side, prosthesis_material, sim.materials)
	if r["ok"]:
		_refresh_body("Prothese %s (%s) angebracht." % [r["id"], sim.materials.get_material(prosthesis_material).display_name])
	else:
		last_message = r["message"]
	return r


func add_leaf() -> Dictionary:
	var r := plan.add_leaf()
	if r["ok"]:
		_refresh_body("Blatt %s hinzugefügt." % r["id"])
	else:
		last_message = r["message"]
	return r


func remove_leaf() -> Dictionary:
	var r := plan.remove_leaf()
	if r["ok"]:
		_refresh_body("Blatt %s entfernt." % r["removed"][0])
	else:
		last_message = r["message"]
	return r


func play(anim: String) -> Dictionary:
	if views.is_empty():
		return {"ok": false}
	var r: Dictionary = views[0].animator.request(anim, "l" if side == "l" else "r")
	last_message = r["message"]
	return r


func save_config(path: String = SAVE_PATH) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_message = "Speichern fehlgeschlagen: %s" % path
		return false
	f.store_string(JSON.stringify(plan.to_dict(), "  "))
	f.close()
	last_message = "Gespeichert: " + ProjectSettings.globalize_path(path)
	return true


func load_config(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		last_message = "Keine gespeicherte Konfiguration unter %s." % ProjectSettings.globalize_path(path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	var r := BodyPlan.from_dict(data, sim.materials)
	if not r["ok"]:
		last_message = "Laden abgewiesen: " + "; ".join(r["errors"])
		return false
	view_mode = "single"
	_clear_figures()
	plan = r["plan"]
	base_seed = plan.plan_seed
	_spawn(plan, Vector3.ZERO)
	for c in _single_controls:
		c.visible = true
	_sync_controls()
	last_message = "Geladen: " + ProjectSettings.globalize_path(path)
	return true


# ── Aufbau ───────────────────────────────────────

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.38, 0.41)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.85)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.light_energy = 0.95
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.35
	add_child(fill)
	# Boden mit 10-cm-Raster
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 8)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.31, 0.33)
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0, -0.001, -2)
	add_child(floor_mi)
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-10, 11):
		var x := i * 0.1
		im.surface_add_vertex(Vector3(x, 0.001, -1.0))
		im.surface_add_vertex(Vector3(x, 0.001, 1.0))
		im.surface_add_vertex(Vector3(-1.0, 0.001, x))
		im.surface_add_vertex(Vector3(1.0, 0.001, x))
	im.surface_end()
	grid.mesh = im
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.32, 0.32, 0.34)
	grid.material_override = gm
	add_child(grid)
	# Größenreferenz: 1-m-Stab mit Marken alle 10 cm
	var pole := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.015, 1.0, 0.015)
	pole.mesh = bm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.9, 0.3)
	pole.material_override = pmat
	pole.position = Vector3(-0.45, 0.5, 0)
	add_child(pole)
	for i in range(0, 11):
		var tick := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.06 if i % 5 == 0 else 0.035, 0.004, 0.004)
		tick.mesh = tb
		tick.material_override = pmat
		tick.position = Vector3(-0.45 + 0.025, i * 0.1, 0)
		add_child(tick)
		if i % 5 == 0:
			var l := Label3D.new()
			l.text = "%.1f m" % (i * 0.1)
			l.pixel_size = 0.0015
			l.position = Vector3(-0.53, i * 0.1, 0)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(l)


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
	left.offset_right = 400
	left.anchor_bottom = 1.0
	left.offset_bottom = -10
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	Nav.back_button(v, self)
	_header(v, "Ansicht")
	var vr := HBoxContainer.new()
	v.add_child(vr)
	Nav.button(vr, "Einzeln", func(): show_single(base_seed))
	Nav.button(vr, "10 Varianten", func(): show_variants(10))
	Nav.button(vr, "50 Figuren (Test)", func(): show_variants(50))
	var sr := HBoxContainer.new()
	v.add_child(sr)
	Nav.label(sr, "Startwert:", 13, false)
	_seed_box = SpinBox.new()
	_seed_box.max_value = 2147483647
	_seed_box.value = base_seed
	_seed_box.custom_minimum_size = Vector2(120, 0)
	sr.add_child(_seed_box)
	Nav.button(sr, "Erzeugen", _on_seed_generate)
	Nav.button(sr, "Zufall", _on_seed_random)
	var single := VBoxContainer.new()
	v.add_child(single)
	_single_controls.append(single)
	_header(single, "Körperparameter (innerhalb sinnvoller Grenzen)")
	_slider(single, "height_m", "Größe", 0.6, 1.1, 0.01, "m")
	_slider(single, "torso_ratio", "Rumpfproportion", 0.85, 1.15, 0.01, "×")
	_slider(single, "arm_factor", "Armlänge", 0.85, 1.15, 0.01, "×")
	_slider(single, "leg_factor", "Beinlänge", 0.85, 1.15, 0.01, "×")
	var cr := HBoxContainer.new()
	single.add_child(cr)
	Nav.label(cr, "Körperfarbe:", 13, false)
	_color_opt = OptionButton.new()
	_color_opt.focus_mode = Control.FOCUS_NONE
	for pid in db.config("creature_defaults").get("variation", {}).get("skin_palette_ids", ["F001", "F002", "F005"]):
		var e := db.get_def("palettes", pid)
		_color_opt.add_item("%s (%s, Excel %s)" % [e.get("name", pid), e.get("color", "?"), pid])
		_color_opt.set_item_metadata(_color_opt.item_count - 1, pid)
	_color_opt.item_selected.connect(_on_color_selected)
	cr.add_child(_color_opt)
	var lr := HBoxContainer.new()
	single.add_child(lr)
	Nav.label(lr, "Blattform:", 13, false)
	_shape_opt = OptionButton.new()
	_shape_opt.focus_mode = Control.FOCUS_NONE
	for s in CreatureGenerator.LEAF_SHAPES:
		_shape_opt.add_item(s)
	_shape_opt.item_selected.connect(func(i): set_gene("leaf_shape", CreatureGenerator.LEAF_SHAPES[i]))
	lr.add_child(_shape_opt)
	_header(single, "Körperveränderungen")
	var sd := HBoxContainer.new()
	single.add_child(sd)
	Nav.label(sd, "Seite:", 13, false)
	var side_opt := OptionButton.new()
	side_opt.focus_mode = Control.FOCUS_NONE
	side_opt.add_item("links")
	side_opt.add_item("rechts")
	side_opt.item_selected.connect(func(i): side = "l" if i == 0 else "r")
	sd.add_child(side_opt)
	Nav.button(sd, "Unterarm entfernen", remove_forearm)
	var pr := HBoxContainer.new()
	single.add_child(pr)
	Nav.label(pr, "Prothese:", 13, false)
	var pm_opt := OptionButton.new()
	pm_opt.focus_mode = Control.FOCUS_NONE
	pm_opt.add_item("Holz (Stütze)")
	pm_opt.add_item("Kupfer (Haken)")
	pm_opt.item_selected.connect(func(i): prosthesis_material = "wood" if i == 0 else "copper")
	pr.add_child(pm_opt)
	Nav.button(pr, "Anbringen", attach_prosthesis)
	var lf := HBoxContainer.new()
	single.add_child(lf)
	Nav.button(lf, "Blatt +", add_leaf)
	Nav.button(lf, "Blatt −", remove_leaf)
	Nav.button(lf, "Körper zurücksetzen", func(): show_single(base_seed, true))
	_header(single, "Animation (Vorschau, keine Handlung)")
	var ar := HBoxContainer.new()
	single.add_child(ar)
	Nav.button(ar, "Ruhe", func(): play("idle"))
	Nav.button(ar, "Gehen", func(): play("walk"))
	Nav.button(ar, "Greifen", func(): play("grasp"))
	Nav.button(ar, "Zum Mund", func(): play("eat"))
	# Prompt 6B: Arbeitsposen als Vorführung (zyklisch, ohne Handlung und ohne Gegenstand; Ziel 30 cm vor dem Wesen)
	var wr := HBoxContainer.new()
	single.add_child(wr)
	for pair in [["Schlagen", "strike"], ["Einsetzen", "place"], ["Ablegen 2H", "put_down_two"], ["Verbinden", "assemble"], ["Verbinden 1H", "assemble_one"], ["Gießen", "pour"], ["Graben", "dig"]]:
		var an: String = pair[1]
		Nav.button(wr, pair[0], func(): play(an))
	_ui_anim = Nav.label(single, "", 12)
	_ui_anim.modulate = Color(0.8, 0.95, 1)
	_header(single, "Speichern / Laden")
	var sl := HBoxContainer.new()
	single.add_child(sl)
	Nav.button(sl, "Speichern", func(): save_config())
	Nav.button(sl, "Laden", func(): load_config())
	var hints := Nav.label(v, "Maus: rechts ziehen = drehen · Mitte/Umschalt+rechts = verschieben · Rad = zoomen\nTasten: WASD/QE bewegen · Leertaste Pause der Animation\nGreifen/Zum Mund nutzen die bei „Seite“ gewählte Hand; fehlt sie, wird die andere Seite verwendet oder die Animation abgelehnt.\nArbeitsposen (Prompt 6B) laufen hier als Vorführung ohne Handlung; im Spiel steuert die Handlung Phase und Ziel. Graben ist vorbereitet, aber abgewiesen.", 12)
	hints.modulate = Color(0.8, 0.85, 0.9)
	var right := Nav.panel(root)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -470
	right.offset_right = -10
	right.offset_top = 10
	right.anchor_bottom = 1.0
	right.offset_bottom = -10
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rs)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(rv)
	_ui_msg = Nav.label(rv, "", 13)
	_ui_msg.modulate = Color(0.6, 1, 0.6)
	_ui_info = RichTextLabel.new()
	_ui_info.bbcode_enabled = true
	_ui_info.fit_content = true
	_ui_info.custom_minimum_size = Vector2(440, 0)
	_ui_info.add_theme_font_size_override("normal_font_size", 12)
	_ui_info.add_theme_font_size_override("bold_font_size", 12)
	rv.add_child(_ui_info)


func _on_seed_generate() -> void:
	if view_mode == "single":
		show_single(int(_seed_box.value))
	else:
		_apply_seed_multi()


func _on_seed_random() -> void:
	_seed_box.set_value_no_signal(randi() % 100000)
	show_single(int(_seed_box.value))


## Excel-Farbe gewählt: Haut- und davon abgeleitete Blattfarbe setzen (gekoppelt).
func _on_color_selected(i: int) -> void:
	var pid: String = _color_opt.get_item_metadata(i)
	overrides["skin_palette_id"] = pid
	overrides["skin_color"] = db.palette_color(pid).to_html(false)
	overrides["leaf_color"] = db.palette_color(pid).lightened(0.2).to_html(false)
	show_single(base_seed, true)
	last_message = "Körperfarbe Excel %s gewählt." % pid


func _apply_seed_multi() -> void:
	base_seed = int(_seed_box.value)
	show_variants(10 if view_mode == "ten" else 50)


func _header(parent: Control, text: String) -> void:
	var l := Nav.label(parent, text, 15)
	l.modulate = Color(0.75, 0.9, 1)


func _slider(parent: Control, key: String, title: String, lo: float, hi: float, stp: float, unit: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Nav.label(row, title, 12, false)
	l.custom_minimum_size = Vector2(110, 0)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = stp
	s.custom_minimum_size = Vector2(170, 0)
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var val := Nav.label(row, "", 12, false)
	s.value_changed.connect(func(x): val.text = "%.2f %s" % [x, unit])
	s.drag_ended.connect(func(_changed): set_gene(key, s.value))
	_sliders[key] = s


func _sync_controls() -> void:
	if plan == null:
		return
	for k in _sliders:
		(_sliders[k] as HSlider).set_value_no_signal(float(plan.genes.get(k, 1.0)))
		(_sliders[k] as HSlider).value_changed.emit(float(plan.genes.get(k, 1.0)))
	_seed_box.set_value_no_signal(base_seed)
	var idx := CreatureGenerator.LEAF_SHAPES.find(str(plan.genes.get("leaf_shape", "rund")))
	_shape_opt.select(maxi(idx, 0))
	for i in _color_opt.item_count:
		if _color_opt.get_item_metadata(i) == plan.genes.get("skin_palette_id", ""):
			_color_opt.select(i)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		sim.set_paused(not sim.is_paused())
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if view_mode == "fifty" and not perf.is_empty():
		_perf_frames.append(delta)
		if _perf_frames.size() == 180 and not _perf_written:
			_finish_perf()
	_accum += delta
	if _accum < 0.2:
		return
	_accum = 0.0
	_refresh_ui()


func _finish_perf() -> void:
	var s := 0.0
	var worst := 0.0
	for d in _perf_frames:
		s += d
		worst = maxf(worst, d)
	perf["frames_measured"] = _perf_frames.size()
	perf["avg_frame_ms"] = s / _perf_frames.size() * 1000.0
	perf["worst_frame_ms"] = worst * 1000.0
	perf["fps_engine"] = Engine.get_frames_per_second()
	perf["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	perf["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	perf["objects_in_frame"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	perf["static_memory_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	perf["note"] = "Gemessen über 180 Bilder nach dem Aufbau. Keine Simulation, keine KI; nur Darstellung + Animation."
	var f := FileAccess.open(PERF_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(perf, "  "))
		f.close()
	_perf_written = true


func _refresh_ui() -> void:
	_ui_msg.text = last_message
	if plan == null:
		return
	if _ui_anim and not views.is_empty():
		_ui_anim.text = "Animation: %s · %s" % [views[0].animator.state, views[0].animator.message]
	var L: Array = []
	if view_mode != "single":
		L.append("[b]%s[/b] · Startwerte ab %d · Entitäten im Register: %d" % ["10 Varianten" if view_mode == "ten" else "50 Figuren (Leistungstest)", base_seed, sim.registry.count()])
		if view_mode == "fifty":
			for k in ["figures", "build_ms", "mesh_instances", "collision_areas", "voxels_total", "avg_frame_ms", "worst_frame_ms", "fps_engine", "draw_calls", "primitives", "static_memory_mb", "renderer", "video_adapter", "godot", "cpu"]:
				if perf.has(k):
					L.append("%s: %s" % [k, ("%.2f" % perf[k]) if typeof(perf[k]) == TYPE_FLOAT else str(perf[k])])
			if _perf_written:
				L.append("Messung gespeichert: %s" % ProjectSettings.globalize_path(PERF_PATH))
			else:
				L.append("Messung läuft (%d/180 Bilder) …" % _perf_frames.size())
		L.append("")
		L.append("Diese Figuren sind keine Bevölkerung: kein Hunger, kein Gedächtnis, keine KI.")
		_ui_info.text = "\n".join(L)
		return
	var g := plan.genes
	var caps := plan.capabilities()
	L.append("[b]Pflanzenwesen (Excel %s)[/b] · Startwert [b]%d[/b] · Entität #%d" % [plan.species_id, plan.plan_seed, plan.id])
	L.append("Größe %.0f cm · Rumpf ×%.2f · Arme ×%.2f · Beine ×%.2f" % [float(g["height_m"]) * 100.0, g["torso_ratio"], g["arm_factor"], g["leg_factor"]])
	L.append("Farbe %s (Excel %s) · Blattform %s · Blätter %d" % [g["skin_color"], g.get("skin_palette_id", "?"), g["leaf_shape"], caps["leaves"]])
	L.append("[b]Gesamtmasse %.3f kg[/b] (Modellvolumen · Dichte)" % plan.total_mass(sim.materials))
	L.append("Kann: Gehen %s · Greifen L %s / R %s" % ["ja" if caps["walk"] else "nein", _cap(caps["grasp"]["l"]), _cap(caps["grasp"]["r"])])
	var v: CreatureView = views[0] if not views.is_empty() else null
	L.append("")
	L.append("[b]Körperteile[/b] (Masse · Modellvol. · Voxelvol. · Material · Status)")
	for pid in plan.order:
		var p: Dictionary = plan.parts[pid]
		var st: String = p["status"]
		var eff := plan.is_present(pid)
		var col := "#ffffff" if eff else "#888888"
		if st == "replaced":
			col = "#d0a060"
		var geo: float = v.geometric_volume.get(pid, 0.0) if v != null else 0.0
		L.append("[color=%s]%s · %s · %.3f kg · %.0f cm³ · %s · %s · %s[/color]" % [col, pid, p["type"],
			plan.part_mass(pid, sim.materials) if eff else 0.0, plan.model_volume(pid) * 1e6,
			("%.0f cm³" % (geo * 1e6)) if eff else "–", p["material_id"], _status_de(st, eff)])
	if v != null:
		L.append("")
		L.append("Darstellung: %d Netze, %d Voxel à %.0f mm · Kollision: %d Quader" % [v.meshes.size(), v.voxel_count, voxel_size * 1000.0, v.areas.size()])
	_ui_info.text = "\n".join(L)


static func _cap(c: String) -> String:
	return {"hand": "Hand", "hook": "Haken"}.get(c, "nein")


func _status_de(st: String, eff: bool) -> String:
	if st == "present" and not eff:
		return "hängt an entferntem Teil"
	return {"present": "vorhanden", "removed": "entfernt", "replaced": "ersetzt"}.get(st, st)
