class_name WorkSystem
extends RefCounted
## Arbeitsketten aus eigenem Bedarf (Prompt 6B): Werkzeug herstellen → bearbeiten → Bruchstücke sammeln
## → tragen → lagern / verbauen / im Testofen schmelzen. Jeder Schritt läuft als normale Handlung über
## den ActionExecutor (alle Prüfungen: Reichweite, Masse, Hände, Temperatur, Kapazität). Es gibt KEINEN
## zweiten Entscheider: Ketten werden über DecisionSystem-Optionen („work:start“/„work:continue“)
## gestartet und fortgesetzt; nur Wesen mit abgeschaltetem Verhalten (gezielt ausgelöst) treibt tick().
##
## Ablauf je Schritt (zustandsbasiert, damit Unterbrechen/Speichern/Laden nichts verdoppelt):
##   1. erledigt? (aus dem Weltzustand abgeleitet: gehalten, eingelagert, verbaut, im Tiegel, zerbrochen …)
##   2. sonst: nötige Teilhandlung anfordern (ggf. erst hingehen bzw. Hand freimachen)
## Bedarf (eigener Anlass, nur eigenes Wissen): eigene Baustelle mit freien Plätzen, selbst erzeugte
## lose Stücke + bekanntes Lager, bekanntes Gießverfahren mit Kupfer/Tiegel/Ofen/Form, eigenes
## Einzelbauwerk beginnen. Werkzeugbau nur mit bekanntem Umwickelverfahren (außer gezielt ausgelöst).

const OPS := ["bring", "connect", "check_tool", "equip", "release", "break", "work_copper", "collect", "carry",
	"heat", "wait_molten", "pour", "check", "mark_site"]
const OP_LABEL := {"bring": "Bauteil zum Stiel tragen", "connect": "Hammer binden", "check_tool": "Werkzeug prüfen",
	"equip": "Werkzeug aufnehmen", "release": "Werkzeug ablegen", "break": "Stein zerschlagen", "work_copper": "Kupfer bearbeiten",
	"collect": "Stücke sammeln", "carry": "Stück tragen", "heat": "Tiegel in den Ofen setzen", "wait_molten": "warten, bis es schmilzt",
	"pour": "gießen", "check": "Ergebnis prüfen", "mark_site": "Baustelle markieren"}
const GOAL_LABEL := {"lagern": "Bruchstücke einlagern", "bauen": "Steinreihe bauen", "schmelzen": "Kupfer schmelzen und gießen"}
const MODE_LABEL := {"deposit": "einlagern", "place": "verbauen", "put_in": "in den Tiegel legen", "bring": "hinlegen"}
const MAX_MOVES := 4
const MAX_BREAK_ROUNDS := 8
const MAX_LOOP := 24

var chains: Dictionary = {}      # id -> WorkChain
var by_actor: Dictionary = {}    # actor_id -> chain id (offen)
var next_id: int = 1
var last_end_t: Dictionary = {}  # actor_id -> Zeitpunkt des letzten Kettenendes (Abklingzeit)
var last_site_t: Dictionary = {} # actor_id -> Zeitpunkt, an dem das Wesen zuletzt selbst eine Baustelle anlegte
var pending_drops: Array = []     # Wesen, die nach Kettenende Getragenes ablegen sollen (Hände frei)
var proposals: Dictionary = {}    # actor_id -> geprüfter Modellvorschlag {goal, plan, source, explanation, uncertainty, request_id, t}
var stats := {"started": 0, "completed": 0, "failed": 0, "aborted": 0, "autonomous_started": 0, "autonomous_completed": 0, "paused": 0, "resumed": 0}


static func wc(ctx: LifeContext) -> Dictionary:
	return ctx.tc("work")


func active(cr: Creature) -> WorkChain:
	if cr == null or not by_actor.has(cr.id):
		return null
	var w: WorkChain = chains.get(int(by_actor[cr.id]), null)
	return w if w != null and w.is_open() else null


func of_creature(aid: int) -> Array:
	var out: Array = []
	for id in chains:
		if (chains[id] as WorkChain).actor_id == aid:
			out.append(chains[id])
	out.sort_custom(func(a, b): return a.id > b.id)
	return out


# ── Wissen des Wesens (nur Wahrgenommenes) ─────────────────────────

static func _known(cr: Creature) -> Dictionary:
	return cr.tech.get("objects", {}) if not cr.tech.is_empty() else {}


static func knows_procedure(cr: Creature, prefix: String, min_level: String) -> bool:
	if cr.tech.is_empty():
		return false
	var need := ProceduralKnowledge.level_index(min_level)
	for k in cr.tech.get("procedures", {}):
		if str(k).begins_with(prefix) and ProceduralKnowledge.level_index(str(cr.tech["procedures"][k].get("level", ""))) >= need:
			return true
	return false


## Bekanntes, vorhandenes Schlagwerkzeug (Verbund mit Kopf, Verbindung intakt); gehaltenes bevorzugt.
static func find_tool(cr: Creature, ctx: LifeContext) -> int:
	if cr.held_object_id != 0 and ctx.assemblies.has(cr.held_object_id) and (ctx.assemblies[cr.held_object_id] as Assembly).head_part_id != 0:
		return cr.held_object_id
	var best := 0
	var bd := INF
	for id in _known(cr):
		var top := ConstructionSystem.top_id(ctx, int(id))
		if top == 0 or not ctx.assemblies.has(top):
			continue
		var asm: Assembly = ctx.assemblies[top]
		if asm.head_part_id == 0 or _joint_broken(asm) or not (asm.carrier_id in [0, cr.id]):
			continue
		var d := ctx.distance_xz(cr.position, asm.position)
		if d < bd:
			bd = d
			best = top
	return best


static func _joint_broken(asm: Assembly) -> bool:
	for c in asm.connections:
		if bool((c as Dictionary).get("broken", false)):
			return true
	return false


## Bekannte freie Bauteile für einen Hammer: Stiel (Stab ≥ 0,25 m), Kopf (kompakter Stein 0,08–1 kg), Fasern.
static func find_tool_parts(cr: Creature, ctx: LifeContext, exclude: Array = []) -> Dictionary:
	var handle := 0
	var head := 0
	var fiber := 0
	var hd := INF
	for id in _known(cr):
		var p: MaterialPiece = ctx.material_pieces.get(int(id), null)
		if p == null or not p.is_free() or p.storage_id != 0 or int(id) in exclude:
			continue
		var d := ctx.distance_xz(cr.position, p.position)
		if p.shape == "rod" and p.dims_m.x >= 0.25 and p.material_id in ["wood", "plant_tissue"] and handle == 0:
			handle = p.id
		elif p.material_id == "stone" and p.shape in ["lump", "block"] and p.mass_kg >= 0.08 and p.mass_kg <= 1.0 and d < hd:
			head = p.id
			hd = d
		elif p.material_id == "plant_fiber" and fiber == 0:
			fiber = p.id
	if handle == 0 or head == 0 or fiber == 0:
		return {}
	return {"handle": handle, "head": head, "fiber": fiber}


## Welche Hammerbauteile dem Wesen fehlen (für eine verständliche Begründung).
static func missing_tool_parts(cr: Creature, ctx: LifeContext) -> Array:
	var have := {"Stiel": false, "Steinkopf": false, "Fasern": false}
	for id in _known(cr):
		var p: MaterialPiece = ctx.material_pieces.get(int(id), null)
		if p == null or not p.is_free() or p.storage_id != 0:
			continue
		if p.shape == "rod" and p.dims_m.x >= 0.25 and p.material_id in ["wood", "plant_tissue"]:
			have["Stiel"] = true
		elif p.material_id == "stone" and p.shape in ["lump", "block"] and p.mass_kg >= 0.08 and p.mass_kg <= 1.0:
			have["Steinkopf"] = true
		elif p.material_id == "plant_fiber":
			have["Fasern"] = true
	var out: Array = []
	for k in have:
		if not have[k]:
			out.append(k)
	return out


## Bekannter Stein, der zu groß ist (für eine Hand zu schwer oder größer als ein Bauplatz erlaubt).
## Gewählt wird der KLEINSTE solche Stein (wenigste Schläge, Bruchstücke am ehesten passend), bei
## gleicher Masse der nähere. 0 = keiner bekannt.
static func find_breakable(cr: Creature, ctx: LifeContext, max_kg: float) -> int:
	var best := 0
	var bm := INF
	for id in _known(cr):
		var p: MaterialPiece = ctx.material_pieces.get(int(id), null)
		if p == null or not p.is_free() or p.material_id != "stone" or p.storage_id != 0:
			continue
		if p.mass_kg > max_kg:
			var score := p.mass_kg + 0.01 * ctx.distance_xz(cr.position, p.position)
			if score < bm:
				bm = score
				best = p.id
	return best


## Bekannte lose Steinstücke, die für einen Bauplatz geeignet sind.
static func suitable_stones(cr: Creature, ctx: LifeContext, s: Structure, exclude: Array = []) -> Array:
	var out: Array = []
	for id in _known(cr):
		var p: MaterialPiece = ctx.material_pieces.get(int(id), null)
		if p == null or not p.is_free() or p.storage_id != 0 or p.id in exclude:
			continue
		if StructureSystem.check_part(ctx, s, p.id).ok:
			out.append(p.id)
	return out


