class_name PhysicsLab
extends Node3D
## Sichtbares 3D-Physiklabor. Baut alle Testmodelle per Code (Godot-Grundformen).
## Stationen: A Falltest · B Wärmetest · C Kupfer-Schmelztest · D Masse/Bruch.

const STATION := {
	"A": Vector3(-5.0, 0.0, 0.0),
	"B": Vector3(-1.5, 0.0, 0.0),
	"C": Vector3(1.5, 0.0, 0.0),
	"D": Vector3(4.5, 0.0, 0.0),
}
const FALL_MATERIALS := ["copper", "stone", "wood", "plant_tissue"]
const CRUCIBLE_INNER := Vector2(0.06, 0.06)
const BEAKER_INNER := Vector2(0.08, 0.08)
const HEATER := "melt_heater"
const COOLER := "melt_cooler"

@onready var sim: Simulation = $Simulation
@onready var camera: LabCamera = $LabCamera
@onready var ui: LabUI = $LabUI

var samples_root: Node3D
var bodies: Dictionary = {}          # id -> PhysicalBody
var roles: Dictionary = {}           # Rolle -> id
var contact_keys: Dictionary = {}    # Name -> Kontaktschlüssel
var false_color: bool = false
var selected_id: int = 0
var secondary_id: int = 0
var heater_power_w: float = 1000.0
var heater_enabled: bool = false
var cooling_enabled: bool = false
var load_j: float = 100.0
var fall_released: bool = false
var station_d_initial_mass: float = 0.0
var last_message: String = ""

var _next_spawn: Dictionary = {}
var _child_counter: Dictionary = {}
var _ground: StaticBody3D
var _crucible_floor: Vector3
var _beaker_floor: Vector3
var _contact_mesh: MeshInstance3D
var _contact_labels: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ok := sim.initialize()
	sim.object_added.connect(_on_object_added)
	sim.object_removed.connect(_on_object_removed)
	_build_environment()
	samples_root = Node3D.new()
	samples_root.name = "Proben"
	samples_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(samples_root)
	camera.object_picked.connect(_on_pick)
	ui.setup(self)
	if not ok:
		return
	var lab: Dictionary = sim.settings["lab"]
	heater_power_w = float(lab["heater_power_default_w"])
	load_j = float(lab["load_default_j"])
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, float(sim.settings["gravity_m_s2"]))
	_build_samples()
	view_station("")


# ── Aufbau ───────────────────────────────────────

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.65)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	_ground = StaticBody3D.new()
	_ground.name = "Boden"
	_add_box(_ground, Vector3(16, 0.2, 6), Vector3(0, -0.1, 0), Color(0.32, 0.34, 0.36))
	add_child(_ground)

	for st in STATION:
		var title: String = {"A": "A  Falltest", "B": "B  Wärmetest", "C": "C  Kupfer-Schmelztest", "D": "D  Masse & Bruch"}[st]
		var l := Label3D.new()
		l.text = title
		l.font_size = 48
		l.pixel_size = 0.0025
		l.outline_size = 8
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = STATION[st] + Vector3(0, 0.55 if st != "A" else 3.4, -0.7)
		add_child(l)

	# A: Höhenmarke
	var h: float = float(sim.settings.get("lab", {}).get("drop_height_m", 3.0)) if sim.is_ready() else 3.0
	var pole := StaticBody3D.new()
	pole.name = "Messlatte"
	_add_box(pole, Vector3(0.04, h, 0.04), Vector3(0, h * 0.5, 0), Color(0.85, 0.85, 0.8))
	pole.position = STATION["A"] + Vector3(-1.1, 0, -0.4)
	add_child(pole)
	for m in range(0, int(h) + 1):
		var tick := Label3D.new()
		tick.text = "%d m" % m
		tick.pixel_size = 0.003
		tick.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tick.position = pole.position + Vector3(-0.15, m, 0)
		add_child(tick)

	# C: Heizplatte + Tiegel (Wärmekapazität des Tiegels ist NICHT modelliert)
	var c: Vector3 = STATION["C"]
	var plate := StaticBody3D.new()
	plate.name = "Heizplatte"
	_add_box(plate, Vector3(0.14, 0.02, 0.14), Vector3(0, 0.01, 0), Color(0.25, 0.25, 0.28))
	plate.position = c
	add_child(plate)
	_crucible_floor = c + Vector3(0, 0.028, 0)
	add_child(_make_container("Tiegel", c + Vector3(0, 0.02, 0), CRUCIBLE_INNER, 0.03, 0.008, Color(0.36, 0.34, 0.33), false))

	# B: Becherglas für die Wasserprobe
	var bpos: Vector3 = STATION["B"] + Vector3(0.45, 0, 0)
	_beaker_floor = bpos + Vector3(0, 0.005, 0)
	add_child(_make_container("Becherglas", bpos, BEAKER_INNER, 0.09, 0.005, Color(0.8, 0.9, 1.0, 0.25), true))

	# Kontaktlinien (Überlagerung)
	_contact_mesh = MeshInstance3D.new()
	_contact_mesh.mesh = ImmediateMesh.new()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.85, 0.1)
	lm.no_depth_test = true
	_contact_mesh.material_override = lm
	add_child(_contact_mesh)


