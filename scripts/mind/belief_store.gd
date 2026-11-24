class_name BeliefStore
extends RefCounted
## Strukturierte, überprüfbare Hypothesen eines Wesens (Vermutungen, keine Weltfakten).
## Lernmodell (dokumentiert in docs/mind_and_learning.md): Beta-Bernoulli mit Vergessensfaktor.
##   vor jeder Aktualisierung: α ← α₀ + (α − α₀)·λ,  β ← β₀ + (β − β₀)·λ      (λ = forgetting)
##   Erfolg mit Gewicht w: α += w;  Gegenbeispiel: β += w
##   p = α/(α+β)  (geschätzte Häufigkeit),  n = α+β−α₀−β₀ (wirksame Erfahrungsmenge, ≤ max_evidence)
##   Konfidenz = n / (n + k)  → nach einer einzelnen Erfahrung höchstens 1/(1+k) = 0,2
##   Erwarteter Wert der Folge = gleitender Mittelwert der erlebten Folgenwerte (getrennt von p und Konfidenz)
## Arten:
##   food_place        „Bei Ort (x,z) finde ich Nahrung.“
##   helper            „Wesen #n hilft mir, wenn ich bitte.“
##   gift_after_action „Nach eigener Handlung X trat ein auffälliges Ereignis auf.“ (scope self)
##   gift_after_other  „Nach Handlung X von #n trat ein auffälliges Ereignis auf.“ (beobachtet)
##   gift_base         Grundhäufigkeit auffälliger Ereignisse in gleich langen Zeitfenstern (Vergleichswert)
## Ein zeitlicher Zusammenhang ist KEINE bewiesene Ursache; gespeichert wird nur die Häufigkeit.

var items: Dictionary = {}     # key -> Dictionary


func get_or_create(key: String, kind: String, subject: String, scope: String, now: float, cfg: Dictionary) -> Dictionary:
	if items.has(key):
		return items[key]
	var bc: Dictionary = cfg.get("beliefs", {})
	var h := {"key": key, "kind": kind, "subject": subject, "scope": scope, "alpha": float(bc.get("prior_alpha", 1.0)), "beta": float(bc.get("prior_beta", 1.0)),
		"n_support": 0, "n_contra": 0, "support": [], "contra": [], "value_avg": 0.0, "value_n": 0, "created_t": now, "updated_t": now}
	items[key] = h
	_evict(cfg)
	return items.get(key, h)


func has_belief(key: String) -> bool:
	return items.has(key)


## Aktualisiert eine Hypothese. evidence: kurze Herkunftsangabe (z. B. Erinnerungs-ID und Zeit).
func update(key: String, success: bool, weight: float, now: float, cfg: Dictionary, evidence: Dictionary = {}, value = null) -> void:
	if not items.has(key) or weight <= 0.0:
		return
	var bc: Dictionary = cfg.get("beliefs", {})
	var h: Dictionary = items[key]
	var a0 := float(bc.get("prior_alpha", 1.0))
	var b0 := float(bc.get("prior_beta", 1.0))
	var lam := float(bc.get("forgetting", 0.97))
	h["alpha"] = a0 + (float(h["alpha"]) - a0) * lam
	h["beta"] = b0 + (float(h["beta"]) - b0) * lam
	var w := minf(weight, 1.0)
	if success:
		h["alpha"] = float(h["alpha"]) + w
		h["n_support"] = int(h["n_support"]) + 1
		_push(h["support"], evidence, now)
	else:
		h["beta"] = float(h["beta"]) + w
		h["n_contra"] = int(h["n_contra"]) + 1
		_push(h["contra"], evidence, now)
	var maxe := float(bc.get("max_evidence", 30.0))
	var n := float(h["alpha"]) + float(h["beta"]) - a0 - b0
	if n > maxe:
		var f := maxe / n
		h["alpha"] = a0 + (float(h["alpha"]) - a0) * f
		h["beta"] = b0 + (float(h["beta"]) - b0) * f
	if value != null and success:
		var vn := int(h["value_n"]) + 1
		h["value_n"] = vn
		h["value_avg"] = float(h["value_avg"]) + (float(value) - float(h["value_avg"])) / minf(vn, 10.0)   # begrenzte Lernrate
	h["updated_t"] = now


static func _push(arr: Array, evidence: Dictionary, now: float) -> void:
	var e := evidence.duplicate()
	e["t"] = snappedf(now, 0.1)
	arr.append(e)
	while arr.size() > 6:
		arr.pop_front()


func p(key: String) -> float:
	if not items.has(key):
		return 0.0
	var h: Dictionary = items[key]
	return float(h["alpha"]) / (float(h["alpha"]) + float(h["beta"]))


func evidence_n(key: String, cfg: Dictionary) -> float:
	if not items.has(key):
		return 0.0
	var bc: Dictionary = cfg.get("beliefs", {})
	var h: Dictionary = items[key]
	return maxf(0.0, float(h["alpha"]) + float(h["beta"]) - float(bc.get("prior_alpha", 1.0)) - float(bc.get("prior_beta", 1.0)))


func confidence(key: String, cfg: Dictionary) -> float:
	var n := evidence_n(key, cfg)
	return n / (n + float(cfg.get("beliefs", {}).get("confidence_k", 4.0)))


func value_avg(key: String) -> float:
	return float(items.get(key, {}).get("value_avg", 0.0))


func of_kind(kind: String) -> Array:
	var out: Array = []
	for k in items:
		if items[k]["kind"] == kind:
			out.append(items[k])
	return out


## Lesbare Aussage aus den Daten (keine erfundenen Gedanken).
static func statement(h: Dictionary) -> String:
	match str(h["kind"]):
		"food_place":
			return "Bei Ort %s finde ich Nahrung" % h["subject"]
		"helper":
			return "#%s gibt mir Nahrung, wenn ich bitte" % h["subject"]
		"gift_after_action":
			return "Nach eigenem „%s“ folgte ein auffälliges Ereignis" % ActionDefinition.label(str(h["subject"]))
		"gift_after_other":
			return "Nach „%s“ eines anderen Wesens folgte ein auffälliges Ereignis" % ActionDefinition.label(str(h["subject"]))
		"gift_base":
			return "Auffällige Ereignisse in meiner Nähe allgemein (Vergleichswert)"
	return str(h["key"])


func _evict(cfg: Dictionary) -> void:
	var cap := int(cfg.get("beliefs", {}).get("capacity", 32))
	while items.size() > cap:
		var worst := ""
		var ws := INF
		for k in items:
			if items[k]["kind"] == "gift_base":
				continue
			var sc := evidence_n(k, cfg) + float(items[k]["updated_t"]) * 1e-4
			if sc < ws:
				ws = sc
				worst = k
		if worst == "":
			break
		items.erase(worst)


func audit() -> Array:
	var out: Array = []
	for k in items:
		var h: Dictionary = items[k]
		if float(h["alpha"]) <= 0.0 or float(h["beta"]) <= 0.0:
			out.append("Überzeugung %s: ungültige Parameter" % k)
	return out


func to_dict() -> Dictionary:
	return {"items": items.duplicate(true)}


static func from_dict(d: Dictionary) -> BeliefStore:
	var s := BeliefStore.new()
	var it: Dictionary = d.get("items", {})
	for k in it:
		var h: Dictionary = it[k].duplicate(true)
		for f in ["n_support", "n_contra", "value_n"]:
			h[f] = int(h.get(f, 0))
		s.items[str(k)] = h
	return s