# ── Planung (gezielt oder aus Bedarf) ─────────────────────────

## Werkzeugschritte: vorhandenes Werkzeug nutzen oder Hammer aus bekannten Teilen binden.
## Rückgabe {ok, steps, tool, message}. force = gezielt ausgelöst (kein Vorwissen nötig).
static func tool_steps(cr: Creature, ctx: LifeContext, force: bool) -> Dictionary:
	var t := find_tool(cr, ctx)
	if t != 0:
		return {"ok": true, "steps": [{"op": "equip", "obj": t}], "tool": t, "message": "nutzt vorhandenes Werkzeug #%d" % t}
	if not force and not knows_procedure(cr, "verbinden:lashing", str(wc(ctx).get("tool_min_level", "gehört"))):
		return {"ok": false, "steps": [], "tool": 0, "message": "kein Schlagwerkzeug bekannt und kein Verfahren zum Binden bekannt"}
	var parts := find_tool_parts(cr, ctx)
	if parts.is_empty():
		return {"ok": false, "steps": [], "tool": 0, "message": "Bauteile für einen Hammer fehlen: %s nicht bekannt" % ", ".join(missing_tool_parts(cr, ctx))}
	return {"ok": true, "tool": 0, "message": "bindet einen Hammer aus #%d, #%d, #%d" % [parts["handle"], parts["head"], parts["fiber"]],
		"steps": [{"op": "bring", "obj": parts["head"], "target": parts["handle"]}, {"op": "bring", "obj": parts["fiber"], "target": parts["handle"]},
			{"op": "connect", "obj": parts["handle"], "head": parts["head"], "fiber": parts["fiber"]}, {"op": "check_tool"}, {"op": "equip", "obj": -1}]}


## Plan für ein Ziel. opts: storage, site, crucible, heater, mold, target, pieces, force.
static func plan(goal: String, cr: Creature, ctx: LifeContext, opts: Dictionary) -> Dictionary:
	var force := bool(opts.get("force", false))
	var steps: Array = []
	var msg := ""
	match goal:
		"lagern":
			var sid := int(opts.get("storage", 0))
			if not ctx.storages.has(sid):
				return {"ok": false, "message": "kein bekanntes Lager"}
			var tgt := int(opts.get("target", 0))
			if tgt != 0:
				var ts := tool_steps(cr, ctx, force)
				if not ts["ok"]:
					return {"ok": false, "message": ts["message"]}
				steps.append_array(ts["steps"])
				steps.append({"op": "break", "target": tgt})
				steps.append({"op": "release"})
				msg = "%s; zerschlägt #%d; lagert die Bruchstücke ein" % [ts["message"], tgt]
			steps.append({"op": "collect", "dest": sid, "mode": "deposit", "pieces": opts.get("pieces", []).duplicate()})
			steps.append({"op": "check"})
			return {"ok": true, "steps": steps, "dest": sid, "target": tgt, "message": msg if msg != "" else "lagert lose Stücke ein"}
		"bauen":
			var st: Structure = ctx.structures.get(int(opts.get("site", 0)), null)
			if st == null:
				return {"ok": false, "message": "keine bekannte Baustelle"}
			var free := st.slots.size() - st.filled()
			if free <= 0:
				return {"ok": false, "message": "Baustelle bereits fertig"}
			var have := suitable_stones(cr, ctx, st)
			var tgt2 := int(opts.get("target", 0))
			if tgt2 == 0 and have.size() < free:
				tgt2 = find_breakable(cr, ctx, _carry_or_slot_limit(cr, ctx, st))
			if tgt2 != 0:
				var ts2 := tool_steps(cr, ctx, force)
				if not ts2["ok"]:
					if have.is_empty():
						return {"ok": false, "message": ts2["message"]}
					tgt2 = 0
				else:
					steps.append_array(ts2["steps"])
					steps.append({"op": "break", "target": tgt2})
					steps.append({"op": "release"})
					msg = "%s; zerschlägt #%d" % [ts2["message"], tgt2]
			if tgt2 == 0 and have.is_empty():
				return {"ok": false, "message": "kein geeigneter Stein bekannt (und keiner zum Zerkleinern)"}
			steps.append({"op": "collect", "dest": st.id, "mode": "place", "pieces": have.slice(0, free)})
			steps.append({"op": "check"})
			return {"ok": true, "steps": steps, "dest": st.id, "target": tgt2, "message": (msg + "; " if msg != "" else "") + "setzt Steine auf %d freie Plätze" % free}
		"schmelzen":
			var cru := int(opts.get("crucible", 0))
			var hid := int(opts.get("heater", 0))
			var mold := int(opts.get("mold", 0))
			if not ctx.heaters.has(hid):
				return {"ok": false, "message": "keine Wärmequelle: Ofen #%d fehlt" % hid if hid != 0 else "keine Wärmequelle bekannt"}
			if cru == 0:
				return {"ok": false, "message": "kein Tiegel bekannt"}
			if not ctx.material_pieces.has(mold):
				return {"ok": false, "message": "keine Gussform bekannt"}
			var cup := PutIntoContainerAction.cup_of(ctx, cru)
			if cup == null:
				return {"ok": false, "message": "kein Tiegel"}
			var tgt3 := int(opts.get("target", 0))
			var pieces: Array = opts.get("pieces", []).duplicate()
			if tgt3 != 0:
				var ts3 := tool_steps(cr, ctx, force)
				if not ts3["ok"]:
					return {"ok": false, "message": ts3["message"]}
				steps.append_array(ts3["steps"])
				steps.append({"op": "work_copper", "target": tgt3})
				steps.append({"op": "release"})
				if not (tgt3 in pieces):
					pieces.append(tgt3)
				msg = "%s; bearbeitet #%d mit dem Hammer" % [ts3["message"], tgt3]
			steps.append({"op": "collect", "dest": cup.id, "mode": "put_in", "pieces": pieces})
			steps.append({"op": "heat", "obj": cru, "heater": hid})
			steps.append({"op": "wait_molten", "obj": cru})
			steps.append({"op": "pour", "obj": cru, "mold": mold})
			steps.append({"op": "check"})
			return {"ok": true, "steps": steps, "dest": cup.id, "target": tgt3, "message": (msg + "; " if msg != "" else "") + "legt Kupfer in Tiegel #%d, schmilzt im Ofen #%d, gießt in Form #%d" % [cup.id, hid, mold]}
	return {"ok": false, "message": "unbekanntes Ziel %s" % goal}


## Ab welcher Masse ein Stein zerkleinert werden muss: größer als ein Bauplatz erlaubt oder für eine Hand zu schwer.
static func _carry_or_slot_limit(cr: Creature, ctx: LifeContext, st: Structure) -> float:
	return minf(float(StructureSystem.bp(ctx, st.blueprint).get("max_kg", 2.2)), ToolUseSystem.carry_limit_kg(cr, ctx))


# ── Bedarf → Optionen für den Entscheider ─────────────────────────

## Anlässe aus eigenem Wissen. Rückgabe [{goal, need, opts, why}] (nicht sortiert).
func needs(cr: Creature, ctx: LifeContext) -> Array:
	var c := wc(ctx)
	var out: Array = []
	var rad := float(c.get("candidate_radius_m", 14.0))
	var known := _known(cr)
	for id in known:
		var e: Dictionary = known[id]
		# eigene Baustelle mit freien Plätzen
		if e.get("bauwerk", false) and ctx.structures.has(int(id)):
			var st: Structure = ctx.structures[int(id)]
			if st.initiator == cr.id and st.filled() < st.slots.size() and ctx.distance_xz(cr.position, st.position) <= rad:
				out.append({"goal": "bauen", "need": float(c.get("need_site", 0.45)) * (1.0 - float(st.filled()) / maxf(1.0, st.slots.size())),
					"opts": {"site": st.id}, "why": "eigene Baustelle #%d hat freie Plätze (%d/%d belegt)" % [st.id, st.filled(), st.slots.size()]})
		# bekanntes Lager mit Platz + selbst erzeugte lose Stücke
		if e.get("lager", false) and ctx.storages.has(int(id)) and e.get("platz_frei", true):
			var loose: Array = []
			for w in of_creature(cr.id):
				for pid in (w as WorkChain).produced:
					var p: MaterialPiece = ctx.material_pieces.get(int(pid), null)
					if p != null and p.is_free() and p.storage_id == 0 and known.has(pid):
						loose.append(p.id)
			if not loose.is_empty():
				out.append({"goal": "lagern", "need": float(c.get("need_store", 0.3)) * minf(1.0, loose.size() / 3.0),
					"opts": {"storage": int(id), "pieces": loose}, "why": "%d selbst erzeugte Stücke liegen lose; Lager #%d hat Platz" % [loose.size(), int(id)]})
	# bekanntes Gießverfahren + Kupfer + Tiegel + freie Heizung + Form
	if knows_procedure(cr, "giessen:", "zugesehen"):
		var cast := _cast_setup(cr, ctx)
		if not cast.is_empty():
			out.append({"goal": "schmelzen", "need": float(c.get("need_cast", 0.35)), "opts": cast, "why": "kennt das Gießen; Kupfer, Tiegel, Ofen und Form bekannt"})
	# eigenes Einzelbauwerk beginnen: wer schon selbst erfolgreich gebaut hat, will es eher wieder
	# (Kompetenzerleben); sonst selten und nur beharrliche Wesen. Immer nur mit bekanntem Stein.
	var built_before := knows_procedure(cr, "bauen:steinreihe", "erfolgreich")
	if (built_before or cr.personality.v("beharrlichkeit") >= float(c.get("start_site_min_persistence", 0.55))) and _own_open_site(cr, ctx) == null \
			and ctx.now() - float(last_site_t.get(cr.id, -1.0e9)) > float(c.get("start_site_cooldown_s", 600.0)):
		var stones := 0
		for id2 in known:
			var p2: MaterialPiece = ctx.material_pieces.get(int(id2), null)
			if p2 != null and p2.material_id == "stone" and p2.is_free() and p2.mass_kg >= 0.12:
				stones += 1
		if stones >= int(c.get("start_site_min_stones", 1)):
			out.append({"goal": "bauen", "need": float(c.get("need_start_site_known" if built_before else "need_start_site", 0.2)), "opts": {"start_site": true},
				"why": "möchte eine eigene Steinreihe anlegen (%d bekannte Steine%s)" % [stones, "; hat schon selbst erfolgreich gebaut" if built_before else ""]})
	return out