func _make_container(cname: String, pos: Vector3, inner: Vector2, height: float, wall: float, col: Color, transparent: bool) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = cname
	sb.position = pos
	_add_box(sb, Vector3(inner.x + 2 * wall, wall, inner.y + 2 * wall), Vector3(0, wall * 0.5, 0), col, transparent)
	var hy := wall + height * 0.5
	_add_box(sb, Vector3(wall, height, inner.y + 2 * wall), Vector3(-(inner.x + wall) * 0.5, hy, 0), col, transparent)
	_add_box(sb, Vector3(wall, height, inner.y + 2 * wall), Vector3((inner.x + wall) * 0.5, hy, 0), col, transparent)
	_add_box(sb, Vector3(inner.x, height, wall), Vector3(0, hy, -(inner.y + wall) * 0.5), col, transparent)
	_add_box(sb, Vector3(inner.x, height, wall), Vector3(0, hy, (inner.y + wall) * 0.5), col, transparent)
	return sb


func _add_box(parent: Node3D, size: Vector3, offset: Vector3, col: Color, transparent: bool = false) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	parent.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = offset
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	parent.add_child(mi)


func _build_samples() -> void:
	var lab: Dictionary = sim.settings["lab"]
	var amb := float(lab["ambient_temperature_k"])
	# A: gleich große Würfel, Masse folgt aus der Dichte
	var e := float(lab["fall_cube_edge_m"])
	var h := float(lab["drop_height_m"])
	for i in FALL_MATERIALS.size():
		var mid: String = FALL_MATERIALS[i]
		var pos: Vector3 = STATION["A"] + Vector3(-0.6 + i * 0.4, h, 0)
		_spawn("fall_" + mid, mid, e * e * e, amb, "A", "Fallwürfel " + sim.materials.get_material(mid).display_name, pos, false, Vector2.ZERO, true)
	# B: warme Kupferprobe, kalte Steinprobe, Wasser im Becherglas
	var b: Vector3 = STATION["B"]
	_spawn("warm", "copper", 0.000125, 363.15, "B", "Warme Probe (Kupfer)", b + Vector3(-0.3, 0.025, 0))
	_spawn("cold", "stone", 0.000125, 278.15, "B", "Kalte Probe (Stein)", b + Vector3(-0.248, 0.025, 0))
	_spawn("water", "water", 0.00025, amb, "B", "Wasserprobe 0,25 L", _beaker_floor, true, BEAKER_INNER)
	var warm := _obj("warm")
	contact_keys["Kupfer–Stein"] = sim.thermal.add_contact(warm, _obj("cold"), 0.0025, "Kupfer–Stein")
	contact_keys["Kupfer–Wasser"] = sim.thermal.add_contact(warm, _obj("water"), 0.0025, "Kupfer–Wasser")
	# C: Kupferprobe im Tiegel
	var me := float(lab["melt_sample_edge_m"])
	_spawn("melt", "copper", me * me * me, amb, "C", "Schmelzprobe (Kupfer)", _crucible_floor, true, CRUCIBLE_INNER)
	sim.thermal.add_heater(HEATER, roles["melt"], heater_power_w)
	sim.thermal.add_sink(COOLER, roles["melt"], float(lab["cooling_power_w"]), float(lab["cooling_sink_temperature_k"]))
	heater_enabled = false
	cooling_enabled = false
	# D: Proben für Teilen, Zusammenführen und Bruch
	var d: Vector3 = STATION["D"]
	_spawn("d_stone", "stone", 0.001, amb, "D", "Steinblock", d + Vector3(-0.5, 0.05, 0))
	_spawn("d_wood", "wood", 0.001, amb, "D", "Holzblock", d + Vector3(0.0, 0.05, 0))
	_spawn("d_plant", "plant_tissue", 0.001, amb, "D", "Pflanzengewebe", d + Vector3(0.5, 0.05, 0))
	station_d_initial_mass = sim.total_mass("D")
	sim.event_log.add("lab_built", [], {"objects": sim.registry.count()})


