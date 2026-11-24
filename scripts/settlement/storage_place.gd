class_name StoragePlace
extends RefCounted
## Realer Lagerplatz (Prompt 6B; Grundlage für Prompt 9). Ein begrenzter Bodenbereich mit Kapazität
## nach Masse und Volumen. Eingelagerte Stücke bleiben eigene Weltobjekte mit eigener Position,
## Temperatur und eigenem Zustand (kein Zusammenführen zu Stapeln, keine Teleportation): Ein- und
## Auslagern geschieht nur durch tatsächliches Tragen (Handlungen deposit_in_storage bzw. Aufnehmen).

var id: int = 0
var label: String = "Lagerplatz"
var position := Vector3.ZERO       # Mitte des Bereichs am Boden
var size_m := Vector2(0.8, 0.8)    # Ausdehnung x, z
var capacity_kg: float = 25.0
var capacity_m3: float = 0.02
var contents: Array = []           # Stück-IDs (Reihenfolge des Einlagerns)
var created_by: int = 0            # 0 = Testaufbau
var origin: String = "test_equipment"
var created_t: float = 0.0
var history: Array = []


func add_history(t: float, what: String) -> void:
	history.append({"t": snappedf(t, 0.01), "what": what})
	while history.size() > 30:
		history.pop_front()


func to_dict() -> Dictionary:
	return {"id": id, "label": label, "position": [position.x, position.y, position.z], "size_m": [size_m.x, size_m.y],
		"capacity_kg": capacity_kg, "capacity_m3": capacity_m3, "contents": contents.duplicate(), "created_by": created_by,
		"origin": origin, "created_t": created_t, "history": history.duplicate(true)}


static func from_dict(d: Dictionary) -> StoragePlace:
	var s := StoragePlace.new()
	s.id = int(d["id"])
	s.label = str(d.get("label", s.label))
	var p: Array = d.get("position", [0, 0, 0])
	s.position = Vector3(p[0], p[1], p[2])
	var sz: Array = d.get("size_m", [0.8, 0.8])
	s.size_m = Vector2(sz[0], sz[1])
	s.capacity_kg = float(d.get("capacity_kg", 25.0))
	s.capacity_m3 = float(d.get("capacity_m3", 0.02))
	for c in d.get("contents", []):
		s.contents.append(int(c))
	s.created_by = int(d.get("created_by", 0))
	s.origin = str(d.get("origin", "test_equipment"))
	s.created_t = float(d.get("created_t", 0.0))
	s.history = d.get("history", []).duplicate(true)
	return s
