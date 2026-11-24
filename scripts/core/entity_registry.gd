class_name EntityRegistry
extends RefCounted
## Vergibt eindeutige ganzzahlige IDs und verwaltet registrierte Objekte.
## Ein Objekt muss eine Eigenschaft `id: int` besitzen.

signal entity_registered(id: int)
signal entity_unregistered(id: int)

var _next_id: int = 1
var _entities: Dictionary = {}


func allocate_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


## Registriert ein Objekt. id == 0 → neue ID wird vergeben.
## Gibt die ID zurück oder -1 bei Fehler (doppelte ID / ungültig).
func register(entity: Object) -> int:
	if entity == null or not ("id" in entity):
		push_error("EntityRegistry: Objekt ohne id-Eigenschaft abgewiesen.")
		return -1
	if entity.id == 0:
		entity.id = allocate_id()
	elif entity.id < 0:
		push_error("EntityRegistry: negative ID %d abgewiesen." % entity.id)
		return -1
	if _entities.has(entity.id):
		push_error("EntityRegistry: doppelte ID %d abgewiesen." % entity.id)
		return -1
	_entities[entity.id] = entity
	if entity.id >= _next_id:
		_next_id = entity.id + 1
	entity_registered.emit(entity.id)
	return entity.id


## Nächste freie ID mindestens auf n setzen (Laden eines Spielstands).
func ensure_next_id(n: int) -> void:
	if n > _next_id:
		_next_id = n


func next_id() -> int:
	return _next_id


func unregister(id: int) -> bool:
	if not _entities.has(id):
		return false
	_entities.erase(id)
	entity_unregistered.emit(id)
	return true


func get_entity(id: int) -> Object:
	return _entities.get(id, null)


func has_id(id: int) -> bool:
	return _entities.has(id)


func ids() -> Array:
	var result := _entities.keys()
	result.sort()
	return result


func count() -> int:
	return _entities.size()


## Entfernt alle Objekte. Mit reset_counter beginnt die Vergabe wieder bei 1.
func clear(reset_counter: bool = false) -> void:
	for id in ids():
		unregister(id)
	if reset_counter:
		_next_id = 1
