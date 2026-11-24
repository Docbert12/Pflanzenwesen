class_name Structure
extends RefCounted
## Einfaches Einzelbauwerk an einer Baustelle (Prompt 6B; gemeinsames Bauen folgt in Prompt 9).
## Ein Bauwerk besteht aus Plätzen (slots) nach einem im Code unterstützten, parametrisierten
## Bauplan. Ein verbautes Teil bleibt dasselbe Weltobjekt mit Masse, Material und Temperatur;
## das Bauwerk führt nur Verweise. Ein Name allein verleiht keine Funktion (StructureSystem.evaluate).

var id: int = 0
var blueprint: String = "steinreihe"
var label: String = ""
var position := Vector3.ZERO      # Ursprung am Boden (erster Platz)
var heading: float = 0.0          # Richtung der Reihe (Drehung um y)
var slots: Array = []             # [{"local": [x, y, z], "part_id": int}]
var initiator: int = 0            # Wesen, das die Baustelle angelegt hat (0 = Testaufbau)
var origin: String = "test_equipment"
var status: String = "geplant"    # geplant | im Bau | fertig
var created_t: float = 0.0
var history: Array = []


func add_history(t: float, what: String) -> void:
	history.append({"t": snappedf(t, 0.01), "what": what})
	while history.size() > 30:
		history.pop_front()


func filled() -> int:
	var n := 0
	for s in slots:
		if int(s.get("part_id", 0)) != 0:
			n += 1
	return n


func to_dict() -> Dictionary:
	return {"id": id, "blueprint": blueprint, "label": label, "position": [position.x, position.y, position.z], "heading": heading,
		"slots": slots.duplicate(true), "initiator": initiator, "origin": origin, "status": status, "created_t": created_t,
		"history": history.duplicate(true)}


static func from_dict(d: Dictionary) -> Structure:
	var s := Structure.new()
	s.id = int(d["id"])
	s.blueprint = str(d.get("blueprint", "steinreihe"))
	s.label = str(d.get("label", ""))
	var p: Array = d.get("position", [0, 0, 0])
	s.position = Vector3(p[0], p[1], p[2])
	s.heading = float(d.get("heading", 0.0))
	for sl in d.get("slots", []):
		var e: Dictionary = sl.duplicate(true)
		e["part_id"] = int(e.get("part_id", 0))
		s.slots.append(e)
	s.initiator = int(d.get("initiator", 0))
	s.origin = str(d.get("origin", "test_equipment"))
	s.status = str(d.get("status", "geplant"))
	s.created_t = float(d.get("created_t", 0.0))
	s.history = d.get("history", []).duplicate(true)
	return s