func _own_open_site(cr: Creature, ctx: LifeContext) -> Structure:
	for sid in ctx.structures:
		var st: Structure = ctx.structures[sid]
		if st.initiator == cr.id and st.status != "fertig":
			return st
	return null


static func _cast_setup(cr: Creature, ctx: LifeContext) -> Dictionary:
	var known := _known(cr)
	var cru := 0
	var hid := 0
	var mold := 0
	var copper: Array = []
	for id in known:
		var top := ConstructionSystem.top_id(ctx, int(id))
		if known[id].get("heater", false) and ctx.heaters.has(int(id)) and (ctx.heaters[int(id)] as TestHeater).slot_id == 0:
			hid = int(id)
		if top != 0 and PutIntoContainerAction.cup_of(ctx, top) != null and ctx.assemblies.has(top):
			cru = top
		var p: MaterialPiece = ctx.material_pieces.get(int(id), null)
		if p != null and p.shape == "mold" and ConstructionSystem.contents_of(ctx, p.id).is_empty():
			mold = p.id
		if p != null and p.material_id == "copper" and p.is_free() and p.liquid_fraction() == 0.0 and p.mass_kg <= 0.2:
			copper.append(p.id)
	if cru == 0 or hid == 0 or mold == 0 or copper.is_empty():
		return {}
	return {"crucible": cru, "heater": hid, "mold": mold, "pieces": copper.slice(0, 2)}


func options(cr: Creature, ctx: LifeContext, free: float, critical: bool) -> Array:
	var c := wc(ctx)
	if critical or not bool(c.get("enabled", true)) or cr.tech.is_empty():
		return []
	var pers := cr.personality
	var w := active(cr)
	if w != null:
		var o := {"id": "work:continue", "goal": "work", "u": 0.0, "parts": {"arbeit_fortsetzen": float(c.get("weight", 0.55)) * (0.6 + 0.6 * pers.v("beharrlichkeit")) * free + 0.15}}
		if w.status == "pausiert":
			o["parts"]["pausiert"] = -0.05
		ExperimentSystem._sum(o)
		return [o]
	if cr.metabolism.hunger() > float(c.get("max_hunger", 0.5)):
		return []
	# Geprüfter Modellvorschlag (Prompt 6B): konkurriert wie jede Option; verfällt nach proposal_ttl_s
	var out_model: Array = []
	if proposals.has(cr.id):
		var pr: Dictionary = proposals[cr.id]
		if ctx.now() - float(pr["t"]) > float(c.get("proposal_ttl_s", 180.0)):
			proposals.erase(cr.id)
		else:
			var um := float(c.get("weight", 0.55)) * float(c.get("need_model", 0.4)) * (1.0 - 0.5 * float(pr["uncertainty"])) * free
			out_model.append({"id": "work:model", "goal": "work", "u": um, "parts": {"modellvorschlag": um}, "why": str(pr["explanation"])})
	if ctx.now() - float(last_end_t.get(cr.id, -1.0e9)) < float(c.get("cooldown_s", 20.0)):
		return out_model
	var best := {}
	var best_u := -1.0e9
	for n in needs(cr, ctx):
		var u := float(c.get("weight", 0.55)) * float(n["need"]) * (0.5 + 0.5 * pers.v("beharrlichkeit")) * free
		if u > best_u:
			best_u = u
			best = n
	if best.is_empty() or best_u <= 0.02:
		return out_model
	return out_model + [{"id": "work:start", "goal": "work", "u": best_u, "parts": {"bedarf": best_u}, "need": best, "why": str(best["why"])}]


func execute_option(cr: Creature, o: Dictionary, ctx: LifeContext) -> Dictionary:
	if str(o["id"]) == "work:continue":
		return advance(cr, ctx)
	if str(o["id"]) == "work:model":
		var pr: Dictionary = proposals.get(cr.id, {})
		proposals.erase(cr.id)
		if pr.is_empty():
			return {"ok": false, "state": "", "reason": "kein Modellvorschlag mehr"}
		var stm := start(cr, str(pr["goal"]), pr["plan"], str(pr["source"]), true, ctx, str(pr["explanation"]))
		if not stm["ok"]:
			return {"ok": false, "state": "", "reason": stm["message"]}
		var am := advance(cr, ctx)
		return {"ok": true, "state": "arbeitet", "reason": "Arbeitskette #%d nach %s: %s. %s" % [stm["chain"].id, str(pr["source"]), str(pr["explanation"]), am["reason"]]}
	var n: Dictionary = o.get("need", {})
	var opts: Dictionary = (n.get("opts", {}) as Dictionary).duplicate(true)
	if opts.get("start_site", false):
		var spot = _site_spot(cr, ctx)
		if spot == null:
			return {"ok": false, "state": "", "reason": "kein freier ebener Platz für eine Baustelle"}
		var st := StructureSystem.create_site(ctx, "steinreihe", spot, cr.heading, cr.id, "angelegt von #%d (eigener Bedarf)" % cr.id)
		last_site_t[cr.id] = ctx.now()
		StructureSystem.perceive(cr, ctx, 30.0)
		opts = {"site": st.id}
	var p := plan(str(n.get("goal", "")), cr, ctx, opts)
	if not p["ok"]:
		last_end_t[cr.id] = ctx.now()
		return {"ok": false, "state": "", "reason": "Arbeit nicht planbar: %s" % p["message"]}
	var st2 := start(cr, str(n["goal"]), p, "eigener Bedarf", true, ctx, str(n.get("why", "")))
	if not st2["ok"]:
		return {"ok": false, "state": "", "reason": st2["message"]}
	var a := advance(cr, ctx)
	return {"ok": true, "state": "arbeitet", "reason": "Arbeitskette #%d (%s): %s. %s" % [st2["chain"].id, GOAL_LABEL.get(n["goal"], n["goal"]), p["message"], a["reason"]]}


## Freier, begehbarer Platz für eine kleine Baustelle in der Nähe (3 Plätze in Blickrichtung).
static func _site_spot(cr: Creature, ctx: LifeContext):
	if ctx.nav == null:
		return cr.position + Vector3(sin(cr.heading), 0, cos(cr.heading)) * 1.0
	for r in [1.2, 1.8, 2.5]:
		for k in 8:
			var ang := cr.heading + k * PI / 4.0
			var p: Vector3 = cr.position + Vector3(sin(ang), 0, cos(ang)) * float(r)
			var ok := true
			for i in 3:
				var q: Vector3 = p + Vector3(cos(cr.heading), 0, -sin(cr.heading)) * (0.22 * i)
				var col := ctx.nav.world_to_col(q)
				if not ctx.nav.in_bounds(col) or not ctx.nav.is_walkable(col):
					ok = false
					break
			if ok:
				return Vector3(p.x, ctx.nav.ground_y(ctx.nav.world_to_col(p)), p.z)
	return null


# ── Start, Pause, Ende ─────────────────────────

func start(cr: Creature, goal: String, p: Dictionary, source: String, autonomous: bool, ctx: LifeContext, why: String = "") -> Dictionary:
	if active(cr) != null:
		return {"ok": false, "message": "Wesen #%d arbeitet bereits an Kette #%d." % [cr.id, active(cr).id]}
	var w := WorkChain.new()
	w.id = next_id
	next_id += 1
	w.actor_id = cr.id
	w.goal = goal
	w.goal_text = GOAL_LABEL.get(goal, goal)
	w.source = source
	w.autonomous = autonomous
	w.started_t = ctx.now()
	w.target_id = int(p.get("target", 0))
	w.dest_id = int(p.get("dest", 0))
	for s in p.get("steps", []):
		var e: Dictionary = (s as Dictionary).duplicate(true)
		e["status"] = "offen"
		w.steps.append(e)
	w.add_log(ctx.now(), "Start (%s): %s%s" % [source, str(p.get("message", "")), (" – Anlass: " + why) if why != "" else ""])
	chains[w.id] = w
	by_actor[cr.id] = w.id
	stats["started"] += 1
	if autonomous:
		stats["autonomous_started"] += 1
	ctx.log_event("work_started", [cr.id], {"chain": w.id, "goal": goal, "source": source, "autonomous": autonomous, "steps": w.steps.size()})
	return {"ok": true, "chain": w, "message": "Arbeitskette #%d gestartet" % w.id}


