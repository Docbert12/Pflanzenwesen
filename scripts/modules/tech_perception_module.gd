class_name TechPerceptionModule
extends SimModule
## Technik, Teil Wahrnehmung: Gegenstände und Vorgänge, die ein Wesen gerade sieht (praktisches Wissen).

func _init() -> void:
	id = "technology.perception"
	title = "Technik: Gegenstände wahrnehmen"
	depends_on = ["mind.perception"]
	per_actor = true


func actor_tick(cr: Creature, _dt: float) -> void:
	if ctx.perceived_actor_id == cr.id:
		ExperimentSystem.perceive_objects(cr, ctx)
