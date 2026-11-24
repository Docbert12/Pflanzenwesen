class_name ActionExecutor
extends RefCounted
## Führt Handlungen aus und verwaltet Reservierungen.
## - Pro Wesen läuft höchstens eine Handlung.
## - Reservierungen verhindern Doppelverbrauch: verfügbare Menge = Menge − Summe der Reservierungen.
##   Die Mengenänderung selbst erfolgt atomar in FoodSource.take_reserved (ein Aufruf, ein Thread).
## - Jedes Ende (Erfolg, Fehlschlag, Abbruch, Tod, Zeitlimit, Zielverlust) gibt Reservierungen frei.
## - Ergebnisse werden als strukturierte Ereignisse protokolliert (Grundlage für spätere Lernsysteme).

var ctx: LifeContext
var validator := ActionValidator.new()
var impls: Dictionary = {}
var running: Dictionary = {}       # actor_id -> GameAction
var reservations: Dictionary = {}  # res_id -> Dictionary
var history: Array = []            # begrenzte Liste der letzten Ergebnisse
var next_action_id: int = 1
var next_res_id: int = 1
var stats := {"requested": 0, "rejected": 0, "succeeded": 0, "failed": 0, "cancelled": 0}


func _init(p_ctx: LifeContext) -> void:
	ctx = p_ctx
	impls = {"move_to": MoveToAction.new(), "pick_up": PickUpAction.new(), "eat": EatAction.new(),
		"drop": DropAction.new(), "wait": WaitAction.new(), "request_food": RequestFoodAction.new(),
		"offer_food": OfferFoodAction.new(), "give_food": GiveFoodAction.new(), "decline_request": DeclineRequestAction.new(),
		"raise_arms": RaiseArmsAction.new(), "talk": TalkAction.new(),
		"inspect_object": InspectObjectAction.new(), "equip_tool": EquipToolAction.new(), "strike_target": StrikeTargetAction.new(),
		"deform_material": DeformMaterialAction.new(), "connect_parts": ConnectPartsAction.new(), "disconnect_parts": DisconnectPartsAction.new(),
		"place_in_heater": PlaceInHeaterAction.new(), "pour_into_mold": PourIntoMoldAction.new(),
		"demonstrate_procedure": DemonstrateProcedureAction.new(), "practice_procedure": PracticeProcedureAction.new()}


## Fordert eine Handlung an. Rückgabe {"result": ActionResult, "action": GameAction}.
func request(actor_id: int, type: String, target_id: int = 0, target_pos = null, params: Dictionary = {}) -> Dictionary:
	stats["requested"] += 1
	var a := GameAction.new()
	a.id = next_action_id
	next_action_id += 1
	a.actor_id = actor_id
	a.type = type
	a.target_id = target_id
	a.target_pos = target_pos
	a.params = params.duplicate(true)
	a.required_caps = ActionDefinition.info(type).get("capabilities", []).duplicate()
	if not impls.has(type):
		return _reject(a, ActionResult.fail("unknown_type", "Unbekannter Handlungstyp '%s'." % type))
	var impl: ActionImpl = impls[type]
	if running.has(actor_id):
		var cur: GameAction = running[actor_id]
		if params.get("preempt", false) and ActionDefinition.info(cur.type).get("interruptible", false):
			cancel(actor_id, "preempted", "Durch neue Handlung „%s“ ersetzt." % type)
		else:
			return _reject(a, ActionResult.fail("busy", "Führt bereits „%s“ aus." % cur.type))
	var r := validator.validate_start(a, ctx, impl)
	if not r.ok:
		return _reject(a, r)
	var acfg := ctx.c("actions")
	a.timeout_s = float(params.get("timeout_s", maxf(float(acfg.get("timeout_min_s", 10.0)), impl.estimate_s(a, ctx) * float(acfg.get("timeout_factor", 3.0)))))
	a.status = ActionDefinition.STATUS_RUNNING
	a.started_t = ctx.now()
	running[actor_id] = a
	var sr := impl.start(a, ctx)
	if not sr.ok:
		_finish(a, ActionDefinition.STATUS_FAILED, sr.code, sr.message)
		return {"result": sr, "action": a}
	ctx.log_event("action_started", [actor_id, a.target_id] if a.target_id != 0 else [actor_id], {"action_id": a.id, "type": type})
	return {"result": ActionResult.success(), "action": a}


