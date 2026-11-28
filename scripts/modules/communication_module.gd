class_name CommunicationModule
extends SimModule
## Kommunikation und KI: Gespräche, Hörensagen, optionale Modellanbindung (AISystem). Bei Pause läuft
## nur das Netzwerk weiter; es werden keine Anfragen gestellt und nichts angewendet.

func _init() -> void:
	id = "communication"
	has_section = true
	title = "Kommunikation und KI"
	depends_on = ["work"]
	load_order = 70
	after_load_order = 10


func tick(_dt: float, _zone: int) -> void:
	ctx.ai.update(false)


func tick_paused() -> void:
	if ctx != null and ctx.ai != null:
		ctx.ai.update(true)


func save_section() -> Dictionary:
	return {"communication": ctx.comm.to_dict(),
		"ai_note": "Gespeichert: angenommene Pläne, Hörensagen mit Herkunft und Vertrauen, Gesprächsprotokoll, Wartezeiten. NICHT gespeichert: offene Modellanfragen, Verbindungen, Modellname, Adresse (Anwendungseinstellungen). Der Spielstand lädt ohne Modell."}


func load_section(d: Dictionary) -> Dictionary:
	ctx.comm = CommunicationSystem.from_dict(d.get("communication", {}))
	return {"ok": true}


func after_load() -> Array:
	return ctx.ai.after_load()
