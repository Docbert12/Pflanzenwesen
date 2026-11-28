class_name LifeContext
extends RefCounted
## Gemeinsamer Zugriff der Lebenssysteme auf Welt und Entitäten (keine eigene Logik,
## keine Node-Referenzen außer der VoxelWorld). Alle Entitäten sind zusätzlich im
## EntityRegistry der Simulation registriert (eine ID-Vergabe für alles).

var sim: Simulation
var db: DefinitionDB
var cfg: Dictionary                 # data/config/life.json
var mind_cfg: Dictionary            # data/config/mind.json
var social: SocialInteractionSystem
var interventions: InterventionSystem
var comm: CommunicationSystem         # Gespräche (Prompt 5)
var ai: AISystem                      # Modellanbindung dieser Welt (Prompt 5); arbeitet auch ausgeschaltet
var world: VoxelWorld
var terrain: WorldAccess              # Alpha 1.1: einziger Geländezugriff außerhalb der Welt-Schicht
var rng_streams := RngStreams.new()   # Alpha 1.1: Zufallsströme je Modul (neue Module)
var perceived_actor_id: int = 0       # Wesen, das in diesem Simulationsbild gerade wahrgenommen hat (0 = keines)
var nav: NavigationService
var day_night: DayNightSystem
var executor: ActionExecutor
var ledger: ResourceLedger
var creatures: Dictionary = {}      # id -> Creature
var foods: Dictionary = {}          # id -> FoodSource
var items: Dictionary = {}          # id -> FoodItem
var shade_cols: Dictionary = {}     # Vector2i -> true (unter Baumkrone)
var dev_mode: bool = false
var _hash: Dictionary = {}          # Raster 1 m → Wesen-IDs (Nachbarsuche, je Takt neu)
var refill_enabled: bool = false    # sichtbare Testoption, im normalen Spiel aus
var material_pieces: Dictionary = {}   # id -> MaterialPiece (Göttereingriffe, Testwerkstatt, Bruch, Guss)
var assemblies: Dictionary = {}        # id -> Assembly (zusammengesetzte Gegenstände, Prompt 6)
var heaters: Dictionary = {}           # id -> TestHeater (nur Testausrüstung)
var experiments: ExperimentSystem      # Versuche, Verfahrenswissen-Verbuchung (Prompt 6)
var storages: Dictionary = {}          # id -> StoragePlace (Prompt 6B: reale Lagerplätze)
var structures: Dictionary = {}        # id -> Structure (Prompt 6B: Baustellen/Einzelbauwerke)
var work: WorkSystem                   # Arbeitsketten aus eigenem Bedarf (Prompt 6B)
var tech_cfg: Dictionary = {}          # data/config/technology.json
var last_observers: Array = []          # Diagnose: Beobachter des zuletzt verteilten Ereignisses
var observation_stats: Dictionary = {}  # Zähler: verteilte Ereignisse, Sichtprüfungen, Beobachtungen


func now() -> float:
	return sim.clock.sim_time_s


func c(section: String) -> Dictionary:
	return cfg.get(section, {})


func m(section: String) -> Dictionary:
	return mind_cfg.get(section, {})


func tc(section: String) -> Dictionary:
	return tech_cfg.get(section, {})


## Protokolliert ein Ereignis (Weltfakt) und verteilt es als Beobachtung an die Wesen, die es
## tatsächlich wahrnehmen können (Perception.broadcast). Rückgabe: Ereignis-Sequenznummer.
## ev: {"type", "actor", "target", "position": Vector3, "consequences": {}, "visibility_m"}
func publish(ev: Dictionary, severity: String = "info") -> int:
	var ids: Array = []
	for k in ["actor", "target"]:
		if int(ev.get(k, 0)) != 0:
			ids.append(int(ev[k]))
	var p: Vector3 = ev.get("position", Vector3.ZERO)
	var data: Dictionary = ev.get("consequences", {}).duplicate()
	data["pos"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
	var entry := sim.event_log.add(str(ev["type"]), ids, data, severity)
	ev["seq"] = int(entry["seq"])
	ev["t"] = now()
	Perception.broadcast(self, ev)
	return ev["seq"]


## Routineereignisse (Start/Erfolg einer Handlung, Reservierungen) erscheinen nicht im gemeinsamen,
## begrenzten Ereignisprotokoll, sonst verdrängen 50 Wesen alle anderen Einträge in Sekunden.
## Alle Handlungsergebnisse stehen vollständig im begrenzten ActionExecutor.history.
const ROUTINE_EVENTS := ["action_started", "action_succeeded", "reservation_created", "reservation_released", "item_removed"]
var log_routine: bool = false


func log_event(type: String, ids: Array, data: Dictionary, severity: String = "info") -> void:
	if not log_routine and type in ROUTINE_EVENTS:
		return
	sim.event_log.add(type, ids, data, severity)


## Position einer Entität (Wesen, Nahrungsquelle, Gegenstand) oder null.
func position_of(id: int):
	if creatures.has(id):
		return creatures[id].position
	if foods.has(id):
		return foods[id].position
	if items.has(id):
		var it: FoodItem = items[id]
		if it.carrier_id != 0 and creatures.has(it.carrier_id):
			return creatures[it.carrier_id].position
		return it.position
	if material_pieces.has(id):
		return material_pieces[id].position
	if assemblies.has(id):
		return assemblies[id].position
	if heaters.has(id):
		return heaters[id].position
	if storages.has(id):
		return storages[id].position
	if structures.has(id):
		return structures[id].position
	return null


func creature(id: int) -> Creature:
	return creatures.get(id, null)


## Neuen Gegenstand (Nahrungsportion) anlegen und registrieren.
func create_item(food_props: Dictionary, mass_kg: float, carrier_id: int, pos: Vector3, source_id: int) -> FoodItem:
	var it := FoodItem.new()
	it.food_id = str(food_props.get("food_id", ""))
	it.kind = str(food_props.get("kind", ""))
	it.energy_j_per_kg = float(food_props.get("energy_j_per_kg", 0.0))
	it.nutrients_g_per_kg = float(food_props.get("nutrients_g_per_kg", 0.0))
	it.mass_kg = mass_kg
	it.carrier_id = carrier_id
	it.position = pos
	it.source_id = source_id
	sim.add_entity(it, "food_item")
	items[it.id] = it
	return it


func remove_item(id: int, reason: String) -> void:
	if not items.has(id):
		return
	items.erase(id)
	sim.remove_object(id)
	log_event("item_removed", [id], {"reason": reason})


func distance_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Räumliches Raster der lebenden Wesen (1-m-Zellen), einmal je Takt neu aufgebaut.
func rebuild_spatial_hash() -> void:
	_hash.clear()
	for id in creatures:
		var cr: Creature = creatures[id]
		var k := Vector2i(floori(cr.position.x), floori(cr.position.z))
		if not _hash.has(k):
			_hash[k] = []
		_hash[k].append(id)


func nearby_creatures(pos: Vector3, r: float) -> Array:
	var res: Array = []
	var k := Vector2i(floori(pos.x), floori(pos.z))
	var n := ceili(r)
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var cell = _hash.get(k + Vector2i(dx, dz), null)
			if cell != null:
				res.append_array(cell)
	return res