## Prüft eine Handlung über DIESELBE Schnittstelle wie request(), ohne sie zu starten oder zu
## protokollieren (Prompt 6: Modellvorschläge und Versuchspläne werden so Schritt für Schritt
## gegen den aktuellen Zustand geprüft). Rückgabe ActionResult.
func dry_run(actor_id: int, type: String, target_id: int = 0, target_pos = null, params: Dictionary = {}) -> ActionResult:
	if not impls.has(type):
		return ActionResult.fail("unknown_type", "Unbekannter Handlungstyp '%s'." % type)
	var a := GameAction.new()
	a.actor_id = actor_id
	a.type = type
	a.target_id = target_id
	a.target_pos = target_pos
	a.params = params.duplicate(true)
	a.required_caps = ActionDefinition.info(type).get("capabilities", []).duplicate()
	return validator.validate_start(a, ctx, impls[type])


func _reject(a: GameAction, r: ActionResult) -> Dictionary:
	stats["rejected"] += 1
	a.status = ActionDefinition.STATUS_FAILED
	a.result_code = r.code
	a.result_message = r.message
	a.ended_t = ctx.now()
	_record(a, "action_rejected")
	return {"result": r, "action": a}


func step(dt: float) -> void:
	var actors := running.keys()
	actors.sort()
	for actor_id in actors:
		if not running.has(actor_id):
			continue
		var a: GameAction = running[actor_id]
		var impl: ActionImpl = impls[a.type]
		var v := validator.validate_step(a, ctx, impl)
		if not v.ok:
			_finish(a, ActionDefinition.STATUS_FAILED, v.code, v.message)
			continue
		a.elapsed_s += dt
		var r := impl.step(a, ctx, dt)
		if not r.ok:
			_finish(a, ActionDefinition.STATUS_FAILED, r.code, r.message)
		elif r.data.get("done", false):
			_finish(a, ActionDefinition.STATUS_SUCCEEDED, "ok", r.message)
		elif a.elapsed_s > a.timeout_s:
			_finish(a, ActionDefinition.STATUS_FAILED, "timeout", "Zeitlimit von %.1f s überschritten." % a.timeout_s)
	_expire_reservations()


## Bricht die laufende Handlung eines Wesens ab (z. B. bei Tod, Laden, Entwicklereingriff).
func cancel(actor_id: int, code: String, message: String) -> bool:
	if not running.has(actor_id):
		return false
	_finish(running[actor_id], ActionDefinition.STATUS_CANCELLED, code, message)
	return true


func _finish(a: GameAction, status: String, code: String, message: String) -> void:
	var impl: ActionImpl = impls[a.type]
	impl.cleanup(a, ctx)
	if a.reservation_id != 0:
		release(a.reservation_id, "Handlung beendet (%s)" % status)
	a.status = status
	a.result_code = code
	a.result_message = message
	a.ended_t = ctx.now()
	running.erase(a.actor_id)
	stats[status] = int(stats.get(status, 0)) + 1
	_record(a, "action_" + status)
	var cr := ctx.creature(a.actor_id)
	if cr != null:
		cr.on_action_finished(a, ctx)


func _record(a: GameAction, event_type: String) -> void:
	var entry := {"action_id": a.id, "actor": a.actor_id, "type": a.type, "target": a.target_id, "status": a.status,
		"code": a.result_code, "message": a.result_message, "duration_s": a.elapsed_s, "consumed": a.consumed.duplicate(true), "t": ctx.now()}
	history.append(entry)
	var cap := int(ctx.c("actions").get("result_history", 500))
	while history.size() > cap:
		history.pop_front()
	var sev := "info" if a.status == ActionDefinition.STATUS_SUCCEEDED else "warning"
	if event_type == "action_rejected":
		sev = "info"
	ctx.log_event(event_type, [a.actor_id, a.target_id] if a.target_id != 0 else [a.actor_id], entry, sev)


# ── Reservierungen ──────────────────────────────

## Reserviert kg an einer Nahrungsquelle bzw. einen ganzen Gegenstand. Rückgabe res_id oder 0.
func reserve(actor_id: int, action_id: int, target_id: int, kg: float) -> int:
	if kg <= 0.0:
		return 0
	var res := next_res_id
	if ctx.foods.has(target_id):
		var f: FoodSource = ctx.foods[target_id]
		if f.available_kg() + 1e-12 < kg:
			return 0
		f.reserved[res] = kg
	elif ctx.items.has(target_id):
		var it: FoodItem = ctx.items[target_id]
		if it.reserved_by != 0 or it.carrier_id != 0:
			return 0
		it.reserved_by = res
	else:
		return 0
	next_res_id += 1
	reservations[res] = {"id": res, "owner": actor_id, "action_id": action_id, "target": target_id, "kg": kg,
		"created_t": ctx.now(), "expires_t": ctx.now() + float(ctx.c("actions").get("reservation_ttl_s", 60.0))}
	ctx.log_event("reservation_created", [actor_id, target_id], {"res_id": res, "kg": kg})
	return res


