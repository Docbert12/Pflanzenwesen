class_name Assembly
extends RefCounted
## Zusammengesetzter Gegenstand (Prompt 6). Besitzt selbst KEINE Masse und kein Material:
## Masse, Wärme und Verschleiß liegen ausschließlich in den Bauteilen (MaterialPiece mit
## assembly_id = id). Damit gibt es weder doppelte Masse noch Bauteile, die gleichzeitig einzeln
## und zusammengesetzt existieren.
##
## Geometrie: position = Griffpunkt. offsets[part_id] = Lage des Bauteilmittelpunkts relativ zum
## Griffpunkt entlang der Stielachse (+x). Die Darstellung dreht nur; die Simulation nutzt die
## Abstände (Trägheitsmoment beim Schwingen).
##
## connections: [{id, a, b, method, binding_id, capacity_j, quality, wear, strikes, created_t}]
## Eine Verbindung ist nie unsichtbar oder unzerstörbar: Belastung > capacity_j → Bruch,
## Verschleiß ≥ 1 → Bruch. Bruch löst den Verbund auf, alle Teile bleiben Weltobjekte.

var id: int = 0
var label: String = ""             # nur Anzeige – bestimmt KEINE Fähigkeit
var origin: String = ""            # "gebaut:#<wesen>", "test_equipment"
var created_by: int = 0
var created_t: float = 0.0
var part_ids: Array = []
var offsets: Dictionary = {}       # part_id -> float (Abstand vom Griffpunkt entlang +x)
var connections: Array = []
var grip_part_id: int = 0
var head_part_id: int = 0          # 0 = kein Arbeitskopf
var position := Vector3.ZERO
var carrier_id: int = 0
var container_id: int = 0          # Testheizung, in der der Verbund steht
var test_equipment: bool = false
var reserved_by: int = 0
var history: Array = []
var visual_version: int = 0        # nur Darstellung


func add_history(t: float, what: String) -> void:
	history.append({"t": t, "what": what})
	while history.size() > 12:
		history.pop_front()


func to_dict() -> Dictionary:
	var off := {}
	for k in offsets:
		off[str(k)] = offsets[k]
	return {"id": id, "label": label, "origin": origin, "created_by": created_by, "created_t": created_t,
		"part_ids": part_ids.duplicate(), "offsets": off, "connections": connections.duplicate(true),
		"grip_part_id": grip_part_id, "head_part_id": head_part_id, "position": [position.x, position.y, position.z],
		"carrier_id": carrier_id, "container_id": container_id, "test_equipment": test_equipment, "history": history.duplicate(true)}


static func from_dict(d: Dictionary) -> Assembly:
	var a := Assembly.new()
	a.id = int(d["id"])
	a.label = str(d.get("label", ""))
	a.origin = str(d.get("origin", ""))
	a.created_by = int(d.get("created_by", 0))
	a.created_t = float(d.get("created_t", 0.0))
	for p in d.get("part_ids", []):
		a.part_ids.append(int(p))
	var off: Dictionary = d.get("offsets", {})
	for k in off:
		a.offsets[int(k)] = float(off[k])
	a.connections = d.get("connections", []).duplicate(true)
	for c in a.connections:
		for k in ["id", "a", "b", "binding_id", "strikes"]:
			if c.has(k):
				c[k] = int(c[k])
	a.grip_part_id = int(d.get("grip_part_id", 0))
	a.head_part_id = int(d.get("head_part_id", 0))
	var p: Array = d.get("position", [0, 0, 0])
	a.position = Vector3(p[0], p[1], p[2])
	a.carrier_id = int(d.get("carrier_id", 0))
	a.container_id = int(d.get("container_id", 0))
	a.test_equipment = bool(d.get("test_equipment", false))
	a.history = d.get("history", []).duplicate(true)
	return a
