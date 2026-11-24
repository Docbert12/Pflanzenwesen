class_name Observation
extends RefCounted
## Eine Beobachtung eines Wesens (nicht der Weltfakt selbst).
## Enthält nur, was der Beobachter wahrgenommen hat: Ereignistyp, sichtbare Beteiligte, Ort,
## sichtbare Folgen, Qualität (Entfernung × Kopffunktion) und die Quellenart.
## NICHT enthalten: Absichten anderer, verdeckte Ursachen, Spielerwissen aus dem Göttermenü.
## Quellenstruktur ist für spätere Mitteilungen erweiterbar ({"kind": "mitteilung", "via": id, "chain": [...]}),
## in dieser Version gibt es nur "eigene_beobachtung".

const SOURCE_OWN := "eigene_beobachtung"

var observer_id: int = 0
var t: float = 0.0
var event_type: String = ""
var actor_id: int = 0                 # wahrgenommener Handelnder (0 = keiner erkennbar)
var target_id: int = 0                # wahrgenommenes Ziel/Empfänger (0 = keiner)
var participants: Array = []
var position := Vector3.ZERO
var consequences: Dictionary = {}     # nur sichtbare Folgen
var quality: float = 1.0
var source: Dictionary = {"kind": SOURCE_OWN}
var event_seq: int = 0                # nur Diagnose (Bezug zum Weltprotokoll); der Geist nutzt ihn nicht


func involves(id: int) -> bool:
	return actor_id == id or target_id == id


func to_dict() -> Dictionary:
	return {"observer": observer_id, "t": t, "type": event_type, "actor": actor_id, "target": target_id, "participants": participants.duplicate(),
		"pos": [position.x, position.y, position.z], "consequences": consequences.duplicate(true), "quality": quality, "source": source.duplicate(true)}