## Gezielt ausgelöst (Testszene/Entwicklermodus): Plan bauen und starten, Herkunft wird angezeigt.
func trigger(cr: Creature, goal: String, opts: Dictionary, ctx: LifeContext, source: String = "gezielt ausgelöst (Testszene)") -> Dictionary:
	var o := opts.duplicate(true)
	o["force"] = true
	var p := plan(goal, cr, ctx, o)
	if not p["ok"]:
		return {"ok": false, "message": "Nicht planbar: %s" % p["message"]}
	var st := start(cr, goal, p, source, false, ctx)
	if st["ok"] and not cr.behavior_enabled:
		advance(cr, ctx)
	return st


func pause(cr: Creature, reason: String, ctx: LifeContext) -> void:
	var w := active(cr)
	if w == null or w.status != "läuft":
		return
	w.status = "pausiert"
	w.pause_reason = reason
	w.paused_t = ctx.now()
	stats["paused"] += 1
	# Zweihändig Getragenes wird abgelegt (sonst keine Hand frei für Nahrung)
	if cr.hold_mode == "two" and cr.held_object_id != 0:
		ToolUseSystem.release_at(ctx, cr, DropAction.put_down_point(ctx, cr, cr.held_object_id), "abgelegt wegen Unterbrechung")
	w.add_log(ctx.now(), "pausiert: %s" % reason)


func abort(cr: Creature, reason: String, ctx: LifeContext) -> void:
	var w := active(cr)
	if w != null:
		_finish(cr, w, "abgebrochen", reason, ctx)


func _finish(cr: Creature, w: WorkChain, status: String, reason: String, ctx: LifeContext) -> Dictionary:
	w.status = status
	w.ended_t = ctx.now()
	if status != "abgeschlossen":
		w.abort_reason = reason
	w.add_log(ctx.now(), "%s: %s" % [status, reason])
	by_actor.erase(w.actor_id)
	last_end_t[w.actor_id] = ctx.now()
	match status:
		"abgeschlossen":
			stats["completed"] += 1
			if w.autonomous:
				stats["autonomous_completed"] += 1
		"fehlgeschlagen":
			stats["failed"] += 1
		_:
			stats["aborted"] += 1
	ctx.log_event("work_finished", [w.actor_id], {"chain": w.id, "status": status, "reason": reason, "moved_kg": snappedf(w.moved_kg, 0.001), "delivered": w.delivered.size()})
	# Getragenes Material (kein Werkzeug) nach dem Ende ablegen – über eine normale Ablegehandlung im nächsten Takt
	if cr != null and cr.alive and cr.held_object_id != 0 and not ctx.assemblies.has(cr.held_object_id) and not (w.actor_id in pending_drops):
		pending_drops.append(w.actor_id)
	return {"ok": status == "abgeschlossen", "state": status, "reason": "Arbeitskette #%d %s: %s" % [w.id, status, reason]}


func _fail(cr: Creature, w: WorkChain, s: Dictionary, reason: String, ctx: LifeContext) -> Dictionary:
	s["status"] = "fehlgeschlagen"
	s["note"] = reason
	return _finish(cr, w, "fehlgeschlagen", reason, ctx)


func _done(w: WorkChain, s: Dictionary, note: String, ctx: LifeContext) -> void:
	s["status"] = "erledigt" if not s.get("skipped", false) else "übersprungen"
	if note != "":
		s["note"] = note
	w.add_log(ctx.now(), "Schritt %d (%s): %s" % [w.step_i + 1, OP_LABEL.get(s["op"], s["op"]), note if note != "" else s["status"]])
	w.step_i += 1


# ── Ausführung ─────────────────────────

func tick(ctx: LifeContext) -> void:
	for aid in pending_drops.duplicate():
		var c := ctx.creature(int(aid))
		if c == null or not c.alive or c.held_object_id == 0 or ctx.assemblies.has(c.held_object_id) or active(c) != null:
			pending_drops.erase(aid)
			continue
		if not ctx.executor.running.has(c.id):
			pending_drops.erase(aid)
			var rd := ctx.executor.request(c.id, "drop", 0, null, {"object": true})
			if not rd["result"].ok:
				ToolUseSystem.release_at(ctx, c, DropAction.put_down_point(ctx, c, c.held_object_id), "nach Kettenende abgelegt")
	var ids := by_actor.keys()
	ids.sort()
	for aid in ids:
		var cr := ctx.creature(int(aid))
		var w: WorkChain = chains.get(int(by_actor[aid]), null)
		if w == null:
			by_actor.erase(aid)
			continue
		if cr == null or not cr.alive:
			_finish(cr, w, "abgebrochen", "Wesen gestorben", ctx)
			continue
		if w.status == "pausiert" and ctx.now() - w.paused_t > float(wc(ctx).get("pause_max_s", 240.0)):
			_finish(cr, w, "abgebrochen", "zu lange unterbrochen (%s)" % w.pause_reason, ctx)
			continue
		if not cr.behavior_enabled and not ctx.executor.running.has(cr.id):
			# gezielt ausgelöste Ketten: nach einer Unterbrechung kurz innehalten, dann fortsetzen
			if w.status == "läuft" or (w.status == "pausiert" and ctx.now() - w.paused_t >= float(wc(ctx).get("resume_after_s", 2.0))):
				advance(cr, ctx)


func advance(cr: Creature, ctx: LifeContext) -> Dictionary:
	var w := active(cr)
	if w == null:
		return {"ok": false, "state": "", "reason": "keine Arbeitskette"}
	if ctx.executor.running.has(cr.id):
		return {"ok": true, "state": "arbeitet", "reason": "Schritt läuft"}
	if w.status == "pausiert":
		w.status = "läuft"
		stats["resumed"] += 1
		w.add_log(ctx.now(), "fortgesetzt nach Pause (%s)" % w.pause_reason)
		w.pause_reason = ""
	if w.steps.size() > int(wc(ctx).get("max_steps", 80)):
		return _finish(cr, w, "fehlgeschlagen", "zu viele Schritte (Schutz vor Endlosschleife)", ctx)
	for _guard in MAX_LOOP:
		if w.step_i >= w.steps.size():
			return _complete(cr, w, ctx)
		var s: Dictionary = w.steps[w.step_i]
		var r := _step(cr, w, s, ctx)
		if not w.is_open():
			return r
		if r.get("next", false):
			continue
		return r
	return {"ok": true, "state": "arbeitet", "reason": "mehrere Schritte übersprungen"}


