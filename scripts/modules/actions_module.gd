class_name ActionsModule
extends SimModule
## Handlungen: einzige Handlungsausführung (ActionExecutor). Laufende Handlungen werden nach ihrem
## Ladeverhalten (ActionDefinition.on_load) fortgesetzt, neu geplant oder kontrolliert abgebrochen.

const HISTORY_TAIL := 50
var cancelled: Array = []
var continued: Array = []

func _init() -> void:
	id = "actions"
	has_section = true
	title = "Handlungen (Ausführung)"
	depends_on = ["actors"]
	load_order = 90


func tick(dt: float, _zone: int) -> void:
	ctx.executor.step(dt)


func save_section() -> Dictionary:
	var ex := ctx.executor
	var running: Array = []
	for aid in SaveManager.sorted_keys(ex.running):
		running.append(ex.running[aid].to_dict())
	return {"actions": {"running": running, "next_action_id": ex.next_action_id, "next_res_id": ex.next_res_id, "stats": ex.stats.duplicate(),
		"history_tail": ex.history.slice(maxi(0, ex.history.size() - HISTORY_TAIL)), "reservations_saved": false}}


func load_section(d: Dictionary) -> Dictionary:
	var acts: Dictionary = d.get("actions", {})
	var ex := ctx.executor
	ex.next_action_id = int(acts.get("next_action_id", 1))
	ex.next_res_id = int(acts.get("next_res_id", 1))
	for k in acts.get("stats", {}):
		ex.stats[k] = int(acts["stats"][k])
	ex.history = acts.get("history_tail", []).duplicate(true)
	cancelled = []
	continued = []
	for ad in acts.get("running", []):
		var a := GameAction.from_dict(ad)
		var cr2 := ctx.creature(a.actor_id)
		var policy := str(ActionDefinition.info(a.type).get("on_load", "cancel"))
		a.reservation_id = 0
		if policy == "continue" and a.type == "eat" and a.state.get("mode", "") != "carried":
			policy = "cancel"   # direktes Essen hing an einer Reservierung → kontrolliert abbrechen
		if cr2 == null or not cr2.alive:
			policy = "cancel"
		if policy == "replan":
			a.state["need_path"] = true
			a.state["replans"] = 0
		if policy in ["continue", "replan"]:
			var impl: ActionImpl = ex.impls[a.type]
			var v := ex.validator.validate_step(a, ctx, impl)
			if v.ok:
				ex.running[a.actor_id] = a
				continued.append("%s #%d (%s)" % [a.type, a.actor_id, policy])
				continue
			policy = "cancel"
		cancelled.append("%s #%d" % [a.type, a.actor_id])
		ctx.log_event("action_cancelled_on_load", [a.actor_id], {"action_id": a.id, "type": a.type, "reason": "Ladeverhalten: kontrolliert abgebrochen"}, "warning")
		if cr2 != null:
			cr2.last_result = {"type": a.type, "status": ActionDefinition.STATUS_CANCELLED, "code": "cancelled_on_load", "message": "Beim Laden kontrolliert abgebrochen.", "t": ctx.now(), "target": a.target_id}
			cr2.next_decision_t = ctx.now()
	return {"ok": true}


func metrics() -> Dictionary:
	return {"laufend": ctx.executor.running.size(), "reservierungen": ctx.executor.reservations.size(), "angefordert": int(ctx.executor.stats.get("requested", 0))}
