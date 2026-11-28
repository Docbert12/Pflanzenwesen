class_name PerceptionModule
extends SimModule
## Geist, Teil Wahrnehmung: Umgebung abtasten, Hörensagen an der Wahrnehmung prüfen, Lernen.
## Setzt ctx.perceived_actor_id für die Wahrnehmungsanteile anderer Module (Technik, Siedlung) im
## selben Simulationsbild – diese Module fragen den Kontext, nicht dieses Modul.

var _interval: float = 1.0

func _init() -> void:
	id = "mind.perception"
	title = "Geist: Wahrnehmung und Lernen"
	depends_on = ["life"]
	per_actor = true


func tick(_dt: float, _zone: int) -> void:
	_interval = float(ctx.c("perception").get("interval_s", 1.0))
	ctx.perceived_actor_id = 0


func actor_tick(cr: Creature, _dt: float) -> void:
	ctx.perceived_actor_id = 0
	var now := ctx.now()
	if now < cr.next_perception_t:
		return
	Perception.scan(cr, ctx)
	ClaimEvaluator.on_perception(cr, ctx)
	LearningSystem.tick(cr, ctx)
	ctx.perceived_actor_id = cr.id
	cr.next_perception_t = now + _interval
