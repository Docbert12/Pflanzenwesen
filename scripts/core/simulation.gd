class_name Simulation
extends Node
## Zentrale Koordination der Simulation.
## Initialisierungsreihenfolge (fest, siehe docs/architecture.md):
##   1 Einstellungen  2 Uhr  3 Ereignisprotokoll  4 Objektregister
##   5 Materialien    6 Physiksysteme  7 Zufallsgenerator (Startwert)
## Ein zweiter initialize()-Aufruf wird ignoriert (keine doppelte Initialisierung).
## Schritt: läuft in _physics_process mit Godots festem Physiktakt; bei Pause
## stoppt sowohl Godots Körperphysik (SceneTree.paused) als auch diese Simulation.

signal object_added(id: int)
signal object_removed(id: int)
signal world_reset(generation: int)

const DEFAULT_SETTINGS_PATH := "res://data/settings/simulation.json"
const DEFAULT_MATERIALS_DIR := "res://data/materials"
const SUPPORTED_SETTINGS_SCHEMA := 1

var settings: Dictionary = {}
var clock: SimulationClock
var event_log: EventLog
var registry: EntityRegistry
var materials: MaterialRegistry
var thermal: ThermalSystem
var phases: PhaseChangeSystem
var damage: DamageSystem
var processes: MaterialProcessSystem
var rng := RandomNumberGenerator.new()
var init_errors: Array = []
var init_order: Array = []
var generation: int = 0
var _initialized := false


func is_initialized() -> bool:
	return _initialized


func is_ready() -> bool:
	return _initialized and init_errors.is_empty()


func initialize(settings_path: String = DEFAULT_SETTINGS_PATH, materials_dir: String = DEFAULT_MATERIALS_DIR) -> bool:
	if _initialized:
		push_warning("Simulation.initialize(): bereits initialisiert – Aufruf ignoriert.")
		return init_errors.is_empty()
	_initialized = true
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# 1 Einstellungen
	var loaded := JsonUtil.load_json(settings_path)
	if not loaded["ok"]:
		init_errors.append(loaded["error"])
		settings = {}
	else:
		var errs := validate_settings(loaded["data"])
		init_errors.append_array(errs)
		settings = loaded["data"] if errs.is_empty() else {}
	init_order.append("settings")
	# 2 Uhr
	clock = SimulationClock.new()
	init_order.append("clock")
	# 3 Ereignisprotokoll
	event_log = EventLog.new(clock, int(settings.get("event_log_max_entries", 300)))
	init_order.append("event_log")
	# 4 Objektregister
	registry = EntityRegistry.new()
	registry.entity_registered.connect(func(id): object_added.emit(id))
	registry.entity_unregistered.connect(func(id): object_removed.emit(id))
	init_order.append("registry")
	# 5 Materialien
	materials = MaterialRegistry.new()
	if not materials.load_directory(materials_dir):
		for e in materials.errors:
			init_errors.append("Material: " + e)
	init_order.append("materials")
	# 6 Physiksysteme
	thermal = ThermalSystem.new(event_log)
	var lab: Dictionary = settings.get("lab", {})
	thermal.ambient_temperature_k = float(lab.get("ambient_temperature_k", 293.15))
	thermal.environment_enabled = bool(lab.get("environment_exchange_enabled", true))
	thermal.convection_coefficient = float(lab.get("convection_coefficient_w_m2k", 10.0))
	phases = PhaseChangeSystem.new()
	damage = DamageSystem.new()
	processes = MaterialProcessSystem.new()
	init_order.append("systems")
	# 7 Zufall
	rng.seed = int(settings.get("random_seed", 0))
	init_order.append("rng")

	if settings.has("physics_ticks_per_second"):
		Engine.physics_ticks_per_second = int(settings["physics_ticks_per_second"])
	for e in init_errors:
		event_log.add("init_error", [], {"message": e}, "error")
	event_log.add("simulation_initialized", [], {"materials": materials.ids(), "seed": rng.seed, "ok": init_errors.is_empty()})
	return init_errors.is_empty()


