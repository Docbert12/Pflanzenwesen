class_name TestHeater
extends RefCounted
## Ausdrücklich als TESTAUSRÜSTUNG platzierte, extern versorgte Heizung (Prompt 6, Testwerkstatt).
## Sie ist keine Erfindung der Wesen und keine frei erfundene Energiequelle: ihre Leistung ist ein
## fester Parameter, die zugeführte Energie erscheint in der Wärmebilanz als Heizzufuhr
## (ThermalSystem.heaters[name].supplied_j). Die Heizung selbst hat keine Wärmekapazität; sie
## heizt den eingesetzten Behälter (Tiegelkörper) direkt, solange er im Einsatz steht.

var id: int = 0
var label: String = "Testheizung (extern versorgt)"
var position := Vector3.ZERO
var power_w: float = 3500.0
var slot_id: int = 0          # eingesetzter Verbund/Behälter (Objekt-ID) oder 0
var target_piece_id: int = 0  # beheiztes Stück (Tiegelkörper)
var origin: String = "test_equipment"


func heater_name() -> String:
	return "testheizung_%d" % id


func slot_position() -> Vector3:
	return position + Vector3(0, 0.12, 0)


func to_dict() -> Dictionary:
	return {"id": id, "label": label, "position": [position.x, position.y, position.z], "power_w": power_w,
		"slot_id": slot_id, "target_piece_id": target_piece_id, "origin": origin}


static func from_dict(d: Dictionary) -> TestHeater:
	var h := TestHeater.new()
	h.id = int(d["id"])
	h.label = str(d.get("label", h.label))
	var p: Array = d.get("position", [0, 0, 0])
	h.position = Vector3(p[0], p[1], p[2])
	h.power_w = float(d.get("power_w", 3500.0))
	h.slot_id = int(d.get("slot_id", 0))
	h.target_piece_id = int(d.get("target_piece_id", 0))
	h.origin = str(d.get("origin", "test_equipment"))
	return h