## Ein Schritt: erledigt → weiter (next = true); sonst Teilhandlung anfordern.
func _step(cr: Creature, w: WorkChain, s: Dictionary, ctx: LifeContext) -> Dictionary:
	var op := str(s["op"])
	s["status"] = "läuft"
	match op:
		"equip":
			var oid := int(s.get("obj", 0))
			if oid == -1:
				oid = w.tool_id
				s["obj"] = oid
			if oid == 0 or not ConstructionSystem.is_object(ctx, oid):
				return _fail(cr, w, s, "Werkzeug fehlt", ctx)
			w.current_obj = oid
			if ConstructionSystem.top_id(ctx, oid) == cr.held_object_id:
				if ctx.assemblies.has(cr.held_object_id) and w.tool_id == 0:
					w.tool_id = cr.held_object_id
				_done(w, s, "#%d in der Hand" % oid, ctx)
				return {"next": true}
			return _request_with_prep(cr, w, s, "equip_tool", oid, {}, ctx)
		"release":
			if cr.held_object_id == 0:
				_done(w, s, "Hand frei", ctx)
				return {"next": true}
			return _req(cr, w, "drop", 0, null, {"object": true}, "legt #%d ab" % cr.held_object_id, ctx)
		"bring":
			return _carry(cr, w, s, int(s.get("obj", 0)), int(s.get("target", 0)), "bring", ctx)
		"carry":
			return _carry(cr, w, s, int(s.get("obj", 0)), int(s.get("dest", 0)), str(s.get("mode", "deposit")), ctx)
		"connect":
			var h: MaterialPiece = ctx.material_pieces.get(int(s.get("obj", 0)), null)
			if h != null and h.assembly_id != 0 and ctx.assemblies.has(h.assembly_id) and (ctx.assemblies[h.assembly_id] as Assembly).part_ids.has(int(s.get("head", 0))):
				w.tool_id = h.assembly_id
				_done(w, s, "Hammer #%d gebunden" % w.tool_id, ctx)
				return {"next": true}
			w.current_obj = int(s.get("obj", 0))
			return _request_with_prep(cr, w, s, "connect_parts", int(s.get("obj", 0)), {"head": int(s.get("head", 0)), "fiber": int(s.get("fiber", 0)), "label": "Hammer"}, ctx)
		"check_tool":
			if w.tool_id == 0 or not ctx.assemblies.has(w.tool_id):
				return _fail(cr, w, s, "kein Werkzeug entstanden", ctx)
			var ev := ObjectEvaluator.evaluate(ctx, cr, w.tool_id)
			s["evaluation"] = ObjectEvaluator.lines(ev)
			if not ev.get("suitable", false):
				return _fail(cr, w, s, "Werkzeug #%d ungeeignet: %s" % [w.tool_id, "; ".join(ObjectEvaluator.lines(ev).slice(0, 2))], ctx)
			_done(w, s, "Werkzeug #%d geprüft: geeignet" % w.tool_id, ctx)
			return {"next": true}
		"break":
			var tid := int(s.get("target", 0))
			var t: MaterialPiece = ctx.material_pieces.get(tid, null)
			if t == null:
				_done(w, s, "#%d zerbrochen" % tid, ctx)
				return {"next": true}
			w.current_obj = tid
			if int(s.get("rounds", 0)) >= MAX_BREAK_ROUNDS:
				return _fail(cr, w, s, "#%d zerbricht nicht (%d Schlagfolgen)" % [tid, MAX_BREAK_ROUNDS], ctx)
			if w.tool_id != 0 and cr.held_object_id != w.tool_id:
				if not ctx.assemblies.has(w.tool_id):
					return _replan_tool(cr, w, s, "Werkzeug #%d existiert nicht mehr" % w.tool_id, ctx)
				w.steps.insert(w.step_i, {"op": "equip", "obj": w.tool_id, "status": "offen"})
				return {"next": true}
			return _request_with_prep(cr, w, s, "deform_material", tid, {"strikes": int(ctx.tc("strike").get("max_strikes_per_action", 30))}, ctx)
		"work_copper":
			var cid := int(s.get("target", 0))
			var cp: MaterialPiece = ctx.material_pieces.get(cid, null)
			if cp == null:
				return _fail(cr, w, s, "Kupferstück #%d fehlt" % cid, ctx)
			if not s.has("strain0"):
				s["strain0"] = cp.strain
			if cp.strain > float(s["strain0"]) + 0.005 or s.get("worked", false):
				_done(w, s, "#%d verformt (Dehnung %.3f), nicht gebrochen" % [cid, cp.strain], ctx)
				return {"next": true}
			w.current_obj = cid
			if w.tool_id != 0 and cr.held_object_id != w.tool_id and ctx.assemblies.has(w.tool_id):
				w.steps.insert(w.step_i, {"op": "equip", "obj": w.tool_id, "status": "offen"})
				return {"next": true}
			return _request_with_prep(cr, w, s, "deform_material", cid, {"strikes": 6}, ctx)
		"collect":
			return _collect(cr, w, s, ctx)
		"heat":
			var cru := int(s.get("obj", 0))
			var hid := int(s.get("heater", 0))
			if not ctx.heaters.has(hid):
				return _fail(cr, w, s, "keine Wärmequelle (Ofen #%d fehlt)" % hid, ctx)
			if ToolUseSystem.heater_of(ctx, cru) == hid:
				_done(w, s, "Tiegel #%d steht im Ofen #%d" % [cru, hid], ctx)
				return {"next": true}
			if (ctx.heaters[hid] as TestHeater).slot_id != 0:
				return _fail(cr, w, s, "keine freie Wärmequelle (Ofen #%d belegt)" % hid, ctx)
			w.current_obj = cru
			if cr.held_object_id != 0 and cr.held_object_id != ConstructionSystem.top_id(ctx, cru):
				return _req(cr, w, "drop", 0, null, {"object": true}, "legt #%d ab, um den Tiegel zu nehmen" % cr.held_object_id, ctx)
			return _request_with_prep(cr, w, s, "place_in_heater", cru, {"heater": hid}, ctx, (ctx.heaters[hid] as TestHeater).position)
		"wait_molten":
			var cup := PutIntoContainerAction.cup_of(ctx, int(s.get("obj", 0)))
			if cup == null:
				return _fail(cr, w, s, "Tiegel fehlt", ctx)
			var cont := ConstructionSystem.contents_of(ctx, cup.id)
			if cont.is_empty():
				return _fail(cr, w, s, "Tiegel ist leer", ctx)
			var liquid := true
			for c in cont:
				if (c as MaterialPiece).liquid_fraction() < float(ctx.tc("casting").get("min_liquid_fraction", 0.95)):
					liquid = false
			if liquid:
				_done(w, s, "Inhalt geschmolzen", ctx)
				return {"next": true}
			if ToolUseSystem.heater_of(ctx, ConstructionSystem.top_id(ctx, cup.id)) == 0:
				return _fail(cr, w, s, "keine Wärmequelle: Tiegel steht nicht im Ofen", ctx)
			s["waited_s"] = float(s.get("waited_s", 0.0)) + 3.0
			if float(s["waited_s"]) > 1200.0:
				return _fail(cr, w, s, "schmilzt nicht – Wärme reicht nicht", ctx)
			return _req(cr, w, "wait", 0, null, {"duration_s": 3.0, "reason": "wartet, bis das Kupfer schmilzt"}, "wartet auf die Schmelze", ctx)
		"pour":
			var cru2 := int(s.get("obj", 0))
			var cup2 := PutIntoContainerAction.cup_of(ctx, cru2)
			if s.get("poured", false) or (cup2 != null and ConstructionSystem.contents_of(ctx, cup2.id).is_empty()):
				_done(w, s, "gegossen in Form #%d" % int(s.get("mold", 0)), ctx)
				return {"next": true}
			if cr.held_object_id != 0 and cr.held_object_id != ConstructionSystem.top_id(ctx, cru2):
				return _req(cr, w, "drop", 0, null, {"object": true}, "legt #%d ab, um zu gießen" % cr.held_object_id, ctx)
			w.current_obj = cru2
			var mp_ = ctx.position_of(int(s.get("mold", 0)))
			return _request_with_prep(cr, w, s, "pour_into_mold", cru2, {"mold": int(s.get("mold", 0))}, ctx, mp_)
		"check":
			return _check(cr, w, s, ctx)
		"mark_site":
			_done(w, s, "Baustelle #%d" % w.dest_id, ctx)
			return {"next": true}
	return _fail(cr, w, s, "unbekannter Schritt %s" % op, ctx)


## Handlung anfordern; außer Reichweite → hingehen (begrenzt), Hand belegt → ablegen.
func _request_with_prep(cr: Creature, w: WorkChain, s: Dictionary, type: String, target: int, params: Dictionary, ctx: LifeContext, near = null) -> Dictionary:
	var dry := ctx.executor.dry_run(cr.id, type, target, null, params)
	if dry.ok:
		return _req(cr, w, type, target, null, params, "%s (#%d)" % [ActionDefinition.LABELS.get(type, type), target], ctx)
	match dry.code:
		"out_of_reach":
			var p = near if near != null else ctx.position_of(target)
			if p == null:
				return _fail(cr, w, s, "Ziel #%d nicht mehr vorhanden" % target, ctx)
			return _move_near(cr, w, s, p, 0.35, ctx)
		"hands_full":
			if cr.held_object_id != 0:
				return _req(cr, w, "drop", 0, null, {"object": true}, "legt #%d ab, um die Hand frei zu haben" % cr.held_object_id, ctx)
			if cr.carried_item_id != 0:
				return _req(cr, w, "drop", 0, null, {}, "legt Nahrung ab, um die Hand frei zu haben", ctx)
		"too_hot":
			s["cool_waits"] = int(s.get("cool_waits", 0)) + 1
			if int(s["cool_waits"]) <= 20:
				return _req(cr, w, "wait", 0, null, {"duration_s": 5.0, "reason": "lässt abkühlen"}, "wartet, bis es abkühlt", ctx)
		"no_heater", "heater_full":
			return _fail(cr, w, s, "keine (freie) Wärmequelle: %s" % dry.message, ctx)
		"missing_capability":
			return _fail(cr, w, s, "Körper erlaubt es nicht: %s" % dry.message, ctx)
	if type in ["deform_material", "strike_target"] and dry.code in ["no_tool", "self_target"]:
		return _replan_tool(cr, w, s, dry.message, ctx)
	return _fail(cr, w, s, "%s: %s" % [ActionDefinition.LABELS.get(type, type), dry.message], ctx)


func _req(cr: Creature, w: WorkChain, type: String, target: int, pos, params: Dictionary, what: String, ctx: LifeContext) -> Dictionary:
	var res := ctx.executor.request(cr.id, type, target, pos, params)
	if not res["result"].ok:
		var s := w.current_step()
		return _fail(cr, w, s if not s.is_empty() else {}, "%s abgelehnt: %s" % [what, res["result"].message], ctx)
	w.pending_action = (res["action"] as GameAction).id
	return {"ok": true, "state": "arbeitet", "reason": "Kette #%d, Schritt %d/%d: %s." % [w.id, w.step_i + 1, w.steps.size(), what]}


