class_name ActionValidator
extends RefCounted
## Allgemeine Prüfungen für jede Handlung (beim Start und in jedem Ausführungsschritt).
## Handlungsspezifische Prüfungen liegen in der jeweiligen Implementierung.

func validate_start(a: GameAction, ctx: LifeContext, impl: ActionImpl) -> ActionResult:
	if not ActionDefinition.has_type(a.type):
		return ActionResult.fail("unknown_type", "Unbekannter Handlungstyp '%s'." % a.type)
	var cr := ctx.creature(a.actor_id)
	if cr == null:
		return ActionResult.fail("no_actor", "Handelndes Wesen #%d existiert nicht." % a.actor_id)
	if not cr.alive:
		return ActionResult.fail("actor_dead", "Wesen #%d ist tot." % a.actor_id)
	var r := check_capabilities(a, cr)
	if not r.ok:
		return r
	var info := ActionDefinition.info(a.type)
	match info.get("target", "none"):
		"position":
			if a.target_pos == null:
				return ActionResult.fail("no_target", "Zielposition fehlt.")
		"entity":
			if a.target_id == 0 or ctx.position_of(a.target_id) == null:
				return ActionResult.fail("target_lost", "Ziel #%d existiert nicht." % a.target_id)
	return impl.validate_start(a, ctx)


func validate_step(a: GameAction, ctx: LifeContext, impl: ActionImpl) -> ActionResult:
	var cr := ctx.creature(a.actor_id)
	if cr == null or not cr.alive:
		return ActionResult.fail("actor_dead", "Handelndes Wesen ist nicht mehr am Leben.")
	var r := check_capabilities(a, cr)
	if not r.ok:
		return r
	return impl.validate_step(a, ctx)


## Benötigte Körperfähigkeiten aus BodyCapabilities (Werte > 0, Gehen zusätzlich can_walk).
func check_capabilities(a: GameAction, cr: Creature) -> ActionResult:
	for cap in a.required_caps:
		if cap == "locomotion":
			if not cr.caps.get("can_walk", false):
				return ActionResult.fail("cannot_walk", "Fortbewegung nicht möglich: %s" % cr.caps.get("walk_reason", "unbekannt"))
		elif float(cr.caps.get(cap, 0.0)) <= 0.0:
			return ActionResult.fail("missing_capability", "Körperfähigkeit „%s“ fehlt (%s)." % [cap, cr.caps.get("explain", {}).get(cap, "kein beitragendes Körperteil")])
	return ActionResult.success()
