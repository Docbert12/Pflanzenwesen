class_name TalkAction
extends ActionImpl
## „Sprechen“: kurze direkte Mitteilung an ein nahes Wesen (communication.duration_s, Reichweite range_m).
## Inhalt ist eine vorher geprüfte, strukturierte Äußerung (CommunicationSystem.pending). Bei Abschluss
## wird sie zugestellt, wenn der Zuhörer noch lebt, in Reichweite ist und den Sprecher wahrnimmt.
## Keine Gegenstände, keine Ressourcen, keine weiteren Wirkungen.

func estimate_s(_a: GameAction, ctx: LifeContext) -> float:
	return float(ctx.m("communication").get("duration_s", 1.5))


func validate_start(a: GameAction, ctx: LifeContext) -> ActionResult:
	if ctx.comm == null or not ctx.comm.pending.has(int(a.params.get("utterance", 0))):
		return ActionResult.fail("no_content", "Keine geprüfte Äußerung.")
	return _check(a, ctx, 1.0)


func validate_step(a: GameAction, ctx: LifeContext) -> ActionResult:
	return _check(a, ctx, 1.25)


func _check(a: GameAction, ctx: LifeContext, slack: float) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	var t := ctx.creature(a.target_id)
	if t == null or not t.alive or t.id == cr.id:
		return ActionResult.fail("target_lost", "Kein lebender Zuhörer.")
	var r := float(ctx.m("communication").get("range_m", 4.0)) * slack
	var d := ctx.distance_xz(cr.position, t.position)
	if d > r:
		return ActionResult.fail("out_of_reach", "Zuhörer %.1f m entfernt (Gespräch bis %.1f m)." % [d, r])
	return ActionResult.success()


func step(a: GameAction, ctx: LifeContext, _dt: float) -> ActionResult:
	var d := estimate_s(a, ctx)
	a.progress = clampf(a.elapsed_s / d, 0.0, 1.0)
	if a.elapsed_s < d:
		return ActionResult.success()
	var res := ctx.comm.deliver(int(a.params.get("utterance", 0)), ctx)
	a.consumed = {"heard": res["ok"]}
	return ActionResult.success("Gesagt: %s" % str(res["message"]), {"done": true})


func cleanup(a: GameAction, ctx: LifeContext) -> void:
	# Nach erfolgreicher Zustellung ist die Äußerung nicht mehr offen; sonst: unterbrochen
	if ctx.comm != null and ctx.comm.pending.has(int(a.params.get("utterance", 0))):
		ctx.comm.cancel_pending(int(a.params.get("utterance", 0)), "Gespräch unterbrochen", ctx)


func power_w(_a: GameAction, _ctx: LifeContext) -> float:
	return 0.5
