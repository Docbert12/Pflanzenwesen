class_name GoalManager
extends RefCounted
## Bindung an Ziele (gegen ständigen Zielwechsel) und Schnittstelle für externe Zielvorschläge.
## - Ein gewähltes Ziel bleibt mindestens commit_base_s · (0,5 + Beharrlichkeit) aktiv.
## - Während der Bindung erhält die Option des aktuellen Ziels den Zuschlag switch_margin;
##   ein Wechsel braucht also einen deutlich höheren Nutzwert.
## - Ausnahmen: kritischer Hunger (Überleben) oder ungültige Voraussetzungen (Option entfällt).
## - suggest(): VORBEREITET für spätere Ollama-Pläne. Ein Vorschlag ist nur ein begrenzter Zuschlag
##   (≤ suggestion_max_bonus) für eine bereits gültige Option im selben Entscheider – kein zweiter
##   Entscheider, keine Netzwerkverbindung, keine direkte Handlung.

const GOAL_TYPES := ["food", "ask_food", "respond_request", "offer_food", "collect_share", "approach", "explore", "repeat_learned", "rest",
	"plan", "talk", "check_hint"]


static func commit(cr: Creature, goal_type: String, target: int, utility: float, ctx: LifeContext) -> void:
	var now := ctx.now()
	var dc: Dictionary = ctx.m("decision")
	if cr.goal_state.get("type", "") == goal_type and now < float(cr.goal_state.get("commit_until", 0.0)):
		cr.goal_state["utility"] = utility
		return
	cr.goal_state = {"type": goal_type, "target": target, "started_t": now, "utility": utility,
		"commit_until": now + float(dc.get("commit_base_s", 6.0)) * (0.5 + cr.personality.v("beharrlichkeit"))}


static func binding_bonus(cr: Creature, option_id: String, ctx: LifeContext) -> float:
	if cr.goal_state.get("type", "") == option_id and ctx.now() < float(cr.goal_state.get("commit_until", 0.0)):
		return float(ctx.m("decision").get("switch_margin", 0.15))
	return 0.0


## Externer Zielvorschlag (vorbereitet für Ollama). Rückgabe {"ok", "message"}.
static func suggest(cr: Creature, goal_type: String, source: String, weight: float, ctx: LifeContext, ttl_s: float = 30.0) -> Dictionary:
	if not goal_type in GOAL_TYPES:
		return {"ok": false, "message": "Unbekannter Zieltyp '%s'." % goal_type}
	if not cr.alive:
		return {"ok": false, "message": "Wesen ist tot."}
	var w := clampf(weight, 0.0, 1.0)
	cr.suggestions.append({"type": goal_type, "source": source, "weight": w, "expires": ctx.now() + ttl_s})
	while cr.suggestions.size() > 3:
		cr.suggestions.pop_front()
	return {"ok": true, "message": "Vorschlag „%s“ (%s) gespeichert; wirkt nur als Zuschlag ≤ %.2f." % [goal_type, source, float(ctx.m("decision").get("suggestion_max_bonus", 0.2))]}


static func suggestion_bonus(cr: Creature, option_id: String, ctx: LifeContext) -> float:
	var now := ctx.now()
	cr.suggestions = cr.suggestions.filter(func(s): return float(s["expires"]) > now)
	var b := 0.0
	for s in cr.suggestions:
		if s["type"] == option_id:
			b = maxf(b, float(s["weight"]) * float(ctx.m("decision").get("suggestion_max_bonus", 0.2)))
	return b
