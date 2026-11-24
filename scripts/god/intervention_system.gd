class_name InterventionSystem
extends RefCounted
## Führt Göttereingriffe aus und führt Buch darüber (Weltseite, nicht Wissen der Wesen).
## Trennung (Prompt 4, Abschnitt 12):
##   1. Absicht des Spielers   → record["player"]: gewählte Art und optional zugeordnetes Ereignis.
##                              Nur Diagnose/Auswertung. Gelangt NIE in den Geist eines Wesens.
##   2. Sichtbarer Eingriff    → Weltänderung + Ereignis (food_appeared / material_appeared / healed),
##                              das Perception.broadcast nur an Wesen in Sichtweite verteilt.
##   3. Deutung je Beobachter  → RewardAssociation (im Geist jedes Wesens, das es wahrgenommen hat).
## Bilanz: Nahrung über ResourceLedger.god_kg; Material und Heilung in totals.

var ctx: LifeContext
var history: Array = []          # Eingriffsprotokoll (begrenzt)
var next_id: int = 1
var totals := {"food_kg": 0.0, "material_kg": {}, "healed_damage": 0.0, "count": 0}
var effects: Array = []          # sichtbare Leuchtmarken {pos, kind, until_t} (nur Darstellung)
const HISTORY_MAX := 200
const SELECTABLE := ["raise_arms", "food_given", "food_requested", "request_declined", "food_offered", "offer_not_accepted",
	"food_eaten", "food_taken", "death", "injury_visible", "food_appeared", "material_appeared", "healed"]


func _init(p_ctx: LifeContext) -> void:
	ctx = p_ctx


## Kürzlich geschehene, für den Spieler auswählbare Ereignisse (Spielerwissen aus dem Ereignisprotokoll).
func recent_events(window_s: float = 120.0, n: int = 30, actor_filter: int = 0) -> Array:
	var out: Array = []
	var now := ctx.now()
	var entries := ctx.sim.event_log.recent(1000)
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if now - float(e.get("t", 0.0)) > window_s:
			break
		if not e["type"] in SELECTABLE:
			continue
		var ids: Array = e.get("ids", [])
		var actor := int(ids[0]) if ids.size() > 0 else 0
		if actor_filter != 0 and not actor_filter in ids:
			continue
		out.append({"seq": int(e["seq"]), "type": e["type"], "actor": actor, "ids": ids.duplicate(), "t": float(e["t"])})
		if out.size() >= n:
			break
	return out


