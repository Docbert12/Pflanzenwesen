class_name ActionImpl
extends RefCounted
## Basis einer Handlungsimplementierung. Alle Methoden arbeiten nur über LifeContext.

## Geschätzte Dauer [s] für das Zeitlimit.
func estimate_s(_a: GameAction, _ctx: LifeContext) -> float:
	return 5.0


## Spezifische Startprüfung (allgemeine Prüfungen macht ActionValidator).
func validate_start(_a: GameAction, _ctx: LifeContext) -> ActionResult:
	return ActionResult.success()


## Prüfung während der Ausführung.
func validate_step(_a: GameAction, _ctx: LifeContext) -> ActionResult:
	return ActionResult.success()


func start(_a: GameAction, _ctx: LifeContext) -> ActionResult:
	return ActionResult.success()


## Ein Ausführungsschritt. data.done = true → erfolgreich beendet.
func step(_a: GameAction, _ctx: LifeContext, _dt: float) -> ActionResult:
	return ActionResult.success("", {"done": true})


## Aufräumen bei jedem Ende (Erfolg, Fehlschlag, Abbruch). Reservierungen gibt der Executor frei.
func cleanup(_a: GameAction, _ctx: LifeContext) -> void:
	pass


## Leistung [W], die diese Handlung zusätzlich verbraucht (Spielwert).
func power_w(a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.c("metabolism").get("action_power_w", {}).get(a.type, 0.0))
