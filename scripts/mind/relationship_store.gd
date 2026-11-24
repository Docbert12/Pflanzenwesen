class_name RelationshipStore
extends RefCounted
## Gerichtete Beziehungen: was DIESES Wesen über ein anderes erlebt hat (A→B ≠ B→A).
## Getrennte Größen:
##   familiarity   Vertrautheit (0…1): wächst mit Beobachtungen/Begegnungen, nimmt langsam ab
##   trust α/β     Vertrauen aus eigenen Erfahrungen (Beta-Schätzung: Hilfe ↑, Ablehnung/Negatives ↓)
##   help_received erhaltene Hilfe (Anzahl), help_given gegebene Hilfe
##   negative      erlebte negative Interaktionen, declines erhaltene Ablehnungen
##   similarity    wahrgenommene Ähnlichkeit aus SICHTBAREN Körpermerkmalen (nicht aus verborgenen Genen)
##   origin        beobachtete Herkunft, soweit bekannt (Startpopulation: "unbekannt")
##   honesty       vorbereitet für spätere Sprache – in dieser Version immer null und nicht angezeigt
## Ähnlichkeit wirkt nur als kleine Anfangstendenz; eigene Erfahrungen überwiegen nach wenigen Ereignissen.

var rel: Dictionary = {}     # other id -> Dictionary


## Sichtbare Merkmale eines Körpers (was ein anderes Wesen sehen kann).
static func visible_traits(cr: Creature) -> Dictionary:
	var g: Dictionary = cr.plan.genes
	var missing := 0
	for pid in cr.plan.order:
		if cr.plan.parts[pid]["status"] != "present" and cr.plan.parts[pid]["type"] != "leaf":
			missing += 1
	return {"skin": str(g.get("skin_color", "#2e7d32")), "height_m": float(g.get("height_m", 0.85)), "leaf_shape": str(g.get("leaf_shape", "")),
		"leaves": cr.plan.leaf_ids().size(), "missing_parts": missing}


static func similarity(a: Dictionary, b: Dictionary) -> float:
	var ca := Color.html(a["skin"])
	var cb := Color.html(b["skin"])
	var dc := Vector3(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b).length() / 1.732
	var dh := absf(float(a["height_m"]) - float(b["height_m"])) / 0.3
	var ds := 0.0 if a["leaf_shape"] == b["leaf_shape"] else 1.0
	var dl := absf(int(a["leaves"]) - int(b["leaves"])) / 3.0
	var dm := minf(1.0, absf(int(a["missing_parts"]) - int(b["missing_parts"])) / 2.0)
	return clampf(1.0 - (0.35 * minf(dc * 3.0, 1.0) + 0.2 * minf(dh, 1.0) + 0.15 * ds + 0.15 * minf(dl, 1.0) + 0.15 * dm), 0.0, 1.0)


func ensure(self_cr: Creature, other: Creature, now: float, cfg: Dictionary) -> Dictionary:
	if rel.has(other.id):
		return rel[other.id]
	var rc: Dictionary = cfg.get("relationships", {})
	var sim := similarity(visible_traits(self_cr), visible_traits(other))
	var r := {"familiarity": float(rc.get("similarity_familiarity", 0.12)) * sim, "alpha": 1.0 + float(rc.get("similarity_trust_prior", 0.6)) * sim, "beta": 1.0,
		"help_received": 0, "help_given": 0, "negative": 0, "declines": 0, "requests_to_me": 0, "observed_help_others": 0,
		"similarity": sim, "origin": "unbekannt", "first_t": now, "last_t": now, "honesty": null}
	rel[other.id] = r
	_evict(cfg)
	return rel.get(other.id, r)


func trust(id: int) -> float:
	if not rel.has(id):
		return 0.5
	var r: Dictionary = rel[id]
	return float(r["alpha"]) / (float(r["alpha"]) + float(r["beta"]))


func familiarity(id: int) -> float:
	return float(rel.get(id, {}).get("familiarity", 0.0))


func trust_evidence(id: int) -> float:
	if not rel.has(id):
		return 0.0
	return float(rel[id]["alpha"]) + float(rel[id]["beta"]) - 2.0


## Vertrauensupdate mit begrenzter Lernrate (Vergessensfaktor wie bei Überzeugungen).
func trust_update(id: int, positive: bool, weight: float, cfg: Dictionary) -> void:
	if not rel.has(id) or weight <= 0.0:
		return
	var lam := float(cfg.get("relationships", {}).get("trust_forgetting", 0.98))
	var r: Dictionary = rel[id]
	var a0 := 1.0 + float(cfg.get("relationships", {}).get("similarity_trust_prior", 0.6)) * float(r["similarity"])
	r["alpha"] = a0 + (float(r["alpha"]) - a0) * lam
	r["beta"] = 1.0 + (float(r["beta"]) - 1.0) * lam
	if positive:
		r["alpha"] = float(r["alpha"]) + minf(weight, 1.5)
	else:
		r["beta"] = float(r["beta"]) + minf(weight, 1.5)


func touch(id: int, gain: float, now: float, cfg: Dictionary) -> void:
	if not rel.has(id):
		return
	var r: Dictionary = rel[id]
	var decay := float(cfg.get("relationships", {}).get("familiarity_decay_per_s", 0.0002)) * maxf(0.0, now - float(r["last_t"]))
	r["familiarity"] = clampf(float(r["familiarity"]) - decay + gain, 0.0, 1.0)
	r["last_t"] = now


func _evict(cfg: Dictionary) -> void:
	var cap := int(cfg.get("relationships", {}).get("capacity", 24))
	while rel.size() > cap:
		var worst := 0
		var ws := INF
		for k in rel:
			var r: Dictionary = rel[k]
			var sc := float(r["familiarity"]) + 0.3 * (int(r["help_received"]) + int(r["help_given"]) + int(r["negative"]))
			if sc < ws:
				ws = sc
				worst = k
		rel.erase(worst)


func to_dict() -> Dictionary:
	var out := {}
	for k in rel:
		out[str(k)] = rel[k].duplicate()
	return out


static func from_dict(d: Dictionary) -> RelationshipStore:
	var s := RelationshipStore.new()
	for k in d:
		var r: Dictionary = d[k].duplicate()
		for f in ["help_received", "help_given", "negative", "declines", "requests_to_me", "observed_help_others"]:
			r[f] = int(r.get(f, 0))
		s.rel[int(k)] = r
	return s
