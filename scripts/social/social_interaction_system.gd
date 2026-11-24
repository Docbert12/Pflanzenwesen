class_name SocialInteractionSystem
extends RefCounted
## Weltseitige Verwaltung sozialer Interaktionen (Weltfakten, nicht Wissen der Wesen):
## offene Bitten mit Status. Was ein Wesen davon weiß, steht nur in seinem Geist (Eingang aus Beobachtung).
## Ablauf einer Bitte:
##   request_food (Bittender, 1,5 s Geste, Reichweite 3 m) → Bitte „offen“ (verfällt nach 10 s)
##   Empfänger entscheidet in SEINER Entscheidungsrunde: give_food (Übergabe) oder decline_request
##   Wartezeiten: Bittender 15 s allgemein, 60 s je Ziel nach unbeantworteter, 90 s nach abgelehnter Bitte.

var requests: Dictionary = {}     # id -> {id, from, to, t, status}
var next_id: int = 1
var stats := {"requests": 0, "given": 0, "declined": 0, "expired": 0, "offers": 0, "offers_accepted": 0}


func create_request(from_id: int, to_id: int, now: float) -> int:
	var id := next_id
	next_id += 1
	requests[id] = {"id": id, "from": from_id, "to": to_id, "t": now, "status": "offen"}
	stats["requests"] += 1
	return id


func open_request(from_id: int, to_id: int, now: float, expire_s: float) -> int:
	for id in requests:
		var r: Dictionary = requests[id]
		if r["status"] == "offen" and int(r["from"]) == from_id and int(r["to"]) == to_id and now - float(r["t"]) <= expire_s:
			return id
	return 0


func resolve(id: int, status: String) -> void:
	if requests.has(id) and requests[id]["status"] == "offen":
		requests[id]["status"] = status
		if stats.has(status):
			stats[status] += 1


func tick(now: float, expire_s: float) -> void:
	for id in requests.keys():
		var r: Dictionary = requests[id]
		if r["status"] == "offen" and now - float(r["t"]) > expire_s:
			r["status"] = "expired"
			stats["expired"] += 1
		if r["status"] != "offen" and now - float(r["t"]) > 120.0:
			requests.erase(id)


## Kann der Empfänger eine Portion annehmen? Bewertung durch den Geist des EMPFÄNGERS.
static func would_accept(receiver: Creature, giver_id: int, ctx: LifeContext) -> Dictionary:
	if not receiver.alive:
		return {"ok": false, "reason": "Empfänger lebt nicht"}
	if receiver.carried_item_id != 0:
		return {"ok": false, "reason": "Empfänger trägt bereits etwas"}
	if ctx.executor.running.has(receiver.id) and (ctx.executor.running[receiver.id] as GameAction).type in ["pick_up", "eat", "give_food", "offer_food"]:
		return {"ok": false, "reason": "Empfänger ist gerade mit Nahrung beschäftigt"}
	if float(receiver.caps.get("grasp", 0.0)) <= 0.0:
		return {"ok": false, "reason": "Empfänger kann nichts greifen"}
	var asked: Dictionary = receiver.social.get("pending_request", {})
	if not asked.is_empty() and int(asked["to"]) == giver_id:
		return {"ok": true, "reason": "hatte darum gebeten"}
	var h := receiver.metabolism.hunger()
	var need := float(ctx.m("social").get("accept_hunger_min", 0.25))
	if h >= need:
		return {"ok": true, "reason": "Hunger %.0f %% ≥ %.0f %%" % [h * 100, need * 100]}
	return {"ok": false, "reason": "kein Bedarf (Hunger %.0f %%)" % (h * 100)}


func to_dict() -> Dictionary:
	var rq := {}
	for k in requests:
		rq[str(k)] = requests[k].duplicate()
	return {"requests": rq, "next_id": next_id, "stats": stats.duplicate()}


static func from_dict(d: Dictionary) -> SocialInteractionSystem:
	var s := SocialInteractionSystem.new()
	s.next_id = int(d.get("next_id", 1))
	for k in d.get("requests", {}):
		var r: Dictionary = d["requests"][k].duplicate()
		for f in ["id", "from", "to"]:
			r[f] = int(r[f])
		s.requests[int(k)] = r
	for k in d.get("stats", {}):
		s.stats[k] = int(d["stats"][k])
	return s