## Hingehen: Ziel aus wechselnder Richtung anlaufen (Umplanen bei blockiertem Weg), begrenzt.
func _move_near(cr: Creature, w: WorkChain, s: Dictionary, p: Vector3, dist: float, ctx: LifeContext) -> Dictionary:
	s["moves"] = int(s.get("moves", 0)) + 1
	if int(s["moves"]) > MAX_MOVES + int(s.get("move_fail", 0)):
		return _fail(cr, w, s, "Ziel nicht erreichbar (%d Anläufe)" % int(s["moves"]), ctx)
	var away: Vector3 = cr.position - p
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.RIGHT
	var ang := float(int(s.get("move_fail", 0))) * PI * 0.5
	var dir := away.normalized().rotated(Vector3.UP, ang)
	var dest: Vector3 = p + dir * dist
	# Ankunftsradius kleiner als der Wunschabstand, sonst „kommt“ das Wesen an, ohne sich zu bewegen
	var res := ctx.executor.request(cr.id, "move_to", 0, dest, {"arrive_radius_m": clampf(dist * 0.5, 0.08, 0.3)})
	if not res["result"].ok:
		s["move_fail"] = int(s.get("move_fail", 0)) + 1
		if int(s["move_fail"]) > int(wc(ctx).get("move_retries", 2)):
			return _fail(cr, w, s, "Weg blockiert: %s" % res["result"].message, ctx)
		return {"ok": true, "state": "plant_um", "reason": "Weg blockiert – sucht anderen Zugang (%s)" % res["result"].message, "next": false}
	w.pending_action = (res["action"] as GameAction).id
	return {"ok": true, "state": "geht", "reason": "Kette #%d: geht zu %.1f/%.1f" % [w.id, dest.x, dest.z]}


## Tragen eines Stücks zu einem Ziel (zustandsbasiert): aufnehmen → hingehen → abliefern.
func _carry(cr: Creature, w: WorkChain, s: Dictionary, oid: int, dest: int, mode: String, ctx: LifeContext) -> Dictionary:
	var p: MaterialPiece = ctx.material_pieces.get(oid, null)
	if p == null and not ctx.assemblies.has(oid):
		s["skipped"] = true
		_done(w, s, "#%d existiert nicht mehr" % oid, ctx)
		return {"next": true}
	w.current_obj = oid
	# 1. bereits abgeliefert?
	if _delivered(ctx, oid, dest, mode, cr):
		if not s.get("counted", false) and mode != "bring":
			s["counted"] = true
			if not (oid in w.delivered):
				w.delivered.append(oid)
				w.moved_kg += ConstructionSystem.mass_of(ctx, oid)
		_done(w, s, "#%d %s" % [oid, MODE_LABEL.get(mode, mode)], ctx)
		return {"next": true}
	var top := ConstructionSystem.top_id(ctx, oid)
	var held := cr.held_object_id == top and top != 0
	if not held:
		if cr.held_object_id != 0:
			return _req(cr, w, "drop", 0, null, {"object": true}, "legt #%d ab, um #%d zu tragen" % [cr.held_object_id, oid], ctx)
		var dry := ctx.executor.dry_run(cr.id, "equip_tool", oid, null, {"carry": true})
		if not dry.ok:
			match dry.code:
				"out_of_reach":
					return _move_near(cr, w, s, ctx.position_of(oid), 0.35, ctx)
				"hands_full":
					if cr.carried_item_id != 0:
						return _req(cr, w, "drop", 0, null, {}, "legt Nahrung ab", ctx)
				"too_hot":
					s["cool_waits"] = int(s.get("cool_waits", 0)) + 1
					if int(s["cool_waits"]) <= 20:
						return _req(cr, w, "wait", 0, null, {"duration_s": 5.0, "reason": "lässt abkühlen"}, "wartet, bis #%d abkühlt" % oid, ctx)
			w.rejected.append({"id": oid, "reason": dry.message})
			s["skipped"] = true
			_done(w, s, "#%d bleibt liegen: %s" % [oid, dry.message], ctx)
			return {"next": true}
		return _req(cr, w, "equip_tool", oid, null, {"carry": true}, "nimmt #%d auf (%.2f kg)" % [oid, ConstructionSystem.mass_of(ctx, oid)], ctx)
	# 2. hingehen
	var dp = _dest_point(ctx, dest, mode)
	if dp == null:
		return _fail(cr, w, s, "Ziel #%d existiert nicht mehr" % dest, ctx)
	var reach := _deliver_reach(ctx, dest, mode)
	if ctx.distance_xz(cr.position, dp) > reach:
		return _move_near(cr, w, s, dp, minf(0.4, reach * 0.5), ctx)
	# 3. abliefern (die Handlung prüft Kapazität, Bauplan, Schmelzeignung)
	var type: String = {"deposit": "deposit_in_storage", "place": "place_building_part", "put_in": "put_into_container", "bring": "drop"}[mode]
	var params := {"object": true} if mode == "bring" else ({"purpose": "schmelzen"} if mode == "put_in" else {})
	var tgt := 0 if mode == "bring" else dest
	var dry2 := ctx.executor.dry_run(cr.id, type, tgt, null, params)
	if not dry2.ok and dry2.code != "out_of_reach":
		w.rejected.append({"id": oid, "reason": dry2.message})
		s["skipped"] = true
		s["status"] = "übersprungen"
		w.add_log(ctx.now(), "#%d abgewiesen: %s – wird abgelegt" % [oid, dry2.message])
		w.step_i += 1
		return _req(cr, w, "drop", 0, null, {"object": true}, "legt abgewiesenes #%d ab" % oid, ctx)
	if not dry2.ok:
		return _move_near(cr, w, s, dp, 0.3, ctx)
	return _req(cr, w, type, tgt, null, params, "%s #%d" % [MODE_LABEL.get(mode, mode), oid], ctx)


static func _delivered(ctx: LifeContext, oid: int, dest: int, mode: String, cr: Creature) -> bool:
	var p: MaterialPiece = ctx.material_pieces.get(oid, null)
	match mode:
		"deposit":
			return p != null and p.storage_id == dest
		"place":
			return p != null and p.structure_id == dest
		"put_in":
			return p != null and p.container_id == dest
		"bring":
			var po = ctx.position_of(oid)
			var pt = ctx.position_of(dest)
			return po != null and pt != null and cr.held_object_id != ConstructionSystem.top_id(ctx, oid) \
				and ctx.distance_xz(po, pt) <= TechActionUtil.reach_m(ctx) * 0.45
	return false


static func _dest_point(ctx: LifeContext, dest: int, mode: String):
	match mode:
		"deposit":
			var s: StoragePlace = ctx.storages.get(dest, null)
			return s.position if s != null else null
		"place":
			var st: Structure = ctx.structures.get(dest, null)
			if st == null:
				return null
			var i := StructureSystem.next_free_slot(st)
			return StructureSystem.slot_world(st, maxi(0, i))
	return ctx.position_of(dest)


static func _deliver_reach(ctx: LifeContext, dest: int, mode: String) -> float:
	match mode:
		"deposit":
			var s: StoragePlace = ctx.storages.get(dest, null)
			return TechActionUtil.reach_m(ctx) * 0.8 + (maxf(s.size_m.x, s.size_m.y) * 0.5 if s != null else 0.0)
		"place":
			return TechActionUtil.reach_m(ctx) * 0.8
		"bring":
			return TechActionUtil.reach_m(ctx) * 0.4
	return TechActionUtil.reach_m(ctx) * 0.8


