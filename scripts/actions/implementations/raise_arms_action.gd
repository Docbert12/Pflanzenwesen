class_name RaiseArmsAction
extends ActionImpl
## „Arme heben“: anhalten und beide (vorhandenen) Arme heben, 3 s. Neutrale Ausdruckshandlung –
## kein Gebet, kein Wissen über eine Gottheit, keine garantierte Wirkung. Ihr Wert entsteht nur durch
## eigene Erfahrungen (LearningSystem/RewardAssociation). Benötigt mindestens einen Oberarm (gesture > 0).

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.m("raise_arms").get("duration_s", 3.0))


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var cr := ctx.creature(a.actor_id)
	ctx.publish({"type": "raise_arms", "actor": cr.id, "position": cr.position, "consequences": {"dauer_s": d}})
	return ActionResult.success("Arme gehoben.", {"done": true})


func power_w(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.m("raise_arms").get("energy_w", 3.0))
