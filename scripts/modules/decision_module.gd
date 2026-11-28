class_name DecisionModule
extends SimModule
## Geist, Teil Entscheidung: DecisionSystem ist der EINZIGE Entscheider je Wesen.

var _interval: float = 0.5

func _init() -> void:
	id = "mind.decision"
	title = "Geist: Entscheidung"
	depends_on = ["settlement"]
	per_actor = true


func tick(_dt: float, _zone: int) -> void:
	_interval = float(ctx.c("behavior").get("decision_interval_s", 0.5))


func actor_tick(cr: Creature, _dt: float) -> void:
	ctx.perceived_actor_id = 0
	var now := ctx.now()
	if cr.behavior_enabled and now >= cr.next_decision_t:
		cr.next_decision_t = now + _interval
		DecisionSystem.decide(cr, ctx)