func _spawn(role: String, material_id: String, volume: float, temp_k: float, station: String, label: String, pos: Vector3, contained: bool = false, inner: Vector2 = Vector2.ZERO, frozen: bool = false) -> void:
	_next_spawn = {"pos": pos, "contained": contained, "inner": inner, "frozen": frozen}
	var obj := sim.create_object(material_id, volume, temp_k, station, label)
	_next_spawn = {}
	if obj != null:
		roles[role] = obj.id


func _obj(role: String) -> PhysicalObject:
	return sim.registry.get_entity(roles.get(role, 0)) as PhysicalObject


func _on_object_added(id: int) -> void:
	var obj: PhysicalObject = sim.registry.get_entity(id) as PhysicalObject
	var info: Dictionary = _next_spawn if not _next_spawn.is_empty() else _derive_spawn(obj)
	var body := PhysicalBody.new()
	body.setup(sim, obj, info["contained"], info["inner"])
	samples_root.add_child(body)
	body.global_position = info["pos"]
	if info.get("frozen", false):
		body.set_frozen_for_test(true)
	body.body_entered.connect(_on_body_contact.bind(id))
	bodies[id] = body


## Platzierung neuer Teile (Fragmente, Teilmengen, Zusammenführung) am Elternobjekt.
func _derive_spawn(obj: PhysicalObject) -> Dictionary:
	var parent_id: int = obj.parent_ids[0] if obj.parent_ids.size() > 0 else 0
	var parent: PhysicalBody = bodies.get(parent_id, null)
	if parent == null:
		return {"pos": STATION.get(obj.station, Vector3.ZERO) + Vector3(0, 0.3, 0.8), "contained": false, "inner": Vector2.ZERO}
	var idx: int = _child_counter.get(parent_id, 0)
	_child_counter[parent_id] = idx + 1
	if parent.contained and idx == 0:
		return {"pos": parent.global_position, "contained": true, "inner": parent.container_inner}
	var base := parent.label_anchor()
	if parent.contained:
		base = parent.global_position + Vector3(0.2, 0.0, 0.0)
	var off := Vector3((idx - 0.5) * 0.14, 0.12 + idx * 0.04, 0.0)
	if obj.origin == "merge":
		off = Vector3(0, 0.15, 0)
	return {"pos": base + off, "contained": false, "inner": Vector2.ZERO}


func _on_object_removed(id: int) -> void:
	if bodies.has(id):
		var b: PhysicalBody = bodies[id]
		bodies.erase(id)
		if b.get_parent() != null:
			b.get_parent().remove_child(b)
		b.queue_free()
	if selected_id == id:
		selected_id = 0
	if secondary_id == id:
		secondary_id = 0


# ── Bedienung ────────────────────────────────────

## Kamera-Schnellansichten. "" = Übersicht.
func view_station(st: String) -> void:
	var views := {
		"": [Vector3(0.0, 0.3, 0.0), 7.5, -0.38],
		"A": [STATION["A"] + Vector3(-0.1, 1.4, 0), 4.2, -0.12],
		"B": [STATION["B"] + Vector3(0.05, 0.03, 0), 1.0, -0.5],
		"C": [_crucible_floor, 0.42, -0.95],
		"D": [STATION["D"] + Vector3(0, 0.05, 0), 1.9, -0.45],
	}
	var v: Array = views.get(st, views[""])
	camera.target = v[0]
	camera.distance = v[1]
	camera.pitch = v[2]
	camera.yaw = 0.0
	camera._apply()


func toggle_pause() -> void:
	sim.set_paused(not sim.is_paused())


func reset_lab() -> void:
	if not sim.is_ready():
		return
	selected_id = 0
	secondary_id = 0
	fall_released = false
	for b in bodies.values():
		if b.get_parent() != null:
			b.get_parent().remove_child(b)
		b.free()
	bodies.clear()
	roles.clear()
	contact_keys.clear()
	_child_counter.clear()
	for l in _contact_labels.values():
		l.queue_free()
	_contact_labels.clear()
	sim.reset_world()
	_build_samples()
	last_message = "Labor zurückgesetzt (Durchgang %d)." % sim.generation