static func validate_settings(d) -> Array:
	var errs: Array = []
	if typeof(d) != TYPE_DICTIONARY:
		return ["simulation.json: Inhalt ist kein JSON-Objekt."]
	if not JsonUtil.is_number(d.get("schema_version", null)) or int(d["schema_version"]) != SUPPORTED_SETTINGS_SCHEMA:
		errs.append("simulation.json: schema_version muss %d sein." % SUPPORTED_SETTINGS_SCHEMA)
	for key in ["random_seed", "initial_population", "physics_ticks_per_second", "gravity_m_s2", "event_log_max_entries"]:
		if not JsonUtil.is_number(d.get(key, null)):
			errs.append("simulation.json: '%s' fehlt oder ist keine Zahl." % key)
	if JsonUtil.is_number(d.get("initial_population", null)) and int(d["initial_population"]) < 0:
		errs.append("simulation.json: initial_population darf nicht negativ sein.")
	if JsonUtil.is_number(d.get("physics_ticks_per_second", null)) and (int(d["physics_ticks_per_second"]) < 10 or int(d["physics_ticks_per_second"]) > 240):
		errs.append("simulation.json: physics_ticks_per_second muss zwischen 10 und 240 liegen.")
	if typeof(d.get("lab", null)) != TYPE_DICTIONARY:
		errs.append("simulation.json: Abschnitt 'lab' fehlt.")
	else:
		for key in ["ambient_temperature_k", "convection_coefficient_w_m2k", "heater_power_default_w", "heater_power_max_w", "cooling_power_w", "cooling_sink_temperature_k", "drop_height_m", "fall_cube_edge_m", "melt_sample_edge_m", "load_default_j", "load_max_j"]:
			var v = d["lab"].get(key, null)
			if not JsonUtil.is_number(v) or float(v) < 0.0:
				errs.append("simulation.json: lab.%s fehlt oder ist negativ." % key)
	return errs


func _physics_process(delta: float) -> void:
	if is_ready():
		step(delta)


## Ein fester Simulationsschritt. Gibt den simulierten Zeitschritt zurück (0 bei Pause).
func step(fixed_dt: float) -> float:
	var dt := clock.advance(fixed_dt)
	if dt <= 0.0:
		return 0.0
	thermal.step(dt, registry)
	phases.update(registry, event_log)
	return dt


func set_paused(p: bool) -> void:
	if not _initialized or clock.paused == p:
		return
	clock.paused = p
	if is_inside_tree():
		get_tree().paused = p
	event_log.add("paused" if p else "resumed", [], {})


func is_paused() -> bool:
	return _initialized and clock.paused


## Erzeugt ein Objekt aus Volumen und Temperatur (Masse = Dichte · Volumen) und registriert es.
func create_object(material_id: String, volume_m3: float, temperature_k: float, station: String, label: String, liquid_fraction: float = 0.0) -> PhysicalObject:
	var errs: Array = []
	var mat := materials.get_material(material_id)
	if mat == null:
		errs.append("Unbekannte Material-ID '%s'." % material_id)
	var obj: PhysicalObject = null
	if errs.is_empty():
		obj = PhysicalObject.create(mat, volume_m3, temperature_k, errs, liquid_fraction)
	if obj == null:
		event_log.add("object_rejected", [], {"material_id": material_id, "errors": errs}, "error")
		return null
	obj.station = station
	obj.label = label
	if add_object(obj) < 0:
		return null
	return obj


## Registriert eine nicht-physikalische Entität (z. B. Wesen, Weltobjekt) mit eindeutiger ID.
## Sie braucht eine Eigenschaft `id`; Wärme- und Phasensysteme ignorieren sie.
func add_entity(entity: Object, kind: String) -> int:
	var id := registry.register(entity)
	if id < 0:
		event_log.add("entity_rejected", [], {"kind": kind}, "error")
	else:
		event_log.add("entity_added", [id], {"kind": kind})
	return id


func add_object(obj: PhysicalObject) -> int:
	if obj == null or obj.material() == null or not materials.has_material(obj.material_id):
		event_log.add("object_rejected", [], {"reason": "ungültiges Objekt oder Material"}, "error")
		return -1
	if not (obj.mass_kg > 0.0):
		event_log.add("object_rejected", [], {"reason": "Masse muss > 0 sein"}, "error")
		return -1
	var id := registry.register(obj)
	if id < 0:
		event_log.add("object_rejected", [obj.id], {"reason": "doppelte oder ungültige ID"}, "error")
	return id


func remove_object(id: int) -> bool:
	if not registry.has_id(id):
		return false
	thermal.on_entity_removed(id)
	phases.forget(id)
	return registry.unregister(id)


## Setzt die Welt vollständig zurück: alle Objekte, Kontakte, Heizungen, Uhr,
## Protokoll und Zufallsgenerator. Erhöht generation, damit veraltete Rückrufe erkannt werden.
func reset_world() -> void:
	generation += 1
	registry.clear(true)
	thermal.clear()
	var lab: Dictionary = settings.get("lab", {})
	thermal.environment_enabled = bool(lab.get("environment_exchange_enabled", true))
	phases.clear()
	clock.reset()
	if is_inside_tree():
		get_tree().paused = false
	event_log.clear()
	rng.seed = int(settings.get("random_seed", 0))
	event_log.add("world_reset", [], {"generation": generation})
	world_reset.emit(generation)


func total_mass(station: String = "") -> float:
	var s := 0.0
	for id in registry.ids():
		var o: PhysicalObject = registry.get_entity(id) as PhysicalObject
		if o != null and (station == "" or o.station == station):
			s += o.mass_kg
	return s


func ids_in_station(station: String) -> Array:
	var r: Array = []
	for id in registry.ids():
		var o: PhysicalObject = registry.get_entity(id) as PhysicalObject
		if o != null and o.station == station:
			r.append(id)
	return r
