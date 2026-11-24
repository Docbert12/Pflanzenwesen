class_name EventLog
extends RefCounted
## Strukturiertes Ereignisprotokoll mit begrenzter Historie im Arbeitsspeicher.
## Protokolliert Zustandswechsel und Fehler – keine Werte pro Frame.

var max_entries: int = 300
var _entries: Array = []
var _seq: int = 0
var dropped_count: int = 0
var _clock: SimulationClock


func _init(clock: SimulationClock = null, max_count: int = 300) -> void:
	_clock = clock
	max_entries = max(10, max_count)


## type: kurzer Bezeichner, z. B. "melting_started". ids: beteiligte Objekt-IDs.
func add(type: String, ids: Array = [], data: Dictionary = {}, severity: String = "info") -> Dictionary:
	_seq += 1
	var entry := {
		"seq": _seq,
		"t": _clock.sim_time_s if _clock != null else 0.0,
		"type": type,
		"severity": severity,
		"ids": ids.duplicate(),
		"data": data.duplicate(true),
	}
	_entries.append(entry)
	while _entries.size() > max_entries:
		_entries.pop_front()
		dropped_count += 1
	if severity == "error":
		push_warning("Ereignis-Fehler: %s %s" % [type, str(data)])
	return entry


func recent(n: int) -> Array:
	var start: int = max(0, _entries.size() - n)
	return _entries.slice(start)


func all_entries() -> Array:
	return _entries.duplicate()


func count_type(type: String) -> int:
	var c := 0
	for e in _entries:
		if e["type"] == type:
			c += 1
	return c


func clear() -> void:
	_entries.clear()
	_seq = 0
	dropped_count = 0