## Stücke für das Ziel auswählen und je Stück einen Trageschritt einfügen.
func _collect(cr: Creature, w: WorkChain, s: Dictionary, ctx: LifeContext) -> Dictionary:
	var dest := int(s.get("dest", w.dest_id))
	var mode := str(s.get("mode", "deposit"))
	var cand: Array = []
	for pid in s.get("pieces", []) + w.produced:
		if not (int(pid) in cand) and not (int(pid) in w.delivered):
			cand.append(int(pid))
	var accepted: Array = []
	var kg := 0.0
	var m3 := 0.0
	var free_slots := 999
	if mode == "place" and ctx.structures.has(dest):
		var st: Structure = ctx.structures[dest]
		free_slots = st.slots.size() - st.filled()
	for pid in cand:
		var p: MaterialPiece = ctx.material_pieces.get(pid, null)
		if p == null or p.structure_id != 0 or p.assembly_id != 0:
			continue
		var why := ""
		match mode:
			"deposit":
				var sp: StoragePlace = ctx.storages.get(dest, null)
				if sp == null:
					return _fail(cr, w, s, "Lager #%d existiert nicht mehr" % dest, ctx)
				if p.storage_id == dest:
					continue
				var u := StorageSystem.used(ctx, sp)
				if float(u["kg"]) + kg + p.mass_kg > sp.capacity_kg or float(u["m3"]) + m3 + p.volume_m3() > sp.capacity_m3:
					why = "Lager #%d hätte keinen Platz mehr" % dest
			"place":
				if not ctx.structures.has(dest):
					return _fail(cr, w, s, "Baustelle #%d existiert nicht mehr" % dest, ctx)
				var chk := StructureSystem.check_part(ctx, ctx.structures[dest], pid)
				if not chk.ok:
					why = chk.message
				elif accepted.size() >= free_slots:
					why = "alle Plätze vergeben"
			"put_in":
				var cup: MaterialPiece = ctx.material_pieces.get(dest, null)
				var ms := MaterialProcessSystem.melt_support(p.material(), cup.material() if cup != null else null)
				if not ms["ok"]:
					why = str(ms["message"])
				elif cup != null and p.volume_m3() + m3 > PutIntoContainerAction.free_volume_m3(ctx, cup):
					why = "passt nicht mehr in den Tiegel"
		if why != "":
			if not _rejected_has(w, pid):
				w.rejected.append({"id": pid, "reason": why})
				w.add_log(ctx.now(), "#%d nicht genommen: %s" % [pid, why])
			continue
		accepted.append(pid)
		kg += p.mass_kg
		m3 += p.volume_m3()
	if accepted.is_empty():
		if mode == "place" and ctx.structures.has(dest) and ctx.structures[dest].filled() < ctx.structures[dest].slots.size():
			# Umplanen: weiteren Stein zerkleinern, falls bekannt und Werkzeug vorhanden
			var big := find_breakable(cr, ctx, _carry_or_slot_limit(cr, ctx, ctx.structures[dest]))
			if big != 0 and w.replans < int(wc(ctx).get("max_replans", 4)) and (w.tool_id != 0 or find_tool(cr, ctx) != 0):
				w.replans += 1
				var tl := w.tool_id if w.tool_id != 0 else find_tool(cr, ctx)
				w.tool_id = tl
				var extra := [{"op": "equip", "obj": tl, "status": "offen"}, {"op": "break", "target": big, "status": "offen"},
					{"op": "release", "status": "offen"}, {"op": "collect", "dest": dest, "mode": "place", "pieces": [], "status": "offen"}]
				s["status"] = "erledigt"
				s["note"] = "zu wenig geeignete Stücke – umgeplant: #%d zerkleinern" % big
				w.add_log(ctx.now(), s["note"])
				for j in extra.size():
					w.steps.insert(w.step_i + 1 + j, extra[j])
				w.step_i += 1
				return {"next": true}
			if w.delivered.is_empty():
				return _fail(cr, w, s, "kein geeignetes Material für die Baustelle", ctx)
		elif mode == "put_in" and w.delivered.is_empty() and ConstructionSystem.contents_of(ctx, dest).is_empty():
			return _fail(cr, w, s, "kein schmelzbares Material (abgewiesen: %s)" % _rejected_text(w), ctx)
		elif mode == "deposit" and w.delivered.is_empty() and not cand.is_empty():
			return _fail(cr, w, s, "nichts einlagerbar (%s)" % _rejected_text(w), ctx)
	for j in accepted.size():
		w.steps.insert(w.step_i + 1 + j, {"op": "carry", "obj": accepted[j], "dest": dest, "mode": mode, "status": "offen"})
	_done(w, s, "%d Stücke zum %s ausgewählt (%.2f kg)%s" % [accepted.size(), MODE_LABEL.get(mode, mode), kg,
		("; abgewiesen: " + _rejected_text(w)) if not w.rejected.is_empty() else ""], ctx)
	return {"next": true}


static func _rejected_has(w: WorkChain, pid: int) -> bool:
	for r in w.rejected:
		if int(r.get("id", 0)) == pid:
			return true
	return false


static func _rejected_text(w: WorkChain) -> String:
	var parts: Array = []
	for r in w.rejected.slice(maxi(0, w.rejected.size() - 3)):
		parts.append("#%d: %s" % [int(r["id"]), str(r["reason"])])
	return "; ".join(parts) if not parts.is_empty() else "–"


func _replan_tool(cr: Creature, w: WorkChain, s: Dictionary, why: String, ctx: LifeContext) -> Dictionary:
	if w.replans >= int(wc(ctx).get("max_replans", 4)):
		return _fail(cr, w, s, "Werkzeug fehlt (%s), keine Umplanung mehr möglich" % why, ctx)
	var ts := tool_steps(cr, ctx, not w.autonomous)
	if not ts["ok"]:
		return _fail(cr, w, s, "Werkzeug fehlt (%s); %s" % [why, ts["message"]], ctx)
	w.replans += 1
	w.tool_id = int(ts["tool"])
	w.add_log(ctx.now(), "umgeplant (%s): %s" % [why, ts["message"]])
	var ins: Array = ts["steps"]
	for j in ins.size():
		var e: Dictionary = ins[j].duplicate(true)
		e["status"] = "offen"
		w.steps.insert(w.step_i + j, e)
	return {"next": true}


## Ergebnis prüfen und Verfahrenswissen verbuchen (eigene Ausführung).
func _check(cr: Creature, w: WorkChain, s: Dictionary, ctx: LifeContext) -> Dictionary:
	var res := {"geliefert": w.delivered.size(), "masse_kg": snappedf(w.moved_kg, 0.001), "abgewiesen": w.rejected.size()}
	var ok := not w.delivered.is_empty()
	match w.goal:
		"bauen":
			if ctx.structures.has(w.dest_id):
				var ev := StructureSystem.evaluate(ctx, ctx.structures[w.dest_id])
				res["bauwerk"] = ev
				ok = int(ev["teile"]) > 0
				_learn(cr, w, "bauen:steinreihe:stone", ok, ["stone"], "Steine verbaut (%d/%d Plätze)" % [int(ev["teile"]), int(ev["plaetze"])], ctx)
		"lagern":
			if ctx.storages.has(w.dest_id):
				var u := StorageSystem.used(ctx, ctx.storages[w.dest_id])
				res["lager"] = {"stuecke": int(u["count"]), "kg": snappedf(float(u["kg"]), 0.001)}
				_learn(cr, w, "lagern:stone", ok, ["stone"], "%d Stücke eingelagert" % w.delivered.size(), ctx)
		"schmelzen":
			var mold := int(w.steps[w.steps.size() - 2].get("mold", 0)) if w.steps.size() >= 2 else 0
			var cast := ConstructionSystem.contents_of(ctx, mold) if mold != 0 else []
			ok = not cast.is_empty()
			res["guss"] = cast.map(func(p): return {"id": p.id, "kg": snappedf(p.mass_kg, 0.0001), "fluessig": snappedf(p.liquid_fraction(), 0.01)})
	w.result = res
	_done(w, s, "Ergebnis: %s" % JSON.stringify(res).left(160), ctx)
	if not ok:
		return _finish(cr, w, "fehlgeschlagen", "kein verwertbares Ergebnis%s" % ((" (abgewiesen: %s)" % _rejected_text(w)) if not w.rejected.is_empty() else ""), ctx)
	return {"next": true}


func _learn(cr: Creature, w: WorkChain, key: String, ok: bool, materials: Array, note: String, ctx: LifeContext) -> void:
	ProceduralKnowledge.record_own(ctx, cr, key, ok, materials, 0, note)
	if not (key in w.knowledge):
		w.knowledge.append(key)


func _complete(cr: Creature, w: WorkChain, ctx: LifeContext) -> Dictionary:
	return _finish(cr, w, "abgeschlossen", "%s: %d Stücke, %.2f kg abgeliefert" % [w.goal_text, w.delivered.size(), w.moved_kg], ctx)


## Rückmeldung einer beendeten Handlung (von Creature.on_action_finished).
func on_action_finished(cr: Creature, a: GameAction, ctx: LifeContext) -> void:
	var w := active(cr)
	if w == null or a.id != w.pending_action:
		return
	w.pending_action = 0
	var s := w.current_step()
	if s.is_empty():
		return
	var ok := a.status == ActionDefinition.STATUS_SUCCEEDED
	if a.type == "move_to" and not ok:
		s["move_fail"] = int(s.get("move_fail", 0)) + 1
		w.add_log(ctx.now(), "Weg gescheitert (%s): %s" % [a.result_code, a.result_message])
		if int(s["move_fail"]) > int(wc(ctx).get("move_retries", 2)):
			_fail(cr, w, s, "Weg blockiert: %s" % a.result_message, ctx)
		return
	if not ok:
		if a.result_code in ["blocked"]:
			s["move_fail"] = int(s.get("move_fail", 0)) + 1
			if int(s["move_fail"]) > int(wc(ctx).get("move_retries", 2)):
				_fail(cr, w, s, "Weg zum Arbeitsplatz blockiert: %s" % a.result_message, ctx)
			return
		if a.result_code in ["cancelled", "preempted", "interrupted", "timeout"] or a.status == ActionDefinition.STATUS_CANCELLED:
			w.add_log(ctx.now(), "Handlung %s unterbrochen: %s" % [a.type, a.result_message])
			return
		s["fails"] = int(s.get("fails", 0)) + 1
		w.add_log(ctx.now(), "%s fehlgeschlagen: %s" % [ActionDefinition.LABELS.get(a.type, a.type), a.result_message])
		if int(s["fails"]) >= 3:
			_fail(cr, w, s, "%s: %s" % [ActionDefinition.LABELS.get(a.type, a.type), a.result_message], ctx)
		return
	match a.type:
		"connect_parts":
			w.tool_id = int(a.consumed.get("assembly", 0))
			_learn(cr, w, str(a.consumed.get("key", "verbinden:lashing")), true, [], "Hammer #%d gebunden (%s)" % [w.tool_id, str(a.consumed.get("variant", ""))], ctx)
		"deform_material":
			for f in a.consumed.get("fragments", []):
				if not (int(f) in w.produced):
					w.produced.append(int(f))
			if a.consumed.get("tool_broke", false):
				w.add_log(ctx.now(), "Werkzeugverbindung gebrochen")
			if str(s.get("op", "")) == "break":
				s["rounds"] = int(s.get("rounds", 0)) + 1
			if str(s.get("op", "")) == "work_copper":
				s["worked"] = true
			var key := str(a.consumed.get("key", ""))
			if key != "":
				_learn(cr, w, key, true, [], "%d Schläge, %s" % [int(a.consumed.get("strikes", 0)), "zerbrochen" if a.consumed.get("fractured", false) else "nicht zerbrochen"], ctx)
		"pour_into_mold":
			s["poured"] = true
			var key2 := str(a.consumed.get("key", ""))
			if key2 != "":
				_learn(cr, w, key2, true, ["copper"], "gegossen", ctx)


