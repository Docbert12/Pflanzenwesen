class_name RequestQueue
extends RefCounted
## Begrenzte Warteschlange für Modellanfragen.
## - Priorität (höher zuerst), bei Gleichstand das Wesen, das am längsten nicht bedient wurde (Fairness),
##   dann die älteste Anfrage.
## - Höchstens EINE offene Anfrage je Wesen (wartend oder laufend). Eine weitere Anfrage desselben
##   Wesens ersetzt die wartende nur, wenn ihre Priorität höher ist (Duplikaterkennung).
## - Ablauf: Anfragen verfallen nach ttl (Simulationszeit), Wiederholungen mit Wartezeit (Echtzeit).
## - Voll: eine neue Anfrage verdrängt höchstens eine wartende mit niedrigerer Priorität, sonst Abweisung.

var max_len: int = 16
var waiting: Array = []          # Einträge (Dictionary)
var running: Dictionary = {}     # request_id -> Eintrag
var served_at: Dictionary = {}   # actor -> letzte Bedienung (ms)
var dropped: Array = []          # zuletzt verworfene Einträge mit Grund (begrenzt, Diagnose)


func size() -> int:
	return waiting.size()


func has_actor(actor: int) -> bool:
	if running.values().any(func(e): return int(e["actor"]) == actor):
		return true
	return waiting.any(func(e): return int(e["actor"]) == actor)


func entry_for_actor(actor: int) -> Dictionary:
	for e in running.values():
		if int(e["actor"]) == actor:
			return e
	for e in waiting:
		if int(e["actor"]) == actor:
			return e
	return {}


## Rückgabe {"ok", "code": "queued"|"duplicate"|"replaced"|"queue_full"|"evicted_other", "message"}
func enqueue(e: Dictionary) -> Dictionary:
	var actor := int(e["actor"])
	for r in running.values():
		if int(r["actor"]) == actor:
			return {"ok": false, "code": "duplicate", "message": "Für #%d läuft bereits eine Anfrage." % actor}
	for i in waiting.size():
		var w: Dictionary = waiting[i]
		if int(w["actor"]) == actor:
			if int(e["priority"]) > int(w["priority"]):
				_drop(w, "durch dringendere Anfrage desselben Wesens ersetzt")
				waiting[i] = e
				return {"ok": true, "code": "replaced", "message": "Wartende Anfrage von #%d ersetzt." % actor}
			return {"ok": false, "code": "duplicate", "message": "Für #%d wartet bereits eine Anfrage." % actor}
	if waiting.size() >= max_len:
		var low := -1
		for i in waiting.size():
			if int(waiting[i]["priority"]) < int(e["priority"]) and (low < 0 or int(waiting[i]["priority"]) < int(waiting[low]["priority"])):
				low = i
		if low < 0:
			return {"ok": false, "code": "queue_full", "message": "Warteschlange voll (%d) – Anfrage nicht angenommen, Wesen handelt lokal." % max_len}
		_drop(waiting[low], "von dringenderer Anfrage verdrängt (Warteschlange voll)")
		waiting.remove_at(low)
		waiting.append(e)
		return {"ok": true, "code": "evicted_other", "message": "Warteschlange voll – niedriger priorisierte Anfrage verdrängt."}
	waiting.append(e)
	return {"ok": true, "code": "queued", "message": ""}


## Nächste versandbereite Anfrage (oder {}). Abgelaufene werden dabei verworfen.
func pop_ready(now_ms: int, sim_t: float) -> Dictionary:
	expire(sim_t)
	var best := -1
	for i in waiting.size():
		var e: Dictionary = waiting[i]
		if int(e.get("next_try_ms", 0)) > now_ms:
			continue
		if best < 0 or _before(e, waiting[best]):
			best = i
	if best < 0:
		return {}
	var e2: Dictionary = waiting[best]
	waiting.remove_at(best)
	return e2


func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["priority"]) != int(b["priority"]):
		return int(a["priority"]) > int(b["priority"])
	var sa := int(served_at.get(int(a["actor"]), -1))
	var sb := int(served_at.get(int(b["actor"]), -1))
	if sa != sb:
		return sa < sb
	return float(a["created_t"]) < float(b["created_t"])


func expire(sim_t: float) -> void:
	for i in range(waiting.size() - 1, -1, -1):
		if float(waiting[i]["expires_t"]) < sim_t:
			_drop(waiting[i], "abgelaufen (nicht rechtzeitig gesendet)")
			waiting.remove_at(i)


func mark_running(e: Dictionary, now_ms: int) -> void:
	running[int(e["id"])] = e
	served_at[int(e["actor"])] = now_ms


func finish(request_id: int) -> Dictionary:
	var e: Dictionary = running.get(request_id, {})
	running.erase(request_id)
	return e


## Wiederholung einplanen (Echtzeit-Wartezeit). Rückgabe false, wenn keine Versuche mehr übrig sind.
func retry(e: Dictionary, now_ms: int, max_retries: int, backoff_s: float) -> bool:
	running.erase(int(e["id"]))
	if int(e.get("attempts", 0)) > max_retries:
		return false
	e["next_try_ms"] = now_ms + int(backoff_s * 1000.0 * int(e["attempts"]))
	waiting.append(e)
	return true


## Alle Einträge eines Wesens entfernen (z. B. Tod). Rückgabe: entfernte Einträge (laufende inklusive).
func remove_actor(actor: int, reason: String) -> Array:
	var out: Array = []
	for i in range(waiting.size() - 1, -1, -1):
		if int(waiting[i]["actor"]) == actor:
			_drop(waiting[i], reason)
			out.append(waiting[i])
			waiting.remove_at(i)
	for rid in running.keys():
		if int(running[rid]["actor"]) == actor:
			_drop(running[rid], reason)
			out.append(running[rid])
			running.erase(rid)
	return out


func clear(reason: String) -> Array:
	var out: Array = waiting.duplicate()
	out.append_array(running.values())
	for e in out:
		_drop(e, reason)
	waiting.clear()
	running.clear()
	return out


func _drop(e: Dictionary, reason: String) -> void:
	dropped.append({"id": e["id"], "actor": e["actor"], "kind": e["kind"], "reason": reason})
	while dropped.size() > 30:
		dropped.pop_front()
