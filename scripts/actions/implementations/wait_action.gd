class_name WaitAction
extends ActionImpl
## Warten: params.duration_s (Standard 2 s), params.reason (Text für die Anzeige).

func estimate_s(a: GameAction, _ctx: LifeContext) -> float:
	return float(a.params.get("duration_s", 2.0))


func validate_start(a: GameAction, _ctx: LifeContext) -> ActionResult:
	var d := float(a.params.get("duration_s", 2.0))
	if d <= 0.0 or d > 600.0:
		return ActionResult.fail("invalid_duration", "Wartedauer muss zwischen 0 und 600 s liegen.")
	return ActionResult.success()


func step(a: GameAction, _ctx: LifeContext, _dt: float) -> ActionResult:
	var d := float(a.params.get("duration_s", 2.0))
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	return ActionResult.success("", {"done": a.elapsed_s >= d})