func start_fall_test() -> void:
	if fall_released:
		last_message = "Falltest läuft bereits – zum Wiederholen Labor zurücksetzen."
		return
	fall_released = true
	var t := sim.clock.sim_time_s
	for mid in FALL_MATERIALS:
		var b: PhysicalBody = bodies.get(roles.get("fall_" + mid, 0), null)
		if b != null:
			b.fall_release_time = t
			b.set_frozen_for_test(false)
	sim.event_log.add("fall_test_started", [], {"height_m": sim.settings["lab"]["drop_height_m"]})


func expected_fall_time() -> float:
	var lab: Dictionary = sim.settings["lab"]
	var dist := float(lab["drop_height_m"]) - float(lab["fall_cube_edge_m"]) * 0.5
	return sqrt(2.0 * dist / float(sim.settings["gravity_m_s2"]))


func _on_body_contact(other: Node, id: int) -> void:
	var b: PhysicalBody = bodies.get(id, null)
	if b == null or b.fall_release_time < 0.0 or b.fall_time_s >= 0.0:
		return
	if other == _ground:
		b.fall_time_s = sim.clock.sim_time_s - b.fall_release_time
		var obj := sim.registry.get_entity(id) as PhysicalObject
		sim.event_log.add("fall_landed", [id], {"material": obj.material_id, "mass_kg": obj.mass_kg, "fall_time_s": b.fall_time_s, "expected_s": expected_fall_time()})


func toggle_contact(cname: String) -> void:
	var key: String = contact_keys.get(cname, "")
	if key == "" or not sim.thermal.contacts.has(key):
		last_message = "Kontakt %s nicht verfügbar (eine Probe wurde entfernt). Labor zurücksetzen." % cname
		return
	sim.thermal.set_contact_enabled(key, not sim.thermal.contacts[key]["enabled"])


func contact_enabled(cname: String) -> bool:
	var key: String = contact_keys.get(cname, "")
	return key != "" and sim.thermal.contacts.has(key) and sim.thermal.contacts[key]["enabled"]


func set_heater_power(w: float) -> void:
	heater_power_w = clampf(w, 0.0, float(sim.settings["lab"]["heater_power_max_w"]))
	sim.thermal.set_heater(HEATER, heater_enabled, heater_power_w)


func toggle_heater() -> void:
	heater_enabled = not heater_enabled
	sim.thermal.set_heater(HEATER, heater_enabled, heater_power_w)


func toggle_cooling() -> void:
	cooling_enabled = not cooling_enabled
	sim.thermal.set_sink(COOLER, cooling_enabled)


func retarget_thermal_to_selection() -> void:
	if selected_id == 0:
		last_message = "Erst eine Probe auswählen."
		return
	sim.thermal.retarget(HEATER, selected_id)
	sim.thermal.retarget(COOLER, selected_id)
	last_message = "Heizung und Kühlung wirken jetzt auf #%d." % selected_id


func toggle_environment() -> void:
	sim.thermal.environment_enabled = not sim.thermal.environment_enabled
	sim.event_log.add("environment_exchange_on" if sim.thermal.environment_enabled else "environment_exchange_off", [], {})


func toggle_false_color() -> void:
	false_color = not false_color


func apply_load_to_selection() -> void:
	if selected_id == 0:
		last_message = "Erst eine Probe auswählen."
		return
	var r := sim.damage.apply_load(sim, selected_id, load_j)
	match r["status"]:
		"rejected":
			last_message = "Abgewiesen: " + r["message"]
		"damaged":
			last_message = "Laboreingriff %.0f J: Schaden jetzt %.0f %%." % [load_j, r["damage"] * 100.0]
		"deformed":
			last_message = "Laboreingriff %.0f J: Probe verformt (duktil, kein Bruch)." % load_j
		"fractured":
			last_message = "Laboreingriff %.0f J: zerbrochen in %d Teile, Masse %.6f → %.6f kg." % [load_j, r["fragment_ids"].size(), r["mass_before_kg"], r["mass_after_kg"]]


func split_selection(fraction: float) -> void:
	if selected_id == 0:
		last_message = "Erst eine Probe auswählen."
		return
	var r := sim.processes.split(sim, selected_id, fraction)
	last_message = ("Geteilt in #%d und #%d." % [r["ids"][0], r["ids"][1]]) if r["ok"] else "Abgewiesen: " + r["message"]


func merge_selection() -> void:
	if selected_id == 0 or secondary_id == 0:
		last_message = "Für Laboroperation Zusammenführen: Probe anklicken, zweite Probe mit Umschalt+Klick wählen."
		return
	var r := sim.processes.merge(sim, selected_id, secondary_id)
	if r["ok"]:
		last_message = "Laboroperation: zu #%d zusammengeführt." % r["id"]
		selected_id = r["id"]
	else:
		last_message = "Abgewiesen: " + r["message"]