func execute(cmd_in: Dictionary) -> Dictionary:
	var prep := GodCommands.prepare(ctx, cmd_in)
	if not prep["ok"]:
		return {"ok": false, "message": "; ".join(prep["errors"]), "id": 0}
	var cmd: Dictionary = prep["cmd"]
	var id := next_id
	next_id += 1
	var now := ctx.now()
	var gc: Dictionary = ctx.m("god")
	var vis := float(ctx.m("observation").get("intervention_visibility_m", 14.0))
	var rec := {"id": id, "t": snappedf(now, 0.001), "kind": cmd["kind"], "target": int(cmd.get("target_id", 0)), "result": {},
		"player": {"linked_event": cmd.get("linked_event", {}).duplicate(), "note": "Spielerabsicht – nur Diagnose, nicht im Geist der Wesen"},
		"observers": []}
	var ev := {}
	match str(cmd["kind"]):
		"gift_food":
			var pos: Vector3 = cmd["position"]
			var food := ctx.db.get_def("food", str(cmd["food_id"]))
			var fc: Dictionary = ctx.c("food")
			var props := {"food_id": str(cmd["food_id"]), "kind": "gabe",
				"energy_j_per_kg": float(food.get("nutrition", 10.0)) * float(fc.get("energy_j_per_kg_per_nutrition_point", 3000.0)),
				"nutrients_g_per_kg": (1.0 - float(food.get("water_content", 0.5))) * float(fc.get("nutrient_g_per_kg_dry_matter", 100.0))}
			var kg := float(cmd["amount_kg"])
			var it := ctx.create_item(props, kg, 0, pos, 0)
			ctx.ledger.god_kg += kg
			totals["food_kg"] = float(totals["food_kg"]) + kg
			rec["result"] = {"item": it.id, "kg": kg, "food_id": cmd["food_id"], "pos": [pos.x, pos.y, pos.z]}
			ev = {"type": "food_appeared", "actor": 0, "target": int(cmd.get("target_id", 0)), "position": pos,
				"consequences": {"kg": kg, "item": it.id, "intervention": id}, "visibility_m": vis}
		"place_material":
			var pos2: Vector3 = cmd["position"]
			var npr := ConstructionSystem.new_piece(ctx, str(cmd["material_id"]), GodCommands.piece_shape(cmd), GodCommands.piece_dims(cmd),
				ctx.sim.thermal.ambient_temperature_k, pos2, "eingriff:%d" % id, "", false, 0.0,
				pow(float(cmd["size_m"]), 3) if str(cmd.get("shape", "block")) == "block" else -1.0)
			if not npr["ok"]:
				return {"ok": false, "message": "Materialstück nicht möglich: %s" % npr["message"], "record": {}}
			var mp: MaterialPiece = npr["piece"]
			var mk: Dictionary = totals["material_kg"]
			mk[mp.material_id] = float(mk.get(mp.material_id, 0.0)) + mp.mass_kg
			rec["result"] = {"piece": mp.id, "material": mp.material_id, "kg": mp.mass_kg, "pos": [pos2.x, pos2.y, pos2.z]}
			ev = {"type": "material_appeared", "actor": 0, "target": int(cmd.get("target_id", 0)), "position": pos2,
				"consequences": {"material": mp.material_id, "kg": mp.mass_kg, "piece": mp.id, "intervention": id}, "visibility_m": vis}
		"heal":
			var cr := ctx.creature(int(cmd["target_id"]))
			var plan := GodCommands.heal_plan(cr, float(cmd["heal_amount"]))
			for p in plan["parts"]:
				cr.health.part_damage[p["id"]] = float(p["to"])
				if float(p["to"]) <= 1e-9:
					cr.health.part_damage.erase(p["id"])
				cr.health.causes.append({"t": now, "part": p["id"], "amount": -(float(p["from"]) - float(p["to"])), "cause": "Heilung (Eingriff %d)" % id})
			while cr.health.causes.size() > 50:
				cr.health.causes.pop_front()
			var was_walk: bool = cr.caps.get("can_walk", false)
			cr.refresh_body(ctx)
			totals["healed_damage"] = float(totals["healed_damage"]) + float(plan["total"])
			rec["result"] = {"healed": plan["total"], "parts": plan["parts"], "can_walk_before": was_walk, "can_walk_after": cr.caps.get("can_walk", false)}
			ev = {"type": "healed", "actor": 0, "target": cr.id, "position": cr.position,
				"consequences": {"healed": snappedf(float(plan["total"]), 0.001), "intervention": id, "sichtbar": "Leuchten am Körper"}, "visibility_m": vis}
	totals["count"] = int(totals["count"]) + 1
	ctx.sim.event_log.add("god_intervention", [rec["target"]] if int(rec["target"]) != 0 else [], {"id": id, "kind": rec["kind"], "result": rec["result"],
		"linked_event": rec["player"]["linked_event"]}, "warning")
	var before := int(ctx.observation_stats.get("observations", 0))
	ctx.last_observers.clear()
	ctx.publish(ev, "warning")
	rec["observers"] = ctx.last_observers.duplicate()
	rec["observed_by"] = int(ctx.observation_stats.get("observations", 0)) - before
	history.append(rec)
	while history.size() > HISTORY_MAX:
		history.pop_front()
	effects.append({"pos": ev["position"], "kind": rec["kind"], "until_t": now + float(gc.get("effect_visible_s", 4.0)), "id": id})
	return {"ok": true, "id": id, "message": "Eingriff #%d ausgeführt: %s. Wahrgenommen von %d Wesen." % [id, GodCommands.label(rec["kind"]), rec["observed_by"]], "record": rec}


func tick() -> void:
	var now := ctx.now()
	effects = effects.filter(func(e): return float(e["until_t"]) > now)


func find(id: int) -> Dictionary:
	for r in history:
		if int(r["id"]) == id:
			return r
	return {}


func to_dict() -> Dictionary:
	var eff: Array = []
	for e in effects:
		var p: Vector3 = e["pos"]
		eff.append({"pos": [p.x, p.y, p.z], "kind": e["kind"], "until_t": e["until_t"], "id": e["id"]})
	return {"history": history.duplicate(true), "next_id": next_id, "totals": totals.duplicate(true), "effects": eff}


func load_dict(d: Dictionary) -> void:
	history = d.get("history", []).duplicate(true)
	for r in history:
		r["id"] = int(r["id"])
		r["target"] = int(r.get("target", 0))
	next_id = int(d.get("next_id", 1))
	var t: Dictionary = d.get("totals", {})
	totals = {"food_kg": float(t.get("food_kg", 0.0)), "material_kg": t.get("material_kg", {}).duplicate(), "healed_damage": float(t.get("healed_damage", 0.0)), "count": int(t.get("count", 0))}
	effects.clear()
	for e in d.get("effects", []):
		effects.append({"pos": Vector3(e["pos"][0], e["pos"][1], e["pos"][2]), "kind": e["kind"], "until_t": float(e["until_t"]), "id": int(e["id"])})