## Reserviert eine GETRAGENE Portion des Handelnden (Anbieten/Geben): sie kann dann weder gegessen
## noch anderweitig vergeben werden. Rückgabe res_id oder 0.
func reserve_carried(actor_id: int, action_id: int, item_id: int) -> int:
	if not ctx.items.has(item_id):
		return 0
	var it: FoodItem = ctx.items[item_id]
	if it.carrier_id != actor_id or it.reserved_by != 0:
		return 0
	var res := next_res_id
	next_res_id += 1
	it.reserved_by = res
	reservations[res] = {"id": res, "owner": actor_id, "action_id": action_id, "target": item_id, "kg": it.mass_kg,
		"created_t": ctx.now(), "expires_t": ctx.now() + float(ctx.c("actions").get("reservation_ttl_s", 60.0)), "carried": true}
	ctx.log_event("reservation_created", [actor_id, item_id], {"res_id": res, "kg": it.mass_kg, "carried": true})
	return res


func release(res_id: int, reason: String) -> void:
	if not reservations.has(res_id):
		return
	var r: Dictionary = reservations[res_id]
	var tgt: int = r["target"]
	if ctx.foods.has(tgt):
		(ctx.foods[tgt] as FoodSource).reserved.erase(res_id)
	elif ctx.items.has(tgt):
		var it: FoodItem = ctx.items[tgt]
		if it.reserved_by == res_id:
			it.reserved_by = 0
	reservations.erase(res_id)
	ctx.log_event("reservation_released", [r["owner"], tgt], {"res_id": res_id, "reason": reason})


func release_all_for(actor_id: int, reason: String) -> void:
	for res in reservations.keys():
		if reservations[res]["owner"] == actor_id:
			release(res, reason)


func _expire_reservations() -> void:
	var now := ctx.now()
	for res in reservations.keys():
		if not reservations.has(res):
			continue
		var r: Dictionary = reservations[res]
		if now <= r["expires_t"]:
			continue
		var owner: int = r["owner"]
		if running.has(owner) and running[owner].reservation_id == res:
			_finish(running[owner], ActionDefinition.STATUS_FAILED, "reservation_expired", "Reservierung abgelaufen.")
		else:
			release(res, "abgelaufen")


## Konsistenzprüfung: Liste gefundener Probleme (leer = in Ordnung).
func audit() -> Array:
	var problems: Array = []
	for res in reservations:
		var r: Dictionary = reservations[res]
		var owner: int = r["owner"]
		if not running.has(owner) or running[owner].reservation_id != res:
			problems.append("Reservierung %d ohne laufende Handlung des Besitzers #%d" % [res, owner])
		var cr := ctx.creature(owner)
		if cr == null or not cr.alive:
			problems.append("Reservierung %d gehört totem/fehlendem Wesen #%d" % [res, owner])
		if not ctx.foods.has(r["target"]) and not ctx.items.has(r["target"]):
			problems.append("Reservierung %d zeigt auf fehlendes Ziel #%d" % [res, r["target"]])
	for fid in ctx.foods:
		var f: FoodSource = ctx.foods[fid]
		var s := 0.0
		for res in f.reserved:
			s += f.reserved[res]
			if not reservations.has(res):
				problems.append("Quelle #%d hält unbekannte Reservierung %d" % [fid, res])
		if s > f.amount_kg + 1e-9:
			problems.append("Quelle #%d: reserviert %.4f kg > Menge %.4f kg" % [fid, s, f.amount_kg])
		if f.amount_kg < -1e-12:
			problems.append("Quelle #%d: negative Menge" % fid)
	for actor in running:
		var cr2 := ctx.creature(actor)
		if cr2 == null or not cr2.alive:
			problems.append("Laufende Handlung eines toten/fehlenden Wesens #%d" % actor)
	return problems


func running_summary(actor_id: int) -> String:
	return (running[actor_id] as GameAction).summary() if running.has(actor_id) else "keine"