func write_snapshot() -> String:
	var transforms := {}
	for id in bodies:
		var b: PhysicalBody = bodies[id]
		transforms[id] = {
			"position": [b.global_position.x, b.global_position.y, b.global_position.z],
			"linear_velocity": [b.linear_velocity.x, b.linear_velocity.y, b.linear_velocity.z],
			"contained": b.contained,
		}
	var snap := WorldState.capture(sim, transforms)
	var path := "user://lab_snapshot.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_message = "Schnappschuss konnte nicht geschrieben werden."
		return ""
	f.store_string(JSON.stringify(snap, "  "))
	f.close()
	last_message = "Schnappschuss geschrieben: " + ProjectSettings.globalize_path(path)
	return path


func _on_pick(origin: Vector3, direction: Vector3, additive: bool) -> void:
	var best_id := 0
	var best_t := INF
	for id in bodies:
		var t: float = bodies[id].ray_hit_distance(origin, direction)
		if t > 0.0 and t < best_t:
			best_t = t
			best_id = id
	if additive:
		if best_id != 0 and best_id != selected_id:
			secondary_id = best_id
	else:
		selected_id = best_id
		if secondary_id == best_id:
			secondary_id = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				toggle_pause()
			KEY_R:
				reset_lab()
			KEY_F:
				toggle_false_color()
			KEY_C:
				if bodies.has(selected_id):
					camera.focus_on(bodies[selected_id].label_anchor())
			KEY_ESCAPE:
				selected_id = 0
				secondary_id = 0
			KEY_0:
				view_station("")
			KEY_1:
				view_station("A")
			KEY_2:
				view_station("B")
			KEY_3:
				view_station("C")
			KEY_4:
				view_station("D")
			_:
				return
		get_viewport().set_input_as_handled()


# ── Darstellung ──────────────────────────────────

func _process(_delta: float) -> void:
	for id in bodies:
		bodies[id].refresh_visual(false_color, id == selected_id, id == secondary_id)
	_draw_contacts()


func _draw_contacts() -> void:
	var im: ImmediateMesh = _contact_mesh.mesh
	im.clear_surfaces()
	var lines: Array = []
	var idx := 0
	for cname in contact_keys:
		idx += 1
		var key: String = contact_keys[cname]
		var lbl: Label3D = _contact_labels.get(cname, null)
		if lbl == null:
			lbl = Label3D.new()
			lbl.pixel_size = 0.0012
			lbl.font_size = 28
			lbl.outline_size = 6
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.modulate = Color(1.0, 0.9, 0.3)
			add_child(lbl)
			_contact_labels[cname] = lbl
		if not sim.thermal.contacts.has(key) or not sim.thermal.contacts[key]["enabled"]:
			lbl.visible = false
			continue
		var c: Dictionary = sim.thermal.contacts[key]
		var ba: PhysicalBody = bodies.get(c["a"], null)
		var bb: PhysicalBody = bodies.get(c["b"], null)
		if ba == null or bb == null:
			lbl.visible = false
			continue
		var pa := ba.label_anchor() + Vector3(0, 0.06, 0)
		var pb := bb.label_anchor() + Vector3(0, 0.06, 0)
		lines.append([pa, pb])
		lbl.visible = true
		lbl.position = pb + Vector3(0, 0.05, 0)  # Beschriftung über dem Kontaktpartner, damit sie sich nicht überlagern
		lbl.text = "Wärmekontakt %s\nG = %.3f W/K · %.2f W" % [cname, c["conductance_w_k"], absf(c["last_flow_w"])]
	if lines.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in lines:
		im.surface_add_vertex(l[0])
		im.surface_add_vertex(l[1])
	im.surface_end()


## Falschfarbe (reine Darstellungsüberlagerung), zweiteilige Skala:
## 273 K blau → 400 K grün (feine Auflösung für Raumtemperaturversuche)
## 400 K → 1400 K rot (Schmelzversuch).
static func temperature_color(t_k: float) -> Color:
	var x: float
	if t_k < 400.0:
		x = 0.5 * clampf((t_k - 273.15) / (400.0 - 273.15), 0.0, 1.0)
	else:
		x = 0.5 + 0.5 * clampf((t_k - 400.0) / 1000.0, 0.0, 1.0)
	return Color.from_hsv((1.0 - x) * 0.66, 0.85, 1.0)