# ── Anzeige (Spielerdiagnose; Wesen sehen nur ihr eigenes Wissen) ─────────

func status_view(cr: Creature, ctx: LifeContext) -> Dictionary:
	var w := active(cr)
	if w == null:
		var past := of_creature(cr.id)
		if past.is_empty():
			return {}
		w = past[0]
	var s := w.current_step()
	var a: GameAction = ctx.executor.running.get(cr.id, null)
	var anim: Dictionary = a.state.get("anim", {}) if a != null else {}
	var carried := 0.0
	if cr.held_object_id != 0 and cr.held_object_id != w.tool_id:
		carried = ConstructionSystem.mass_of(ctx, cr.held_object_id)
	var prog := 0.0
	if w.goal == "bauen" and ctx.structures.has(w.dest_id):
		var st: Structure = ctx.structures[w.dest_id]
		prog = float(st.filled()) / maxf(1.0, st.slots.size())
	elif not w.steps.is_empty():
		prog = float(mini(w.step_i, w.steps.size())) / float(w.steps.size())
	return {"chain": w.id, "ziel": w.goal_text, "herkunft": w.source, "autonom": w.autonomous, "status": w.status,
		"handlung": ("%s (%s)" % [ActionDefinition.LABELS.get(a.type, a.type), str(anim.get("phase", "-"))]) if a != null else "–",
		"schritt": "%d/%d %s" % [mini(w.step_i + 1, w.steps.size()), w.steps.size(), OP_LABEL.get(str(s.get("op", "")), str(s.get("op", "")))] if not s.is_empty() else "–",
		"werkzeug": w.tool_id, "zielobjekt": w.current_obj if w.current_obj != 0 else w.target_id, "bestimmung": w.dest_id,
		"getragen_kg": carried, "getragen_id": cr.held_object_id if carried > 0.0 else 0, "transportiert_kg": w.moved_kg,
		"abgeliefert": w.delivered.size(), "fortschritt": prog, "abbruchgrund": w.abort_reason, "pausegrund": w.pause_reason,
		"kontakte": int(anim.get("contacts", 0)), "pose": str(anim.get("pose", "")), "log": w.log.slice(maxi(0, w.log.size() - 6))}


# ── Modellvorschläge (Ollama): nur geprüfte Vorschläge, Start über den Entscheider ─────────

## Prüft einen vorgeschlagenen Plan {goal, steps:[{op, obj?, target?, dest?, mode?}]} gegen das Wissen
## des Wesens und die Handlungsregeln. Ergebnis: {ok, plan, errors}. Erfindet keine Mengen/IDs.
func validate_model_plan(cr: Creature, proposal: Dictionary, ctx: LifeContext) -> Dictionary:
	var errors: Array = []
	var goal := str(proposal.get("goal", ""))
	if not GOAL_LABEL.has(goal):
		errors.append("unbekanntes Ziel '%s'" % goal)
	var steps: Array = proposal.get("steps", [])
	if steps.is_empty() or steps.size() > 12:
		errors.append("Schrittzahl %d außerhalb 1–12" % steps.size())
	var known := _known(cr)
	for s in steps:
		if typeof(s) != TYPE_DICTIONARY or not (str(s.get("op", "")) in OPS):
			errors.append("unzulässiger Schritt %s" % str(s))
			continue
		for f in ["obj", "target", "dest", "head", "fiber", "heater", "mold"]:
			var id := int(s.get(f, 0))
			if id > 0 and not known.has(id) and not (cr.held_object_id != 0 and ConstructionSystem.top_id(ctx, id) == cr.held_object_id):
				errors.append("Schritt %s: #%d ist dem Wesen nicht bekannt" % [s.get("op", ""), id])
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var clean: Array = []
	for s in steps:
		var e := {}
		for f in ["op", "obj", "target", "dest", "mode", "head", "fiber", "heater", "mold"]:
			if s.has(f):
				e[f] = s[f] if f in ["op", "mode"] else int(s[f])
		clean.append(e)
	return {"ok": true, "plan": {"steps": clean, "dest": int(proposal.get("dest", 0)), "target": int(proposal.get("target", 0)),
		"message": "Modellvorschlag (%d Schritte, geprüft)" % clean.size()}, "errors": []}


## Geprüften Modellvorschlag ablegen (aus AISystem). Ausführung erst, wenn das Wesen ihn als Option wählt.
func add_proposal(cr: Creature, goal: String, p: Dictionary, source: String, explanation: String, uncertainty: float, request_id: int, ctx: LifeContext) -> Dictionary:
	if active(cr) != null:
		return {"ok": false, "message": "Wesen arbeitet bereits an einer Kette."}
	proposals[cr.id] = {"goal": goal, "plan": p.duplicate(true), "source": source, "explanation": explanation, "uncertainty": uncertainty,
		"request_id": request_id, "t": ctx.now()}
	ctx.log_event("work_proposal", [cr.id], {"goal": goal, "steps": (p.get("steps", []) as Array).size(), "source": source, "request_id": request_id})
	return {"ok": true, "as": "work_proposal", "message": "Arbeitsvorschlag (%s, %d Schritte) geprüft und als Option abgelegt: %s" % [GOAL_LABEL.get(goal, goal), (p.get("steps", []) as Array).size(), explanation]}


# ── Speichern ─────────────────────────

func to_dict() -> Dictionary:
	var arr: Array = []
	var ids := chains.keys()
	ids.sort()
	for id in ids:
		arr.append((chains[id] as WorkChain).to_dict())
	var be := {}
	for k in by_actor:
		be[str(k)] = by_actor[k]
	var le := {}
	for k in last_end_t:
		le[str(k)] = last_end_t[k]
	var ls := {}
	for k in last_site_t:
		ls[str(k)] = last_site_t[k]
	return {"chains": arr, "by_actor": be, "next_id": next_id, "last_end_t": le, "last_site_t": ls, "stats": stats.duplicate(), "pending_drops": pending_drops.duplicate(), "proposals": _proposals_dict()}


func _proposals_dict() -> Dictionary:
	var out := {}
	for k in proposals:
		out[str(k)] = (proposals[k] as Dictionary).duplicate(true)
	return out


func from_dict(d: Dictionary) -> void:
	chains.clear()
	by_actor.clear()
	last_end_t.clear()
	for cd in d.get("chains", []):
		var w := WorkChain.from_dict(cd)
		chains[w.id] = w
	for k in d.get("by_actor", {}):
		by_actor[int(k)] = int(d["by_actor"][k])
	for k in d.get("last_end_t", {}):
		last_end_t[int(k)] = float(d["last_end_t"][k])
	last_site_t.clear()
	for k in d.get("last_site_t", {}):
		last_site_t[int(k)] = float(d["last_site_t"][k])
	next_id = int(d.get("next_id", chains.size() + 1))
	pending_drops.clear()
	for x in d.get("pending_drops", []):
		pending_drops.append(int(x))
	proposals.clear()
	for k in d.get("proposals", {}):
		proposals[int(k)] = (d["proposals"][k] as Dictionary).duplicate(true)
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]


## Nach dem Laden: laufende Ketten werden fortgesetzt (jeder Schritt wird aus dem Weltzustand neu
## geprüft); die vor dem Speichern laufende Handlung wurde vom Executor abgebrochen.
func after_load(ctx: LifeContext) -> void:
	for id in chains:
		var w: WorkChain = chains[id]
		if not w.is_open():
			continue
		w.pending_action = 0
		w.resumed_after_load = true
		w.add_log(ctx.now(), "nach dem Laden fortgesetzt (Schritt %d neu geprüft)" % (w.step_i + 1))
	for k in by_actor.keys():
		if not chains.has(int(by_actor[k])) or not (chains[int(by_actor[k])] as WorkChain).is_open():
			by_actor.erase(k)


func audit(ctx: LifeContext) -> Array:
	var p: Array = []
	for aid in by_actor:
		var w: WorkChain = chains.get(int(by_actor[aid]), null)
		if w == null:
			p.append("Arbeitskette für #%d fehlt" % aid)
		elif w.actor_id != int(aid):
			p.append("Arbeitskette #%d gehört #%d, nicht #%d" % [w.id, w.actor_id, aid])
		if ctx.creature(int(aid)) == null:
			p.append("Arbeitskette #%d: Wesen #%d fehlt" % [int(by_actor[aid]), aid])
	return p
