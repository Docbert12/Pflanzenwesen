class_name GodModule
extends SimModule
## Göttermenü: Eingriffe des Spielers und ihre Nachwirkungen (InterventionSystem).

func _init() -> void:
	id = "god"
	has_section = true
	title = "Göttermenü (Eingriffe)"
	depends_on = ["social"]
	load_order = 80


func tick(_dt: float, _zone: int) -> void:
	ctx.interventions.tick()


func save_section() -> Dictionary:
	return {"interventions": ctx.interventions.to_dict()}


func load_section(d: Dictionary) -> Dictionary:
	ctx.interventions.load_dict(d.get("interventions", {}))
	return {"ok": true}
